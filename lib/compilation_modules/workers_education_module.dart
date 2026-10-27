// ignore_for_file: curly_braces_in_flow_control_structures, unused_element
import 'dart:math';
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/compilation_rules.dart';
import '../core/table_export.dart';
import '../core/compilation_style.dart';
import 'package:intl/intl.dart';
import 'package:master_admin/core/app_palette.dart';

class WorkersEducationModule extends StatefulWidget {
  final List<dynamic> logs;
  final List<Map<String, dynamic>>? masterMembers;
  final String timePeriod, level, analyticsMode, groupBy;
  final double targetValue;
  final String? activeUnitLabel;

  final String selectedLocation;
  final String selectedSubLocation;
  final String selectedDepartment;
  final String selectedTeam;

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

  const WorkersEducationModule({
    super.key,
    required this.logs,
    this.masterMembers,
    required this.timePeriod,
    required this.level,
    required this.analyticsMode,
    required this.groupBy,
    this.targetValue = 90.0,
    this.selectedLocation = '',
    this.selectedSubLocation = '',
    this.selectedDepartment = '',
    this.selectedTeam = '',
    this.activeUnitLabel,
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
  State<WorkersEducationModule> createState() => _WorkersEducationModuleState();
}

class _WorkersEducationModuleState extends State<WorkersEducationModule> {
  final Color pPurple = const Color(0xFF4A148C);

  String _selectedTrendMetric = "Overall Attendance";



  // Headcount comes only from the screen's scoped member list. (The old
  // fallback loaded ALL church members when the scoped list was empty.)
  List<Map<String, dynamic>> get _effectiveMembers => widget.masterMembers ?? const [];

  int get _sessions => widget.timePeriod == "Current status" ? 1 : CompPeriod.sessionCount(_scopedWorkerLogs);

  List<Map<String, dynamic>> get _scopedWorkers {
    final workers = _effectiveMembers.where((m) {
      if (m['is_worker'] == true) return true;
      final duty = (m['duty'] ?? '').toString().trim();
      return duty.isNotEmpty && duty != '구역원';
    }).toList();
    return workers.isNotEmpty ? workers : _effectiveMembers;
  }

  // Table Sizing
  static const double rh = 24.0;
  static const double hh = 30.0;
  static const double sh = 20.0;
  static const double cw = 65.0;
  static const double lw = 115.0;
  static const double totalHeaderHeight = hh + hh + sh;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant WorkersEducationModule oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  // FIXED: No 100% Worker Log Discard
  List<dynamic> get _scopedWorkerLogs {
    return widget.logs.where((l) {
      final members = l['members'] is Map ? l['members'] as Map : {};
      if (members['is_worker'] == true || l['is_worker'] == true) return true;
      final duty = (members['duty'] ?? l['duty'] ?? '').toString().trim();
      if (duty.isNotEmpty && duty != '구역원') return true;
      // If duty/worker flags are not populated in the log, do not discard rows already in the workers table
      return true;
    }).toList();
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

  List<String> _sortAscending(List<String> items) {
    int extractNumber(String s) {
      final match = RegExp(r'\d+').firstMatch(s);
      return match != null ? int.parse(match.group(0)!) : 999999;
    }
    final sorted = List<String>.from(items);
    sorted.sort((a, b) {
      int numA = extractNumber(a);
      int numB = extractNumber(b);
      if (numA != numB) return numA.compareTo(numB);
      return a.compareTo(b);
    });
    return sorted;
  }

  List<String> _getScopedTeams() {
    final Set<String> teams = {};
    for (var m in _scopedWorkers) {
      final t = m['team']?.toString().trim() ?? '';
      if (t.isNotEmpty) teams.add(t);
    }
    return _sortAscending(teams.toList());
  }

  List<String> _getScopedCellGroups() {
    final Set<String> cells = {};
    for (var m in _scopedWorkers) {
      final c = m['cell_group']?.toString().trim() ?? '';
      if (c.isNotEmpty) cells.add(c);
    }
    return _sortAscending(cells.toList());
  }

  // BULLETPROOF: Supports new WorkersEducationEntry (status_detail) + Legacy columns
  // Sessions = the weeks THIS unit reported in; percentages from exact totals.
  Map<String, dynamic> _calc(List<dynamic> logsList, {List<dynamic>? officialMembers, int sessions = 1}) {
    sessions = widget.timePeriod == "Current status" ? 1 : CompPeriod.sessionCount(logsList);
    num per(int v) => CompPeriod.avgPerSession(v, sessions);
    num n = officialMembers != null ? officialMembers.length : per(logsList.length);
    double pct(int raw) => officialMembers != null
        ? CompPeriod.pctOf(raw, officialMembers.length, sessions)
        : (logsList.isEmpty ? 0.0 : raw / logsList.length * 100);

    // Any filled-in answer that isn't a "no" (WE Missed, Absent, Didn't ...) counts as attended
    bool isAttended(dynamic x) => CompStatus.isPositive(x['status_detail'] ?? x['edu_sun'] ?? x['edu_wed']);

    bool isSun(dynamic x) {
      final day = (x['edu_day'] ?? x['education_day'] ?? x['service_day'] ?? '').toString().trim().toLowerCase();
      if (day == 'sunday' || day == 'sun') return true;
      final d = (x['report_date'] ?? '').toString();
      try { return DateTime.parse(d).weekday == DateTime.sunday; } catch (_) { return false; }
    }

    bool isWed(dynamic x) {
      final day = (x['edu_day'] ?? x['education_day'] ?? x['service_day'] ?? '').toString().trim().toLowerCase();
      if (day == 'wednesday' || day == 'wed') return true;
      final d = (x['report_date'] ?? '').toString();
      try { return DateTime.parse(d).weekday == DateTime.wednesday; } catch (_) { return false; }
    }

    final rSun = logsList.where((x) => (x['edu_sun'] == "Attended") || (isSun(x) && isAttended(x))).length;
    final rWed = logsList.where((x) => (x['edu_wed'] == "Attended") || (isWed(x) && isAttended(x))).length;
    final rOth = logsList.where((x) => (x['edu_other'] == "Attended") || (!isSun(x) && !isWed(x) && isAttended(x))).length;
    final rAtt = logsList.where(isAttended).length;
    num sun = per(rSun);
    num wed = per(rWed);
    num oth = per(rOth);
    num att = per(rAtt);
    num ab = n > att ? (n - att) : 0;
    final attP = pct(rAtt);

    return {
      "n": n,
      "att": att,
      "pct": attP,
      "sun": sun,
      "sunp": pct(rSun),
      "wed": wed,
      "wedp": pct(rWed),
      "oth": oth,
      "othp": pct(rOth),
      "ab": ab,
      "abp": attP >= 100 ? 0.0 : 100 - attP,
    };
  }

  @override
  Widget build(BuildContext context) {
    _capRows.clear();
    final Map<String, dynamic> totS = _calc(
      _scopedWorkerLogs,
      officialMembers: _scopedWorkers.isNotEmpty ? _scopedWorkers : null, sessions: _sessions);

    return Column(children: [
      _buildToolbar(),
      _section(_sessions > 1 ? "Workers education summary table (average of $_sessions weeks)" : "Workers education summary table", _buildExcelGrid(totS), context),
      const SizedBox(height: 8),
      _section("Participation visualization", _buildChart(), context),
    ]);
  }

  Widget _buildToolbar() => Row(
    mainAxisAlignment: MainAxisAlignment.start,
    children: [
      TableExport.buttons(context, _exportTable),
    ],
  );

  Widget _buildExcelGrid(Map<String, dynamic> tot) {
    Widget? childRows = _buildDynamicHierarchicalRows();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: AppPalette.line(Colors.black), width: 1.0)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildMergedHeader(),
            _totalRow(() => _mergedRow("Total", "General total", tot, b: true)),
            if (childRows != null) childRows,
          ]),
        ),
      ),
    );
  }

  // SOLVED: Next-Tier Decomposition (Never suppresses to null)
  // Same members/logs the chart uses, for the chart helpers above
  List<Map<String, dynamic>> get _chartMembers => _scopedWorkers;
  List<dynamic> get _chartLogs => _scopedWorkerLogs;

  // One row per unit at the selected level. Uses the same unit list as the
  // chart (CompLevel.orderedUnits), so table rows and chart bars match.
  Widget? _buildDynamicHierarchicalRows() {
    final members = _chartMembers;
    final activeLogs = _chartLogs;
    final keys = CompLevel.orderedUnits(members, activeLogs, widget.level);
    // A single unit row would just repeat the General total
    if (keys.length <= 1) return null;

    final groupedLogs = CompLevel.groupBy(activeLogs, widget.level);
    final groupedMembers = CompLevel.groupBy(members, widget.level);
    final int sessions = _sessions;

    final Map<String, dynamic> calculatedBlocks = {};
    for (final k in keys) {
      calculatedBlocks[k] = _calc(groupedLogs[k] ?? [], officialMembers: groupedMembers[k], sessions: sessions);
    }

    final String label = (widget.activeUnitLabel ?? '').isNotEmpty ? widget.activeUnitLabel! : CompLevel.unitTitle(widget.level);
    return _mergedBlock(label, calculatedBlocks);
  }

  // Header row and General total row share one look across all modules
  // (CompStyle): their own fills, header text a little larger.
  ({Color bg, Color fg, double fs, bool force})? _rowStyle;

  Widget _buildMergedHeader() {
    _rowStyle = (bg: CompStyle.headerBg, fg: CompStyle.headerFg, fs: CompStyle.headerFont, force: true);
    try {
      return _buildMergedHeaderRaw();
    } finally {
      _rowStyle = null;
    }
  }

  Widget _totalRow(Widget Function() build) {
    _rowStyle = (bg: CompStyle.totalBg, fg: CompStyle.totalFg, fs: CompStyle.cellFont, force: false);
    try {
      return build();
    } finally {
      _rowStyle = null;
    }
  }

  Widget _buildMergedHeaderRaw() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cell("Classification", w: lw, h: totalHeaderHeight, b: true, bg: const Color(0xFFF8FAFC)),
      _cell("Unit", w: lw, h: totalHeaderHeight, b: true, bg: const Color(0xFFF8FAFC)),
      Column(children: [
        Row(children: [
          _cell("Summary", w: cw * 11, h: hh, b: true, bg: const Color(0xFFF8FAFC)),
        ]),
        Row(children: [
          _cell("Overall metrics", w: cw * 3, h: hh, b: true),
          _cell("Sunday", w: cw * 2, h: hh, b: true),
          _cell("Wednesday", w: cw * 2, h: hh, b: true),
          _cell("Other", w: cw * 2, h: hh, b: true),
          _cell("Absentees", w: cw * 2, h: hh, b: true),
        ]),
        Row(children: [
          _cell("Workers", w: cw, h: sh), _cell("Att", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
        ]),
      ]),
    ]);
  }

  Widget _mergedBlock(String label, Map<String, dynamic> children) {
    List<Widget> rows = [];
    children.forEach((k, v) => rows.add(_dataRow(k, v)));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cell(label, w: lw, h: (rows.length * rh).toDouble(), b: true, bg: const Color(0xFFFAF5FF)),
      Column(children: rows),
    ]);
  }

  Widget _mergedRow(String c1, String c2, Map<String, dynamic> d, {bool b = false}) => Row(children: [
    _cell(c1, w: lw, h: rh, b: b, bg: const Color(0xFFF3E5F5)),
    _dataRow(c2, d, b: b),
  ]);

  // Each table row is also recorded as text for Excel / PDF / Print.
  List<String>? _capRow;
  final List<List<String>> _capRows = [];

  Widget _dataRow(String label, Map<String, dynamic> d, {bool b = false}) {
    final row = <String>[];
    _capRow = row;
    try {
      return _dataRowRaw(label, d, b: b);
    } finally {
      _capRow = null;
      _capRows.add(row);
    }
  }

  ExportTable _exportTable() {
    final unit = (widget.activeUnitLabel ?? '').isNotEmpty ? widget.activeUnitLabel! : CompLevel.unitTitle(widget.level);
    final heads = <String>[unit, ...['Num', 'Attended', 'Att %', 'Sunday', 'Sun %', 'Wednesday', 'Wed %', 'Other', 'Other %', 'Absentees', 'Absent %']];
    return ExportTable(
      title: "Workers Education – $unit",
      subtitle: "Period: ${widget.timePeriod} · Level: ${widget.level}",
      headers: heads,
      rows: [for (final r in _capRows) r],
    );
  }

  Widget _dataRowRaw(String label, Map<String, dynamic> d, {bool b = false}) {
    return Row(children: [
      _cell(label, w: lw, h: rh, b: b, a: Alignment.center),
      _cell(CompPeriod.fmt(d['n']), a: Alignment.center),
      _cell(CompPeriod.fmt(d['att']), a: Alignment.center),
      _cell("${d['pct'].toStringAsFixed(1)}%", b: true, a: Alignment.center),
      _cell(CompPeriod.fmt(d['sun']), a: Alignment.center),
      _cell("${d['sunp'].toStringAsFixed(1)}%", a: Alignment.center),
      _cell(CompPeriod.fmt(d['wed']), a: Alignment.center),
      _cell("${d['wedp'].toStringAsFixed(1)}%", a: Alignment.center),
      _cell(CompPeriod.fmt(d['oth']), a: Alignment.center),
      _cell("${d['othp'].toStringAsFixed(1)}%", a: Alignment.center),
      _cell(CompPeriod.fmt(d['ab']), color: Colors.red[800], a: Alignment.center),
      _cell("${d['abp'].toStringAsFixed(1)}%", a: Alignment.center),
    ]);
  }

  Widget _cell(
    String t, {
    double? w,
    double h = rh,
    bool b = false,
    Color? color,
    Color? bg,
    Alignment a = Alignment.center,
  }) {
    _capRow?.add(t);
    return Container(
      width: w ?? cw,
      height: h,
      alignment: a,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(color: AppPalette.bg((_rowStyle?.force ?? false) ? _rowStyle!.bg : (bg ?? _rowStyle?.bg ?? Colors.white)), border: Border.all(color: AppPalette.line(Colors.black45), width: 0.4)),
      child: Text(
        t,
        textAlign: TextAlign.center,
        style: GoogleFonts.merriweather(
          fontSize: _rowStyle?.fs ?? CompStyle.cellFont,
          fontWeight: (b || (_rowStyle?.force ?? false)) ? FontWeight.w900 : FontWeight.normal,
          color: AppPalette.fg((_rowStyle?.force ?? false) ? _rowStyle!.fg : (color ?? _rowStyle?.fg ?? Colors.black87)),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _getDynamicXAxisLabel() {
    return (widget.activeUnitLabel ?? '').isNotEmpty ? widget.activeUnitLabel! : CompLevel.unitTitle(widget.level);
  }

  // TREND CHART: Week 1 to Week 5 & Month 1 to Month 4
  Widget _buildChart() {
    bool isTrend = widget.timePeriod != "Current status";
    final lvl = widget.level.toLowerCase();
    final scopedLogs = _scopedWorkerLogs;

    if (!isTrend) {
      String xName = _getDynamicXAxisLabel();
      List<String> keys = _getUnitKeysForLevel(lvl);

      Map<String, List<dynamic>> cgLogs = {};
      Map<String, List<dynamic>> cgMembers = {};

      for (var k in keys) {
        cgLogs[k] = [];
        cgMembers[k] = [];
      }

      for (var m in _scopedWorkers) {
        String b = _resolveUnitKeyForRecord(m, lvl);
        if (cgMembers.containsKey(b)) cgMembers[b]!.add(m);
      }
      for (var l in scopedLogs) {
        String b = _resolveUnitKeyForRecord(l, lvl);
        if (cgLogs.containsKey(b)) cgLogs[b]!.add(l);
      }

      double maxHeadcount = 10.0;
      for (var key in keys) {
        final s = _calc(cgLogs[key] ?? [], officialMembers: cgMembers[key]);
        final double nVal = (s['n'] as num?)?.toDouble() ?? 0.0;
        final double attVal = (s['att'] as num?)?.toDouble() ?? 0.0;
        final double sunVal = (s['sun'] as num?)?.toDouble() ?? 0.0;
        final double wedVal = (s['wed'] as num?)?.toDouble() ?? 0.0;
        final double highest = max<double>(nVal, max<double>(attVal, max<double>(sunVal, wedVal)));
        if (highest > maxHeadcount) maxHeadcount = highest;
      }
      double dynamicMaxY = (maxHeadcount * 1.2).ceilToDouble();

      return Column(children: [
        Container(
          height: 360,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: _barChart(xName, keys, cgLogs, cgMembers, dynamicMaxY),
        ),
        Padding(padding: const EdgeInsets.only(top: 10, bottom: 5), child: _buildBarLegend()),
      ]);
    }

    final Set<String> rawDates = {};
    for (var l in scopedLogs) {
      // One point per week (Weekly) or month (Monthly), else per date
      final d = CompPeriod.bucketKey(l, widget.timePeriod);
      if (d.isNotEmpty) rawDates.add(d);
    }
    // Weekly = Week 1..Week 5, Monthly = the 4 months, even if a week has no reports
    final List<String> sortedDates = rawDates.isEmpty
        ? <String>[]
        : (CompPeriod.expectedBuckets(widget.timePeriod) ?? (rawDates.toList()..sort()));

    if (sortedDates.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text("No historical records found for this period")));
    }

    List<String> periodLabels = [];
    if (widget.timePeriod == "Weekly status") {
      periodLabels = List.generate(sortedDates.length, (i) {
        final d = sortedDates[i];
        final mmdd = d.length >= 10 ? "${d.substring(5, 7)}/${d.substring(8, 10)}" : d;
        return "Week ${i + 1}\n($mmdd)";
      });
    } else if (widget.timePeriod == "Monthly status") {
      periodLabels = List.generate(sortedDates.length, (i) {
        final d = sortedDates[i];
        try {
          final dt = DateTime.parse(d);
          return DateFormat('MMM').format(dt);
        } catch (_) {
          return "M${i + 1}";
        }
      });
    } else {
      periodLabels = sortedDates.map((d) => d.length >= 10 ? "${d.substring(5, 7)}/${d.substring(8, 10)}" : d).toList();
    }

    final List<String> unitKeys = _getUnitKeysForLevel(lvl);
    final List<Color> palette = [
      pPurple, Colors.blue.shade700, Colors.teal.shade600, Colors.orange.shade800,
      Colors.deepOrange, Colors.pink.shade700, Colors.indigo.shade600, Colors.green.shade800,
      Colors.brown, Colors.amber.shade900, Colors.cyan.shade800, Colors.purpleAccent.shade700, Colors.blueGrey,
    ];

    double maxTrendValue = 10.0;
    final List<LineChartBarData> lineBars = [];

    for (int u = 0; u < unitKeys.length; u++) {
      final unitName = unitKeys[u];
      final Color unitColor = palette[u % palette.length];
      final List<FlSpot> spots = [];

      for (int d = 0; d < sortedDates.length; d++) {
        final dateStr = sortedDates[d];
        final dateLogs = scopedLogs.where((l) {
          final matchesDate = CompPeriod.bucketKey(l, widget.timePeriod) == dateStr;
          final matchesUnit = _resolveUnitKeyForRecord(l, lvl) == unitName;
          return matchesDate && matchesUnit;
        }).toList();

        final calc = _calc(dateLogs, officialMembers: _scopedWorkers, sessions: CompPeriod.sessionCount(dateLogs));
        double val = 0.0;
        if (_selectedTrendMetric == "Overall Attendance") {
          val = (calc['att'] as num).toDouble();
        } else if (_selectedTrendMetric == "Sunday Education") {
          val = (calc['sun'] as num).toDouble();
        } else {
          val = (calc['wed'] as num).toDouble();
        }

        if (val > maxTrendValue) maxTrendValue = val;
        spots.add(FlSpot(d.toDouble(), val));
      }

      lineBars.add(LineChartBarData(
        spots: spots,
        color: unitColor,
        barWidth: 2.5,
        isCurved: true,
        dotData: const FlDotData(show: true),
      ));
    }

    double dynamicMaxY = (maxTrendValue * 1.25).ceilToDouble();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text("Trend by Date (${widget.timePeriod == 'Weekly status' ? 'Weeks 1-5' : 'Months 1-4'})", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87)), maxLines: 2, overflow: TextOverflow.ellipsis)),
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF3E5F5)), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppPalette.line(Colors.purple.shade200))),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTrendMetric,
                  icon: const Icon(Icons.tune, size: 14),
                  style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)),
                  items: ["Overall Attendance", "Sunday Education", "Wednesday Education"].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedTrendMetric = v);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      Container(
        height: 340,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        child: LineChart(LineChartData(
          maxY: dynamicMaxY,
          borderData: FlBorderData(show: true, border: Border(left: BorderSide(color: AppPalette.line(Colors.black), width: 1.0), bottom: BorderSide(color: AppPalette.line(Colors.black), width: 1.0))),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              axisNameWidget: Text(widget.timePeriod == "Weekly status" ? "Weekly Performance (Week 1–5)" : "Service Date (MM/DD)", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold)),
              axisNameSize: 22,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: 1.0,
                getTitlesWidget: (v, m) {
                  int idx = v.toInt();
                  if (idx < 0 || idx >= periodLabels.length || v != idx.toDouble()) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(periodLabels[idx], textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 8.5, fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: Text("$_selectedTrendMetric (Persons)", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold)),
              axisNameSize: 22,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (v, m) => Text("${v.toInt()}", style: GoogleFonts.merriweather(fontSize: 9.5)),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: lineBars,
        )),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Center(
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: List.generate(unitKeys.length, (i) => _lgItem(unitKeys[i], palette[i % palette.length])),
          ),
        ),
      ),
    ]);
  }

  List<String> _getUnitKeysForLevel(String lvl) {
    return CompLevel.orderedUnits(_chartMembers, _chartLogs, widget.level);
  }

  String _resolveUnitKeyForRecord(dynamic record, String lvl) => CompLevel.unitKey(record, widget.level);

  Widget _barChart(String xN, List<String> ks, Map<String, List<dynamic>> gsLogs, Map<String, List<dynamic>> gsMembers, double maxY) => BarChart(BarChartData(
    maxY: maxY,
    borderData: FlBorderData(show: true, border: Border(left: BorderSide(color: AppPalette.line(Colors.black), width: 1.0), bottom: BorderSide(color: AppPalette.line(Colors.black), width: 1.0))),
    titlesData: FlTitlesData(
      bottomTitles: AxisTitles(
        axisNameWidget: Padding(
          padding: const EdgeInsets.only(top: 15),
          child: Text(xN, style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold)),
        ),
        axisNameSize: 32,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 50,
          interval: 1.0,
          getTitlesWidget: (v, m) {
            int index = v.toInt();
            if (index < 0 || index >= ks.length || v != index.toDouble()) return const SizedBox.shrink();
            return Transform.rotate(
              angle: -0.45,
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(ks[index], style: GoogleFonts.merriweather(fontSize: 9, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87)), overflow: TextOverflow.ellipsis),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        axisNameWidget: Text("Headcount (Persons)", style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold)),
        axisNameSize: 22,
        sideTitles: SideTitles(showTitles: true, reservedSize: 42, getTitlesWidget: (v, m) => Text("${v.toInt()}", style: GoogleFonts.merriweather(fontSize: 10))),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    ),
    gridData: const FlGridData(show: true, drawVerticalLine: false),
    barGroups: List.generate(ks.length, (i) {
      final s = _calc(gsLogs[ks[i]] ?? [], officialMembers: gsMembers[ks[i]]);
      return BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: (s['n'] as num).toDouble(), color: Colors.grey.shade400, width: 7, borderRadius: BorderRadius.circular(2)),
        BarChartRodData(toY: (s['att'] as num).toDouble(), color: pPurple, width: 7, borderRadius: BorderRadius.circular(2)),
        BarChartRodData(toY: (s['sun'] as num).toDouble(), color: Colors.blue.shade600, width: 7, borderRadius: BorderRadius.circular(2)),
        BarChartRodData(toY: (s['wed'] as num).toDouble(), color: Colors.teal.shade600, width: 7, borderRadius: BorderRadius.circular(2)),
      ]);
    }),
  ));

  Widget _buildBarLegend() => Center(
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 18,
      runSpacing: 6,
      children: [
        _lgItem("Workers (Num)", Colors.grey.shade400),
        _lgItem("Overall Att", pPurple),
        _lgItem("Sunday", Colors.blue.shade600),
        _lgItem("Wednesday", Colors.teal.shade600),
      ],
    ),
  );

  Widget _lgItem(String t, Color c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: AppPalette.bg(c), borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 5),
      Text(t, style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87))),
    ],
  );


  Widget _section(String title, Widget content, BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      color: AppPalette.bg(Colors.white),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppPalette.line(Colors.black), width: 1.0),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Column(children: [
      ListTile(
        dense: true,
        title: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14.5, color: AppPalette.fg(pPurple))),
        trailing: IconButton(
          icon: const Icon(Icons.fullscreen, size: 18),
          onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (c) => Scaffold(
              appBar: AppBar(title: Text(title, style: GoogleFonts.merriweather())),
              body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(8), child: content)),
            ),
          )),
        ),
      ),
      Divider(height: 1, color: AppPalette.bg(Colors.black26)),
      content,
    ]),
  );
}