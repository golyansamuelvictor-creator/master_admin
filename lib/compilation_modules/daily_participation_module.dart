// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, dead_null_aware_expression, unused_import
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/compilation_rules.dart';
import '../core/table_export.dart';
import '../core/compilation_style.dart';
import 'package:intl/intl.dart';
import 'package:master_admin/core/app_palette.dart';

class DailyParticipationModule extends StatefulWidget {
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

  const DailyParticipationModule({
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
  State<DailyParticipationModule> createState() => _DailyParticipationModuleState();
}

class _DailyParticipationModuleState extends State<DailyParticipationModule> {
  final Color pPurple = const Color(0xFF4A148C);
  String _selectedChartUnit = "General total";



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

  static const double rh = 24.0;
  static const double hh = 28.0;
  static const double sh = 18.0;
  static const double baseCw = 60.0;
  static const double lw = 115.0;
  static const double totalHeaderHeight = hh + hh + sh;

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

  bool get _isLocationRestricted {
    return !widget.isChurchWide && !widget.isGroupLeader && widget.userLoc.isNotEmpty && widget.userLoc != 'Church';
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant DailyParticipationModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level ||
        oldWidget.selectedLocation != widget.selectedLocation ||
        oldWidget.selectedSubLocation != widget.selectedSubLocation ||
        oldWidget.selectedDepartment != widget.selectedDepartment ||
        oldWidget.selectedTeam != widget.selectedTeam) {
      _selectedChartUnit = "General total";
    }
  }

  // Any filled-in answer that isn't a "no" counts (labels like "WDP Participated" were missed before)
  bool _isParticipated(dynamic val) => CompStatus.isPositive(val);

  bool _isDayDone(dynamic log, String dayCode, String legacyField) {
    final partDay = (log['part_day'] ?? '').toString().trim().toLowerCase();
    if (partDay.isNotEmpty) {
      if (partDay == dayCode.toLowerCase() || partDay.startsWith(dayCode.toLowerCase())) {
        return _isParticipated(log['status_detail']);
      }
      return false;
    }
    return _isParticipated(log[legacyField]) || _isParticipated(log['status_detail']);
  }

  // FIXED: No 100% Worker Log Discard
  List<dynamic> get _scopedWorkerLogs {
    return widget.logs.where((l) {
      final members = l['members'] is Map ? l['members'] as Map : {};
      if (members['is_worker'] == true || l['is_worker'] == true) return true;
      final duty = (members['duty'] ?? l['duty'] ?? '').toString().trim();
      if (duty.isNotEmpty && duty != '구역원') return true;
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

  // Strictly 5 Worker Days: Mon, Tue, Thu, Fri, Sat (Divided by n * 5)
  // [sessions] = number of weeks; day columns show an average week.
  // Sessions = the weeks THIS unit reported in; percentages from exact totals.
  Map<String, dynamic> _calc(List<dynamic> logsList, {List<dynamic>? officialMembers, int sessions = 1}) {
    sessions = widget.timePeriod == "Current status" ? 1 : CompPeriod.sessionCount(logsList);
    num per(int v) => CompPeriod.avgPerSession(v, sessions);
    num n = officialMembers != null ? officialMembers.length : per(logsList.length);
    double pct(int raw) => officialMembers != null
        ? CompPeriod.pctOf(raw, officialMembers.length, sessions)
        : (logsList.isEmpty ? 0.0 : raw / logsList.length * 100);

    final rMon = logsList.where((l) => _isDayDone(l, 'Mon', 'mon_part')).length;
    final rTue = logsList.where((l) => _isDayDone(l, 'Tue', 'tue_part')).length;
    final rThu = logsList.where((l) => _isDayDone(l, 'Thu', 'thu_part')).length;
    final rFri = logsList.where((l) => _isDayDone(l, 'Fri', 'fri_part')).length;
    final rSat = logsList.where((l) => _isDayDone(l, 'Sat', 'sat_part')).length;
    num mon = per(rMon), tue = per(rTue), thu = per(rThu), fri = per(rFri), sat = per(rSat);

    double avgPct = (pct(rMon) + pct(rTue) + pct(rThu) + pct(rFri) + pct(rSat)) / 5.0;

    return {
      "n": n,
      "mon": mon,
      "monp": pct(rMon),
      "tue": tue,
      "tuep": pct(rTue),
      "thu": thu,
      "thup": pct(rThu),
      "fri": fri,
      "frip": pct(rFri),
      "sat": sat,
      "satp": pct(rSat),
      "avg": avgPct,
    };
  }

  @override
  Widget build(BuildContext context) {
    _capRows.clear();
    final Map<String, dynamic> totS = _calc(
      _scopedWorkerLogs,
      officialMembers: _scopedWorkers.isNotEmpty ? _scopedWorkers : null, sessions: _sessions);

    final Map<String, Map<String, dynamic>> blockData = _getCalculatedBlocksMap();

    Map<String, dynamic> activeChartData = totS;
    if (_selectedChartUnit != "General total" && blockData.containsKey(_selectedChartUnit)) {
      activeChartData = blockData[_selectedChartUnit]!;
    }

    bool isTrend = widget.timePeriod != "Current status" || widget.analyticsMode == "Trend";

    return Column(children: [
      _buildToolbar(),
      _section(_sessions > 1 ? "Workers daily participation summary (average of $_sessions weeks)" : "Workers daily participation summary", _buildExcelGrid(totS), context),
      const SizedBox(height: 8),
      if (isTrend)
        _section("Historical trend over time", _buildTrendChart(blockData), context)
      else
        _section(
          "Weekly breakdown (%) - $_selectedChartUnit",
          _buildChartSection(totS, blockData, activeChartData),
          context,
        ),
    ]);
  }

  Widget _buildToolbar() => Row(
    mainAxisAlignment: MainAxisAlignment.start,
    children: [
      TableExport.buttons(context, _exportTable),
    ],
  );

  Widget _buildExcelGrid(Map<String, dynamic> tot) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availWidth = constraints.maxWidth;
        final double baseWidth = lw * 2 + baseCw * 12;
        final double effectiveCw = availWidth > baseWidth
            ? (availWidth - (lw * 2)) / 12.0
            : baseCw;
        final double effectiveTotalWidth = lw * 2 + effectiveCw * 12;

        Widget? childRows = _buildDynamicHierarchicalRows(effectiveCw);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              width: effectiveTotalWidth,
              decoration: BoxDecoration(border: Border.all(color: AppPalette.line(Colors.black), width: 1.0)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMergedHeader(effectiveCw),
                  _totalRow(() => _mergedRow("Total", "General total", tot, effectiveCw, b: true)),
                  if (childRows != null) childRows,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // SOLVED: Next-Tier Decomposition (Never suppresses to null)
  List<Map<String, dynamic>> get _chartMembers => _scopedWorkers;
  List<dynamic> get _chartLogs => _scopedWorkerLogs;

  // One entry per unit at the selected level; the table, the unit chips and
  // the charts all read this map, so they always show the same units.
  Map<String, Map<String, dynamic>> _getCalculatedBlocksMap() {
    final members = _chartMembers;
    final activeLogs = _chartLogs;
    final keys = CompLevel.orderedUnits(members, activeLogs, widget.level);
    final groupedLogs = CompLevel.groupBy(activeLogs, widget.level);
    final groupedMembers = CompLevel.groupBy(members, widget.level);
    final int sessions = _sessions;

    final Map<String, Map<String, dynamic>> calculatedBlocks = {};
    for (final k in keys) {
      calculatedBlocks[k] = _calc(groupedLogs[k] ?? [], officialMembers: groupedMembers[k], sessions: sessions);
    }
    return calculatedBlocks;
  }

  Widget? _buildDynamicHierarchicalRows(double colW) {
    final blockData = _getCalculatedBlocksMap();
    // A single unit row would just repeat the General total
    if (blockData.length <= 1) return null;

    String categoryName = (widget.activeUnitLabel != null && widget.activeUnitLabel!.isNotEmpty)
        ? widget.activeUnitLabel!
        : "Unit";
    return _mergedBlock(categoryName, blockData, colW);
  }

  // Header row and General total row share one look across all modules
  // (CompStyle): their own fills, header text a little larger.
  ({Color bg, Color fg, double fs, bool force})? _rowStyle;

  Widget _buildMergedHeader(double colW) {
    _rowStyle = (bg: CompStyle.headerBg, fg: CompStyle.headerFg, fs: CompStyle.headerFont, force: true);
    try {
      return _buildMergedHeaderRaw(colW);
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

  Widget _buildMergedHeaderRaw(double colW) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cell("Classification", w: lw, h: totalHeaderHeight, b: true, bg: const Color(0xFFF8FAFC)),
      _cell("Unit", w: lw, h: totalHeaderHeight, b: true, bg: const Color(0xFFF8FAFC)),
      Column(children: [
        Row(children: [
          _cell("Participation by Day", w: colW * 12, h: hh, b: true, bg: const Color(0xFFF8FAFC)),
        ]),
        Row(children: [
          _cell("Base", w: colW, h: hh, b: true),
          _cell("Monday", w: colW * 2, h: hh, b: true),
          _cell("Tuesday", w: colW * 2, h: hh, b: true),
          _cell("Thursday", w: colW * 2, h: hh, b: true),
          _cell("Friday", w: colW * 2, h: hh, b: true),
          _cell("Saturday", w: colW * 2, h: hh, b: true),
          _cell("Overall", w: colW, h: hh, b: true),
        ]),
        Row(children: [
          _cell("Workers", w: colW, h: sh),
          _cell("Total", w: colW, h: sh), _cell("%", w: colW, h: sh),
          _cell("Total", w: colW, h: sh), _cell("%", w: colW, h: sh),
          _cell("Total", w: colW, h: sh), _cell("%", w: colW, h: sh),
          _cell("Total", w: colW, h: sh), _cell("%", w: colW, h: sh),
          _cell("Total", w: colW, h: sh), _cell("%", w: colW, h: sh),
          _cell("Avg %", w: colW, h: sh),
        ]),
      ]),
    ]);
  }

  Widget _mergedBlock(String label, Map<String, dynamic> children, double colW) {
    List<Widget> rows = [];
    children.forEach((k, v) => rows.add(_dataRow(k, v, colW)));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cell(label, w: lw, h: (rows.length * rh).toDouble(), b: true, bg: const Color(0xFFFAF5FF)),
      Column(children: rows),
    ]);
  }

  Widget _mergedRow(String c1, String c2, Map<String, dynamic> d, double colW, {bool b = false}) => Row(children: [
    _cell(c1, w: lw, h: rh, b: b, bg: const Color(0xFFF3E5F5)),
    _dataRow(c2, d, colW, b: b),
  ]);

  // Each table row is also recorded as text for Excel / PDF / Print.
  List<String>? _capRow;
  final List<List<String>> _capRows = [];

  Widget _dataRow(String label, Map<String, dynamic> d, double colW, {bool b = false}) {
    final row = <String>[];
    _capRow = row;
    try {
      return _dataRowRaw(label, d, colW, b: b);
    } finally {
      _capRow = null;
      _capRows.add(row);
    }
  }

  ExportTable _exportTable() {
    final unit = (widget.activeUnitLabel ?? '').isNotEmpty ? widget.activeUnitLabel! : CompLevel.unitTitle(widget.level);
    final heads = <String>[unit, ...['Num', 'Mon', 'Mon %', 'Tue', 'Tue %', 'Thu', 'Thu %', 'Fri', 'Fri %', 'Sat', 'Sat %', 'Avg %']];
    return ExportTable(
      title: "Workers Daily Participation – $unit",
      subtitle: "Period: ${widget.timePeriod} · Level: ${widget.level}",
      headers: heads,
      rows: [for (final r in _capRows) r],
    );
  }

  Widget _dataRowRaw(String label, Map<String, dynamic> d, double colW, {bool b = false}) {
    return Row(children: [
      _cell(label, w: lw, h: rh, b: b, a: Alignment.center),
      _cell(CompPeriod.fmt(d['n']), w: colW, a: Alignment.center),
      _cell(CompPeriod.fmt(d['mon']), w: colW, a: Alignment.center),
      _cell("${d['monp'].toStringAsFixed(1)}%", w: colW, a: Alignment.center, color: pPurple, b: true),
      _cell(CompPeriod.fmt(d['tue']), w: colW, a: Alignment.center),
      _cell("${d['tuep'].toStringAsFixed(1)}%", w: colW, a: Alignment.center, color: pPurple, b: true),
      _cell(CompPeriod.fmt(d['thu']), w: colW, a: Alignment.center),
      _cell("${d['thup'].toStringAsFixed(1)}%", w: colW, a: Alignment.center, color: pPurple, b: true),
      _cell(CompPeriod.fmt(d['fri']), w: colW, a: Alignment.center),
      _cell("${d['frip'].toStringAsFixed(1)}%", w: colW, a: Alignment.center, color: pPurple, b: true),
      _cell(CompPeriod.fmt(d['sat']), w: colW, a: Alignment.center),
      _cell("${d['satp'].toStringAsFixed(1)}%", w: colW, a: Alignment.center, color: pPurple, b: true),
      _cell(
        "${d['avg'].toStringAsFixed(1)}%",
        w: colW,
        b: true,
        a: Alignment.center,
        color: (d['avg'] >= widget.targetValue) ? Colors.green[800] : Colors.red[800],
      ),
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
      width: w ?? baseCw,
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

  Widget _buildChartSection(Map<String, dynamic> totS, Map<String, Map<String, dynamic>> blockData, Map<String, dynamic> activeData) {
    List<String> unitsList = ["General total", ...blockData.keys];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        children: [
          if (unitsList.length > 1 && !_is24ChurchDept && !_isLocationRestricted && widget.groupBy != 'Church')
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: unitsList.map((u) {
                  final isSel = _selectedChartUnit == u;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 8),
                    child: InkWell(
                      onTap: () => setState(() => _selectedChartUnit = u),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppPalette.bg(isSel ? pPurple : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppPalette.line(isSel ? Colors.black : Colors.black26)),
                        ),
                        child: Text(
                          u,
                          style: GoogleFonts.merriweather(
                            fontSize: 10.5,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                            color: AppPalette.fg(isSel ? Colors.white : Colors.black87),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 8),
          _buildBarChart(activeData),
        ],
      ),
    );
  }

  Widget _buildBarChart(Map<String, dynamic> data) {
    List<double> vals = [
      (data['monp'] as num).toDouble(),
      (data['tuep'] as num).toDouble(),
      (data['thup'] as num).toDouble(),
      (data['frip'] as num).toDouble(),
      (data['satp'] as num).toDouble(),
    ];
    List<String> days = ["Monday", "Tuesday", "Thursday", "Friday", "Saturday"];

    return Column(children: [
      Container(
        height: 270,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        child: BarChart(BarChartData(
          maxY: 100,
          borderData: FlBorderData(show: true, border: Border(left: BorderSide(color: AppPalette.line(Colors.black), width: 1.0), bottom: BorderSide(color: AppPalette.line(Colors.black), width: 1.0))),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(
              y: widget.targetValue,
              color: Colors.green[700]!,
              strokeWidth: 1.5,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.green[800]), fontSize: 9.5, fontWeight: FontWeight.bold),
                labelResolver: (_) => "Target ${widget.targetValue.toInt()}%",
              ),
            ),
          ]),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              axisNameWidget: Text("Participation Rate (%)", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold)),
              axisNameSize: 22,
              sideTitles: SideTitles(showTitles: true, reservedSize: 38, getTitlesWidget: (v, m) => Text("${v.toInt()}%", style: GoogleFonts.merriweather(fontSize: 9.5))),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, m) {
                int idx = v.toInt();
                if (idx < 0 || idx >= days.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(days[idx], style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold)));
              }),
            ),
          ),
          barGroups: List.generate(5, (i) => BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: vals[i],
              color: pPurple,
              width: 38,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              backDrawRodData: BackgroundBarChartRodData(show: true, toY: 100, color: const Color(0xFFF1F5F9)),
            ),
          ])),
        )),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 20,
        alignment: WrapAlignment.center,
        children: [
          _lgItem("Participated (%)", pPurple),
          _lgItem("Target (${widget.targetValue.toInt()}%)", Colors.green[700]!, isDashed: true),
        ],
      ),
    ]);
  }

  Widget _buildTrendChart(Map<String, Map<String, dynamic>> blockData) {
    final Set<String> rawDates = {};
    for (var l in _scopedWorkerLogs) {
      // One point per week (Weekly) or month (Monthly), else per date
      final d = CompPeriod.bucketKey(l, widget.timePeriod);
      if (d.isNotEmpty) rawDates.add(d);
    }
    // Weekly = Week 1..Week 5, Monthly = the 4 months, even if a week has no reports
    final List<String> sortedDates = rawDates.isEmpty
        ? <String>[]
        : (CompPeriod.expectedBuckets(widget.timePeriod) ?? (rawDates.toList()..sort()));

    if (sortedDates.isEmpty) {
      return SizedBox(
        height: 180, 
        child: Center(
          child: Text(
            "No historical records found for this period",
            style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700)),
          ),
        ),
      );
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

    final List<String> unitKeys = _isLocationRestricted
        ? [widget.userLoc]
        : blockData.keys.toList();

    final List<Color> palette = [
      pPurple, Colors.blue.shade700, Colors.teal.shade600, Colors.orange.shade800,
      Colors.deepOrange, Colors.pink.shade700, Colors.indigo.shade600, Colors.green.shade800,
      Colors.brown, Colors.amber.shade900, Colors.cyan.shade800, Colors.blueGrey,
    ];

    double maxPct = 10.0;
    final List<LineChartBarData> lineBars = [];

    if (unitKeys.isEmpty || _is24ChurchDept || _isLocationRestricted || widget.groupBy == 'Church') {
      final List<FlSpot> spots = [];
      for (int d = 0; d < sortedDates.length; d++) {
        final dateStr = sortedDates[d];
        final dateLogs = _scopedWorkerLogs.where((l) => CompPeriod.bucketKey(l, widget.timePeriod) == dateStr).toList();
        final calc = _calc(dateLogs, officialMembers: _scopedWorkers, sessions: CompPeriod.sessionCount(dateLogs));
        final double avgP = (calc['avg'] as num).toDouble();
        if (avgP > maxPct) maxPct = avgP;
        spots.add(FlSpot(d.toDouble(), avgP));
      }
      lineBars.add(LineChartBarData(
        spots: spots,
        color: pPurple,
        barWidth: 3.0,
        isCurved: true,
        dotData: const FlDotData(show: true),
      ));
    } else {
      for (int u = 0; u < unitKeys.length; u++) {
        final unitName = unitKeys[u];
        final Color unitColor = palette[u % palette.length];
        final List<FlSpot> spots = [];

        for (int d = 0; d < sortedDates.length; d++) {
          final dateStr = sortedDates[d];
          final dateLogs = _scopedWorkerLogs.where((l) {
            final matchesDate = CompPeriod.bucketKey(l, widget.timePeriod) == dateStr;
            final matchesUnit = _resolveUnitKeyForRecord(l, widget.level.toLowerCase()) == unitName;
            return matchesDate && matchesUnit;
          }).toList();

          final calc = _calc(dateLogs, officialMembers: _scopedWorkers, sessions: CompPeriod.sessionCount(dateLogs));
          final double avgP = (calc['avg'] as num).toDouble();
          if (avgP > maxPct) maxPct = avgP;
          spots.add(FlSpot(d.toDouble(), avgP));
        }

        lineBars.add(LineChartBarData(
          spots: spots,
          color: unitColor,
          barWidth: 2.2,
          isCurved: true,
          dotData: const FlDotData(show: true),
        ));
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        children: [
          SizedBox(
            height: 280,
            child: LineChart(LineChartData(
              maxY: min(100.0, max(maxPct * 1.25, 40.0)),
              borderData: FlBorderData(
                show: true, 
                border: Border(
                  left: BorderSide(color: AppPalette.line(Colors.black), width: 1.0), 
                  bottom: BorderSide(color: AppPalette.line(Colors.black), width: 1.0),
                ),
              ),
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
                  axisNameWidget: Text("Average Participation (%)", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold)),
                  axisNameSize: 22,
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (v, m) => Text("${v.toInt()}%", style: GoogleFonts.merriweather(fontSize: 9.5)),
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: lineBars,
            )),
          ),
          if (unitKeys.isNotEmpty && !_is24ChurchDept && !_isLocationRestricted && widget.groupBy != 'Church')
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Wrap(
                spacing: 16,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: List.generate(
                  unitKeys.length,
                  (i) => _lgItem(unitKeys[i], palette[i % palette.length]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _resolveUnitKeyForRecord(dynamic record, String lvl) => CompLevel.unitKey(record, widget.level);

  Widget _lgItem(String t, Color c, {bool isDashed = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: isDashed ? 3 : 10, decoration: BoxDecoration(color: AppPalette.bg(c), borderRadius: BorderRadius.circular(isDashed ? 0 : 2))),
      const SizedBox(width: 6),
      Text(t, style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87))),
    ],
  );


  Widget _section(String title, Widget content, BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      color: AppPalette.bg(Colors.white),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppPalette.line(Colors.black), width: 1.0),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
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