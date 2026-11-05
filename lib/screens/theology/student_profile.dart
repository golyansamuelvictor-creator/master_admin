import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';
import '../../core/i18n.dart';
import 'center_students_tab.dart' show graduateStudent;
import 'student_duties.dart' show StudentsConfig;

const Color _kPurple = Color(0xFF4A148C);

/// Member Bio › Student profiles: every student the viewer may see
/// (center_students), searchable, each opening its profile.
class StudentDirectoryScreen extends StatefulWidget {
  const StudentDirectoryScreen({super.key});
  @override
  State<StudentDirectoryScreen> createState() => _StudentDirectoryScreenState();
}

class _StudentDirectoryScreenState extends State<StudentDirectoryScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String _q = '';
  String? _status = 'Active', _level, _center, _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db.from('center_students').select().order('student_name');
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(r);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load the students (run 23_round22.sql): ${e is PostgrestException ? e.message : e}";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = _rows.where((s) {
      if (_status != null && (s['status'] ?? 'Active') != _status) return false;
      if (_level != null && s['class_level'] != _level) return false;
      if (_center != null && s['center_place'] != _center) return false;
      return q.isEmpty || "${s['student_name']} ${s['korean_name']} ${s['center_place']} ${s['contact']} ${s['guide_name']}".toLowerCase().contains(q);
    }).toList();
    final centers = {for (final s in _rows) (s['center_place'] ?? '').toString()}.where((c) => c.isNotEmpty).toList()..sort();
    final levels = {for (final s in _rows) (s['class_level'] ?? '').toString()}.where((c) => c.isNotEmpty).toList()..sort();
    Widget pick(String all, String? v, List<String> opts, IconData i, void Function(String?) set) => PopupMenuButton<String>(
          onSelected: (x) => setState(() => set(x == '\u0000' ? null : x)),
          itemBuilder: (_) => [PopupMenuItem(value: '\u0000', child: Text(all)), for (final o in opts) PopupMenuItem(value: o, child: Text(o))],
          child: Chip(visualDensity: VisualDensity.compact, avatar: Icon(i, size: 16), label: Text(v ?? all)),
        );
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 46,
        title: Text("Student profiles", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple))),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: [
            SizedBox(
              width: 240,
              height: 36,
              child: TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: tr("Search name, center, contact"), isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 6), border: const OutlineInputBorder()),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            pick("All statuses", _status, const ['Active', 'Graduated', 'Dropped'], Icons.verified_rounded, (x) => _status = x),
            pick("All levels", _level, levels, Icons.stairs_rounded, (x) => _level = x),
            pick("All centers", _center, centers, Icons.location_city_rounded, (x) => _center = x),
            Text("${list.length}", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
                  : list.isEmpty
                      ? Center(child: Text("No students here.", style: TextStyle(color: AppPalette.fg(Colors.grey))))
                      : LayoutBuilder(builder: (context, box) {
                          final cols = box.maxWidth >= 1100 ? 3 : (box.maxWidth >= 700 ? 2 : 1);
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 6, 10, 60),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: 86, crossAxisSpacing: 10, mainAxisSpacing: 10),
                            itemCount: list.length,
                            itemBuilder: (_, i) => _StudentTile(
                              s: list[i],
                              onTap: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => StudentProfileScreen(studentId: list[i]['id'].toString())));
                                _load();
                              },
                            ),
                          );
                        }),
        ),
      ]),
    );
  }
}

class _StudentTile extends StatelessWidget {
  final Map<String, dynamic> s;
  final VoidCallback onTap;
  const _StudentTile({required this.s, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final photo = (s['photo_url'] ?? '').toString();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.13), blurRadius: 14, spreadRadius: -3, offset: const Offset(0, 7))],
      ),
      child: Material(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppPalette.bg(const Color(0xFFEDE3F8)),
                backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
                child: photo.isEmpty ? Icon(Icons.person_rounded, color: AppPalette.fg(_kPurple)) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text("${s['student_name']}", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13)),
                  Text([s['center_place'], s['class_level']].where((x) => (x ?? '').toString().isNotEmpty).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.blueGrey.shade700))),
                  Text((s['status'] ?? 'Active').toString(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(s['status'] == 'Dropped' ? Colors.red.shade700 : (s['status'] == 'Graduated' ? Colors.blue.shade700 : Colors.green.shade700)))),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppPalette.fg(_kPurple)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One student's profile: photo, details, level (promote / move back with a
/// reason), details added over time, level history, attendance and offering.
class StudentProfileScreen extends StatefulWidget {
  final String studentId;
  const StudentProfileScreen({super.key, required this.studentId});
  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  final _db = Supabase.instance.client;
  Map<String, dynamic>? _s;
  List<Map<String, dynamic>> _levels = [];
  StudentsConfig? _cfg;
  (int, int, int)? _att; // attended, absent, records (last 90 days)
  num _given = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final from = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 90)));
      final r = await Future.wait<dynamic>([
        _db.from('center_students').select().eq('id', widget.studentId).maybeSingle(),
        _db.from('center_student_levels').select().eq('student_id', widget.studentId).order('changed_at', ascending: false).then<dynamic>((v) => v, onError: (_) => []),
        StudentsConfig.load(),
        _db.from('logs_center_attendance').select('status').eq('student_id', widget.studentId).gte('report_date', from).then<dynamic>((v) => v, onError: (_) => []),
        _db.from('logs_student_offering').select('amounts').eq('student_id', widget.studentId).then<dynamic>((v) => v, onError: (_) => []),
      ]);
      final att = List<Map<String, dynamic>>.from(r[3] as List);
      final a = att.where((x) => (x['status'] ?? '').toString().toLowerCase().startsWith('attend')).length;
      num given = 0;
      for (final o in (r[4] as List)) {
        for (final v in ((o['amounts'] as Map?) ?? const {}).values) {
          given += (v as num?) ?? 0;
        }
      }
      if (!mounted) return;
      setState(() {
        _s = r[0] == null ? null : Map<String, dynamic>.from(r[0] as Map);
        _levels = List<Map<String, dynamic>>.from(r[1] as List);
        _cfg = r[2] as StudentsConfig;
        _att = (a, att.length - a, att.length);
        _given = given;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load: ${e is PostgrestException ? e.message : e}")));
    }
  }

  void _snack(String m, {bool ok = false}) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: ok ? Colors.green.shade700 : null));
  }

  Future<void> _photo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = res?.files.first;
    if (f?.bytes == null) return;
    if (f!.bytes!.length > 5 * 1024 * 1024) return _snack("The photo is over 5 MB.");
    setState(() => _busy = true);
    try {
      final ext = f.name.split('.').last.toLowerCase();
      final path = "${widget.studentId}/passport_${DateTime.now().millisecondsSinceEpoch}.$ext";
      await _db.storage.from('students').uploadBinary(path, f.bytes!, fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg', upsert: true));
      final url = _db.storage.from('students').getPublicUrl(path);
      await _db.from('center_students').update({'photo_url': url, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', widget.studentId);
      await _load();
      _snack("Passport photo saved", ok: true);
    } catch (e) {
      _snack("Couldn't save the photo (run 23_round22.sql): ${e is StorageException ? e.message : (e is PostgrestException ? e.message : e)}");
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _changeLevel(String to, {required bool back}) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(back ? "Move back to $to" : "Promote to $to"),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(back ? "Use this when the student was promoted by mistake." : "The student moves to the $to level.", style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 10),
            TextField(controller: reason, maxLines: 2, decoration: InputDecoration(labelText: tr(back ? "Reason (needed)" : "Note (optional)"), border: const OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(back ? "Move back" : "Promote")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.rpc('change_student_level', params: {'p_id': widget.studentId, 'p_to': to, 'p_reason': reason.text.trim()});
      await _load();
      _snack(back ? "Moved back to $to" : "Promoted to $to", ok: true);
    } catch (e) {
      _snack(e is PostgrestException ? e.message : "$e");
    }
  }

  Future<void> _detail([String? key]) async {
    final extra = Map<String, dynamic>.from((_s?['extra_details'] as Map?) ?? const {});
    final k = TextEditingController(text: key ?? '');
    final v = TextEditingController(text: key == null ? '' : (extra[key] ?? '').toString());
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(key == null ? "Add a detail" : "Edit detail"),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: k, decoration: InputDecoration(labelText: tr("Detail (e.g. Next of kin, Baptism date)"), border: const OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: v, maxLines: 3, decoration: InputDecoration(labelText: tr("Value"), border: const OutlineInputBorder())),
          ]),
        ),
        actions: [
          if (key != null) TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: Text("Remove", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text("Save")),
        ],
      ),
    );
    if (res == null) return;
    if (key != null) extra.remove(key);
    if (res == 'save' && k.text.trim().isNotEmpty) extra[k.text.trim()] = v.text.trim();
    try {
      await _db.from('center_students').update({'extra_details': extra, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', widget.studentId);
      await _load();
    } catch (e) {
      _snack("Couldn't save: ${e is PostgrestException ? e.message : e}");
    }
  }

  Widget _section(String title, IconData icon, List<Widget> children, {Widget? trailing}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.10), blurRadius: 14, spreadRadius: -3, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: AppPalette.fg(_kPurple)),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppPalette.fg(_kPurple)))),
            if (trailing != null) trailing,
          ]),
          const Divider(height: 14),
          ...children,
        ]),
      );

  Widget _kv(String k, dynamic v) => (v ?? '').toString().trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 150, child: Text(k, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.blueGrey.shade600)))),
            Expanded(child: SelectableText(v.toString(), style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.w600))),
          ]),
        );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final cfg = _cfg;
    if (s == null || cfg == null) {
      return Scaffold(appBar: AppBar(toolbarHeight: 46), body: const Center(child: CircularProgressIndicator()));
    }
    final canEdit = cfg.canEnter;
    final levels = cfg.levels;
    final i = levels.indexOf((s['class_level'] ?? levels.first).toString());
    final next = i >= 0 && i < levels.length - 1 ? levels[i + 1] : null;
    final prev = i > 0 ? levels[i - 1] : null;
    final last = i == levels.length - 1;
    final photo = (s['photo_url'] ?? '').toString();
    final extra = Map<String, dynamic>.from((s['extra_details'] as Map?) ?? const {});
    final active = (s['status'] ?? 'Active') == 'Active';
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 46,
        title: Text("Student profile", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple))),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.all(12), children: [
            // header
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppPalette.solid(_kPurple), AppPalette.solid(const Color(0xFF7B4FC0))]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.25), blurRadius: 18, spreadRadius: -4, offset: const Offset(0, 10))],
              ),
              child: Row(children: [
                Stack(children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: Colors.white24,
                    backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
                    child: photo.isEmpty ? const Icon(Icons.person_rounded, color: Colors.white, size: 40) : null,
                  ),
                  if (canEdit)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _busy ? null : _photo,
                          child: Padding(padding: const EdgeInsets.all(5), child: Icon(Icons.photo_camera_rounded, size: 16, color: AppPalette.fg(_kPurple))),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("${s['student_name']}", style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                    if ((s['korean_name'] ?? '').toString().isNotEmpty) Text("${s['korean_name']}", style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final t in [s['center_place'], s['class_level'], s['status'] ?? 'Active'])
                        if ((t ?? '').toString().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                            child: Text(t.toString(), style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                    ]),
                    if (photo.isEmpty && canEdit)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text("Add the passport photo (needed to leave the first level)", style: GoogleFonts.merriweather(fontSize: 11, color: Colors.amberAccent)),
                      ),
                  ]),
                ),
              ]),
            ),
            if (canEdit && active)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                  if (next != null)
                    FilledButton.icon(onPressed: () => _changeLevel(next, back: false), icon: const Icon(Icons.arrow_upward_rounded, size: 18), label: Text("Promote to $next")),
                  if (prev != null)
                    OutlinedButton.icon(onPressed: () => _changeLevel(prev, back: true), icon: const Icon(Icons.undo_rounded, size: 18), label: Text("Move back to $prev")),
                  if (last && s['member_id'] == null)
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        if (await graduateStudent(context, s)) _load();
                      },
                      icon: const Icon(Icons.school_rounded, size: 18),
                      label: const Text("Enrol in church (graduate)"),
                    ),
                ]),
              ),
            if (_att != null)
              _section("Last 90 days", Icons.insights_rounded, [
                Wrap(spacing: 10, runSpacing: 8, children: [
                  _stat("Attended", "${_att!.$1}", Colors.green.shade700),
                  _stat("Absent", "${_att!.$2}", Colors.red.shade700),
                  _stat("Attendance", _att!.$3 == 0 ? "–" : "${(_att!.$1 * 100 / _att!.$3).toStringAsFixed(0)}%", _kPurple),
                  _stat("Offering (all time)", NumberFormat('#,##0').format(_given), Colors.indigo),
                ]),
              ]),
            _section("Center", Icons.location_city_rounded, [
              _kv("Center", s['center_place']),
              _kv("Center location", [s['center_location'], s['center_sub_location']].where((x) => (x ?? '').toString().isNotEmpty).join(' › ')),
              _kv("Center code", s['center_code']),
              _kv("Instructor", s['center_instructor']),
              _kv("Class level", s['class_level']),
              _kv("Opening month", s['month']),
              _kv("Started", s['start_date']),
              _kv("Graduated", s['graduated_on']),
            ]),
            _section("Personal details", Icons.badge_rounded, [
              _kv("Gender", s['gender']),
              _kv("Date of birth", s['dob']),
              _kv("Contact", s['contact']),
              _kv("Email", s['email']),
              _kv("Nationality", s['nationality']),
              _kv("Marital status", s['marital_status']),
              _kv("Job", s['job']),
              _kv("Church", s['church']),
              _kv("Denomination", s['denomination']),
              _kv("Years of faith", s['years_of_faith']),
              _kv("Languages", [s['language_main'], s['language_secondary']].where((x) => (x ?? '').toString().isNotEmpty).join(', ')),
              _kv("Address", [s['street'], s['city'], s['country']].where((x) => (x ?? '').toString().isNotEmpty).join(', ')),
            ]),
            _section("Guide and teacher", Icons.people_alt_rounded, [
              _kv("Guide", [s['guide_name'], s['guide_korean_name']].where((x) => (x ?? '').toString().isNotEmpty).join(' · ')),
              _kv("Guide's unit", [s['guide_location'], s['guide_sub_location'], s['guide_dept'], s['guide_team'], s['guide_cell']].where((x) => (x ?? '').toString().isNotEmpty).join(' › ')),
              _kv("BB teacher", [s['teacher_name'], s['teacher_korean_name']].where((x) => (x ?? '').toString().isNotEmpty).join(' · ')),
              _kv("Evangelist", s['evangelist_name']),
            ]),
            _section(
              "More details",
              Icons.post_add_rounded,
              [
                if (extra.isEmpty) Text("Details added later (next of kin, documents …) appear here.", style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade600))),
                for (final e in extra.entries)
                  InkWell(onTap: canEdit ? () => _detail(e.key) : null, child: _kv(e.key, e.value)),
              ],
              trailing: canEdit ? TextButton.icon(onPressed: () => _detail(), icon: const Icon(Icons.add_rounded, size: 18), label: const Text("Add")) : null,
            ),
            _section("Level history", Icons.timeline_rounded, [
              if (_levels.isEmpty) Text("No level changes yet.", style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade600))),
              for (final l in _levels)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    (l['reason'] ?? '').toString().isNotEmpty ? Icons.undo_rounded : Icons.arrow_upward_rounded,
                    color: AppPalette.fg(_kPurple),
                    size: 18,
                  ),
                  title: Text("${l['from_level'] ?? '—'} → ${l['to_level']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text([
                    DateFormat('d MMM yyyy').format(DateTime.parse(l['changed_at'].toString()).toLocal()),
                    if ((l['reason'] ?? '').toString().isNotEmpty) l['reason'].toString(),
                  ].join(' · ')),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color c) => Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppPalette.bg(c.withValues(alpha: 0.08)), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: AppPalette.fg(c))),
          Text(label, style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.blueGrey.shade700))),
        ]),
      );
}
