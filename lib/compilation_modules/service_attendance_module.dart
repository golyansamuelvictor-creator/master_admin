// ignore_for_file: unused_element, curly_braces_in_flow_control_structures
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceAttendanceModule extends StatefulWidget {
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

  const ServiceAttendanceModule({
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
  State<ServiceAttendanceModule> createState() => _ServiceAttendanceModuleState();
}

class _ServiceAttendanceModuleState extends State<ServiceAttendanceModule> {
  final _supabase = Supabase.instance.client;
  bool _isExpanded = false;
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

  static const double rh = 21.0;
  static const double hh = 32.0;
  static const double sh = 20.0;
  static const double lw = 115.0;
  static const double totalHeaderHeight = hh + hh + sh;

  double get cw => _isExpanded ? 48.0 : 65.0;

  bool get _is24ChurchDept {
    final r = widget.userRole.toLowerCase();
    final d = widget.userDept.toLowerCase();
    return (r.contains('_dept_') || r.startsWith('ia_') || d.contains('내무')) && !widget.isLocationLeader && !widget.isSubLocationLeader && !widget.isDeptLeader && !widget.isTeamLeader && !widget.isGroupLeader;
  }

  @override
  void initState() {
    super.initState();
    _fetchMasterUnitsAndMembers();
  }

  @override
  void didUpdateWidget(covariant ServiceAttendanceModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedLocation != widget.selectedLocation ||
        oldWidget.selectedSubLocation != widget.selectedSubLocation ||
        oldWidget.selectedDepartment != widget.selectedDepartment ||
        oldWidget.selectedTeam != widget.selectedTeam || 
        oldWidget.level != widget.level ||
        oldWidget.timePeriod != widget.timePeriod ||
        oldWidget.analyticsMode != widget.analyticsMode ||
        oldWidget.groupBy != widget.groupBy) {
      _fetchMasterUnitsAndMembers();
    }
  }

  Future<void> _fetchMasterUnitsAndMembers() async {
    try {
      final lvl = widget.level.toLowerCase();

      // 1. SUB-LOCATION STATUS: Fetch Sub-Locations from DB for selected Location
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

      // 2. TARGETED FETCH FOR MEMBERS (Scoped by user track to avoid 8000-member dump)
      dynamic mQuery = _supabase.from('members').select(
        'id, location, sub_location, department, team, cell_group, reg_status, geo_category, book_of_life, bol_dept, official_dept_id'
      );

      // A. Church 24-Department in Dept Mode: Only fetch Church staff (< 20 members)
      if (_is24ChurchDept && widget.groupBy == 'Church') {
        mQuery = mQuery.or('location.eq.Church,location.eq.Church Workers,location.eq.Church Main,location.is.null');
        if (widget.userDept.isNotEmpty && widget.userDept != 'Church') {
          mQuery = mQuery.eq('department', widget.userDept);
        }
      }
      // B. Cross-Region Group Leader constraint
      else if (widget.isGroupLeader && widget.userDept.isNotEmpty) {
        mQuery = mQuery.eq('department', widget.userDept).neq('location', 'Mou').neq('location', 'New Saints');
      }
      // C. Location Overseers / Workers
      else if (!widget.isChurchWide) {
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

      // Drill-down filters
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
      debugPrint("Service Module Master Fetch Error: $e");
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

  Map<String, dynamic> _calc(List<dynamic> logsList, {List<dynamic>? officialMembers}) {
    int n = officialMembers != null ? officialMembers.length : logsList.length;

    int ip = logsList.where((x) => x['attendance_realtime'] == "In-person").length;
    int onl = logsList.where((x) => x['attendance_realtime'] == "On-line").length;
    int call = logsList.where((x) => x['attendance_realtime'] == "Call").length;
    int meet = logsList.where((x) => x['attendance_realtime'] == "Meet").length;
    int sum = logsList.where((x) => x['attendance_realtime'] == "Summary").length;
    int att = ip + onl + call + meet + sum;

    int regCount(String r, String field, String val) => 
        logsList.where((x) => x['geo_category'] == r && x[field] == val).length;

    Map<String, dynamic> regData(String r) => {
      "act": {
        "ip": regCount(r, 'attendance_realtime', 'In-person'),
        "on": regCount(r, 'attendance_realtime', 'On-line'),
        "cl": regCount(r, 'attendance_realtime', 'Call'),
        "mt": regCount(r, 'attendance_realtime', 'Meet'),
        "sm": regCount(r, 'attendance_realtime', 'Summary')
      },
      "mu": {
        "ip": regCount(r, 'attendance_makeup', 'In-person'),
        "on": regCount(r, 'attendance_makeup', 'On-line'),
        "cl": regCount(r, 'attendance_makeup', 'Call'),
        "mt": regCount(r, 'attendance_makeup', 'Meet'),
        "sm": regCount(r, 'attendance_makeup', 'Summary')
      },
      "abs": logsList.where((x) => x['geo_category'] == r && x['attendance_realtime'] == "Absentee").length
    };

    int absentees = n > att ? (n - att) : 0;

    return {
      "n": n, 
      "att": att, 
      "pct": n > 0 ? (att / n * 100) : 0.0,
      "ip": ip, 
      "ipp": n > 0 ? (ip / n * 100) : 0.0,
      "ot": att - ip, 
      "otp": n > 0 ? ((att - ip) / n * 100) : 0.0,
      "ab": absentees, 
      "abp": n > 0 ? (absentees / n * 100) : 0.0,
      "hm": logsList.where((x) => x['is_hm'] == true).length, 
      "lt": logsList.where((x) => x['is_lta'] == true).length,
      "kla": regData("Kampala"), 
      "vil": regData("Village"), 
      "abr": regData("Abroad"),
    };
  }

  @override
  Widget build(BuildContext context) {
    final hqMembers = _masterMembers.where((m) => ["교회등록", "총회등록"].contains(m['reg_status']?.toString())).toList();
    final enMembers = _masterMembers.where((m) => m['reg_status']?.toString() == "입교").toList();

    final hqLogs = widget.logs.where((l) => ["교회등록", "총회등록"].contains(l['reg_status']?.toString())).toList();
    final enLogs = widget.logs.where((l) => l['reg_status']?.toString() == "입교").toList();

    final Map<String, dynamic> hqS = _calc(hqLogs, officialMembers: hqMembers.isNotEmpty ? hqMembers : null); 
    final Map<String, dynamic> enS = _calc(enLogs, officialMembers: enMembers.isNotEmpty ? enMembers : null);
    
    int totN = hqS['n'] + enS['n'];
    int totAtt = hqS['att'] + enS['att'];
    int totIp = hqS['ip'] + enS['ip'];
    int totOt = hqS['ot'] + enS['ot'];
    int totAb = totN > totAtt ? (totN - totAtt) : 0;

    final Map<String, dynamic> totS = {
      "n": totN, 
      "att": totAtt, 
      "pct": totN > 0 ? (totAtt / totN * 100) : 0.0,
      "ip": totIp, 
      "ipp": totN > 0 ? (totIp / totN * 100) : 0.0,
      "ot": totOt, 
      "otp": totN > 0 ? (totOt / totN * 100) : 0.0,
      "ab": totAb, 
      "abp": totN > 0 ? (totAb / totN * 100) : 0.0,
      "hm": hqS['hm'] + enS['hm'], 
      "lt": hqS['lt'] + enS['lt'], 
      "kla": hqS['kla'], 
      "vil": hqS['vil'], 
      "abr": hqS['abr']
    };

    return Column(children: [
      _buildToolbar(),
      _section("Attendance summary table", _buildExcelGrid(hqS, enS, totS), context),
      const SizedBox(height: 6), 
      _section("Participation visualization", _buildChart(totS), context),
    ]);
  }

  Widget _buildToolbar() => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Row(children: [
      IconButton(onPressed: _printReport, icon: const Icon(Icons.print, color: Colors.blueGrey, size: 18)),
      IconButton(onPressed: () {}, icon: const Icon(Icons.download, color: Colors.green, size: 18)),
    ]),
    TextButton.icon(
      onPressed: () => setState(() => _isExpanded = !_isExpanded), 
      icon: Icon(_isExpanded ? Icons.close_fullscreen : Icons.open_in_full, size: 14), 
      label: Text(_isExpanded ? "Collapse regional grid" : "Expand regional grid", 
        style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple)
      )
    ),
  ]);

  Widget _buildExcelGrid(Map<String, dynamic> hq, Map<String, dynamic> en, Map<String, dynamic> tot) {
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
            _mergedBlock("Status", {"Church / h.q": hq, "Enrollment": en}),
            if (childRows != null) childRows,
          ]),
        ),
      ),
    );
  }

  // --- DYNAMIC ROWS (ELIMINATES DUPLICATES AND MISPLACED 24-DEPT ROWS) ---
  Widget? _buildDynamicHierarchicalRows() {
    final String lvl = widget.level.trim().toLowerCase();

    // 1. Church status top row already represents Church
    if (lvl == 'church status') return null;

    // 2. 24 Departments at Church: No demographic sub-departments (장년회, 부녀회...)
    if (_is24ChurchDept || widget.groupBy == 'Church') return null;

    // 3. Location leader viewing location status: Summary is already at top
    if (widget.isLocationLeader && lvl == 'location status') return null;

    // 4. Sub-location leader viewing sub-location status: Prevent duplicate row
    if (widget.isSubLocationLeader && (lvl.contains('sub location') || lvl.contains('sub-location'))) return null;

    // 5. Dept leader viewing dept status: Prevent duplicate row
    if (widget.isDeptLeader && lvl == 'dept status') return null;

    // 6. Team leader viewing team status: Prevent duplicate row
    if (widget.isTeamLeader && lvl == 'team status') return null;

    // 7. Group leader viewing group status: Summary is already at top
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
          if (_isExpanded) ...["Kampala", "Village", "Abroad"].map((r) => _cell(r, w: cw * 11, h: hh, b: true, bg: const Color(0xFFF8FAFC))),
        ]),
        Row(children: [
          _cell("Overall metrics", w: cw * 3, h: hh, b: true),
          _cell("In-person", w: cw * 2, h: hh, b: true),
          _cell("Other methods", w: cw * 2, h: hh, b: true),
          _cell("Absentees", w: cw * 2, h: hh, b: true),
          _cell("Special", w: cw * 2, h: hh, b: true),
          if (_isExpanded) ...List.generate(3, (i) => Row(children: [
            _cell("Actual", w: cw * 5, h: hh, b: true), 
            _cell("Make up", w: cw * 5, h: hh, b: true), 
            _cell("Abs", w: cw, h: hh, b: true)
          ]))
        ]),
        Row(children: [
          _cell("Num", w: cw, h: sh), _cell("Att", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("H-m", w: cw, h: sh), _cell("Lta", w: cw, h: sh),
          if (_isExpanded) ...List.generate(6, (i) => Row(children: [
            _cell("In-p", w: cw, h: sh), _cell("Onl", w: cw, h: sh), _cell("Call", w: cw, h: sh), _cell("Meet", w: cw, h: sh), _cell("Sum", w: cw, h: sh),
          ])),
          if (_isExpanded) ...List.generate(3, (i) => _cell("Total", w: cw, h: sh)),
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
    Widget reg(Map<String, dynamic> r) => Row(children: [
      _cell("${r['act']?['ip'] ?? 0}"), _cell("${r['act']?['on'] ?? 0}"), _cell("${r['act']?['cl'] ?? 0}"), _cell("${r['act']?['mt'] ?? 0}"), _cell("${r['act']?['sm'] ?? 0}"),
      _cell("${r['mu']?['ip'] ?? 0}"), _cell("${r['mu']?['on'] ?? 0}"), _cell("${r['mu']?['cl'] ?? 0}"), _cell("${r['mu']?['mt'] ?? 0}"), _cell("${r['mu']?['sm'] ?? 0}"),
      _cell("${r['abs'] ?? 0}"),
    ]);
    return Row(children: [
      _cell(label, w: lw, h: rh, b: b, a: Alignment.center),
      _cell("${d['n']}"), _cell("${d['att']}"), _cell("${d['pct'].toStringAsFixed(1)}%", b: true),
      _cell("${d['ip']}"), _cell("${d['ipp'].toStringAsFixed(1)}%"),
      _cell("${d['ot']}"), _cell("${d['otp'].toStringAsFixed(1)}%"),
      _cell("${d['ab']}"), _cell("${d['abp'].toStringAsFixed(1)}%"),
      _cell("${d['hm']}"), _cell("${d['lt']}"),
      if (_isExpanded) ...[reg(d['kla'] ?? {}), reg(d['vil'] ?? {}), reg(d['abr'] ?? {})],
    ]);
  }

  Widget _cell(
    String t, {
    double? w, 
    double h = rh, 
    bool b = false, 
    Color? color, 
    Color? bg, 
    Alignment a = Alignment.center
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

  // --- CONNECTED CHART (ALIGNED WITH SIDEBAR MODE AND TIME PERIOD) ---
  Widget _buildChart(Map<String, dynamic> totSummary) {
    // Respects sidebar mode: if Analytics mode is Trend, or if multi-day period, show Trend
    bool isTrend = widget.analyticsMode == "Trend" || (widget.timePeriod != "Current status" && widget.analyticsMode != "Summary");
    final lvl = widget.level.toLowerCase();

    // ─────────────────────────────────────────────────────────────────────────
    // CASE A: SNAPSHOT / SUMMARY MODE -> BAR CHART
    // ─────────────────────────────────────────────────────────────────────────
    if (!isTrend) {
      String xName = _getDynamicXAxisLabel();
      List<String> keys = _getUnitKeysForLevel(lvl);

      // SINGLE UNIT / DEPARTMENT VIEW: Chart displays metric breakdown
      if (keys.isEmpty || keys.length == 1 || _is24ChurchDept || widget.groupBy == 'Church') {
        final double nVal = (totSummary['n'] as num?)?.toDouble() ?? 0.0;
        final double attVal = (totSummary['att'] as num?)?.toDouble() ?? 0.0;
        final double ipVal = (totSummary['ip'] as num?)?.toDouble() ?? 0.0;
        final double otVal = (totSummary['ot'] as num?)?.toDouble() ?? 0.0;
        final double abVal = (totSummary['ab'] as num?)?.toDouble() ?? 0.0;

        final double dynamicMaxY = (max(nVal, max(attVal, abVal)) * 1.25).ceilToDouble();

        final List<_BarMetric> metrics = [
          _BarMetric("Saints (N)", nVal, Colors.grey.shade500),
          _BarMetric("Attended", attVal, pPurple),
          _BarMetric("In-person", ipVal, Colors.blue.shade700),
          _BarMetric("Online", otVal, Colors.teal.shade600),
          _BarMetric("Absentees", abVal, Colors.red.shade400),
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
                  BarChartRodData(toY: metrics[i].val, color: metrics[i].color, width: 36, borderRadius: BorderRadius.circular(4))
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

      // MULTI-UNIT VIEW: Compares units across level
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
        final double highest = max(nVal, max(attVal, ipVal));
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
    // CASE B: TREND OVER TIME (WEEKLY / MONTHLY) -> MULTI-LINE OVER DATES
    // ─────────────────────────────────────────────────────────────────────────
    final Set<String> rawDates = {};
    for (var l in widget.logs) {
      final d = l['report_date']?.toString();
      if (d != null && d.isNotEmpty) rawDates.add(d);
    }
    final List<String> sortedDates = rawDates.toList()..sort();

    if (sortedDates.isEmpty) {
      return const SizedBox(
        height: 200, 
        child: Center(child: Text("No historical records found for this period"))
      );
    }

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

    // If viewing single department: show single line trend
    if (unitKeys.isEmpty || _is24ChurchDept || widget.groupBy == 'Church') {
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
              decoration: BoxDecoration(
                color: const Color(0xFFF3E5F5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.purple.shade200)
              ),
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
      if (unitKeys.isNotEmpty && !_is24ChurchDept && widget.groupBy != 'Church')
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Center(
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: List.generate(
                unitKeys.length, 
                (i) => _lgItem(unitKeys[i], palette[i % palette.length])
              ),
            ),
          ),
        ),
    ]);
  }

  List<String> _getUnitKeysForLevel(String lvl) {
    if (_is24ChurchDept || widget.groupBy == 'Church' || lvl.contains('church')) {
      return [];
    }
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
          }
        )
      ),
      leftTitles: AxisTitles(
        axisNameWidget: Text("Headcount (Persons)", style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold)), 
        axisNameSize: 22, 
        sideTitles: SideTitles(showTitles: true, reservedSize: 42, getTitlesWidget: (v, m) => Text("${v.toInt()}", style: GoogleFonts.merriweather(fontSize: 10)))
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
    pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Text("Attendance Report"))));
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Widget _section(String title, Widget content, BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      color: Colors.white, 
      borderRadius: BorderRadius.circular(12), 
      border: Border.all(color: Colors.black, width: 1.0),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))]
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
              body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(8), child: content))
            )
          ))
        ),
      ),
      const Divider(height: 1, color: Colors.black26),
      content,
    ]),
  );
}

class _BarMetric {
  final String label;
  final double val;
  final Color color;
  _BarMetric(this.label, this.val, this.color);
}