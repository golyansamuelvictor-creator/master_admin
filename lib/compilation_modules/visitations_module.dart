// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

class VisitationsModule extends StatelessWidget {
  final List<dynamic> logs;
  final String level;
  final String category;

  const VisitationsModule({
    super.key, 
    required this.logs, 
    required this.level, 
    required this.category
  });

  // --- LOGIC: DATA AGGREGATION ---
  Map<String, List<dynamic>> _groupDataByLevel() {
    Map<String, List<dynamic>> map = {};
    
    // Determining the correct key based on the Main Engine's navigation level
    String k = 'cell_number';
    if (level.contains('Team')) k = 'team_number';
    else if (level.contains('Dept')) k = 'current_dept';
    else if (level.contains('Sub loc')) k = 'sub_location';
    else if (level.contains('Loc')) k = 'location';
    else if (level.contains('Church')) k = 'location'; // Default to loc for church-wide

    for (var log in logs) {
      String val = log['members'][k]?.toString() ?? "Unassigned";
      map.putIfAbsent(val, () => []).add(log);
    }
    return map;
  }

  // --- UI: TABLE SUMMARY (Title Case) ---
  Widget _buildVisitationsTable(Map<String, List<dynamic>> groupedData, Color pPurple) {
    List<String> h = ["Unit name", "Saints", "Total visited", "Counselled", "Positive", "Negative"];

    return LayoutBuilder(builder: (context, constraints) {
      // FIXED: cellW is utilized to maintain professional rigid column widths
      double cellW = max(100.0, constraints.maxWidth / h.length);

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
              int saints = unitData.value.length;
              
              // Filter data by current visitation category (LTA, H.M, etc)
              var filtered = unitData.value.where((l) => l['visitation_reason'] == category).toList();
              
              int pos = filtered.where((l) => l['status_detail'] == "Positive").length;
              int neg = filtered.where((l) => l['status_detail'] == "Negative").length;
              int visited = pos + neg;
              
              // Counselled logic
              int counselled = filtered.where((l) => 
                ["Education", "LTA"].contains(l['visitation_reason'])
              ).length;

              return DataRow(
                color: WidgetStateProperty.all(idx.isEven ? Colors.white : const Color(0xFFF8FAFC)),
                cells: [
                  _cell(unitData.key, cellW, isBold: true),
                  _cell("$saints", cellW),
                  _cell("$visited", cellW, color: pPurple, isBold: true),
                  _cell("$counselled", cellW),
                  _dataWithPct(pos, visited, cellW, Colors.green[700]!),
                  _dataWithPct(neg, visited, cellW, Colors.red[700]!),
                ],
              );
            }).toList(),
          ),
        ),
      );
    });
  }

  // --- UI: PIE CHART ---
  Widget _buildOutcomeChart(Color pPurple) {
    var filtered = logs.where((l) => l['visitation_reason'] == category).toList();
    if (filtered.isEmpty) return const SizedBox(height: 120, child: Center(child: Text("No data found for this category", style: TextStyle(fontStyle: FontStyle.italic))));

    int pos = filtered.where((l) => l['status_detail'] == "Positive").length;
    int neg = filtered.where((l) => l['status_detail'] == "Negative").length;
    int pending = filtered.where((l) => l['status_detail'] == "Not Visited").length;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
      child: Column(children: [
        _buildLegend(pPurple),
        const SizedBox(height: 30),
        SizedBox(height: 300, child: PieChart(PieChartData(
          sectionsSpace: 4, 
          centerSpaceRadius: 50, 
          sections: [
            PieChartSectionData(
              value: pos.toDouble(), 
              title: "$pos", 
              color: Colors.green[600], 
              radius: 60, 
              titleStyle: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)
            ),
            PieChartSectionData(
              value: neg.toDouble(), 
              title: "$neg", 
              color: Colors.red[400], 
              radius: 60, 
              titleStyle: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)
            ),
            PieChartSectionData(
              value: pending.toDouble(), 
              title: "$pending", 
              color: Colors.blueGrey[100], 
              radius: 60, 
              titleStyle: GoogleFonts.merriweather(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 11)
            ),
          ]
        )))
      ]),
    );
  }

  // --- HELPERS ---
  DataCell _cell(String t, double w, {Color? color, bool isBold = false}) => DataCell(
    SizedBox(width: w, child: Center(child: Text(t, style: GoogleFonts.merriweather(fontSize: 11, color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))))
  );

  DataCell _dataWithPct(int count, int total, double w, Color color) {
    double pct = total > 0 ? (count / total * 100) : 0;
    return DataCell(
      SizedBox(width: w, child: Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text("$count", style: GoogleFonts.merriweather(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        const SizedBox(width: 4),
        Text("(${pct.toStringAsFixed(0)}%)", style: GoogleFonts.merriweather(fontSize: 9, color: Colors.blueGrey)),
      ])))
    );
  }

  Widget _buildLegend(Color pPurple) {
    return Wrap(spacing: 20, runSpacing: 10, alignment: WrapAlignment.center, children: [
      _legItem("Positive", Colors.green[600]!),
      _legItem("Negative", Colors.red[400]!),
      _legItem("Not visited", Colors.blueGrey[200]!),
    ]);
  }

  Widget _legItem(String l, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)), 
    const SizedBox(width: 8), 
    Text(l, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]))
  ]);

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
    Map<String, List<dynamic>> groupedData = _groupDataByLevel();
    return Column(children: [
      _section("Member care summary: $category", _buildVisitationsTable(groupedData, pPurple), context),
      const SizedBox(height: 10),
      _section("Visitation outcomes (%)", _buildOutcomeChart(pPurple), context),
    ]);
  }
}