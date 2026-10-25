// ignore_for_file: curly_braces_in_flow_control_structures, unused_element
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../core/compilation_rules.dart';

class _EvangelismUnitStat {
  final String unitName;
  final int totalSaints;
  final int mon;
  final int tue;
  final int wed;
  final int thu;
  final int fri;
  final int sat;
  final int sun;

  _EvangelismUnitStat({
    required this.unitName,
    required this.totalSaints,
    required this.mon,
    required this.tue,
    required this.wed,
    required this.thu,
    required this.fri,
    required this.sat,
    required this.sun,
  });

  double get weeklyAvg => (mon + tue + wed + thu + fri + sat + sun) / 7.0;
  double get weeklyAvgPct => totalSaints > 0 ? (weeklyAvg / totalSaints * 100.0) : 0.0;
  double get monPct => totalSaints > 0 ? (mon / totalSaints * 100.0) : 0.0;
  double get tuePct => totalSaints > 0 ? (tue / totalSaints * 100.0) : 0.0;
  double get wedPct => totalSaints > 0 ? (wed / totalSaints * 100.0) : 0.0;
  double get thuPct => totalSaints > 0 ? (thu / totalSaints * 100.0) : 0.0;
  double get friPct => totalSaints > 0 ? (fri / totalSaints * 100.0) : 0.0;
  double get satPct => totalSaints > 0 ? (sat / totalSaints * 100.0) : 0.0;
  double get sunPct => totalSaints > 0 ? (sun / totalSaints * 100.0) : 0.0;
}

class EvangelismModule extends StatefulWidget {
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

  const EvangelismModule({
    super.key,
    required this.logs,
    this.masterMembers,
    required this.timePeriod,
    required this.level,
    required this.analyticsMode,
    required this.groupBy,
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
  State<EvangelismModule> createState() => _EvangelismModuleState();
}

class _EvangelismModuleState extends State<EvangelismModule> {
  static const Color pPurple = Color(0xFF4A148C);

  String _selectedChartUnit = 'General total';

  // Headcount comes only from the screen's scoped member list. (The old
  // fallback loaded ALL church members when the scoped list was empty.)
  List<Map<String, dynamic>> get _effectiveMembers => widget.masterMembers ?? const [];

  int get _sessions => widget.timePeriod == "Current status" ? 1 : CompPeriod.sessionCount(widget.logs);

  bool get _is24ChurchDept {
    final r = widget.userRole.toLowerCase();
    final d = widget.userDept.toLowerCase();
    return (r.contains('_dept_') || r.startsWith('ia_') || d.contains('내무')) &&
        !widget.isLocationLeader &&
        !widget.isSubLocationLeader &&
        !widget.isDeptLeader &&
        !widget.isTeamLeader &&
        !widget.isGroupLeader;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant EvangelismModule oldWidget) {
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
    String dept = item['department']?.toString() ?? m['department']?.toString() ?? '';
    String team = item['team']?.toString() ?? m['team']?.toString() ?? '';

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
        widget.selectedDepartment != 'Dept status' &&
        !_is24ChurchDept) {
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

  // SOLVED: Next-Tier Unit Resolution
  // Same level rules as every other module (shared CompLevel); the old
  // contains('location status') check also caught "Sub location status".
  String _getUnitKey(Map<String, dynamic> item) => CompLevel.unitKey(item, widget.level);

  // contains('evang') used to count "Did Not Evangelize" as evangelised
  bool _isEvangelised(dynamic val) => CompStatus.isPositive(val);

  bool _isDayEvangelised(dynamic log, String dayCode, String legacyField) {
    final evangDay = (log['evang_day'] ?? '').toString().trim().toLowerCase();
    if (evangDay.isNotEmpty) {
      if (evangDay == dayCode.toLowerCase() || evangDay.startsWith(dayCode.toLowerCase())) {
        return _isEvangelised(log['status_detail']);
      }
      return false;
    }
    return _isEvangelised(log[legacyField]) || _isEvangelised(log['status_detail']);
  }

  // SOLVED: Next-tier decomposition (Never returns empty list on Church view)
  List<_EvangelismUnitStat> _calculateStats() {
    final cascadedLogs = widget.logs.where((l) {
      if (l is! Map) return false;
      return _matchesCascade(Map<String, dynamic>.from(l));
    }).toList();

    final cascadedMembers = _effectiveMembers.where((m) => _matchesCascade(m)).toList();

    final Map<String, int> unitSaintsCount = {};
    for (var m in cascadedMembers) {
      final u = _getUnitKey(m);
      if (u != 'Unassigned') {
        unitSaintsCount[u] = (unitSaintsCount[u] ?? 0) + 1;
      }
    }

    final Map<String, List<dynamic>> unitLogs = {};
    for (var l in cascadedLogs) {
      final u = _getUnitKey(Map<String, dynamic>.from(l));
      if (u != 'Unassigned') {
        unitLogs.putIfAbsent(u, () => []).add(l);
      }
    }

    final Set<String> allUnits = {...unitSaintsCount.keys, ...unitLogs.keys};
    final sortedUnits = allUnits.toList()..sort((a, b) => a.compareTo(b));

    List<_EvangelismUnitStat> stats = [];

    for (var u in sortedUnits) {
      final uLogs = unitLogs[u] ?? [];
      int saints = unitSaintsCount[u] ?? 0;

      if (saints == 0) {
        final distinctIds = <dynamic>{};
        for (var l in uLogs) {
          final mid = l['member_id'] ?? l['members']?['id'] ?? l['id'];
          if (mid != null) distinctIds.add(mid);
        }
        saints = distinctIds.isNotEmpty ? distinctIds.length : uLogs.length;
      }

      // Per-week averages over the period (one week for "Current status")
      final int sessions = _sessions;
      int per(int v) => CompPeriod.perSession(v, sessions);
      int mon = per(uLogs.where((l) => _isDayEvangelised(l, 'Mon', 'mon_part')).length);
      int tue = per(uLogs.where((l) => _isDayEvangelised(l, 'Tue', 'tue_part')).length);
      int wed = per(uLogs.where((l) => _isDayEvangelised(l, 'Wed', 'wed_part')).length);
      int thu = per(uLogs.where((l) => _isDayEvangelised(l, 'Thu', 'thu_part')).length);
      int fri = per(uLogs.where((l) => _isDayEvangelised(l, 'Fri', 'fri_part')).length);
      int sat = per(uLogs.where((l) => _isDayEvangelised(l, 'Sat', 'sat_part')).length);
      int sun = per(uLogs.where((l) => _isDayEvangelised(l, 'Sun', 'sun_part')).length);

      int maxDay = math.max(mon, math.max(tue, math.max(wed, math.max(thu, math.max(fri, math.max(sat, sun))))));
      saints = math.max(saints, maxDay);

      stats.add(_EvangelismUnitStat(
        unitName: u,
        totalSaints: saints,
        mon: mon,
        tue: tue,
        wed: wed,
        thu: thu,
        fri: fri,
        sat: sat,
        sun: sun,
      ));
    }

    return stats;
  }

  _EvangelismUnitStat _calculateTotalStat(List<dynamic> allLogs, List<Map<String, dynamic>> allMembers) {
    int totalSaints = allMembers.isNotEmpty ? allMembers.length : 0;

    final int sessions = _sessions;
    int per(int v) => CompPeriod.perSession(v, sessions);
    int mon = per(allLogs.where((l) => _isDayEvangelised(l, 'Mon', 'mon_part')).length);
    int tue = per(allLogs.where((l) => _isDayEvangelised(l, 'Tue', 'tue_part')).length);
    int wed = per(allLogs.where((l) => _isDayEvangelised(l, 'Wed', 'wed_part')).length);
    int thu = per(allLogs.where((l) => _isDayEvangelised(l, 'Thu', 'thu_part')).length);
    int fri = per(allLogs.where((l) => _isDayEvangelised(l, 'Fri', 'fri_part')).length);
    int sat = per(allLogs.where((l) => _isDayEvangelised(l, 'Sat', 'sat_part')).length);
    int sun = per(allLogs.where((l) => _isDayEvangelised(l, 'Sun', 'sun_part')).length);

    int maxDay = math.max(mon, math.max(tue, math.max(wed, math.max(thu, math.max(fri, math.max(sat, sun))))));
    totalSaints = math.max(totalSaints, maxDay);

    return _EvangelismUnitStat(
      unitName: 'General total',
      totalSaints: totalSaints,
      mon: mon,
      tue: tue,
      wed: wed,
      thu: thu,
      fri: fri,
      sat: sat,
      sun: sun,
    );
  }

  // --- UI: TABLE SUMMARY (17 Columns) ---
  // Centres the table when it is narrower than the screen; scrolls sideways when wider.
  Widget _centeredScroll({required Widget child}) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth.isFinite ? constraints.maxWidth : 0),
            child: Center(child: child),
          ),
        ),
      );

  Widget _buildEvangelismTable(List<_EvangelismUnitStat> stats, _EvangelismUnitStat totalStat) {
    const double rh = 24.0;
    const double hh = 28.0;

    final Map<int, TableColumnWidth> colWidths = {
      0: const FixedColumnWidth(125),
      1: const FixedColumnWidth(60),
      2: const FixedColumnWidth(68),
      3: const FixedColumnWidth(50),
      4: const FixedColumnWidth(48),
      5: const FixedColumnWidth(50),
      6: const FixedColumnWidth(48),
      7: const FixedColumnWidth(50),
      8: const FixedColumnWidth(48),
      9: const FixedColumnWidth(50),
      10: const FixedColumnWidth(48),
      11: const FixedColumnWidth(50),
      12: const FixedColumnWidth(48),
      13: const FixedColumnWidth(50),
      14: const FixedColumnWidth(48),
      15: const FixedColumnWidth(50),
      16: const FixedColumnWidth(48),
    };

    List<String> headers = [
      widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : "Unit name",
      "Saints", "Weekly avg",
      "Mon", "Mon %", "Tue", "Tue %", "Wed", "Wed %",
      "Thu", "Thu %", "Fri", "Fri %", "Sat", "Sat %", "Sun", "Sun %"
    ];

    return _centeredScroll(
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: colWidths,
        border: TableBorder.all(color: Colors.black, width: 1.0),
        children: [
          // Header Row
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF3E5F5)),
            children: headers.map((title) {
              return SizedBox(
                height: hh,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: Text(
                      title,
                      style: GoogleFonts.merriweather(
                        color: pPurple,
                        fontSize: 9.0,
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
            decoration: const BoxDecoration(color: Color(0xFFEDE7F6)),
            children: [
              _cellText("General total", 26.0, isBold: true, color: pPurple),
              _cellText("${totalStat.totalSaints}", 26.0, isBold: true),
              _cellText(totalStat.weeklyAvg.toStringAsFixed(1), 26.0, isBold: true, color: pPurple),
              _cellText("${totalStat.mon}", 26.0, isBold: true),
              _cellPercent(totalStat.monPct, 26.0, pPurple, isBold: true),
              _cellText("${totalStat.tue}", 26.0, isBold: true),
              _cellPercent(totalStat.tuePct, 26.0, pPurple, isBold: true),
              _cellText("${totalStat.wed}", 26.0, isBold: true),
              _cellPercent(totalStat.wedPct, 26.0, pPurple, isBold: true),
              _cellText("${totalStat.thu}", 26.0, isBold: true),
              _cellPercent(totalStat.thuPct, 26.0, pPurple, isBold: true),
              _cellText("${totalStat.fri}", 26.0, isBold: true),
              _cellPercent(totalStat.friPct, 26.0, pPurple, isBold: true),
              _cellText("${totalStat.sat}", 26.0, isBold: true),
              _cellPercent(totalStat.satPct, 26.0, Colors.blue[900]!, isBold: true),
              _cellText("${totalStat.sun}", 26.0, isBold: true),
              _cellPercent(totalStat.sunPct, 26.0, Colors.blue[900]!, isBold: true),
            ],
          ),

          // Child Data Rows
          // A single unit row would just repeat the General total
          if (stats.length > 1) ...stats.asMap().entries.map((entry) {
            int idx = entry.key;
            _EvangelismUnitStat u = entry.value;
            final isEven = idx.isEven;
            final rowColor = isEven ? Colors.white : const Color(0xFFF8FAFC);

            return TableRow(
              decoration: BoxDecoration(color: rowColor),
              children: [
                _cellText(u.unitName, rh, isBold: true),
                _cellText("${u.totalSaints}", rh),
                _cellText(u.weeklyAvg.toStringAsFixed(1), rh, color: pPurple, isBold: true),
                _cellText("${u.mon}", rh),
                _cellPercent(u.monPct, rh, pPurple),
                _cellText("${u.tue}", rh),
                _cellPercent(u.tuePct, rh, pPurple),
                _cellText("${u.wed}", rh),
                _cellPercent(u.wedPct, rh, pPurple),
                _cellText("${u.thu}", rh),
                _cellPercent(u.thuPct, rh, pPurple),
                _cellText("${u.fri}", rh),
                _cellPercent(u.friPct, rh, pPurple),
                _cellText("${u.sat}", rh),
                _cellPercent(u.satPct, rh, Colors.blue[800]!),
                _cellText("${u.sun}", rh),
                _cellPercent(u.sunPct, rh, Colors.blue[800]!),
              ],
            );
          }),
        ],
      ),
    );
  }

  // --- UI: RANKING LIST ---
  Widget _buildRankingList(List<_EvangelismUnitStat> stats, bool isTop) {
    if (stats.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text("No ranking data found", style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final sorted = List<_EvangelismUnitStat>.from(stats);
    sorted.sort((a, b) => isTop ? b.weeklyAvgPct.compareTo(a.weeklyAvgPct) : a.weeklyAvgPct.compareTo(b.weeklyAvgPct));
    final displayList = sorted.take(5).toList();

    return Column(
      children: displayList.asMap().entries.map((entry) {
        int rank = entry.key + 1;
        _EvangelismUnitStat item = entry.value;
        final color = isTop ? Colors.green[700]! : Colors.red[700]!;

        return ListTile(
          dense: true,
          leading: CircleAvatar(
            backgroundColor: isTop ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12),
            radius: 16,
            child: Text(
              "#$rank",
              style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          title: Row(
            children: [
              Icon(isTop ? Icons.trending_up_rounded : Icons.priority_high_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(item.unitName, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          subtitle: Text(
            "Saints: ${item.totalSaints} | Wkly Avg: ${item.weeklyAvg.toStringAsFixed(1)}",
            style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
          trailing: Text(
            "${item.weeklyAvgPct.toStringAsFixed(1)}%",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: color),
          ),
        );
      }).toList(),
    );
  }

  // --- UI: DYNAMIC UNIT SELECTOR PILLS ---
  Widget _buildUnitPillBar(List<_EvangelismUnitStat> stats) {
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
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
                selected: isSelected,
                selectedColor: pPurple,
                backgroundColor: const Color(0xFFF1F5F9),
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

  // --- UI: DYNAMIC 7-DAY BREAKDOWN CHART ---
  Widget _buildEvangelismChart(List<_EvangelismUnitStat> stats, _EvangelismUnitStat totalStat) {
    _EvangelismUnitStat active = totalStat;
    if (_selectedChartUnit != 'General total') {
      active = stats.firstWhere((s) => s.unitName == _selectedChartUnit, orElse: () => totalStat);
    }

    final List<double> percentages = [
      active.monPct,
      active.tuePct,
      active.wedPct,
      active.thuPct,
      active.friPct,
      active.satPct,
      active.sunPct,
    ];

    final List<int> counts = [
      active.mon,
      active.tue,
      active.wed,
      active.thu,
      active.fri,
      active.sat,
      active.sun,
    ];

    const List<String> days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stats.isNotEmpty) _buildUnitPillBar(stats),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Displaying: ${active.unitName} (${active.totalSaints} Saints)",
                style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.redAccent, width: 0.5),
                ),
                child: Text(
                  "Target: ${widget.targetValue.toInt()}%",
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          height: 320,
          child: BarChart(
            BarChartData(
              maxY: 100,
              minY: 0,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 20,
                getDrawingHorizontalLine: (val) => FlLine(
                  color: Colors.grey.withValues(alpha: 0.18),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: const Border(
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                  left: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: widget.targetValue,
                    color: Colors.redAccent,
                    strokeWidth: 1.5,
                    dashArray: [5, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      labelResolver: (_) => '${widget.targetValue.toInt()}% Target',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 20,
                    getTitlesWidget: (val, meta) => Text(
                      "${val.toInt()}%",
                      style: GoogleFonts.merriweather(fontSize: 9, color: Colors.blueGrey),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (val, meta) {
                      int idx = val.toInt();
                      if (idx < 0 || idx >= days.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          days[idx],
                          style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final day = days[group.x.toInt()];
                    final count = counts[group.x.toInt()];
                    final pct = rod.toY.toStringAsFixed(1);
                    return BarTooltipItem(
                      "$day\n$count Evangelised ($pct%)",
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    );
                  },
                ),
              ),
              barGroups: List.generate(7, (i) {
                final pct = percentages[i];
                final isAboveTarget = pct >= widget.targetValue;
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: pct,
                      color: isAboveTarget ? pPurple : const Color(0xFF7E57C2),
                      width: 22,
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

  // --- PDF REPORT EXPORT ---
  Future<void> _exportPdf(List<_EvangelismUnitStat> stats, _EvangelismUnitStat totalStat) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.merriweatherRegular();
    final fontBold = await PdfGoogleFonts.merriweatherBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Evangelism Daily Participation Report (All Saints)',
                      style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.purple900)),
                  pw.Text(
                    'Generated: ${DateTime.now().toLocal().toString().split(' ')[0]}',
                    style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Level: ${widget.level} | Group By: ${widget.groupBy} | Period: ${widget.timePeriod}'
              '${widget.selectedLocation.isNotEmpty ? ' | Loc: ${widget.selectedLocation}' : ''}'
              '${widget.selectedSubLocation.isNotEmpty ? ' | Sub: ${widget.selectedSubLocation}' : ''}'
              '${widget.selectedDepartment.isNotEmpty ? ' | Dept: ${widget.selectedDepartment}' : ''}'
              '${widget.selectedTeam.isNotEmpty ? ' | Team: ${widget.selectedTeam}' : ''}',
              style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: [
                widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : 'Unit',
                'Saints',
                'Wkly Avg',
                'Mon',
                'Mon %',
                'Tue',
                'Tue %',
                'Wed',
                'Wed %',
                'Thu',
                'Thu %',
                'Fri',
                'Fri %',
                'Sat',
                'Sat %',
                'Sun',
                'Sun %',
              ],
              data: [
                [
                  'General Total',
                  '${totalStat.totalSaints}',
                  totalStat.weeklyAvg.toStringAsFixed(1),
                  '${totalStat.mon}',
                  '${totalStat.monPct.toStringAsFixed(0)}%',
                  '${totalStat.tue}',
                  '${totalStat.tuePct.toStringAsFixed(0)}%',
                  '${totalStat.wed}',
                  '${totalStat.wedPct.toStringAsFixed(0)}%',
                  '${totalStat.thu}',
                  '${totalStat.thuPct.toStringAsFixed(0)}%',
                  '${totalStat.fri}',
                  '${totalStat.friPct.toStringAsFixed(0)}%',
                  '${totalStat.sat}',
                  '${totalStat.satPct.toStringAsFixed(0)}%',
                  '${totalStat.sun}',
                  '${totalStat.sunPct.toStringAsFixed(0)}%',
                ],
                ...stats.map((u) => [
                      u.unitName,
                      '${u.totalSaints}',
                      u.weeklyAvg.toStringAsFixed(1),
                      '${u.mon}',
                      '${u.monPct.toStringAsFixed(0)}%',
                      '${u.tue}',
                      '${u.tuePct.toStringAsFixed(0)}%',
                      '${u.wed}',
                      '${u.wedPct.toStringAsFixed(0)}%',
                      '${u.thu}',
                      '${u.thuPct.toStringAsFixed(0)}%',
                      '${u.fri}',
                      '${u.friPct.toStringAsFixed(0)}%',
                      '${u.sat}',
                      '${u.satPct.toStringAsFixed(0)}%',
                      '${u.sun}',
                      '${u.sunPct.toStringAsFixed(0)}%',
                    ]),
              ],
              headerStyle: pw.TextStyle(font: fontBold, fontSize: 7.0, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.purple900),
              cellStyle: pw.TextStyle(font: font, fontSize: 7.0),
              cellAlignment: pw.Alignment.center,
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
              rowDecoration: const pw.BoxDecoration(),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

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
            color: color ?? Colors.black87,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        ),
      ),
    );
  }

  Widget _cellPercent(double pct, double height, Color color, {bool isBold = false}) {
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          "${pct.toStringAsFixed(0)}%",
          style: GoogleFonts.merriweather(
            fontSize: 9.0,
            color: color,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // --- SECTION CONTAINER WITH DARK BORDER ---
  Widget _section(String title, Widget content, BuildContext context, {VoidCallback? onPdf}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 1.0),
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
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.black12, width: 1.0)),
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
                      color: pPurple,
                    ),
                  ),
                ),
                if (onPdf != null)
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 20, color: pPurple),
                    tooltip: 'Export PDF Report',
                    onPressed: onPdf,
                  ),
                IconButton(
                  icon: const Icon(Icons.open_in_full_rounded, size: 19, color: Colors.blueGrey),
                  tooltip: 'Fullscreen View',
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
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: pPurple,
            foregroundColor: Colors.white,
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
    final List<_EvangelismUnitStat> unitStats = _calculateStats();
    final cascadedMembers = _effectiveMembers.where((m) => _matchesCascade(m)).toList();
    final cascadedLogs = widget.logs.where((l) {
      if (l is! Map) return false;
      return _matchesCascade(Map<String, dynamic>.from(l));
    }).toList();

    final _EvangelismUnitStat totalStat = _calculateTotalStat(cascadedLogs, cascadedMembers);

    return Column(
      children: [
        if (widget.analyticsMode == 'Ranking') ...[
          _section(
            "Top performing evangelism units",
            _buildRankingList(unitStats, true),
            context,
          ),
          _section(
            "Units requiring evangelism support",
            _buildRankingList(unitStats, false),
            context,
          ),
        ] else ...[
          _section(
            "Evangelism daily summary",
            _buildEvangelismTable(unitStats, totalStat),
            context,
            onPdf: () => _exportPdf(unitStats, totalStat),
          ),
          const SizedBox(height: 10),
          _section(
            "7-day breakdown (%)",
            _buildEvangelismChart(unitStats, totalStat),
            context,
          ),
        ],
      ],
    );
  }
}