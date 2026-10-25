// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';

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

      // 1. Fetch FULL member row with all 42 columns
      final fullData = await _supabase.from('members').select().eq('id', mId).single();

      // 2. Fetch Milestones
      final milestones = await _supabase.from('member_milestones')
          .select().eq('member_id', mId).order('completion_date');

      // 3. Fetch Unit Transfers
      final transfers = await _supabase.from('member_transfers')
          .select().eq('member_id', mId).order('transfer_date');

      // 4. Determine Attendance Health (Automation feature preserved)
      final attendance = await _supabase.from('logs_service_attendance_status')
          .select('attendance_realtime')
          .eq('member_id', mId)
          .order('report_date', ascending: false)
          .limit(4);

      if (mounted) {
        setState(() {
          _fullMemberData = fullData;
          _milestones = milestones;
          _transfers = transfers;
          _calculateAttendanceBadge(attendance as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Full Profile Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateAttendanceBadge(List attendance) {
    int absents = attendance.where((a) => a['attendance_realtime'] == "Absentee").length;
    if (attendance.isEmpty) { _attendanceHealth = "New Member"; _healthColor = Colors.blue; }
    else if (absents == 0) { _attendanceHealth = "HM"; _healthColor = Colors.green; }
    else if (absents <= 6) { _attendanceHealth = "Habitual Absentee"; _healthColor = Colors.orange; }
    else { _attendanceHealth = "LTA"; _healthColor = Colors.red; }
  }

  // ==========================================
  // CATEGORY 2: UI RENDERING
  // ==========================================

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 900;
    const sapphire = Color(0xFF0D47A1);

    List<Widget> sections = [
      _buildSection("Personal Details", [
        _infoCard("Korean Name", _fullMemberData['korean_name']),
        _infoCard("Gender", _fullMemberData['gender']),
        _infoCard("Date of Birth", _fullMemberData['dob']),
        _infoCard("Nationality", _fullMemberData['nationality']),
        _infoCard("Marital Status", _fullMemberData['marital_status']),
        // NEW: Physical Health Status (Entered Data)
        _infoCard("Physical Health", _fullMemberData['health_status']), 
      ]),
      _buildSection("Church Alignment", [
        _infoCard("Location", _fullMemberData['location']),
        _infoCard("Department", _fullMemberData['department']), // Fixed from current_dept
        _infoCard("Team", _fullMemberData['team']),             // Fixed from team_number
        _infoCard("Cell", _fullMemberData['cell_group']),       // Fixed from cell_number
        _infoCard("Duty", _fullMemberData['duty']),
        _infoCard("Appointment", _fullMemberData['appointment']),
        _infoCard("Year Joined", _fullMemberData['date_joined']),
      ]),
      _buildSection("Growth & Lineage", [
        _infoCard("Center Class", _fullMemberData['faith_in_pp']), // Used your column name
        _infoCard("Instructor", _fullMemberData['instructor_name']),
        _infoCard("Evangelist", _fullMemberData['evangelist_name']),
        _infoCard("BB Teacher", _fullMemberData['bb_teacher_name']),
        _infoCard("Guide", _fullMemberData['guide_name']),
      ]),
      _buildSection("Family & Internal", [
        _infoCard("Relatives in SCJ", _fullMemberData['relatives_in_scj']),
        _infoCard("Family Info", _fullMemberData['family_info']),
      ]),
      _buildSection("Professional & Skills", [
        _infoCard("Occupation", _fullMemberData['occupation']),
        _infoCard("Education Background", _fullMemberData['education_level']),
        _infoCard("Special Skills", _fullMemberData['special_skills']),
      ]),
      // HISTORY MODULES
      _buildHistorySection("Education & Milestones", Icons.school, _milestones.map((m) => {
        'title': m['milestone_name'],
        'subtitle': "Graduated: ${m['completion_date']}",
        'color': Colors.green[700]
      }).toList()),
      _buildHistorySection("Unit History", Icons.move_up, _transfers.map((t) => {
        'title': "Transfer Completed",
        'subtitle': "${t['old_unit']} → ${t['new_unit']} (${t['transfer_date']})",
        'color': Colors.blue[700]
      }).toList()),
      _buildSection("Contact Info", [
        _infoCard("Physical Address", _fullMemberData['physical_address']),
        _infoCard("Emergency Contact", _fullMemberData['emergency_contact']),
        _infoCard("Email", _fullMemberData['email_address']),
      ]),
    ];

    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        title: Text("Member Profile", style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold)),
        backgroundColor: AppPalette.bg(sapphire), foregroundColor: AppPalette.fg(Colors.white), elevation: 0, centerTitle: true,
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        child: Column(children: [
          _buildHeroHeader(sapphire, isDesktop),
          Padding(
            padding: const EdgeInsets.all(10),
            child: isDesktop
              ? Wrap(spacing: 15, runSpacing: 15, children: sections.map((s) => SizedBox(width: (width / 3) - 30, child: s)).toList())
              : Column(children: sections),
          ),
          const SizedBox(height: 50), 
        ]),
      ),
    );
  }

  Widget _buildHeroHeader(Color sapphire, bool isDesktop) {
    return Container(
      width: double.infinity, color: AppPalette.bg(sapphire), padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      child: Column(children: [
        CircleAvatar(radius: 40, backgroundColor: AppPalette.bg(Colors.white24), child: Icon(Icons.person, size: 40, color: AppPalette.fg(Colors.white))),
        const SizedBox(height: 15),
        Text(_fullMemberData['english_name'] ?? "No Name", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        // PERFORMANCE BADGE
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: AppPalette.bg(_healthColor), borderRadius: BorderRadius.circular(20)),
          child: Text(_attendanceHealth, style: TextStyle(color: AppPalette.fg(Colors.white), fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        Text("SCJ ID: ${_fullMemberData['scj_id'] ?? 'N/A'}", style: TextStyle(color: AppPalette.fg(Colors.white70), fontSize: 12)),
      ]),
    );
  }

  Widget _buildHistorySection(String title, IconData icon, List<Map<String, dynamic>> items) {
    return _buildSection(title, items.isEmpty 
      ? [Padding(padding: EdgeInsets.all(10), child: Text("No records found.", style: TextStyle(color: AppPalette.fg(Colors.grey), fontSize: 12)))]
      : items.map((item) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: AppPalette.fg(item['color']), size: 20),
          title: Text(item['title'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          subtitle: Text(item['subtitle'], style: const TextStyle(fontSize: 12)),
        )).toList(),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: AppPalette.fg(const Color(0xFF0D47A1)))),
        const Divider(height: 25),
        ...children,
      ]),
    );
  }

  Widget _infoCard(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(flex: 2, child: Text(label, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.blueGrey[600]), fontSize: 13))),
        Expanded(flex: 3, child: Text("${value ?? '-'}", textAlign: TextAlign.right, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.black), fontSize: 13, fontWeight: FontWeight.bold))),
      ]),
    );
  }
}