// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/compliance_logic.dart';
import '../../core/export_logic.dart';
import 'package:master_admin/core/app_palette.dart';

class DutyStat {
  final String dutyName;
  final String tableName;
  final IconData icon;
  final Color color;
  final double currentRate;
  final double previousRate;
  final int currentCount;
  final int previousCount;

  DutyStat({
    required this.dutyName,
    required this.tableName,
    required this.icon,
    required this.color,
    required this.currentRate,
    required this.previousRate,
    required this.currentCount,
    required this.previousCount,
  });

  double get diff => currentRate - previousRate;
  bool get isPositive => diff >= 0;
}

class MonthlyExecutiveReport extends StatefulWidget {
  final String? userRole;
  final String? userUnit;

  const MonthlyExecutiveReport({
    super.key,
    this.userRole,
    this.userUnit,
  });

  @override
  State<MonthlyExecutiveReport> createState() => _MonthlyExecutiveReportState();
}

class _MonthlyExecutiveReportState extends State<MonthlyExecutiveReport> {
  final _supabase = Supabase.instance.client;
  final Color pPurple = const Color(0xFF3B0764);
  bool _isLoading = true;

  // User jurisdiction
  String _activeRole = 'church_head_instructor';
  String _activeUnit = 'Church executive';
  String _userLoc = "";
  String _userSub = "";
  String _userDept = "";
  String _userTeam = "";
  String _userCell = "";

  // Report period selection
  final List<String> _periodOptions = [
    'Weekly',
    'Monthly',
    'Quarterly',
    'Half year',
    'Yearly',
    'Custom period',
  ];
  String _selectedPeriod = 'Monthly';
  DateTimeRange? _customRange;
  late DateTime _curStart, _curEnd;
  late DateTime _prevStart, _prevEnd;

  // Accountability drilldown level
  String _drilldownLevel = 'Team';
  final List<String> _drillLevels = ['Location', 'Sub location', 'Department', 'Team', 'Cell'];

  // Aggregated stats
  int totalSaints = 0;
  int newConverts = 0;
  int dropouts = 0;
  int successfulRecoveries = 0;
  int netGrowth = 0;

  double attendanceCompliance = 0.0;
  double churchAvgAttendance = 0.0;
  List<String> missingUnits = [];
  List<dynamic> _logs = []; // Populated for excel export
  Map<String, dynamic> _managerInsights = {};
  List<DutyStat> _dutyStats = [];

  bool get _isChurchWideScope {
    String r = _activeRole.toLowerCase();
    return r == 'admin' ||
        r.startsWith('church_') ||
        r.startsWith('korean_worker_') ||
        r.contains('_dept_');
  }

  @override
  void initState() {
    super.initState();
    _calculatePeriods();
    _identifyAndLoad();
  }

  void _calculatePeriods() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Weekly':
        _curStart = now.subtract(const Duration(days: 7));
        _curEnd = now;
        _prevStart = _curStart.subtract(const Duration(days: 7));
        _prevEnd = _curStart.subtract(const Duration(days: 1));
        break;
      case 'Monthly':
        _curStart = DateTime(now.year, now.month, 1);
        _curEnd = now;
        _prevStart = DateTime(now.year, now.month - 1, 1);
        _prevEnd = DateTime(now.year, now.month, 0);
        break;
      case 'Quarterly':
        int q = ((now.month - 1) ~/ 3) * 3 + 1;
        _curStart = DateTime(now.year, q, 1);
        _curEnd = now;
        _prevStart = DateTime(now.year, q - 3, 1);
        _prevEnd = DateTime(now.year, q, 0);
        break;
      case 'Half year':
        int h = now.month <= 6 ? 1 : 7;
        _curStart = DateTime(now.year, h, 1);
        _curEnd = now;
        _prevStart = h == 1 ? DateTime(now.year - 1, 7, 1) : DateTime(now.year, 1, 1);
        _prevEnd = DateTime(_curStart.year, _curStart.month, 0);
        break;
      case 'Yearly':
        _curStart = DateTime(now.year, 1, 1);
        _curEnd = now;
        _prevStart = DateTime(now.year - 1, 1, 1);
        _prevEnd = DateTime(now.year - 1, 12, 31);
        break;
      case 'Custom period':
        if (_customRange != null) {
          _curStart = _customRange!.start;
          _curEnd = _customRange!.end;
          final duration = _curEnd.difference(_curStart);
          _prevStart = _curStart.subtract(duration);
          _prevEnd = _curStart.subtract(const Duration(days: 1));
        } else {
          _curStart = DateTime(now.year, now.month, 1);
          _curEnd = now;
          _prevStart = DateTime(now.year, now.month - 1, 1);
          _prevEnd = DateTime(now.year, now.month, 0);
        }
        break;
    }
  }

  Future<void> _identifyAndLoad() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final profile = await _supabase.from('profiles').select().eq('id', user.id).maybeSingle();
        if (profile != null && mounted) {
          _activeRole = widget.userRole ?? profile['role'] ?? 'church_head_instructor';
          _userLoc = profile['location'] ?? "";
          _userSub = profile['sub_location'] ?? "";
          _userDept = profile['department'] ?? "";
          _userTeam = profile['team'] ?? "";
          _userCell = profile['cell_group'] ?? "";
          _activeUnit = widget.userUnit ?? _resolveUnitName();
          _setDefaultDrilldown();
        }
      }
    } catch (e) {
      debugPrint("Identify error: $e");
    }
    await _loadReportData();
  }

  void _setDefaultDrilldown() {
    String r = _activeRole.toLowerCase();
    if (_isChurchWideScope || r.contains('loc_')) _drilldownLevel = 'Sub location';
    else if (r.contains('sub_loc')) _drilldownLevel = 'Department';
    else if (r.contains('dept')) _drilldownLevel = 'Team';
    else _drilldownLevel = 'Cell';
  }

  String _resolveUnitName() {
    String r = _activeRole.toLowerCase();
    if (_isChurchWideScope) return "Church executive";
    if (r.contains('cell')) return _userCell.isNotEmpty ? _userCell : "Cell";
    if (r.contains('team')) return _userTeam.isNotEmpty ? _userTeam : "Team";
    if (r.contains('dept')) return _userDept.isNotEmpty ? _userDept : "Department";
    if (r.contains('sub_loc')) return _userSub.isNotEmpty ? _userSub : "Sub location";
    if (r.contains('loc')) return _userLoc.isNotEmpty ? _userLoc : "Location";
    return "Church admin";
  }

  Future<void> _loadReportData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final curStartStr = DateFormat('yyyy-MM-dd').format(_curStart);
      final curEndStr = DateFormat('yyyy-MM-dd').format(_curEnd);
      final prevStartStr = DateFormat('yyyy-MM-dd').format(_prevStart);
      final prevEndStr = DateFormat('yyyy-MM-dd').format(_prevEnd);

      // 1. Total saints in unit
      var curMembers = _supabase.from('members').select('id');
      _applyScope(curMembers);
      final mRes = await curMembers;
      totalSaints = (mRes as List).length;

      // 2. Growth metrics
      var newQ = _supabase.from('members').select('id').gte('created_at', curStartStr).lte('created_at', curEndStr);
      _applyScope(newQ);
      final nRes = await newQ;
      newConverts = (nRes as List).length;

      final dropRes = await _supabase.from('member_lifecycle').select('id').eq('status_type', 'Dropout').gte('event_date', curStartStr).lte('event_date', curEndStr);
      dropouts = (dropRes as List).length;
      netGrowth = newConverts - dropouts;

      final recRes = await _supabase.from('member_recovery_logs').select('id').eq('outcome', 'Recovered').gte('contact_date', curStartStr).lte('contact_date', curEndStr);
      successfulRecoveries = (recRes as List).length;

      // 3. Compliance calculation
      String unitLvl = _drilldownLevel.contains('Cell') ? 'Cell' : 'Team';
      missingUnits = await ComplianceLogic.getMissingReports(
        logTable: 'logs_service_attendance_status',
        unitLevel: unitLvl,
        date: _curStart,
      );
      attendanceCompliance = await ComplianceLogic.calculateComplianceRate(
        logTable: 'logs_service_attendance_status',
        unitLevel: unitLvl,
        date: _curStart,
      );

      // 4. Populate _logs with full relation for excel export
      var attQuery = _supabase.from('logs_service_attendance_status')
          .select('*, members!inner(*)')
          .gte('report_date', curStartStr)
          .lte('report_date', curEndStr);
      _applyScopedRelation(attQuery);
      final attLogs = await attQuery;
      _logs = attLogs as List;

      int presentCount = _logs.where((l) {
        String p = (l['attendance_realtime'] ?? '').toString();
        return p.contains('In-person') || p.contains('On-line') || p.contains('Live');
      }).length;
      churchAvgAttendance = totalSaints > 0 ? (presentCount / totalSaints) * 100 : 0.0;

      // 5. Multi-duty historical tracking
      List<DutyStat> tempStats = [];

      final prevAtt = await _fetchDutyRate('logs_service_attendance_status', prevStartStr, prevEndStr, isAttendance: true);
      tempStats.add(DutyStat(
        dutyName: "Service attendance status",
        tableName: "logs_service_attendance_status",
        icon: Icons.groups_rounded,
        color: Colors.blue[800]!,
        currentRate: churchAvgAttendance,
        previousRate: prevAtt['rate'],
        currentCount: presentCount,
        previousCount: prevAtt['count'],
      ));

      final curCell = await _fetchDutyRate('logs_cell_service', curStartStr, curEndStr);
      final prevCell = await _fetchDutyRate('logs_cell_service', prevStartStr, prevEndStr);
      tempStats.add(DutyStat(
        dutyName: "Cell group service",
        tableName: "logs_cell_service",
        icon: Icons.meeting_room_rounded,
        color: Colors.teal[800]!,
        currentRate: curCell['rate'],
        previousRate: prevCell['rate'],
        currentCount: curCell['count'],
        previousCount: prevCell['count'],
      ));

      final curVis = await _fetchDutyRate('logs_visitations', curStartStr, curEndStr);
      final prevVis = await _fetchDutyRate('logs_visitations', prevStartStr, prevEndStr);
      tempStats.add(DutyStat(
        dutyName: "Visitations and counselling",
        tableName: "logs_visitations",
        icon: Icons.support_agent_rounded,
        color: Colors.orange[800]!,
        currentRate: curVis['rate'],
        previousRate: prevVis['rate'],
        currentCount: curVis['count'],
        previousCount: prevVis['count'],
      ));

      final curEvang = await _fetchDutyRate('logs_evangelism', curStartStr, curEndStr);
      final prevEvang = await _fetchDutyRate('logs_evangelism', prevStartStr, prevEndStr);
      tempStats.add(DutyStat(
        dutyName: "Evangelism part",
        tableName: "logs_evangelism",
        icon: Icons.campaign_rounded,
        color: Colors.purple[800]!,
        currentRate: curEvang['rate'],
        previousRate: prevEvang['rate'],
        currentCount: curEvang['count'],
        previousCount: prevEvang['count'],
      ));

      final curAllEdu = await _fetchDutyRate('logs_all_saints_education', curStartStr, curEndStr);
      final prevAllEdu = await _fetchDutyRate('logs_all_saints_education', prevStartStr, prevEndStr);
      tempStats.add(DutyStat(
        dutyName: "All saints education",
        tableName: "logs_all_saints_education",
        icon: Icons.school_rounded,
        color: Colors.cyan[800]!,
        currentRate: curAllEdu['rate'],
        previousRate: prevAllEdu['rate'],
        currentCount: curAllEdu['count'],
        previousCount: prevAllEdu['count'],
      ));

      final curWEdu = await _fetchDutyRate('logs_workers_education', curStartStr, curEndStr);
      final prevWEdu = await _fetchDutyRate('logs_workers_education', prevStartStr, prevEndStr);
      tempStats.add(DutyStat(
        dutyName: "Workers education",
        tableName: "logs_workers_education",
        icon: Icons.menu_book_rounded,
        color: Colors.green[800]!,
        currentRate: curWEdu['rate'],
        previousRate: prevWEdu['rate'],
        currentCount: curWEdu['count'],
        previousCount: prevWEdu['count'],
      ));

      final curPart = await _fetchDutyRate('logs_workers_participation', curStartStr, curEndStr);
      final prevPart = await _fetchDutyRate('logs_workers_participation', prevStartStr, prevEndStr);
      tempStats.add(DutyStat(
        dutyName: "Workers daily participation",
        tableName: "logs_workers_participation",
        icon: Icons.assignment_turned_in_rounded,
        color: Colors.deepOrange[800]!,
        currentRate: curPart['rate'],
        previousRate: prevPart['rate'],
        currentCount: curPart['count'],
        previousCount: prevPart['count'],
      ));

      final curOff = await _fetchDutyRate('logs_offering', curStartStr, curEndStr);
      final prevOff = await _fetchDutyRate('logs_offering', prevStartStr, prevEndStr);
      tempStats.add(DutyStat(
        dutyName: "Offering status",
        tableName: "logs_offering",
        icon: Icons.volunteer_activism_rounded,
        color: Colors.indigo[800]!,
        currentRate: curOff['rate'],
        previousRate: prevOff['rate'],
        currentCount: curOff['count'],
        previousCount: prevOff['count'],
      ));

      _dutyStats = _filterDutiesByRole(tempStats);

      // 6. Managerial insights
      final insights = await _supabase.from('manager_insights')
          .select()
          .eq('duty_name', 'Monthly Executive Summary')
          .gte('period_start', curStartStr)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      _managerInsights = insights ?? {};

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("Report aggregate error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _fetchDutyRate(String table, String start, String end, {bool isAttendance = false}) async {
    try {
      var query = _supabase.from(table).select('*, members!inner(*)').gte('report_date', start).lte('report_date', end);
      _applyScopedRelation(query);
      final res = await query;
      int count = (res as List).length;
      if (count == 0) return {'rate': 0.0, 'count': 0};

      if (isAttendance) {
        int present = (res).where((l) {
          String s = (l['attendance_realtime'] ?? '').toString();
          return s.contains('In-person') || s.contains('On-line') || s.contains('Live');
        }).length;
        double rate = totalSaints > 0 ? (present / totalSaints) * 100 : 0.0;
        return {'rate': rate, 'count': present};
      } else {
        int positive = (res).where((l) {
          String s = (l['status_detail'] ?? l['attendance_status'] ?? '').toString();
          return !s.toLowerCase().contains('absent') && !s.toLowerCase().contains('failed');
        }).length;
        double rate = count > 0 ? (positive / count) * 100 : 80.0;
        return {'rate': rate, 'count': count};
      }
    } catch (e) {
      return {'rate': 0.0, 'count': 0};
    }
  }

  List<DutyStat> _filterDutiesByRole(List<DutyStat> all) {
    String r = _activeRole.toLowerCase();
    if (_isChurchWideScope || r.contains('internal_affairs') || r == 'admin') return all;
    if (r.contains('edu_')) return all.where((d) => d.dutyName.contains('education')).toList();
    if (r.contains('evang_')) return all.where((d) => d.dutyName.contains('Evangelism')).toList();
    if (r.contains('fin_') || r.contains('treasurer')) return all.where((d) => d.dutyName.contains('Offering')).toList();
    return all;
  }

  void _applyScope(PostgrestFilterBuilder q) {
    if (_isChurchWideScope) return;
    String r = _activeRole.toLowerCase();
    if (r.contains('cell') && _userCell.isNotEmpty) q.eq('cell_group', _userCell);
    else if (r.contains('team') && _userTeam.isNotEmpty) q.eq('team', _userTeam);
    else if (r.contains('dept') && _userDept.isNotEmpty) q.eq('department', _userDept);
    else if (r.contains('sub_loc') && _userSub.isNotEmpty) q.eq('sub_location', _userSub);
    else if (r.contains('loc') && _userLoc.isNotEmpty) q.eq('location', _userLoc);
  }

  void _applyScopedRelation(PostgrestFilterBuilder q) {
    if (_isChurchWideScope) return;
    String r = _activeRole.toLowerCase();
    if (r.contains('cell') && _userCell.isNotEmpty) q.eq('members.cell_group', _userCell);
    else if (r.contains('team') && _userTeam.isNotEmpty) q.eq('members.team', _userTeam);
    else if (r.contains('dept') && _userDept.isNotEmpty) q.eq('members.department', _userDept);
    else if (r.contains('sub_loc') && _userSub.isNotEmpty) q.eq('members.sub_location', _userSub);
    else if (r.contains('loc') && _userLoc.isNotEmpty) q.eq('members.location', _userLoc);
  }

  String _formatRole(String r) {
    return r.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? "" : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  // ==========================================
  // UI LAYOUT
  // ==========================================

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 900;
    double sidePadding = isDesktop ? 24.0 : 12.0;

    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppPalette.fg(Color(0xFF3B0764))),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Executive performance report",
          style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple), fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B0764)))
          : RefreshIndicator(
              onRefresh: _loadReportData,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: sidePadding, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Toolbar
                    _buildTopToolbar(),
                    const SizedBox(height: 12),

                    // Growth performance card
                    _buildGrowthCard(),
                    const SizedBox(height: 14),

                    // KPI Grid (Height reduced by 1/3)
                    _buildKPIGrid(),
                    const SizedBox(height: 14),

                    // Operational duties performance
                    _sectionTitle("Operational duties performance and trends"),
                    const SizedBox(height: 8),
                    _buildDutyGrid(isDesktop),
                    const SizedBox(height: 14),

                    // Accountability drilldown
                    _sectionTitle("Reporting compliance and unit accountability"),
                    const SizedBox(height: 8),
                    _buildAccountabilityDrilldownCard(),
                    const SizedBox(height: 14),

                    // Managerial insights
                    _sectionTitle("Managerial insights and recommendations"),
                    const SizedBox(height: 8),
                    _build14PointCard(1, "Executive summary", _managerInsights['observation'] ?? "Performance tracking reflects regular attendance and steady submissions for the active window."),
                    _build14PointCard(11, "Problem areas and root causes", _managerInsights['root_cause'] ?? "No persistent operational failures flagged for this evaluation period."),
                    _build14PointCard(13, "Recommended leadership actions", _managerInsights['recommended_action'] ?? "Focus pastoral follow-up on flagged missing units and strengthen weekday education."),
                    const SizedBox(height: 35),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTopToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.18))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 18, color: AppPalette.fg(pPurple)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${_formatRole(_activeRole)} • $_activeUnit",
                    style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[900])),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppPalette.bg(const Color(0xFFF3E5F5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedPeriod,
                isDense: true,
                style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)),
                items: _periodOptions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  if (v == 'Custom period') {
                    final p = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime.now());
                    if (p != null) {
                      setState(() { _selectedPeriod = v; _customRange = p; _calculatePeriods(); });
                      _loadReportData();
                    }
                  } else {
                    setState(() { _selectedPeriod = v; _calculatePeriods(); });
                    _loadReportData();
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),

          Row(
            children: [
              IconButton(
                icon: Icon(Icons.picture_as_pdf_rounded, color: AppPalette.fg(Colors.red), size: 20),
                tooltip: "Download PDF",
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                onPressed: () => ExportLogic.generateExecutivePDF(
                  month: "${DateFormat('dd MMM').format(_curStart)} - ${DateFormat('dd MMM yyyy').format(_curEnd)}",
                  growth: netGrowth,
                  attendance: churchAvgAttendance,
                  missingUnits: missingUnits,
                ),
              ),
              IconButton(
                icon: Icon(Icons.table_view_rounded, color: AppPalette.fg(Colors.green), size: 20),
                tooltip: "Export Excel",
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                onPressed: () => ExportLogic.exportToExcel(_logs, "Monthly_Report_${DateFormat('yyyy_MM_dd').format(_curStart)}"),
              ),
              IconButton(
                icon: Icon(Icons.print_rounded, color: AppPalette.fg(Colors.blueGrey), size: 20),
                tooltip: "Print report",
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthCard() {
    bool up = netGrowth >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppPalette.solid(pPurple), AppPalette.solid(const Color(0xFF1E1B4B))], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: pPurple.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Total saint growth and stability", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white70), fontSize: 13, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppPalette.bg(up ? Colors.green.withValues(alpha: 0.25) : Colors.red.withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(6)),
                child: Text("${up ? '+' : ''}$netGrowth saints", style: GoogleFonts.merriweather(color: AppPalette.fg(up ? Colors.greenAccent : Colors.redAccent), fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text("$totalSaints", style: GoogleFonts.merriweather(fontSize: 30, fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.white))),
          Text("Active registered members in assigned jurisdiction", style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.white60))),
          Divider(color: AppPalette.bg(Colors.white24), height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _metricCol("New converts", "+$newConverts", Colors.greenAccent),
              _metricCol("Dropouts", "-$dropouts", Colors.redAccent),
              _metricCol("Recoveries", "$successfulRecoveries", Colors.amberAccent),
              _metricCol("Avg attendance", "${churchAvgAttendance.toStringAsFixed(1)}%", Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCol(String l, String v, Color c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(v, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.w900, color: AppPalette.fg(c))),
      Text(l, style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.white60))),
    ],
  );

  // 3. KPI GRID REDUCED IN HEIGHT BY 1/3 (childAspectRatio adjusted to 2.7)
  Widget _buildKPIGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.7, // Height squeezed by 33%
      children: [
        _kpiCard("Reporting compliance", "${attendanceCompliance.toStringAsFixed(1)}%", Icons.assignment_turned_in, Colors.blue[800]!),
        _kpiCard("Average attendance", "${churchAvgAttendance.toStringAsFixed(1)}%", Icons.people_alt, Colors.green[800]!),
        _kpiCard("Recovery results", "$successfulRecoveries recovered", Icons.refresh, Colors.orange[800]!),
        _kpiCard("Graduation milestones", "Active", Icons.school, Colors.teal[800]!),
      ],
    );
  }

  Widget _kpiCard(String t, String v, IconData i, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), // Squeezed padding
    decoration: BoxDecoration(
      color: AppPalette.bg(Colors.white),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.16))),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4)],
    ),
    child: Row(
      children: [
        Icon(i, color: AppPalette.fg(c), size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(v, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.w900, color: AppPalette.fg(c))),
              Text(t, style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey[700]), fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildDutyGrid(bool isDesktop) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _dutyStats.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 4 : 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: isDesktop ? 1.8 : 1.35,
      ),
      itemBuilder: (context, i) {
        final d = _dutyStats[i];
        bool up = d.isPositive;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppPalette.bg(Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.16))),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(d.icon, color: AppPalette.fg(d.color), size: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppPalette.bg(up ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1)), borderRadius: BorderRadius.circular(6)),
                    child: Text("${up ? '+' : ''}${d.diff.toStringAsFixed(1)}%", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(up ? Colors.green[800] : Colors.red[800]))),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.dutyName, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[900])), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text("${d.currentRate.toStringAsFixed(1)}%", style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: AppPalette.fg(d.color))),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Prior: ${d.previousRate.toStringAsFixed(1)}%", style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey[600]))),
                  Text("${d.currentCount} logs", style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey[600]), fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccountabilityDrilldownCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.2))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Scale down jurisdiction level:", style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[800]))),
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF3E5F5)), borderRadius: BorderRadius.circular(6)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _drilldownLevel,
                    isDense: true,
                    style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)),
                    items: _drillLevels.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _drilldownLevel = v);
                        _loadReportData();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          Text(
            missingUnits.isEmpty ? "All $_drilldownLevel units submitted their duties successfully." : "${missingUnits.length} $_drilldownLevel units pending submission:",
            style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.fg(missingUnits.isEmpty ? Colors.green[800] : Colors.red[900])),
          ),
          const SizedBox(height: 8),
          if (missingUnits.isNotEmpty)
            SizedBox(
              height: 120,
              child: ListView.builder(
                itemCount: missingUnits.length,
                itemBuilder: (c, i) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppPalette.bg(Colors.red.withValues(alpha: 0.04)), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppPalette.line(Colors.red.withValues(alpha: 0.15)))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(missingUnits[i], style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)),
                      Text("Pending duty report", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.red[800]), fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _build14PointCard(int point, String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.16))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 11, backgroundColor: AppPalette.bg(pPurple.withValues(alpha: 0.1)), child: Text("$point", style: TextStyle(color: AppPalette.fg(pPurple), fontSize: 12, fontWeight: FontWeight.bold))),
              const SizedBox(width: 8),
              Text(title, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[900]))),
            ],
          ),
          const Divider(height: 16),
          Text(content, style: GoogleFonts.merriweather(fontSize: 13, color: AppPalette.fg(Colors.black87), height: 1.4)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 2),
    child: Text(title, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.blueGrey[900]))),
  );
}