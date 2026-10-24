// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:master_admin/compilation_modules/evangelism_results_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../compilation_modules/service_attendance_module.dart';
import '../compilation_modules/cell_service_module.dart';
import '../compilation_modules/workers_education_module.dart';
import '../compilation_modules/all_saints_education_module.dart';
import '../compilation_modules/offering_module.dart';
import '../compilation_modules/evangelism_module.dart';
import '../compilation_modules/daily_participation_module.dart';
import '../compilation_modules/morning_light_module.dart';
import '../compilation_modules/visitations_module.dart';
import '../compilation_modules/growth_tracking_module.dart';
import 'compilation_results_list.dart';
import 'admin/hierarchy_leaderboard_screen.dart';

class CompilationEngine extends StatefulWidget {
  final String role, userUnit, selectedDuty, loc, sub, dept, team; 

  const CompilationEngine({
    super.key, 
    required this.role, 
    required this.userUnit, 
    required this.selectedDuty, 
    required this.loc,
    required this.sub, 
    required this.dept, 
    required this.team,
  });

  @override
  State<CompilationEngine> createState() => _CompilationEngineState();
}

class _CompilationEngineState extends State<CompilationEngine> {
  final _supabase = Supabase.instance.client;
  final Color pPurple = const Color(0xFF4A148C);
  final TextEditingController _analysisController = TextEditingController();

  List<String> _timeOptions = ["Current status", "Weekly status", "Monthly status", "Custom period"];
  List<String> _modeOptions = ["Summary", "Ranking", "Trend"];
  List<String> _visitationCategories = ["Lta", "H.m", "Offline", "Offering", "Evangelism"];
  
  String _timePeriod = 'Weekly status';
  String _analyticsMode = 'Summary'; 
  String _groupBy = 'Church'; 
  String _currentLevel = 'Church status';
  DateTimeRange? _customRange;
  late List<String> _hierarchy;
  bool _isLoading = true;
  List<dynamic> _logs = [];

  // 3 Dynamic Growth Metrics
  double _primaryGrowth = 0.0;
  double _secondaryGrowth = 0.0;
  double _tertiaryGrowth = 0.0;
  String _primaryLabel = "General Growth";
  String _secondaryLabel = "In-person Growth";
  String _tertiaryLabel = "Absentees Change";

  List<Map<String, dynamic>> _locationData = [];
  List<Map<String, dynamic>> _subLocationData = [];
  List<Map<String, dynamic>> _deptData = [];
  List<Map<String, dynamic>> _teamData = [];

  List<String> _locations = [];
  List<String> _subLocations = [];
  List<String> _departments = [];
  List<String> _teams = [];

  String? _selectedLocation;
  String? _selectedSubLocation;
  String? _selectedDepartment;
  String? _selectedTeam;

  Map<String, dynamic>? _roleMetadata;
  bool _dualModeIsChurch = true;

  String get _scope => _roleMetadata?['approval_scope'] ?? '';
  String get _grouping => (_roleMetadata?['Grouping'] ?? '').toString();

  bool get _isGroupLeader {
    String r = widget.role.toLowerCase();
    if (r.contains('cell') || r.contains('team') || r.startsWith('dept_') || r.startsWith('sub_loc') || r.startsWith('loc_')) {
      return false;
    }

    if (_grouping == '24-Dept MG' || 
        _grouping == '24-Dept WG' || 
        _grouping == '24-Dept YAG' || 
        _grouping == '24-Dept New Saints' || 
        _grouping == '24-Dept MOU' ||
        _grouping.startsWith('24-Dept 18')) {
      return true;
    }

    return r.contains('_group_') || 
           r.contains('new_saints_dept') || 
           r.contains('theology_dept') ||
           r.contains('mou_dept');
  }

  String get _groupLeaderCleanDept {
    final r = widget.role.toLowerCase();
    if (_grouping == '24-Dept MG' || r.startsWith('mg_group')) return '장년회';
    if (_grouping == '24-Dept WG' || r.startsWith('wg_group')) return '부녀회';
    if (_grouping == '24-Dept YAG' || r.startsWith('yag_group')) return '청년회';
    if (_grouping == '24-Dept New Saints' || r.startsWith('new_saints')) return '새신자';
    if (_grouping.startsWith('24-Dept 18') || r.startsWith('theology')) return '신학부';
    if (_grouping == '24-Dept MOU' || r.startsWith('mou')) return 'Mou';
    return widget.dept.replaceAll(RegExp(r'(회장|부장|총무|서무|과장)$'), '').trim();
  }

  bool get _isInternalAffairs {
    String r = widget.role.toLowerCase();
    String d = widget.dept.trim().toLowerCase();
    return r.contains('internal_affairs') || 
           r.startsWith('ia_') || 
           d.contains('내무') ||
           _grouping.startsWith('24-Dept 3');
  }

  bool get _isEvangelismDept {
    String r = widget.role.toLowerCase();
    String d = widget.dept.trim().toLowerCase();
    return (r.contains('evang_dept') || d.contains('전도') || _grouping.startsWith('24-Dept 5')) &&
           !r.contains('loc_evang');
  }

  bool get _isEducationDept {
    String r = widget.role.toLowerCase();
    String d = widget.dept.trim().toLowerCase();
    return (r.contains('edu_dept') || d.contains('교육') || _grouping.startsWith('24-Dept 4')) &&
           !r.contains('loc_edu');
  }

  bool get _isAdministrationDept {
    String r = widget.role.toLowerCase();
    String d = widget.dept.trim().toLowerCase();
    return (r.contains('admin_dept') || d.contains('행정서무') || 
            _grouping.startsWith('24-Dept 11') || _grouping.startsWith('24-Dept 12') || _grouping.startsWith('24-Dept 13')) &&
           r != 'admin';
  }

  bool get _hasDualModeForCurrentDuty {
    final d = widget.selectedDuty.trim();
    if (_isInternalAffairs) return true;

    if (_isEvangelismDept && 
        (d == 'Evangelism' || d == 'Evangelism Part' || d == 'Evangelism Results' || d == 'BB Results')) {
      return true;
    }

    if (_isEducationDept && 
        (d == 'All Saints Education' || d == 'Workers Education')) {
      return true;
    }

    if (_isAdministrationDept && 
        d == 'Service Attendance Status') {
      return true;
    }

    return false;
  }

  String _getDualModeTitle() {
    if (_isInternalAffairs) return "Internal Affairs Scope";
    if (_isEvangelismDept) return "Evangelism Scope";
    if (_isEducationDept) return "Education Scope";
    if (_isAdministrationDept) return "Administration Scope";
    return "Report Scope";
  }

  bool get _isChurchWideCompiler {
    if (_isGroupLeader) return false;
    
    if (_hasDualModeForCurrentDuty) {
      return _dualModeIsChurch;
    }

    if (_scope == 'church_department' || _grouping.startsWith('24-Dept')) return false;

    if (_scope == 'church') return true;

    String r = widget.role.toLowerCase();
    return r == 'admin' || r.startsWith('church_') || r.startsWith('korean_worker_');
  }

  bool get _is24DeptWorker {
    if (_isGroupLeader || _isChurchWideCompiler) return false;
    if (_hasDualModeForCurrentDuty && !_dualModeIsChurch) return true;
    return _grouping.startsWith('24-Dept') || _scope == 'church_department';
  }

  bool get _isLocationLeader {
    if (_isChurchWideCompiler || _isGroupLeader || _is24DeptWorker) return false;
    return _scope == 'location' || _grouping.startsWith('Location') || (widget.role.contains('loc_') && !widget.role.contains('sub_loc'));
  }

  bool get _isSubLocationLeader {
    if (_isChurchWideCompiler || _isGroupLeader || _is24DeptWorker) return false;
    return _scope == 'sub_location' || _grouping.startsWith('Sub-Location') || widget.role.contains('sub_loc');
  }

  bool get _isDeptLeader {
    if (_isChurchWideCompiler || _isGroupLeader || _is24DeptWorker || _isLocationLeader || _isSubLocationLeader) return false;
    return _scope == 'department' || _grouping.startsWith('Dept ') || widget.role.contains('dept_');
  }

  bool get _isTeamLeader {
    if (_isChurchWideCompiler || _isGroupLeader || _is24DeptWorker || _isLocationLeader || _isSubLocationLeader || _isDeptLeader) return false;
    return _scope == 'team' || _grouping.startsWith('Team') || _grouping == 'Location Team' || widget.role.contains('team_');
  }

  @override
  void initState() {
    super.initState();
    _setHierarchy();
    _initHierarchyAndData();
  }

  Future<void> _initHierarchyAndData() async {
    await _fetchRoleMetadata();
    _setHierarchy();
    await _loadUIConfig();
    await _fetchInitialLocations();
    await _fetchData();
  }

  Future<void> _fetchRoleMetadata() async {
    try {
      final res = await _supabase
          .from('app_roles')
          .select('role_key, approval_scope, display_name_ko, "Grouping", official_dept_id')
          .eq('role_key', widget.role)
          .maybeSingle();

      if (mounted && res != null) {
        setState(() {
          _roleMetadata = res;
        });
      }
    } catch (e) {
      debugPrint("Role Metadata Fetch Error: $e");
    }
  }

  void _setHierarchy() {
    if (_isGroupLeader) {
      _hierarchy = ['Group status', 'Location status', 'Sub location status', 'Team status', 'Cell status'];
    } else if (_isChurchWideCompiler) {
      _hierarchy = ['Church status', 'Group status', 'Location status', 'Sub location status', 'Dept status', 'Team status', 'Cell status'];
    } else if (_is24DeptWorker || (_hasDualModeForCurrentDuty && !_dualModeIsChurch)) {
      _hierarchy = ['Dept status'];
    } else if (_isLocationLeader) {
      _hierarchy = ['Location status', 'Sub location status', 'Dept status', 'Team status', 'Cell status'];
    } else if (_isSubLocationLeader) {
      _hierarchy = ['Sub location status', 'Dept status', 'Team status', 'Cell status'];
    } else if (_isDeptLeader) {
      _hierarchy = ['Sub location status', 'Dept status', 'Team status', 'Cell status'];
    } else if (_isTeamLeader) {
      _hierarchy = ['Team status', 'Cell status'];
    } else {
      _hierarchy = ['Cell status'];
    }

    if (!_hierarchy.contains(_currentLevel)) {
      _currentLevel = _hierarchy.first;
    }
    _updateGroupByFromLevel(_currentLevel);
  }

  void _updateGroupByFromLevel(String level) {
    if (_is24DeptWorker || (_hasDualModeForCurrentDuty && !_dualModeIsChurch)) {
      _groupBy = 'Church';
    } else if (_isDeptLeader && level == 'Dept status') {
      _groupBy = 'Church';
    } else if (_isSubLocationLeader && level == 'Sub location status') {
      _groupBy = 'Church';
    } else if (level.contains('Cell')) {
      _groupBy = 'Cell';
    } else if (level.contains('Team')) {
      _groupBy = 'Team';
    } else if (level.contains('Dept')) {
      _groupBy = 'Dept';
    } else if (level.contains('Sub location')) {
      _groupBy = 'Sub-loc';
    } else if (level.contains('Location')) {
      _groupBy = 'Loc';
    } else if (level.contains('Group')) {
      _groupBy = 'Group';
    } else {
      _groupBy = 'Church';
    }
  }

  Future<void> _fetchInitialLocations() async {
    try {
      List<Map<String, dynamic>> data = [];
      try {
        final res = await _supabase.from('locations').select('id, location').order('location');
        data = List<Map<String, dynamic>>.from(res);
      } catch (_) {
        try {
          final res = await _supabase.from('locations').select('id, name').order('name');
          data = List<Map<String, dynamic>>.from(res.map((e) => {'id': e['id'], 'location': e['name']}));
        } catch (_) {}
      }

      if (data.isEmpty) {
        final mLocs = await _supabase.from('members').select('location').not('location', 'is', null);
        final Set<String> distinct = {};
        for (var row in mLocs) {
          final l = row['location']?.toString() ?? '';
          if (l.isNotEmpty) distinct.add(l);
        }
        data = distinct.map((l) => {'id': l, 'location': l}).toList();
      }

      if (!mounted) return;
      setState(() {
        _locationData = data;
        _locations = _locationData
            .map((e) => (e['location'] ?? e['name'] ?? '').toString())
            .where((l) => l.isNotEmpty && l.toLowerCase() != 'church' && l.toLowerCase() != 'church workers')
            .toSet()
            .toList();
        _locations.sort();

        if (!_isChurchWideCompiler && !_isGroupLeader && widget.loc.isNotEmpty && widget.loc != 'Church') {
          _selectedLocation = widget.loc;
        } else if (_locations.isNotEmpty) {
          _selectedLocation = _locations.first;
        }

        if (widget.sub.isNotEmpty) _selectedSubLocation = widget.sub;
        if (widget.dept.isNotEmpty) _selectedDepartment = widget.dept;
        if (widget.team.isNotEmpty) _selectedTeam = widget.team;
      });

      if (_selectedLocation != null) {
        await _fetchSubLocations(_selectedLocation!, triggerFetch: false);
      }
    } catch (e) {
      debugPrint("Compilation Location Fetch Error: $e");
    }
  }

  Future<void> _fetchSubLocations(String locName, {bool triggerFetch = true}) async {
    try {
      final match = _locationData.firstWhere(
        (e) => (e['location'] ?? e['name']) == locName, 
        orElse: () => {}
      );
      if (match.isEmpty || match['id'] == null) return;
      final locId = match['id'];

      final data = await _supabase.from('sub_locations').select('id, name').eq('location_id', locId).order('name');
      if (!mounted) return;
      setState(() {
        _subLocationData = List<Map<String, dynamic>>.from(data);
        _subLocations = _subLocationData.map((e) => e['name'].toString()).toList();
        
        if (widget.sub.isNotEmpty && _subLocations.contains(widget.sub)) {
          _selectedSubLocation = widget.sub;
        } else {
          _selectedSubLocation = _subLocations.isNotEmpty ? _subLocations.first : null;
        }
      });

      if (_selectedSubLocation != null) {
        await _fetchDepartments(_selectedSubLocation!, triggerFetch: false);
      }
      if (triggerFetch) _fetchData();
    } catch (e) {
      debugPrint("Compilation Sub-loc Fetch Error: $e");
    }
  }

  Future<void> _fetchDepartments(String subName, {bool triggerFetch = true}) async {
    try {
      if (_isGroupLeader || _isDeptLeader || _isTeamLeader) {
        setState(() => _selectedDepartment = widget.dept);
        if (_selectedDepartment != null) await _fetchTeams(_selectedDepartment!, triggerFetch: false);
        if (triggerFetch) _fetchData();
        return;
      }

      final match = _subLocationData.firstWhere((e) => e['name'] == subName, orElse: () => {});
      if (match.isEmpty || match['id'] == null) return;
      final subId = match['id'];

      final data = await _supabase.from('departments').select('id, name').eq('sub_location_id', subId).order('name');
      if (!mounted) return;
      setState(() {
        _deptData = List<Map<String, dynamic>>.from(data);
        _departments = _deptData.map((e) => e['name'].toString()).toList();
        if (_departments.isEmpty) {
          _departments = ["장년회", "부녀회", "청년회", "신학부", "새신자"];
        }
        
        if (widget.dept.isNotEmpty && _departments.contains(widget.dept)) {
          _selectedDepartment = widget.dept;
        } else {
          _selectedDepartment = _departments.first;
        }
      });

      if (_selectedDepartment != null) {
        await _fetchTeams(_selectedDepartment!, triggerFetch: false);
      }
      if (triggerFetch) _fetchData();
    } catch (e) {
      debugPrint("Compilation Dept Fetch Error: $e");
    }
  }

  Future<void> _fetchTeams(String deptName, {bool triggerFetch = true}) async {
    try {
      final match = _deptData.firstWhere((e) => e['name'] == deptName, orElse: () => {});
      if (match.isEmpty || match['id'] == null) {
        setState(() => _teams = ["팀1", "팀2", "팀3"]);
        if (triggerFetch) _fetchData();
        return;
      }
      final deptId = match['id'];

      final data = await _supabase.from('teams').select('id, name').eq('dept_id', deptId).order('name');
      if (!mounted) return;
      setState(() {
        _teamData = List<Map<String, dynamic>>.from(data);
        _teams = _teamData.map((e) => e['name'].toString()).toList();
        if (_teams.isEmpty) _teams = ["팀1", "팀2", "팀3"];
        
        if (widget.team.isNotEmpty && _teams.contains(widget.team)) {
          _selectedTeam = widget.team;
        } else {
          _selectedTeam = _teams.isNotEmpty ? _teams.first : null;
        }
      });
      if (triggerFetch) _fetchData();
    } catch (e) {
      debugPrint("Compilation Team Fetch Error: $e");
    }
  }

  Future<void> _loadUIConfig() async {
    try {
      final res = await _supabase.from('compilation_ui_config').select().eq('is_active', true).order('sort_order');
      if (res.isNotEmpty && mounted) {
        final List<dynamic> list = res as List<dynamic>;
        final times = list.where((e) => e['config_type'] == 'time_period').map((e) => e['label'].toString()).toList();
        final modes = list.where((e) => e['config_type'] == 'analytics_mode').map((e) => e['label'].toString()).toList();
        final vis = list.where((e) => e['config_type'] == 'visitation_category').map((e) => e['label'].toString()).toList();

        setState(() {
          if (times.isNotEmpty) _timeOptions = times;
          if (modes.isNotEmpty) _modeOptions = modes;
          if (vis.isNotEmpty) _visitationCategories = vis;
        });
      }
    } catch (e) {
      debugPrint("UI Config fallback: $e");
    }
  }

  String _getTargetTable() {
    String d = widget.selectedDuty;
    if (d == 'Service Attendance Status') return 'logs_service_attendance_status';
    if (d == 'Cell Group Service') return 'logs_cell_service';
    if (d == 'All Saints Education') return 'logs_all_saints_education';
    if (d == 'Offering' || d == 'Offering Status') return 'logs_offering';
    if (d == 'Evangelism' || d == 'Evangelism Part') return 'logs_evangelism';
    if (d == 'Morning Light') return 'logs_morning_light';
    if (d == 'Visitations and Counselling') return 'logs_visitations';
    if (d == 'Workers Education') return 'logs_workers_education';
    if (d == 'Workers Daily Participation') return 'logs_workers_participation';
    if (d == 'Growth Tracking') return 'logs_growth_tracking';
    return 'logs_service_attendance_status';
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final String table = _getTargetTable();
      final DateTime now = DateTime.now();
      final DateFormat df = DateFormat('yyyy-MM-dd');

      DateTime bStart;
      DateTime bEnd;

      if (_timePeriod == "Custom period" && _customRange != null) {
        bStart = _customRange!.start.subtract(_customRange!.duration);
        bEnd = _customRange!.start.subtract(const Duration(days: 1));
      } else if (_timePeriod == "Weekly status") {
        bStart = now.subtract(const Duration(days: 14));
        bEnd = now.subtract(const Duration(days: 8));
      } else if (_timePeriod == "Current status") {
        bStart = now.subtract(const Duration(days: 1));
        bEnd = now.subtract(const Duration(days: 1));
      } else {
        bStart = DateTime(now.year, now.month - 1, 1);
        bEnd = DateTime(now.year, now.month, 0);
      }

      final lvl = _currentLevel.toLowerCase();

      const String lightColumns = '''
        id, report_date, unit_name, verification_status, correction_note, situation_notes,
        attendance_realtime, attendance_makeup, status_detail, service_day,
        is_hm, is_lta, geo_category, reg_status, location, sub_location, department, team, cell_group,
        members!inner(id, location, sub_location, department, team, cell_group, reg_status, geo_category, book_of_life, bol_dept, official_dept_id)
      ''';

      dynamic buildQuery(DateTime? start, DateTime? end, {bool isPrev = false}) {
        dynamic q = _supabase.from(table).select(lightColumns);

        if (_timePeriod == "Custom period" && _customRange != null) {
          String s = isPrev ? df.format(bStart) : df.format(_customRange!.start);
          String e = isPrev ? df.format(bEnd) : df.format(_customRange!.end);
          q = q.gte('report_date', s).lte('report_date', e);
        } else if (_timePeriod == "Weekly status") {
          String s = isPrev ? df.format(bStart) : df.format(now.subtract(const Duration(days: 7)));
          String e = isPrev ? df.format(bEnd) : df.format(now);
          q = q.gte('report_date', s).lte('report_date', e);
        } else if (_timePeriod == "Current status") {
          String s = isPrev ? df.format(bStart) : df.format(now);
          q = q.eq('report_date', s);
        } else {
          String s = isPrev ? df.format(bStart) : df.format(DateTime(now.year, now.month, 1));
          String e = isPrev ? df.format(bEnd) : df.format(now);
          q = q.gte('report_date', s).lte('report_date', e);
        }

        // 1. GROUP WORKERS (Resolves exact member department like '장년회' rather than '장년회장')
        if (_isGroupLeader) {
          final deptTarget = _groupLeaderCleanDept;
          q = q.eq('members.department', deptTarget);

          if (deptTarget != 'Mou') {
            q = q.neq('members.location', 'Mou');
          }
          if (deptTarget != '새신자') {
            q = q.neq('members.location', 'New Saints');
          }

          q = q.neq('members.location', 'Church Workers')
               .neq('members.location', 'Church Main')
               .neq('members.location', 'Church');
        }
        // 2. 24 DEPARTMENTS (CHURCH LEVEL < 20 SAINTS)
        else if (_is24DeptWorker || (_hasDualModeForCurrentDuty && !_dualModeIsChurch)) {
          q = q.neq('members.location', 'Mou').neq('members.location', 'New Saints');
          q = q.or('location.eq.Church,location.eq.Church Workers,location.eq.Church Main,members.location.eq.Church,members.location.eq.Church Workers,members.location.eq.Church Main,members.location.is.null');

          final officialDeptId = _roleMetadata?['official_dept_id'];
          if (officialDeptId != null) {
            q = q.eq('members.official_dept_id', officialDeptId);
          } else if (_isInternalAffairs) {
            q = q.or('members.department.eq.내무부,members.department.ilike.%internal affairs%');
          } else if (_isEvangelismDept) {
            q = q.or('members.department.eq.전도부,members.department.ilike.%evangelism%');
          } else if (_isEducationDept) {
            q = q.or('members.department.eq.교육부,members.department.ilike.%education%');
          } else if (_isAdministrationDept) {
            q = q.or('members.department.eq.행정서무부,members.department.ilike.%admin%');
          } else if (widget.dept.isNotEmpty && widget.dept != 'N/A' && widget.dept != 'Church') {
            q = q.eq('members.department', widget.dept);
          }
        }
        // 3. LOCATION WORKERS
        else if (!_isChurchWideCompiler) {
          if (widget.loc.isNotEmpty && widget.loc != 'Church' && widget.loc != 'N/A') {
            q = q.eq('members.location', widget.loc);
          }
          if (_isDeptLeader) {
            if (widget.dept.isNotEmpty && widget.dept != 'N/A') q = q.eq('members.department', widget.dept);
            if (lvl.contains(RegExp(r'team|cell')) && _selectedSubLocation != null && _selectedSubLocation!.isNotEmpty) {
              q = q.eq('members.sub_location', _selectedSubLocation!);
            }
          } else if (_isSubLocationLeader) {
            if (widget.sub.isNotEmpty && widget.sub != 'N/A') q = q.eq('members.sub_location', widget.sub);
          } else if (_isTeamLeader) {
            if (widget.sub.isNotEmpty && widget.sub != 'N/A') q = q.eq('members.sub_location', widget.sub);
            if (widget.dept.isNotEmpty && widget.dept != 'N/A') q = q.eq('members.department', widget.dept);
            if (widget.team.isNotEmpty && widget.team != 'N/A') q = q.eq('members.team', widget.team);
          }
          if (widget.role.toLowerCase().contains('cell')) {
            q = q.eq('unit_name', widget.userUnit);
          }
        }

        // 4. DRILL-DOWN FILTERS
        if (lvl.contains('sub location') || lvl.contains('sub-location') || lvl.contains('team') || lvl.contains('cell')) {
          if (_selectedLocation != null && _selectedLocation!.isNotEmpty && _selectedLocation != 'Church') {
            q = q.eq('members.location', _selectedLocation!);
          }
        }
        if (lvl.contains(RegExp(r'dept|team|cell')) && !_isDeptLeader) {
          if (_selectedSubLocation != null && _selectedSubLocation!.isNotEmpty) {
            q = q.eq('members.sub_location', _selectedSubLocation!);
          }
        }
        if (!_isGroupLeader && !_isDeptLeader && lvl.contains(RegExp(r'team|cell'))) {
          if (_selectedDepartment != null && _selectedDepartment!.isNotEmpty) {
            q = q.eq('members.department', _selectedDepartment!);
          }
        }
        if (lvl.contains('cell')) {
          if (_selectedTeam != null && _selectedTeam!.isNotEmpty) {
            q = q.eq('members.team', _selectedTeam!);
          }
        }
        return q;
      }

      List<dynamic> allCurrentLogs = [];
      int offset = 0;
      const int pageSize = 1000;
      while (true) {
        final chunk = await buildQuery(null, null, isPrev: false).range(offset, offset + pageSize - 1);
        final list = chunk as List<dynamic>;
        allCurrentLogs.addAll(list);
        if (list.length < pageSize) break;
        offset += pageSize;
      }

      List<dynamic> prevLogs = [];
      try {
        final prevChunk = await buildQuery(bStart, bEnd, isPrev: true).range(0, 999);
        prevLogs = prevChunk as List<dynamic>;
      } catch (_) {
        prevLogs = [];
      }

      _calculateDynamicGrowthMetrics(allCurrentLogs, prevLogs);

      if (!mounted) return;

      setState(() { 
        _logs = allCurrentLogs; 
        _isLoading = false; 
      });
    } catch (e) { 
      debugPrint("Compilation Query Error: $e");
      if (mounted) setState(() => _isLoading = false); 
    }
  }

  void _calculateDynamicGrowthMetrics(List<dynamic> cur, List<dynamic> prev) {
    final d = widget.selectedDuty;

    double pctDiff(double c, double p) {
      if (p == 0) return c > 0 ? 100.0 : 0.0;
      return ((c - p) / p) * 100.0;
    }

    if (d.contains('Attendance') || d.contains('Cell Group') || d.contains('Education')) {
      _primaryLabel = "General Att Growth";
      _secondaryLabel = "In-person Growth";
      _tertiaryLabel = "Absentees Change";

      int cAtt = cur.where((x) => x['attendance_realtime'] != 'Absentee' && (x['status_detail'] ?? '').toString().toLowerCase() != 'absence').length;
      int pAtt = prev.where((x) => x['attendance_realtime'] != 'Absentee' && (x['status_detail'] ?? '').toString().toLowerCase() != 'absence').length;

      int cIp = cur.where((x) => x['attendance_realtime'] == 'In-person' || (x['status_detail'] ?? '').toString().contains('In-person')).length;
      int pIp = prev.where((x) => x['attendance_realtime'] == 'In-person' || (x['status_detail'] ?? '').toString().contains('In-person')).length;

      int cAbs = cur.where((x) => x['attendance_realtime'] == 'Absentee' || (x['status_detail'] ?? '').toString().contains('Absence')).length;
      int pAbs = prev.where((x) => x['attendance_realtime'] == 'Absentee' || (x['status_detail'] ?? '').toString().contains('Absence')).length;

      _primaryGrowth = pctDiff(cAtt.toDouble(), pAtt.toDouble());
      _secondaryGrowth = pctDiff(cIp.toDouble(), pIp.toDouble());
      _tertiaryGrowth = pctDiff(cAbs.toDouble(), pAbs.toDouble());
    } else if (d.contains('Evangelism')) {
      _primaryLabel = "Participation Growth";
      _secondaryLabel = "Active Saints";
      _tertiaryLabel = "Support Needed";

      int cEv = cur.where((x) => (x['status_detail'] ?? '').toString().toLowerCase().contains('evangelised')).length;
      int pEv = prev.where((x) => (x['status_detail'] ?? '').toString().toLowerCase().contains('evangelised')).length;

      _primaryGrowth = pctDiff(cEv.toDouble(), pEv.toDouble());
      _secondaryGrowth = cur.length.toDouble();
      _tertiaryGrowth = math.max(0, cur.length - cEv).toDouble();
    } else if (d.contains('Morning Light') || d.contains('Workers Daily')) {
      _primaryLabel = "Participation Rate";
      _secondaryLabel = "Done Count";
      _tertiaryLabel = "Missed Days";

      int cDone = cur.where((x) => (x['status_detail'] ?? '').toString().toLowerCase().contains('did') || (x['status_detail'] ?? '').toString().toLowerCase().contains('yes')).length;
      int pDone = prev.where((x) => (x['status_detail'] ?? '').toString().toLowerCase().contains('did') || (x['status_detail'] ?? '').toString().toLowerCase().contains('yes')).length;

      _primaryGrowth = pctDiff(cDone.toDouble(), pDone.toDouble());
      _secondaryGrowth = cDone.toDouble();
      _tertiaryGrowth = math.max(0, cur.length - cDone).toDouble();
    } else {
      _primaryLabel = "Total Submissions";
      _secondaryLabel = "Current Period";
      _tertiaryLabel = "Previous Period";

      _primaryGrowth = pctDiff(cur.length.toDouble(), prev.length.toDouble());
      _secondaryGrowth = cur.length.toDouble();
      _tertiaryGrowth = prev.length.toDouble();
    }
  }

  String _getActiveUnitDisplayLabel() {
    final lvl = _currentLevel.toLowerCase();
    if (_is24DeptWorker || (_hasDualModeForCurrentDuty && !_dualModeIsChurch)) {
      return widget.dept.isNotEmpty ? widget.dept : "Department";
    }
    if (_isGroupLeader) {
      if (lvl.contains('group')) return _groupLeaderCleanDept;
      if (lvl.contains('location')) return 'Location';
      if (lvl.contains('sub location')) return _selectedLocation ?? 'Sub-locations';
      if (lvl.contains('team')) return _selectedSubLocation ?? 'Team';
      if (lvl.contains('cell')) return _selectedTeam ?? 'Cell group';
    }
    if (lvl.contains('church')) return 'Church';
    if (lvl.contains('group')) return 'Book of Life';
    if (lvl.contains('location')) return 'Location';
    if (lvl.contains('sub location')) return _selectedLocation ?? 'Sub-locations';
    if (lvl.contains('dept')) return _selectedSubLocation ?? 'Department';
    if (lvl.contains('team')) return _selectedDepartment ?? 'Team';
    if (lvl.contains('cell')) return _selectedTeam ?? 'Cell group';
    return 'Unit';
  }

  String _getFindingsTitle() {
    if (widget.role.isEmpty) return "Leader's findings";
    String formattedRole = widget.role.replaceAll('_', ' ').split(' ').map((str) => str.isNotEmpty ? str[0].toUpperCase() + str.substring(1) : '').join(' ');
    return "$formattedRole's findings";
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    bool isMobile = screenWidth < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white, 
        elevation: 0, 
        iconTheme: IconThemeData(color: pPurple),
        title: Text(
          widget.selectedDuty, 
          style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: pPurple, fontSize: 17.5, letterSpacing: 0.4),
        ),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1.0), child: Container(color: Colors.black, height: 1.0)),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology_alt_rounded, color: Color(0xFF4A148C), size: 24),
            tooltip: "AI Performance Analysis",
            onPressed: _showAiExecutiveReportDialog,
          ),
          if (isMobile) 
            Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.filter_list_rounded), onPressed: () => Scaffold.of(ctx).openEndDrawer())),
        ],
      ),
      endDrawer: isMobile ? Drawer(child: _buildSidebarContent()) : null,
      body: Row(children: [
        if (!isMobile) _buildSidebarContent(),
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator()) 
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.all(isMobile ? 12 : 20), 
                child: _buildMainContent()
              )
        ),
      ]),
    );
  }

  Widget _buildMainContent() => Column(children: [
    _buildGrowthCard(),
    const SizedBox(height: 15),
    _buildSelectedModule(),
    const SizedBox(height: 15),
    _buildAnalysisBox(),
    const SizedBox(height: 40),
  ]);

  Widget _buildSelectedModule() {
    String d = widget.selectedDuty;
    if (_analyticsMode == 'Ranking') {
      return HierarchyLeaderboardScreen(role: widget.role, duty: d, loc: widget.loc, sub: widget.sub, dept: widget.dept, team: widget.team);
    }
    
    if (d == 'Service Attendance Status') {
      return ServiceAttendanceModule(
        logs: _logs, 
        timePeriod: _timePeriod, 
        level: _currentLevel, 
        analyticsMode: _analyticsMode, 
        groupBy: _groupBy, 
        targetValue: 80.0,
        selectedLocation: _selectedLocation ?? '',
        selectedSubLocation: _selectedSubLocation ?? '',
        selectedDepartment: _selectedDepartment ?? '',
        selectedTeam: _selectedTeam ?? '',
        activeUnitLabel: _getActiveUnitDisplayLabel(),
        isChurchWide: _isChurchWideCompiler,
        isLocationLeader: _isLocationLeader,
        isSubLocationLeader: _isSubLocationLeader,
        isDeptLeader: _isDeptLeader,
        isTeamLeader: _isTeamLeader,
        isGroupLeader: _isGroupLeader,
        userRole: widget.role,
        userDept: widget.dept,
        userSub: widget.sub,
        userLoc: widget.loc,
        userTeam: widget.team,
      );
    }
    if (d == 'Cell Group Service') {
      return CellServiceModule(
        logs: _logs, 
        timePeriod: _timePeriod, 
        level: _currentLevel, 
        analyticsMode: _analyticsMode, 
        groupBy: _groupBy, 
        targetValue: 80.0,
        selectedLocation: _selectedLocation ?? '',
        selectedSubLocation: _selectedSubLocation ?? '',
        selectedDepartment: _selectedDepartment ?? '',
        selectedTeam: _selectedTeam ?? '',
        activeUnitLabel: _getActiveUnitDisplayLabel(),
        isChurchWide: _isChurchWideCompiler,
        isLocationLeader: _isLocationLeader,
        isSubLocationLeader: _isSubLocationLeader,
        isDeptLeader: _isDeptLeader,
        isTeamLeader: _isTeamLeader,
        isGroupLeader: _isGroupLeader,
        userRole: widget.role,
        userDept: widget.dept,
        userSub: widget.sub,
        userLoc: widget.loc,
        userTeam: widget.team,
      );
    }
    if (d == 'All Saints Education') {
      return AllSaintsEducationModule(
        logs: _logs, 
        timePeriod: _timePeriod, 
        level: _currentLevel, 
        analyticsMode: _analyticsMode, 
        groupBy: _groupBy, 
        targetValue: 80.0,
        selectedLocation: _selectedLocation ?? '',
        selectedSubLocation: _selectedSubLocation ?? '',
        selectedDepartment: _selectedDepartment ?? '',
        selectedTeam: _selectedTeam ?? '',
        activeUnitLabel: _getActiveUnitDisplayLabel(),
        isChurchWide: _isChurchWideCompiler,
        isLocationLeader: _isLocationLeader,
        isSubLocationLeader: _isSubLocationLeader,
        isDeptLeader: _isDeptLeader,
        isTeamLeader: _isTeamLeader,
        isGroupLeader: _isGroupLeader,
        userRole: widget.role,
        userDept: widget.dept,
        userSub: widget.sub,
        userLoc: widget.loc,
        userTeam: widget.team,
      );
    }
    if (d == 'Offering' || d == 'Offering Status') {
      return OfferingModule(
        logs: _logs,
        timePeriod: _timePeriod,
        level: _currentLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _selectedLocation ?? '',
        selectedSubLocation: _selectedSubLocation ?? '',
        selectedDepartment: _selectedDepartment ?? '',
        selectedTeam: _selectedTeam ?? '',
        activeUnitLabel: _getActiveUnitDisplayLabel(),
        isChurchWide: _isChurchWideCompiler,
        isLocationLeader: _isLocationLeader,
        isSubLocationLeader: _isSubLocationLeader,
        isDeptLeader: _isDeptLeader,
        isTeamLeader: _isTeamLeader,
        isGroupLeader: _isGroupLeader,
        userRole: widget.role,
        userDept: widget.dept,
        userSub: widget.sub,
        userLoc: widget.loc,
        userTeam: widget.team,
      );
    }
    if (d == 'Evangelism' || d == 'Evangelism Part') {
      return EvangelismModule(
        logs: _logs,
        timePeriod: _timePeriod,
        level: _currentLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _selectedLocation ?? '',
        selectedSubLocation: _selectedSubLocation ?? '',
        selectedDepartment: _selectedDepartment ?? '',
        selectedTeam: _selectedTeam ?? '',
        activeUnitLabel: _getActiveUnitDisplayLabel(),
        isChurchWide: _isChurchWideCompiler,
        isLocationLeader: _isLocationLeader,
        isSubLocationLeader: _isSubLocationLeader,
        isDeptLeader: _isDeptLeader,
        isTeamLeader: _isTeamLeader,
        isGroupLeader: _isGroupLeader,
        userRole: widget.role,
        userDept: widget.dept,
        userSub: widget.sub,
        userLoc: widget.loc,
        userTeam: widget.team,
      );
    }

    if (d == 'Morning Light') {
      return MorningLightModule(
        logs: _logs,
        timePeriod: _timePeriod,
        level: _currentLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _selectedLocation ?? '',
        selectedSubLocation: _selectedSubLocation ?? '',
        selectedDepartment: _selectedDepartment ?? '',
        selectedTeam: _selectedTeam ?? '',
        activeUnitLabel: _getActiveUnitDisplayLabel(),
        isChurchWide: _isChurchWideCompiler,
        isLocationLeader: _isLocationLeader,
        isSubLocationLeader: _isSubLocationLeader,
        isDeptLeader: _isDeptLeader,
        isTeamLeader: _isTeamLeader,
        isGroupLeader: _isGroupLeader,
        userRole: widget.role,
        userDept: widget.dept,
        userSub: widget.sub,
        userLoc: widget.loc,
        userTeam: widget.team,
      );
    }
    if (d == 'Workers Education') {
      return WorkersEducationModule(
        logs: _logs,
        timePeriod: _timePeriod,
        level: _currentLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _selectedLocation ?? '',
        selectedSubLocation: _selectedSubLocation ?? '',
        selectedDepartment: _selectedDepartment ?? '',
        selectedTeam: _selectedTeam ?? '',
        activeUnitLabel: _getActiveUnitDisplayLabel(),
        isChurchWide: _isChurchWideCompiler,
        isLocationLeader: _isLocationLeader,
        isSubLocationLeader: _isSubLocationLeader,
        isDeptLeader: _isDeptLeader,
        isTeamLeader: _isTeamLeader,
        isGroupLeader: _isGroupLeader,
        userRole: widget.role,
        userDept: widget.dept,
        userSub: widget.sub,
        userLoc: widget.loc,
        userTeam: widget.team,
      );
    }
    if (d == 'Workers Daily Participation') {
      return DailyParticipationModule(
        logs: _logs,
        timePeriod: _timePeriod,
        level: _currentLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _selectedLocation ?? '',
        selectedSubLocation: _selectedSubLocation ?? '',
        selectedDepartment: _selectedDepartment ?? '',
        selectedTeam: _selectedTeam ?? '',
        activeUnitLabel: _getActiveUnitDisplayLabel(),
        isChurchWide: _isChurchWideCompiler,
        isLocationLeader: _isLocationLeader,
        isSubLocationLeader: _isSubLocationLeader,
        isDeptLeader: _isDeptLeader,
        isTeamLeader: _isTeamLeader,
        isGroupLeader: _isGroupLeader,
        userRole: widget.role,
        userDept: widget.dept,
        userSub: widget.sub,
        userLoc: widget.loc,
        userTeam: widget.team,
      );
    }

    if (d == 'Visitations and Counselling') {
      return VisitationsModule(
        logs: _logs,
        timePeriod: _timePeriod,
        level: _currentLevel,
        category: _visitationCategories.isNotEmpty ? _visitationCategories.first : 'All',
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _selectedLocation ?? '',
        selectedSubLocation: _selectedSubLocation ?? '',
        selectedDepartment: _selectedDepartment ?? '',
        selectedTeam: _selectedTeam ?? '',
        activeUnitLabel: _getActiveUnitDisplayLabel(),
        isChurchWide: _isChurchWideCompiler,
        isLocationLeader: _isLocationLeader,
        isSubLocationLeader: _isSubLocationLeader,
        isDeptLeader: _isDeptLeader,
        isTeamLeader: _isTeamLeader,
        isGroupLeader: _isGroupLeader,
        userRole: widget.role,
        userDept: widget.dept,
        userSub: widget.sub,
        userLoc: widget.loc,
        userTeam: widget.team,
      );
    }

    if (d == 'Evangelism Results' || d == 'BB Results') {
      return EvangelismResultsModule(
        bbData: _logs,
        logs: _logs,
        timePeriod: _timePeriod,
        level: _currentLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _selectedLocation ?? '',
        selectedSubLocation: _selectedSubLocation ?? '',
        selectedDepartment: _selectedDepartment ?? '',
        selectedTeam: _selectedTeam ?? '',
        activeUnitLabel: _getActiveUnitDisplayLabel(),
        isChurchWide: _isChurchWideCompiler,
        isLocationLeader: _isLocationLeader,
        isSubLocationLeader: _isSubLocationLeader,
        isDeptLeader: _isDeptLeader,
        isTeamLeader: _isTeamLeader,
        isGroupLeader: _isGroupLeader,
        userRole: widget.role,
        userDept: widget.dept,
        userSub: widget.sub,
        userLoc: widget.loc,
        userTeam: widget.team,
      );
    }
    if (d == 'Growth Tracking') {
      return GrowthTrackingModule(
        category: d,
        logs: _logs,
        timePeriod: _timePeriod,
        level: _currentLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _selectedLocation ?? '',
        selectedSubLocation: _selectedSubLocation ?? '',
        selectedDepartment: _selectedDepartment ?? '',
        selectedTeam: _selectedTeam ?? '',
        activeUnitLabel: _getActiveUnitDisplayLabel(),
        isChurchWide: _isChurchWideCompiler,
        isLocationLeader: _isLocationLeader,
        isSubLocationLeader: _isSubLocationLeader,
        isDeptLeader: _isDeptLeader,
        isTeamLeader: _isTeamLeader,
        isGroupLeader: _isGroupLeader,
        userRole: widget.role,
        userDept: widget.dept,
        userSub: widget.sub,
        userLoc: widget.loc,
        userTeam: widget.team,
      );
    }
    return const Center(child: Text("Module logic pending..."));
  }

  Widget _buildGrowthCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: Colors.black, width: 1.0), 
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Growth Performance Metrics", style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black87)),
                  const SizedBox(height: 2),
                  Text(_timePeriod, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: pPurple)),
                ],
              ),
              InkWell(
                onTap: _showAiExecutiveReportDialog,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: pPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: pPurple.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: pPurple, size: 14),
                      const SizedBox(width: 4),
                      Text("AI Analysis", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 10),
          Row(
            children: [
              _metricPill(_primaryLabel, _primaryGrowth, isPercentage: true),
              const SizedBox(width: 8),
              _metricPill(_secondaryLabel, _secondaryGrowth, isPercentage: _secondaryLabel.contains('Growth') || _secondaryLabel.contains('Rate')),
              const SizedBox(width: 8),
              _metricPill(_tertiaryLabel, _tertiaryGrowth, isInverse: _tertiaryLabel.contains('Absentees') || _tertiaryLabel.contains('Support') || _tertiaryLabel.contains('Missed')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricPill(String title, double value, {bool isPercentage = false, bool isInverse = false}) {
    bool isPositive = value >= 0;
    Color color = isPositive 
        ? (isInverse ? Colors.red.shade700 : Colors.green.shade700) 
        : (isInverse ? Colors.green.shade700 : Colors.red.shade700);

    String sign = value > 0 ? "+" : "";
    String display = isPercentage ? "$sign${value.toStringAsFixed(1)}%" : "${value.toInt()}";

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.merriweather(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(display, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }

  void _showAiExecutiveReportDialog() {
    final period = _timePeriod;
    final duty = widget.selectedDuty;

    final Map<String, List<dynamic>> unitMap = {};
    for (var l in _logs) {
      final u = (l['unit_name'] ?? l['cell_group'] ?? l['department'] ?? 'Other').toString();
      unitMap.putIfAbsent(u, () => []).add(l);
    }

    final List<Map<String, dynamic>> unitRanks = [];
    unitMap.forEach((u, lList) {
      int att = lList.where((x) => x['attendance_realtime'] != 'Absentee' && (x['status_detail'] ?? '').toString().toLowerCase() != 'absence').length;
      double pct = lList.isNotEmpty ? (att / lList.length * 100.0) : 0.0;
      unitRanks.add({'unit': u, 'total': lList.length, 'att': att, 'pct': pct});
    });

    unitRanks.sort((a, b) => (b['pct'] as double).compareTo(a['pct'] as double));
    final topUnits = unitRanks.take(3).map((e) => "${e['unit']} (${(e['pct'] as double).toStringAsFixed(1)}%)").toList();
    final bottomUnits = unitRanks.reversed.take(3).map((e) => "${e['unit']} (${(e['pct'] as double).toStringAsFixed(1)}%)").toList();

    final Set<String> rawFindings = {};
    for (var l in _logs) {
      final n = (l['correction_note'] ?? l['situation_notes'] ?? '').toString().trim();
      if (n.isNotEmpty && n != 'null') rawFindings.add(n);
    }
    final findingsSummary = rawFindings.isNotEmpty 
        ? rawFindings.take(4).join("\n• ") 
        : "Regular unit tracking maintained with ongoing pastoral check-ins.";

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: Container(
          width: 580,
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: pPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.psychology_alt_rounded, color: pPurple, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("AI Executive Performance Report", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: pPurple)),
                            Text("$duty • $period", style: GoogleFonts.merriweather(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ],
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: Colors.black26),
                const SizedBox(height: 12),

                _reportSection("1. Executive Summary", 
                  "During the $period period for $duty, total submissions reached ${_logs.length} records. "
                  "Primary metric performance trend is recorded at ${_primaryGrowth >= 0 ? '+' : ''}${_primaryGrowth.toStringAsFixed(1)}% compared to the previous period.",
                  Icons.analytics_outlined
                ),

                _reportSection("2. Benchmark Leading Units", 
                  topUnits.isNotEmpty ? "The top-performing units setting the standard are:\n• ${topUnits.join('\n• ')}" : "All units currently performing at parity.",
                  Icons.stars_rounded, color: Colors.green.shade800
                ),

                _reportSection("3. Critical Focus & Support Required", 
                  bottomUnits.isNotEmpty ? "The following units require immediate pastoral and administrative intervention:\n• ${bottomUnits.join('\n• ')}" : "No units critically behind threshold.",
                  Icons.warning_amber_rounded, color: Colors.red.shade800
                ),

                _reportSection("4. Synthesis of Unit Leader Findings", 
                  "• $findingsSummary",
                  Icons.comment_bank_outlined
                ),

                _reportSection("5. Actionable Directive for Senior Leadership", 
                  "Recommended focus for the upcoming week:\n"
                  "1. Conduct targeted one-on-one reviews with cell leaders of trailing units.\n"
                  "2. Deploy experienced workers to assist units requiring support.\n"
                  "3. Implement absentee recovery check-ins prior to the next service session.",
                  Icons.assignment_turned_in_outlined, color: pPurple
                ),

                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Close", style: GoogleFonts.merriweather(color: Colors.grey.shade700))),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: pPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: const BorderSide(color: Colors.black, width: 1.0),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: Text("Download PDF Report", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () => _exportAiReportPdf(duty, period, topUnits, bottomUnits, findingsSummary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reportSection(String title, String body, IconData icon, {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (color ?? pPurple).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (color ?? pPurple).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color ?? pPurple),
              const SizedBox(width: 8),
              Text(title, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.w900, color: color ?? Colors.black87)),
            ],
          ),
          const SizedBox(height: 6),
          Text(body, style: GoogleFonts.merriweather(fontSize: 11.5, color: Colors.black87, height: 1.4)),
        ],
      ),
    );
  }

  Future<void> _exportAiReportPdf(String duty, String period, List<String> top, List<String> bottom, String findings) async {
    final pdf = pw.Document();
    final fontBold = await PdfGoogleFonts.merriweatherBold();
    final font = await PdfGoogleFonts.merriweatherRegular();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Executive AI Strategic Performance Report', style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.purple900)),
                    pw.Text(DateFormat('yyyy-MM-dd').format(DateTime.now()), style: pw.TextStyle(font: font, fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Duty: $duty | Period: $period | Submissions: ${_logs.length}', style: pw.TextStyle(font: font, fontSize: 9.5, color: PdfColors.grey700)),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 10),

              pw.Text('1. Performance Metrics Overview', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.purple900)),
              pw.Bullet(text: '$_primaryLabel: ${_primaryGrowth >= 0 ? "+" : ""}${_primaryGrowth.toStringAsFixed(1)}%', style: pw.TextStyle(font: font, fontSize: 9.5)),
              pw.Bullet(text: '$_secondaryLabel: ${_secondaryGrowth.toStringAsFixed(1)}', style: pw.TextStyle(font: font, fontSize: 9.5)),
              pw.Bullet(text: '$_tertiaryLabel: ${_tertiaryGrowth.toStringAsFixed(1)}', style: pw.TextStyle(font: font, fontSize: 9.5)),
              pw.SizedBox(height: 10),

              pw.Text('2. Top Performing Units', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.green900)),
              ...top.map((e) => pw.Bullet(text: e, style: pw.TextStyle(font: font, fontSize: 9.5))),
              pw.SizedBox(height: 10),

              pw.Text('3. Units Requiring Urgent Support', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.red900)),
              ...bottom.map((e) => pw.Bullet(text: e, style: pw.TextStyle(font: font, fontSize: 9.5))),
              pw.SizedBox(height: 10),

              pw.Text('4. Synthesis of Lower Leader Findings', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.purple900)),
              pw.Text(findings, style: pw.TextStyle(font: font, fontSize: 9.5)),
              pw.SizedBox(height: 10),

              pw.Text('5. Strategic Action Directives for Next Week', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.purple900)),
              pw.Bullet(text: 'Conduct one-on-one pastoral interviews with leaders of bottom-performing units.', style: pw.TextStyle(font: font, fontSize: 9.5)),
              pw.Bullet(text: 'Cross-deploy successful evangelism strategies to underperforming areas.', style: pw.TextStyle(font: font, fontSize: 9.5)),
              pw.Bullet(text: 'Submit targeted absentee intervention status prior to mid-week service.', style: pw.TextStyle(font: font, fontSize: 9.5)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Widget _buildSidebarContent() {
    bool isMobile = MediaQuery.of(context).size.width < 900;
    return Container(
      width: isMobile ? null : 310,
      decoration: BoxDecoration(
        color: Colors.white,
        border: isMobile ? null : const Border(right: BorderSide(color: Colors.black, width: 1.0)),
      ),
      child: Column(children: [
        if (isMobile)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.black26, width: 1.0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, color: pPurple, size: 20),
                    const SizedBox(width: 8),
                    Text("Analytics filters", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: pPurple, fontSize: 16)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22, color: Colors.black87),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Column(children: [
              if (_hasDualModeForCurrentDuty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purple.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_getDualModeTitle(), style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: pPurple)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _dualModeIsChurch = true;
                                  _setHierarchy();
                                });
                                _fetchData();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: _dualModeIsChurch ? pPurple : Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: Text("Church Reports", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dualModeIsChurch ? Colors.white : Colors.black87)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _dualModeIsChurch = false;
                                  _setHierarchy();
                                });
                                _fetchData();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: !_dualModeIsChurch ? pPurple : Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: Text("Dept Reports", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: !_dualModeIsChurch ? Colors.white : Colors.black87)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              _bentoNavCard("Data category", _timeOptions, _timePeriod, (v) async {
                if (v == 'Custom period') {
                  final p = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime.now());
                  if (p != null) { setState(() { _customRange = p; _timePeriod = v; }); _fetchData(); }
                } else { setState(() => _timePeriod = v); _fetchData(); }
                if (isMobile) Navigator.pop(context);
              }),
              const SizedBox(height: 10),

              _bentoNavCard("Analytics mode", _modeOptions, _analyticsMode, (v) { 
                setState(() => _analyticsMode = v);
                if (isMobile) Navigator.pop(context);
              }),
              const SizedBox(height: 10),

              _buildUnitNavigationCard(),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(15),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF3E5F5), 
                foregroundColor: pPurple, 
                elevation: 0, 
                side: const BorderSide(color: Colors.black, width: 1.0),
                padding: const EdgeInsets.symmetric(vertical: 16), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => CompilationResultsList(logs: _logs, selectedDuty: widget.selectedDuty, role: widget.role))), 
              icon: const Icon(Icons.list_alt_rounded), 
              label: Text("Detailed results", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13))
            ),
          ),
        ),
      ]),
    );
  }

  // --- UNIT NAVIGATION CARD WITH CASCADING NESTED PICKERS ---
  Widget _buildUnitNavigationCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(15), 
        border: Border.all(color: Colors.black, width: 1.0),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Unit navigation", style: GoogleFonts.merriweather(fontSize: 14.5, fontWeight: FontWeight.w900, color: Colors.black87)),
              Icon(Icons.tune_rounded, size: 16, color: pPurple),
            ],
          ),
          const Divider(height: 16, color: Colors.black26),
          ..._hierarchy.map((levelName) {
            bool isSelected = _currentLevel == levelName;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _currentLevel = levelName;
                        _updateGroupByFromLevel(levelName);
                      });
                      _fetchData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? pPurple : const Color(0xFFFBFBFE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? Colors.white : Colors.grey, size: 14),
                          const SizedBox(width: 8),
                          Expanded(child: Text(levelName, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87))),
                          if (isSelected) const Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),

                // CASCADING PICKER APPEARS RIGHT BENEATH SELECTED UNIT IN SIDEBAR
                if (isSelected)
                  _buildCascadingPicker(levelName),
              ],
            );
          }),
        ],
      ),
    );
  }

  // --- CASCADING PICKER STYLES PRESERVED EXACTLY ---
  Widget _buildCascadingPicker(String levelName) {
    final lvl = levelName.toLowerCase();

    Widget pick(String label, List<String> items, String? current, ValueChanged<String> onSelect) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: pPurple)),
          const SizedBox(height: 3),
          _unitDropdown(items, current, onSelect),
          const SizedBox(height: 6),
        ],
      );
    }

    final locPicker = pick("Select location:", _locations, _selectedLocation, (v) {
      setState(() => _selectedLocation = v);
      _fetchSubLocations(v, triggerFetch: true);
    });

    final subPicker = pick("Select sub-location:", _subLocations, _selectedSubLocation, (v) {
      setState(() => _selectedSubLocation = v);
      _fetchDepartments(v, triggerFetch: true);
    });

    final deptPicker = pick("Select department:", _departments, _selectedDepartment, (v) {
      setState(() => _selectedDepartment = v);
      _fetchTeams(v, triggerFetch: true);
    });

    final teamPicker = pick("Select team:", _teams, _selectedTeam, (v) {
      setState(() => _selectedTeam = v);
      _fetchData();
    });

    // 1. Group Leaders: Shows Location Picker directly underneath Sub location status
    if (_isGroupLeader) {
      if (lvl.contains('group')) {
        return _infoText("Displaying summary for $_groupLeaderCleanDept across all locations");
      }
      if (lvl.contains('location status')) {
        return _infoText("Displaying $_groupLeaderCleanDept performance by location");
      }
      if (lvl.contains('sub location') || lvl.contains('sub-location')) {
        return _pickerContainer([locPicker]);
      }
      if (lvl.contains('team')) {
        return _pickerContainer([locPicker, subPicker]);
      }
      if (lvl.contains('cell')) {
        return _pickerContainer([locPicker, subPicker, teamPicker]);
      }
    }

    if (_is24DeptWorker || (_hasDualModeForCurrentDuty && !_dualModeIsChurch)) {
      if (lvl.contains('dept')) return _infoText("Displaying summary for ${widget.dept.isNotEmpty ? widget.dept : 'your department'} at Church");
    }

    if (_isLocationLeader) {
      if (lvl.contains('location status')) return _infoText("Displaying summary for your location (${widget.loc})");
      if (lvl.contains('sub location') || lvl.contains('sub-location')) return _infoText("Displaying all sub-locations under ${widget.loc}");
      if (lvl.contains('dept')) return _pickerContainer([subPicker]);
      if (lvl.contains('team')) return _pickerContainer([subPicker, deptPicker]);
      if (lvl.contains('cell')) return _pickerContainer([subPicker, deptPicker, teamPicker]);
    }

    if (_isSubLocationLeader) {
      if (lvl.contains('sub location') || lvl.contains('sub-location')) return _infoText("Displaying summary for ${widget.sub}");
      if (lvl.contains('dept')) return _infoText("Displaying departments under ${widget.sub}");
      if (lvl.contains('team')) return _pickerContainer([deptPicker]);
      if (lvl.contains('cell')) return _pickerContainer([deptPicker, teamPicker]);
    }

    if (_isDeptLeader) {
      if (lvl.contains('sub location') || lvl.contains('sub-location')) {
        return _pickerContainer([subPicker]);
      }
      if (lvl.contains('dept')) return _infoText("Displaying summary for ${widget.dept}");
      if (lvl.contains('team')) return _pickerContainer([subPicker, teamPicker]);
      if (lvl.contains('cell')) return _pickerContainer([subPicker, teamPicker]);
    }

    if (_isTeamLeader) {
      if (lvl.contains('team')) return _infoText("Displaying summary for your team (${widget.team})");
      if (lvl.contains('cell')) return _infoText("Displaying cell groups under ${widget.team}");
    }

    if (_isChurchWideCompiler) {
      if (lvl.contains('church')) return _infoText("Displaying general church summary (All Locations, MOU, Church Workers)");
      if (lvl.contains('group')) return _infoText("Displaying groups based on Book of Life (교역자, 자문회, 장년회, 부녀회, 청년회)");
      if (lvl.contains('sub location') || lvl.contains('sub-location')) return _pickerContainer([locPicker]);
      if (lvl.contains('location status')) return _infoText("Displaying all church locations including MOU and 24 Dept");
      if (lvl.contains('dept')) return _pickerContainer([locPicker, subPicker]);
      if (lvl.contains('team')) return _pickerContainer([locPicker, subPicker, deptPicker]);
      if (lvl.contains('cell')) return _pickerContainer([locPicker, subPicker, deptPicker, teamPicker]);
    }

    return const SizedBox.shrink();
  }

  Widget _infoText(String text) => Padding(
    padding: const EdgeInsets.only(left: 14, bottom: 8, top: 2),
    child: Text(text, style: GoogleFonts.merriweather(fontSize: 10, color: pPurple, fontStyle: FontStyle.italic)),
  );

  Widget _pickerContainer(List<Widget> children) => Container(
    margin: const EdgeInsets.only(left: 14, right: 4, bottom: 8),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: const Color(0xFFF3E5F5), borderRadius: BorderRadius.circular(8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _unitDropdown(List<String> items, String? selected, ValueChanged<String> onChanged) {
    if (items.isEmpty) {
      return Text("No units available in this scope", style: GoogleFonts.merriweather(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic));
    }
    String val = (selected != null && items.contains(selected)) ? selected : items.first;
    return Container(
      height: 32,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.purple.shade200)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          isExpanded: true,
          value: val,
          items: items.map((u) => DropdownMenuItem(value: u, child: Text(u, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  Widget _bentoNavCard(String t, List<String> items, String cur, Function(String) onS) => Container(
    margin: const EdgeInsets.only(bottom: 2),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white, 
      borderRadius: BorderRadius.circular(15), 
      border: Border.all(color: Colors.black, width: 1.0),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))]
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: GoogleFonts.merriweather(fontSize: 14.5, fontWeight: FontWeight.w900, color: Colors.black87)),
      const Divider(height: 16, color: Colors.black26),
      ...items.map((i) => Padding(padding: const EdgeInsets.only(bottom: 3), child: InkWell(onTap: () => onS(i), child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: cur == i ? pPurple : const Color(0xFFFBFBFE), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(cur == i ? Icons.check_circle : Icons.circle_outlined, color: cur == i ? Colors.white : Colors.grey, size: 14),
          const SizedBox(width: 8),
          Expanded(child: Text(i, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: cur == i ? Colors.white : Colors.black87))),
        ]),
      ))))
    ]),
  );

  Widget _buildAnalysisBox() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), 
    decoration: BoxDecoration(
      color: Colors.white, 
      borderRadius: BorderRadius.circular(16), 
      border: Border.all(color: Colors.black, width: 1.0),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))]
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, 
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _getFindingsTitle(), 
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: Colors.black87, fontSize: 14)
            ),
            Icon(Icons.rate_review_outlined, color: pPurple, size: 18),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _analysisController, 
          minLines: 3,
          maxLines: 5, 
          style: GoogleFonts.merriweather(fontSize: 13), 
          decoration: InputDecoration(
            hintText: "Enter analysis, unit status observations, or remarks here...", 
            hintStyle: GoogleFonts.merriweather(fontSize: 12, color: Colors.black38),
            filled: true, 
            fillColor: const Color(0xFFFBFBFE), 
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), 
              borderSide: const BorderSide(color: Colors.black38, width: 1.0),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), 
              borderSide: const BorderSide(color: Colors.black26, width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), 
              borderSide: BorderSide(color: pPurple, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight, 
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: pPurple, 
              foregroundColor: Colors.white, 
              elevation: 0,
              side: const BorderSide(color: Colors.black, width: 1.0),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ), 
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Findings submitted successfully")),
              );
            }, 
            icon: const Icon(Icons.send_rounded, size: 14),
            label: Text("Submit findings", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ),
      ],
    ),
  );
}