// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

class UnitGrowthTrackerScreen extends StatefulWidget {
  final String userRole;
  final String userLoc;
  final String userSub;
  final String userDept;
  final String userTeam;
  final String userCell;

  const UnitGrowthTrackerScreen({
    super.key,
    required this.userRole,
    required this.userLoc,
    required this.userSub,
    required this.userDept,
    required this.userTeam,
    required this.userCell,
  });

  @override
  State<UnitGrowthTrackerScreen> createState() => _UnitGrowthTrackerScreenState();
}

class _UnitGrowthTrackerScreenState extends State<UnitGrowthTrackerScreen> {
  final _supabase = Supabase.instance.client;
  final Color pPurple = const Color(0xFF4A148C);

  final List<String> _periods = [
    'Weekly',
    'Monthly',
    'Quarterly',
    'Half-Yearly',
    'Yearly',
    'Custom'
  ];
  String _selectedPeriod = 'Monthly';
  DateTimeRange? _customDateRange;

  late List<String> _availableLevels;
  late String _selectedLevel;

  List<Map<String, dynamic>> _data = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupHierarchyLevels();
    _loadGrowthData();
  }

  void _setupHierarchyLevels() {
    String r = widget.userRole.toLowerCase();

    // 1. Church-wide / Executive / Admin: Can scale down to everything
    if (r == 'admin' ||
        r.contains('church') ||
        r.contains('korean_worker') ||
        r.contains('internal_affairs')) {
      _availableLevels = ['Location', 'Sub-Location', 'Department', 'Team', 'Cell'];
    }
    // 2. Location Leaders: Can scale down to Sub-loc, Dept, Team, Cell
    else if (r.contains('loc') && !r.contains('sub_loc')) {
      _availableLevels = ['Sub-Location', 'Department', 'Team', 'Cell'];
    }
    // 3. Sub-Location Leaders: Can scale down to Dept, Team, Cell
    else if (r.contains('sub_loc')) {
      _availableLevels = ['Department', 'Team', 'Cell'];
    }
    // 4. Department Leaders: Can scale down to Team, Cell
    else if (r.contains('dept')) {
      _availableLevels = ['Team', 'Cell'];
    }
    // 5. Team Leaders: Can scale down to Cell
    else if (r.contains('team')) {
      _availableLevels = ['Cell'];
    }
    // 6. Cell Leaders
    else {
      _availableLevels = ['Cell'];
    }

    _selectedLevel = _availableLevels.first;
  }

  String _getParentScopeName() {
    String r = widget.userRole.toLowerCase();
    if (r == 'admin' || r.contains('church') || r.contains('internal_affairs')) {
      return "Church Wide (All Locations)";
    }
    if (r.contains('loc') && !r.contains('sub_loc') && widget.userLoc.isNotEmpty) {
      return "Location: ${widget.userLoc}";
    }
    if (r.contains('sub_loc') && widget.userSub.isNotEmpty) {
      return "Sub-Location: ${widget.userSub}";
    }
    if (r.contains('dept') && widget.userDept.isNotEmpty) {
      return "Department: ${widget.userDept}";
    }
    if (r.contains('team') && widget.userTeam.isNotEmpty) {
      return "Team: ${widget.userTeam}";
    }
    return "All Units";
  }

  String _formatRoleName(String role) {
    return role.replaceAll('_', ' ').split(' ').map((w) {
      return w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  Future<void> _loadGrowthData() async {
    setState(() => _isLoading = true);
    try {
      String levelKey = _selectedLevel.toLowerCase().replaceAll('-', '_');
      String r = widget.userRole.toLowerCase();

      var query = _supabase.from('unit_growth').select().eq('unit_level', levelKey);

      // Lock down boundary: only filter child units under this leader
      if (r.contains('loc') && !r.contains('sub_loc') && widget.userLoc.isNotEmpty) {
        query = query.eq('parent_name', widget.userLoc);
      } else if (r.contains('sub_loc') && widget.userSub.isNotEmpty) {
        query = query.eq('parent_name', widget.userSub);
      } else if (r.contains('dept') && widget.userDept.isNotEmpty) {
        query = query.eq('parent_name', widget.userDept);
      } else if (r.contains('team') && widget.userTeam.isNotEmpty) {
        query = query.eq('parent_name', widget.userTeam);
      }

      final res = await query.order('net_growth_percentage', ascending: false);

      if (mounted) {
        setState(() {
          _data = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (e) {
      debugPrint("Error loading unit growth: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customDateRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
    );

    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedPeriod = 'Custom';
      });
      _loadGrowthData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFE),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF4A148C), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Unit Growth Tracking",
          style: GoogleFonts.merriweather(
            color: pPurple,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _buildScopeBadge(),
                  const SizedBox(height: 10),
                  _buildSideBySideDropdowns(),
                  const SizedBox(height: 14),
                  _buildRankingTableCard(),
                  const SizedBox(height: 16),
                  _buildChartCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildScopeBadge() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 16, color: pPurple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Role: ${_formatRoleName(widget.userRole)}  •  ${_getParentScopeName()}",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // --- Combined 50% Left (Level) and 50% Right (Period) Dropdowns ---
  Widget _buildSideBySideDropdowns() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Left 50%: Select Level to Compare
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _selectedLevel,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: "Level to Compare",
                labelStyle: TextStyle(fontSize: 11, color: pPurple, fontWeight: FontWeight.bold),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: _availableLevels.map((lvl) {
                return DropdownMenuItem(
                  value: lvl,
                  child: Text(
                    "Compare ${lvl}s",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedLevel = val);
                  _loadGrowthData();
                }
              },
            ),
          ),
          const SizedBox(width: 10),

          // Right 50%: Period Dropdown
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _selectedPeriod,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: "Period",
                labelStyle: TextStyle(fontSize: 11, color: pPurple, fontWeight: FontWeight.bold),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: _periods.map((p) {
                return DropdownMenuItem(
                  value: p,
                  child: Text(
                    p,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val == 'Custom') {
                  _pickCustomRange();
                } else if (val != null) {
                  setState(() => _selectedPeriod = val);
                  _loadGrowthData();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- Ranked Table with 75% Header Height, 50% Row Height, and Larger Fonts ---
  Widget _buildRankingTableCard() {
    List<String> headers = [
      "Rank",
      "Unit Name",
      "Total",
      "Active",
      "Attendance %",
      "New Converts",
      "Dropouts",
      "Net Growth %",
    ];

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                "Ranked Growth Leaderboard ($_selectedLevel)",
                style: GoogleFonts.merriweather(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: pPurple,
                ),
              ),
            ),
            LayoutBuilder(builder: (context, constraints) {
              double cellW = max(78.0, constraints.maxWidth / headers.length);

              return Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400, width: 0.8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      // Header height reduced to ~75% (34px)
                      headingRowHeight: 34,
                      // Data row height reduced to ~50% (28px)
                      dataRowMinHeight: 28,
                      dataRowMaxHeight: 32,
                      horizontalMargin: 6,
                      columnSpacing: 4,
                      border: TableBorder(
                        horizontalInside: BorderSide(color: Colors.grey.shade300, width: 0.8),
                        verticalInside: BorderSide(color: Colors.grey.shade300, width: 0.8),
                      ),
                      headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
                      columns: headers.map((h) => DataColumn(
                        label: SizedBox(
                          width: cellW,
                          child: Center(
                            child: Text(
                              h,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12, // Increased header font size
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      )).toList(),
                      rows: _data.isEmpty
                          ? [
                              DataRow(cells: [
                                _cell("-", cellW),
                                DataCell(
                                  SizedBox(
                                    width: cellW * 2,
                                    child: const Center(
                                      child: Text(
                                        "No records found for this unit/period",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                ...List.generate(headers.length - 2, (_) => _cell("-", cellW)),
                              ]),
                            ]
                          : _data.asMap().entries.map((entry) {
                              int rank = entry.key + 1;
                              var row = entry.value;

                              int total = (row['total_members'] as num?)?.toInt() ?? 0;
                              int active = (row['active_members'] as num?)?.toInt() ?? 0;
                              int converts = (row['new_converts'] as num?)?.toInt() ?? 0;
                              int dropouts = (row['dropouts'] as num?)?.toInt() ?? 0;
                              double netGrowth = (row['net_growth_percentage'] as num?)?.toDouble() ?? 0.0;
                              double attPct = total > 0 ? (active / total * 100) : 0.0;

                              return DataRow(
                                color: WidgetStateProperty.all(
                                  rank.isEven ? Colors.white : const Color(0xFFFBFBFE),
                                ),
                                cells: [
                                  _cell(rank <= 3 ? (rank == 1 ? "🥇 1" : rank == 2 ? "🥈 2" : "🥉 3") : "#$rank", cellW, isBold: true),
                                  _cell(row['unit_name']?.toString() ?? "-", cellW, isBold: true),
                                  _cell("$total", cellW),
                                  _cell("$active", cellW, color: Colors.blue.shade800),
                                  _cell("${attPct.toStringAsFixed(1)}%", cellW, color: Colors.indigo.shade800, isBold: true),
                                  _cell("$converts", cellW, color: Colors.green.shade800, isBold: true),
                                  _cell("$dropouts", cellW, color: Colors.red.shade700),
                                  _cell(
                                    "${netGrowth >= 0 ? '+' : ''}${netGrowth.toStringAsFixed(1)}%",
                                    cellW,
                                    color: netGrowth >= 0 ? Colors.green.shade800 : Colors.red,
                                    isBold: true,
                                  ),
                                ],
                              );
                            }).toList(),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard() {
    if (_data.isEmpty) return const SizedBox.shrink();

    int limit = min(7, _data.length);
    List<Map<String, dynamic>> topUnits = _data.sublist(0, limit);

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Active Attendance vs New Converts",
              style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: pPurple),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: BarChart(
                BarChartData(
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (val, meta) {
                          int i = val.toInt();
                          if (i < 0 || i >= topUnits.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              topUnits[i]['unit_name']?.toString() ?? '',
                              style: const TextStyle(fontSize: 9),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(topUnits.length, (i) {
                    double active = (topUnits[i]['active_members'] as num?)?.toDouble() ?? 0.0;
                    double converts = (topUnits[i]['new_converts'] as num?)?.toDouble() ?? 0.0;
                    return BarChartGroupData(x: i, barRods: [
                      BarChartRodData(toY: active, color: Colors.blue.shade700, width: 8),
                      BarChartRodData(toY: converts, color: Colors.green.shade700, width: 8),
                    ]);
                  }),
                ),
              ),
            ),
          ],
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
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12, // Increased content font size
            color: color ?? Colors.black87,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    ),
  );
}