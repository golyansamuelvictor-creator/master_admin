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

class _EvangelismResultUnitStat {
  final String unitName;
  final int chakki;
  final int possible;
  final int newBb;
  final int proceeding;
  final int confirmed;
  final int offline;
  final int online;

  _EvangelismResultUnitStat({
    required this.unitName,
    required this.chakki,
    required this.possible,
    required this.newBb,
    required this.proceeding,
    required this.confirmed,
    required this.offline,
    required this.online,
  });

  int get total => chakki + possible + newBb + proceeding + confirmed;
}

class EvangelismResultsModule extends StatefulWidget {
  final List<dynamic> bbData;
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

  const EvangelismResultsModule({
    super.key,
    required this.bbData,
    this.logs = const [],
    this.masterMembers,
    this.timePeriod = 'Weekly status',
    this.level = 'Cell',
    this.analyticsMode = 'Summary',
    this.groupBy = 'Cell',
    this.targetValue = 80.0,
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
  });

  @override
  State<EvangelismResultsModule> createState() => _EvangelismResultsModuleState();
}

class _EvangelismResultsModuleState extends State<EvangelismResultsModule> {
  static const Color pPurple = Color(0xFF4A148C);
  String _selectedChartUnit = 'General total';

  @override
  void didUpdateWidget(covariant EvangelismResultsModule oldWidget) {
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
    String dept = item['department']?.toString() ?? item['current_dept']?.toString() ?? item['dept']?.toString() ?? m['department']?.toString() ?? m['current_dept']?.toString() ?? m['dept']?.toString() ?? '';
    String team = item['team']?.toString() ?? item['team_number']?.toString() ?? m['team']?.toString() ?? m['team_number']?.toString() ?? '';

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
    String dept = (record['department'] ?? record['current_dept'] ?? record['dept'] ?? '').toString().trim().toUpperCase();
    if (dept.contains('MOU')) return 'MOU';

    String loc = (record['location'] ?? record['loc'] ?? '').toString().trim();
    String locLower = loc.toLowerCase();

    if (locLower == '24dept' || locLower == '24부서' || locLower == 'church' || locLower == '교회') {
      return '24Dept';
    }
    return loc.isNotEmpty ? loc : 'Other';
  }

  // SOLVED: Next-tier resolution for bb_students
  // Same level rules as every other module (shared CompLevel); the old
  // contains('location status') check also caught "Sub location status".
  String _getUnitKey(Map<String, dynamic> item) => CompLevel.unitKey(item, widget.level);

  bool _isOffline(dynamic method) {
    if (method == null) return false;
    final s = method.toString().trim().toLowerCase();
    return s == 'inperson' || s == 'offline' || s == 'in person' || s == 'in-person' || s == 'off-line';
  }

  bool _isOnline(dynamic method) {
    if (method == null) return false;
    final s = method.toString().trim().toLowerCase();
    return s == 'online' || s == 'on-line';
  }

  bool _statusMatch(dynamic levelStatus, String targetKey) {
    if (levelStatus == null) return false;
    final s = levelStatus.toString().trim().toLowerCase();
    final t = targetKey.trim().toLowerCase();
    if (s == t) return true;
    if (t == 'new bb' && (s == 'new bb' || s == 'newbb' || s == 'new')) return true;
    return s.contains(t);
  }

  List<dynamic> _getFilteredBbData() {
    return widget.bbData.where((d) {
      if (d is! Map) return false;
      return _matchesCascade(Map<String, dynamic>.from(d));
    }).toList();
  }

  List<_EvangelismResultUnitStat> _calculateUnitStats(List<dynamic> filteredData) {
    final Map<String, List<dynamic>> map = {};
    for (var d in filteredData) {
      final u = _getUnitKey(Map<String, dynamic>.from(d));
      if (u != 'Unassigned') {
        map.putIfAbsent(u, () => []).add(d);
      }
    }

    final sortedUnits = map.keys.toList()..sort();
    List<_EvangelismResultUnitStat> stats = [];

    for (var u in sortedUnits) {
      final items = map[u]!;
      int chakki = items.where((d) => _statusMatch(d['level_status'], 'Chakki')).length;
      int possible = items.where((d) => _statusMatch(d['level_status'], 'Possible')).length;
      int newBb = items.where((d) => _statusMatch(d['level_status'], 'New Bb')).length;
      int proceeding = items.where((d) => _statusMatch(d['level_status'], 'Proceeding')).length;
      int confirmed = items.where((d) => _statusMatch(d['level_status'], 'Confirmed')).length;
      int offline = items.where((d) => _isOffline(d['method'])).length;
      int online = items.where((d) => _isOnline(d['method'])).length;

      stats.add(_EvangelismResultUnitStat(
        unitName: u,
        chakki: chakki,
        possible: possible,
        newBb: newBb,
        proceeding: proceeding,
        confirmed: confirmed,
        offline: offline,
        online: online,
      ));
    }

    return stats;
  }

  _EvangelismResultUnitStat _calculateTotalStat(List<_EvangelismResultUnitStat> stats) {
    int chakki = 0;
    int possible = 0;
    int newBb = 0;
    int proceeding = 0;
    int confirmed = 0;
    int offline = 0;
    int online = 0;

    for (var s in stats) {
      chakki += s.chakki;
      possible += s.possible;
      newBb += s.newBb;
      proceeding += s.proceeding;
      confirmed += s.confirmed;
      offline += s.offline;
      online += s.online;
    }

    return _EvangelismResultUnitStat(
      unitName: 'General total',
      chakki: chakki,
      possible: possible,
      newBb: newBb,
      proceeding: proceeding,
      confirmed: confirmed,
      offline: offline,
      online: online,
    );
  }

  // --- UI: STATUS CARDS ---
  Widget _buildResultCards(List<dynamic> filteredData) {
    return Column(
      children: [
        _resultCard("Chakki", "Chakki", pPurple, Colors.orange, filteredData),
        _resultCard("Possible", "Possible", pPurple, Colors.blue, filteredData),
        _resultCard("New Bb", "New Bb", pPurple, Colors.teal, filteredData),
        _resultCard("Proceeding", "Proceeding", pPurple, Colors.indigo, filteredData),
        _resultCard("Confirmed", "Confirmed", pPurple, Colors.green, filteredData),
      ],
    );
  }

  Widget _resultCard(String title, String statusKey, Color purple, Color accent, List<dynamic> data) {
    final group = data.where((d) => _statusMatch(d['level_status'], statusKey)).toList();
    final overall = group.length;
    final offline = group.where((d) => _isOffline(d['method'])).length;
    final online = group.where((d) => _isOnline(d['method'])).length;

    String format(int val) => val.toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.line(Colors.black), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: AppPalette.bg(accent),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  bottomLeft: Radius.circular(7),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(
                          title,
                          style: GoogleFonts.merriweather(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: AppPalette.fg(purple),
                          ), maxLines: 2, overflow: TextOverflow.ellipsis)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppPalette.bg(accent.withValues(alpha: 0.12)),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppPalette.line(accent.withValues(alpha: 0.5)), width: 0.5),
                          ),
                          child: Text(
                            "$overall Total",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(accent)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _row("Overall total", "${format(overall)} / 00 / 00 / 00"),
                    const SizedBox(height: 4),
                    _row("Total offline", "${format(offline)} / 00 / 00 / 00"),
                    const SizedBox(height: 4),
                    _row("Total online", "${format(online)} / 00 / 00 / 00"),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(child: Text(
        label,
        style: GoogleFonts.merriweather(
          fontSize: 11,
          color: AppPalette.fg(Colors.blueGrey[700]),
          fontWeight: FontWeight.w500,
        ), maxLines: 2, overflow: TextOverflow.ellipsis)),
      Text(
        value,
        style: GoogleFonts.merriweather(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppPalette.fg(Colors.black87),
          letterSpacing: 1.2,
        ),
      ),
    ],
  );

  // --- UI: TABLE SUMMARY (9 Columns) ---
  Widget _buildTableSummary(List<_EvangelismResultUnitStat> stats, _EvangelismResultUnitStat totalStat) {
    const double rh = 24.0;
    const double hh = 28.0;

    final Map<int, TableColumnWidth> colWidths = {
      0: const FixedColumnWidth(130),
      1: const FixedColumnWidth(65),
      2: const FixedColumnWidth(65),
      3: const FixedColumnWidth(65),
      4: const FixedColumnWidth(65),
      5: const FixedColumnWidth(75),
      6: const FixedColumnWidth(75),
      7: const FixedColumnWidth(65),
      8: const FixedColumnWidth(65),
    };

    List<String> headers = [
      widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : "Unit name",
      "Total", "Chakki", "Possible", "New Bb", "Proceeding", "Confirmed", "Offline", "Online"
    ];

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
              _cellText("${totalStat.total}", 26.0, isBold: true, color: pPurple),
              _cellText("${totalStat.chakki}", 26.0, isBold: true),
              _cellText("${totalStat.possible}", 26.0, isBold: true),
              _cellText("${totalStat.newBb}", 26.0, isBold: true),
              _cellText("${totalStat.proceeding}", 26.0, isBold: true),
              _cellText("${totalStat.confirmed}", 26.0, isBold: true, color: Colors.green[900]!),
              _cellText("${totalStat.offline}", 26.0, isBold: true),
              _cellText("${totalStat.online}", 26.0, isBold: true),
            ],
          ),

          // Data Rows
          // A single unit row would just repeat the General total
          if (stats.length > 1) ...stats.asMap().entries.map((entry) {
            int idx = entry.key;
            _EvangelismResultUnitStat u = entry.value;
            final isEven = idx.isEven;
            final rowColor = isEven ? Colors.white : const Color(0xFFF8FAFC);

            return TableRow(
              decoration: BoxDecoration(color: AppPalette.bg(rowColor)),
              children: [
                _cellText(u.unitName, rh, isBold: true, align: TextAlign.left, padLeft: 6),
                _cellText("${u.total}", rh, isBold: true, color: pPurple),
                _cellText("${u.chakki}", rh),
                _cellText("${u.possible}", rh),
                _cellText("${u.newBb}", rh),
                _cellText("${u.proceeding}", rh),
                _cellText("${u.confirmed}", rh, color: Colors.green[800]!, isBold: true),
                _cellText("${u.offline}", rh),
                _cellText("${u.online}", rh),
              ],
            );
          }),
        ],
      ),
    );
  }

  // --- UI: DYNAMIC UNIT SELECTOR PILLS ---
  Widget _buildUnitPillBar(List<_EvangelismResultUnitStat> stats) {
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

  // --- UI: DYNAMIC STAGE BREAKDOWN CHART ---
  Widget _buildStageChart(List<_EvangelismResultUnitStat> stats, _EvangelismResultUnitStat totalStat) {
    if (stats.isEmpty && totalStat.total == 0) {
      return const SizedBox(height: 100, child: Center(child: Text("No evangelism results records")));
    }

    _EvangelismResultUnitStat active = totalStat;
    if (_selectedChartUnit != 'General total') {
      active = stats.firstWhere((s) => s.unitName == _selectedChartUnit, orElse: () => totalStat);
    }

    final List<int> values = [
      active.chakki,
      active.possible,
      active.newBb,
      active.proceeding,
      active.confirmed,
    ];

    const List<String> labels = ["Chakki", "Possible", "New Bb", "Proceeding", "Confirmed"];
    final List<Color> colors = [Colors.orange, Colors.blue, Colors.teal, Colors.indigo, Colors.green];

    int maxVal = values.reduce(math.max);
    double maxY = maxVal > 0 ? (maxVal * 1.25).ceilToDouble() : 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUnitPillBar(stats),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(
                "Displaying: ${active.unitName} (${active.total} Total Fruits)",
                style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[800])), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Text(
                "Offline: ${active.offline} | Online: ${active.online}",
                style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
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
                    getTitlesWidget: (val, meta) => Text(
                      "${val.toInt()}",
                      style: GoogleFonts.merriweather(fontSize: 9, color: AppPalette.fg(Colors.blueGrey)),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (val, meta) {
                      int idx = val.toInt();
                      if (idx < 0 || idx >= labels.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          labels[idx],
                          style: GoogleFonts.merriweather(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[800])),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final label = labels[group.x.toInt()];
                    final count = rod.toY.toInt();
                    return BarTooltipItem(
                      "$label: $count",
                      TextStyle(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold, fontSize: 11),
                    );
                  },
                ),
              ),
              barGroups: List.generate(5, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: values[i].toDouble(),
                      color: colors[i],
                      width: 26,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
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
  Widget _buildRankingList(List<_EvangelismResultUnitStat> stats, bool isTop) {
    if (stats.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text("No ranking data found", style: TextStyle(color: AppPalette.fg(Colors.grey))),
        ),
      );
    }

    final sorted = List<_EvangelismResultUnitStat>.from(stats);
    sorted.sort((a, b) => isTop ? b.total.compareTo(a.total) : a.total.compareTo(b.total));
    final displayList = sorted.take(5).toList();

    return Column(
      children: displayList.asMap().entries.map((entry) {
        int rank = entry.key + 1;
        _EvangelismResultUnitStat item = entry.value;
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
            "Confirmed: ${item.confirmed} | Offline: ${item.offline} | Online: ${item.online}",
            style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.blueGrey)),
          ),
          trailing: Text(
            "${item.total} Total",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(color)),
          ),
        );
      }).toList(),
    );
  }

  // --- PDF REPORT EXPORT ---
  // Excel / PDF / Print for the summary table (same rows as the old PDF)
  ExportTable _exportTable(List<_EvangelismResultUnitStat> stats, _EvangelismResultUnitStat totalStat) => ExportTable(
        title: "Evangelism Results – ${widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : widget.level}",
        subtitle: 'Level: ${widget.level} | Group By: ${widget.groupBy} | Period: ${widget.timePeriod}'
              '${widget.selectedLocation.isNotEmpty ? ' | Loc: ${widget.selectedLocation}' : ''}'
              '${widget.selectedSubLocation.isNotEmpty ? ' | Sub: ${widget.selectedSubLocation}' : ''}'
              '${widget.selectedDepartment.isNotEmpty ? ' | Dept: ${widget.selectedDepartment}' : ''}'
              '${widget.selectedTeam.isNotEmpty ? ' | Team: ${widget.selectedTeam}' : ''}',
        headers: <String>[
                widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : 'Unit',
                'Total',
                'Chakki',
                'Possible',
                'New Bb',
                'Proceeding',
                'Confirmed',
                'Offline',
                'Online',
              ],
        rows: <List<String>>[
                [
                  'General Total',
                  '${totalStat.total}',
                  '${totalStat.chakki}',
                  '${totalStat.possible}',
                  '${totalStat.newBb}',
                  '${totalStat.proceeding}',
                  '${totalStat.confirmed}',
                  '${totalStat.offline}',
                  '${totalStat.online}',
                ],
                ...stats.map((u) => [
                      u.unitName,
                      '${u.total}',
                      '${u.chakki}',
                      '${u.possible}',
                      '${u.newBb}',
                      '${u.proceeding}',
                      '${u.confirmed}',
                      '${u.offline}',
                      '${u.online}',
                    ]),
              ],
      );

  Future<void> _exportPdf(List<_EvangelismResultUnitStat> stats, _EvangelismResultUnitStat totalStat) =>
      TableExport.showMenu(context, () => _exportTable(stats, totalStat));

  // --- CELL HELPERS ---
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

  // --- SECTION CONTAINER WITH DARK BORDER ---
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
    final filteredData = _getFilteredBbData();
    final List<_EvangelismResultUnitStat> unitStats = _calculateUnitStats(filteredData);
    final _EvangelismResultUnitStat totalStat = _calculateTotalStat(unitStats);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.analyticsMode == 'Ranking') ...[
          _section(
            "Top performing evangelism result units",
            _buildRankingList(unitStats, true),
            context,
          ),
          _section(
            "Units requiring evangelism follow-up support",
            _buildRankingList(unitStats, false),
            context,
          ),
        ] else ...[
          _section(
            "Evangelism results stage cards",
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildResultCards(filteredData),
            ),
            context,
          ),
          _section(
            "Evangelism results summary table",
            _buildTableSummary(unitStats, totalStat),
            context,
            onPdf: () => _exportPdf(unitStats, totalStat),
          ),
          const SizedBox(height: 10),
          _section(
            "Evangelism results stage breakdown",
            _buildStageChart(unitStats, totalStat),
            context,
          ),
        ],
      ],
    );
  }
}