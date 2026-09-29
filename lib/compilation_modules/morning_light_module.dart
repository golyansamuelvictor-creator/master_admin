// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

class MorningLightModule extends StatelessWidget {
  final List<dynamic> logs;
  final String timePeriod, level;
  final String analyticsMode;
  final String groupBy;

  const MorningLightModule({
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

  // --- UI: TABLE SUMMARY (14 Columns) ---
  Widget _buildMLTable(Map<String, List<dynamic>> groupedData, Color pPurple) {
    List<String> h = [
      "Unit name", "Saints", "Avg part", "Avg %", 
      "Mon", "Mon %", "Tue", "Tue %", "Wed", "Wed %", "Thu", "Thu %", "Fri", "Fri %"
    ];

    return LayoutBuilder(builder: (context, constraints) {
      // FIXED: cellW is used to create a rigid, professional Excel-like grid
      double cellW = max(75.0, constraints.maxWidth / 7);
      
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
              var unitData = entry.value;
              int tot = unitData.value.length;
              
              // Daily Counts logic based on DB keys
              int m = unitData.value.where((l) => l['mon_ml'] == "ML Did").length;
              int t = unitData.value.where((l) => l['tue_ml'] == "ML Did").length;
              int w = unitData.value.where((l) => l['wed_ml'] == "ML Did").length;
              int th = unitData.value.where((l) => l['thu_ml'] == "ML Did").length;
              int f = unitData.value.where((l) => l['fri_ml'] == "ML Did").length;
              
              double avg = (m + t + w + th + f) / 5;

              return DataRow(
                color: WidgetStateProperty.all(idx.isEven ? Colors.white : const Color(0xFFF8FAFC)),
                cells: [
                  _cell(unitData.key, cellW, isBold: true), 
                  _cell("$tot", cellW),
                  _cell(avg.toStringAsFixed(1), cellW, color: pPurple, isBold: true),
                  _pCell(avg, tot, cellW, pPurple),
                  _cell("$m", cellW), _pCell(m.toDouble(), tot, cellW, Colors.blue[700]!),
                  _cell("$t", cellW), _pCell(t.toDouble(), tot, cellW, Colors.blue[700]!),
                  _cell("$w", cellW), _pCell(w.toDouble(), tot, cellW, Colors.blue[700]!),
                  _cell("$th", cellW), _pCell(th.toDouble(), tot, cellW, Colors.blue[700]!),
                  _cell("$f", cellW), _pCell(f.toDouble(), tot, cellW, Colors.blue[700]!),
                ],
              );
            }).toList(),
          ),
        ),
      );
    });
  }

  // --- UI: RANKING LIST (Sentence Case) ---
  Widget _buildRankingList(Map<String, List<dynamic>> groupedData, bool isTop) {
    List<Map<String, dynamic>> stats = groupedData.entries.map((e) {
      int tot = e.value.length;
      int m = e.value.where((l) => l['mon_ml'] == "ML Did").length;
      int t = e.value.where((l) => l['tue_ml'] == "ML Did").length;
      int w = e.value.where((l) => l['wed_ml'] == "ML Did").length;
      double avg = (m + t + w) / 3; 
      return {'name': e.key, 'pct': tot > 0 ? (avg / tot * 100) : 0.0};
    }).toList();

    stats.sort((a, b) => isTop ? b['pct'].compareTo(a['pct']) : a['pct'].compareTo(b['pct']));
    var displayList = stats.take(5).toList();

    if (displayList.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No ranking data found")));

    return Column(children: displayList.map((item) => ListTile(
      leading: CircleAvatar(
        backgroundColor: isTop ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1), 
        radius: 18, 
        child: Icon(isTop ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded, size: 16, color: isTop ? Colors.green : Colors.red)
      ),
      title: Text(item['name'], style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13)),
      trailing: Text("${item['pct'].toStringAsFixed(1)}%", 
        style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: isTop ? Colors.green[700] : Colors.red[700])),
    )).toList());
  }

  // --- UI: CHART ---
  Widget _buildMLChart(Map<String, List<dynamic>> groupedData, Color pPurple) {
    if (groupedData.isEmpty) return const SizedBox(height: 100, child: Center(child: Text("Data not found")));
    
    var allLogs = groupedData.values.expand((x) => x).toList();
    int tot = allLogs.length;
    if (tot == 0) return const SizedBox(height: 100);

    List<double> values = [
      (allLogs.where((l) => l['mon_ml'] == "ML Did").length / tot * 100),
      (allLogs.where((l) => l['tue_ml'] == "ML Did").length / tot * 100),
      (allLogs.where((l) => l['wed_ml'] == "ML Did").length / tot * 100),
      (allLogs.where((l) => l['thu_ml'] == "ML Did").length / tot * 100),
      (allLogs.where((l) => l['fri_ml'] == "ML Did").length / tot * 100),
    ];
    List<String> days = ["Mon", "Tue", "Wed", "Thu", "Fri"];

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 30, 10, 10), 
      height: 350, 
      child: BarChart(
        BarChartData(
          maxY: 100,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  if (val.toInt() >= days.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: Text(days[val.toInt()], style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  );
                }
              )
            )
          ),
          barGroups: List.generate(5, (i) => BarChartGroupData(
            x: i, 
            barRods: [BarChartRodData(toY: values[i], color: pPurple, width: 22, borderRadius: const BorderRadius.vertical(top: Radius.circular(6)))]
          )),
        )
      )
    );
  }

  // --- HELPERS ---
  DataCell _cell(String t, double w, {Color? color, bool isBold = false}) => DataCell(
    SizedBox(width: w, child: Center(child: Text(t, style: GoogleFonts.merriweather(fontSize: 10, color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))))
  );
  
  DataCell _pCell(double count, int total, double w, Color color) {
    double pct = total > 0 ? (count / total * 100) : 0;
    return DataCell(
      SizedBox(width: w, child: Center(child: Text("${pct.toStringAsFixed(0)}%", 
        style: GoogleFonts.merriweather(color: color, fontWeight: FontWeight.w900, fontSize: 9))))
    );
  }

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

  @override
  Widget build(BuildContext context) {
    const pPurple = Color(0xFF4A148C);
    Map<String, List<dynamic>> processedData = _groupDataBySelection();
    
    return Column(children: [
      if (analyticsMode == 'Ranking') ...[
        _section("Top performing morning light units", _buildRankingList(processedData, true), context),
        _section("Units requiring support", _buildRankingList(processedData, false), context),
      ] else ...[
        _section("Morning light participation summary", _buildMLTable(processedData, pPurple), context),
        const SizedBox(height: 10),
        _section("Daily participation breakdown (%)", _buildMLChart(processedData, pPurple), context),
      ],
    ]);
  }
}