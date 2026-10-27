// ignore_for_file: curly_braces_in_flow_control_structures, unused_element
import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/compilation_rules.dart';
import '../core/table_export.dart';
import '../core/compilation_style.dart';
import 'package:master_admin/core/app_palette.dart';

class _GrowthUnitStat {
  final String unitName;
  final int totalSaints;
  final int newEnrollment;
  final int graduation;
  final int transfer;

  _GrowthUnitStat({
    required this.unitName,
    required this.totalSaints,
    required this.newEnrollment,
    required this.graduation,
    required this.transfer,
  });

  int get netGrowth => newEnrollment - graduation;
  double get growthPct => totalSaints > 0 ? (netGrowth / totalSaints * 100.0) : 0.0;
  double get newPct => totalSaints > 0 ? (newEnrollment / totalSaints * 100.0) : 0.0;
  double get gradPct => totalSaints > 0 ? (graduation / totalSaints * 100.0) : 0.0;
}

class GrowthTrackingModule extends StatefulWidget {
  final List<dynamic> logs;
  final List<Map<String, dynamic>>? masterMembers;
  final String timePeriod;
  final String level;
  final String analyticsMode;
  final String groupBy;
  final double targetValue;

  final String selectedLocation;
  final String selectedSubLocation;
  final String selectedDepartment;
  final String selectedTeam;
  final String activeUnitLabel;

  final bool isChurchWide;
  final bool isLocationLeader;
  final bool isSubLocationLeader;
  final bool isDeptLeader;
  final bool isTeamLeader;
  final bool isGroupLeader;

  final String userRole;
  final String userDept;
  final String userSub;
  final String userLoc;
  final String userTeam;

  const GrowthTrackingModule({
    super.key,
    required this.logs,
    this.masterMembers,
    this.timePeriod = 'Quarterly status',
    required this.level,
    required this.analyticsMode,
    required this.groupBy,
    this.targetValue = 10.0,
    this.selectedLocation = '',
    this.selectedSubLocation = '',
    this.selectedDepartment = '',
    this.selectedTeam = '',
    this.activeUnitLabel = 'Unit name',
    this.isChurchWide = false,
    this.isLocationLeader = false,
    this.isSubLocationLeader = false,
    this.isDeptLeader = false,
    this.isTeamLeader = false,
    this.isGroupLeader = false,
    this.userRole = '',
    this.userDept = '',
    this.userSub = '',
    this.userLoc = '',
    this.userTeam = '', 
    required String category,
  });

  @override
  State<GrowthTrackingModule> createState() => _GrowthTrackingModuleState();
}

class _GrowthTrackingModuleState extends State<GrowthTrackingModule> {
  static const Color pPurple = Color(0xFF4A148C);

  String _selectedChartUnit = 'General total';

  // Headcount comes only from the screen's scoped member list. (The old
  // fallback loaded ALL church members when the scoped list was empty.)
  List<Map<String, dynamic>> get _effectiveMembers => widget.masterMembers ?? const [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant GrowthTrackingModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level ||
        oldWidget.selectedLocation != widget.selectedLocation ||
        oldWidget.selectedSubLocation != widget.selectedSubLocation ||
        oldWidget.selectedDepartment != widget.selectedDepartment ||
        oldWidget.selectedTeam != widget.selectedTeam ||
        oldWidget.groupBy != widget.groupBy) {
      _selectedChartUnit = 'General total';
    }
  }


  bool _matchesCascade(Map<String, dynamic> item) {
    Map<String, dynamic> m = {};
    if (item['members'] is Map) {
      m = Map<String, dynamic>.from(item['members']);
    }

    String loc = item['location']?.toString() ?? m['location']?.toString() ?? '';
    if (CompLevel.isMou(item)) loc = CompLevel.mou; // MOUWakiso etc. belong to the MOU location
    String sub = item['sub_location']?.toString() ?? m['sub_location']?.toString() ?? '';
    String dept = item['department']?.toString() ?? item['dept']?.toString() ?? m['department']?.toString() ?? '';
    String team = item['team']?.toString() ?? item['team_number']?.toString() ?? m['team']?.toString() ?? '';

    if (widget.selectedLocation.isNotEmpty &&
        widget.selectedLocation != 'All' &&
        widget.selectedLocation != 'Church Wide') {
      if (loc.isNotEmpty && loc.toLowerCase() != widget.selectedLocation.toLowerCase()) {
        return false;
      }
    }

    if (widget.selectedSubLocation.isNotEmpty &&
        widget.selectedSubLocation != 'All' &&
        widget.selectedSubLocation != 'Sub-location status') {
      if (sub.isNotEmpty && sub.toLowerCase() != widget.selectedSubLocation.toLowerCase()) {
        return false;
      }
    }

    if (widget.selectedDepartment.isNotEmpty &&
        widget.selectedDepartment != 'All' &&
        widget.selectedDepartment != 'Dept status') {
      if (dept.isNotEmpty && dept.toLowerCase() != widget.selectedDepartment.toLowerCase()) {
        return false;
      }
    }

    if (widget.selectedTeam.isNotEmpty &&
        widget.selectedTeam != 'All' &&
        widget.selectedTeam != 'Team status') {
      if (team.isNotEmpty && team.toLowerCase() != widget.selectedTeam.toLowerCase()) {
        return false;
      }
    }

    return true;
  }

  String _resolveLocationBucket(dynamic record) {
    String dept = (record['department'] ?? record['members']?['department'] ?? '').toString().trim().toUpperCase();
    if (dept.contains('MOU')) return 'MOU';

    String loc = (record['location'] ?? record['members']?['location'] ?? '').toString().trim();
    String locLower = loc.toLowerCase();

    if (locLower == '24dept' || locLower == '24부서' || locLower == 'church' || locLower == '교회') {
      return '24Dept';
    }
    return loc.isNotEmpty ? loc : 'Other';
  }

  // SOLVED: Next-tier resolution for growth
  // Same level rules as every other module (shared CompLevel); the old
  // contains('location status') check also caught "Sub location status".
  String _getUnitKey(Map<String, dynamic> item) => CompLevel.unitKey(item, widget.level);

  // SOLVED: Calculates Real Saints Growth From Live Members Registry
  List<_GrowthUnitStat> _calculateStats() {
    final cascadedMembers = _effectiveMembers.where((m) => _matchesCascade(m)).toList();

    final Map<String, List<Map<String, dynamic>>> unitMembers = {};
    for (var m in cascadedMembers) {
      final u = _getUnitKey(m);
      if (u != 'Unassigned') {
        unitMembers.putIfAbsent(u, () => []).add(m);
      }
    }

    final sortedUnits = unitMembers.keys.toList()..sort();
    List<_GrowthUnitStat> stats = [];

    for (var u in sortedUnits) {
      final uList = unitMembers[u]!;
      int saints = uList.length;

      int newEnc = uList.where((m) {
        final reg = (m['reg_status'] ?? '').toString();
        return reg == '입교' || (m['is_new_enrollment'] == true);
      }).length;

      int grad = uList.where((m) {
        final reg = (m['reg_status'] ?? '').toString();
        return reg == '총회등록' || (m['is_graduation'] == true);
      }).length;

      int trans = uList.where((m) => m['is_transfer'] == true).length;

      stats.add(_GrowthUnitStat(
        unitName: u,
        totalSaints: saints,
        newEnrollment: newEnc,
        graduation: grad,
        transfer: trans,
      ));
    }

    return stats;
  }

  _GrowthUnitStat _calculateTotalStat(List<_GrowthUnitStat> stats) {
    int totalSaints = 0;
    int newEnrollment = 0;
    int graduation = 0;
    int transfer = 0;

    for (var s in stats) {
      totalSaints += s.totalSaints;
      newEnrollment += s.newEnrollment;
      graduation += s.graduation;
      transfer += s.transfer;
    }

    return _GrowthUnitStat(
      unitName: 'General total',
      totalSaints: totalSaints,
      newEnrollment: newEnrollment,
      graduation: graduation,
      transfer: transfer,
    );
  }

  // --- UI: TABLE SUMMARY (7 Columns) ---
  Widget _buildGrowthTable(List<_GrowthUnitStat> stats, _GrowthUnitStat totalStat) {
    const double rh = 24.0;
    const double hh = 28.0;

    final Map<int, TableColumnWidth> colWidths = {
      0: const FixedColumnWidth(140),
      1: const FixedColumnWidth(80),
      2: const FixedColumnWidth(75),
      3: const FixedColumnWidth(75),
      4: const FixedColumnWidth(75),
      5: const FixedColumnWidth(85),
      6: const FixedColumnWidth(85),
    };

    List<String> headers = [
      widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : "Unit",
      "Total", "New", "Grads", "Trans", "Net Growth", "Growth %"
    ];

    if (stats.isEmpty && totalStat.totalSaints == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        child: Text("No records found for this unit", style: TextStyle(fontStyle: FontStyle.italic, color: AppPalette.fg(Colors.grey))),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: colWidths,
        border: TableBorder.all(color: Colors.black87, width: 1.0),
        children: [
          // Header Row
          TableRow(
            decoration: BoxDecoration(color: AppPalette.bg(CompStyle.headerBg)),
            children: headers.map((title) {
              return SizedBox(
                height: hh,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: Text(
                      title,
                      style: GoogleFonts.merriweather(
                        color: AppPalette.fg(CompStyle.headerFg),
                        fontSize: CompStyle.headerFont,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          // General Total Summary Row
          TableRow(
            decoration: BoxDecoration(color: AppPalette.bg(CompStyle.totalBg)),
            children: [
              _cellText("General total", 26.0, isBold: true, color: pPurple, align: TextAlign.left, padLeft: 6),
              _cellText("${totalStat.totalSaints}", 26.0, isBold: true),
              _cellText("${totalStat.newEnrollment}", 26.0, isBold: true, color: Colors.blue[800]!),
              _cellText("${totalStat.graduation}", 26.0, isBold: true, color: Colors.green[800]!),
              _cellText("${totalStat.transfer}", 26.0, isBold: true),
              _cellText(totalStat.netGrowth >= 0 ? "+${totalStat.netGrowth}" : "${totalStat.netGrowth}", 26.0,
                  isBold: true, color: totalStat.netGrowth >= 0 ? Colors.green[900]! : Colors.red[900]!),
              _cellPercent(totalStat.growthPct, 26.0, totalStat.netGrowth >= 0 ? Colors.green[900]! : Colors.red[900]!,
                  isBold: true, showSign: true),
            ],
          ),

          // Data Rows
          // A single unit row would just repeat the General total
          if (stats.length > 1) ...stats.asMap().entries.map((entry) {
            int idx = entry.key;
            _GrowthUnitStat u = entry.value;
            final isEven = idx.isEven;
            final rowColor = isEven ? Colors.white : const Color(0xFFF8FAFC);
            final isPositive = u.netGrowth >= 0;
            final growthColor = isPositive ? Colors.green[800]! : Colors.red[800]!;

            return TableRow(
              decoration: BoxDecoration(color: AppPalette.bg(rowColor)),
              children: [
                _cellText(u.unitName, rh, isBold: true, align: TextAlign.left, padLeft: 6),
                _cellText("${u.totalSaints}", rh),
                _cellText("${u.newEnrollment}", rh, color: Colors.blue[700]!, isBold: true),
                _cellText("${u.graduation}", rh, color: Colors.green[700]!, isBold: true),
                _cellText("${u.transfer}", rh),
                _cellText(isPositive ? "+${u.netGrowth}" : "${u.netGrowth}", rh, color: growthColor, isBold: true),
                _cellPercent(u.growthPct, rh, growthColor, isBold: true, showSign: true),
              ],
            );
          }),
        ],
      ),
    );
  }

  // --- UI: DYNAMIC UNIT SELECTOR PILLS ---
  Widget _buildUnitPillBar(List<_GrowthUnitStat> stats) {
    final List<String> units = ['General total', ...stats.map((s) => s.unitName)];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: units.map((u) {
            final isSelected = _selectedChartUnit == u;
            return Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: ChoiceChip(
                label: Text(
                  u,
                  style: GoogleFonts.merriweather(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: AppPalette.fg(isSelected ? Colors.white : Colors.black87),
                  ),
                ),
                selected: isSelected,
                selectedColor: AppPalette.bg(pPurple),
                backgroundColor: AppPalette.bg(const Color(0xFFF1F5F9)),
                visualDensity: VisualDensity.compact,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedChartUnit = u);
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // --- UI: DYNAMIC GROWTH CHART ---
  Widget _buildGrowthChart(List<_GrowthUnitStat> stats, _GrowthUnitStat totalStat) {
    if (stats.isEmpty && totalStat.totalSaints == 0) {
      return const SizedBox(height: 100, child: Center(child: Text("No data available to chart")));
    }

    List<_GrowthUnitStat> displayUnits = [];
    if (_selectedChartUnit == 'General total') {
      displayUnits = stats.take(8).toList();
    } else {
      displayUnits = [stats.firstWhere((s) => s.unitName == _selectedChartUnit, orElse: () => totalStat)];
    }

    int maxCount = 0;
    for (var u in displayUnits) {
      maxCount = math.max(maxCount, math.max(u.newEnrollment, u.graduation));
    }
    double maxY = maxCount > 0 ? (maxCount * 1.3).ceilToDouble() : 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stats.isNotEmpty) _buildUnitPillBar(stats),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(
                "Displaying: $_selectedChartUnit",
                style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[800])), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Row(
                children: [
                  _legItem("New Enrollment", Colors.blue[700]!),
                  const SizedBox(width: 12),
                  _legItem("Graduation", Colors.green[700]!),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          height: 300,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: math.max(1.0, (maxY / 5).ceilToDouble()),
                getDrawingHorizontalLine: (val) => FlLine(
                  color: AppPalette.line(Colors.grey.withValues(alpha: 0.18)),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  bottom: BorderSide(color: AppPalette.line(Colors.black45), width: 1),
                  left: BorderSide(color: AppPalette.line(Colors.black45), width: 1),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, m) => Text(
                      "${v.toInt()}",
                      style: GoogleFonts.merriweather(fontSize: 9, color: AppPalette.fg(Colors.blueGrey)),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (v, m) {
                      int idx = v.toInt();
                      if (idx < 0 || idx >= displayUnits.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          displayUnits[idx].unitName,
                          style: GoogleFonts.merriweather(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[800])),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final unit = displayUnits[group.x.toInt()];
                    final type = rodIndex == 0 ? "New Enrollment" : "Graduation";
                    final count = rod.toY.toInt();
                    return BarTooltipItem(
                      "${unit.unitName}\n$type: $count",
                      TextStyle(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold, fontSize: 11),
                    );
                  },
                ),
              ),
              barGroups: List.generate(displayUnits.length, (i) {
                final u = displayUnits[i];
                return BarChartGroupData(
                  x: i,
                  barsSpace: 6,
                  barRods: [
                    BarChartRodData(
                      toY: u.newEnrollment.toDouble(),
                      color: Colors.blue[700]!,
                      width: 14,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    BarChartRodData(
                      toY: u.graduation.toDouble(),
                      color: Colors.green[700]!,
                      width: 14,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  // --- UI: RANKING LIST ---
  Widget _buildRankingList(List<_GrowthUnitStat> stats, bool isTop) {
    if (stats.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text("No ranking data found", style: TextStyle(color: AppPalette.fg(Colors.grey))),
        ),
      );
    }

    final sorted = List<_GrowthUnitStat>.from(stats);
    sorted.sort((a, b) => isTop ? b.growthPct.compareTo(a.growthPct) : a.growthPct.compareTo(b.growthPct));
    final displayList = sorted.take(5).toList();

    return Column(
      children: displayList.asMap().entries.map((entry) {
        int rank = entry.key + 1;
        _GrowthUnitStat item = entry.value;
        final color = isTop ? Colors.green[700]! : Colors.red[700]!;

        return ListTile(
          dense: true,
          leading: CircleAvatar(
            backgroundColor: AppPalette.bg(isTop ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12)),
            radius: 16,
            child: Text(
              "#$rank",
              style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: AppPalette.fg(color)),
            ),
          ),
          title: Text(
            item.unitName,
            style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          subtitle: Text(
            "Saints: ${item.totalSaints} | New: +${item.newEnrollment} | Grads: -${item.graduation}",
            style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.blueGrey)),
          ),
          trailing: Text(
            item.growthPct >= 0 ? "+${item.growthPct.toStringAsFixed(1)}%" : "${item.growthPct.toStringAsFixed(1)}%",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(color)),
          ),
        );
      }).toList(),
    );
  }

  // --- PDF REPORT EXPORT ---
  // Excel / PDF / Print for the summary table (same rows as the old PDF)
  ExportTable _exportTable(List<_GrowthUnitStat> stats, _GrowthUnitStat totalStat) => ExportTable(
        title: "Growth Tracking – ${widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : widget.level}",
        subtitle: 'Level: ${widget.level} | Group By: ${widget.groupBy} | Period: ${widget.timePeriod}'
              '${widget.selectedLocation.isNotEmpty ? ' | Loc: ${widget.selectedLocation}' : ''}'
              '${widget.selectedSubLocation.isNotEmpty ? ' | Sub: ${widget.selectedSubLocation}' : ''}'
              '${widget.selectedDepartment.isNotEmpty ? ' | Dept: ${widget.selectedDepartment}' : ''}'
              '${widget.selectedTeam.isNotEmpty ? ' | Team: ${widget.selectedTeam}' : ''}',
        headers: <String>[
                widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : 'Unit',
                'Total Saints',
                'New Enrollment',
                'Graduation',
                'Transfer',
                'Net Growth',
                'Growth %',
              ],
        rows: <List<String>>[
                ...stats.map((u) => [
                      u.unitName,
                      '${u.totalSaints}',
                      '${u.newEnrollment}',
                      '${u.graduation}',
                      '${u.transfer}',
                      u.netGrowth >= 0 ? '+${u.netGrowth}' : '${u.netGrowth}',
                      '${u.growthPct.toStringAsFixed(1)}%',
                    ]),
                [
                  'General Total',
                  '${totalStat.totalSaints}',
                  '${totalStat.newEnrollment}',
                  '${totalStat.graduation}',
                  '${totalStat.transfer}',
                  totalStat.netGrowth >= 0 ? '+${totalStat.netGrowth}' : '${totalStat.netGrowth}',
                  '${totalStat.growthPct.toStringAsFixed(1)}%',
                ],
              ],
      );

  Future<void> _exportPdf(List<_GrowthUnitStat> stats, _GrowthUnitStat totalStat) =>
      TableExport.showMenu(context, () => _exportTable(stats, totalStat));

  // --- HELPERS ---
  Widget _cellText(String text, double height, {
    Color? color,
    bool isBold = false,
    TextAlign align = TextAlign.center,
    double padLeft = 0,
  }) {
    return SizedBox(
      height: height,
      child: Container(
        alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.center,
        padding: EdgeInsets.only(left: padLeft, right: 2),
        child: Text(
          text,
          style: GoogleFonts.merriweather(
            fontSize: 9.5,
            color: AppPalette.fg(color ?? Colors.black87),
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        ),
      ),
    );
  }

  Widget _cellPercent(double pct, double height, Color color, {bool isBold = false, bool showSign = false}) {
    final sign = showSign && pct > 0 ? "+" : "";
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          "$sign${pct.toStringAsFixed(1)}%",
          style: GoogleFonts.merriweather(
            fontSize: 9.0,
            color: AppPalette.fg(color),
            fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _legItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: AppPalette.bg(color), shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.merriweather(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[800])),
        ),
      ],
    );
  }

  Widget _section(String title, Widget content, BuildContext context, {VoidCallback? onPdf}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.line(Colors.black), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppPalette.line(Colors.black12), width: 1.0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.merriweather(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: AppPalette.fg(pPurple),
                    ),
                  ),
                ),
                if (onPdf != null)
                  IconButton(
                    icon: Icon(Icons.download_rounded, size: 20, color: AppPalette.fg(pPurple)),
                    tooltip: tr('Excel / PDF / Print'),
                    onPressed: onPdf,
                  ),
                IconButton(
                  icon: Icon(Icons.open_in_full_rounded, size: 19, color: AppPalette.fg(Colors.blueGrey)),
                  tooltip: tr('Fullscreen View'),
                  onPressed: () => _showFull(context, title, content),
                ),
              ],
            ),
          ),
          content,
        ],
      ),
    );
  }

  void _showFull(BuildContext ctx, String title, Widget content) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
          appBar: AppBar(
            backgroundColor: AppPalette.bg(pPurple),
            foregroundColor: AppPalette.fg(Colors.white),
            title: Text(title, style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.bold)),
            centerTitle: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: content,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<_GrowthUnitStat> unitStats = _calculateStats();
    final _GrowthUnitStat totalStat = _calculateTotalStat(unitStats);

    return Column(
      children: [
        if (widget.analyticsMode == 'Ranking') ...[
          _section(
            "Top growing units",
            _buildRankingList(unitStats, true),
            context,
          ),
          _section(
            "Units requiring growth support",
            _buildRankingList(unitStats, false),
            context,
          ),
        ] else ...[
          _section(
            "Unit growth metrics summary",
            _buildGrowthTable(unitStats, totalStat),
            context,
            onPdf: () => _exportPdf(unitStats, totalStat),
          ),
          const SizedBox(height: 10),
          _section(
            "Enrollment vs graduation breakdown",
            _buildGrowthChart(unitStats, totalStat),
            context,
          ),
        ],
      ],
    );
  }
}