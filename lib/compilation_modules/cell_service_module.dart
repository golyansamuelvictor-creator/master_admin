// ignore_for_file: curly_braces_in_flow_control_structures, unused_element
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

class CellServiceModule extends StatefulWidget {
  final List<dynamic> logs;
  final String timePeriod, level, analyticsMode, groupBy;
  final double targetValue;
  final String? activeUnitLabel;

  final String selectedLocation;
  final String selectedSubLocation;
  final String selectedDepartment;
  final String selectedTeam;

  final bool isChurchWide;
  final bool isLocationLeader;
  final bool isSubLocationLeader;
  final bool isDeptLeader;
  final bool isTeamLeader;
  final bool isGroupLeader;

  final String userRole;
  final String userDept;
  final String userSub;
  final String userLoc;
  final String userTeam;

  const CellServiceModule({
    super.key,
    required this.logs,
    required this.timePeriod,
    required this.level,
    required this.analyticsMode,
    required this.groupBy,
    required this.targetValue,
    this.selectedLocation = '',
    this.selectedSubLocation = '',
    this.selectedDepartment = '',
    this.selectedTeam = '',
    this.activeUnitLabel,
    this.isChurchWide = false,
    this.isLocationLeader = false,
    this.isSubLocationLeader = false,
    this.isDeptLeader = false,
    this.isTeamLeader = false,
    this.isGroupLeader = false,
    this.userRole = '',
    this.userDept = '',
    this.userSub = '',
    this.userLoc = '',
    this.userTeam = '',
  });

  @override
  State<CellServiceModule> createState() => _CellServiceModuleState();
}

class _CellServiceModuleState extends State<CellServiceModule> {
  final _supabase = Supabase.instance.client;
  final Color pPurple = const Color(0xFF4A148C);

  String _selectedTrendMetric = "General Attendance";

  final List<String> _orderedBOLGroups = ["교역자", "자문회", "장년회", "부녀회", "청년회"];
  final List<String> _orderedLocations = [
    "24Dept", "MOU", "New Location", "Wakiso", "Lubaga", "Busega",
    "Kawempe", "Makerere", "Makindye", "Nakawa", "Mukono", "Entebbe", "UAE"
  ];
  final List<String> _orderedDepartments = ["장년회", "부녀회", "청년회", "신학부", "새신자"];

  List<String> _masterSubLocations = [];
  List<Map<String, dynamic>> _masterMembers = [];

  // Table Sizing
  static const double rh = 24.0;
  static const double hh = 30.0;
  static const double sh = 20.0;
  static const double cw = 65.0;
  static const double lw = 115.0;
  static const double totalHeaderHeight = hh + hh + sh;

  bool get _is24ChurchDept {
    final r = widget.userRole.toLowerCase();
    final d = widget.userDept.toLowerCase();
    return (r.contains('_dept_') || r.startsWith('ia_') || d.contains('내무')) &&
        !widget.isLocationLeader &&
        !widget.isSubLocationLeader &&
        !widget.isDeptLeader &&
        !widget.isTeamLeader &&
        !widget.isGroupLeader;
  }

  @override
  void initState() {
    super.initState();
    _fetchMasterUnitsAndMembers();
  }

  @override
  void didUpdateWidget(covariant CellServiceModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedLocation != widget.selectedLocation ||
        oldWidget.selectedSubLocation != widget.selectedSubLocation ||
        oldWidget.selectedDepartment != widget.selectedDepartment ||
        oldWidget.selectedTeam != widget.selectedTeam ||
        oldWidget.level != widget.level ||
        oldWidget.timePeriod != widget.timePeriod ||
        oldWidget.analyticsMode != widget.analyticsMode ||
        oldWidget.groupBy != widget.groupBy ||
        oldWidget.logs != widget.logs) {
      _fetchMasterUnitsAndMembers();
    }
  }

  Future<void> _fetchMasterUnitsAndMembers() async {
    try {
      final lvl = widget.level.toLowerCase();

      // 1. Fetch sub-locations for selected location excluding MOU
      String locToFetch = widget.selectedLocation.isNotEmpty ? widget.selectedLocation : widget.userLoc;
      if ((lvl.contains('sub location') || lvl.contains('sub-location')) && locToFetch.isNotEmpty && locToFetch.toLowerCase() != 'church') {
        final locRes = await _supabase.from('locations').select('id, location, name').or('location.eq.$locToFetch,name.eq.$locToFetch').maybeSingle();
        if (locRes != null && locRes['id'] != null) {
          final subData = await _supabase.from('sub_locations').select('name, is_mou').eq('location_id', locRes['id']).order('name');
          if (mounted) {
            bool isViewingMou = locToFetch.toUpperCase() == 'MOU';
            setState(() {
              _masterSubLocations = subData
                  .where((e) => isViewingMou ? (e['is_mou'] == true) : (e['is_mou'] != true))
                  .map((e) => e['name'].toString())
                  .toList();
            });
          }
        }
      }

      // 2. Targeted fetch of members (Scoped to prevent 8,000-member dump)
      dynamic mQuery = _supabase.from('members').select(
        'id, location, sub_location, department, team, cell_group, reg_status, geo_category, book_of_life, bol_dept, official_dept_id'
      );

      if (_is24ChurchDept && widget.groupBy == 'Church') {
        mQuery = mQuery.or('location.eq.Church,location.eq.Church Workers,location.eq.Church Main,location.is.null');
        if (widget.userDept.isNotEmpty && widget.userDept != 'Church') {
          mQuery = mQuery.eq('department', widget.userDept);
        }
      } else if (widget.isGroupLeader && widget.userDept.isNotEmpty) {
        mQuery = mQuery.eq('department', widget.userDept).neq('location', 'Mou').neq('location', 'New Saints');
      } else if (!widget.isChurchWide) {
        if (widget.userLoc.isNotEmpty && widget.userLoc != 'Church') {
          mQuery = mQuery.eq('location', widget.userLoc);
        }
        if (widget.isSubLocationLeader && widget.userSub.isNotEmpty) {
          mQuery = mQuery.eq('sub_location', widget.userSub);
        }
        if (widget.isDeptLeader && widget.userDept.isNotEmpty) {
          mQuery = mQuery.eq('department', widget.userDept);
        }
      }

      if (lvl.contains('sub location') || lvl.contains('sub-location')) {
        if (widget.selectedLocation.isNotEmpty && widget.selectedLocation.toLowerCase() != 'church') {
          mQuery = mQuery.eq('location', widget.selectedLocation);
        }
      } else if (lvl.contains('dept') && !_is24ChurchDept) {
        if (widget.selectedLocation.isNotEmpty && widget.selectedLocation.toLowerCase() != 'church') {
          mQuery = mQuery.eq('location', widget.selectedLocation);
        }
        if (widget.selectedSubLocation.isNotEmpty) {
          mQuery = mQuery.eq('sub_location', widget.selectedSubLocation);
        }
      } else if (lvl.contains('team')) {
        if (widget.selectedLocation.isNotEmpty && widget.selectedLocation.toLowerCase() != 'church') {
          mQuery = mQuery.eq('location', widget.selectedLocation);
        }
        if (widget.selectedSubLocation.isNotEmpty) {
          mQuery = mQuery.eq('sub_location', widget.selectedSubLocation);
        }
        if (!widget.isGroupLeader && widget.selectedDepartment.isNotEmpty) {
          mQuery = mQuery.eq('department', widget.selectedDepartment);
        }
      } else if (lvl.contains('cell')) {
        if (widget.selectedLocation.isNotEmpty && widget.selectedLocation.toLowerCase() != 'church') {
          mQuery = mQuery.eq('location', widget.selectedLocation);
        }
        if (widget.selectedSubLocation.isNotEmpty) {
          mQuery = mQuery.eq('sub_location', widget.selectedSubLocation);
        }
        if (!widget.isGroupLeader && widget.selectedDepartment.isNotEmpty) {
          mQuery = mQuery.eq('department', widget.selectedDepartment);
        }
        if (widget.selectedTeam.isNotEmpty) {
          mQuery = mQuery.eq('team', widget.selectedTeam);
        }
      }

      List<Map<String, dynamic>> allMembers = [];
      int offset = 0;
      const int pageSize = 1000;
      while (true) {
        final chunk = await mQuery.range(offset, offset + pageSize - 1);
        final list = List<Map<String, dynamic>>.from(chunk);
        allMembers.addAll(list);
        if (list.length < pageSize) break;
        offset += pageSize;
      }

      if (mounted) setState(() => _masterMembers = allMembers);
    } catch (e) {
      debugPrint("Cell Service Master Fetch Error: $e");
    }
  }

  String _resolveLocationBucket(dynamic record) {
    String dept = (record['department'] ?? record['members']?['department'] ?? '').toString().trim().toUpperCase();
    if (dept.contains('MOU')) return 'MOU';

    String loc = (record['location'] ?? record['members']?['location'] ?? '').toString().trim();
    String locLower = loc.toLowerCase();

    if (locLower == '24dept' || locLower == '24부서' || locLower == 'church' || locLower == '교회') {
      return '24Dept';
    }
    return loc;
  }

  List<String> _sortAscending(List<String> items) {
    int extractNumber(String s) {
      final match = RegExp(r'\d+').firstMatch(s);
      return match != null ? int.parse(match.group(0)!) : 999999;
    }
    final sorted = List<String>.from(items);
    sorted.sort((a, b) {
      int numA = extractNumber(a);
      int numB = extractNumber(b);
      if (numA != numB) return numA.compareTo(numB);
      return a.compareTo(b);
    });
    return sorted;
  }

  List<String> _getScopedTeams() {
    final Set<String> teams = {};
    for (var m in _masterMembers) {
      final t = m['team']?.toString().trim() ?? '';
      if (t.isNotEmpty) teams.add(t);
    }
    return _sortAscending(teams.toList());
  }

  List<String> _getScopedCellGroups() {
    final Set<String> cells = {};
    for (var m in _masterMembers) {
      final c = m['cell_group']?.toString().trim() ?? '';
      if (c.isNotEmpty) cells.add(c);
    }
    return _sortAscending(cells.toList());
  }

  // --- CALCULATION ENGINE ---
  Map<String, dynamic> _calc(List<dynamic> logsList, {List<dynamic>? officialMembers}) {
    int n = officialMembers != null ? officialMembers.length : logsList.length;

    int ip = logsList.where((x) => x['status_detail'] == "CS In-Person" || x['status_detail'] == "In-person").length;
    int on = logsList.where((x) => x['status_detail'] == "CS Online" || x['status_detail'] == "Online" || x['status_detail'] == "On-line").length;
    int mu = logsList.where((x) => x['status_detail'] == "CS Make Up" || x['status_detail'] == "Make Up" || x['status_detail'] == "Makeup").length;
    int att = ip + on + mu;
    int ab = n > att ? (n - att) : logsList.where((x) => x['status_detail'] == "CS Absentee" || x['status_detail'] == "Absentee").length;

    return {
      "n": n,
      "att": att,
      "pct": n > 0 ? (att / n * 100) : 0.0,
      "ip": ip,
      "ipp": n > 0 ? (ip / n * 100) : 0.0,
      "on": on,
      "onp": n > 0 ? (on / n * 100) : 0.0,
      "mu": mu,
      "mup": n > 0 ? (mu / n * 100) : 0.0,
      "ab": ab,
      "abp": n > 0 ? (ab / n * 100) : 0.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> totS = _calc(widget.logs, officialMembers: _masterMembers.isNotEmpty ? _masterMembers : null);

    return Column(children: [
      _buildToolbar(),
      _section("Cell service table summary", _buildExcelGrid(totS), context),
      const SizedBox(height: 8),
      _section("Participation visualization", _buildChart(totS), context),
    ]);
  }

  Widget _buildToolbar() => Row(
    mainAxisAlignment: MainAxisAlignment.start,
    children: [
      IconButton(onPressed: _printReport, icon: const Icon(Icons.print, color: Colors.blueGrey, size: 18)),
      IconButton(onPressed: () {}, icon: const Icon(Icons.download, color: Colors.green, size: 18)),
    ],
  );

  Widget _buildExcelGrid(Map<String, dynamic> tot) {
    Widget? childRows = _buildDynamicHierarchicalRows();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 1.0)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildMergedHeader(),
            _mergedRow("Total", "General total", tot, b: true),
            if (childRows != null) childRows,
          ]),
        ),
      ),
    );
  }

  // --- DYNAMIC ROWS (ELIMINATES DUPLICATES IN TABLE) ---
  Widget? _buildDynamicHierarchicalRows() {
    final String lvl = widget.level.trim().toLowerCase();

    // Avoid redundant row when viewing own unit tier
    if (lvl == 'church status') return null;
    if (_is24ChurchDept || widget.groupBy == 'Church') return null;
    if (widget.isLocationLeader && lvl == 'location status') return null;
    if (widget.isSubLocationLeader && (lvl.contains('sub location') || lvl.contains('sub-location'))) return null;
    if (widget.isDeptLeader && lvl == 'dept status') return null;
    if (widget.isTeamLeader && lvl == 'team status') return null;
    if (widget.isGroupLeader && lvl.contains('group')) return null;

    Map<String, List<dynamic>> groupedLogs = {};
    Map<String, List<dynamic>> groupedMembers = {};
    String categoryName = widget.activeUnitLabel ?? "Unit";

    String extract(dynamic l, List<String> keys) {
      for (var k in keys) {
        var v = l['members']?[k] ?? l[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }

    // 1. GROUP STATUS (BOOK OF LIFE)
    if (lvl.contains('group status')) {
      categoryName = "Book of Life";
      for (var g in _orderedBOLGroups) {
        groupedLogs[g] = [];
        groupedMembers[g] = [];
      }
      for (var m in _masterMembers) {
        String bol = m['book_of_life']?.toString() ?? m['bol_dept']?.toString() ?? '';
        if (groupedMembers.containsKey(bol)) groupedMembers[bol]!.add(m);
      }
      for (var l in widget.logs) {
        String bol = extract(l, ['book_of_life', 'bol_dept']);
        if (groupedLogs.containsKey(bol)) groupedLogs[bol]!.add(l);
      }
    }
    // 2. SUB-LOCATION STATUS (Supports Dept Leader overseeing all sub-locations)
    else if (lvl.contains('sub location') || lvl.contains('sub-location')) {
      categoryName = widget.selectedLocation.isNotEmpty ? widget.selectedLocation : (widget.userLoc.isNotEmpty ? widget.userLoc : "Sub-locations");

      final Set<String> subLocs = Set.from(_masterSubLocations);
      for (var m in _masterMembers) {
        String sub = m['sub_location']?.toString().trim() ?? '';
        if (sub.isNotEmpty) subLocs.add(sub);
      }
      for (var l in widget.logs) {
        String sub = extract(l, ['sub_location', 'sub_loc']);
        if (sub.isNotEmpty) subLocs.add(sub);
      }

      for (var sub in subLocs) {
        groupedLogs[sub] = [];
        groupedMembers[sub] = [];
      }
      for (var m in _masterMembers) {
        String sub = m['sub_location']?.toString().trim() ?? '';
        if (sub.isNotEmpty) groupedMembers.putIfAbsent(sub, () => []).add(m);
      }
      for (var l in widget.logs) {
        String sub = extract(l, ['sub_location', 'sub_loc']);
        if (sub.isNotEmpty) groupedLogs.putIfAbsent(sub, () => []).add(l);
      }
    }
    // 3. LOCATION STATUS
    else if (lvl.contains('location status')) {
      categoryName = "Location";
      for (var loc in _orderedLocations) {
        groupedLogs[loc] = [];
        groupedMembers[loc] = [];
      }
      for (var m in _masterMembers) {
        String bucket = _resolveLocationBucket(m);
        if (groupedMembers.containsKey(bucket)) {
          groupedMembers[bucket]!.add(m);
        } else if (bucket.isNotEmpty) {
          groupedMembers.putIfAbsent(bucket, () => []).add(m);
        }
      }
      for (var l in widget.logs) {
        String bucket = _resolveLocationBucket(l);
        if (groupedLogs.containsKey(bucket)) {
          groupedLogs[bucket]!.add(l);
        } else if (bucket.isNotEmpty && bucket.toLowerCase() != 'church') {
          groupedLogs.putIfAbsent(bucket, () => []).add(l);
        }
      }
    }
    // 4. DEPT STATUS (Location Departments only)
    else if (lvl.contains('dept')) {
      categoryName = widget.selectedSubLocation.isNotEmpty ? widget.selectedSubLocation : "Department";
      
      for (var d in _orderedDepartments) {
        groupedLogs[d] = [];
        groupedMembers[d] = [];
      }
      for (var m in _masterMembers) {
        String dept = m['department']?.toString().trim() ?? '';
        if (groupedMembers.containsKey(dept)) {
          groupedMembers[dept]!.add(m);
        } else if (dept.isNotEmpty) {
          groupedMembers.putIfAbsent(dept, () => []).add(m);
        }
      }
      for (var l in widget.logs) {
        String dept = extract(l, ['department', 'dept', 'dept_name']);
        if (groupedLogs.containsKey(dept)) {
          groupedLogs[dept]!.add(l);
        } else if (dept.isNotEmpty) {
          groupedLogs.putIfAbsent(dept, () => []).add(l);
        }
      }
    }
    // 5. TEAM STATUS
    else if (lvl.contains('team')) {
      categoryName = widget.selectedDepartment.isNotEmpty ? widget.selectedDepartment : "Team";
      final List<String> distinctTeams = _getScopedTeams();

      for (var t in distinctTeams) {
        groupedLogs[t] = [];
        groupedMembers[t] = [];
      }
      for (var m in _masterMembers) {
        String team = m['team']?.toString().trim() ?? '';
        if (team.isNotEmpty) groupedMembers.putIfAbsent(team, () => []).add(m);
      }
      for (var l in widget.logs) {
        String team = extract(l, ['team', 'team_name']);
        if (team.isNotEmpty) groupedLogs.putIfAbsent(team, () => []).add(l);
      }
    }
    // 6. CELL STATUS
    else if (lvl.contains('cell')) {
      categoryName = widget.selectedTeam.isNotEmpty ? widget.selectedTeam : "Cell groups";
      final List<String> distinctCells = _getScopedCellGroups();

      for (var cg in distinctCells) {
        groupedLogs[cg] = [];
        groupedMembers[cg] = [];
      }
      for (var m in _masterMembers) {
        String cell = m['cell_group']?.toString().trim() ?? '';
        if (cell.isNotEmpty) groupedMembers.putIfAbsent(cell, () => []).add(m);
      }
      for (var l in widget.logs) {
        String cell = extract(l, ['unit_name', 'cell_group', 'cell', 'cell_name']);
        if (cell.isNotEmpty) groupedLogs.putIfAbsent(cell, () => []).add(l);
      }
    }

    if (groupedLogs.isEmpty) return null;

    Map<String, dynamic> calculatedBlocks = {};
    groupedLogs.forEach((unitKey, logs) {
      calculatedBlocks[unitKey] = _calc(logs, officialMembers: groupedMembers[unitKey]);
    });

    return _mergedBlock(categoryName, calculatedBlocks);
  }

  Widget _buildMergedHeader() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cell("Classification", w: lw, h: totalHeaderHeight, b: true, bg: const Color(0xFFF8FAFC)),
      _cell("Unit", w: lw, h: totalHeaderHeight, b: true, bg: const Color(0xFFF8FAFC)),
      Column(children: [
        Row(children: [
          _cell("Summary", w: cw * 11, h: hh, b: true, bg: const Color(0xFFF8FAFC)),
        ]),
        Row(children: [
          _cell("Overall metrics", w: cw * 3, h: hh, b: true),
          _cell("In-person", w: cw * 2, h: hh, b: true),
          _cell("Online", w: cw * 2, h: hh, b: true),
          _cell("Makeup", w: cw * 2, h: hh, b: true),
          _cell("Absentees", w: cw * 2, h: hh, b: true),
        ]),
        Row(children: [
          _cell("Num", w: cw, h: sh), _cell("Att", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
        ]),
      ]),
    ]);
  }

  Widget _mergedBlock(String label, Map<String, dynamic> children) {
    List<Widget> rows = [];
    children.forEach((k, v) => rows.add(_dataRow(k, v)));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cell(label, w: lw, h: (rows.length * rh).toDouble(), b: true, bg: const Color(0xFFFAF5FF)),
      Column(children: rows),
    ]);
  }

  Widget _mergedRow(String c1, String c2, Map<String, dynamic> d, {bool b = false}) => Row(children: [
    _cell(c1, w: lw, h: rh, b: b, bg: const Color(0xFFF3E5F5)),
    _dataRow(c2, d, b: b),
  ]);

  Widget _dataRow(String label, Map<String, dynamic> d, {bool b = false}) {
    return Row(children: [
      _cell(label, w: lw, h: rh, b: b, a: Alignment.center),
      _cell("${d['n']}", a: Alignment.center),
      _cell("${d['att']}", a: Alignment.center),
      _cell("${d['pct'].toStringAsFixed(1)}%", b: true, a: Alignment.center),
      _cell("${d['ip']}", a: Alignment.center),
      _cell("${d['ipp'].toStringAsFixed(1)}%", a: Alignment.center),
      _cell("${d['on']}", a: Alignment.center),
      _cell("${d['onp'].toStringAsFixed(1)}%", a: Alignment.center),
      _cell("${d['mu']}", a: Alignment.center),
      _cell("${d['mup'].toStringAsFixed(1)}%", a: Alignment.center),
      _cell("${d['ab']}", color: Colors.red[800], a: Alignment.center),
      _cell("${d['abp'].toStringAsFixed(1)}%", a: Alignment.center),
    ]);
  }

  Widget _cell(
    String t, {
    double? w,
    double h = rh,
    bool b = false,
    Color? color,
    Color? bg,
    Alignment a = Alignment.center,
  }) {
    return Container(
      width: w ?? cw,
      height: h,
      alignment: a,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(color: bg ?? Colors.white, border: Border.all(color: Colors.black45, width: 0.4)),
      child: Text(
        t,
        textAlign: TextAlign.center,
        style: GoogleFonts.merriweather(fontSize: 9.5, fontWeight: b ? FontWeight.w900 : FontWeight.normal, color: color ?? Colors.black87),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
  // Generates the dynamic X-axis label based on the active level
  String _getDynamicXAxisLabel() {
    final lvl = widget.level.toLowerCase();
    if (_is24ChurchDept || widget.groupBy == 'Church') {
      return widget.userDept.isNotEmpty ? widget.userDept : 'Department Summary';
    }
    if (widget.isGroupLeader && lvl.contains('location status')) {
      return '${widget.userDept} across Locations';
    }
    if (lvl.contains('church')) return 'Church Results';
    if (lvl.contains('group')) return 'Book of Life Groups';
    if (lvl.contains('sub location') || lvl.contains('sub-location')) {
      return widget.selectedLocation.isNotEmpty ? '${widget.selectedLocation} Sub-locations' : 'Sub-locations';
    }
    if (lvl.contains('location status')) return 'Locations';
    if (lvl.contains('dept')) {
      return widget.selectedSubLocation.isNotEmpty ? '${widget.selectedSubLocation} Departments' : 'Departments';
    }
    if (lvl.contains('team')) {
      return widget.selectedDepartment.isNotEmpty ? '${widget.selectedDepartment} Teams' : 'Teams';
    }
    if (lvl.contains('cell')) {
      return widget.selectedTeam.isNotEmpty ? '${widget.selectedTeam} Cell Groups' : 'Cell Groups';
    }
    return widget.groupBy;
  }
  
  // --- RESTORED: MULTI-DAY PERIODS ALWAYS RENDER LINE CHART ---
  Widget _buildChart(Map<String, dynamic> totSummary) {
    // RESTORED ORIGINAL LOGIC: Any multi-day period always renders the Line Chart
    bool isTrend = widget.timePeriod != "Current status";
    final lvl = widget.level.toLowerCase();

    // ─────────────────────────────────────────────────────────────────────────
    // CASE A: 1-DAY SNAPSHOT (CURRENT STATUS ONLY) -> BAR CHART
    // ─────────────────────────────────────────────────────────────────────────
    if (!isTrend) {
      String xName = _getDynamicXAxisLabel();
      List<String> keys = _getUnitKeysForLevel(lvl);

      // Single unit/24-dept: clean breakdown bars
      if (keys.isEmpty || keys.length == 1 || _is24ChurchDept) {
        final double nVal = (totSummary['n'] as num?)?.toDouble() ?? 0.0;
        final double attVal = (totSummary['att'] as num?)?.toDouble() ?? 0.0;
        final double ipVal = (totSummary['ip'] as num?)?.toDouble() ?? 0.0;
        final double onVal = (totSummary['on'] as num?)?.toDouble() ?? 0.0;
        final double muVal = (totSummary['mu'] as num?)?.toDouble() ?? 0.0;
        final double abVal = (totSummary['ab'] as num?)?.toDouble() ?? 0.0;

        final double dynamicMaxY = (max(nVal, max(attVal, abVal)) * 1.25).ceilToDouble();

        final List<_CellBarMetric> metrics = [
          _CellBarMetric("Saints (N)", nVal, Colors.grey.shade500),
          _CellBarMetric("Attended", attVal, pPurple),
          _CellBarMetric("In-person", ipVal, Colors.indigo),
          _CellBarMetric("Online", onVal, Colors.teal),
          _CellBarMetric("Make-up", muVal, Colors.orange),
          _CellBarMetric("Absentees", abVal, Colors.red.shade400),
        ];

        return Column(children: [
          Container(
            height: 320,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: BarChart(BarChartData(
              maxY: dynamicMaxY > 0 ? dynamicMaxY : 10,
              borderData: FlBorderData(show: true, border: const Border(left: BorderSide(color: Colors.black, width: 1.0), bottom: BorderSide(color: Colors.black, width: 1.0))),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  axisNameWidget: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(xName, style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                  axisNameSize: 28,
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, m) {
                      int idx = v.toInt();
                      if (idx < 0 || idx >= metrics.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(metrics[idx].label, style: GoogleFonts.merriweather(fontSize: 9.5, fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  axisNameWidget: Text("Persons", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold)),
                  axisNameSize: 22,
                  sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, m) => Text("${v.toInt()}", style: GoogleFonts.merriweather(fontSize: 9.5))),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: List.generate(metrics.length, (i) {
                return BarChartGroupData(x: i, barRods: [
                  BarChartRodData(toY: metrics[i].val, color: metrics[i].color, width: 34, borderRadius: BorderRadius.circular(4))
                ]);
              }),
            )),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: metrics.map((m) => _lgItem("${m.label}: ${m.val.toInt()}", m.color)).toList(),
            ),
          ),
        ]);
      }

      // RESTORED ORIGINAL: Multi-unit 3-rod comparison bar chart
      Map<String, List<dynamic>> cgLogs = {};
      Map<String, List<dynamic>> cgMembers = {};

      for (var k in keys) {
        cgLogs[k] = [];
        cgMembers[k] = [];
      }

      for (var m in _masterMembers) {
        String b = _resolveUnitKeyForRecord(m, lvl);
        if (cgMembers.containsKey(b)) cgMembers[b]!.add(m);
      }
      for (var l in widget.logs) {
        String b = _resolveUnitKeyForRecord(l, lvl);
        if (cgLogs.containsKey(b)) cgLogs[b]!.add(l);
      }

      double maxHeadcount = 10.0;
      for (var key in keys) {
        final s = _calc(cgLogs[key] ?? [], officialMembers: cgMembers[key]);
        final double nVal = (s['n'] as num?)?.toDouble() ?? 0.0;
        final double attVal = (s['att'] as num?)?.toDouble() ?? 0.0;
        final double ipVal = (s['ip'] as num?)?.toDouble() ?? 0.0;
        final double highest = max<double>(nVal, max<double>(attVal, ipVal));
        if (highest > maxHeadcount) maxHeadcount = highest;
      }
      double dynamicMaxY = (maxHeadcount * 1.25).ceilToDouble();

      return Column(children: [
        Container(
          height: 360,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: _barChart(xName, keys, cgLogs, cgMembers, dynamicMaxY),
        ),
        Padding(padding: const EdgeInsets.only(top: 10, bottom: 5), child: _buildBarLegend()),
      ]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CASE B: TREND OVER TIME (WEEKLY / MONTHLY / YEARLY) -> MULTI-LINE OVER DATES
    // ─────────────────────────────────────────────────────────────────────────
    final Set<String> rawDates = {};
    for (var l in widget.logs) {
      final d = l['report_date']?.toString();
      if (d != null && d.isNotEmpty) rawDates.add(d);
    }
    final List<String> sortedDates = rawDates.toList()..sort();

    if (sortedDates.isEmpty) {
      return SizedBox(
        height: 200, 
        child: Center(
          child: Text(
            "No historical records found for this period",
            style: GoogleFonts.merriweather(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
      );
    }

    // RESTORED: Generates the true unit keys for plotting all line curves
    final List<String> unitKeys = _getUnitKeysForLevel(lvl);

    final List<Color> palette = [
      pPurple,
      Colors.blue.shade700,
      Colors.teal.shade600,
      Colors.orange.shade800,
      Colors.deepOrange,
      Colors.pink.shade700,
      Colors.indigo.shade600,
      Colors.green.shade800,
      Colors.brown,
      Colors.amber.shade900,
      Colors.cyan.shade800,
      Colors.purpleAccent.shade700,
      Colors.blueGrey,
    ];

    double maxTrendValue = 10.0;
    final List<LineChartBarData> lineBars = [];

    // Single unit/dept: clean single trend curve
    if (unitKeys.isEmpty || _is24ChurchDept) {
      final List<FlSpot> spots = [];
      for (int d = 0; d < sortedDates.length; d++) {
        final dateStr = sortedDates[d];
        final dateLogs = widget.logs.where((l) => l['report_date']?.toString() == dateStr).toList();
        final calc = _calc(dateLogs);
        double val = _selectedTrendMetric == "General Attendance" ? (calc['att'] as num).toDouble() : (calc['ip'] as num).toDouble();
        if (val > maxTrendValue) maxTrendValue = val;
        spots.add(FlSpot(d.toDouble(), val));
      }
      lineBars.add(LineChartBarData(
        spots: spots,
        color: pPurple,
        barWidth: 3.0,
        isCurved: true,
        dotData: const FlDotData(show: true),
      ));
    } else {
      // Multi-unit: Dedicated curve per unit across the selected level
      for (int u = 0; u < unitKeys.length; u++) {
        final unitName = unitKeys[u];
        final Color unitColor = palette[u % palette.length];
        final List<FlSpot> spots = [];

        for (int d = 0; d < sortedDates.length; d++) {
          final dateStr = sortedDates[d];
          final dateLogs = widget.logs.where((l) {
            final matchesDate = l['report_date']?.toString() == dateStr;
            final matchesUnit = _resolveUnitKeyForRecord(l, lvl) == unitName;
            return matchesDate && matchesUnit;
          }).toList();

          final calc = _calc(dateLogs);
          double val = _selectedTrendMetric == "General Attendance" ? (calc['att'] as num).toDouble() : (calc['ip'] as num).toDouble();
          if (val > maxTrendValue) maxTrendValue = val;
          spots.add(FlSpot(d.toDouble(), val));
        }

        lineBars.add(LineChartBarData(
          spots: spots,
          color: unitColor,
          barWidth: 2.5,
          isCurved: true,
          dotData: const FlDotData(show: true),
        ));
      }
    }

    double dynamicMaxY = (maxTrendValue * 1.25).ceilToDouble();

    List<String> formattedDates = sortedDates.map((d) {
      if (d.length >= 10) return "${d.substring(5, 7)}/${d.substring(8, 10)}";
      return d;
    }).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Trend by Date", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: const Color(0xFFF3E5F5), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.purple.shade200)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTrendMetric,
                  icon: const Icon(Icons.tune, size: 14),
                  style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple),
                  items: ["General Attendance", "In-person"].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedTrendMetric = v);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      Container(
        height: 340,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        child: LineChart(LineChartData(
          maxY: dynamicMaxY,
          borderData: FlBorderData(show: true, border: const Border(left: BorderSide(color: Colors.black, width: 1.0), bottom: BorderSide(color: Colors.black, width: 1.0))),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              axisNameWidget: Text("Service Date (MM/DD)", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold)),
              axisNameSize: 22,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1.0,
                getTitlesWidget: (v, m) {
                  int idx = v.toInt();
                  if (idx < 0 || idx >= formattedDates.length || v != idx.toDouble()) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(formattedDates[idx], style: GoogleFonts.merriweather(fontSize: 9.5, fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: Text("$_selectedTrendMetric (Persons)", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold)),
              axisNameSize: 22,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (v, m) => Text("${v.toInt()}", style: GoogleFonts.merriweather(fontSize: 9.5)),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: lineBars,
        )),
      ),
      // FULL RESTORED LEGEND FOR MULTI-LINE CURVES
      if (unitKeys.isNotEmpty && !_is24ChurchDept)
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Center(
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: List.generate(unitKeys.length, (i) => _lgItem(unitKeys[i], palette[i % palette.length])),
            ),
          ),
        ),
    ]);
  }

  // RESTORED: Provides all units for the current level to plot multi-line curves
  List<String> _getUnitKeysForLevel(String lvl) {
    if (_is24ChurchDept) {
      return [];
    }
    if (lvl.contains('church')) return ["Church (Overall)"];
    if (lvl.contains('group')) return List.from(_orderedBOLGroups);
    if (lvl.contains('sub location') || lvl.contains('sub-location')) {
      final Set<String> subs = Set.from(_masterSubLocations);
      for (var m in _masterMembers) {
        final s = m['sub_location']?.toString().trim() ?? '';
        if (s.isNotEmpty) subs.add(s);
      }
      return subs.isNotEmpty ? _sortAscending(subs.toList()) : [];
    }
    if (lvl.contains('location status')) {
      if (widget.isLocationLeader && widget.selectedLocation.isNotEmpty) {
        return [widget.selectedLocation];
      }
      return List.from(_orderedLocations);
    }
    if (lvl.contains('dept')) {
      if (widget.isDeptLeader && widget.userDept.isNotEmpty) return [widget.userDept];
      return List.from(_orderedDepartments);
    }
    if (lvl.contains('team')) {
      final teams = _getScopedTeams();
      return teams.isNotEmpty ? teams : [];
    }
    if (lvl.contains('cell')) {
      final cells = _getScopedCellGroups();
      return cells.isNotEmpty ? cells : [];
    }
    return [];
  }

  String _resolveUnitKeyForRecord(dynamic record, String lvl) {
    if (lvl.contains('church')) return "Church (Overall)";
    if (lvl.contains('group')) {
      return (record['book_of_life'] ?? record['members']?['book_of_life'] ?? record['bol_dept'] ?? '').toString();
    }
    if (lvl.contains('sub location') || lvl.contains('sub-location')) {
      return (record['sub_location'] ?? record['members']?['sub_location'] ?? '').toString();
    }
    if (lvl.contains('location status')) {
      return _resolveLocationBucket(record);
    }
    if (lvl.contains('dept')) {
      return (record['department'] ?? record['members']?['department'] ?? '').toString();
    }
    if (lvl.contains('team')) {
      return (record['team'] ?? record['members']?['team'] ?? '').toString();
    }
    if (lvl.contains('cell')) {
      return (record['unit_name'] ?? record['cell_group'] ?? record['members']?['cell_group'] ?? '').toString();
    }
    return '';
  }

  Widget _barChart(String xN, List<String> ks, Map<String, List<dynamic>> gsLogs, Map<String, List<dynamic>> gsMembers, double maxY) => BarChart(BarChartData(
    maxY: maxY,
    borderData: FlBorderData(show: true, border: const Border(left: BorderSide(color: Colors.black, width: 1.0), bottom: BorderSide(color: Colors.black, width: 1.0))),
    titlesData: FlTitlesData(
      bottomTitles: AxisTitles(
        axisNameWidget: Padding(
          padding: const EdgeInsets.only(top: 15),
          child: Text(xN, style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold)),
        ),
        axisNameSize: 32,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 50,
          interval: 1.0,
          getTitlesWidget: (v, m) {
            int index = v.toInt();
            if (index < 0 || index >= ks.length || v != index.toDouble()) return const SizedBox.shrink();
            return Transform.rotate(
              angle: -0.45,
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(ks[index], style: GoogleFonts.merriweather(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black87), overflow: TextOverflow.ellipsis),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        axisNameWidget: Text("Headcount (Persons)", style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold)),
        axisNameSize: 22,
        sideTitles: SideTitles(showTitles: true, reservedSize: 42, getTitlesWidget: (v, m) => Text("${v.toInt()}", style: GoogleFonts.merriweather(fontSize: 10))),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    ),
    gridData: const FlGridData(show: true, drawVerticalLine: false),
    barGroups: List.generate(ks.length, (i) {
      final s = _calc(gsLogs[ks[i]] ?? [], officialMembers: gsMembers[ks[i]]);
      return BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: (s['n'] as num).toDouble(), color: Colors.grey.shade400, width: 7, borderRadius: BorderRadius.circular(2)),
        BarChartRodData(toY: (s['att'] as num).toDouble(), color: pPurple, width: 7, borderRadius: BorderRadius.circular(2)),
        BarChartRodData(toY: (s['ip'] as num).toDouble(), color: Colors.blue.shade600, width: 7, borderRadius: BorderRadius.circular(2)),
      ]);
    }),
  ));

  Widget _buildBarLegend() => Center(
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 20,
      runSpacing: 6,
      children: [
        _lgItem("Saints (Num)", Colors.grey.shade400),
        _lgItem("General Att (Att)", pPurple),
        _lgItem("In-person", Colors.blue.shade600),
      ],
    ),
  );

  Widget _lgItem(String t, Color c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 5),
      Text(t, style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
    ],
  );

  Future<void> _printReport() async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Text("Cell Group Service Report"))));
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Widget _section(String title, Widget content, BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.black, width: 1.0),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Column(children: [
      ListTile(
        dense: true,
        title: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14.5, color: pPurple)),
        trailing: IconButton(
          icon: const Icon(Icons.fullscreen, size: 18),
          onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (c) => Scaffold(
              appBar: AppBar(title: Text(title, style: GoogleFonts.merriweather())),
              body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(8), child: content)),
            ),
          )),
        ),
      ),
      const Divider(height: 1, color: Colors.black26),
      content,
    ]),
  );
}

class _CellBarMetric {
  final String label;
  final double val;
  final Color color;
  _CellBarMetric(this.label, this.val, this.color);
}