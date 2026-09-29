// ignore_for_file: unused_element, curly_braces_in_flow_control_structures
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
  });

  @override
  State<ServiceAttendanceModule> createState() => _ServiceAttendanceModuleState();
}

class _ServiceAttendanceModuleState extends State<ServiceAttendanceModule> {
  final _supabase = Supabase.instance.client;
  bool _isExpanded = false;
  final Color pPurple = const Color(0xFF4A148C);

  List<String> _masterLocations = [];
  List<String> _masterCellGroups = [];

  static const double rh = 21.0;
  static const double hh = 32.0;
  static const double sh = 20.0;
  static const double lw = 115.0;
  static const double totalHeaderHeight = hh + hh + sh;

  double get cw => _isExpanded ? 48.0 : 65.0;

  @override
  void initState() {
    super.initState();
    _fetchMasterUnits();
  }

  @override
  void didUpdateWidget(covariant ServiceAttendanceModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTeam != widget.selectedTeam || oldWidget.level != widget.level) {
      _fetchMasterUnits();
    }
  }

  Future<void> _fetchMasterUnits() async {
    try {
      // 1. Fetch ALL locations from Supabase (Solves Point 1)
      final locData = await _supabase.from('locations').select('location').order('location');
      if (locData.isNotEmpty && mounted) {
        setState(() {
          _masterLocations = locData
              .map((e) => e['location'].toString())
              .where((l) => l.toLowerCase() != 'church')
              .toList();
        });
      }

      // 2. Fetch cell groups
      final cellData = await _supabase.from('cell_groups').select('name');
      if (cellData.isNotEmpty && mounted) {
        setState(() {
          _masterCellGroups = _sortCellGroups(List<String>.from(cellData.map((e) => e['name'].toString())));
        });
      }
    } catch (e) {
      debugPrint("Service Module Master Units Fetch Error: $e");
    }
  }

  // --- NATURAL SORTING FROM SMALLEST TO HIGHEST (Point 5) ---
  List<String> _sortCellGroups(List<String> items) {
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

  Map<String, dynamic> _calc(List<dynamic> l) {
    int n = l.length;
    int ip = l.where((x) => x['attendance_realtime'] == "In-person").length;
    int onl = l.where((x) => x['attendance_realtime'] == "On-line").length;
    int call = l.where((x) => x['attendance_realtime'] == "Call").length;
    int meet = l.where((x) => x['attendance_realtime'] == "Meet").length;
    int sum = l.where((x) => x['attendance_realtime'] == "Summary").length;
    int att = ip + onl + call + meet + sum;

    int regCount(String r, String field, String val) => 
        l.where((x) => x['geo_category'] == r && x[field] == val).length;

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
      "abs": l.where((x) => x['geo_category'] == r && x['attendance_realtime'] == "Absentee").length
    };

    return {
      "n": n, 
      "att": att, 
      "pct": n > 0 ? (att / n * 100) : 0.0,
      "ip": ip, 
      "ipp": n > 0 ? (ip / n * 100) : 0.0,
      "ot": att - ip, 
      "otp": n > 0 ? ((att - ip) / n * 100) : 0.0,
      "ab": n - att, 
      "abp": n > 0 ? ((n - att) / n * 100) : 0.0,
      "hm": l.where((x) => x['is_hm'] == true).length, 
      "lt": l.where((x) => x['is_lta'] == true).length,
      "kla": regData("Kampala"), 
      "vil": regData("Village"), 
      "abr": regData("Abroad"),
    };
  }

  @override
  Widget build(BuildContext context) {
    final hqList = widget.logs.where((l) => ["교회등록", "총회등록"].contains(l['reg_status']?.toString())).toList();
    final enList = widget.logs.where((l) => l['reg_status']?.toString() == "입교").toList();
    final Map<String, dynamic> hqS = _calc(hqList); 
    final Map<String, dynamic> enS = _calc(enList);
    
    final Map<String, dynamic> totS = {
      "n": hqS['n'] + enS['n'], 
      "att": hqS['att'] + enS['att'],
      "pct": (hqS['n'] + enS['n']) > 0 ? ((hqS['att'] + enS['att']) / (hqS['n'] + enS['n']) * 100) : 0.0,
      "ip": hqS['ip'] + enS['ip'], 
      "ipp": (hqS['n'] + enS['n']) > 0 ? ((hqS['ip'] + enS['ip']) / (hqS['n'] + enS['n']) * 100) : 0.0,
      "ot": hqS['ot'] + enS['ot'], 
      "otp": (hqS['n'] + enS['n']) > 0 ? ((hqS['ot'] + enS['ot']) / (hqS['n'] + enS['n']) * 100) : 0.0,
      "ab": hqS['ab'] + enS['ab'], 
      "abp": (hqS['n'] + enS['n']) > 0 ? ((hqS['ab'] + enS['ab']) / (hqS['n'] + enS['n']) * 100) : 0.0,
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
      _section("Participation visualization", _buildChart(), context),
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

  Widget? _buildDynamicHierarchicalRows() {
    final String lvl = widget.level.trim().toLowerCase();

    // No redundant mother row when viewing own tier
    if (lvl == 'church status' || (widget.isLocationLeader && lvl == 'location status')) {
      return null;
    }

    Map<String, List<dynamic>> grouped = {};
    String categoryName = widget.activeUnitLabel ?? "Unit";

    String extract(dynamic l, List<String> keys) {
      for (var k in keys) {
        var v = l['members']?[k] ?? l[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }

    // 1. Group Status -> Show Groups
    if (lvl.contains('group status')) {
      categoryName = "Group";
      for (var l in widget.logs) {
        String dept = extract(l, ['department', 'dept', 'dept_name']);
        if (dept.isNotEmpty) grouped.putIfAbsent(dept, () => []).add(l);
      }
      for (var d in ["장년회", "부녀회", "청년회", "신학부", "새신자부"]) {
        grouped.putIfAbsent(d, () => []);
      }
    } 
    // 2. Location Status -> ALL LOCATIONS FROM DATABASE (Fix for Point 1)
    else if (lvl.contains('location status')) {
      categoryName = "Location";
      for (var l in widget.logs) {
        String loc = extract(l, ['location', 'loc', 'church_name']);
        if (loc.isNotEmpty && loc.toLowerCase() != 'church') {
          grouped.putIfAbsent(loc, () => []).add(l);
        }
      }
      // Populate all master locations from Supabase
      for (var loc in _masterLocations) {
        grouped.putIfAbsent(loc, () => []);
      }
      if (grouped.isEmpty) {
        for (var lc in ["Wakiso", "Lubaga", "Makindye", "Kawempe", "Nakawa", "Entebbe", "Mukono", "Jinja"]) {
          grouped.putIfAbsent(lc, () => []);
        }
      }
    } 
    // 3. Sub Location Status
    else if (lvl.contains('sub location') || lvl.contains('sub-location')) {
      categoryName = widget.selectedLocation.isNotEmpty ? widget.selectedLocation : "Sub-locations";
      for (var l in widget.logs) {
        String loc = extract(l, ['location', 'loc']);
        bool locOk = widget.selectedLocation.isEmpty || loc.toLowerCase() == widget.selectedLocation.toLowerCase();
        if (locOk) {
          String sub = extract(l, ['sub_location', 'sub_loc']);
          if (sub.isNotEmpty) grouped.putIfAbsent(sub, () => []).add(l);
        }
      }
      if (grouped.isEmpty) {
        grouped["Sub-loc 1"] = [];
        grouped["Sub-loc 2"] = [];
      }
    } 
    // 4. Dept Status
    else if (lvl.contains('dept')) {
      categoryName = widget.selectedSubLocation.isNotEmpty ? widget.selectedSubLocation : "Dept";
      for (var l in widget.logs) {
        String loc = extract(l, ['location', 'loc']);
        String sub = extract(l, ['sub_location', 'sub_loc']);
        bool locOk = widget.selectedLocation.isEmpty || loc.toLowerCase() == widget.selectedLocation.toLowerCase();
        bool subOk = widget.selectedSubLocation.isEmpty || sub.toLowerCase() == widget.selectedSubLocation.toLowerCase();
        if (locOk && subOk) {
          String dept = extract(l, ['department', 'dept', 'dept_name']);
          if (dept.isNotEmpty) grouped.putIfAbsent(dept, () => []).add(l);
        }
      }
      for (var d in ["장년회", "부녀회", "청년회", "신학부", "새신자부"]) {
        grouped.putIfAbsent(d, () => []);
      }
    } 
    // 5. Team Status
    else if (lvl.contains('team')) {
      categoryName = widget.selectedDepartment.isNotEmpty ? widget.selectedDepartment : "Team";
      for (var l in widget.logs) {
        String sub = extract(l, ['sub_location', 'sub_loc']);
        String dept = extract(l, ['department', 'dept']);
        bool subOk = widget.selectedSubLocation.isEmpty || sub.toLowerCase() == widget.selectedSubLocation.toLowerCase();
        bool deptOk = widget.selectedDepartment.isEmpty || dept.toLowerCase() == widget.selectedDepartment.toLowerCase();
        if (subOk && deptOk) {
          String team = extract(l, ['team', 'team_name']);
          if (team.isNotEmpty) grouped.putIfAbsent(team, () => []).add(l);
        }
      }
      for (var t in ["팀1", "팀2", "팀3"]) {
        grouped.putIfAbsent(t, () => []);
      }
    } 
    // 6. Cell Status -> NATURALLY SORTED FROM SMALLEST TO HIGHEST (Fix for Point 5)
    else if (lvl.contains('cell')) {
      categoryName = widget.selectedTeam.isNotEmpty ? widget.selectedTeam : "Cell groups";
      
      for (var l in widget.logs) {
        String team = extract(l, ['team', 'team_name']);
        bool teamOk = widget.selectedTeam.isEmpty || team.toLowerCase() == widget.selectedTeam.toLowerCase();
        if (teamOk) {
          String cell = extract(l, ['unit_name', 'cell_group', 'cell', 'cell_name']);
          if (cell.isNotEmpty) grouped.putIfAbsent(cell, () => []).add(l);
        }
      }

      for (var cg in _masterCellGroups) {
        grouped.putIfAbsent(cg, () => []);
      }

      if (grouped.isEmpty) {
        for (int i = 1; i <= 8; i++) {
          grouped["구역$i"] = [];
        }
      }

      // Sort keys naturally (1, 2, 3... 10)
      final sortedKeys = _sortCellGroups(grouped.keys.toList());
      final sortedGrouped = <String, List<dynamic>>{};
      for (var k in sortedKeys) {
        sortedGrouped[k] = grouped[k]!;
      }
      grouped = sortedGrouped;
    }

    if (grouped.isEmpty) return null;

    return _mergedBlock(categoryName, grouped.map((k, v) => MapEntry(k, _calc(v))));
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
    children.forEach((k, v) => rows.add(_dataRow(k, v is List ? _calc(v) : v)));
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
      decoration: BoxDecoration(
        color: bg ?? Colors.white, 
        border: Border.all(color: Colors.black45, width: 0.4)
      ),
      child: Text(
        t, 
        textAlign: TextAlign.center, 
        style: GoogleFonts.merriweather(
          fontSize: 9.5, 
          fontWeight: b ? FontWeight.w900 : FontWeight.normal, 
          color: color ?? Colors.black87
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildChart() {
    bool isTrend = widget.timePeriod != "Current status";
    String xName = widget.timePeriod == "Current status" ? widget.groupBy : "Period";
    
    Map<String, List<dynamic>> cg = {};
    String k = _getParentKey();
    for (var log in widget.logs) {
      String n = log['members']?[k]?.toString() ?? "Other";
      cg.putIfAbsent(n, () => []).add(log);
    }
    List<String> keys = cg.keys.toList();

    return Column(children: [
      Container(
        height: 350, 
        width: double.infinity, 
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
        child: isTrend ? _lineChart(xName, keys, cg) : _barChart(xName, keys, cg)
      ),
      Padding(padding: const EdgeInsets.only(top: 5, bottom: 5), child: _buildLegend()),
    ]);
  }

  Widget _barChart(String xN, List<String> ks, Map<String, List<dynamic>> gs) => BarChart(BarChartData(
    maxY: 100, 
    borderData: FlBorderData(show: true, border: Border(left: BorderSide(color: Colors.black, width: 1.0), bottom: BorderSide(color: Colors.black, width: 1.0))),
    titlesData: _titles(xN, ks), 
    gridData: const FlGridData(show: false),
    barGroups: List.generate(ks.length, (i) {
      final s = _calc(gs[ks[i]]!);
      return BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: 100, color: Colors.amber.withValues(alpha: 0.25), width: 8),
        BarChartRodData(toY: s['pct'], color: pPurple, width: 8),
        BarChartRodData(toY: s['ipp'], color: Colors.blue, width: 8),
      ]);
    }),
  ));

  Widget _lineChart(String xN, List<String> ks, Map<String, List<dynamic>> gs) => LineChart(LineChartData(
    maxY: 100, 
    borderData: FlBorderData(show: true, border: Border(left: BorderSide(color: Colors.black, width: 1.0), bottom: BorderSide(color: Colors.black, width: 1.0))),
    titlesData: _titles(xN, ks), 
    gridData: const FlGridData(show: false),
    lineBarsData: [
      LineChartBarData(spots: List.generate(ks.length, (i) => FlSpot(i.toDouble(), 100)), color: Colors.amber.withValues(alpha: 0.2), dotData: const FlDotData(show: false)),
      LineChartBarData(spots: List.generate(ks.length, (i) => FlSpot(i.toDouble(), _calc(gs[ks[i]]!)['pct'])), color: pPurple, isCurved: true, barWidth: 3),
      LineChartBarData(spots: List.generate(ks.length, (i) => FlSpot(i.toDouble(), _calc(gs[ks[i]]!)['ipp'])), color: Colors.blue, isCurved: true, barWidth: 2),
    ],
  ));

  FlTitlesData _titles(String xN, List<String> ks) => FlTitlesData(
    bottomTitles: AxisTitles(
      axisNameWidget: Text(xN, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)), 
      axisNameSize: 18, 
      sideTitles: SideTitles(showTitles: true, reservedSize: 25, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 2), child: Text(v.toInt() < ks.length ? ks[v.toInt()] : "", style: GoogleFonts.merriweather(fontSize: 10))))),
    leftTitles: AxisTitles(
      axisNameWidget: Text("Percentage (%)", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)), 
      axisNameSize: 22, 
      sideTitles: SideTitles(showTitles: true, reservedSize: 35, getTitlesWidget: (v, m) => Text("${v.toInt()}%", style: GoogleFonts.merriweather(fontSize: 10)))),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );

  Widget _buildLegend() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _lgItem("Target", Colors.amber), const SizedBox(width: 20),
    _lgItem("Attendance", pPurple), const SizedBox(width: 20),
    _lgItem("In-person", Colors.blue),
  ]);

  Widget _lgItem(String t, Color c) => Row(children: [Container(width: 10, height: 10, color: c), const SizedBox(width: 5), Text(t, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold))]);

  Future<void> _printReport() async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Text("Attendance Report"))));
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  String _getParentKey() {
    String r = widget.level.toLowerCase();
    if (r.contains('location')) return 'location';
    if (r.contains('sub location')) return 'sub_location';
    if (r.contains('dept') || r.contains('group')) return 'department';
    return 'team';
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
        trailing: IconButton(icon: const Icon(Icons.fullscreen, size: 18), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => Scaffold(appBar: AppBar(title: Text(title, style: GoogleFonts.merriweather())), body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(8), child: content)))))),
      ),
      const Divider(height: 1, color: Colors.black26),
      content,
    ]),
  );
}