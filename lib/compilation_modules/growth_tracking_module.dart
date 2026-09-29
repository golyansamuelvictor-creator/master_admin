// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

class GrowthTrackingModule extends StatelessWidget {
  final List<dynamic> logs;
  final String level;
  final String analyticsMode;
  final String groupBy;

  const GrowthTrackingModule({
    super.key,
    required this.logs,
    required this.level,
    required this.analyticsMode,
    required this.groupBy,
  });

  Map<String, List<dynamic>> _groupDataBySelection() {
    Map<String, List<dynamic>> map = {};
    String k = 'cell_number';
    if (groupBy == 'Team') k = 'team_number';
    if (groupBy == 'Dept') k = 'current_dept';
    for (var log in logs) {
      String val = log['members']?[k]?.toString() ?? log[k]?.toString() ?? "General";
      map.putIfAbsent(val, () => []).add(log);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    const pPurple = Color(0xFF4A148C);
    Map<String, List<dynamic>> groupedData = _groupDataBySelection();

    return Column(
      children: [
        _section("Unit Growth Metrics", _buildGrowthTable(groupedData, pPurple), context),
        const SizedBox(height: 25),
        _section("Enrollment vs Graduation", _buildGrowthChart(groupedData), context),
      ],
    );
  }

  Widget _buildGrowthTable(Map<String, List<dynamic>> groupedData, Color pPurple) {
    List<String> h = ["Unit", "Total", "New", "Grads", "Trans", "Growth %"];

    return LayoutBuilder(builder: (context, constraints) {
      double cellW = max(75.0, constraints.maxWidth / h.length);

      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400, width: 0.8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingRowHeight: 46,
              horizontalMargin: 8,
              columnSpacing: 6,
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade300, width: 0.8),
                verticalInside: BorderSide(color: Colors.grey.shade300, width: 0.8),
              ),
              headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
              columns: h.map((s) => DataColumn(
                label: SizedBox(
                  width: cellW,
                  child: Center(
                    child: Text(
                      s,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              )).toList(),
              // Keeps headers and borders visible even if logs are empty
              rows: groupedData.isEmpty
                  ? [
                      DataRow(cells: [
                        _cell("-", cellW),
                        DataCell(
                          SizedBox(
                            width: cellW * 2,
                            child: const Center(
                              child: Text(
                                "No records found for this unit",
                                style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                              ),
                            ),
                          ),
                        ),
                        ...List.generate(h.length - 2, (_) => _cell("-", cellW)),
                      ])
                    ]
                  : groupedData.entries.toList().asMap().entries.map((entry) {
                      int idx = entry.key;
                      var data = entry.value;
                      int tot = data.value.length;
                      int newEnc = data.value.where((l) => l['is_new_enrollment'] == true).length;
                      int grad = data.value.where((l) => l['is_graduation'] == true).length;
                      int trans = data.value.where((l) => l['is_transfer'] == true).length;
                      double growth = tot > 0 ? ((newEnc - grad) / tot * 100) : 0;

                      return DataRow(
                        color: WidgetStateProperty.all(idx.isEven ? Colors.white : const Color(0xFFFBFBFE)),
                        cells: [
                          _cell(data.key, cellW, isBold: true),
                          _cell("$tot", cellW),
                          _cell("$newEnc", cellW, color: Colors.blue.shade700),
                          _cell("$grad", cellW, color: Colors.green.shade700),
                          _cell("$trans", cellW),
                          _cell("${growth.toStringAsFixed(1)}%", cellW, color: growth >= 0 ? Colors.green.shade800 : Colors.red, isBold: true),
                        ],
                      );
                    }).toList(),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildGrowthChart(Map<String, List<dynamic>> groupedData) {
    List<String> labels = groupedData.keys.toList();
    if (labels.isEmpty) {
      return const SizedBox(height: 100, child: Center(child: Text("No data available to chart")));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        height: 250,
        child: BarChart(
          BarChartData(
            borderData: FlBorderData(show: false),
            gridData: FlGridData(show: true, drawVerticalLine: false),
            barGroups: List.generate(labels.length, (i) {
              var unitLogs = groupedData[labels[i]]!;
              int n = unitLogs.where((l) => l['is_new_enrollment'] == true).length;
              int g = unitLogs.where((l) => l['is_graduation'] == true).length;
              return BarChartGroupData(x: i, barRods: [
                BarChartRodData(toY: n.toDouble(), color: Colors.blue.shade700, width: 10),
                BarChartRodData(toY: g.toDouble(), color: Colors.green.shade700, width: 10),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  DataCell _cell(String t, double w, {Color? color, bool isBold = false}) => DataCell(
    SizedBox(
      width: w,
      child: Center(
        child: Text(
          t,
          style: TextStyle(
            fontSize: 11,
            color: color ?? Colors.black87,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    ),
  );

  Widget _section(String title, Widget content, BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13)),
            trailing: IconButton(
              icon: const Icon(Icons.fullscreen_rounded, size: 26),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (context) => Scaffold(
                    appBar: AppBar(title: Text(title), centerTitle: true),
                    body: Center(child: SingleChildScrollView(child: content)),
                  ),
                ),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: Container(color: Colors.white, width: double.infinity, child: content),
          ),
        ],
      ),
    );
  }
}