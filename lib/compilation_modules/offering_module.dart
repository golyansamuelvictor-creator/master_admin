// ignore_for_file: curly_braces_in_flow_control_structures, unused_element
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import '../core/compilation_rules.dart';
import '../core/table_export.dart';
import '../core/compilation_style.dart';
import 'package:master_admin/core/app_palette.dart';

class _OfferingUnitStat {
  final String unitName;
  final int totalSaints;
  final num givers;
  final num tithe;
  final num weekly;
  final num thanks;
  final num construction;
  final num donation;

  _OfferingUnitStat({
    required this.unitName,
    required this.totalSaints,
    required this.givers,
    required this.tithe,
    required this.weekly,
    required this.thanks,
    required this.construction,
    required this.donation,
  });

  double get giversPct => totalSaints > 0 ? (givers / totalSaints * 100.0) : 0.0;
  double get tithePct => totalSaints > 0 ? (tithe / totalSaints * 100.0) : 0.0;
  double get weeklyPct => totalSaints > 0 ? (weekly / totalSaints * 100.0) : 0.0;
  double get thanksPct => totalSaints > 0 ? (thanks / totalSaints * 100.0) : 0.0;
  double get constructionPct => totalSaints > 0 ? (construction / totalSaints * 100.0) : 0.0;
  double get donationPct => totalSaints > 0 ? (donation / totalSaints * 100.0) : 0.0;
}

class OfferingModule extends StatefulWidget {
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

  const OfferingModule({
    super.key,
    required this.logs,
    this.masterMembers,
    required this.timePeriod,
    required this.level,
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
  State<OfferingModule> createState() => _OfferingModuleState();
}

class _OfferingModuleState extends State<OfferingModule> {
  static const Color pPurple = Color(0xFF4A148C);

  String _selectedChartUnit = 'General total';

  // Headcount comes only from the screen's scoped member list. (The old
  // fallback loaded ALL church members when the scoped list was empty.)
  List<Map<String, dynamic>> get _effectiveMembers => widget.masterMembers ?? const [];

  int get _sessions => widget.timePeriod == "Current status" ? 1 : CompPeriod.sessionCount(widget.logs);

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant OfferingModule oldWidget) {
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

  // SOLVED: Accurate Unit Mapping
  // Same level rules as every other module (shared CompLevel); the old
  // contains('location status') check also caught "Sub location status".
  String _getUnitKey(Map<String, dynamic> item) => CompLevel.unitKey(item, widget.level);

  // An amount greater than 0 or any "yes"-type answer counts as given
  // (amounts such as "5000" used to count as not paid).
  bool _isPaid(dynamic val) {
    final s = CompStatus.norm(val);
    if (s.isEmpty) return false;
    final num? amount = num.tryParse(s.replaceAll(',', '').replaceAll(' ', ''));
    if (amount != null) return amount > 0;
    return CompStatus.isPositive(s);
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    try {
      return DateTime.parse(val.toString());
    } catch (_) {
      return null;
    }
  }

  // SOLVED: Next-Tier Decomposition (Never suppresses to null)
  List<_OfferingUnitStat> _calculateStats() {
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

    List<_OfferingUnitStat> stats = [];

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

      // Per-week averages over the weeks THIS unit reported in (one week for "Current status")
      final int sessions = widget.timePeriod == "Current status" ? 1 : CompPeriod.sessionCount(uLogs);
      num per(int v) => CompPeriod.avgPerSession(v, sessions);
      num t = per(uLogs.where((l) => _isPaid(l['offering_tithe'])).length);
      num w = per(uLogs.where((l) => _isPaid(l['offering_weekly'])).length);
      num th = per(uLogs.where((l) => _isPaid(l['offering_thanks'])).length);
      num c = per(uLogs.where((l) => _isPaid(l['offering_construction'])).length);
      num d = per(uLogs.where((l) => _isPaid(l['offering_donation'])).length);

      num givers = per(uLogs.where((l) =>
        _isPaid(l['offering_tithe']) ||
        _isPaid(l['offering_weekly']) ||
        _isPaid(l['offering_thanks']) ||
        _isPaid(l['offering_construction']) ||
        _isPaid(l['offering_donation'])
      ).length);

      saints = math.max(saints, math.max(givers, math.max(t, math.max(w, math.max(th, math.max(c, d))))).ceil());

      stats.add(_OfferingUnitStat(
        unitName: u,
        totalSaints: saints,
        givers: givers,
        tithe: t,
        weekly: w,
        thanks: th,
        construction: c,
        donation: d,
      ));
    }

    return stats;
  }

  _OfferingUnitStat _calculateTotalStat(List<_OfferingUnitStat> stats) {
    int totalSaints = 0;
    num givers = 0;
    num tithe = 0;
    num weekly = 0;
    num thanks = 0;
    num construction = 0;
    num donation = 0;

    for (var s in stats) {
      totalSaints += s.totalSaints;
      givers += s.givers;
      tithe += s.tithe;
      weekly += s.weekly;
      thanks += s.thanks;
      construction += s.construction;
      donation += s.donation;
    }

    return _OfferingUnitStat(
      unitName: 'General total',
      totalSaints: totalSaints,
      givers: givers,
      tithe: tithe,
      weekly: weekly,
      thanks: thanks,
      construction: construction,
      donation: donation,
    );
  }

  // --- UI: TABLE SUMMARY (13 Columns) ---
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

  // Fills the card width, keeping about 1 cm free on each side (columns grow
  // in proportion); on narrow screens the table scrolls sideways instead.
  Widget _fitTable(Map<int, double> widths, Widget Function(Map<int, TableColumnWidth> cols) build) => LayoutBuilder(
        builder: (context, constraints) {
          final double natural = widths.values.fold<double>(0, (a, b) => a + b);
          final double avail = constraints.maxWidth.isFinite ? constraints.maxWidth - 2 * CompStyle.tableSideMargin : natural;
          final double scale = avail > natural ? avail / natural : 1.0;
          final Map<int, TableColumnWidth> cols = widths.map((k, v) => MapEntry(k, FixedColumnWidth(v * scale)));
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: scale > 1.0 ? CompStyle.tableSideMargin : 0),
              child: build(cols),
            ),
          );
        },
      );

  Widget _buildOfferingTable(List<_OfferingUnitStat> stats, _OfferingUnitStat totalStat) {
    const double rh = 24.0;
    const double hh = 28.0;

    final Map<int, double> colWidths = {
      0: 130,
      1: 65,
      2: 65,
      3: 55,
      4: 50,
      5: 55,
      6: 50,
      7: 55,
      8: 50,
      9: 55,
      10: 50,
      11: 55,
      12: 50,
    };

    List<String> headers = [
      widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : "Unit name",
      "Saints", "Givers", "Tithe", "%", "Wkly", "%", "Thks", "%", "Const", "%", "Donat", "%"
    ];

    return _fitTable(colWidths, (cols) => Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: cols,
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
              _cellText("General total", 26.0, isBold: true, color: pPurple),
              _cellText("${totalStat.totalSaints}", 26.0, isBold: true),
              _cellText(CompPeriod.fmt(totalStat.givers), 26.0, isBold: true, color: pPurple),
              _cellText(CompPeriod.fmt(totalStat.tithe), 26.0, isBold: true),
              _cellPercent(totalStat.tithePct, 26.0, pPurple, isBold: true),
              _cellText(CompPeriod.fmt(totalStat.weekly), 26.0, isBold: true),
              _cellPercent(totalStat.weeklyPct, 26.0, Colors.blue[900]!, isBold: true),
              _cellText(CompPeriod.fmt(totalStat.thanks), 26.0, isBold: true),
              _cellPercent(totalStat.thanksPct, 26.0, Colors.orange[900]!, isBold: true),
              _cellText(CompPeriod.fmt(totalStat.construction), 26.0, isBold: true),
              _cellPercent(totalStat.constructionPct, 26.0, Colors.teal[900]!, isBold: true),
              _cellText(CompPeriod.fmt(totalStat.donation), 26.0, isBold: true),
              _cellPercent(totalStat.donationPct, 26.0, Colors.indigo[900]!, isBold: true),
            ],
          ),

          // Data Rows
          // A single unit row would just repeat the General total
          if (stats.length > 1) ...stats.asMap().entries.map((entry) {
            int idx = entry.key;
            _OfferingUnitStat u = entry.value;
            final isEven = idx.isEven;
            final rowColor = isEven ? Colors.white : const Color(0xFFF8FAFC);

            return TableRow(
              decoration: BoxDecoration(color: AppPalette.bg(rowColor)),
              children: [
                _cellText(u.unitName, rh, isBold: true),
                _cellText("${u.totalSaints}", rh),
                _cellText(CompPeriod.fmt(u.givers), rh, color: pPurple, isBold: true),
                _cellText(CompPeriod.fmt(u.tithe), rh),
                _cellPercent(u.tithePct, rh, pPurple),
                _cellText(CompPeriod.fmt(u.weekly), rh),
                _cellPercent(u.weeklyPct, rh, Colors.blue[800]!),
                _cellText(CompPeriod.fmt(u.thanks), rh),
                _cellPercent(u.thanksPct, rh, Colors.orange[900]!),
                _cellText(CompPeriod.fmt(u.construction), rh),
                _cellPercent(u.constructionPct, rh, Colors.teal[800]!),
                _cellText(CompPeriod.fmt(u.donation), rh),
                _cellPercent(u.donationPct, rh, Colors.indigo[800]!),
              ],
            );
          }),
        ],
      ),
    );
  }

  // --- UI: DYNAMIC UNIT SELECTOR PILLS ---
  Widget _buildUnitPillBar(List<_OfferingUnitStat> stats) {
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

  // --- UI: DYNAMIC TREND CHART (Week 1–5 or Month 1–4) ---
  Widget _buildTrendChart(List<_OfferingUnitStat> stats) {
    final cascadedLogs = widget.logs.where((l) {
      if (l is! Map) return false;
      return _matchesCascade(Map<String, dynamic>.from(l));
    }).toList();

    final filteredLogs = _selectedChartUnit == 'General total'
        ? cascadedLogs
        : cascadedLogs.where((l) => _getUnitKey(Map<String, dynamic>.from(l)) == _selectedChartUnit).toList();

    Map<DateTime, List<dynamic>> timeMap = {};
    for (var log in filteredLogs) {
      // One point per week (Weekly) or month (Monthly), else per date
      final key = DateTime.tryParse(CompPeriod.bucketKey(log, widget.timePeriod));
      if (key != null) {
        timeMap.putIfAbsent(key, () => []).add(log);
      }
    }

    // Weekly = Week 1..Week 5, Monthly = the 4 months, even if one has no reports
    final expected = CompPeriod.expectedBuckets(widget.timePeriod);
    if (expected != null && timeMap.isNotEmpty) {
      for (final k in expected) {
        timeMap.putIfAbsent(DateTime.parse(k), () => []);
      }
    }
    var sortedDates = timeMap.keys.toList()..sort();
    if (sortedDates.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUnitPillBar(stats),
          const SizedBox(height: 120, child: Center(child: Text("No offering date records found for trend chart"))),
        ],
      );
    }

    List<String> periodLabels = [];
    if (widget.timePeriod == "Weekly status") {
      periodLabels = List.generate(sortedDates.length, (i) {
        return "Week ${i + 1}\n(${DateFormat('MM/dd').format(sortedDates[i])})";
      });
    } else if (widget.timePeriod == "Monthly status") {
      periodLabels = List.generate(sortedDates.length, (i) {
        return DateFormat('MMM').format(sortedDates[i]);
      });
    } else {
      periodLabels = sortedDates.map((d) => DateFormat('MM/dd').format(d)).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUnitPillBar(stats),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(
                "Displaying: $_selectedChartUnit",
                style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[800])), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  _legItem("Tithe", pPurple),
                  _legItem("Weekly", Colors.blue),
                  _legItem("Thanks", Colors.orange),
                  _legItem("Const", Colors.teal),
                  _legItem("Donat", Colors.indigo),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          height: 320,
          child: LineChart(
            LineChartData(
              maxY: 100,
              minY: 0,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 20,
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
                    reservedSize: 34,
                    interval: 20,
                    getTitlesWidget: (v, m) => Text(
                      "${v.toInt()}%",
                      style: GoogleFonts.merriweather(fontSize: 9, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey)),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 32,
                    getTitlesWidget: (v, m) {
                      int idx = v.toInt();
                      if (idx < 0 || idx >= periodLabels.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          periodLabels[idx],
                          textAlign: TextAlign.center,
                          style: GoogleFonts.merriweather(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[800])),
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                _lineData(sortedDates, timeMap, 'offering_tithe', pPurple),
                _lineData(sortedDates, timeMap, 'offering_weekly', Colors.blue),
                _lineData(sortedDates, timeMap, 'offering_thanks', Colors.orange),
                _lineData(sortedDates, timeMap, 'offering_construction', Colors.teal),
                _lineData(sortedDates, timeMap, 'offering_donation', Colors.indigo),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- UI: RANKING LIST ---
  Widget _buildRankingList(List<_OfferingUnitStat> stats, bool isTop) {
    if (stats.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text("No ranking data found", style: TextStyle(color: AppPalette.fg(Colors.grey))),
        ),
      );
    }

    final sorted = List<_OfferingUnitStat>.from(stats);
    sorted.sort((a, b) => isTop ? b.giversPct.compareTo(a.giversPct) : a.giversPct.compareTo(b.giversPct));
    final displayList = sorted.take(5).toList();

    return Column(
      children: displayList.asMap().entries.map((entry) {
        int rank = entry.key + 1;
        _OfferingUnitStat item = entry.value;
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
          title: Row(
            children: [
              Icon(isTop ? Icons.payments_rounded : Icons.money_off_rounded, size: 14, color: AppPalette.fg(color)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(item.unitName, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          subtitle: Text(
            "Saints: ${item.totalSaints} | Givers: ${CompPeriod.fmt(item.givers)} (Tithe: ${CompPeriod.fmt(item.tithe)}, Wkly: ${CompPeriod.fmt(item.weekly)})",
            style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.blueGrey)),
          ),
          trailing: Text(
            "${item.giversPct.toStringAsFixed(1)}%",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(color)),
          ),
        );
      }).toList(),
    );
  }

  // --- PDF REPORT EXPORT ---
  // Excel / PDF / Print for the summary table (same rows as the old PDF)
  ExportTable _exportTable(List<_OfferingUnitStat> stats, _OfferingUnitStat totalStat) => ExportTable(
        title: "Offering Status – ${widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : widget.level}",
        subtitle: 'Level: ${widget.level} | Group By: ${widget.groupBy} | Period: ${widget.timePeriod}'
              '${widget.selectedLocation.isNotEmpty ? ' | Loc: ${widget.selectedLocation}' : ''}'
              '${widget.selectedSubLocation.isNotEmpty ? ' | Sub: ${widget.selectedSubLocation}' : ''}'
              '${widget.selectedDepartment.isNotEmpty ? ' | Dept: ${widget.selectedDepartment}' : ''}'
              '${widget.selectedTeam.isNotEmpty ? ' | Team: ${widget.selectedTeam}' : ''}',
        headers: <String>[
                widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : 'Unit',
                'Saints',
                'Givers',
                'Tithe',
                'Tithe %',
                'Wkly',
                'Wkly %',
                'Thks',
                'Thks %',
                'Const',
                'Const %',
                'Donat',
                'Donat %',
              ],
        rows: <List<String>>[
                ...stats.map((u) => [
                      u.unitName,
                      '${u.totalSaints}',
                      CompPeriod.fmt(u.givers),
                      CompPeriod.fmt(u.tithe),
                      '${u.tithePct.toStringAsFixed(0)}%',
                      CompPeriod.fmt(u.weekly),
                      '${u.weeklyPct.toStringAsFixed(0)}%',
                      CompPeriod.fmt(u.thanks),
                      '${u.thanksPct.toStringAsFixed(0)}%',
                      CompPeriod.fmt(u.construction),
                      '${u.constructionPct.toStringAsFixed(0)}%',
                      CompPeriod.fmt(u.donation),
                      '${u.donationPct.toStringAsFixed(0)}%',
                    ]),
                [
                  'General Total',
                  '${totalStat.totalSaints}',
                  CompPeriod.fmt(totalStat.givers),
                  CompPeriod.fmt(totalStat.tithe),
                  '${totalStat.tithePct.toStringAsFixed(0)}%',
                  CompPeriod.fmt(totalStat.weekly),
                  '${totalStat.weeklyPct.toStringAsFixed(0)}%',
                  CompPeriod.fmt(totalStat.thanks),
                  '${totalStat.thanksPct.toStringAsFixed(0)}%',
                  CompPeriod.fmt(totalStat.construction),
                  '${totalStat.constructionPct.toStringAsFixed(0)}%',
                  CompPeriod.fmt(totalStat.donation),
                  '${totalStat.donationPct.toStringAsFixed(0)}%',
                ],
              ],
      );

  Future<void> _exportPdf(List<_OfferingUnitStat> stats, _OfferingUnitStat totalStat) =>
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

  Widget _cellPercent(double pct, double height, Color color, {bool isBold = false}) {
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          "${pct.toStringAsFixed(0)}%",
          style: GoogleFonts.merriweather(
            fontSize: 9.0,
            color: AppPalette.fg(color),
            fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
          ),
        ),
      ),
    );
  }

  LineChartBarData _lineData(List<DateTime> dates, Map<DateTime, List<dynamic>> map, String key, Color color) {
    return LineChartBarData(
      isCurved: true,
      color: color,
      barWidth: 2.5,
      dotData: FlDotData(show: dates.length <= 4),
      spots: List.generate(dates.length, (i) {
        var dayLogs = map[dates[i]]!;
        int count = dayLogs.where((l) => _isPaid(l[key])).length;
        double pct = dayLogs.isNotEmpty ? (count / dayLogs.length * 100) : 0.0;
        return FlSpot(i.toDouble(), pct);
      }),
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
                    tooltip: 'Excel / PDF / Print',
                    onPressed: onPdf,
                  ),
                IconButton(
                  icon: Icon(Icons.open_in_full_rounded, size: 19, color: AppPalette.fg(Colors.blueGrey)),
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
    final List<_OfferingUnitStat> unitStats = _calculateStats();
    final _OfferingUnitStat totalStat = _calculateTotalStat(unitStats);

    return Column(
      children: [
        if (widget.analyticsMode == 'Ranking') ...[
          _section(
            "Top giving units",
            _buildRankingList(unitStats, true),
            context,
          ),
          _section(
            "Units requiring financial counseling",
            _buildRankingList(unitStats, false),
            context,
          ),
        ] else ...[
          _section(
            "Offering summary table",
            _buildOfferingTable(unitStats, totalStat),
            context,
            onPdf: () => _exportPdf(unitStats, totalStat),
          ),
          const SizedBox(height: 10),
          _section(
            "Giving trends (%)",
            _buildTrendChart(unitStats),
            context,
          ),
        ],
      ],
    );
  }
}