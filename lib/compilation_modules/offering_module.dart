// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math';

class OfferingModule extends StatelessWidget {
  final List<dynamic> logs;
  final String timePeriod, level;
  final String analyticsMode;
  final String groupBy;

  const OfferingModule({
    super.key, 
    required this.logs, 
    required this.timePeriod, 
    required this.level,
    this.analyticsMode = 'Summary',
    this.groupBy = 'Cell'
  });

  // --- LOGIC: DATA AGGREGATION ---
  Map<String, List<dynamic>> _groupDataBySelection() {
    Map<String, List<dynamic>> map = {};
    String k = 'cell_number';
    if (groupBy == 'Team') k = 'team_number';
    if (groupBy == 'Dept') k = 'current_dept';
    if (groupBy == 'Sub-loc') k = 'sub_location';
    if (groupBy == 'Loc') k = 'location';

    for (var log in logs) {
      String val = log['members'][k]?.toString() ?? "Unassigned";
      map.putIfAbsent(val, () => []).add(log);
    }
    return map;
  }

  // --- UI: TABLE SUMMARY (13 Columns) ---
  Widget _buildOfferingTable(Map<String, List<dynamic>> groupedData, Color pPurple) {
    List<String> h = ["Unit name", "Saints", "Givers", "Tithe", "%", "Wkly", "%", "Thks", "%", "Const", "%", "Donat", "%"];

    return LayoutBuilder(builder: (context, constraints) {
      // FIXED: cellW is now utilized to define professional column geometry
      double cellW = max(80.0, constraints.maxWidth / 7);
      
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal, 
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            headingRowHeight: 48, horizontalMargin: 10, columnSpacing: 0,
            headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
            columns: h.map((s) => DataColumn(
              label: SizedBox(width: cellW, child: Center(child: Text(s, style: GoogleFonts.merriweather(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))))
            )).toList(),
            rows: groupedData.entries.toList().asMap().entries.map((entry) {
              int idx = entry.key; 
              var data = entry.value; 
              int tot = data.value.length;
              
              int t = data.value.where((l) => l['offering_tithe'] == "Yes" || l['offering_tithe'] == "Paid").length;
              int w = data.value.where((l) => l['offering_weekly'] == "Yes" || l['offering_weekly'] == "Paid").length;
              int th = data.value.where((l) => l['offering_thanks'] == "Yes" || l['offering_thanks'] == "Paid").length;
              int c = data.value.where((l) => l['offering_construction'] == "Yes" || l['offering_construction'] == "Paid").length;
              int d = data.value.where((l) => l['offering_donation'] == "Yes" || l['offering_donation'] == "Paid").length;
              
              int givers = data.value.where((l) => 
                [l['offering_tithe'], l['offering_weekly'], l['offering_thanks'], l['offering_construction'], l['offering_donation']]
                .any((v) => v == "Yes" || v == "Paid")
              ).length;

              return DataRow(
                color: WidgetStateProperty.all(idx.isEven ? Colors.white : const Color(0xFFF8FAFC)),
                cells: [
                  _cell(data.key, cellW, isBold: true), 
                  _cell("$tot", cellW),
                  _cell("$givers", cellW, color: pPurple, isBold: true),
                  _cell("$t", cellW), _pCell(t, tot, cellW, pPurple),
                  _cell("$w", cellW), _pCell(w, tot, cellW, Colors.blue[700]!),
                  _cell("$th", cellW), _pCell(th, tot, cellW, Colors.orange[800]!),
                  _cell("$c", cellW), _pCell(c, tot, cellW, Colors.teal[700]!),
                  _cell("$d", cellW), _pCell(d, tot, cellW, Colors.indigo[700]!),
                ]);
            }).toList(),
          ),
        ),
      );
    });
  }

  // --- UI: TREND CHART ---
  Widget _buildTrendChart(Color pPurple) {
    Map<DateTime, List<dynamic>> timeMap = {};
    for (var log in logs) {
      DateTime d = DateTime.parse(log['report_date']);
      timeMap.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(log);
    }
    var sortedDates = timeMap.keys.toList()..sort();
    if (sortedDates.isEmpty) return const SizedBox(height: 100, child: Center(child: Text("Data not found")));

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 10), 
      child: Column(children: [
        Wrap(spacing: 12, runSpacing: 8, children: [
          _legItem("Tithe", pPurple), _legItem("Weekly", Colors.blue), 
          _legItem("Thanks", Colors.orange), _legItem("Const", Colors.teal), 
          _legItem("Donat", Colors.indigo)
        ]),
        const SizedBox(height: 30),
        SizedBox(height: 300, child: LineChart(LineChartData(
          maxY: 100, 
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text("${v.toInt()}%", style: GoogleFonts.merriweather(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blueGrey)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1, getTitlesWidget: (v, m) => SideTitleWidget(meta: m, child: Text(v.toInt() < sortedDates.length ? DateFormat('dd/MM').format(sortedDates[v.toInt()]) : '', style: GoogleFonts.merriweather(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blueGrey))))),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            _lineData(sortedDates, timeMap, 'offering_tithe', pPurple),
            _lineData(sortedDates, timeMap, 'offering_weekly', Colors.blue),
            _lineData(sortedDates, timeMap, 'offering_thanks', Colors.orange),
            _lineData(sortedDates, timeMap, 'offering_construction', Colors.teal),
            _lineData(sortedDates, timeMap, 'offering_donation', Colors.indigo),
          ],
        ))),
      ]),
    );
  }

  // --- UI: RANKING LIST ---
  Widget _buildRankingList(Map<String, List<dynamic>> groupedData, bool isTop) {
    List<Map<String, dynamic>> stats = groupedData.entries.map((e) {
      int tot = e.value.length;
      int givers = e.value.where((l) => [l['offering_tithe'], l['offering_weekly']].any((v) => v == "Yes" || v == "Paid")).length;
      return {'name': e.key, 'pct': tot > 0 ? (givers / tot * 100) : 0.0};
    }).toList();

    stats.sort((a, b) => isTop ? b['pct'].compareTo(a['pct']) : a['pct'].compareTo(b['pct']));
    var displayList = stats.take(5).toList();

    return Column(children: displayList.map((item) => ListTile(
      leading: CircleAvatar(
        backgroundColor: isTop ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1), 
        radius: 18, 
        child: Icon(isTop ? Icons.payments_rounded : Icons.money_off_rounded, size: 16, color: isTop ? Colors.green : Colors.red)
      ),
      title: Text(item['name'], style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13)),
      trailing: Text("${item['pct'].toStringAsFixed(1)}%", 
        style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: isTop ? Colors.green[700] : Colors.red[700])),
    )).toList());
  }

  // --- HELPERS ---
  DataCell _cell(String t, double w, {Color? color, bool isBold = false}) => DataCell(
    SizedBox(width: w, child: Center(child: Text(t, style: GoogleFonts.merriweather(fontSize: 10, color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))))
  );
  
  DataCell _pCell(int c, int t, double w, Color clr) {
    double pct = t > 0 ? (c / t * 100) : 0;
    return DataCell(
      SizedBox(width: w, child: Center(child: Text("${pct.toStringAsFixed(0)}%", 
        style: GoogleFonts.merriweather(color: clr, fontWeight: FontWeight.w900, fontSize: 9))))
    );
  }

  LineChartBarData _lineData(List<DateTime> dates, Map<DateTime, List<dynamic>> map, String key, Color color) => LineChartBarData(
    isCurved: true, color: color, barWidth: 3, dotData: const FlDotData(show: false),
    spots: List.generate(dates.length, (i) { 
      var logs = map[dates[i]]!; 
      int count = logs.where((l) => l[key] == "Yes" || l[key] == "Paid").length; 
      return FlSpot(i.toDouble(), (count / logs.length) * 100); 
    })
  );

  Widget _section(String title, Widget content, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8))]
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          title: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: const Color(0xFF4A148C))), 
          trailing: IconButton(icon: const Icon(Icons.open_in_full_rounded, size: 20, color: Colors.blueGrey), onPressed: () => _showFull(context, title, content))
        ),
        const Divider(height: 1),
        content,
      ]),
    );
  }

  void _showFull(BuildContext ctx, String t, Widget c) {
    Navigator.push(ctx, MaterialPageRoute(
      fullscreenDialog: true, 
      builder: (context) => Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(title: Text(t, style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold)), centerTitle: true), 
        body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(20), child: c))
      )
    ));
  }

  Widget _legItem(String l, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)), 
    const SizedBox(width: 6), 
    Text(l, style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]))
  ]);

  @override
  Widget build(BuildContext context) {
    const pPurple = Color(0xFF4A148C);
    Map<String, List<dynamic>> processedData = _groupDataBySelection();
    
    return Column(children: [
      if (analyticsMode == 'Ranking') ...[
        _section("Top giving units", _buildRankingList(processedData, true), context),
        _section("Units requiring financial counseling", _buildRankingList(processedData, false), context),
      ] else ...[
        _section("Offering summary table", _buildOfferingTable(processedData, pPurple), context),
        const SizedBox(height: 10),
        _section("Giving trends (%)", _buildTrendChart(pPurple), context),
      ],
    ]);
  }
}