// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math';
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/hierarchy_comparison_logic.dart';
import 'package:master_admin/core/app_palette.dart';

class HierarchyLeaderboardScreen extends StatefulWidget {
  final String role, loc, sub, dept, team, duty;

  const HierarchyLeaderboardScreen({
    super.key,
    required this.role,
    required this.loc,
    required this.sub,
    required this.dept,
    required this.team,
    required this.duty,
  });

  @override
  State<HierarchyLeaderboardScreen> createState() => _HierarchyLeaderboardScreenState();
}

class _HierarchyLeaderboardScreenState extends State<HierarchyLeaderboardScreen> {
  final Color pPurple = const Color(0xFF4A148C);
  List<Map<String, dynamic>> _data = [];
  bool _isLoading = true;

  late String _selectedLevel;
  late List<String> _availableLevels;

  @override
  void initState() {
    super.initState();
    _setupLevels();
    _loadRanking();
  }

  @override
  void didUpdateWidget(covariant HierarchyLeaderboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duty != widget.duty || oldWidget.role != widget.role) {
      _loadRanking();
    }
  }

  void _setupLevels() {
    String r = widget.role.toLowerCase();
    if (r == 'admin' || r.contains('church') || r.contains('internal affairs')) {
      _availableLevels = ['Location', 'Sub location', 'Dept', 'Team', 'Cell'];
    } else if (r.contains('loc') && !r.contains('sub_loc')) {
      _availableLevels = ['Sub location', 'Dept', 'Team', 'Cell'];
    } else if (r.contains('sub_loc')) {
      _availableLevels = ['Dept', 'Team', 'Cell'];
    } else if (r.contains('dept')) {
      _availableLevels = ['Team', 'Cell'];
    } else {
      _availableLevels = ['Cell'];
    }
    _selectedLevel = _availableLevels.first;
  }

  String _mapLevelToField(String level) {
    if (level == 'Location') return 'location';
    if (level == 'Sub location') return 'sub_location';
    if (level == 'Dept') return 'current_dept';
    if (level == 'Team') return 'team_number';
    return 'cell_number';
  }

  String _getParentField(String level) {
    if (level == 'Location') return 'church_name';
    if (level == 'Sub location') return 'location';
    if (level == 'Dept') return 'sub_location';
    if (level == 'Team') return 'current_dept';
    return 'team_number';
  }

  String _getParentValue(String level) {
    if (level == 'Location') return 'Church';
    if (level == 'Sub location') return widget.loc;
    if (level == 'Dept') return widget.sub;
    if (level == 'Team') return widget.dept;
    return widget.team;
  }

  String _mapDutyToTable(String d) {
    String duty = d.toLowerCase();
    if (duty.contains('attendance')) return 'logs_service_attendance_status';
    if (duty.contains('cell')) return 'logs_cell_service';
    if (duty.contains('offering')) return 'logs_offering';
    if (duty.contains('evangelism')) return 'logs_evangelism';
    if (duty.contains('morning light')) return 'logs_morning_light';
    if (duty.contains('all saints')) return 'logs_all_saints_education';
    if (duty.contains('visitation')) return 'logs_visitations';
    if (duty.contains('workers education')) return 'logs_workers_education';
    if (duty.contains('workers daily') || duty.contains('workers participation')) return 'logs_workers_participation';
    return 'logs_service_attendance_status';
  }

  Future<void> _loadRanking() async {
    setState(() => _isLoading = true);
    try {
      final rankings = await HierarchyComparisonLogic.getRankings(
        tableName: _mapDutyToTable(widget.duty),
        parentField: _getParentField(_selectedLevel),
        parentValue: _getParentValue(_selectedLevel),
        childField: _mapLevelToField(_selectedLevel),
      );
      if (mounted) setState(() => _data = rankings);
    } catch (e) {
      debugPrint("Leaderboard query error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Dynamic Headers for All 10 Duties ---
  List<String> _getHeaders() {
    final d = widget.duty.toLowerCase();
    if (d.contains('attendance')) {
      return ["Rank", "Unit Name", "Total Saints", "General Attendance", "In-person"];
    }
    if (d.contains('cell')) {
      return ["Rank", "Unit Name", "Total Saints", "General Attendance"];
    }
    if (d.contains('offering')) {
      return ["Rank", "Unit Name", "Total Saints", "Tithe", "Weekly Offering"];
    }
    if (d.contains('evangelism results')) {
      return ["Rank", "Unit Name", "Goal", "Confirmed", "Interview"];
    }
    if (d.contains('evangelism') || d.contains('morning light')) {
      return ["Rank", "Unit Name", "Total Saints", "Weekly Average Participation"];
    }
    if (d.contains('all saints')) {
      return ["Rank", "Unit Name", "Total Saints", "General Attendance"];
    }
    if (d.contains('visitation') || d.contains('counselling')) {
      return ["Rank", "Unit Name", "Total Saints", "Visited", "Positive", "Negative"];
    }
    if (d.contains('workers education')) {
      return ["Rank", "Unit Name", "Total Workers", "Sun %", "Wed % Attendance"];
    }
    if (d.contains('workers daily') || d.contains('workers participation')) {
      return ["Rank", "Unit Name", "Total Workers", "Mon %", "Tue %", "Thurs %", "Fri %"];
    }
    return ["Rank", "Unit Name", "Total Saints", "Success", "Score (%)"];
  }

  // --- Dynamic Value Resolver from DB Records ---
  List<Widget> _buildRowCells(int rank, Map<String, dynamic> item, double cellW) {
    final d = widget.duty.toLowerCase();
    final rankWidget = _cell(rank <= 3 ? (rank == 1 ? "🥇 1" : rank == 2 ? "🥈 2" : "🥉 3") : "#$rank", cellW * 0.7, b: true);
    final unitWidget = _cell(item['unit_name']?.toString() ?? "Unit", cellW * 1.3, a: Alignment.centerLeft, b: true);
    final total = "${item['total'] ?? item['total_saints'] ?? item['total_workers'] ?? 0}";

    if (d.contains('attendance')) {
      return [
        rankWidget,
        unitWidget,
        _cell(total, cellW),
        _cell("${item['general_attendance'] ?? item['success'] ?? 0}", cellW, color: Colors.blue.shade800),
        _cell("${item['in_person'] ?? item['score'] ?? 0}%", cellW, color: pPurple, b: true),
      ];
    }
    if (d.contains('cell') || d.contains('all saints')) {
      return [
        rankWidget,
        unitWidget,
        _cell(total, cellW),
        _cell("${item['general_attendance'] ?? item['success'] ?? 0}", cellW, color: Colors.green.shade800, b: true),
      ];
    }
    if (d.contains('offering')) {
      return [
        rankWidget,
        unitWidget,
        _cell(total, cellW),
        _cell("${item['tithe'] ?? item['success'] ?? 0}", cellW, color: Colors.indigo.shade800),
        _cell("${item['weekly_offering'] ?? item['score'] ?? 0}", cellW, color: Colors.green.shade800, b: true),
      ];
    }
    if (d.contains('evangelism results')) {
      return [
        rankWidget,
        unitWidget,
        _cell("${item['goal'] ?? 0}", cellW),
        _cell("${item['confirmed'] ?? item['success'] ?? 0}", cellW, color: Colors.green.shade800, b: true),
        _cell("${item['interview'] ?? item['score'] ?? 0}", cellW, color: Colors.blue.shade800),
      ];
    }
    if (d.contains('evangelism') || d.contains('morning light')) {
      return [
        rankWidget,
        unitWidget,
        _cell(total, cellW),
        _cell("${item['weekly_avg_part'] ?? item['score'] ?? 0}%", cellW, color: pPurple, b: true),
      ];
    }
    if (d.contains('visitation') || d.contains('counselling')) {
      return [
        rankWidget,
        unitWidget,
        _cell(total, cellW),
        _cell("${item['visited'] ?? item['success'] ?? 0}", cellW, color: Colors.blue.shade800),
        _cell("${item['positive'] ?? item['score'] ?? 0}", cellW, color: Colors.green.shade800, b: true),
        _cell("${item['negative'] ?? 0}", cellW, color: Colors.red.shade700),
      ];
    }
    if (d.contains('workers education')) {
      return [
        rankWidget,
        unitWidget,
        _cell(total, cellW),
        _cell("${item['sun_pct'] ?? item['score'] ?? 0}%", cellW, color: Colors.blue.shade800, b: true),
        _cell("${item['wed_pct'] ?? item['success'] ?? 0}%", cellW, color: Colors.teal.shade800),
      ];
    }
    if (d.contains('workers daily') || d.contains('workers participation')) {
      return [
        rankWidget,
        unitWidget,
        _cell(total, cellW),
        _cell("${item['mon_pct'] ?? item['score'] ?? 0}%", cellW, color: Colors.blue.shade800),
        _cell("${item['tue_pct'] ?? '-'}%", cellW),
        _cell("${item['thurs_pct'] ?? '-'}%", cellW),
        _cell("${item['fri_pct'] ?? '-'}%", cellW, color: Colors.green.shade800, b: true),
      ];
    }
    return [
      rankWidget,
      unitWidget,
      _cell(total, cellW),
      _cell("${item['success'] ?? 0}", cellW, color: Colors.green.shade800),
      _cell("${item['score'] ?? 0}%", cellW, b: true, color: pPurple),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSelectionDropdown(),
        const SizedBox(height: 12),
        _section(
          "Ranking Performance: $_selectedLevel",
          LayoutBuilder(builder: (context, constraints) {
            bool isWide = constraints.maxWidth > 750;
            return isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Table (58%)
                      Expanded(flex: 58, child: _buildRankingGrid(constraints.maxWidth * 0.58)),
                      // Spacing reduced to 25% (4px)
                      const SizedBox(width: 4),
                      // Right: Visualization Chart (42%)
                      Expanded(flex: 42, child: _buildChart()),
                    ],
                  )
                : Column(
                    children: [
                      _buildRankingGrid(constraints.maxWidth),
                      const SizedBox(height: 6), // 25% space on mobile
                      _buildChart(),
                    ],
                  );
          }),
        ),
      ],
    );
  }

  // --- Dropdown with Dark Border and Shadow ---
  Widget _buildSelectionDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppPalette.line(Colors.black), width: 1.0), // Dark border
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, size: 18, color: AppPalette.fg(pPurple)),
          const SizedBox(width: 10),
          Text(
            "Level to Compare:",
            style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _selectedLevel,
              isDense: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: _availableLevels.map((lvl) {
                return DropdownMenuItem(
                  value: lvl,
                  child: Text("Compare ${lvl}s", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedLevel = val);
                  _loadRanking();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingGrid(double maxWidth) {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()));
    }

    final headers = _getHeaders();
    double cellW = max(68.0, maxWidth / (headers.length + 0.3));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppPalette.line(Colors.black), width: 1.0), // Dark border
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: AppPalette.bg(const Color(0xFF1E293B)),
              child: Row(
                children: headers.asMap().entries.map((entry) {
                  int i = entry.key;
                  String h = entry.value;
                  double w = (i == 1) ? cellW * 1.3 : (i == 0) ? cellW * 0.7 : cellW;
                  return _cell(h, w, b: true, textColor: Colors.white, a: (i == 1) ? Alignment.centerLeft : Alignment.center);
                }).toList(),
              ),
            ),
            if (_data.isEmpty)
              Row(
                children: [
                  _cell("-", cellW * 0.7),
                  _cell("No ranking records found", cellW * 1.3, a: Alignment.centerLeft, textColor: Colors.grey),
                  ...List.generate(headers.length - 2, (_) => _cell("-", cellW)),
                ],
              )
            else
              ..._data.asMap().entries.map((entry) {
                return Row(children: _buildRowCells(entry.key + 1, entry.value, cellW));
              }),
          ],
        ),
      ),
    );
  }

  // --- Visualization Chart: Dark Border + Always-Visible Axes ---
  Widget _buildChart() {
    int displayLimit = min(5, _data.length);
    List<Map<String, dynamic>> topUnits = _data.isNotEmpty ? _data.sublist(0, displayLimit) : [];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.line(Colors.black), width: 1.0), // Dark border
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Performance Overview",
                style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppPalette.bg(_data.isNotEmpty ? Colors.green.shade50 : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _data.isNotEmpty ? "Top $displayLimit Units" : "No Data",
                  style: TextStyle(
                    fontSize: 10,
                    color: AppPalette.fg(_data.isNotEmpty ? Colors.green.shade800 : Colors.grey.shade700),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Chart with permanent axes and grid lines even when empty
          SizedBox(
            height: 170,
            child: Stack(
              children: [
                BarChart(
                  BarChartData(
                    maxY: 100,
                    minY: 0,
                    borderData: FlBorderData(
                      show: true,
                      border: Border(
                        bottom: BorderSide(color: AppPalette.line(Colors.black54), width: 1),
                        left: BorderSide(color: AppPalette.line(Colors.black54), width: 1),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (val) => FlLine(color: AppPalette.line(Colors.grey.shade200), strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: 25,
                          getTitlesWidget: (v, m) => Text(
                            "${v.toInt()}%",
                            style: TextStyle(fontSize: 8.5, color: AppPalette.fg(Colors.grey.shade700), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (val, meta) {
                            int i = val.toInt();
                            if (_data.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text("Unit ${i + 1}", style: TextStyle(fontSize: 8.5, color: AppPalette.fg(Colors.grey))),
                              );
                            }
                            if (i < 0 || i >= topUnits.length) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                topUnits[i]['unit_name']?.toString() ?? '',
                                style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    // If no data, show 0-height phantom bars so axes remain intact
                    barGroups: _data.isEmpty
                        ? List.generate(4, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: 0, color: Colors.transparent, width: 12)]))
                        : List.generate(topUnits.length, (i) {
                            num raw = (topUnits[i]['score'] as num?) ?? (topUnits[i]['success'] as num?) ?? 0;
                            double score = raw.toDouble();
                            return BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                toY: score > 100 ? 100 : (score < 0 ? 0 : score),
                                color: i == 0 ? Colors.amber.shade700 : (i == 1 ? Colors.blueGrey : pPurple),
                                width: 14,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ]);
                          }),
                  ),
                ),
                // Subtle overlay note when data is empty
                if (_data.isEmpty)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppPalette.bg(Colors.white.withValues(alpha: 0.9)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppPalette.line(Colors.grey.shade300)),
                      ),
                      child: Text(
                        "No ranking data currently",
                        style: TextStyle(fontSize: 10, color: AppPalette.fg(Colors.grey.shade700), fontStyle: FontStyle.italic),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String t, double w, {double h = 34, bool b = false, Color? color, Color? textColor, Alignment a = Alignment.center}) => Container(
    width: w,
    height: h,
    alignment: a,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(border: Border.all(color: AppPalette.line(Colors.grey.shade300), width: 0.5)),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 11,
        fontWeight: b ? FontWeight.bold : FontWeight.normal,
        color: AppPalette.fg(textColor ?? color ?? Colors.black87),
      ),
      overflow: TextOverflow.ellipsis,
    ),
  );

  // --- Master Section Card with Dark Border and Shadow ---
  Widget _section(String title, Widget content) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppPalette.line(Colors.black), width: 1.0), // Dark border
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4), // Matching shadow
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 14, color: AppPalette.fg(pPurple))),
          ),
          Divider(height: 1, color: AppPalette.bg(Colors.black12)),
          Padding(padding: const EdgeInsets.all(10), child: content),
        ],
      ),
    );
  }
}