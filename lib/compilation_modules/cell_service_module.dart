// ignore_for_file: curly_braces_in_flow_control_structures, unused_element
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class CellServiceModule extends StatefulWidget {
  final List<dynamic> logs;
  final String timePeriod, level, analyticsMode, groupBy;
  final double targetValue;

  const CellServiceModule({
    super.key, 
    required this.logs, 
    required this.timePeriod, 
    required this.level, 
    required this.analyticsMode,
    required this.groupBy,
    required this.targetValue,
  });

  @override
  State<CellServiceModule> createState() => _CellServiceModuleState();
}

class _ServiceAttendanceModuleState {} // Placeholder to avoid confusion

class _CellServiceModuleState extends State<CellServiceModule> {
  bool _isExpanded = false;
  final Color pPurple = const Color(0xFF4A148C);

  // Precision Sizing
  static const double rh = 26.0; 
  static const double hh = 32.0; 
  static const double sh = 20.0; 
  static const double cw = 65.0; 
  static const double lw = 110.0; 
  static const double totalHeaderHeight = hh + hh + sh;

  // --- CALCULATION ENGINE ---
  Map<String, dynamic> _calc(List<dynamic> l) {
    int n = l.length;
    int ip = l.where((x) => x['status_detail'] == "CS In-Person").length;
    int on = l.where((x) => x['status_detail'] == "CS Online").length;
    int mu = l.where((x) => x['status_detail'] == "CS Make Up").length;
    int ab = l.where((x) => x['status_detail'] == "CS Absentee").length;
    int att = ip + on + mu;

    return {
      "n": n, "att": att, "pct": n > 0 ? (att / n * 100) : 0.0,
      "ip": ip, "ipp": n > 0 ? (ip / n * 100) : 0.0,
      "on": on, "onp": n > 0 ? (on / n * 100) : 0.0,
      "mu": mu, "mup": n > 0 ? (mu / n * 100) : 0.0,
      "ab": ab, "abp": n > 0 ? (ab / n * 100) : 0.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final hqList = widget.logs.where((l) => ["교회등록", "총회등록"].contains(l['reg_status']?.toString())).toList();
    final enList = widget.logs.where((l) => l['reg_status']?.toString() == "입교").toList();
    
    final Map<String, dynamic> hqS = _calc(hqList); 
    final Map<String, dynamic> enS = _calc(enList);
    
    // Row 5 (General total) = Row 6 + Row 7
    final Map<String, dynamic> totS = {
      "n": hqS['n'] + enS['n'], "att": hqS['att'] + enS['att'],
      "pct": (hqS['n'] + enS['n']) > 0 ? ((hqS['att'] + enS['att']) / (hqS['n'] + enS['n']) * 100) : 0.0,
      "ip": hqS['ip'] + enS['ip'], "ipp": (hqS['n'] + enS['n']) > 0 ? ((hqS['ip'] + enS['ip']) / (hqS['n'] + enS['n']) * 100) : 0.0,
      "on": hqS['on'] + enS['on'], "onp": (hqS['n'] + enS['n']) > 0 ? ((hqS['on'] + enS['on']) / (hqS['n'] + enS['n']) * 100) : 0.0,
      "mu": hqS['mu'] + enS['mu'], "mup": (hqS['n'] + enS['n']) > 0 ? ((hqS['mu'] + enS['mu']) / (hqS['n'] + enS['n']) * 100) : 0.0,
      "ab": hqS['ab'] + enS['ab'], "abp": (hqS['n'] + enS['n']) > 0 ? ((hqS['ab'] + enS['ab']) / (hqS['n'] + enS['n']) * 100) : 0.0,
    };

    return Column(children: [
      _buildToolbar(),
      _section("Cell service table summary", _buildExcelGrid(hqS, enS, totS), context),
      const SizedBox(height: 8), 
      _section("Participation visualization", _buildChart(), context),
    ]);
  }

  Widget _buildToolbar() => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Row(children: [
      IconButton(onPressed: _printReport, icon: const Icon(Icons.print, color: Colors.blueGrey, size: 18)),
      IconButton(onPressed: () {}, icon: const Icon(Icons.download, color: Colors.green, size: 18)),
    ]),
    TextButton.icon(onPressed: () => setState(() => _isExpanded = !_isExpanded), icon: const Icon(Icons.open_in_full, size: 14), label: Text("Expand regional grid", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple))),
  ]);

  // --- GRID UI ---
  Widget _buildExcelGrid(Map<String, dynamic> hq, Map<String, dynamic> en, Map<String, dynamic> tot) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade700, width: 0.4)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildMergedHeader(),
            _mergedRow("Total", "General total", tot, b: true),
            _mergedBlock("Status", {"Church / h.q": hq, "Enrollment": en}),
            if (_isExpanded) ..._buildDynamicBreakdownRows(),
          ]),
        ),
      ),
    );
  }

  List<Widget> _buildDynamicBreakdownRows() {
    List<Widget> breakdown = [];
    String parentKey = _getParentKey();
    String childKey = _getChildKey();

    Map<String, Map<String, List<dynamic>>> groupLogs() {
      Map<String, Map<String, List<dynamic>>> map = {};
      for (var log in widget.logs) {
        String p = log['members']?[parentKey]?.toString() ?? "Other";
        String c = log['members']?[childKey]?.toString() ?? "Other";
        map.putIfAbsent(p, () => {}).putIfAbsent(c, () => []).add(log);
      }
      return map;
    }

    String r = widget.level.toLowerCase();
    if (r.contains('location')) {
       groupLogs().forEach((k, v) => breakdown.add(_mergedBlock("Sub Locations", v)));
    } else if (r.contains('sub location')) {
       groupLogs().forEach((k, v) => breakdown.add(_mergedBlock("Dept", v)));
    } else if (r.contains('dept')) {
       groupLogs().forEach((k, v) => breakdown.add(_mergedBlock("Team", v)));
    } else {
       groupLogs().forEach((k, v) => breakdown.add(_mergedBlock("Cell Group", v)));
    }
    return breakdown;
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
    children.forEach((k, v) => rows.add(_dataRow(k, v is List ? _calc(v) : v)));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cell(label, w: lw, h: (rows.length * rh).toDouble(), b: true),
      Column(children: rows),
    ]);
  }

  Widget _mergedRow(String c1, String c2, Map<String, dynamic> d, {bool b = false}) => Row(children: [
    _cell(c1, w: lw, h: rh, b: b),
    _dataRow(c2, d, b: b),
  ]);

  Widget _dataRow(String label, Map<String, dynamic> d, {bool b = false}) {
    return Row(children: [
      _cell(label, w: lw, h: rh, b: b, a: Alignment.centerLeft),
      _cell("${d['n']}"), _cell("${d['att']}"), _cell("${d['pct'].toStringAsFixed(1)}%", b: true),
      _cell("${d['ip']}"), _cell("${d['ipp'].toStringAsFixed(1)}%"),
      _cell("${d['on']}"), _cell("${d['onp'].toStringAsFixed(1)}%"),
      _cell("${d['mu']}"), _cell("${d['mup'].toStringAsFixed(1)}%"),
      _cell("${d['ab']}", color: Colors.red[800]), _cell("${d['abp'].toStringAsFixed(1)}%"),
    ]);
  }

  Widget _cell(String t, {double w = cw, double h = rh, bool b = false, Color? color, Color? bg, Alignment a = Alignment.center}) => Container(
    width: w, height: h, alignment: a, padding: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(color: bg, border: Border.all(color: Colors.grey.shade700, width: 0.4)),
    child: Text(t, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: b ? FontWeight.w900 : FontWeight.normal, color: color ?? Colors.black)),
  );

  // --- CHART UI ---
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
      Container(height: 330, width: double.infinity, padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
        child: isTrend ? _lineChart(xName, keys, cg) : _barChart(xName, keys, cg)),
      Padding(padding: const EdgeInsets.only(top: 2, bottom: 5), child: _buildLegend()),
    ]);
  }

  Widget _barChart(String xN, List<String> ks, Map<String, List<dynamic>> gs) => BarChart(BarChartData(
    maxY: 100, borderData: FlBorderData(show: true, border: Border(left: BorderSide(color: Colors.grey.shade800), bottom: BorderSide(color: Colors.grey.shade800))),
    titlesData: _titles(xN, ks), gridData: const FlGridData(show: false),
    barGroups: List.generate(ks.length, (i) {
      final s = _calc(gs[ks[i]]!);
      return BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: 100, color: Colors.amber.withValues(alpha: 0.2), width: 8, borderRadius: BorderRadius.circular(2)),
        BarChartRodData(toY: s['pct'], color: pPurple, width: 8, borderRadius: BorderRadius.circular(2)),
        BarChartRodData(toY: s['ipp'], color: Colors.blue, width: 8, borderRadius: BorderRadius.circular(2)),
      ]);
    }),
  ));

  Widget _lineChart(String xN, List<String> ks, Map<String, List<dynamic>> gs) => LineChart(LineChartData(
    maxY: 100, borderData: FlBorderData(show: true, border: Border(left: BorderSide(color: Colors.grey.shade800), bottom: BorderSide(color: Colors.grey.shade800))),
    titlesData: _titles(xN, ks), gridData: const FlGridData(show: false),
    lineBarsData: [
      LineChartBarData(spots: List.generate(ks.length, (i) => FlSpot(i.toDouble(), 100)), color: Colors.amber.withValues(alpha: 0.1), dotData: const FlDotData(show: false)),
      LineChartBarData(spots: List.generate(ks.length, (i) => FlSpot(i.toDouble(), _calc(gs[ks[i]]!)['pct'])), color: pPurple, isCurved: true, barWidth: 3),
      LineChartBarData(spots: List.generate(ks.length, (i) => FlSpot(i.toDouble(), _calc(gs[ks[i]]!)['ipp'])), color: Colors.blue, isCurved: true, barWidth: 2),
    ],
  ));

  FlTitlesData _titles(String xN, List<String> ks) => FlTitlesData(
    bottomTitles: AxisTitles(axisNameWidget: Padding(padding: const EdgeInsets.only(top: 2), child: Text(xN, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold))), axisNameSize: 18, sideTitles: SideTitles(showTitles: true, reservedSize: 25, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 2), child: Text(v.toInt() < ks.length ? ks[v.toInt()] : "", style: GoogleFonts.merriweather(fontSize: 10))))),
    leftTitles: AxisTitles(axisNameWidget: Text("Percentage (%)", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold)), axisNameSize: 22, sideTitles: SideTitles(showTitles: true, reservedSize: 35, getTitlesWidget: (v, m) => Text("${v.toInt()}%", style: GoogleFonts.merriweather(fontSize: 10)))),
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
    pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Text("Cell Group Service Report"))));
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  String _getParentKey() {
    String r = widget.level.toLowerCase();
    if (r.contains('location')) return 'location';
    if (r.contains('sub location')) return 'sub_location';
    if (r.contains('dept')) return 'current_dept';
    return 'team_number';
  }

  String _getChildKey() {
    String r = widget.level.toLowerCase();
    if (r.contains('location')) return 'sub_location';
    if (r.contains('sub location')) return 'current_dept';
    if (r.contains('dept')) return 'team_number';
    return 'cell_number';
  }

  Widget _section(String title, Widget content, BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6), 
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withValues(alpha: 0.1))),
    child: Column(children: [
      ListTile(
        dense: true,
        title: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: pPurple)),
        trailing: IconButton(icon: const Icon(Icons.fullscreen, size: 18), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => Scaffold(appBar: AppBar(title: Text(title, style: GoogleFonts.merriweather())), body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(8), child: content)))))),
      ),
      const Divider(height: 1),
      content,
    ]),
  );
}