// ignore_for_file: camel_case_types, curly_braces_in_flow_control_structures, unused_element, dead_null_aware_expression, unused_import
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

class VisitationsModule extends StatefulWidget {
  final List<dynamic> logs;
  final String level;
  final String category;
  final String timePeriod;
  final String analyticsMode;
  final String groupBy;
  final double targetValue;

  final String selectedLocation;
  final String selectedSubLocation;
  final String selectedDepartment;
  final String selectedTeam;
  final String activeUnitLabel;

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

  const VisitationsModule({
    super.key,
    required this.logs,
    required this.level,
    this.category = 'All',
    this.timePeriod = 'Weekly status',
    this.analyticsMode = 'Summary',
    this.groupBy = 'Church',
    this.targetValue = 80.0,
    this.selectedLocation = '',
    this.selectedSubLocation = '',
    this.selectedDepartment = '',
    this.selectedTeam = '',
    this.activeUnitLabel = 'Unit name',
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
  State<VisitationsModule> createState() => _VisitationsModuleState();
}

class _VisitationsModuleState extends State<VisitationsModule> {
  final _supabase = Supabase.instance.client;
  final Color pPurple = const Color(0xFF4A148C);
  late String _activeCategory;
  String _selectedChartUnit = "General total";

  final List<String> _categories = ["All", "Lta", "H.m", "Offline", "Offering", "Evangelism", "Education"];
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
    _activeCategory = (widget.category.isNotEmpty && widget.category.toLowerCase() != 'lta') ? widget.category : "All";
    _fetchMasterUnitsAndMembers();
  }

  @override
  void didUpdateWidget(covariant VisitationsModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.category != oldWidget.category && widget.category.isNotEmpty) {
      _activeCategory = widget.category;
    }
    if (oldWidget.selectedLocation != widget.selectedLocation ||
        oldWidget.selectedSubLocation != widget.selectedSubLocation ||
        oldWidget.selectedDepartment != widget.selectedDepartment ||
        oldWidget.selectedTeam != widget.selectedTeam ||
        oldWidget.level != widget.level) {
      _selectedChartUnit = "General total";
      _fetchMasterUnitsAndMembers();
    }
  }

  bool _matchCategory(String? dbValue, String target) {
    if (dbValue == null || dbValue.trim().isEmpty) return false;
    final a = dbValue.toLowerCase().replaceAll('.', '').replaceAll(' ', '').trim();
    final b = target.toLowerCase().replaceAll('.', '').replaceAll(' ', '').trim();
    return a == b;
  }

  bool _isPositive(dynamic val) {
    if (val == null) return false;
    final s = val.toString().trim().toLowerCase();
    return s == 'positive' || s == 'pos' || s.startsWith('pos');
  }

  bool _isNegative(dynamic val) {
    if (val == null) return false;
    final s = val.toString().trim().toLowerCase();
    return s == 'negative' || s == 'neg' || s.startsWith('neg');
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

      // 1. Fetch sub-locations strictly for the selected location
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

      // 2. Query members with strict cascading scope
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

      // Hierarchy overrides
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
      debugPrint("Visitations Master Fetch Error: $e");
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

  List<dynamic> _filterLogsByCategory(List<dynamic> list) {
    if (_activeCategory.toLowerCase() == "all") return list;
    return list.where((l) => _matchCategory(l['visitation_reason']?.toString(), _activeCategory)).toList();
  }

  Map<String, dynamic> _calc(List<dynamic> logsList, {List<dynamic>? officialMembers}) {
    int n = officialMembers != null ? officialMembers.length : logsList.length;

    final catLogs = _filterLogsByCategory(logsList);
    int pos = catLogs.where((l) => _isPositive(l['status_detail'])).length;
    int neg = catLogs.where((l) => _isNegative(l['status_detail'])).length;

    int visited = (pos + neg > 0) ? (pos + neg) : catLogs.where((l) {
      final r = (l['visitation_reason'] ?? '').toString().trim();
      final s = (l['status_detail'] ?? '').toString().trim();
      return r.isNotEmpty || s.isNotEmpty;
    }).length;

    int couns = logsList.where((l) {
      final r = (l['visitation_reason'] ?? '').toString();
      return _matchCategory(r, 'Education') || _matchCategory(r, 'Lta') || _matchCategory(r, 'LTA');
    }).length;

    return {
      "n": n,
      "visited": visited,
      "visp": n > 0 ? (visited / n * 100) : 0.0,
      "couns": couns,
      "pos": pos,
      "posp": visited > 0 ? (pos / visited * 100) : 0.0,
      "neg": neg,
      "negp": visited > 0 ? (neg / visited * 100) : 0.0,
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

    // Determine current chart data based on selected unit
    Map<String, dynamic> activeChartData = totS;
    if (_selectedChartUnit != "General total" && blockData.containsKey(_selectedChartUnit)) {
      activeChartData = blockData[_selectedChartUnit]!;
    }

    return Column(children: [
      _buildToolbar(),
      _buildCategoryPillBar(),
      const SizedBox(height: 8),
      _section("Member care & visitations summary ($_activeCategory)", _buildExcelGrid(totS), context),
      const SizedBox(height: 8),
      _section(
        "Outcomes 3D pizza chart - $_selectedChartUnit",
        _buildPizzaSection(totS, blockData, activeChartData),
        context,
      ),
    ]);
  }

  Widget _buildToolbar() => Row(
    mainAxisAlignment: MainAxisAlignment.start,
    children: [
      IconButton(onPressed: _printReport, icon: const Icon(Icons.print, color: Colors.blueGrey, size: 18)),
      IconButton(onPressed: () {}, icon: const Icon(Icons.download, color: Colors.green, size: 18)),
    ],
  );

  Widget _buildCategoryPillBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black, width: 1.0)),
    child: Row(children: [
      Text("Category: ", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.w900, color: pPurple)),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _categories.map((cat) {
              final isSel = _activeCategory.toLowerCase() == cat.toLowerCase();
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () => setState(() => _activeCategory = cat),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: isSel ? pPurple : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6), border: Border.all(color: isSel ? Colors.black : Colors.black26)),
                    child: Text(cat, style: GoogleFonts.merriweather(fontSize: 10, fontWeight: isSel ? FontWeight.bold : FontWeight.w600, color: isSel ? Colors.white : Colors.black87)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    ]),
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

    String categoryName = widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : "Unit";
    return _mergedBlock(categoryName, blockData);
  }

  Widget _buildMergedHeader() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cell("Classification", w: lw, h: totalHeaderHeight, b: true, bg: const Color(0xFFF8FAFC)),
      _cell("Unit", w: lw, h: totalHeaderHeight, b: true, bg: const Color(0xFFF8FAFC)),
      Column(children: [
        Row(children: [
          _cell("Care & Visitation Metrics", w: cw * 8, h: hh, b: true, bg: const Color(0xFFF8FAFC)),
        ]),
        Row(children: [
          _cell("Base", w: cw, h: hh, b: true),
          _cell("Visited", w: cw * 2, h: hh, b: true),
          _cell("Counselled", w: cw, h: hh, b: true),
          _cell("Positive", w: cw * 2, h: hh, b: true),
          _cell("Negative", w: cw * 2, h: hh, b: true),
        ]),
        Row(children: [
          _cell("Saints", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh),
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
      _cell("${d['visited']}", color: pPurple, b: true, a: Alignment.center),
      _cell("${d['visp'].toStringAsFixed(1)}%", color: pPurple, b: true, a: Alignment.center),
      _cell("${d['couns']}", a: Alignment.center),
      _cell("${d['pos']}", color: Colors.green[800], b: true, a: Alignment.center),
      _cell("${d['posp'].toStringAsFixed(1)}%", color: Colors.green[800], a: Alignment.center),
      _cell("${d['neg']}", color: Colors.red[800], b: true, a: Alignment.center),
      _cell("${d['negp'].toStringAsFixed(1)}%", color: Colors.red[800], a: Alignment.center),
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

  // --- DYNAMIC UNIT SELECTOR + 3D SOLID PIZZA PIE CHART (NO HOLE) ---
  Widget _buildPizzaSection(Map<String, dynamic> totS, Map<String, Map<String, dynamic>> blockData, Map<String, dynamic> chartData) {
    List<String> unitsList = ["General total", ...blockData.keys];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        children: [
          // Dynamic Row Selector linked directly to the Summary Table
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
          const SizedBox(height: 10),

          // 3D Solid Pizza Chart Display
          _build3DPizzaVisual(chartData),
        ],
      ),
    );
  }

  Widget _build3DPizzaVisual(Map<String, dynamic> d) {
    int saints = d['n'] as int;
    int visited = d['visited'] as int;
    int pos = d['pos'] as int;
    int neg = d['neg'] as int;
    int pending = math.max(0, saints - visited);

    double visPct = d['visp'] as double;
    double posPct = d['posp'] as double;
    double negPct = d['negp'] as double;
    double pendingPct = saints > 0 ? (pending / saints * 100) : 0.0;

    if (visited == 0 && pos == 0 && neg == 0) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Text(
          "No visitations logged yet for '$_selectedChartUnit' under '$_activeCategory'",
          style: GoogleFonts.merriweather(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
        ),
      );
    }

    final List<_PizzaSlice> slices = [
      if (pos > 0)
        _PizzaSlice(
          label: "Positive",
          count: pos,
          percentage: posPct,
          topColor: const Color(0xFF10B981), // Emerald Green
          sideColor: const Color(0xFF047857), // 3D Edge Shading
        ),
      if (neg > 0)
        _PizzaSlice(
          label: "Negative",
          count: neg,
          percentage: negPct,
          topColor: const Color(0xFFEF4444), // Crimson Red
          sideColor: const Color(0xFFB91C1C), // 3D Edge Shading
        ),
      if (pending > 0)
        _PizzaSlice(
          label: "Pending",
          count: pending,
          percentage: pendingPct,
          topColor: const Color(0xFF94A3B8), // Cool Slate
          sideColor: const Color(0xFF475569), // 3D Edge Shading
        ),
    ];

    return Column(
      children: [
        // Summary KPI Strip
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _metricPill("Total Saints", "$saints", Colors.blueGrey.shade800),
            const SizedBox(width: 8),
            _metricPill("Visited", "$visited (${visPct.toStringAsFixed(1)}%)", pPurple),
            const SizedBox(width: 8),
            _metricPill("Positive", "$pos (${posPct.toStringAsFixed(1)}%)", Colors.green.shade800),
            const SizedBox(width: 8),
            _metricPill("Negative", "$neg (${negPct.toStringAsFixed(1)}%)", Colors.red.shade800),
          ],
        ),
        const SizedBox(height: 20),

        // Custom 3D Solid Pizza Painter (Perspective Disc, No Hole)
        SizedBox(
          height: 280,
          width: double.infinity,
          child: CustomPaint(
            painter: _3DPizzaPainter(slices: slices),
          ),
        ),
        const SizedBox(height: 14),

        // Legend
        Wrap(
          spacing: 16,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            _legendDot("Positive ($pos)", const Color(0xFF10B981)),
            _legendDot("Negative ($neg)", const Color(0xFFEF4444)),
            _legendDot("Pending ($pending)", const Color(0xFF94A3B8)),
          ],
        ),
      ],
    );
  }

  Widget _metricPill(String t, String v, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6), border: Border.all(color: c.withValues(alpha: 0.3))),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("$t: ", style: GoogleFonts.merriweather(fontSize: 10, color: Colors.black87)),
        Text(v, style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.w900, color: c)),
      ],
    ),
  );

  Widget _legendDot(String l, Color c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(l, style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800)),
    ],
  );

  Future<void> _printReport() async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Text("Care and Visitations Report - $_activeCategory"))));
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

// Slice Data Model
class _PizzaSlice {
  final String label;
  final int count;
  final double percentage;
  final Color topColor;
  final Color sideColor;

  _PizzaSlice({
    required this.label,
    required this.count,
    required this.percentage,
    required this.topColor,
    required this.sideColor,
  });
}

// Custom 3D Solid Pizza Painter (Perspective disc, extruded depth, solid slices)
class _3DPizzaPainter extends CustomPainter {
  final List<_PizzaSlice> slices;

  _3DPizzaPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty) return;

    final Offset center = Offset(size.width / 2, (size.height / 2) - 10);
    final double radiusX = math.min(130.0, (size.width / 2) - 30);
    final double radiusY = radiusX * 0.65; // Isometric 3D tilt perspective (ellipse)
    const double depth = 26.0; // Extruded physical 3D thickness

    double totalVal = slices.fold(0.0, (sum, s) => sum + s.count);
    if (totalVal == 0) totalVal = 1.0;

    // Draw Floor Drop Shadow for the entire 3D Pizza
    final shadowRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + depth + 10),
      width: (radiusX * 2) + 20,
      height: (radiusY * 2) + 12,
    );
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(shadowRect, shadowPaint);

    // 1. Draw 3D Extruded Cylinder Edges (for all slices facing the front: 0 to π)
    double startAngle = -math.pi / 2;
    for (var slice in slices) {
      final sweepAngle = (slice.count / totalVal) * (2 * math.pi);
      _draw3DExtrudedEdge(canvas, center, radiusX, radiusY, depth, startAngle, sweepAngle, slice.sideColor);
      startAngle += sweepAngle;
    }

    // 2. Draw Top Pizza Slices (Flat solid pizza disc with perspective, NO center hole)
    startAngle = -math.pi / 2;
    for (var slice in slices) {
      final sweepAngle = (slice.count / totalVal) * (2 * math.pi);

      final slicePath = Path();
      slicePath.moveTo(center.dx, center.dy);

      const int steps = 40;
      for (int i = 0; i <= steps; i++) {
        final double theta = startAngle + (sweepAngle * (i / steps));
        final double x = center.dx + radiusX * math.cos(theta);
        final double y = center.dy + radiusY * math.sin(theta);
        slicePath.lineTo(x, y);
      }
      slicePath.close();

      // Top Slice Paint with subtle light gradient
      final slicePaint = Paint()
        ..shader = RadialGradient(
          center: Alignment.topLeft,
          radius: 0.9,
          colors: [
            Color.lerp(slice.topColor, Colors.white, 0.2)!,
            slice.topColor,
          ],
        ).createShader(Rect.fromCenter(center: center, width: radiusX * 2, height: radiusY * 2));
      canvas.drawPath(slicePath, slicePaint);

      // White Pizza Cut Border
      final cutBorderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(slicePath, cutBorderPaint);

      // Label floating directly over slice
      final midAngle = startAngle + (sweepAngle / 2);
      final labelX = center.dx + (radiusX * 0.65) * math.cos(midAngle);
      final labelY = center.dy + (radiusY * 0.65) * math.sin(midAngle);

      if (sweepAngle > 0.35) {
        _drawSliceLabel(canvas, Offset(labelX, labelY), "${slice.percentage.toStringAsFixed(0)}%");
      }

      startAngle += sweepAngle;
    }
  }

  void _draw3DExtrudedEdge(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    double depth,
    double startAngle,
    double sweepAngle,
    Color sideColor,
  ) {
    const int steps = 30;
    for (int i = 0; i < steps; i++) {
      final double a1 = startAngle + sweepAngle * (i / steps);
      final double a2 = startAngle + sweepAngle * ((i + 1) / steps);

      // Only draw edge for the front-facing half (sin > 0)
      if (math.sin(a1) >= -0.05 || math.sin(a2) >= -0.05) {
        final double x1 = center.dx + rx * math.cos(a1);
        final double y1 = center.dy + ry * math.sin(a1);
        final double x2 = center.dx + rx * math.cos(a2);
        final double y2 = center.dy + ry * math.sin(a2);

        final edgePath = Path()
          ..moveTo(x1, y1)
          ..lineTo(x2, y2)
          ..lineTo(x2, y2 + depth)
          ..lineTo(x1, y1 + depth)
          ..close();

        final edgePaint = Paint()..color = sideColor;
        canvas.drawPath(edgePath, edgePaint);
      }
    }
  }

  void _drawSliceLabel(Canvas canvas, Offset pos, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: GoogleFonts.merriweather(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          shadows: [
            const Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1.5)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    tp.paint(canvas, Offset(pos.dx - (tp.width / 2), pos.dy - (tp.height / 2)));
  }

  @override
  bool shouldRepaint(covariant _3DPizzaPainter oldDelegate) => true;
}