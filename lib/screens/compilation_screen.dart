// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:master_admin/compilation_modules/evangelism_results_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

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
  double _growthTrend = 0.0;

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

  // --- ROLE IDENTIFIERS ---
  bool get _isGroupLeader {
    String r = widget.role.toLowerCase();
    String d = widget.dept.trim().toLowerCase();
    return r.contains('group') || 
           r.contains('general_dept') ||
           r.contains('new_saints') ||
           d.contains('새신자') ||
           ((widget.loc.isEmpty || widget.loc.toLowerCase() == 'church') && 
            (d.contains('장년') || d.contains('부녀') || d.contains('청년') || d.contains('신학')));
  }

  bool get _isChurchWideCompiler {
    if (_isGroupLeader) return false;
    String r = widget.role.toLowerCase();
    String l = widget.loc.trim().toLowerCase();
    return l == 'church' ||
           l.isEmpty ||
           r == 'admin' ||
           r.startsWith('church_') ||
           r.startsWith('korean_worker_') ||
           r.contains('_dept_') ||
           r.contains('internal_affairs');
  }

  bool get _isLocationLeader {
    String r = widget.role.toLowerCase();
    return !_isChurchWideCompiler && !_isGroupLeader && (r.contains('location') || r.contains('loc_')) && !r.contains('sub_loc');
  }

  bool get _isSubLocationLeader {
    String r = widget.role.toLowerCase();
    return !_isChurchWideCompiler && !_isGroupLeader && (r.contains('sub_location') || r.contains('sub_loc') || r.contains('sublocation'));
  }

  bool get _isDeptLeader {
    String r = widget.role.toLowerCase();
    return !_isChurchWideCompiler && !_isGroupLeader && !_isLocationLeader && !_isSubLocationLeader && (r.contains('dept') || r.contains('department'));
  }

  bool get _isTeamLeader {
    String r = widget.role.toLowerCase();
    return !_isChurchWideCompiler && !_isGroupLeader && !_isLocationLeader && !_isSubLocationLeader && !_isDeptLeader && r.contains('team');
  }

  @override
  void initState() {
    super.initState();
    _setHierarchy();
    _initHierarchyAndData();
  }

  Future<void> _initHierarchyAndData() async {
    await _loadUIConfig();
    await _fetchInitialLocations();
    await _fetchData();
  }

  void _setHierarchy() {
    if (_isGroupLeader) {
      _hierarchy = ['Group status', 'Location status', 'Sub location status', 'Team status', 'Cell status'];
    } else if (_isChurchWideCompiler) {
      _hierarchy = ['Church status', 'Group status', 'Location status', 'Sub location status', 'Dept status', 'Team status', 'Cell status'];
    } else if (_isLocationLeader) {
      _hierarchy = ['Location status', 'Sub location status', 'Dept status', 'Team status', 'Cell status'];
    } else if (_isSubLocationLeader) {
      _hierarchy = ['Sub location status', 'Dept status', 'Team status', 'Cell status'];
    } else if (_isDeptLeader) {
      _hierarchy = ['Dept status', 'Team status', 'Cell status'];
    } else if (_isTeamLeader) {
      _hierarchy = ['Team status', 'Cell status'];
    } else {
      _hierarchy = ['Cell status'];
    }
    _currentLevel = _hierarchy.first;
    _updateGroupByFromLevel(_currentLevel);
  }

  void _updateGroupByFromLevel(String level) {
    if (level.contains('Cell')) _groupBy = 'Cell';
    else if (level.contains('Team')) _groupBy = 'Team';
    else if (level.contains('Dept')) _groupBy = 'Dept';
    else if (level.contains('Sub location')) _groupBy = 'Sub-loc';
    else if (level.contains('Location')) _groupBy = 'Loc';
    else if (level.contains('Group')) _groupBy = 'Group';
    else _groupBy = 'Church';
  }

  Future<void> _fetchInitialLocations() async {
    try {
      final data = await _supabase.from('locations').select('id, location').order('location');
      if (!mounted) return;
      setState(() {
        _locationData = List<Map<String, dynamic>>.from(data);
        _locations = _locationData
            .map((e) => e['location'].toString())
            .where((l) => l.toLowerCase() != 'church')
            .toList();

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
      final match = _locationData.firstWhere((e) => e['location'] == locName, orElse: () => {});
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
    if (d == 'Offering Status') return 'logs_offering';
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

      dynamic buildQuery(DateTime? start, DateTime? end, {bool isPrev = false}) {
        dynamic q = _supabase.from(table).select('*, members!inner(*)');
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

        // GROUP LEADER LOCK: Restrict data strictly to their group
        if (_isGroupLeader && widget.dept.isNotEmpty) {
          q = q.eq('members.department', widget.dept);
        }

        // ROLE CONSTRAINTS FOR LOCAL WORKERS
        if (!_isChurchWideCompiler && !_isGroupLeader) {
          String r = widget.role.toLowerCase();
          if (r.contains('cell')) q = q.eq('unit_name', widget.userUnit);
          else if (r.contains('team')) q = q.eq('members.team', widget.userUnit);
          else if (r.contains('dept')) q = q.eq('members.department', widget.userUnit);
          else if (r.contains('sub_loc')) q = q.eq('members.sub_location', widget.userUnit);
          else if (r.contains('loc')) q = q.eq('members.location', widget.userUnit);
        }

        // DRILL-DOWN FILTERS
        if (lvl.contains('sub location') || lvl.contains('sub-location') || lvl.contains('team') || lvl.contains('cell')) {
          if (_selectedLocation != null && _selectedLocation!.isNotEmpty && _selectedLocation != 'Church') {
            q = q.eq('members.location', _selectedLocation!);
          }
        }
        if (lvl.contains(RegExp(r'dept|team|cell'))) {
          if (_selectedSubLocation != null && _selectedSubLocation!.isNotEmpty) {
            q = q.eq('members.sub_location', _selectedSubLocation!);
          }
        }
        if (!_isGroupLeader && lvl.contains(RegExp(r'team|cell'))) {
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

      final prevChunk = await buildQuery(bStart, bEnd, isPrev: true).limit(5000);
      final int pCount = (prevChunk as List).length;

      if (!mounted) return;

      setState(() { 
        _logs = allCurrentLogs; 
        _growthTrend = pCount > 0 ? ((_logs.length - pCount) / pCount) * 100 : 0.0;
        _isLoading = false; 
      });
    } catch (e) { 
      debugPrint("Compilation Query Error: $e");
      if (mounted) setState(() => _isLoading = false); 
    }
  }

  String _getActiveUnitDisplayLabel() {
    final lvl = _currentLevel.toLowerCase();
    if (_isGroupLeader) {
      if (lvl.contains('group')) return widget.dept;
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
    if (d == 'Offering') {
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
    bool up = _growthTrend >= 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(15), 
        border: Border.all(color: Colors.black, width: 1.0), 
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Growth performance", style: GoogleFonts.merriweather(fontSize: 14.5, fontWeight: FontWeight.w900, color: Colors.black87)),
            const SizedBox(height: 2),
            Text(_timePeriod, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: pPurple)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: up ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Text("${up ? '+' : ''}${_growthTrend.toStringAsFixed(1)}%", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: up ? Colors.green[800] : Colors.red[800], fontSize: 16)),
        )
      ]),
    );
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
        if (isMobile) DrawerHeader(child: Center(child: Text("Analytics filters", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: pPurple, fontSize: 18)))),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Column(children: [
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

                if (isSelected)
                  _buildCascadingPicker(levelName),
              ],
            );
          }),
        ],
      ),
    );
  }

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

    // ─────────────────────────────────────────────────────────────────────────
    // 1. GROUP LEADER / NEW SAINTS
    // ─────────────────────────────────────────────────────────────────────────
    if (_isGroupLeader) {
      if (lvl.contains('group')) {
        return _infoText("Displaying general summary for ${widget.dept}");
      }
      if (lvl.contains('location status')) {
        return _infoText("Displaying ${widget.dept} performance across all locations");
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

    // ─────────────────────────────────────────────────────────────────────────
    // 2. LOCATION LEADER (Restricted to widget.loc)
    // ─────────────────────────────────────────────────────────────────────────
    if (_isLocationLeader) {
      if (lvl.contains('location status')) return _infoText("Displaying summary for your location (${widget.loc})");
      if (lvl.contains('sub location') || lvl.contains('sub-location')) return _infoText("Displaying all sub-locations under ${widget.loc}");
      if (lvl.contains('dept')) return _pickerContainer([subPicker]);
      if (lvl.contains('team')) return _pickerContainer([subPicker, deptPicker]);
      if (lvl.contains('cell')) return _pickerContainer([subPicker, deptPicker, teamPicker]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. SUB-LOCATION LEADER
    // ─────────────────────────────────────────────────────────────────────────
    if (_isSubLocationLeader) {
      if (lvl.contains('sub location') || lvl.contains('sub-location')) return _infoText("Displaying summary for ${widget.sub}");
      if (lvl.contains('dept')) return _infoText("Displaying departments under ${widget.sub}");
      if (lvl.contains('team')) return _pickerContainer([deptPicker]);
      if (lvl.contains('cell')) return _pickerContainer([deptPicker, teamPicker]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. DEPT LEADER
    // ─────────────────────────────────────────────────────────────────────────
    if (_isDeptLeader) {
      if (lvl.contains('dept')) return _infoText("Displaying summary for ${widget.dept}");
      if (lvl.contains('team')) return _infoText("Displaying teams under ${widget.dept}");
      if (lvl.contains('cell')) return _pickerContainer([teamPicker]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. TEAM LEADER
    // ─────────────────────────────────────────────────────────────────────────
    if (_isTeamLeader) {
      if (lvl.contains('team')) return _infoText("Displaying summary for your team (${widget.team})");
      if (lvl.contains('cell')) return _infoText("Displaying cell groups under ${widget.team}");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 6. CHURCH-WIDE COMPILER
    // ─────────────────────────────────────────────────────────────────────────
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
    padding: const EdgeInsets.all(20), 
    decoration: BoxDecoration(
      color: Colors.white, 
      borderRadius: BorderRadius.circular(20), 
      border: Border.all(color: Colors.black, width: 1.0),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))]
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_getFindingsTitle(), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: Colors.black87, fontSize: 14.5)),
      const SizedBox(height: 10),
      TextField(
        controller: _analysisController, 
        maxLines: 3, 
        style: GoogleFonts.merriweather(fontSize: 13), 
        decoration: InputDecoration(
          hintText: "Enter findings here...", 
          filled: true, 
          fillColor: const Color(0xFFFBFBFE), 
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black38, width: 0.8))
        )
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerRight, 
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: pPurple, 
            foregroundColor: Colors.white, 
            side: const BorderSide(color: Colors.black, width: 1.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
          ), 
          onPressed: () {}, 
          child: Text("Submit findings", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 12))
        )
      )
    ]),
  );
}