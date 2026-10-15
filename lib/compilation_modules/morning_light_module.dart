// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, dead_null_aware_expression, unused_import
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

class MorningLightModule extends StatefulWidget {
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

  const MorningLightModule({
    super.key,
    required this.logs,
    required this.timePeriod,
    required this.level,
    this.analyticsMode = 'Summary',
    this.groupBy = 'Cell',
    this.targetValue = 80.0,
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
  State<MorningLightModule> createState() => _MorningLightModuleState();
}

class _MorningLightModuleState extends State<MorningLightModule> {
  final _supabase = Supabase.instance.client;
  final Color pPurple = const Color(0xFF4A148C);
  String _selectedChartUnit = "General total";

  final List<String> _orderedBOLGroups = ["교역자", "자문회", "장년회", "부녀회", "청년회"];
  final List<String> _orderedLocations = [
    "24Dept", "MOU", "New Location", "Wakiso", "Lubaga", "Busega",
    "Kawempe", "Makerere", "Makindye", "Nakawa", "Mukono", "Entebbe", "UAE"
  ];
  final List<String> _orderedDepartments = ["장년회", "부녀회", "청년회", "신학부", "새신자"];

  List<String> _masterSubLocations = [];
  List<Map<String, dynamic>> _masterMembers = [];

  static const double rh = 24.0;
  static const double hh = 28.0;
  static const double sh = 18.0;
  static const double cw = 60.0;
  static const double lw = 115.0;
  static const double totalHeaderHeight = hh + hh + sh;

  @override
  void initState() {
    super.initState();
    _fetchMasterUnitsAndMembers();
  }

  @override
  void didUpdateWidget(covariant MorningLightModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedLocation != widget.selectedLocation ||
        oldWidget.selectedSubLocation != widget.selectedSubLocation ||
        oldWidget.selectedDepartment != widget.selectedDepartment ||
        oldWidget.selectedTeam != widget.selectedTeam ||
        oldWidget.level != widget.level) {
      _selectedChartUnit = "General total";
      _fetchMasterUnitsAndMembers();
    }
  }

  bool _isDidML(dynamic val) {
    if (val == null) return false;
    final s = val.toString().trim().toLowerCase();
    return s == "ml did" || s == "did" || s == "yes" || s == "done" || s == "1" || s == "true";
  }

  // --- STRICT CASCADING FILTER ---
  List<T> _applyCascade<T>(List<T> items) {
    final lvl = widget.level.toLowerCase();
    final loc = widget.selectedLocation.trim();
    final sub = widget.selectedSubLocation.trim();
    final dept = widget.selectedDepartment.trim();
    final team = widget.selectedTeam.trim();

    return items.where((item) {
      final map = item is Map<String, dynamic>
          ? item
          : (item is Map && item.containsKey('members') && item['members'] is Map
              ? item['members'] as Map
              : (item is Map ? item : {}));

      final iLoc = (map['location'] ?? '').toString().trim();
      final iSub = (map['sub_location'] ?? '').toString().trim();
      final iDept = (map['department'] ?? '').toString().trim();
      final iTeam = (map['team'] ?? '').toString().trim();

      if (lvl.contains('sub location') || lvl.contains('sub-location')) {
        if (loc.isNotEmpty && loc.toLowerCase() != 'church' && iLoc.toLowerCase() != loc.toLowerCase()) return false;
      } else if (lvl.contains('dept')) {
        if (loc.isNotEmpty && loc.toLowerCase() != 'church' && iLoc.toLowerCase() != loc.toLowerCase()) return false;
        if (sub.isNotEmpty && iSub.toLowerCase() != sub.toLowerCase()) return false;
      } else if (lvl.contains('team')) {
        if (loc.isNotEmpty && loc.toLowerCase() != 'church' && iLoc.toLowerCase() != loc.toLowerCase()) return false;
        if (sub.isNotEmpty && iSub.toLowerCase() != sub.toLowerCase()) return false;
        if (dept.isNotEmpty && iDept.toLowerCase() != dept.toLowerCase()) return false;
      } else if (lvl.contains('cell')) {
        if (loc.isNotEmpty && loc.toLowerCase() != 'church' && iLoc.toLowerCase() != loc.toLowerCase()) return false;
        if (sub.isNotEmpty && iSub.toLowerCase() != sub.toLowerCase()) return false;
        if (dept.isNotEmpty && iDept.toLowerCase() != dept.toLowerCase()) return false;
        if (team.isNotEmpty && iTeam.toLowerCase() != team.toLowerCase()) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _fetchMasterUnitsAndMembers() async {
    try {
      final lvl = widget.level.toLowerCase();

      // 1. Fetch sub-locations for selected location
      if ((lvl.contains('sub location') || lvl.contains('sub-location')) && widget.selectedLocation.isNotEmpty) {
        final locRes = await _supabase.from('locations').select('id').eq('location', widget.selectedLocation).maybeSingle();
        if (locRes != null && locRes['id'] != null) {
          final subData = await _supabase.from('sub_locations').select('name, is_mou').eq('location_id', locRes['id']).order('name');
          if (mounted) {
            bool isViewingMou = widget.selectedLocation.toUpperCase() == 'MOU';
            setState(() {
              _masterSubLocations = subData
                  .where((e) => isViewingMou ? (e['is_mou'] == true) : (e['is_mou'] != true))
                  .map((e) => e['name'].toString())
                  .toList();
            });
          }
        }
      }

      // 2. Query ALL saints from members table (Morning light is for all saints)
      dynamic mQuery = _supabase.from('members').select(
        'id, location, sub_location, department, team, cell_group, reg_status, geo_category, book_of_life, bol_dept, duty'
      );

      final loc = widget.selectedLocation.trim();
      final sub = widget.selectedSubLocation.trim();
      final dept = widget.selectedDepartment.trim();
      final team = widget.selectedTeam.trim();

      if (widget.isDeptLeader && widget.userDept.isNotEmpty) {
        mQuery = mQuery.eq('department', widget.userDept);
      } else if (widget.isTeamLeader && widget.userTeam.isNotEmpty) {
        mQuery = mQuery.eq('team', widget.userTeam);
      } else if (widget.isSubLocationLeader && widget.userSub.isNotEmpty) {
        mQuery = mQuery.eq('sub_location', widget.userSub);
      } else if (widget.isLocationLeader && widget.userLoc.isNotEmpty && widget.userLoc != 'Church') {
        mQuery = mQuery.eq('location', widget.userLoc);
      } else if (widget.isGroupLeader && widget.userDept.isNotEmpty) {
        mQuery = mQuery.eq('department', widget.userDept);
      }

      if (lvl.contains('sub location') || lvl.contains('sub-location')) {
        if (loc.isNotEmpty && loc.toLowerCase() != 'church') mQuery = mQuery.eq('location', loc);
      } else if (lvl.contains('dept')) {
        if (loc.isNotEmpty && loc.toLowerCase() != 'church') mQuery = mQuery.eq('location', loc);
        if (sub.isNotEmpty) mQuery = mQuery.eq('sub_location', sub);
      } else if (lvl.contains('team')) {
        if (loc.isNotEmpty && loc.toLowerCase() != 'church') mQuery = mQuery.eq('location', loc);
        if (sub.isNotEmpty) mQuery = mQuery.eq('sub_location', sub);
        if (dept.isNotEmpty) mQuery = mQuery.eq('department', dept);
      } else if (lvl.contains('cell')) {
        if (loc.isNotEmpty && loc.toLowerCase() != 'church') mQuery = mQuery.eq('location', loc);
        if (sub.isNotEmpty) mQuery = mQuery.eq('sub_location', sub);
        if (dept.isNotEmpty) mQuery = mQuery.eq('department', dept);
        if (team.isNotEmpty) mQuery = mQuery.eq('team', team);
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
      debugPrint("Morning Light Master Fetch Error: $e");
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
    for (var m in _applyCascade(_masterMembers)) {
      final t = m['team']?.toString().trim() ?? '';
      if (t.isNotEmpty) teams.add(t);
    }
    return _sortAscending(teams.toList());
  }

  List<String> _getScopedCellGroups() {
    final Set<String> cells = {};
    for (var m in _applyCascade(_masterMembers)) {
      final c = m['cell_group']?.toString().trim() ?? '';
      if (c.isNotEmpty) cells.add(c);
    }
    return _sortAscending(cells.toList());
  }

  Map<String, dynamic> _calc(List<dynamic> logsList, {List<dynamic>? officialMembers}) {
    int n = officialMembers != null ? officialMembers.length : logsList.length;

    int mon = logsList.where((l) => _isDidML(l['mon_ml'])).length;
    int tue = logsList.where((l) => _isDidML(l['tue_ml'])).length;
    int wed = logsList.where((l) => _isDidML(l['wed_ml'])).length;
    int thu = logsList.where((l) => _isDidML(l['thu_ml'])).length;
    int fri = logsList.where((l) => _isDidML(l['fri_ml'])).length;

    double avg = (mon + tue + wed + thu + fri) / 5.0;
    double avgPct = n > 0 ? (avg / n * 100) : 0.0;

    return {
      "n": n,
      "mon": mon,
      "monp": n > 0 ? (mon / n * 100) : 0.0,
      "tue": tue,
      "tuep": n > 0 ? (tue / n * 100) : 0.0,
      "wed": wed,
      "wedp": n > 0 ? (wed / n * 100) : 0.0,
      "thu": thu,
      "thup": n > 0 ? (thu / n * 100) : 0.0,
      "fri": fri,
      "frip": n > 0 ? (fri / n * 100) : 0.0,
      "avg": avg,
      "avgp": avgPct,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cascadedMembers = _applyCascade(_masterMembers);
    final cascadedLogs = _applyCascade(widget.logs);

    final Map<String, dynamic> totS = _calc(
      cascadedLogs,
      officialMembers: cascadedMembers.isNotEmpty ? cascadedMembers : null,
    );

    final Map<String, Map<String, dynamic>> blockData = _getCalculatedBlocksMap();

    Map<String, dynamic> activeChartData = totS;
    if (_selectedChartUnit != "General total" && blockData.containsKey(_selectedChartUnit)) {
      activeChartData = blockData[_selectedChartUnit]!;
    }

    return Column(children: [
      _buildToolbar(),
      if (widget.analyticsMode == 'Ranking') ...[
        _section("Top performing morning light units", _buildRankingList(blockData, true), context),
        const SizedBox(height: 8),
        _section("Units requiring morning light support", _buildRankingList(blockData, false), context),
      ] else ...[
        _section("Morning light participation summary", _buildExcelGrid(totS), context),
        const SizedBox(height: 8),
        _section(
          "Daily participation breakdown (%) - $_selectedChartUnit",
          _buildChartSection(totS, blockData, activeChartData),
          context,
        ),
      ],
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
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
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

  Map<String, Map<String, dynamic>> _getCalculatedBlocksMap() {
    final String lvl = widget.level.trim().toLowerCase();
    Map<String, List<dynamic>> groupedLogs = {};
    Map<String, List<dynamic>> groupedMembers = {};

    String extract(dynamic l, List<String> keys) {
      for (var k in keys) {
        var v = l['members']?[k] ?? l[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }

    final scopedMembers = _applyCascade(_masterMembers);
    final scopedLogs = _applyCascade(widget.logs);

    if (lvl.contains('group status')) {
      for (var g in _orderedBOLGroups) { groupedLogs[g] = []; groupedMembers[g] = []; }
      for (var m in scopedMembers) {
        String bol = m['book_of_life']?.toString() ?? m['bol_dept']?.toString() ?? '';
        if (groupedMembers.containsKey(bol)) groupedMembers[bol]!.add(m);
      }
      for (var l in scopedLogs) {
        String bol = extract(l, ['book_of_life', 'bol_dept']);
        if (groupedLogs.containsKey(bol)) groupedLogs[bol]!.add(l);
      }
    } else if (lvl.contains('sub location') || lvl.contains('sub-location')) {
      final Set<String> subLocs = Set.from(_masterSubLocations);
      for (var m in scopedMembers) {
        String sub = m['sub_location']?.toString().trim() ?? '';
        if (sub.isNotEmpty) subLocs.add(sub);
      }
      for (var sub in subLocs) { groupedLogs[sub] = []; groupedMembers[sub] = []; }
      for (var m in scopedMembers) {
        String sub = m['sub_location']?.toString().trim() ?? '';
        if (sub.isNotEmpty) groupedMembers.putIfAbsent(sub, () => []).add(m);
      }
      for (var l in scopedLogs) {
        String sub = extract(l, ['sub_location', 'sub_loc']);
        if (sub.isNotEmpty) groupedLogs.putIfAbsent(sub, () => []).add(l);
      }
    } else if (lvl.contains('location status')) {
      for (var loc in _orderedLocations) { groupedLogs[loc] = []; groupedMembers[loc] = []; }
      for (var m in scopedMembers) {
        String bucket = _resolveLocationBucket(m);
        if (groupedMembers.containsKey(bucket)) groupedMembers[bucket]!.add(m);
        else if (bucket.isNotEmpty) groupedMembers.putIfAbsent(bucket, () => []).add(m);
      }
      for (var l in scopedLogs) {
        String bucket = _resolveLocationBucket(l);
        if (groupedLogs.containsKey(bucket)) groupedLogs[bucket]!.add(l);
        else if (bucket.isNotEmpty && bucket.toLowerCase() != 'church') groupedLogs.putIfAbsent(bucket, () => []).add(l);
      }
    } else if (lvl.contains('dept')) {
      List<String> deptsToShow = widget.isDeptLeader && widget.userDept.isNotEmpty ? [widget.userDept] : _orderedDepartments;
      for (var d in deptsToShow) { groupedLogs[d] = []; groupedMembers[d] = []; }
      for (var m in scopedMembers) {
        String dept = m['department']?.toString().trim() ?? '';
        if (groupedMembers.containsKey(dept)) groupedMembers[dept]!.add(m);
      }
      for (var l in scopedLogs) {
        String dept = extract(l, ['department', 'dept', 'dept_name']);
        if (groupedLogs.containsKey(dept)) groupedLogs[dept]!.add(l);
      }
    } else if (lvl.contains('team')) {
      final List<String> distinctTeams = _getScopedTeams();
      for (var t in distinctTeams) { groupedLogs[t] = []; groupedMembers[t] = []; }
      for (var m in scopedMembers) {
        String team = m['team']?.toString().trim() ?? '';
        if (team.isNotEmpty) groupedMembers.putIfAbsent(team, () => []).add(m);
      }
      for (var l in scopedLogs) {
        String team = extract(l, ['team', 'team_name']);
        if (team.isNotEmpty) groupedLogs.putIfAbsent(team, () => []).add(l);
      }
    } else if (lvl.contains('cell')) {
      final List<String> distinctCells = _getScopedCellGroups();
      for (var cg in distinctCells) { groupedLogs[cg] = []; groupedMembers[cg] = []; }
      for (var m in scopedMembers) {
        String cell = m['cell_group']?.toString().trim() ?? '';
        if (cell.isNotEmpty) groupedMembers.putIfAbsent(cell, () => []).add(m);
      }
      for (var l in scopedLogs) {
        String cell = extract(l, ['unit_name', 'cell_group', 'cell', 'cell_name']);
        if (cell.isNotEmpty) groupedLogs.putIfAbsent(cell, () => []).add(l);
      }
    }

    Map<String, Map<String, dynamic>> calculatedBlocks = {};
    groupedLogs.forEach((unitKey, logs) {
      calculatedBlocks[unitKey] = _calc(logs, officialMembers: groupedMembers[unitKey]);
    });

    return calculatedBlocks;
  }

  Widget? _buildDynamicHierarchicalRows() {
    final String lvl = widget.level.trim().toLowerCase();

    if (lvl == 'church status' ||
        (widget.isLocationLeader && lvl == 'location status') ||
        (widget.isSubLocationLeader && lvl.contains('sub location')) ||
        (widget.isDeptLeader && lvl.contains('dept')) ||
        (widget.isTeamLeader && lvl.contains('team'))) {
      return null;
    }

    final blockData = _getCalculatedBlocksMap();
    if (blockData.isEmpty) return null;

    String categoryName = (widget.activeUnitLabel != null && widget.activeUnitLabel!.isNotEmpty)
        ? widget.activeUnitLabel!
        : "Unit";
    return _mergedBlock(categoryName, blockData);
  }

  Widget _buildMergedHeader() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cell("Classification", w: lw, h: totalHeaderHeight, b: true, bg: const Color(0xFFF8FAFC)),
      _cell("Unit", w: lw, h: totalHeaderHeight, b: true, bg: const Color(0xFFF8FAFC)),
      Column(children: [
        Row(children: [
          _cell("Morning Light Participation by Day", w: cw * 13, h: hh, b: true, bg: const Color(0xFFF8FAFC)),
        ]),
        Row(children: [
          _cell("Base", w: cw, h: hh, b: true),
          _cell("Monday", w: cw * 2, h: hh, b: true),
          _cell("Tuesday", w: cw * 2, h: hh, b: true),
          _cell("Wednesday", w: cw * 2, h: hh, b: true),
          _cell("Thursday", w: cw * 2, h: hh, b: true),
          _cell("Friday", w: cw * 2, h: hh, b: true),
          _cell("Overall Average", w: cw * 2, h: hh, b: true),
        ]),
        Row(children: [
          _cell("Saints", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Avg", w: cw, h: sh), _cell("Avg %", w: cw, h: sh),
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
      _cell("${d['mon']}", a: Alignment.center),
      _cell("${d['monp'].toStringAsFixed(1)}%", a: Alignment.center, color: pPurple, b: true),
      _cell("${d['tue']}", a: Alignment.center),
      _cell("${d['tuep'].toStringAsFixed(1)}%", a: Alignment.center, color: pPurple, b: true),
      _cell("${d['wed']}", a: Alignment.center),
      _cell("${d['wedp'].toStringAsFixed(1)}%", a: Alignment.center, color: pPurple, b: true),
      _cell("${d['thu']}", a: Alignment.center),
      _cell("${d['thup'].toStringAsFixed(1)}%", a: Alignment.center, color: pPurple, b: true),
      _cell("${d['fri']}", a: Alignment.center),
      _cell("${d['frip'].toStringAsFixed(1)}%", a: Alignment.center, color: pPurple, b: true),
      _cell((d['avg'] as double).toStringAsFixed(1), a: Alignment.center, b: true),
      _cell(
        "${(d['avgp'] as double).toStringAsFixed(1)}%",
        b: true,
        a: Alignment.center,
        color: (d['avgp'] >= widget.targetValue) ? Colors.green[800] : Colors.red[800],
      ),
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

  // --- RANKING LIST (TOP & SUPPORT) ---
  Widget _buildRankingList(Map<String, Map<String, dynamic>> blockData, bool isTop) {
    List<Map<String, dynamic>> stats = blockData.entries.map((e) {
      double pct = (e.value['avgp'] as num?)?.toDouble() ?? 0.0;
      return {'name': e.key, 'pct': pct};
    }).toList();

    stats.sort((a, b) => isTop ? b['pct'].compareTo(a['pct']) : a['pct'].compareTo(b['pct']));
    var displayList = stats.take(5).toList();

    if (displayList.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No ranking data found")));
    }

    return Column(
      children: displayList.map((item) => ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: isTop ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
          radius: 16,
          child: Icon(isTop ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded, size: 16, color: isTop ? Colors.green : Colors.red),
        ),
        title: Text(item['name'], style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 12.5)),
        trailing: Text(
          "${item['pct'].toStringAsFixed(1)}%",
          style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: isTop ? Colors.green[700] : Colors.red[700]),
        ),
      )).toList(),
    );
  }

  // --- DYNAMIC CHART LINKED DIRECTLY TO SUMMARY TABLE ---
  Widget _buildChartSection(Map<String, dynamic> totS, Map<String, Map<String, dynamic>> blockData, Map<String, dynamic> activeData) {
    List<String> unitsList = ["General total", ...blockData.keys];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        children: [
          if (unitsList.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: unitsList.map((u) {
                  final isSel = _selectedChartUnit == u;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 8),
                    child: InkWell(
                      onTap: () => setState(() => _selectedChartUnit = u),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSel ? pPurple : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isSel ? Colors.black : Colors.black26),
                        ),
                        child: Text(
                          u,
                          style: GoogleFonts.merriweather(
                            fontSize: 10.5,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                            color: isSel ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 8),
          _buildBarChart(activeData),
        ],
      ),
    );
  }

  Widget _buildBarChart(Map<String, dynamic> data) {
    List<double> vals = [
      (data['monp'] as num).toDouble(),
      (data['tuep'] as num).toDouble(),
      (data['wedp'] as num).toDouble(),
      (data['thup'] as num).toDouble(),
      (data['frip'] as num).toDouble(),
    ];
    List<String> days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"];

    return Column(children: [
      Container(
        height: 270,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        child: BarChart(BarChartData(
          maxY: 100,
          borderData: FlBorderData(show: true, border: const Border(left: BorderSide(color: Colors.black, width: 1.0), bottom: BorderSide(color: Colors.black, width: 1.0))),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(
              y: widget.targetValue,
              color: Colors.green[700]!,
              strokeWidth: 1.5,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: GoogleFonts.merriweather(color: Colors.green[800], fontSize: 9.5, fontWeight: FontWeight.bold),
                labelResolver: (_) => "Target ${widget.targetValue.toInt()}%",
              ),
            ),
          ]),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              axisNameWidget: Text("Participation Rate (%)", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold)),
              axisNameSize: 22,
              sideTitles: SideTitles(showTitles: true, reservedSize: 38, getTitlesWidget: (v, m) => Text("${v.toInt()}%", style: GoogleFonts.merriweather(fontSize: 9.5))),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, m) {
                int idx = v.toInt();
                if (idx < 0 || idx >= days.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(days[idx], style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold)));
              }),
            ),
          ),
          barGroups: List.generate(5, (i) => BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: vals[i],
              color: pPurple,
              width: 38,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              backDrawRodData: BackgroundBarChartRodData(show: true, toY: 100, color: const Color(0xFFF1F5F9)),
            ),
          ])),
        )),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 20,
        alignment: WrapAlignment.center,
        children: [
          _lgItem("Morning Light Done (%)", pPurple),
          _lgItem("Target (${widget.targetValue.toInt()}%)", Colors.green[700]!, isDashed: true),
        ],
      ),
    ]);
  }

  Widget _lgItem(String t, Color c, {bool isDashed = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: isDashed ? 3 : 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(isDashed ? 0 : 2))),
      const SizedBox(width: 6),
      Text(t, style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.black87)),
    ],
  );

  Future<void> _printReport() async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Text("Morning Light Report"))));
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