// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import '../core/group_scope.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import '../core/compilation_style.dart';

import '../compilation_modules/service_attendance_module.dart';
import '../compilation_modules/cell_service_module.dart';
import '../compilation_modules/workers_education_module.dart';
import '../compilation_modules/all_saints_education_module.dart';
import '../compilation_modules/offering_module.dart';
import '../compilation_modules/evangelism_module.dart';
import '../compilation_modules/evangelism_results_module.dart';
import '../compilation_modules/daily_participation_module.dart';
import '../compilation_modules/morning_light_module.dart';
import '../compilation_modules/visitations_module.dart';
import '../compilation_modules/growth_tracking_module.dart';
import 'compilation_results_list.dart';
import '../core/compilation_rules.dart';
import '../core/table_export.dart';
import 'package:master_admin/core/app_palette.dart';
import '../widgets/app_menus.dart';
import 'package:master_admin/core/offering_categories.dart';

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
  final FocusNode _findingsFocus = FocusNode();
  List<Map<String, dynamic>> _recentFindings = []; // findings already submitted for this duty + unit

  List<String> _timeOptions = ["Current status", "Weekly status", "Monthly status", "Custom period"];
  List<String> _modeOptions = ["Summary", "Ranking", "Trend Analysis"];
  List<String> _visitationCategories = ["Lta", "H.m", "Offline", "Offering", "Evangelism"];
  List<String> _analysisDirectives = [];
  
  String _timePeriod = 'Weekly status';
  String _analyticsMode = 'Summary'; 
  String _groupBy = 'Church'; 
  String _currentLevel = 'Church status';
  DateTimeRange? _customRange;
  late List<String> _hierarchy;
  bool _isLoading = true;
  bool _includePending = false; // compile approved reports only unless switched on
  int _fetchSeq = 0;
  String? _loadError;
  DateTime? _periodStart;
  DateTime? _periodEnd;
  bool _savingFindings = false;

  // Ranking view state (its own unit level and period)
  String? _rankLevel;
  String _rankPeriod = 'Monthly';
  List<dynamic>? _rankRows;
  bool _rankLoading = false;
  String? _rankError;
  int _rankSeq = 0;

  List<dynamic> _logs = [];
  List<Map<String, dynamic>> _masterMembers = [];

  // Dynamic Growth Metrics
  double _primaryGrowth = 0.0;
  double _secondaryGrowth = 0.0;
  double _tertiaryGrowth = 0.0;
  String _primaryLabel = "General Growth";
  String _secondaryLabel = "Active Participation";
  String _tertiaryLabel = "Support Needed";

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

  String get _scope {
    final s = (_roleMetadata?['approval_scope'] ?? '').toString().trim();
    if (s.isNotEmpty && s != 'null') return s;
    final r = widget.role.toLowerCase();
    if (r.contains('cell')) return 'cell_group';
    if (r == 'member' || r == 'saint') return 'member';
    return '';
  }

  String get _grouping => (_roleMetadata?['Grouping'] ?? '').toString();
  List<String> _subDeptNames = const [];

  /// Church-wide group this user leads (Men's, Women's, Young Adults,
  /// New Saints, Theology, MOU), or null. Group leaders are saved with
  /// department 내무부, so the department text alone made them look like
  /// Internal Affairs (with the Church / Department toggle).
  String? get _groupDept => GroupScope.detect(grouping: _grouping, role: widget.role, subDeptNames: _subDeptNames);

  // ---------------------------------------------------------------------
  // Speed: results are kept for 5 minutes (shared by every compilation
  // screen), so going back to a level / period / duty you already opened is
  // instant. The refresh button in the app bar clears it.
  // ---------------------------------------------------------------------
  static final Map<String, (DateTime, List<dynamic>)> _cache = {};
  static const Duration _cacheTtl = Duration(minutes: 5);

  Future<List<T>> _cached<T>(String key, Future<List<T>> Function() load) async {
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < _cacheTtl) {
      return List<T>.from(hit.$2);
    }
    final data = await load();
    _cache[key] = (DateTime.now(), data);
    return data;
  }

  /// Who is looking and through which scope; part of every cache key.
  String get _scopeKey => [
        widget.role, widget.loc, widget.sub, widget.dept, widget.team, widget.userUnit,
        _dualModeIsChurch, _roleMetadata?['official_dept_id'],
        _sel('loc'), _sel('sub'), _sel('dept'), _sel('team'),
      ].join('|');

  /// Reads every row of a query. The first page comes alone (most views fit
  /// in it); larger views then load 4 pages at a time instead of one by one.
  Future<List<dynamic>> _fetchAllPages(dynamic Function() build) async {
    const int pageSize = 1000;
    const int parallel = 4;
    final List<dynamic> all = List<dynamic>.from(await build().order('id').range(0, pageSize - 1) as List);
    if (all.length < pageSize) return all;
    int offset = pageSize;
    while (true) {
      final pages = await Future.wait([
        for (int i = 0; i < parallel; i++)
          (build().order('id').range(offset + i * pageSize, offset + (i + 1) * pageSize - 1) as Future)
              .then((r) => List<dynamic>.from(r as List)),
      ]);
      bool done = false;
      for (final page in pages) {
        all.addAll(page);
        if (page.length < pageSize) {
          done = true;
          break;
        }
      }
      if (done) return all;
      offset += parallel * pageSize;
    }
  }

  void _refreshData() {
    _cache.clear();
    _fetchData();
  }

  /// Level the modules group by. A group leader's "Group status" (Men's,
  /// Women's, Youth ...) is their group from the department column
  /// (장년회, 부녀회 ...), not the Book of Life groups.
  String get _moduleLevel =>
      (_isGroupLeader && CompLevel.of(_currentLevel) == CompLevel.group) ? 'Dept status' : _currentLevel;

  /// Theology Department: its dashboard toggles between its members at
  /// church level and the Theology department across the locations.
  bool get _isTheologyDept => GroupScope.deptNo(_grouping) == '18' || widget.role.toLowerCase().startsWith('theology_dept');

  bool get _isGroupLeader {
    if (_isTheologyDept) return _dualModeIsChurch; // across the locations
    if (_groupDept != null) return true;
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
    final g = _groupDept;
    if (g != null) return g;
    final r = widget.role.toLowerCase();
    if (_grouping == '24-Dept MG' || r.startsWith('mg_group')) return '장년회';
    if (_grouping == '24-Dept WG' || r.startsWith('wg_group')) return '부녀회';
    if (_grouping == '24-Dept YAG' || r.startsWith('yag_group')) return '청년회';
    if (_grouping == '24-Dept New Saints' || r.startsWith('new_saints')) return '새신자';
    if (_grouping.startsWith('24-Dept 18') || r.startsWith('theology')) return '신학부';
    if (_grouping == '24-Dept MOU' || r.startsWith('mou')) return 'MOU';
    return widget.dept.replaceAll(RegExp(r'(회장|부장|총무|서무|과장)$'), '').trim();
  }

  bool get _isInternalAffairs {
    String r = widget.role.toLowerCase();
    if (_groupDept != null) return false;
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
            GroupScope.isAdministrationGrouping(_grouping)) &&
           r != 'admin';
  }

  bool get _hasDualModeForCurrentDuty {
    final d = widget.selectedDuty.trim();
    if (_isTheologyDept) return true;
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
    if (_isTheologyDept) return "Theology Scope";
    if (_isInternalAffairs) return "Internal Affairs Scope";
    if (_isEvangelismDept) return "Evangelism Scope";
    if (_isEducationDept) return "Education Scope";
    if (_isAdministrationDept) return "Administration Scope";
    return "Report Scope";
  }

  bool get _isChurchWideCompiler {
    if (_isGroupLeader) return false;
    if (_hasDualModeForCurrentDuty) return _dualModeIsChurch;
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

  bool get _isCellLeader {
    if (_isChurchWideCompiler || _isGroupLeader || _is24DeptWorker || _isLocationLeader || _isSubLocationLeader || _isDeptLeader || _isTeamLeader) return false;
    return _scope == 'cell_group' || widget.role.toLowerCase().contains('cell');
  }

  @override
  void initState() {
    super.initState();
    _setHierarchy();
    _initHierarchyAndData();
  }

  Future<void> _initHierarchyAndData() async {
    await Future.wait([_fetchRoleMetadata(), _loadUIConfig()]);
    _setHierarchy();
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
      final subNames = await GroupScope.myDeptNames();

      if (mounted) {
        setState(() {
          if (res != null) _roleMetadata = res;
          _subDeptNames = subNames;
        });
      }
    } catch (e) {
      debugPrint("Role Metadata Fetch Error: $e");
    }
  }

  void _setHierarchy() {
    if (_isCellLeader) {
      _hierarchy = ['Cell status'];
    } else if (_isTeamLeader) {
      _hierarchy = ['Team status', 'Cell status'];
    } else if (_isDeptLeader) {
      _hierarchy = ['Dept status', 'Team status', 'Cell status'];
    } else if (_isSubLocationLeader) {
      _hierarchy = ['Sub location status', 'Dept status', 'Team status', 'Cell status'];
    } else if (_isLocationLeader) {
      // Group status = the location's members by Book of Life group (교역자, 자문회, 장년회 ...)
      _hierarchy = ['Location status', 'Group status', 'Sub location status', 'Dept status', 'Team status', 'Cell status'];
    } else if (_isGroupLeader) {
      _hierarchy = ['Group status', 'Location status', 'Sub location status', 'Team status', 'Cell status'];
    } else if (_is24DeptWorker || (_hasDualModeForCurrentDuty && !_dualModeIsChurch)) {
      _hierarchy = ['Dept status'];
    } else {
      _hierarchy = ['Church status', 'Group status', 'Location status', 'Sub location status', 'Dept status', 'Team status', 'Cell status'];
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
      _groupBy = 'Dept';
    } else if (_isSubLocationLeader && level == 'Sub location status') {
      _groupBy = 'Sub-loc';
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

  // Distinct values of a members column inside the given filters.
  // Used when a unit table has no matching row, instead of listing the
  // whole church (or made-up names like "팀1").
  Future<List<String>> _distinctMemberValues(String column, Map<String, String?> filters) async {
    final active = Map<String, String>.fromEntries(filters.entries
        .where((e) => e.value != null && e.value!.isNotEmpty && e.value != 'N/A' && e.value != 'All Locations')
        .map((e) => MapEntry(e.key, e.value!)));
    try {
      final values = await _cached<String>('distinct|$column|${active.entries.map((e) => '${e.key}=${e.value}').join('&')}', () async {
        final rows = await _fetchAllPages(() {
          dynamic q = _supabase.from('members').select(column);
          active.forEach((k, v) => q = q.eq(k, v));
          return q;
        });
        final Set<String> out = {};
        for (final r in rows) {
          final v = ((r as Map)[column] ?? '').toString().trim();
          if (v.isNotEmpty) out.add(v);
        }
        return CompLevel.naturalSort(out);
      });
      return values;
    } catch (e) {
      debugPrint("Distinct $column fetch error: $e");
      return [];
    }
  }


  Future<void> _fetchInitialLocations() async {
    try {
      if (_isLocationLeader || _isSubLocationLeader || _isDeptLeader || _isTeamLeader || _isCellLeader) {
        if (widget.loc.isNotEmpty && widget.loc != 'Church' && widget.loc != 'N/A') {
          // Load this location's row so its sub-locations can be looked up by id
          try {
            final res = await _supabase.from('locations').select('id, location').eq('location', widget.loc);
            _locationData = List<Map<String, dynamic>>.from(res);
          } catch (_) {
            _locationData = [];
          }
          if (!mounted) return;
          setState(() {
            _locations = [widget.loc];
            _selectedLocation = widget.loc;
            if (widget.sub.isNotEmpty) _selectedSubLocation = widget.sub;
            if (widget.dept.isNotEmpty) _selectedDepartment = widget.dept;
            if (widget.team.isNotEmpty) _selectedTeam = widget.team;
          });
          await _fetchSubLocations(widget.loc, triggerFetch: false);
          return;
        }
      }

      List<Map<String, dynamic>> data = [];
      try {
        final res = await _supabase.from('locations').select('id, location').order('location');
        data = List<Map<String, dynamic>>.from(res);
      } catch (_) {}

      if (data.isEmpty) {
        final names = await _distinctMemberValues('location', {});
        data = names.map((l) => <String, dynamic>{'id': null, 'location': l}).toList();
      }

      if (!mounted) return;
      setState(() {
        _locationData = data;
        // MOU branches (MOUWakiso, MOULubaga ...) are one location: "MOU"
        _locations = _locationData
            .map((e) => (e['location'] ?? '').toString())
            .where((l) => l.isNotEmpty && l.toLowerCase() != 'church' && l.toLowerCase() != 'church workers')
            .map((l) => CompLevel.isMouName(l) ? CompLevel.mou : l)
            .toSet()
            .toList();
        _locations.sort();
        if (!_locations.contains(CompLevel.mou)) _locations.add(CompLevel.mou);
        _selectedLocation = null;
      });
    } catch (e) {
      debugPrint("Compilation Location Fetch Error: $e");
    }
  }

  Future<void> _fetchSubLocations(String locName, {bool triggerFetch = true}) async {
    try {
      final match = _locationData.firstWhere(
        (e) => e['location'] == locName,
        orElse: () => <String, dynamic>{},
      );

      List<Map<String, dynamic>> data = [];
      if (locName == CompLevel.mou) {
        // MOU: every MOU sub-location (MOUNansana, MOUPallisa ...) directly under it
        final names = await _distinctMemberValues('sub_location', {'department': CompLevel.mou});
        data = names.map((n) => <String, dynamic>{'id': null, 'name': n}).toList();
      } else {
        if (match.isNotEmpty && match['id'] != null) {
          final res = await _supabase.from('sub_locations').select('id, name, is_mou').eq('location_id', match['id']).order('name');
          // MOU sub-locations belong to the MOU location, not to Wakiso etc.
          // (An MOU branch such as MOUWakiso keeps its own MOU sub-locations.)
          final bool mouBranch = CompLevel.isMouName(locName);
          data = List<Map<String, dynamic>>.from(res)
              .where((e) => mouBranch || (e['is_mou'] != true && !CompLevel.isMouName(e['name']?.toString())))
              .toList();
        }
        if (data.isEmpty) {
          // No sub_locations rows for this location: use the members' own values
          final names = await _distinctMemberValues('sub_location', {'location': locName});
          data = names
              .where((n) => CompLevel.isMouName(locName) || !CompLevel.isMouName(n))
              .map((n) => <String, dynamic>{'id': null, 'name': n})
              .toList();
        }
      }

      if (!mounted) return;
      setState(() {
        _subLocationData = data;
        _subLocations = _subLocationData.map((e) => e['name'].toString()).toSet().toList();

        if (widget.sub.isNotEmpty && _subLocations.contains(widget.sub)) {
          _selectedSubLocation = widget.sub;
        } else if (_selectedSubLocation == null || !_subLocations.contains(_selectedSubLocation)) {
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
      if (_isGroupLeader) {
        setState(() => _selectedDepartment = _groupLeaderCleanDept);
        if (_selectedDepartment != null) await _fetchTeams(_selectedDepartment!, triggerFetch: false);
        if (triggerFetch) _fetchData();
        return;
      }
      if (_isDeptLeader || _isTeamLeader) {
        setState(() => _selectedDepartment = widget.dept);
        if (_selectedDepartment != null) await _fetchTeams(_selectedDepartment!, triggerFetch: false);
        if (triggerFetch) _fetchData();
        return;
      }

      final match = _subLocationData.firstWhere((e) => e['name'] == subName, orElse: () => <String, dynamic>{});
      List<Map<String, dynamic>> data = [];
      if (_selectedLocation == CompLevel.mou || CompLevel.isMouName(subName)) {
        // MOU has a single department: MOU
        data = [<String, dynamic>{'id': null, 'name': CompLevel.mou}];
      } else if (match.isNotEmpty && match['id'] != null) {
        final res = await _supabase.from('departments').select('id, name').eq('sub_location_id', match['id']).order('name');
        data = List<Map<String, dynamic>>.from(res);
      }
      if (data.isEmpty) {
        final names = await _distinctMemberValues('department', {'location': _selectedLocation, 'sub_location': subName});
        data = names.map((n) => <String, dynamic>{'id': null, 'name': n}).toList();
      }

      if (!mounted) return;
      setState(() {
        _deptData = data;
        _departments = _deptData.map((e) => e['name'].toString()).toSet().toList();

        if (widget.dept.isNotEmpty && _departments.contains(widget.dept)) {
          _selectedDepartment = widget.dept;
        } else if (_selectedDepartment == null || !_departments.contains(_selectedDepartment)) {
          _selectedDepartment = _departments.isNotEmpty ? _departments.first : null;
        }
      });

      if (_selectedDepartment != null) {
        await _fetchTeams(_selectedDepartment!, triggerFetch: false);
      } else if (mounted) {
        setState(() {
          _teams = [];
          _selectedTeam = null;
        });
      }
      if (triggerFetch) _fetchData();
    } catch (e) {
      debugPrint("Compilation Dept Fetch Error: $e");
    }
  }

  Future<void> _fetchTeams(String deptName, {bool triggerFetch = true}) async {
    try {
      if (_isTeamLeader && widget.team.isNotEmpty) {
        setState(() {
          _teams = [widget.team];
          _selectedTeam = widget.team;
        });
        if (triggerFetch) _fetchData();
        return;
      }

      // Department ids are only known when the department came from this
      // sub-location's list; otherwise use the teams members actually have.
      final match = _deptData.firstWhere((e) => e['name'] == deptName, orElse: () => <String, dynamic>{});
      List<String> names = [];
      if (match.isNotEmpty && match['id'] != null) {
        final res = await _supabase.from('teams').select('id, name').eq('dept_id', match['id']).order('name');
        _teamData = List<Map<String, dynamic>>.from(res);
        names = _teamData.map((e) => e['name'].toString()).toList();
      }
      if (names.isEmpty) {
        final String? sub = _selectedSubLocation ?? (widget.sub.isNotEmpty ? widget.sub : null);
        names = await _distinctMemberValues('team', {
          'location': _selectedLocation == CompLevel.mou ? null : _selectedLocation,
          'sub_location': sub,
          'department': deptName,
        });
      }

      if (!mounted) return;
      setState(() {
        _teams = CompLevel.naturalSort(names.toSet());
        if (widget.team.isNotEmpty && _teams.contains(widget.team)) {
          _selectedTeam = widget.team;
        } else if (_selectedTeam == null || !_teams.contains(_selectedTeam)) {
          _selectedTeam = _teams.isNotEmpty ? _teams.first : null;
        }
      });
      if (triggerFetch) _fetchData();
    } catch (e) {
      debugPrint("Compilation Team Fetch Error: $e");
    }
  }

  // OPTION B: Loads directives and modes from compilation_ui_config
  Future<void> _loadUIConfig() async {
    try {
      final res = await _supabase.from('compilation_ui_config').select().eq('is_active', true).order('sort_order');
      if (res.isNotEmpty && mounted) {
        final List<dynamic> list = res as List<dynamic>;
        final times = list.where((e) => e['config_type'] == 'time_period').map((e) => e['label'].toString()).toList();
        final modes = list.where((e) => e['config_type'] == 'analytics_mode').map((e) => e['label'].toString()).toList();
        final vis = list.where((e) => e['config_type'] == 'visitation_category').map((e) => e['label'].toString()).toList();
        final directives = list.where((e) => e['config_type'] == 'analysis_directive').map((e) => e['label'].toString()).toList();

        setState(() {
          if (times.isNotEmpty) _timeOptions = times;
          if (modes.isNotEmpty) _modeOptions = modes;
          if (vis.isNotEmpty) _visitationCategories = vis;
          if (directives.isNotEmpty) _analysisDirectives = directives;
        });
      }
    } catch (e) {
      debugPrint("UI Config fallback: $e");
    }
  }

  String _getTargetTable() {
    String d = widget.selectedDuty.trim();
    if (d == 'Service Attendance Status') return 'logs_service_attendance_status';
    if (d == 'Cell Group Service') return 'logs_cell_service';
    if (d == 'All Saints Education') return 'logs_all_saints_education';
    if (d == 'Offering' || d == 'Offering Status') return 'logs_offering';
    if (d == 'Evangelism' || d == 'Evangelism Part') return 'logs_evangelism';
    if (d == 'Evangelism Results' || d == 'BB Results') return 'bb_students';
    if (d == 'Morning Light') return 'logs_morning_light';
    if (d == 'Visitations and Counselling') return 'logs_visitations';
    if (d == 'Workers Education') return 'logs_workers_education';
    if (d == 'Workers Daily Participation') return 'logs_workers_participation';
    if (d.contains('Growth Tracking')) return 'members';
    return 'logs_service_attendance_status';
  }

  // Columns are taken from the live tables. Asking for a column that does not
  // exist makes Supabase reject the whole query, which is why most duties
  // used to load nothing. `*` returns whatever columns each log table has.
  static const String _memberJoin =
      'members!inner(id, english_name, location, sub_location, department, team, cell_group, reg_status, geo_category, book_of_life, bol_dept, official_dept_id, is_worker, duty)';

  String _getSelectColumnsForDuty() {
    final String d = widget.selectedDuty.trim();

    if (d == 'Evangelism Results' || d == 'BB Results') {
      return '*';
    }

    if (d.contains('Growth Tracking')) {
      return 'id, english_name, location, sub_location, department, team, cell_group, '
          'reg_status, geo_category, book_of_life, bol_dept, official_dept_id, duty, is_worker, created_at';
    }

    return '*, $_memberJoin';
  }

  bool get _usesApproval {
    final t = _getTargetTable();
    return t != 'bb_students' && t != 'members';
  }

  // ---------------------------------------------------------------------
  // Which unit pickers apply at a level. The query, the modules and the
  // sidebar all read this, so a selection only filters data when its
  // picker is actually visible (stale picks no longer hide data).
  // ---------------------------------------------------------------------
  Set<String> _pickersFor(String lv) {
    if (_isGroupLeader) {
      if (lv == CompLevel.location || lv == CompLevel.subLocation) return {'loc'};
      if (lv == CompLevel.team) return {'loc', 'sub'};
      if (lv == CompLevel.cell) return {'loc', 'sub', 'team'};
      return {};
    }
    if (_is24DeptWorker || (_hasDualModeForCurrentDuty && !_dualModeIsChurch)) return {};
    if (_isLocationLeader) {
      if (lv == CompLevel.dept) return {'sub'};
      if (lv == CompLevel.team) return {'sub', 'dept'};
      if (lv == CompLevel.cell) return {'sub', 'dept', 'team'};
      return {};
    }
    if (_isSubLocationLeader) {
      if (lv == CompLevel.team) return {'dept'};
      if (lv == CompLevel.cell) return {'dept', 'team'};
      return {};
    }
    if (_isDeptLeader) {
      if (lv == CompLevel.cell) return {'team'};
      return {};
    }
    if (_isTeamLeader || _isCellLeader) return {};
    if (_isChurchWideCompiler) {
      if (lv == CompLevel.subLocation) return {'loc'};
      if (lv == CompLevel.dept) return {'loc', 'sub'};
      if (lv == CompLevel.team) return {'loc', 'sub', 'dept'};
      if (lv == CompLevel.cell) return {'loc', 'sub', 'dept', 'team'};
    }
    return {};
  }

  /// Results By Units: the unit being looked at, level by level (location,
  /// sub-location, department, team). A picker's choice, or the leader's own
  /// unit for the levels their role fixes (a location leader's location is
  /// never a picker, but it is still their location).
  List<String> _evangelismUnitPath() {
    bool ok(String v) => v.isNotEmpty && v != 'N/A' && v != 'Church';
    String pick(String picker, String own, bool fixed) {
      final s = _sel(picker);
      if (s.isNotEmpty) return s;
      return fixed && ok(own) ? own : '';
    }
    final team = _isTeamLeader || _isCellLeader;
    final dept = team || _isDeptLeader;
    final sub = dept || _isSubLocationLeader;
    final loc = sub || _isLocationLeader;
    final d = pick('dept', widget.dept, dept);
    return [
      pick('loc', widget.loc, loc),
      pick('sub', widget.sub, sub),
      d.isEmpty && _isGroupLeader ? _groupLeaderCleanDept : d,
      pick('team', widget.team, team),
    ];
  }

  /// The selection for [picker] if it applies at the current level, else ''.
  String _sel(String picker) {
    if (!_pickersFor(CompLevel.of(_currentLevel)).contains(picker)) return '';
    String? v;
    switch (picker) {
      case 'loc':
        v = _selectedLocation;
        break;
      case 'sub':
        v = _selectedSubLocation;
        break;
      case 'dept':
        v = _selectedDepartment;
        break;
      case 'team':
        v = _selectedTeam;
        break;
    }
    if (v == null || v.isEmpty || v == 'All Locations' || v == 'Church' || v == 'N/A') return '';
    return v;
  }

  String _friendlyLoadError(Object e) {
    if (e is PostgrestException) {
      if (e.code == '42703') return "The report table is missing a column this screen expects (${e.message}).";
      if (e.code == '42501') return "You don't have permission to view these reports.";
      return "Couldn't load reports: ${e.message}";
    }
    return "Couldn't load reports. Check your connection and try again.";
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    // Every call gets a number; only the newest call may update the screen,
    // so a slow older request can no longer overwrite newer filters.
    final int seq = ++_fetchSeq;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final String table = _getTargetTable();
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);
      final DateFormat df = DateFormat('yyyy-MM-dd');

      DateTime curStart;
      DateTime curEnd = today;
      DateTime prevStart;
      DateTime prevEnd;

      if (_timePeriod == "Custom period" && _customRange != null) {
        curStart = _customRange!.start;
        curEnd = _customRange!.end;
        final int days = curEnd.difference(curStart).inDays + 1;
        prevEnd = curStart.subtract(const Duration(days: 1));
        prevStart = prevEnd.subtract(Duration(days: days - 1));
      } else {
        // Weekly = Week 1..Week 5 (calendar weeks, this one included),
        // Monthly = the last 4 calendar months, Current = latest session in the
        // last 7 days. Same ranges the module charts use (CompPeriod).
        (curStart, curEnd) = CompPeriod.currentRange(_timePeriod, now);
        (prevStart, prevEnd) = CompPeriod.previousRange(_timePeriod, now);
      }
      _periodStart = curStart;
      _periodEnd = curEnd;

      final isBBTable = table == 'bb_students';
      final isMembersTable = table == 'members';
      final Set<String> pickers = _pickersFor(CompLevel.of(_currentLevel));

      dynamic buildQuery({required bool isPrev}) {
        dynamic q = _supabase.from(table).select(_getSelectColumnsForDuty());

        if (!isBBTable && !isMembersTable) {
          final DateTime sDate = isPrev ? prevStart : curStart;
          final DateTime eDate = isPrev ? prevEnd : curEnd;
          q = q.gte('report_date', df.format(sDate)).lte('report_date', df.format(eDate));
        }

        if (_usesApproval) {
          q = _includePending
              ? q.inFilter('verification_status', ['approved', 'pending'])
              : q.eq('verification_status', 'approved');
        }

        // Unit columns: reports are filtered by the member's current unit (joined
        // members table), the members table by its own columns, BB rows by the
        // guide's unit (the cell is stored in cell_name by the BB entry form).
        final String locCol = isBBTable ? 'guide_location' : (isMembersTable ? 'location' : 'members.location');
        final String subCol = isBBTable ? 'guide_sub_location' : (isMembersTable ? 'sub_location' : 'members.sub_location');
        final String deptCol = isBBTable ? 'guide_dept' : (isMembersTable ? 'department' : 'members.department');
        final String teamCol = isBBTable ? 'guide_team' : (isMembersTable ? 'team' : 'members.team');
        final String cellCol = isBBTable ? 'cell_name' : (isMembersTable ? 'cell_group' : 'members.cell_group');

        if (_isGroupLeader) {
          final deptTarget = _groupLeaderCleanDept;
          if (isBBTable || isMembersTable) {
            q = q.eq(deptCol, deptTarget);
            if (deptTarget != 'MOU') q = q.neq(locCol, 'MOU');
            if (deptTarget != '새신자') q = q.neq(locCol, 'New Saints');
            q = q.neq(locCol, 'Church Workers').neq(locCol, 'Church Main').neq(locCol, 'Church');
          } else {
            q = q.eq('members.department', deptTarget);
            if (deptTarget != 'MOU') q = q.neq('members.location', 'MOU');
            if (deptTarget != '새신자') q = q.neq('members.location', 'New Saints');
            q = q.neq('members.location', 'Church Workers')
                 .neq('members.location', 'Church Main')
                 .neq('members.location', 'Church');
          }
        } else if (_is24DeptWorker || (_hasDualModeForCurrentDuty && !_dualModeIsChurch)) {
          if (!isBBTable && !isMembersTable) {
            // Church-level members only. (The old filter mixed report and member
            // columns in one .or(), which Supabase rejects; an .or() on the joined
            // table has to name it with referencedTable.)
            q = q.or('location.in.(Church,"Church Workers","Church Main"),location.is.null', referencedTable: 'members');

            final officialDeptId = _roleMetadata?['official_dept_id'];
            if (officialDeptId != null) {
              q = q.eq('members.official_dept_id', officialDeptId);
            } else if (widget.dept.isNotEmpty && widget.dept != 'N/A' && widget.dept != 'Church') {
              q = q.eq('members.department', widget.dept);
            }
          }
        } else if (!_isChurchWideCompiler) {
          if (widget.loc.isNotEmpty && widget.loc != 'Church' && widget.loc != 'N/A') {
            q = q.eq(locCol, widget.loc);
          }
          if (_isSubLocationLeader || _isDeptLeader || _isTeamLeader) {
            if (widget.sub.isNotEmpty && widget.sub != 'N/A') q = q.eq(subCol, widget.sub);
          }
          if (_isDeptLeader || _isTeamLeader) {
            if (widget.dept.isNotEmpty && widget.dept != 'N/A') q = q.eq(deptCol, widget.dept);
          }
          if (_isTeamLeader) {
            if (widget.team.isNotEmpty && widget.team != 'N/A') q = q.eq(teamCol, widget.team);
          }
          if (_isCellLeader) {
            if (widget.userUnit.isNotEmpty) q = q.eq(cellCol, widget.userUnit);
          }
        }

        // Picker selections (only the pickers visible at this level)
        if (pickers.contains('loc') && _sel('loc').isNotEmpty) {
          // MOU members' location is their branch (MOUWakiso ...); all have department MOU
          q = _sel('loc') == CompLevel.mou ? q.eq(deptCol, CompLevel.mou) : q.eq(locCol, _sel('loc'));
        }
        if (pickers.contains('sub') && _sel('sub').isNotEmpty) q = q.eq(subCol, _sel('sub'));
        if (pickers.contains('dept') && _sel('dept').isNotEmpty) q = q.eq(deptCol, _sel('dept'));
        if (pickers.contains('team') && _sel('team').isNotEmpty) q = q.eq(teamCol, _sel('team'));

        return q;
      }

      // "Current status" keeps only the latest session. Service attendance has
      // two services a week, so it keeps the latest date; the day-based duties
      // keep the latest week (Mon..Sun rows of that week).
      List<dynamic> latestSessionOnly(List<dynamic> rows) {
        if (_timePeriod != "Current status" || isBBTable || isMembersTable) return rows;
        final bool byDate = widget.selectedDuty.trim() == 'Service Attendance Status';
        String keyOf(dynamic r) {
          final d = DateTime.tryParse((r['report_date'] ?? '').toString());
          if (d == null) return '';
          return byDate ? df.format(d) : CompPeriod.weekKey(d);
        }
        String latest = '';
        for (final r in rows) {
          final k = keyOf(r);
          if (k.compareTo(latest) > 0) latest = k;
        }
        if (latest.isEmpty) return rows;
        return rows.where((r) => keyOf(r) == latest).toList();
      }

      final String key = [table, _includePending, _scopeKey].join('|');
      final Future<List<dynamic>> curF = _cached(
          'logs|$key|${df.format(curStart)}|${df.format(curEnd)}', () => _fetchAllPages(() => buildQuery(isPrev: false)));
      final Future<List<dynamic>> prevF = (isBBTable || isMembersTable)
          ? Future.value(<dynamic>[])
          : _cached('logs|$key|${df.format(prevStart)}|${df.format(prevEnd)}',
                  () => _fetchAllPages(() => buildQuery(isPrev: true)))
              .catchError((Object e) {
              debugPrint("Compilation previous-period query error: $e");
              return <dynamic>[];
            });
      final Future<List<Map<String, dynamic>>> membersF = _fetchScopedMasterMembers();

      final List<dynamic> allCurrentLogs = latestSessionOnly(await curF);
      final List<dynamic> prevLogs = latestSessionOnly(await prevF);
      final List<Map<String, dynamic>> members = await membersF;

      if (!mounted || seq != _fetchSeq) return; // a newer request took over

      _calculateDynamicGrowthMetrics(allCurrentLogs, prevLogs);

      setState(() {
        _logs = allCurrentLogs;
        _masterMembers = members;
        CompLevel.configure(members); // repeated cell / team names get their parents
        _isLoading = false;
      });
      if (_analyticsMode.contains('Ranking')) _loadRanking();
    } catch (e) {
      debugPrint("Compilation Query Error: $e");
      if (!mounted || seq != _fetchSeq) return;
      // Clear old rows so the screen never shows the previous filter's data
      // under the new labels.
      setState(() {
        _logs = [];
        _isLoading = false;
        _loadError = _friendlyLoadError(e);
      });
    }
  }

  /// Members in the viewer's scope (the headcount for every unit).
  /// Returns the list instead of calling setState, so logs and members are
  /// always shown together from the same request.
  Future<List<Map<String, dynamic>>> _fetchScopedMasterMembers() async {
    final Set<String> pickers = _pickersFor(CompLevel.of(_currentLevel));

    dynamic build() {
      dynamic mQuery = _supabase.from('members').select(
        'id, english_name, location, sub_location, department, team, cell_group, reg_status, geo_category, book_of_life, bol_dept, official_dept_id, is_worker, duty'
      );

      if (_isGroupLeader) {
        final deptTarget = _groupLeaderCleanDept;
        mQuery = mQuery.eq('department', deptTarget);
        if (deptTarget != 'MOU') mQuery = mQuery.neq('location', 'MOU');
        if (deptTarget != '새신자') mQuery = mQuery.neq('location', 'New Saints');
        mQuery = mQuery.neq('location', 'Church Workers').neq('location', 'Church Main').neq('location', 'Church');
      } else if (_is24DeptWorker || (_hasDualModeForCurrentDuty && !_dualModeIsChurch)) {
        final officialDeptId = _roleMetadata?['official_dept_id'];
        if (officialDeptId != null) {
          mQuery = mQuery.eq('official_dept_id', officialDeptId);
        } else if (widget.dept.isNotEmpty && widget.dept != 'Church') {
          mQuery = mQuery.eq('department', widget.dept);
        }
      } else if (!_isChurchWideCompiler) {
        if (widget.loc.isNotEmpty && widget.loc != 'Church' && widget.loc != 'N/A') mQuery = mQuery.eq('location', widget.loc);
        if (_isSubLocationLeader || _isDeptLeader || _isTeamLeader) {
          if (widget.sub.isNotEmpty && widget.sub != 'N/A') mQuery = mQuery.eq('sub_location', widget.sub);
        }
        if (_isDeptLeader || _isTeamLeader) {
          if (widget.dept.isNotEmpty && widget.dept != 'N/A') mQuery = mQuery.eq('department', widget.dept);
        }
        if (_isTeamLeader) {
          if (widget.team.isNotEmpty && widget.team != 'N/A') mQuery = mQuery.eq('team', widget.team);
        }
        if (_isCellLeader) {
          if (widget.userUnit.isNotEmpty) mQuery = mQuery.eq('cell_group', widget.userUnit);
        }
      }

      if (pickers.contains('loc') && _sel('loc').isNotEmpty) {
        mQuery = _sel('loc') == CompLevel.mou ? mQuery.eq('department', CompLevel.mou) : mQuery.eq('location', _sel('loc'));
      }
      if (pickers.contains('sub') && _sel('sub').isNotEmpty) mQuery = mQuery.eq('sub_location', _sel('sub'));
      if (pickers.contains('dept') && _sel('dept').isNotEmpty) mQuery = mQuery.eq('department', _sel('dept'));
      if (pickers.contains('team') && _sel('team').isNotEmpty) mQuery = mQuery.eq('team', _sel('team'));

      return mQuery;
    }

    try {
      // Members don't depend on the period, so this is shared by every period and duty
      return await _cached<Map<String, dynamic>>('members|$_scopeKey', () async {
        final rows = await _fetchAllPages(build);
        return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      });
    } catch (e) {
      debugPrint("Master Members Fetch Error: $e");
      return [];
    }
  }

  void _calculateDynamicGrowthMetrics(List<dynamic> cur, List<dynamic> prev) {
    final d = widget.selectedDuty;

    double pctDiff(double c, double p) {
      if (p == 0) return c > 0 ? 100.0 : 0.0;
      return ((c - p) / p) * 100.0;
    }

    // Compare per-session averages, so a period with more sessions doesn't look like growth.
    final int cS = CompPeriod.sessionCount(cur);
    final int pS = CompPeriod.sessionCount(prev);
    double cAvg(int n) => n / cS;
    double pAvg(int n) => n / pS;

    // Service attendance stores the answer in attendance_realtime, the other duties in status_detail.
    dynamic answer(dynamic x) => x['attendance_realtime'] ?? x['status_detail'];
    bool inPerson(dynamic x) {
      final s = CompStatus.norm(answer(x));
      return !CompStatus.isNegative(s) && (s.contains('in-person') || s.contains('inperson') || s == 'ip');
    }

    if (d.contains('Growth Tracking')) {
      _primaryLabel = "Total Saints";
      _secondaryLabel = "Registered Saints";
      _tertiaryLabel = "Active Workers";

      int reg = cur.where((x) => x['reg_status'] == '교회등록' || x['reg_status'] == '총회등록').length;
      // is_worker is generated from duty in the database (not empty and not 구역원)
      int workers = cur.where((x) => x['is_worker'] == true).length;

      _primaryGrowth = cur.length.toDouble();
      _secondaryGrowth = reg.toDouble();
      _tertiaryGrowth = workers.toDouble();
    } else if (d == 'Evangelism Results' || d == 'BB Results') {
      _primaryLabel = "Total Fruits";
      _secondaryLabel = "Confirmed";
      _tertiaryLabel = "In Progress";

      int conf = cur.where((x) => (x['level_status'] ?? '').toString().toLowerCase() == 'confirmed').length;
      int proc = cur.where((x) => ['chakki', 'possible', 'new bb', 'proceeding'].contains((x['level_status'] ?? '').toString().toLowerCase())).length;

      _primaryGrowth = cur.length.toDouble();
      _secondaryGrowth = conf.toDouble();
      _tertiaryGrowth = proc.toDouble();
    } else if (d.contains('Attendance') || d.contains('Cell Group') || d.contains('Education')) {
      _primaryLabel = "General Att Growth";
      _secondaryLabel = "In-person Growth";
      _tertiaryLabel = "Absentees Change";

      int cAtt = cur.where((x) => CompStatus.isPositive(answer(x))).length;
      int pAtt = prev.where((x) => CompStatus.isPositive(answer(x))).length;
      int cIp = cur.where(inPerson).length;
      int pIp = prev.where(inPerson).length;
      int cAbs = cur.where((x) => CompStatus.isNegative(answer(x))).length;
      int pAbs = prev.where((x) => CompStatus.isNegative(answer(x))).length;

      _primaryGrowth = pctDiff(cAvg(cAtt), pAvg(pAtt));
      _secondaryGrowth = pctDiff(cAvg(cIp), pAvg(pIp));
      _tertiaryGrowth = pctDiff(cAvg(cAbs), pAvg(pAbs));
    } else if (d.contains('Evangelism')) {
      _primaryLabel = "Participation Growth";
      _secondaryLabel = "Evangelised (avg/week)";
      _tertiaryLabel = "Support Needed";

      int cEv = cur.where((x) => CompStatus.isPositive(x['status_detail'])).length;
      int pEv = prev.where((x) => CompStatus.isPositive(x['status_detail'])).length;

      _primaryGrowth = pctDiff(cAvg(cEv), pAvg(pEv));
      _secondaryGrowth = CompPeriod.perSession(cEv, cS).toDouble();
      _tertiaryGrowth = CompPeriod.perSession(cur.where((x) => CompStatus.isNegative(x['status_detail'])).length, cS).toDouble();
    } else if (d.contains('Morning Light') || d.contains('Workers Daily')) {
      _primaryLabel = "Participation Growth";
      _secondaryLabel = "Done (avg/week)";
      _tertiaryLabel = "Missed Days";

      int cDone = cur.where((x) => CompStatus.isPositive(x['status_detail'])).length;
      int pDone = prev.where((x) => CompStatus.isPositive(x['status_detail'])).length;

      _primaryGrowth = pctDiff(cAvg(cDone), pAvg(pDone));
      _secondaryGrowth = CompPeriod.perSession(cDone, cS).toDouble();
      _tertiaryGrowth = CompPeriod.perSession(cur.where((x) => CompStatus.isNegative(x['status_detail'])).length, cS).toDouble();
    } else {
      _primaryLabel = "Total Records";
      _secondaryLabel = "Current Period";
      _tertiaryLabel = "Previous Period";

      _primaryGrowth = pctDiff(cur.length.toDouble(), prev.length.toDouble());
      _secondaryGrowth = cur.length.toDouble();
      _tertiaryGrowth = prev.length.toDouble();
    }
  }

  String _getActiveUnitDisplayLabel() {
    final lv = CompLevel.of(_currentLevel);
    if (lv == CompLevel.group && _isGroupLeader) return _groupLeaderCleanDept;
    final String title = CompLevel.unitTitle(_currentLevel);
    String parent = '';
    if (lv == CompLevel.cell) parent = _selectedTeam ?? '';
    if (lv == CompLevel.team) parent = _selectedDepartment ?? '';
    if (lv == CompLevel.dept) parent = _selectedSubLocation ?? '';
    if (lv == CompLevel.subLocation) parent = _selectedLocation ?? '';
    if (parent == 'All Locations' || parent == 'N/A') parent = '';
    return parent.isNotEmpty ? "$title · $parent" : title;
  }

  String _getFindingsTitle() {
    if (widget.role.isEmpty) return "Leader's findings";
    String formattedRole = widget.role.replaceAll('_', ' ').split(' ').map((str) => str.isNotEmpty ? str[0].toUpperCase() + str.substring(1) : '').join(' ');
    return "$formattedRole's findings";
  }

  void _setMode(String v) {
    setState(() => _analyticsMode = v);
    if (v.contains('Ranking')) _loadRanking();
  }

  void _togglePending() {
    setState(() => _includePending = !_includePending);
    _fetchData();
  }

  Future<void> _rightClick(Offset pos) => showOfficeMenu(context, pos, [
        OfficeMenuItem("Refresh data", icon: Icons.refresh_rounded, shortcut: "F5", onTap: _isLoading ? null : _refreshData),
        const OfficeMenuItem.divider(),
        for (int i = 0; i < _modeOptions.length; i++)
          OfficeMenuItem(_modeOptions[i],
              icon: _analyticsMode == _modeOptions[i] ? Icons.radio_button_checked : Icons.radio_button_unchecked, shortcut: "Alt+${i + 1}", onTap: () => _setMode(_modeOptions[i])),
        const OfficeMenuItem.divider(),
        OfficeMenuItem(_includePending ? "Count approved reports only" : "Include pending reports", icon: Icons.pending_actions_rounded, shortcut: "Ctrl+Shift+P", onTap: _togglePending),
        OfficeMenuItem("Write findings", icon: Icons.edit_note_rounded, shortcut: "Ctrl+Shift+F", onTap: () => _findingsFocus.requestFocus()),
      ]);

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    bool isMobile = screenWidth < 900;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): () { if (!_isLoading) _refreshData(); },
        ...officeKeys({LogicalKeyboardKey.keyR: () { if (!_isLoading) _refreshData(); }}, ctrlShift: {
          LogicalKeyboardKey.keyP: _togglePending,
          LogicalKeyboardKey.keyF: () => _findingsFocus.requestFocus(),
        }),
        for (int i = 0; i < _modeOptions.length && i < 3; i++)
          SingleActivator(const [LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3][i], alt: true): () => _setMode(_modeOptions[i]),
      },
      child: Focus(
        autofocus: true,
        child: OfficeRightClick(
          onMenu: _rightClick,
          child: Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: AppPalette.bg(Colors.white), 
        elevation: 0, 
        iconTheme: IconThemeData(color: AppPalette.fg(pPurple)),
        title: Text(
          widget.selectedDuty, 
          style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple), fontSize: 17.5, letterSpacing: 0.4),
        ),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1.0), child: Container(color: AppPalette.bg(Colors.black), height: 1.0)),
        actions: [
          IconButton(
            tooltip: tr("Refresh data"),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _refreshData,
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
    ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final bool isTrendAnalysisMode = _analyticsMode.contains('Trend');
    final bool isRankingMode = _analyticsMode.contains('Ranking');

    return Column(children: [
      if (_loadError != null) ...[
        _buildLoadErrorBanner(),
        const SizedBox(height: 15),
      ],
      _buildGrowthCard(),
      const SizedBox(height: 15),
      if (_loadError == null && _logs.isEmpty) ...[
        _buildEmptyNotice(),
        const SizedBox(height: 15),
      ],
      // Trend Analysis shows only the analysis of the period (no summary
      // table / chart); Ranking ranks every level below the one viewed.
      if (isTrendAnalysisMode) ...[
        _buildTrendAnalysis(),
        const SizedBox(height: 15),
        _buildOnPageStrategicDashboard(),
      ] else if (isRankingMode)
        _buildRankingView()
      else
        _buildSelectedModule(),
      const SizedBox(height: 15),
      _buildAnalysisBox(),
      const SizedBox(height: 40),
    ]);
  }

  // =====================================================================
  // SHARED METRIC (Trend Analysis, Ranking and the strategic dashboard)
  //   rate = reports that count as "done" ÷ (sessions × headcount)
  // e.g. the average share of members present per service.
  // =====================================================================
  bool get _hasDatedReports {
    final t = _getTargetTable();
    return t != 'bb_students' && t != 'members';
  }

  bool get _isWorkerDuty {
    final d = widget.selectedDuty;
    return d == 'Workers Education' || d == 'Workers Daily Participation';
  }

  bool _isDone(dynamic r) {
    final d = widget.selectedDuty.trim();
    bool paid(dynamic v) {
      final s = CompStatus.norm(v);
      if (s.isEmpty) return false;
      final num? amount = num.tryParse(s.replaceAll(',', '').replaceAll(' ', ''));
      return amount != null ? amount > 0 : CompStatus.isPositive(s);
    }

    if (d == 'Offering' || d == 'Offering Status') {
      return OfferingCategories.allColumns.any((k) => paid(r[k]));
    }
    if (d == 'Service Attendance Status') return CompStatus.isPositive(r['attendance_realtime']);
    if (d == 'Visitations and Counselling') {
      return CompStatus.norm(r['visitation_reason']).isNotEmpty || CompStatus.isPositive(r['status_detail']);
    }
    if (!_hasDatedReports) return true; // BB results / growth: every row counts
    return CompStatus.isPositive(r['status_detail']);
  }

  /// One session = one report date + day (Sunday / Wednesday service, ML day ...).
  String _sessionKey(dynamic r) {
    final day = r['service_day'] ?? r['education_day'] ?? r['ml_day'] ?? r['part_day'] ?? r['evang_day'] ?? r['edu_day'] ?? '';
    return "${r['report_date'] ?? ''}|$day";
  }

  List<Map<String, dynamic>> get _headcountMembers {
    if (!_isWorkerDuty) return _masterMembers;
    final workers = _masterMembers.where((m) => m['is_worker'] == true).toList();
    return workers.isNotEmpty ? workers : _masterMembers;
  }

  /// Rate in % for a set of reports and the members they belong to.
  /// Without dated reports (BB results, growth) it is simply the row count.
  ({double rate, int done, int expected}) _rateFor(List<dynamic> logs, int headcount) {
    final int done = logs.where(_isDone).length;
    if (!_hasDatedReports) return (rate: done.toDouble(), done: done, expected: headcount);
    final int sessions = logs.map(_sessionKey).toSet().length;
    final int heads = headcount > 0 ? headcount : logs.map((l) => l['member_id']).toSet().length;
    final int expected = sessions * heads;
    final double rate = expected > 0 ? (done / expected * 100).clamp(0, 100).toDouble() : 0.0;
    return (rate: rate, done: done, expected: expected);
  }

  String _bucketLabel(String key, int index) {
    final d = DateTime.tryParse(key);
    if (d == null) return key;
    if (_timePeriod == 'Weekly status') return "Week ${index + 1} (${DateFormat('d MMM').format(d)})";
    if (_timePeriod == 'Monthly status') return DateFormat('MMMM yyyy').format(d);
    return DateFormat('EEE d MMM').format(d);
  }

  String _fmtPts(double v) => "${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} pts";

  // =====================================================================
  // TREND ANALYSIS — how the period went, week by week / month by month
  // =====================================================================
  Widget _buildTrendAnalysis() {
    if (!_hasDatedReports) {
      return _analyticsCard(
        "Trend analysis",
        Icons.show_chart_rounded,
        Text("${widget.selectedDuty} has no dated weekly reports, so there is no trend over time to analyse. Use Summary or Ranking.",
            style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.black87))),
      );
    }

    final String unitWord = _hasDatedReports && _isWorkerDuty ? "workers" : "members";
    final List<String> keys = CompPeriod.expectedBuckets(_timePeriod) ??
        (_logs.map((l) => CompPeriod.bucketKey(l, _timePeriod)).where((k) => k.isNotEmpty).toSet().toList()..sort());
    final Map<String, List<dynamic>> byBucket = {};
    for (final l in _logs) {
      byBucket.putIfAbsent(CompPeriod.bucketKey(l, _timePeriod), () => []).add(l);
    }
    final int heads = _headcountMembers.length;
    final List<({String key, String label, double rate, int done, int expected, bool hasData})> rows = [];
    for (int i = 0; i < keys.length; i++) {
      final logs = byBucket[keys[i]] ?? const [];
      final r = _rateFor(logs, heads);
      rows.add((key: keys[i], label: _bucketLabel(keys[i], i), rate: r.rate, done: r.done, expected: r.expected, hasData: logs.isNotEmpty));
    }
    final withData = rows.where((r) => r.hasData).toList();

    if (withData.isEmpty) {
      return _analyticsCard(
        "Trend analysis",
        Icons.show_chart_rounded,
        Text("No reports in this period yet, so there is no trend to analyse.",
            style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.black87))),
      );
    }

    // Headline
    final first = withData.first, last = withData.last;
    final best = withData.reduce((a, b) => a.rate >= b.rate ? a : b);
    final worst = withData.reduce((a, b) => a.rate <= b.rate ? a : b);
    final double avg = withData.map((r) => r.rate).reduce((a, b) => a + b) / withData.length;
    final double change = last.rate - first.rate;
    final String direction = withData.length < 2
        ? "Only one ${_timePeriod == 'Monthly status' ? 'month' : 'week'} has reports so far"
        : change.abs() < 1
            ? "Stable"
            : (change > 0 ? "Improving" : "Declining");
    final List<String> missing = rows.where((r) => !r.hasData).map((r) => r.label.split(' (').first).toList();

    final String headline = withData.length < 2
        ? "$direction: ${last.label} at ${last.rate.toStringAsFixed(1)}% of $unitWord."
        : "$direction — from ${first.rate.toStringAsFixed(1)}% in ${first.label.split(' (').first} "
            "to ${last.rate.toStringAsFixed(1)}% in ${last.label.split(' (').first} (${_fmtPts(change)}). "
            "Average ${avg.toStringAsFixed(1)}%; best ${best.label.split(' (').first} (${best.rate.toStringAsFixed(1)}%), "
            "lowest ${worst.label.split(' (').first} (${worst.rate.toStringAsFixed(1)}%).";

    // Units that moved the most between their first and last period with reports
    final Map<String, List<dynamic>> byUnit = CompLevel.groupBy(_logs, _moduleLevel);
    final Map<String, List<dynamic>> membersByUnit = CompLevel.groupBy(_headcountMembers, _moduleLevel);
    final List<({String unit, double from, double to})> moves = [];
    byUnit.forEach((unit, logs) {
      final Map<String, List<dynamic>> ub = {};
      for (final l in logs) {
        ub.putIfAbsent(CompPeriod.bucketKey(l, _timePeriod), () => []).add(l);
      }
      final present = keys.where((k) => (ub[k] ?? const []).isNotEmpty).toList();
      if (present.length < 2) return;
      final h = (membersByUnit[unit] ?? const []).length;
      moves.add((unit: unit, from: _rateFor(ub[present.first]!, h).rate, to: _rateFor(ub[present.last]!, h).rate));
    });
    moves.sort((a, b) => (b.to - b.from).compareTo(a.to - a.from));
    final improving = moves.where((m) => m.to - m.from >= 1).take(3).toList();
    final declining = moves.reversed.where((m) => m.to - m.from <= -1).take(3).toList();

    final Color trendColor = change > 0.5 ? Colors.green.shade700 : (change < -0.5 ? Colors.red.shade700 : pPurple);

    return _analyticsCard(
      "Trend analysis — ${widget.selectedDuty}",
      Icons.show_chart_rounded,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppPalette.bg(trendColor.withValues(alpha: 0.06)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppPalette.line(trendColor.withValues(alpha: 0.3))),
          ),
          child: Text(headline, style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87), height: 1.45)),
        ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text("No reports yet for: ${missing.join(', ')}.",
              style: GoogleFonts.merriweather(fontSize: 10.5, color: AppPalette.fg(Colors.orange.shade900), fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 14),
        // Period by period with change from the previous one
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (int i = 0; i < rows.length; i++) _trendPeriodTile(rows[i], i > 0 && rows[i - 1].hasData ? rows[i - 1].rate : null),
        ]),
        const SizedBox(height: 14),
        SizedBox(height: 170, child: _trendLine(rows.map((r) => r.hasData ? r.rate : null).toList(), rows.map((r) => r.label.split(' (').first).toList(), trendColor)),
        const SizedBox(height: 12),
        if (improving.isNotEmpty || declining.isNotEmpty)
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth > 620;
            final a = _moverList("Improving units", improving, Colors.green.shade800);
            final b = _moverList("Units needing support", declining, Colors.red.shade800);
            return wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)])
                : Column(children: [a, const SizedBox(height: 10), b]);
          }),
        const SizedBox(height: 6),
        Text(
          "Rate = reports marked done ÷ (sessions × $unitWord in scope). Units compare their first and last ${_timePeriod == 'Monthly status' ? 'month' : 'week'} with reports.",
          style: GoogleFonts.merriweather(fontSize: 9.5, color: AppPalette.fg(Colors.black54), fontStyle: FontStyle.italic),
        ),
      ]),
    );
  }

  Widget _trendPeriodTile(({String key, String label, double rate, int done, int expected, bool hasData}) r, double? previous) {
    final double? delta = (r.hasData && previous != null) ? r.rate - previous : null;
    final Color c = delta == null ? Colors.black54 : (delta > 0.5 ? Colors.green.shade700 : (delta < -0.5 ? Colors.red.shade700 : Colors.black54));
    return Container(
      width: 132,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppPalette.bg(r.hasData ? Colors.white : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.line(Colors.black26)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.label, style: GoogleFonts.merriweather(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)), maxLines: 2),
        const SizedBox(height: 4),
        Text(r.hasData ? "${r.rate.toStringAsFixed(1)}%" : "—", style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.w900)),
        Text(
          !r.hasData ? "no reports" : (delta == null ? "${r.done} done" : "${delta >= 0 ? '▲' : '▼'} ${_fmtPts(delta)}"),
          style: GoogleFonts.merriweather(fontSize: 9.5, color: AppPalette.fg(c), fontWeight: FontWeight.bold),
        ),
      ]),
    );
  }

  Widget _trendLine(List<double?> values, List<String> labels, Color color) {
    final spots = <FlSpot>[
      for (int i = 0; i < values.length; i++)
        if (values[i] != null) FlSpot(i.toDouble(), values[i]!),
    ];
    return LineChart(LineChartData(
      minY: 0,
      maxY: 100,
      minX: 0,
      maxX: (values.length - 1).clamp(1, 1000).toDouble(),
      gridData: const FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 25),
      borderData: FlBorderData(show: true, border: Border(left: BorderSide(color: AppPalette.line(Colors.black26)), bottom: BorderSide(color: AppPalette.line(Colors.black26)))),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            interval: 25,
            getTitlesWidget: (v, m) => Text("${v.toInt()}%", style: GoogleFonts.merriweather(fontSize: 9)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            reservedSize: 22,
            getTitlesWidget: (v, m) {
              final i = v.toInt();
              if (i < 0 || i >= labels.length || v != i.toDouble()) return const SizedBox.shrink();
              return Padding(padding: const EdgeInsets.only(top: 4), child: Text(labels[i], style: GoogleFonts.merriweather(fontSize: 9)));
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
        ),
      ],
    ));
  }

  Widget _moverList(String title, List<({String unit, double from, double to})> items, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppPalette.bg(color.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.line(color.withValues(alpha: 0.25))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppPalette.fg(color))),
        const SizedBox(height: 6),
        if (items.isEmpty)
          Text("None this period", style: GoogleFonts.merriweather(fontSize: 10.5, color: AppPalette.fg(Colors.black54)))
        else
          ...items.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  "${m.unit}: ${m.from.toStringAsFixed(1)}% → ${m.to.toStringAsFixed(1)}% (${_fmtPts(m.to - m.from)})",
                  style: GoogleFonts.merriweather(fontSize: 10.5, color: AppPalette.fg(Colors.black87)),
                ),
              )),
      ]),
    );
  }

  Widget _analyticsCard(String title, IconData icon, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.line(Colors.black), width: 1.0),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: AppPalette.fg(pPurple), size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: AppPalette.fg(pPurple)))),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );

  // =====================================================================
  // RANKING — every level below the one being viewed, each ranked
  // (a location leader compares sub-locations, departments, teams, cells)
  // =====================================================================

  /// Unit name including its parents below the viewed level, so "1팀" in
  /// two different departments are ranked as two different teams.
  String _rankKey(dynamic record, String levelName, List<String> path) {
    final parts = <String>[];
    for (final lv in path) {
      parts.add(CompLevel.unitKey(record, lv, qualified: false));
      if (lv == levelName) break;
    }
    return parts.join(' › ');
  }

  // =====================================================================
  // RANKING — pick the unit level to compare and the period to rank over.
  // Totals come from the database (compile_unit_stats, see 04_ranking.sql),
  // so even a whole year loads quickly. Shown as a 3D bar chart + table.
  // =====================================================================
  static const List<String> _rankPeriods = ['Weekly', 'Monthly', 'Quarterly', 'Half-year', 'Yearly'];

  /// Weekly = last 7 days, Monthly = last month, Quarterly = last 3 months,
  /// Half-year = last 6 months, Yearly = last 12 months (all up to today).
  (DateTime, DateTime) _rankRange(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'Weekly':
        return (today.subtract(const Duration(days: 6)), today);
      case 'Quarterly':
        return (DateTime(today.year, today.month - 3, today.day + 1), today);
      case 'Half-year':
        return (DateTime(today.year, today.month - 6, today.day + 1), today);
      case 'Yearly':
        return (DateTime(today.year - 1, today.month, today.day + 1), today);
      case 'Monthly':
      default:
        return (DateTime(today.year, today.month - 1, today.day + 1), today);
    }
  }

  /// Levels that can be compared: every level below the one being viewed.
  List<String> get _rankLevels {
    final int idx = _hierarchy.indexOf(_currentLevel);
    return idx >= 0 && idx < _hierarchy.length - 1 ? _hierarchy.sublist(idx + 1) : <String>[];
  }

  /// The viewer's member scope as filters for compile_unit_stats
  /// (same rules as the report query and the headcount).
  List<Map<String, dynamic>> _memberScopeFilters() {
    final f = <Map<String, dynamic>>[];
    void eq(String c, String v) => f.add({'col': c, 'op': 'eq', 'val': v});
    void neq(String c, String v) => f.add({'col': c, 'op': 'neq', 'val': v});
    bool ok(String v) => v.isNotEmpty && v != 'N/A' && v != 'Church';

    if (_isGroupLeader) {
      final t = _groupLeaderCleanDept;
      eq('department', t);
      if (t != 'MOU') neq('location', 'MOU');
      if (t != '새신자') neq('location', 'New Saints');
      neq('location', 'Church Workers');
      neq('location', 'Church Main');
      neq('location', 'Church');
    } else if (_is24DeptWorker || (_hasDualModeForCurrentDuty && !_dualModeIsChurch)) {
      f.add({'col': 'location', 'op': 'in_or_null', 'vals': ['Church', 'Church Workers', 'Church Main']});
      final od = _roleMetadata?['official_dept_id'];
      if (od != null) {
        eq('official_dept_id', od.toString());
      } else if (ok(widget.dept)) {
        eq('department', widget.dept);
      }
    } else if (!_isChurchWideCompiler) {
      if (ok(widget.loc)) eq('location', widget.loc);
      if ((_isSubLocationLeader || _isDeptLeader || _isTeamLeader) && ok(widget.sub)) eq('sub_location', widget.sub);
      if ((_isDeptLeader || _isTeamLeader) && ok(widget.dept)) eq('department', widget.dept);
      if (_isTeamLeader && ok(widget.team)) eq('team', widget.team);
      if (_isCellLeader && widget.userUnit.isNotEmpty) eq('cell_group', widget.userUnit);
    }

    final loc = _sel('loc');
    if (loc.isNotEmpty) loc == CompLevel.mou ? eq('department', CompLevel.mou) : eq('location', loc);
    if (_sel('sub').isNotEmpty) eq('sub_location', _sel('sub'));
    if (_sel('dept').isNotEmpty) eq('department', _sel('dept'));
    if (_sel('team').isNotEmpty) eq('team', _sel('team'));
    return f;
  }

  Future<void> _loadRanking() async {
    if (!_hasDatedReports) return; // BB results / growth rank the loaded rows
    final int seq = ++_rankSeq;
    setState(() {
      _rankLoading = true;
      _rankError = null;
    });
    final (from, to) = _rankRange(_rankPeriod);
    final df = DateFormat('yyyy-MM-dd');
    final filters = _memberScopeFilters();
    final String table = _getTargetTable();
    final String key = 'rank|$table|${df.format(from)}|${df.format(to)}|$_includePending|${jsonEncode(filters)}';
    try {
      final rows = await _cached<dynamic>(key, () async {
        final res = await _supabase.rpc('compile_unit_stats', params: {
          'p_table': table,
          'p_from': df.format(from),
          'p_to': df.format(to),
          'p_include_pending': _includePending,
          'p_filters': filters,
        });
        return List<dynamic>.from(res as List);
      });
      if (!mounted || seq != _rankSeq) return;
      setState(() {
        _rankRows = rows;
        _rankLoading = false;
      });
    } catch (e) {
      debugPrint("Ranking load error: $e");
      if (!mounted || seq != _rankSeq) return;
      setState(() {
        _rankRows = null;
        _rankLoading = false;
        _rankError = (e is PostgrestException && (e.code == 'PGRST202' || e.code == '42883'))
            ? "Ranking needs the database function from 04_ranking.sql. Run that file in the Supabase SQL Editor, then refresh."
            : "Couldn't load the ranking. ${e is PostgrestException ? e.message : 'Check your connection and try again.'}";
      });
    }
  }

  /// Ranked units for [levelName], from the database totals (or the loaded
  /// rows for BB results / growth tracking, which have no weekly sessions).
  List<({String unit, double rate, int done, int reports, int heads, bool reported})> _rankedUnits(String levelName) {
    final List<String> path = _rankLevels.where((l) => CompLevel.of(l) != CompLevel.group).toList();
    final bool isGroup = CompLevel.of(levelName) == CompLevel.group;
    String keyOf(dynamic r) => isGroup ? CompLevel.unitKey(r, levelName) : _rankKey(r, levelName, path);

    final Map<String, int> heads = {};
    for (final m in _headcountMembers) {
      final k = keyOf(m);
      heads[k] = (heads[k] ?? 0) + 1;
    }

    final Map<String, int> done = {};
    final Map<String, int> reports = {};
    int sessions = 0;
    if (_hasDatedReports) {
      for (final r in _rankRows ?? const []) {
        final k = keyOf(r);
        done[k] = (done[k] ?? 0) + ((r['done'] as num?)?.toInt() ?? 0);
        reports[k] = (reports[k] ?? 0) + ((r['reports'] as num?)?.toInt() ?? 0);
        final s = (r['sessions'] as num?)?.toInt() ?? 0;
        if (s > sessions) sessions = s; // sessions in the period (every unit is expected at each)
      }
    } else {
      for (final l in _logs) {
        final k = keyOf(l);
        done[k] = (done[k] ?? 0) + 1;
        reports[k] = (reports[k] ?? 0) + 1;
      }
    }

    final Set<String> units = {...heads.keys, ...done.keys}..removeWhere((k) => k.split(' › ').last == 'Other');
    final list = units.map((u) {
      final int d = done[u] ?? 0, rep = reports[u] ?? 0, h = heads[u] ?? 0;
      double rate;
      if (!_hasDatedReports) {
        rate = d.toDouble();
      } else if (h > 0 && sessions > 0) {
        rate = (d / (sessions * h) * 100).clamp(0, 100).toDouble();
      } else {
        rate = rep > 0 ? d / rep * 100 : 0.0;
      }
      return (unit: u, rate: rate, done: d, reports: rep, heads: h, reported: rep > 0);
    }).toList()
      ..sort((a, b) {
        if (a.reported != b.reported) return a.reported ? -1 : 1; // units without reports last
        return b.rate.compareTo(a.rate);
      });
    return list;
  }

  Widget _buildRankingView() {
    final levels = _rankLevels;
    if (levels.isEmpty) {
      return _analyticsCard(
        "Ranking",
        Icons.leaderboard_rounded,
        Text("There is no level below ${_currentLevel.toLowerCase()} to compare. Choose a higher level in Unit navigation.",
            style: GoogleFonts.merriweather(fontSize: 12)),
      );
    }
    final String level = levels.contains(_rankLevel) ? _rankLevel! : levels.first;
    final (from, to) = _rankRange(_rankPeriod);
    final bool usesRate = _hasDatedReports;

    Widget picker<T>(String label, T value, List<T> items, String Function(T) text, ValueChanged<T> onChanged) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple))),
            const SizedBox(height: 4),
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppPalette.bg(Colors.white),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppPalette.line(Colors.purple.shade200)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  isDense: true,
                  borderRadius: BorderRadius.circular(10),
                  items: items
                      .map((i) => DropdownMenuItem<T>(
                            value: i,
                            child: Text(text(i), style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onChanged(v);
                  },
                ),
              ),
            ),
          ],
        );

    final controls = Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
      picker<String>("Compare", level, levels, (l) => CompLevel.unitTitle(l), (v) => setState(() => _rankLevel = v)),
      if (usesRate)
        picker<String>("Period", _rankPeriod, _rankPeriods, (p) => p, (v) {
          setState(() => _rankPeriod = v);
          _loadRanking();
        }),
      if (usesRate)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Text("${DateFormat('d MMM yyyy').format(from)} – ${DateFormat('d MMM yyyy').format(to)}",
              style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.black54), fontWeight: FontWeight.w600)),
        ),
    ]);

    Widget body;
    if (usesRate && _rankLoading && _rankRows == null) {
      body = const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    } else if (usesRate && _rankError != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(children: [
          Icon(Icons.error_outline, color: AppPalette.fg(Colors.red.shade700)),
          const SizedBox(width: 10),
          Expanded(child: Text(_rankError!, style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.red.shade900)))),
          TextButton(onPressed: _loadRanking, child: const Text("Retry")),
        ]),
      );
    } else {
      final ranked = _rankedUnits(level);
      if (ranked.isEmpty) {
        body = Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text("No ${CompLevel.unitTitle(level).toLowerCase()} with members or reports in your scope for this period.",
              style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.black54))),
        );
      } else {
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_rankLoading) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          _rankBarChart(ranked, usesRate),
          const SizedBox(height: 16),
          _rankTable(ranked, usesRate),
          const SizedBox(height: 8),
          Text(
            usesRate
                ? "Rate = reports marked done ÷ (sessions in the period × ${_isWorkerDuty ? 'workers' : 'members'} in the unit). Units without reports are listed last."
                : "Ranked by number of records.",
            style: GoogleFonts.merriweather(fontSize: 9.5, color: AppPalette.fg(Colors.black54), fontStyle: FontStyle.italic),
          ),
        ]);
      }
    }

    return _analyticsCard(
      "Ranking — ${CompLevel.unitTitle(level)}${usesRate ? ' · $_rankPeriod' : ''}",
      Icons.leaderboard_rounded,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [controls, const SizedBox(height: 14), body]),
    );
  }

  Widget _rankBarChart(List<({String unit, double rate, int done, int reports, int heads, bool reported})> ranked, bool usesRate) {
    final shown = ranked.where((r) => r.reported).take(15).toList();
    if (shown.isEmpty) {
      return Text("No reports in this period yet.", style: GoogleFonts.merriweather(fontSize: 11.5, color: AppPalette.fg(Colors.black54)));
    }
    final double maxValue = usesRate ? 100 : shown.map((r) => r.rate).fold<double>(1, (m, v) => v > m ? v : m);
    return LayoutBuilder(builder: (context, c) {
      const double slot = 64; // width per bar incl. gap
      final double needed = shown.length * slot + 60;
      final double width = needed > c.maxWidth ? needed : c.maxWidth;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          height: 280,
          child: CustomPaint(
            painter: _Bar3DPainter(
              values: shown.map((r) => r.rate).toList(),
              labels: shown.map((r) => r.unit.split(' › ').last).toList(),
              maxValue: maxValue,
              isPercent: usesRate,
              baseColor: pPurple,
            ),
          ),
        ),
      );
    });
  }

  Widget _rankTable(List<({String unit, double rate, int done, int reports, int heads, bool reported})> ranked, bool usesRate) {
    TextStyle head = GoogleFonts.merriweather(fontSize: CompStyle.headerFont, fontWeight: FontWeight.w900, color: AppPalette.fg(CompStyle.headerFg));
    TextStyle cell = GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.black87));
    Widget hc(String t, {TextAlign a = TextAlign.center}) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9), child: Text(t, style: head, textAlign: a));
    Widget dc(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7), child: w);

    final rows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: AppPalette.bg(CompStyle.headerBg)),
        children: [
          hc("Rank"),
          hc("Unit", a: TextAlign.left),
          hc(_isWorkerDuty ? "Workers" : "Members"),
          hc("Reports"),
          hc(usesRate ? "Done" : "Records"),
          hc(usesRate ? "Rate" : "Count"),
        ],
      ),
      for (int i = 0; i < ranked.length; i++)
        TableRow(
          decoration: BoxDecoration(color: AppPalette.bg(i.isEven ? Colors.white : const Color(0xFFFAF7FF))),
          children: [
            dc(Text(ranked[i].reported ? "#${i + 1}" : "–",
                textAlign: TextAlign.center,
                style: cell.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppPalette.fg(i == 0
                        ? const Color(0xFFB78103)
                        : i == 1
                            ? Colors.blueGrey
                            : i == 2
                                ? Colors.brown.shade400
                                : Colors.black54)))),
            dc(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(ranked[i].unit.split(' › ').last,
                  style: cell.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 2),
              if (ranked[i].unit.contains(' › '))
                Text(ranked[i].unit.split(' › ').sublist(0, ranked[i].unit.split(' › ').length - 1).join(' › '),
                    style: cell.copyWith(fontSize: 9.5, color: AppPalette.fg(Colors.black54)), overflow: TextOverflow.ellipsis, maxLines: 2),
            ])),
            dc(Text("${ranked[i].heads}", textAlign: TextAlign.center, style: cell)),
            dc(Text("${ranked[i].reports}", textAlign: TextAlign.center, style: cell)),
            dc(Text("${ranked[i].done}", textAlign: TextAlign.center, style: cell)),
            dc(Center(
              child: !ranked[i].reported
                  ? Text("no reports", style: cell.copyWith(color: AppPalette.fg(Colors.black38), fontSize: 10))
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppPalette.bg((usesRate ? CompStyle.rateColor(ranked[i].rate) : pPurple).withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        usesRate ? "${ranked[i].rate.toStringAsFixed(1)}%" : "${ranked[i].done}",
                        style: cell.copyWith(fontWeight: FontWeight.w900, color: AppPalette.fg(usesRate ? CompStyle.rateColor(ranked[i].rate) : pPurple)),
                      ),
                    ),
            )),
          ],
        ),
    ];

    return LayoutBuilder(builder: (context, c) {
      const double minWidth = 560;
      final table = Table(
        columnWidths: const {
          0: FixedColumnWidth(56),
          1: FlexColumnWidth(3),
          2: FlexColumnWidth(1.1),
          3: FlexColumnWidth(1.1),
          4: FlexColumnWidth(1.1),
          5: FlexColumnWidth(1.4),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          horizontalInside: BorderSide(color: AppPalette.line(Colors.black.withValues(alpha: 0.06))),
          bottom: BorderSide(color: AppPalette.line(Colors.black.withValues(alpha: 0.12))),
        ),
        children: rows,
      );
      final boxed = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: AppPalette.line(Colors.black26)), borderRadius: BorderRadius.circular(12)),
          child: table,
        ),
      );
      if (c.maxWidth >= minWidth) return boxed;
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: minWidth, child: boxed));
    });
  }

  // ON-PAGE STRATEGIC DASHBOARD (Option B from Supabase compilation_ui_config)
  Widget _buildOnPageStrategicDashboard() {
    final period = _timePeriod;
    final duty = widget.selectedDuty;

    // Rank the same units the table and chart show at this level
    final Map<String, List<dynamic>> unitMap = CompLevel.groupBy(_logs, _moduleLevel);

    final Map<String, List<dynamic>> membersByUnit = CompLevel.groupBy(_headcountMembers, _moduleLevel);
    final List<Map<String, dynamic>> unitRanks = [];
    unitMap.forEach((u, lList) {
      // Same rate as Trend Analysis and Ranking: done ÷ (sessions × headcount)
      final r = _rateFor(lList, (membersByUnit[u] ?? const []).length);
      unitRanks.add({'unit': u, 'total': lList.length, 'att': r.done, 'pct': r.rate});
    });

    unitRanks.sort((a, b) => (b['pct'] as double).compareTo(a['pct'] as double));
    final topUnits = unitRanks.take(3).map((e) => "${e['unit']} (${(e['pct'] as double).toStringAsFixed(1)}%)").toList();
    final bottomUnits = unitRanks.reversed.where((e) => !topUnits.any((t) => t.startsWith("${e['unit']} ("))).take(3).map((e) => "${e['unit']} (${(e['pct'] as double).toStringAsFixed(1)}%)").toList();

    final Set<String> rawFindings = {};
    for (var l in _logs) {
      final n = (l['correction_note'] ?? l['situation_notes'] ?? '').toString().trim();
      if (n.isNotEmpty && n != 'null') rawFindings.add(n);
    }
    final findingsSummary = rawFindings.isNotEmpty 
        ? rawFindings.take(4).join("\n• ") 
        : "Regular unit tracking maintained with ongoing pastoral check-ins.";

    // Action directives loaded dynamically from Supabase compilation_ui_config
    final List<String> directives = _analysisDirectives.isNotEmpty
        ? _analysisDirectives
        : [
            "Conduct targeted pastoral reviews with leaders of units falling below the benchmark threshold.",
            "Deploy experienced workers to provide hands-on visitation and evangelism support to trailing units.",
            "Execute immediate absentee recovery check-ins prior to the next scheduled service or education session.",
            "Cross-pollinate effective unit strategies from top-performing units to units requiring critical support."
          ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.line(Colors.black), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // On narrow screens the title wraps and the button moves below it
          LayoutBuilder(builder: (ctx, bc) {
            final titleBlock = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppPalette.bg(pPurple.withValues(alpha: 0.1)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.analytics_rounded, color: AppPalette.fg(pPurple), size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Strategic Performance & Trend Evaluation",
                          softWrap: true,
                          style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: bc.maxWidth < 420 ? 13.5 : 15, color: AppPalette.fg(pPurple))),
                      Text("$duty • $period Analysis",
                          softWrap: true,
                          style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
                    ],
                  ),
                ),
              ],
            );
            final button = ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.bg(pPurple),
                foregroundColor: AppPalette.fg(Colors.white),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: BorderSide(color: AppPalette.line(Colors.black), width: 1.0),
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: Text("Download PDF Report", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 11.5)),
              onPressed: () => _exportAiReportPdf(duty, period, topUnits, bottomUnits, findingsSummary, directives),
            );
            if (bc.maxWidth < 560) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [titleBlock, const SizedBox(height: 10), button]);
            }
            return Row(children: [Expanded(child: titleBlock), const SizedBox(width: 12), button]);
          }),
          const SizedBox(height: 14),
          Divider(height: 1, color: AppPalette.bg(Colors.black26)),
          const SizedBox(height: 14),

          _reportSection(
            "1. Executive Summary",
            "During the $period evaluation for $duty, total recorded submissions reached ${_logs.length} across units. "
            "The primary metric trajectory is recorded at ${_primaryGrowth >= 0 ? '+' : ''}${_primaryGrowth.toStringAsFixed(1)}% compared to the prior period.",
            Icons.analytics_outlined,
          ),

          _reportSection(
            "2. Benchmark Leading Units",
            topUnits.isNotEmpty 
                ? "Top-performing units setting the standard for this period:\n• ${topUnits.join('\n• ')}" 
                : "All units currently performing at parity.",
            Icons.stars_rounded,
            color: Colors.green.shade800,
          ),

          _reportSection(
            "3. Critical Focus & Support Required",
            bottomUnits.isNotEmpty 
                ? "The following units require targeted administrative and pastoral intervention:\n• ${bottomUnits.join('\n• ')}" 
                : "No units critically behind the designated benchmark threshold.",
            Icons.warning_amber_rounded,
            color: Colors.red.shade800,
          ),

          _reportSection(
            "4. Synthesis of Unit Leader Observations",
            "• $findingsSummary",
            Icons.comment_bank_outlined,
          ),

          _reportSection(
            "5. Strategic Directives for Senior Leadership",
            directives.map((d) => "• $d").join('\n'),
            Icons.assignment_turned_in_outlined,
            color: pPurple,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedModule() {
    String d = widget.selectedDuty;
    
    if (d == 'Service Attendance Status') {
      return ServiceAttendanceModule(
        logs: _logs, 
        masterMembers: _masterMembers,
        timePeriod: _timePeriod, 
        level: _moduleLevel, 
        analyticsMode: _analyticsMode, 
        groupBy: _groupBy, 
        targetValue: 80.0,
        selectedLocation: _sel('loc'),
        selectedSubLocation: _sel('sub'),
        selectedDepartment: _sel('dept'),
        selectedTeam: _sel('team'),
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
        masterMembers: _masterMembers,
        timePeriod: _timePeriod, 
        level: _moduleLevel, 
        analyticsMode: _analyticsMode, 
        groupBy: _groupBy, 
        targetValue: 80.0,
        selectedLocation: _sel('loc'),
        selectedSubLocation: _sel('sub'),
        selectedDepartment: _sel('dept'),
        selectedTeam: _sel('team'),
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
        masterMembers: _masterMembers,
        timePeriod: _timePeriod, 
        level: _moduleLevel, 
        analyticsMode: _analyticsMode, 
        groupBy: _groupBy, 
        targetValue: 80.0,
        selectedLocation: _sel('loc'),
        selectedSubLocation: _sel('sub'),
        selectedDepartment: _sel('dept'),
        selectedTeam: _sel('team'),
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
        masterMembers: _masterMembers,
        timePeriod: _timePeriod,
        level: _moduleLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _sel('loc'),
        selectedSubLocation: _sel('sub'),
        selectedDepartment: _sel('dept'),
        selectedTeam: _sel('team'),
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
        masterMembers: _masterMembers,
        timePeriod: _timePeriod,
        level: _moduleLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _sel('loc'),
        selectedSubLocation: _sel('sub'),
        selectedDepartment: _sel('dept'),
        selectedTeam: _sel('team'),
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
        masterMembers: _masterMembers,
        timePeriod: _timePeriod,
        level: _moduleLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _sel('loc'),
        selectedSubLocation: _sel('sub'),
        selectedDepartment: _sel('dept'),
        selectedTeam: _sel('team'),
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
        masterMembers: _masterMembers,
        timePeriod: _timePeriod,
        level: _moduleLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 90.0,
        selectedLocation: _sel('loc'),
        selectedSubLocation: _sel('sub'),
        selectedDepartment: _sel('dept'),
        selectedTeam: _sel('team'),
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
        masterMembers: _masterMembers,
        timePeriod: _timePeriod,
        level: _moduleLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _sel('loc'),
        selectedSubLocation: _sel('sub'),
        selectedDepartment: _sel('dept'),
        selectedTeam: _sel('team'),
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
        masterMembers: _masterMembers,
        timePeriod: _timePeriod,
        level: _moduleLevel,
        category: _visitationCategories.isNotEmpty ? _visitationCategories.first : 'All',
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _sel('loc'),
        selectedSubLocation: _sel('sub'),
        selectedDepartment: _sel('dept'),
        selectedTeam: _sel('team'),
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
        periodStart: _periodStart,
        periodEnd: _periodEnd,
        unitPath: _evangelismUnitPath(),
        bbData: _logs,
        logs: _logs,
        masterMembers: _masterMembers,
        timePeriod: _timePeriod,
        level: _moduleLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 80.0,
        selectedLocation: _sel('loc'),
        selectedSubLocation: _sel('sub'),
        selectedDepartment: _sel('dept'),
        selectedTeam: _sel('team'),
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
    if (d.contains('Growth Tracking')) {
      return GrowthTrackingModule(
        category: d,
        logs: _logs,
        masterMembers: _masterMembers,
        timePeriod: _timePeriod,
        level: _moduleLevel,
        analyticsMode: _analyticsMode,
        groupBy: _groupBy,
        targetValue: 10.0,
        selectedLocation: _sel('loc'),
        selectedSubLocation: _sel('sub'),
        selectedDepartment: _sel('dept'),
        selectedTeam: _sel('team'),
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

  Widget _buildLoadErrorBanner() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppPalette.bg(Colors.red.shade50),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppPalette.line(Colors.red.shade300)),
    ),
    child: Row(children: [
      Icon(Icons.error_outline, color: AppPalette.fg(Colors.red.shade800)),
      const SizedBox(width: 10),
      Expanded(child: Text(_loadError ?? '', style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.red.shade900)))),
      TextButton(onPressed: _fetchData, child: const Text("Retry")),
    ]),
  );

  Widget _buildEmptyNotice() {
    final String range = (_periodStart != null && _periodEnd != null)
        ? "${DateFormat('d MMM').format(_periodStart!)} – ${DateFormat('d MMM yyyy').format(_periodEnd!)}"
        : _timePeriod;
    final String which = (!_usesApproval || _includePending) ? "reports" : "approved reports";
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.bg(const Color(0xFFFFF8E1)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.line(Colors.amber.shade300)),
      ),
      child: Text(
        _usesApproval && !_includePending
            ? "No $which for $range in this unit. Reports appear here after their final approval — switch on \"Include pending reports\" to see submitted ones."
            : "No $which for $range in this unit.",
        style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.brown.shade800)),
      ),
    );
  }

  Widget _buildApprovalToggle() {
    if (!_usesApproval) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppPalette.line(Colors.black), width: 1.0),
      ),
      child: SwitchListTile(
        dense: true,
        title: Text("Include pending reports", style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.w900)),
        subtitle: Text(
          _includePending ? "Counting approved + pending" : "Counting approved reports only",
          style: GoogleFonts.merriweather(fontSize: 10.5, color: AppPalette.fg(Colors.black54)),
        ),
        value: _includePending,
        onChanged: (v) {
          setState(() => _includePending = v);
          _fetchData();
        },
      ),
    );
  }

  Future<void> _submitFindings() async {
    final text = _analysisController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Write your findings first.")));
      return;
    }
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final DateFormat df = DateFormat('yyyy-MM-dd');
    final DateTime end = _periodEnd ?? DateTime.now();
    final DateTime start = _periodStart ?? end;

    setState(() => _savingFindings = true);
    try {
      await _supabase.from('manager_insights').insert({
        'period_start': df.format(start),
        'period_end': df.format(end),
        'duty_name': widget.selectedDuty,
        'unit_id': _getActiveUnitDisplayLabel(),
        'observation': text,
        'manager_id': user.id,
      });
      if (!mounted) return;
      _analysisController.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Findings submitted successfully")));
      _loadRecentFindings();
    } catch (e) {
      debugPrint("Findings save error: $e");
      if (!mounted) return;
      final msg = e is PostgrestException && e.code == '42501'
          ? "Your account isn't allowed to save findings yet. Ask the admin to run 08_round7.sql."
          : "Couldn't save your findings${e is PostgrestException ? ': ${e.message}' : '. Please try again.'}";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red.shade800, content: Text(msg)));
    } finally {
      if (mounted) setState(() => _savingFindings = false);
    }
  }

  Future<void> _loadRecentFindings() async {
    try {
      final res = await _supabase
          .from('manager_insights')
          .select('id, observation, period_start, period_end, manager_id, profiles(full_name)')
          .eq('duty_name', widget.selectedDuty)
          .eq('unit_id', _getActiveUnitDisplayLabel())
          .order('period_end', ascending: false)
          .limit(5);
      if (mounted) setState(() => _recentFindings = List<Map<String, dynamic>>.from(res));
    } catch (e) {
      debugPrint("Findings load: $e");
    }
  }

  @override
  void dispose() {
    _analysisController.dispose();
    _findingsFocus.dispose();
    super.dispose();
  }

  Widget _buildGrowthCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white), 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: AppPalette.line(Colors.black), width: 1.0), 
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Growth Performance Metrics", maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.black87))),
                    const SizedBox(height: 2),
                    Text(_timePeriod, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppPalette.bg(pPurple.withValues(alpha: 0.08)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppPalette.line(pPurple.withValues(alpha: 0.3))),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded, color: AppPalette.fg(pPurple), size: 14),
                    const SizedBox(width: 4),
                    Text(_analyticsMode, maxLines: 1, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppPalette.bg(Colors.black12)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _metricPill(_primaryLabel, _primaryGrowth, isPercentage: !_primaryLabel.contains('Saints') && !_primaryLabel.contains('Fruits')),
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
          color: AppPalette.bg(color.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppPalette.line(color.withValues(alpha: 0.25)), width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // wraps onto a second line instead of "General Att…"
            Text(title, style: GoogleFonts.merriweather(fontSize: 9.5, height: 1.25, color: AppPalette.fg(Colors.black87), fontWeight: FontWeight.bold), maxLines: 2, softWrap: true, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(display, maxLines: 1, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w900, color: AppPalette.fg(color))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportSection(String title, String body, IconData icon, {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.bg((color ?? pPurple).withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.line((color ?? pPurple).withValues(alpha: 0.2))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppPalette.fg(color ?? pPurple)),
              const SizedBox(width: 8),
              Expanded(child: Text(title, softWrap: true, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.w900, color: AppPalette.fg(color ?? Colors.black87)))),
            ],
          ),
          const SizedBox(height: 6),
          Text(body, style: GoogleFonts.merriweather(fontSize: 11.5, color: AppPalette.fg(Colors.black87), height: 1.4)),
        ],
      ),
    );
  }

  Future<void> _exportAiReportPdf(String duty, String period, List<String> top, List<String> bottom, String findings, List<String> directives) async {
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
                    pw.Text('Strategic Trend & Performance Report', style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.purple900)),
                    pw.Text(DateFormat('yyyy-MM-dd').format(DateTime.now()), style: pw.TextStyle(font: font, fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Duty: $duty | Period: $period | Records: ${_logs.length}', style: pw.TextStyle(font: font, fontSize: 9.5, color: PdfColors.grey700)),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 10),

              pw.Text('1. Performance Metrics Overview', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.purple900)),
              pw.Bullet(text: '$_primaryLabel: ${_primaryGrowth.toStringAsFixed(1)}', style: pw.TextStyle(font: font, fontSize: 9.5)),
              pw.Bullet(text: '$_secondaryLabel: ${_secondaryGrowth.toStringAsFixed(1)}', style: pw.TextStyle(font: font, fontSize: 9.5)),
              pw.Bullet(text: '$_tertiaryLabel: ${_tertiaryGrowth.toStringAsFixed(1)}', style: pw.TextStyle(font: font, fontSize: 9.5)),
              pw.SizedBox(height: 10),

              pw.Text('2. Benchmark Leading Units', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.green900)),
              ...top.map((e) => pw.Bullet(text: e, style: pw.TextStyle(font: font, fontSize: 9.5))),
              pw.SizedBox(height: 10),

              pw.Text('3. Units Requiring Urgent Support', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.red900)),
              ...bottom.map((e) => pw.Bullet(text: e, style: pw.TextStyle(font: font, fontSize: 9.5))),
              pw.SizedBox(height: 10),

              pw.Text('4. Synthesis of Unit Leader Observations', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.purple900)),
              pw.Text(findings, style: pw.TextStyle(font: font, fontSize: 9.5)),
              pw.SizedBox(height: 10),

              pw.Text('5. Strategic Action Directives for Next Week', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.purple900)),
              ...directives.map((d) => pw.Bullet(text: d, style: pw.TextStyle(font: font, fontSize: 9.5))),
            ],
          );
        },
      ),
    );

    if (!mounted) return;
    await TableExport.previewDoc(context, widget.selectedDuty, pdf, fileName: '${widget.selectedDuty.replaceAll(' ', '_')}_report.pdf');
  }

  Widget _buildSidebarContent() {
    bool isMobile = MediaQuery.of(context).size.width < 900;
    return Container(
      width: isMobile ? null : 310,
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        border: isMobile ? null : Border(right: BorderSide(color: AppPalette.line(Colors.black), width: 1.0)),
      ),
      child: Column(children: [
        if (isMobile)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppPalette.bg(Colors.white),
              border: Border(bottom: BorderSide(color: AppPalette.line(Colors.black26), width: 1.0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, color: AppPalette.fg(pPurple), size: 20),
                    const SizedBox(width: 8),
                    Text("Analytics filters", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple), fontSize: 16)),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 22, color: AppPalette.fg(Colors.black87)),
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
                    color: AppPalette.bg(Colors.purple.shade50),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppPalette.line(Colors.purple.shade200)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_getDualModeTitle(), style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple))),
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
                                  color: AppPalette.bg(_dualModeIsChurch ? pPurple : Colors.white),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: Text(_isTheologyDept ? "Across locations" : "Church Reports", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(_dualModeIsChurch ? Colors.white : Colors.black87))),
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
                                  color: AppPalette.bg(!_dualModeIsChurch ? pPurple : Colors.white),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: Text(_isTheologyDept ? "Church level" : "Dept Reports", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(!_dualModeIsChurch ? Colors.white : Colors.black87))),
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
                  final p = await _pickCustomRange();
                  if (p != null) { setState(() { _customRange = p; _timePeriod = v; }); _fetchData(); }
                } else { setState(() => _timePeriod = v); _fetchData(); }
                if (isMobile) Navigator.pop(context);
              }),
              const SizedBox(height: 10),

              _buildApprovalToggle(),

              _bentoNavCard("Analytics mode", _modeOptions, _analyticsMode, (v) { 
                _setMode(v);
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
                backgroundColor: AppPalette.bg(const Color(0xFFF3E5F5)), 
                foregroundColor: AppPalette.fg(pPurple), 
                elevation: 0, 
                side: BorderSide(color: AppPalette.line(Colors.black), width: 1.0),
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
        color: AppPalette.bg(Colors.white), 
        borderRadius: BorderRadius.circular(15), 
        border: Border.all(color: AppPalette.line(Colors.black), width: 1.0),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Unit navigation", style: GoogleFonts.merriweather(fontSize: 14.5, fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.black87))),
              Icon(Icons.tune_rounded, size: 16, color: AppPalette.fg(pPurple)),
            ],
          ),
          Divider(height: 16, color: AppPalette.bg(Colors.black26)),
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
                        color: AppPalette.bg(isSelected ? pPurple : const Color(0xFFFBFBFE)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: AppPalette.fg(isSelected ? Colors.white : Colors.grey), size: 14),
                          const SizedBox(width: 8),
                          Expanded(child: Text(levelName, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(isSelected ? Colors.white : Colors.black87)))),
                          if (isSelected) Icon(Icons.arrow_drop_down, color: AppPalette.fg(Colors.white), size: 16),
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

    Widget pick(String label, List<String> items, String? current, ValueChanged<String> onSelect, {bool allowAll = false}) {
      final List<String> pickList = allowAll ? ["All Locations", ...items] : items;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple))),
          const SizedBox(height: 3),
          _unitDropdown(pickList, current, onSelect),
          const SizedBox(height: 6),
        ],
      );
    }

    final locPicker = pick("Select location:", _locations, _selectedLocation, (v) {
      setState(() => _selectedLocation = (v == "All Locations") ? null : v);
      if (_selectedLocation != null) _fetchSubLocations(_selectedLocation!, triggerFetch: true);
      else _fetchData();
    }, allowAll: true);

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

    // Which pickers show is decided by _pickersFor(), the same rule the
    // query and the modules use, so what you pick is what gets filtered.
    final lv = CompLevel.of(levelName);
    final active = _pickersFor(lv);
    if (active.isNotEmpty) {
      return _pickerContainer([
        if (active.contains('loc')) locPicker,
        if (active.contains('sub')) subPicker,
        if (active.contains('dept')) deptPicker,
        if (active.contains('team')) teamPicker,
      ]);
    }

    if (_isGroupLeader) {
      if (lv == CompLevel.group) return _infoText("Displaying summary for $_groupLeaderCleanDept across all locations");
    } else if (_is24DeptWorker || (_hasDualModeForCurrentDuty && !_dualModeIsChurch)) {
      return _infoText("Displaying summary for ${widget.dept.isNotEmpty ? widget.dept : 'your department'} at Church");
    } else if (_isLocationLeader) {
      if (lv == CompLevel.group) return _infoText("Displaying ${widget.loc} by Book of Life group (교역자, 자문회, 장년회, 부녀회, 청년회)");
      if (lv == CompLevel.location) return _infoText("Displaying summary for your location (${widget.loc})");
      if (lv == CompLevel.subLocation) return _infoText("Displaying all sub-locations under ${widget.loc}");
    } else if (_isSubLocationLeader) {
      if (lv == CompLevel.subLocation) return _infoText("Displaying summary for ${widget.sub}");
      if (lv == CompLevel.dept) return _infoText("Displaying departments under ${widget.sub}");
    } else if (_isDeptLeader) {
      if (lv == CompLevel.dept) return _infoText("Displaying summary for ${widget.dept}");
      if (lv == CompLevel.team) return _infoText("Displaying teams under ${widget.dept}");
    } else if (_isTeamLeader) {
      if (lv == CompLevel.team) return _infoText("Displaying summary for your team (${widget.team})");
      if (lv == CompLevel.cell) return _infoText("Displaying cell groups under ${widget.team}");
    } else if (_isCellLeader) {
      if (lv == CompLevel.cell) return _infoText("Displaying summary for your cell group (${widget.userUnit})");
    } else if (_isChurchWideCompiler) {
      if (lv == CompLevel.church) return _infoText("Displaying general church summary (All Locations, MOU, Church Workers)");
      if (lv == CompLevel.group) return _infoText("Displaying groups based on Book of Life (교역자, 자문회, 장년회, 부녀회, 청년회)");
      if (lv == CompLevel.location) return _infoText("Displaying all church locations including MOU and 24 Dept");
    }

    return const SizedBox.shrink();
  }

  Widget _infoText(String text) => Padding(
    padding: const EdgeInsets.only(left: 14, bottom: 8, top: 2),
    child: Text(text, style: GoogleFonts.merriweather(fontSize: 10, color: AppPalette.fg(pPurple), fontStyle: FontStyle.italic)),
  );

  Widget _pickerContainer(List<Widget> children) => Container(
    margin: const EdgeInsets.only(left: 14, right: 4, bottom: 8),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF3E5F5)), borderRadius: BorderRadius.circular(8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _unitDropdown(List<String> rawItems, String? selected, ValueChanged<String> onChanged) {
    // Duplicate names (e.g. the same team name in two departments) crash a DropdownButton
    final List<String> items = rawItems.toSet().toList();
    if (items.isEmpty) {
      return Text("No units available in this scope", style: GoogleFonts.merriweather(fontSize: 10, color: AppPalette.fg(Colors.grey), fontStyle: FontStyle.italic));
    }
    String val = (selected != null && items.contains(selected)) ? selected : items.first;
    return Container(
      height: 32,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppPalette.line(Colors.purple.shade200))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          isExpanded: true,
          value: val,
          items: items.map((u) => DropdownMenuItem(value: u, child: Text(u, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87))))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  /// "Custom period" shows the chosen dates once a range is picked.
  String _navLabel(String item) {
    if (item == 'Custom period' && _customRange != null) {
      return "Custom: ${DateFormat('d MMM').format(_customRange!.start)} – ${DateFormat('d MMM yyyy').format(_customRange!.end)}";
    }
    return item;
  }

  /// Date range picker in the app's style: a centred card on wide screens
  /// (instead of a full-screen page), purple header and selection.
  Future<DateTimeRange?> _pickCustomRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: today,
      initialDateRange: _customRange ?? DateTimeRange(start: today.subtract(const Duration(days: 27)), end: today),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Select report period',
      saveText: 'Apply',
      cancelText: 'Cancel',
      fieldStartLabelText: 'From',
      fieldEndLabelText: 'To',
      builder: (ctx, child) {
        final base = Theme.of(ctx);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: pPurple,
              onPrimary: Colors.white,
              secondary: pPurple,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              headerBackgroundColor: pPurple,
              headerForegroundColor: Colors.white,
              rangePickerBackgroundColor: Colors.white,
              rangePickerSurfaceTintColor: Colors.transparent,
              rangePickerHeaderBackgroundColor: pPurple,
              rangePickerHeaderForegroundColor: Colors.white,
              rangeSelectionBackgroundColor: pPurple.withValues(alpha: 0.12),
              todayBorder: BorderSide(color: AppPalette.line(pPurple), width: 1.2),
              dayShape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              rangePickerShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            textTheme: GoogleFonts.merriweatherTextTheme(base.textTheme),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppPalette.fg(pPurple),
                textStyle: GoogleFonts.merriweather(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620),
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: child!,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bentoNavCard(String t, List<String> items, String cur, Function(String) onS) => Container(
    margin: const EdgeInsets.only(bottom: 2),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppPalette.bg(Colors.white), 
      borderRadius: BorderRadius.circular(15), 
      border: Border.all(color: AppPalette.line(Colors.black), width: 1.0),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))]
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: GoogleFonts.merriweather(fontSize: 14.5, fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.black87))),
      Divider(height: 16, color: AppPalette.bg(Colors.black26)),
      ...items.map((i) => Padding(padding: const EdgeInsets.only(bottom: 3), child: InkWell(onTap: () => onS(i), child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: AppPalette.bg(cur == i ? pPurple : const Color(0xFFFBFBFE)), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(cur == i ? Icons.check_circle : Icons.circle_outlined, color: AppPalette.fg(cur == i ? Colors.white : Colors.grey), size: 14),
          const SizedBox(width: 8),
          Expanded(child: Text(_navLabel(i), style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(cur == i ? Colors.white : Colors.black87)))),
        ]),
      ))))
    ]),
  );

  Widget _buildAnalysisBox() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), 
    decoration: BoxDecoration(
      color: AppPalette.bg(Colors.white), 
      borderRadius: BorderRadius.circular(16), 
      border: Border.all(color: AppPalette.line(Colors.black), width: 1.0),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))]
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, 
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(
              _getFindingsTitle(), 
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.black87), fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis)),
            Icon(Icons.rate_review_outlined, color: AppPalette.fg(pPurple), size: 18),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _analysisController, 
          focusNode: _findingsFocus,
          minLines: 3,
          maxLines: 5, 
          style: GoogleFonts.merriweather(fontSize: 13), 
          decoration: InputDecoration(
            hintText: tr("Enter analysis, unit status observations, or remarks here..."), 
            hintStyle: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.black38)),
            filled: true, 
            fillColor: AppPalette.bg(const Color(0xFFFBFBFE)), 
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), 
              borderSide: BorderSide(color: AppPalette.line(Colors.black38), width: 1.0),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), 
              borderSide: BorderSide(color: AppPalette.line(Colors.black26), width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), 
              borderSide: BorderSide(color: AppPalette.line(pPurple), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight, 
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.bg(pPurple), 
              foregroundColor: AppPalette.fg(Colors.white), 
              elevation: 0,
              side: BorderSide(color: AppPalette.line(Colors.black), width: 1.0),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ), 
            onPressed: _savingFindings ? null : _submitFindings,
            icon: _savingFindings
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 14),
            label: Text("Submit findings", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _loadRecentFindings,
            icon: const Icon(Icons.history_rounded, size: 16),
            label: Text(_recentFindings.isEmpty ? "Show earlier findings" : "Earlier findings (${_recentFindings.length})",
                style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold)),
          ),
        ),
        for (final f in _recentFindings)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: pPurple.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                "${(f['profiles'] is Map ? f['profiles']['full_name'] : null) ?? 'Manager'} · ${f['period_start']} – ${f['period_end']}",
                style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.blueGrey[700]),
              ),
              const SizedBox(height: 4),
              Text((f['observation'] ?? '').toString(), style: GoogleFonts.merriweather(fontSize: 12, height: 1.4)),
            ]),
          ),
      ],
    ),
  );
}


/// 3D bar chart for the Ranking view: each bar has a front face, a lighter
/// top and a darker side. Gold, silver and bronze for the top three.
class _Bar3DPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final double maxValue;
  final bool isPercent;
  final Color baseColor;

  _Bar3DPainter({
    required this.values,
    required this.labels,
    required this.maxValue,
    required this.isPercent,
    required this.baseColor,
  });

  static const List<Color> _medals = [Color(0xFFD4A017), Color(0xFF90A4AE), Color(0xFFB0764A)];

  void _text(Canvas canvas, String s, Offset at, double size, Color color,
      {bool bold = false, bool center = false, bool alignRight = false, bool vCenter = false, bool above = false, double maxWidth = 120, int maxLines = 1}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: GoogleFonts.merriweather(fontSize: size, color: AppPalette.fg(color), fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
      textDirection: TextDirection.ltr,
      textAlign: center ? TextAlign.center : (alignRight ? TextAlign.right : TextAlign.left),
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    double dx = at.dx, dy = at.dy;
    if (center) dx -= tp.width / 2;
    if (alignRight) dx -= tp.width;
    if (vCenter) dy -= tp.height / 2;
    if (above) dy -= tp.height;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const double left = 46, bottom = 46, top = 30, right = 18;
    final double chartH = size.height - bottom - top;
    final double chartW = size.width - left - right;
    final int n = values.length;
    if (n == 0 || chartH <= 0 || chartW <= 0) return;
    final double slot = chartW / n;
    final double barW = (slot * 0.5).clamp(14.0, 44.0).toDouble();
    final double depth = barW * 0.32;
    final double baseY = top + chartH;

    // Grid lines and value axis
    final grid = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = baseY - chartH * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
      final v = maxValue * i / 4;
      _text(canvas, isPercent ? "${v.round()}%" : "${v.round()}", Offset(left - 6, y), 9, const Color(0x99000000),
          alignRight: true, vCenter: true, maxWidth: 40);
    }
    canvas.drawLine(Offset(left, baseY), Offset(size.width - right, baseY), Paint()..color = const Color(0x55000000)..strokeWidth = 1.2);

    for (int i = 0; i < n; i++) {
      final double v = values[i].clamp(0.0, maxValue).toDouble();
      final double h = maxValue > 0 ? chartH * v / maxValue : 0;
      final double x = left + slot * i + (slot - barW - depth) / 2;
      final double yTop = baseY - h;
      final Color c = i < 3 ? _medals[i] : Color.lerp(baseColor, Colors.white, (i / n) * 0.45)!;

      // Shadow on the floor
      canvas.drawRect(Rect.fromLTWH(x + depth * 0.6, baseY - 2, barW, 4), Paint()..color = const Color(0x18000000));
      // Front, top and side faces
      canvas.drawRect(Rect.fromLTWH(x, yTop, barW, h), Paint()..color = c);
      final topFace = Path()
        ..moveTo(x, yTop)
        ..lineTo(x + depth, yTop - depth)
        ..lineTo(x + barW + depth, yTop - depth)
        ..lineTo(x + barW, yTop)
        ..close();
      canvas.drawPath(topFace, Paint()..color = Color.lerp(c, Colors.white, 0.38)!);
      final sideFace = Path()
        ..moveTo(x + barW, yTop)
        ..lineTo(x + barW + depth, yTop - depth)
        ..lineTo(x + barW + depth, baseY - depth)
        ..lineTo(x + barW, baseY)
        ..close();
      canvas.drawPath(sideFace, Paint()..color = Color.lerp(c, Colors.black, 0.28)!);

      final double cx = x + (barW + depth) / 2;
      _text(canvas, isPercent ? "${values[i].toStringAsFixed(1)}%" : values[i].round().toString(), Offset(cx, yTop - depth - 3), 9.5,
          const Color(0xDD000000), bold: true, center: true, above: true, maxWidth: slot + 10);
      _text(canvas, labels[i], Offset(cx, baseY + 6), 9, const Color(0xDD000000), center: true, maxWidth: slot - 4, maxLines: 2);
    }
  }

  @override
  bool shouldRepaint(covariant _Bar3DPainter old) =>
      old.values != values || old.labels != labels || old.maxValue != maxValue || old.isPercent != isPercent;
}
