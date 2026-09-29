// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

class DailyParticipationModule extends StatelessWidget {
  final List<dynamic> logs;
  final String timePeriod, level;
  final String analyticsMode;
  final String groupBy;

  const DailyParticipationModule({
    super.key, 
    required this.logs, 
    required this.timePeriod, 
    required this.level,
    required this.analyticsMode,
    required this.groupBy
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

  // --- UI: TABLE SUMMARY ---
  Widget _buildTable(Map<String, List<dynamic>> groupedData, Color pPurple) {
    List<String> h = ["Unit name", "Workers", "Mon", "Mon %", "Tue", "Tue %", "Wed", "Wed %", "Thu", "Thu %", "Fri", "Fri %"];

    return LayoutBuilder(builder: (context, constraints) {
      // FIXED: cellW is now utilized throughout the headers and cells
      double cellW = max(75.0, constraints.maxWidth / 6.5);
      
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
              
              // Count participation (Assuming "Yes" from your Entry Form logic)
              int mon = data.value.where((l) => l['mon_part'] == "Yes").length;
              int tue = data.value.where((l) => l['tue_part'] == "Yes").length;
              int wed = data.value.where((l) => l['wed_part'] == "Yes").length;
              int thu = data.value.where((l) => l['thu_part'] == "Yes").length;
              int fri = data.value.where((l) => l['fri_part'] == "Yes").length;

              return DataRow(
                color: WidgetStateProperty.all(idx.isEven ? Colors.white : const Color(0xFFF8FAFC)),
                cells: [
                  _cell(data.key, cellW, isBold: true), 
                  _cell("$tot", cellW),
                  _cell("$mon", cellW), _pCell(mon, tot, cellW, pPurple),
                  _cell("$tue", cellW), _pCell(tue, tot, cellW, pPurple),
                  _cell("$wed", cellW), _pCell(wed, tot, cellW, pPurple),
                  _cell("$thu", cellW), _pCell(thu, tot, cellW, pPurple),
                  _cell("$fri", cellW), _pCell(fri, tot, cellW, pPurple),
                ],
              );
            }).toList(),
          ),
        ),
      );
    });
  }

  // --- UI: CHART ---
  Widget _buildParticipationChart(Map<String, List<dynamic>> groupedData, Color pPurple) {
    if (groupedData.isEmpty) return const SizedBox(height: 100, child: Center(child: Text("No visualization data found")));
    
    // Aggregate overall percentages for the days
    var allLogs = groupedData.values.expand((x) => x).toList();
    int tot = allLogs.length;
    if (tot == 0) return const SizedBox(height: 100);

    double m = (allLogs.where((l) => l['mon_part'] == "Yes").length / tot * 100);
    double t = (allLogs.where((l) => l['tue_part'] == "Yes").length / tot * 100);
    double w = (allLogs.where((l) => l['wed_part'] == "Yes").length / tot * 100);
    double th = (allLogs.where((l) => l['thu_part'] == "Yes").length / tot * 100);
    double f = (allLogs.where((l) => l['fri_part'] == "Yes").length / tot * 100);

    List<double> values = [m, t, w, th, f];
    List<String> days = ["Mon", "Tue", "Wed", "Thu", "Fri"];

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 30, 10, 10), 
      height: 300, 
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
                    padding: const EdgeInsets.only(top: 8.0),
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
    SizedBox(width: w, child: Center(child: Text(t, style: GoogleFonts.merriweather(fontSize: 11, color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))))
  );
  
  DataCell _pCell(int c, int t, double w, Color clr) {
    double pct = t > 0 ? (c / t * 100) : 0;
    return DataCell(
      SizedBox(width: w, child: Center(child: Text("${pct.toStringAsFixed(0)}%", 
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
      if (analyticsMode == 'Ranking') 
        const Center(child: Padding(
          padding: EdgeInsets.all(40),
          child: Text("Switch to 'Summary' to view participation data", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
        ))
      else ...[
        _section("Workers daily summary", _buildTable(processedData, pPurple), context),
        const SizedBox(height: 10),
        _section("Weekly breakdown (%)", _buildParticipationChart(processedData, pPurple), context),
      ],
    ]);
  }
}