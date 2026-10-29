// ignore_for_file: curly_braces_in_flow_control_structures, use_build_context_synchronously
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';

import 'member_change_approvals_screen.dart';

/// A member's full profile (members + milestones + unit history + the
/// attendance badge).
///
/// Cell leaders and assistant cell leaders (member_change_roles) get **Edit**:
/// they propose changes to the fields in `member_editable_fields` (not the
/// church alignment, unit history, names, gender, date of birth, education
/// and milestones). The member list changes only after approval
/// (Member Bio › Member profile › Approve member profile changes).
class MemberDetailScreen extends StatefulWidget {
  final Map<String, dynamic> member;
  final String userRole;

  const MemberDetailScreen({super.key, required this.member, required this.userRole});

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic> _fullMemberData = {};
  List<dynamic> _milestones = [];
  List<dynamic> _transfers = [];
  String _attendanceHealth = "Loading..."; // Keeps the auto-calc feature separate
  Color _healthColor = Colors.grey;
  bool _isLoading = true;

  // Profile changes (15_round14.sql)
  bool _canRequest = false, _canApprove = false;
  List<Map<String, dynamic>> _editable = []; // {field, label, section}
  Map<String, dynamic>? _pending; // the member's pending proposal

  static const Color _navy = Color(0xFF0D47A1);
  static const Color _purple = Color(0xFF4A148C);

  @override
  void initState() {
    super.initState();
    _fullMemberData = widget.member;
    _loadMemberHistory();
  }

  // ==========================================
  // CATEGORY 1: DATA LOGIC
  // ==========================================

  Future<void> _loadMemberHistory() async {
    try {
      final mId = widget.member['id'];

      final r = await Future.wait<dynamic>([
        // 1. FULL member row
        _supabase.from('members').select().eq('id', mId).single(),
        // 2. Milestones
        _supabase.from('member_milestones').select().eq('member_id', mId).order('completion_date', ascending: true),
        // 3. Unit transfers
        _supabase.from('member_transfers').select().eq('member_id', mId).order('transfer_date', ascending: true),
        // 4. Attendance health (automation feature preserved)
        _supabase.from('logs_service_attendance_status').select('attendance_realtime').eq('member_id', mId).order('report_date', ascending: false).limit(4),
      ]);

      if (mounted) {
        setState(() {
          _fullMemberData = Map<String, dynamic>.from(r[0] as Map);
          _milestones = r[1] as List;
          _transfers = r[2] as List;
          _calculateAttendanceBadge(r[3] as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Full Profile Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
    _loadChangeInfo();
  }

  Future<void> _loadChangeInfo() async {
    try {
      final info = await _supabase.rpc('member_change_info', params: {'p_member': widget.member['id']});
      if (!mounted || info is! Map) return;
      setState(() {
        _canRequest = info['can_request'] == true;
        _canApprove = info['can_approve'] == true;
        _editable = List<Map<String, dynamic>>.from(((info['fields'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
        _pending = info['pending'] is Map ? Map<String, dynamic>.from(info['pending'] as Map) : null;
      });
    } catch (_) {
      // before 15_round14.sql: profile stays read-only
    }
  }

  void _calculateAttendanceBadge(List attendance) {
    int absents = attendance.where((a) => a['attendance_realtime'] == "Absentee").length;
    if (attendance.isEmpty) { _attendanceHealth = "New Member"; _healthColor = Colors.blue; }
    else if (absents == 0) { _attendanceHealth = "HM"; _healthColor = Colors.green; }
    else if (absents <= 6) { _attendanceHealth = "Habitual Absentee"; _healthColor = Colors.orange; }
    else { _attendanceHealth = "LTA"; _healthColor = Colors.red; }
  }

  String _text(dynamic v) {
    if (v == null) return '';
    if (v is List) return v.where((e) => (e ?? '').toString().trim().isNotEmpty).join(', ');
    final s = v.toString().trim();
    return s.toUpperCase() == 'N/A' ? '' : s;
  }

  // ==========================================
  // EDIT (cell leaders): propose changes for approval
  // ==========================================

  Future<void> _openEdit() async {
    final ctrls = {for (final f in _editable) f['field'].toString(): TextEditingController(text: _text(_fullMemberData[f['field']]))};
    final sections = <String, List<Map<String, dynamic>>>{};
    for (final f in _editable) {
      sections.putIfAbsent((f['section'] ?? 'Other').toString(), () => []).add(f);
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [_navy, _purple]),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Row(children: [
                const Icon(Icons.edit_note_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Edit ${_fullMemberData['english_name'] ?? 'member'}", style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                    const Text("Changes are saved after approval by your team / unit leaders.", style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ),
                IconButton(onPressed: () => Navigator.pop(ctx, false), icon: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                for (final s in sections.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Text(s.key, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(_navy))),
                  ),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final f in s.value)
                      SizedBox(
                        width: 285,
                        child: TextField(
                          controller: ctrls[f['field'].toString()],
                          maxLines: f['field'] == 'family_info' || f['field'] == 'physical_address' ? 2 : 1,
                          decoration: InputDecoration(
                            labelText: tr(f['label'].toString()),
                            helperText: f['field'] == 'phone_numbers' ? tr("Separate numbers with commas") : null,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                Text("Church alignment, unit history, names, gender, date of birth, education and milestones can't be changed here.",
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text("Send for approval"),
                  style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_purple), foregroundColor: AppPalette.fg(Colors.white)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
    if (ok != true) {
      for (final c in ctrls.values) {
        c.dispose();
      }
      return;
    }
    final changes = <String, dynamic>{};
    ctrls.forEach((k, c) {
      if (c.text.trim() != _text(_fullMemberData[k])) changes[k] = c.text.trim();
    });
    for (final c in ctrls.values) {
      c.dispose();
    }
    if (changes.isEmpty) {
      _snack("Nothing was changed.");
      return;
    }
    try {
      await _supabase.rpc('member_change_submit', params: {'p_member': widget.member['id'], 'p_changes': changes});
      _snack("Sent for approval. The profile changes once a leader approves.");
      _loadChangeInfo();
    } catch (e) {
      _snack("Couldn't send: ${e is PostgrestException ? e.message : e}", error: true);
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null, behavior: SnackBarBehavior.floating));
  }

  // ==========================================
  // CATEGORY 2: UI RENDERING
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final d = _fullMemberData;

    final List<Widget> sections = [
      _buildSection("Personal Details", Icons.badge_rounded, const Color(0xFF6A1B9A), [
        _infoCard("Korean Name", d['korean_name']),
        _infoCard("Gender", d['gender']),
        _infoCard("Date of Birth", d['dob']),
        _infoCard("Nationality", d['nationality']),
        _infoCard("Marital Status", d['marital_status']),
        _infoCard("Physical Health", d['health_status']),
      ]),
      _buildSection("Church Alignment", Icons.account_tree_rounded, _navy, [
        _infoCard("Location", d['location']),
        _infoCard("Sub-location", d['sub_location']),
        _infoCard("Department", d['department']),
        _infoCard("Team", d['team']),
        _infoCard("Cell", d['cell_group']),
        _infoCard("Duty", d['duty']),
        _infoCard("Appointment", d['appointment']),
        _infoCard("Year Joined", d['date_joined']),
      ]),
      _buildSection("Growth & Lineage", Icons.spa_rounded, const Color(0xFF2E7D32), [
        _infoCard("Center Class", d['faith_in_pp']),
        _infoCard("Instructor", d['instructor_name']),
        _infoCard("Evangelist", d['evangelist_name']),
        _infoCard("BB Teacher", d['bb_teacher_name']),
        _infoCard("Guide", d['guide_name']),
      ]),
      _buildSection("Family & Internal", Icons.family_restroom_rounded, const Color(0xFFEF6C00), [
        _infoCard("Relatives in SCJ", d['relatives_in_scj']),
        _infoCard("Family Info", d['family_info']),
      ]),
      _buildSection("Professional & Skills", Icons.work_rounded, const Color(0xFF00838F), [
        _infoCard("Occupation", d['occupation']),
        _infoCard("Education Background", d['education_level']),
        _infoCard("Special Skills", d['special_skills']),
      ]),
      // HISTORY MODULES
      _buildHistorySection("Education & Milestones", Icons.school_rounded, const Color(0xFF2E7D32), _milestones.map((m) => {
            'title': (m['milestone_name'] ?? 'Milestone').toString(),
            'subtitle': [
              if ((m['completion_date'] ?? '').toString().isNotEmpty) "Graduated: ${m['completion_date']}",
              if ((m['grade'] ?? '').toString().isNotEmpty) "Grade: ${m['grade']}",
              if ((m['notes'] ?? '').toString().isNotEmpty) m['notes'].toString(),
            ].join(' · '),
          }).toList()),
      _buildHistorySection("Unit History", Icons.move_up_rounded, _navy, _transfers.map((t) {
        String unit(String p) => [t['${p}_location'], t['${p}_sub_location'], t['${p}_dept'], t['${p}_team'], t['${p}_cell']]
            .where((x) => (x ?? '').toString().trim().isNotEmpty)
            .join(' › ');
        final from = unit('old'), to = unit('new');
        return {
          'title': "Transfer completed${(t['transfer_date'] ?? '').toString().isEmpty ? '' : ' · ${t['transfer_date']}'}",
          'subtitle': [
            "${from.isEmpty ? (t['old_unit'] ?? '—') : from} → ${to.isEmpty ? (t['new_unit'] ?? '—') : to}",
            if ((t['reason'] ?? '').toString().isNotEmpty) "Reason: ${t['reason']}",
          ].join('\n'),
        };
      }).toList()),
      _buildSection("Contact Info", Icons.contact_phone_rounded, const Color(0xFFAD1457), [
        _infoCard("Phone Numbers", d['phone_numbers']),
        _infoCard("Physical Address", d['physical_address']),
        _infoCard("Emergency Contact", d['emergency_contact']),
        _infoCard("Email", d['email_address']),
      ]),
    ];

    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF3F5FA)),
      appBar: AppBar(
        title: Text("Member Profile", style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.bold)),
        backgroundColor: AppPalette.bg(_navy),
        foregroundColor: AppPalette.fg(Colors.white),
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_canRequest && !_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _openEdit,
                icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.white),
                label: const Text("Edit", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth;
              final cols = w >= 1200 ? 4 : (w >= 900 ? 3 : (w >= 600 ? 2 : 1));
              final cardW = cols == 1 ? w - 20 : (w - 20 - (cols - 1) * 14) / cols;
              return SingleChildScrollView(
                child: Column(children: [
                  _buildHeroHeader(w >= 760),
                  if (_pending != null) _pendingBanner(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      alignment: WrapAlignment.center,
                      children: [for (final s in sections) SizedBox(width: cardW, child: s)],
                    ),
                  ),
                  const SizedBox(height: 50),
                ]),
              );
            }),
    );
  }

  Widget _pendingBanner() {
    final p = _pending!;
    final when = DateTime.tryParse((p['created_at'] ?? '').toString());
    final n = (p['changes'] as Map?)?.length ?? 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 12, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppPalette.bg(const Color(0xFFFFF8E1)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(const Color(0xFFFFB300))),
      ),
      child: Row(children: [
        Icon(Icons.hourglass_top_rounded, color: AppPalette.fg(const Color(0xFFEF6C00))),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            "$n change${n == 1 ? '' : 's'} waiting for approval${when == null ? '' : ' (sent ${DateFormat('d MMM yyyy').format(when.toLocal())})'}.",
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
        ),
        if (_canApprove)
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberChangeApprovalsScreen())).then((_) => _loadMemberHistory()),
            child: const Text("Review"),
          ),
      ]),
    );
  }

  /// The member's photo on its own full-screen page.
  void _openPhoto(String url, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(name, style: GoogleFonts.merriweather(fontSize: 15, color: Colors.white)),
            centerTitle: true,
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.network(url, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 60)),
            ),
          ),
        ),
      ),
    );
  }

  // The earlier header: photo, name, attendance badge and SCJ ID.
  Widget _buildHeroHeader(bool wide) {
    final d = _fullMemberData;
    final photo = _text(d['photograph_url']);
    final hasPhoto = photo.startsWith('http');
    final name = _text(d['english_name']).isEmpty ? "No Name" : _text(d['english_name']);
    return Container(
      width: double.infinity, color: AppPalette.bg(_navy), padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      child: Column(children: [
        GestureDetector(
          onTap: hasPhoto ? () => _openPhoto(photo, name) : null,
          child: Tooltip(
            message: hasPhoto ? "View photo" : "No photo yet",
            child: CircleAvatar(
              radius: 40,
              backgroundColor: AppPalette.bg(Colors.white24),
              backgroundImage: hasPhoto ? NetworkImage(photo) : null,
              child: hasPhoto ? null : Icon(Icons.person, size: 40, color: AppPalette.fg(Colors.white)),
            ),
          ),
        ),
        const SizedBox(height: 15),
        Text(name, textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        // PERFORMANCE BADGE
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: AppPalette.bg(_healthColor), borderRadius: BorderRadius.circular(20)),
          child: Text(_attendanceHealth, style: TextStyle(color: AppPalette.fg(Colors.white), fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        Text("SCJ ID: ${_text(d['scj_id']).isEmpty ? 'N/A' : _text(d['scj_id'])}", style: TextStyle(color: AppPalette.fg(Colors.white70), fontSize: 12)),
      ]),
    );
  }

  Widget _buildHistorySection(String title, IconData icon, Color color, List<Map<String, dynamic>> items) {
    return _buildSection(
      title,
      icon,
      color,
      items.isEmpty
          ? [Padding(padding: const EdgeInsets.all(10), child: Text("No records found.", style: TextStyle(color: AppPalette.fg(Colors.grey), fontSize: 12)))]
          : [
              for (int i = 0; i < items.length; i++)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Column(children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: AppPalette.bg(color.withValues(alpha: 0.12)), shape: BoxShape.circle),
                      child: Icon(icon, size: 15, color: AppPalette.fg(color)),
                    ),
                    if (i < items.length - 1) Container(width: 2, height: 34, color: AppPalette.line(color.withValues(alpha: 0.25))),
                  ]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12, top: 3),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(items[i]['title'].toString(), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                        if (items[i]['subtitle'].toString().isNotEmpty)
                          Text(items[i]['subtitle'].toString(), style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.blueGrey.shade700))),
                      ]),
                    ),
                  ),
                ]),
            ],
    );
  }

  Widget _buildSection(String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppPalette.line(color.withValues(alpha: 0.12))),
        // raised: the shadow sits below the card
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 14, spreadRadius: -2, offset: const Offset(0, 10)),
          BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: AppPalette.bg(color.withValues(alpha: 0.12)), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: AppPalette.fg(color)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: GoogleFonts.merriweather(fontSize: 15.5, fontWeight: FontWeight.w900, color: AppPalette.fg(color)))),
        ]),
        Divider(height: 22, color: AppPalette.line(color.withValues(alpha: 0.15))),
        ...children,
      ]),
    );
  }

  // One item per row with a visible line under it: the item in dark purple,
  // its value in blue.
  Widget _infoCard(String label, dynamic value) {
    final v = _text(value);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppPalette.line(const Color(0xFFD7DCE8)), width: 1))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 2, child: Text(label, style: GoogleFonts.merriweather(color: AppPalette.fg(_purple), fontSize: 12.5, fontWeight: FontWeight.w600))),
        Expanded(
          flex: 3,
          child: Text(v.isEmpty ? '-' : v,
              textAlign: TextAlign.right,
              style: GoogleFonts.merriweather(color: AppPalette.fg(v.isEmpty ? Colors.grey : const Color(0xFF1565C0)), fontSize: 12.5, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}
