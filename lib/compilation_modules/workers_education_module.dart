// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

class WorkersEducationModule extends StatelessWidget {
  final List<dynamic> logs;
  final String timePeriod, level;
  final String analyticsMode; 
  final String groupBy;      
  final double targetValue; 

  const WorkersEducationModule({
    super.key, 
    required this.logs, 
    required this.timePeriod, 
    required this.level,
    required this.analyticsMode,
    required this.groupBy,
    this.targetValue = 90.0,
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

  // --- UI: TABLE SUMMARY (8 Columns) ---
  Widget _buildEducationTable(Map<String, List<dynamic>> groupedData, Color pPurple) {
    List<String> h = ["Unit name", "Workers", "Sunday", "Sun %", "Wednesday", "Wed %", "Other", "Oth %"];

    return LayoutBuilder(builder: (context, constraints) {
      // FIXED: cellW is now used to ensure a professional, rigid horizontal scroll
      double cellW = max(90.0, constraints.maxWidth / 6);

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal, 
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            headingRowHeight: 48, horizontalMargin: 10, columnSpacing: 0,
            headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
            columns: h.map((s) => DataColumn(
              label: SizedBox(width: cellW, child: Center(child: Text(s, style: GoogleFonts.merriweather(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))))
            )).toList(),
            rows: groupedData.entries.toList().asMap().entries.map((entry) {
              int idx = entry.key; 
              var unitData = entry.value;
              int tot = unitData.value.length;
              
              int sun = unitData.value.where((l) => l['edu_sun'] == "Attended").length;
              int wed = unitData.value.where((l) => l['edu_wed'] == "Attended").length;
              int oth = unitData.value.where((l) => l['edu_other'] == "Attended").length;

              return DataRow(
                color: WidgetStateProperty.all(idx.isEven ? Colors.white : const Color(0xFFF8FAFC)),
                cells: [
                  _cell(unitData.key, cellW, isBold: true),
                  _cell("$tot", cellW),
                  _cell("$sun", cellW), _pCell(sun, tot, cellW, pPurple),
                  _cell("$wed", cellW), _pCell(wed, tot, cellW, pPurple),
                  _cell("$oth", cellW), _pCell(oth, tot, cellW, pPurple),
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
      int att = e.value.where((l) => l['edu_sun'] == "Attended" || l['edu_wed'] == "Attended").length;
      return {'name': e.key, 'pct': tot > 0 ? (att / tot * 100) : 0.0};
    }).toList();

    stats.sort((a, b) => isTop ? b['pct'].compareTo(a['pct']) : a['pct'].compareTo(b['pct']));
    var displayList = stats.take(5).toList();

    if (displayList.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No ranking data found")));

    return Column(children: displayList.map((item) => ListTile(
      leading: CircleAvatar(
        backgroundColor: isTop ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1), 
        radius: 18, 
        child: Icon(isTop ? Icons.star_rounded : Icons.priority_high_rounded, size: 16, color: isTop ? Colors.green : Colors.red)
      ),
      title: Text(item['name'], style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13)),
      trailing: Text("${item['pct'].toStringAsFixed(1)}%", 
        style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: isTop ? Colors.green[700] : Colors.red[700])),
    )).toList());
  }

  // --- UI: CHART (Merriweather Axes) ---
  Widget _buildEducationChart(Map<String, List<dynamic>> groupedData, Color pPurple) {
    if (logs.isEmpty) return const SizedBox(height: 100, child: Center(child: Text("Data not found")));
    
    var unitLogs = groupedData.values.first; 
    int total = unitLogs.length;
    if (total == 0) return const SizedBox(height: 100);

    double sPerc = (unitLogs.where((l) => l['edu_sun'] == "Attended").length / total) * 100;
    double wPerc = (unitLogs.where((l) => l['edu_wed'] == "Attended").length / total) * 100;
    double oPerc = (unitLogs.where((l) => l['edu_other'] == "Attended").length / total) * 100;

    List<double> values = [sPerc, wPerc, oPerc];
    List<String> labels = ["Sunday", "Wednesday", "Other"];

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
                  if (val.toInt() >= labels.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(labels[val.toInt()], style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  );
                }
              )
            )
          ),
          barGroups: List.generate(3, (i) => BarChartGroupData(
            x: i, 
            barRods: [BarChartRodData(
              toY: values[i], 
              color: i == 0 ? pPurple : i == 1 ? Colors.blue[600] : Colors.teal[600], 
              width: 25,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6))
            )]
          )),
        )
      )
    );
  }

  // --- HELPERS ---
  DataCell _cell(String t, double w, {Color? color, bool isBold = false}) => DataCell(
    SizedBox(width: w, child: Center(child: Text(t, style: GoogleFonts.merriweather(fontSize: 11, color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))))
  );
  
  DataCell _pCell(int c, int t, double w, Color clr) {
    double pct = t > 0 ? (c / t * 100) : 0;
    return DataCell(
      SizedBox(width: w, child: Center(child: Text("${pct.toStringAsFixed(1)}%", 
        style: GoogleFonts.merriweather(color: clr, fontWeight: FontWeight.w900, fontSize: 10))))
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
    Navigator.push(ctx, MaterialPageRoute(fullscreenDialog: true, builder: (ctx) => Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Text(t, style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold)), centerTitle: true), 
      body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(20), child: c))
    )));
  }

  @override
  Widget build(BuildContext context) {
    const pPurple = Color(0xFF4A148C);
    Map<String, List<dynamic>> processedData = _groupDataBySelection();
    
    return Column(children: [
      if (analyticsMode == 'Ranking') ...[
        _section("Top performing education units", _buildRankingList(processedData, true), context),
        _section("Units requiring education support", _buildRankingList(processedData, false), context),
      ] else ...[
        _section("Workers education summary", _buildEducationTable(processedData, pPurple), context),
        const SizedBox(height: 10),
        _section("Attendance analytics distribution (%)", _buildEducationChart(processedData, pPurple), context),
      ],
    ]);
  }
}