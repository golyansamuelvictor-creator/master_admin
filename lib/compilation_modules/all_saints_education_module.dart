// ignore_for_file: unused_element, curly_braces_in_flow_control_structures
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../core/compilation_rules.dart';
import '../core/compilation_style.dart';
import 'package:intl/intl.dart';
import 'package:master_admin/core/app_palette.dart';

class AllSaintsEducationModule extends StatefulWidget {
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

  const AllSaintsEducationModule({
    super.key,
    required this.logs,
    this.masterMembers,
    required this.timePeriod,
    required this.level,
    required this.analyticsMode,
    required this.groupBy,
    required this.targetValue,
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
  State<AllSaintsEducationModule> createState() => _AllSaintsEducationModuleState();
}

class _AllSaintsEducationModuleState extends State<AllSaintsEducationModule> {
  final Color pPurple = const Color(0xFF4A148C);

  String _selectedTrendMetric = "General Attendance";
  String _selectedEduDay = "Sun"; 



  // Headcount comes only from the screen's scoped member list. (The old
  // fallback loaded ALL church members when the scoped list was empty.)
  List<Map<String, dynamic>> get _effectiveMembers => widget.masterMembers ?? const [];

  int get _sessions => widget.timePeriod == "Current status" ? 1 : CompPeriod.sessionCount(_filteredLogs);

  static const double rh = 24.0;
  static const double hh = 30.0;
  static const double sh = 20.0;
  static const double baseCw = 65.0;
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

  bool _isSundayRecord(dynamic l) {
    final day = (l['education_day'] ?? l['service_day'] ?? '').toString().toLowerCase();
    if (day == 'sunday' || day == 'sun') return true;
    final dateStr = (l['report_date'] ?? '').toString();
    try {
      final dt = DateTime.parse(dateStr);
      return dt.weekday == DateTime.sunday;
    } catch (_) {
      return false;
    }
  }

  bool _isWednesdayRecord(dynamic l) {
    final day = (l['education_day'] ?? l['service_day'] ?? '').toString().toLowerCase();
    if (day == 'wednesday' || day == 'wed') return true;
    final dateStr = (l['report_date'] ?? '').toString();
    try {
      final dt = DateTime.parse(dateStr);
      return dt.weekday == DateTime.wednesday;
    } catch (_) {
      return false;
    }
  }

  List<dynamic> get _filteredLogs {
    if (widget.timePeriod == "Current status") {
      return widget.logs;
    }
    if (_selectedEduDay == "Sun") {
      return widget.logs.where(_isSundayRecord).toList();
    } else {
      return widget.logs.where(_isWednesdayRecord).toList();
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant AllSaintsEducationModule oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    for (var m in _effectiveMembers) {
      final t = m['team']?.toString().trim() ?? '';
      if (t.isNotEmpty) teams.add(t);
    }
    return _sortAscending(teams.toList());
  }

  List<String> _getScopedCellGroups() {
    final Set<String> cells = {};
    for (var m in _effectiveMembers) {
      final c = m['cell_group']?.toString().trim() ?? '';
      if (c.isNotEmpty) cells.add(c);
    }
    return _sortAscending(cells.toList());
  }

  // [sessions] > 1 turns period totals into an average per session.
  // Each report is counted once: make-up first, then in-person, then online
  // (before, "make up online" was counted twice).
  Map<String, dynamic> _calc(List<dynamic> logsList, {List<dynamic>? officialMembers, int sessions = 1}) {
    int per(int v) => CompPeriod.perSession(v, sessions);
    int n = officialMembers != null ? officialMembers.length : per(logsList.length);

    String st(dynamic x) => CompStatus.norm(x['status_detail'] ?? x['attendance_realtime'] ?? x['attendance_makeup']);
    bool isMu(dynamic x) {
      final s = st(x);
      return !CompStatus.isNegative(s) && (s.contains('make up') || s.contains('makeup') || s.contains('make-up') || s == 'mu');
    }
    bool isIp(dynamic x) {
      final s = st(x);
      return !isMu(x) && !CompStatus.isNegative(s) && (s.contains('in-person') || s.contains('inperson') || s == 'ip');
    }
    bool isOn(dynamic x) {
      final s = st(x);
      return !isMu(x) && !isIp(x) && !CompStatus.isNegative(s) && (s.contains('online') || s.contains('on-line'));
    }
    bool isAb(dynamic x) => CompStatus.isNegative(st(x));

    int ip = per(logsList.where(isIp).length);
    int on = per(logsList.where(isOn).length);
    int mu = per(logsList.where(isMu).length);
    int att = ip + on + mu;
    int ab = n > att ? (n - att) : per(logsList.where(isAb).length);

    return {
      "n": n,
      "att": att,
      "pct": n > 0 ? (att / n * 100) : 0.0,
      "ip": ip,
      "ipp": n > 0 ? (ip / n * 100) : 0.0,
      "on": on,
      "onp": n > 0 ? (on / n * 100) : 0.0,
      "mu": mu,
      "mup": n > 0 ? (mu / n * 100) : 0.0,
      "ab": ab,
      "abp": n > 0 ? (ab / n * 100) : 0.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final activeLogs = _filteredLogs;
    final Map<String, dynamic> totS = _calc(activeLogs, officialMembers: _effectiveMembers.isNotEmpty ? _effectiveMembers : null, sessions: _sessions);

    return Column(children: [
      _buildToolbar(),
      _section(_sessions > 1 ? "Education table summary (average of $_sessions weeks)" : "Education table summary", _buildExcelGrid(totS), context),
      const SizedBox(height: 8),
      _section("Participation visualization", _buildChart(totS), context),
    ]);
  }

  Widget _buildToolbar() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(children: [
        IconButton(onPressed: _printReport, icon: Icon(Icons.print, color: AppPalette.fg(Colors.blueGrey), size: 18)),
        IconButton(onPressed: () {}, icon: Icon(Icons.download, color: AppPalette.fg(Colors.green), size: 18)),
        const SizedBox(width: 8),

        if (widget.timePeriod != "Current status")
          Container(
            height: 28,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AppPalette.bg(const Color(0xFFF3E5F5)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppPalette.line(Colors.purple.shade200)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _eduDayTab("Sun", "Sun Edu"),
                _eduDayTab("Wed", "Wed Edu"),
              ],
            ),
          ),
      ]),
    ],
  );

  Widget _eduDayTab(String key, String label) {
    final isSel = _selectedEduDay == key;
    return InkWell(
      onTap: () {
        if (_selectedEduDay != key) {
          setState(() => _selectedEduDay = key);
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AppPalette.bg(isSel ? pPurple : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: GoogleFonts.merriweather(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppPalette.fg(isSel ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildExcelGrid(Map<String, dynamic> tot) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availWidth = constraints.maxWidth;
        final double baseWidth = lw * 2 + baseCw * 11;
        final double effectiveCw = availWidth > baseWidth
            ? (availWidth - (lw * 2)) / 11.0
            : baseCw;
        final double effectiveTotalWidth = lw * 2 + effectiveCw * 11;

        Widget? childRows = _buildDynamicHierarchicalRows(effectiveCw);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 15),
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

  // Strictly stops at Cell status (No member rows)
  // Same members/logs the chart uses, for the chart helpers above
  List<Map<String, dynamic>> get _chartMembers => _effectiveMembers;
  List<dynamic> get _chartLogs => _filteredLogs;

  // One row per unit at the selected level. Uses the same unit list as the
  // chart (CompLevel.orderedUnits), so table rows and chart bars match.
  Widget? _buildDynamicHierarchicalRows(double colW) {
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
    return _mergedBlock(label, calculatedBlocks, colW);
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
          _cell("Summary", w: colW * 11, h: hh, b: true, bg: const Color(0xFFF8FAFC)),
        ]),
        Row(children: [
          _cell("Overall metrics", w: colW * 3, h: hh, b: true),
          _cell("In-person", w: colW * 2, h: hh, b: true),
          _cell("Online", w: colW * 2, h: hh, b: true),
          _cell("Makeup", w: colW * 2, h: hh, b: true),
          _cell("Absentees", w: colW * 2, h: hh, b: true),
        ]),
        Row(children: [
          _cell("Num", w: colW, h: sh), _cell("Att", w: colW, h: sh), _cell("%", w: colW, h: sh),
          _cell("Total", w: colW, h: sh), _cell("%", w: colW, h: sh),
          _cell("Total", w: colW, h: sh), _cell("%", w: colW, h: sh),
          _cell("Total", w: colW, h: sh), _cell("%", w: colW, h: sh),
          _cell("Total", w: colW, h: sh), _cell("%", w: colW, h: sh),
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

  Widget _dataRow(String label, Map<String, dynamic> d, double colW, {bool b = false}) {
    return Row(children: [
      _cell(label, w: lw, h: rh, b: b, a: Alignment.center),
      _cell("${d['n']}", w: colW, a: Alignment.center),
      _cell("${d['att']}", w: colW, a: Alignment.center),
      _cell("${d['pct'].toStringAsFixed(1)}%", w: colW, b: true, a: Alignment.center),
      _cell("${d['ip']}", w: colW, a: Alignment.center),
      _cell("${d['ipp'].toStringAsFixed(1)}%", w: colW, a: Alignment.center),
      _cell("${d['on']}", w: colW, a: Alignment.center),
      _cell("${d['onp'].toStringAsFixed(1)}%", w: colW, a: Alignment.center),
      _cell("${d['mu']}", w: colW, a: Alignment.center),
      _cell("${d['mup'].toStringAsFixed(1)}%", w: colW, a: Alignment.center),
      _cell("${d['ab']}", w: colW, color: Colors.red[800], a: Alignment.center),
      _cell("${d['abp'].toStringAsFixed(1)}%", w: colW, a: Alignment.center),
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

  String _getDynamicXAxisLabel() {
    if (_is24ChurchDept) {
      return widget.userDept.isNotEmpty ? widget.userDept : 'Department Summary';
    }
    return (widget.activeUnitLabel ?? '').isNotEmpty ? widget.activeUnitLabel! : CompLevel.unitTitle(widget.level);
  }

  // TREND CHART: Week 1–5 or Month 1–4
  Widget _buildChart(Map<String, dynamic> totSummary) {
    bool isTrend = widget.timePeriod != "Current status";
    final lvl = widget.level.toLowerCase();
    final activeLogs = _filteredLogs;

    if (!isTrend) {
      String xName = _getDynamicXAxisLabel();
      List<String> keys = _getUnitKeysForLevel(lvl);

      if (keys.isEmpty || keys.length == 1 || _is24ChurchDept) {
        final double nVal = (totSummary['n'] as num?)?.toDouble() ?? 0.0;
        final double attVal = (totSummary['att'] as num?)?.toDouble() ?? 0.0;
        final double ipVal = (totSummary['ip'] as num?)?.toDouble() ?? 0.0;
        final double onVal = (totSummary['on'] as num?)?.toDouble() ?? 0.0;
        final double muVal = (totSummary['mu'] as num?)?.toDouble() ?? 0.0;
        final double abVal = (totSummary['ab'] as num?)?.toDouble() ?? 0.0;

        final double dynamicMaxY = (max(nVal, max(attVal, abVal)) * 1.25).ceilToDouble();

        final List<_AseBarMetric> metrics = [
          _AseBarMetric("Saints (N)", nVal, Colors.grey.shade500),
          _AseBarMetric("Attended", attVal, pPurple),
          _AseBarMetric("In-person", ipVal, Colors.indigo),
          _AseBarMetric("Online", onVal, Colors.teal),
          _AseBarMetric("Make-up", muVal, Colors.orange),
          _AseBarMetric("Absentees", abVal, Colors.red.shade400),
        ];

        return Column(children: [
          Container(
            height: 320,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: BarChart(BarChartData(
              maxY: dynamicMaxY > 0 ? dynamicMaxY : 10,
              borderData: FlBorderData(show: true, border: Border(left: BorderSide(color: AppPalette.line(Colors.black), width: 1.0), bottom: BorderSide(color: AppPalette.line(Colors.black), width: 1.0))),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  axisNameWidget: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(xName, style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                  axisNameSize: 28,
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, m) {
                      int idx = v.toInt();
                      if (idx < 0 || idx >= metrics.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(metrics[idx].label, style: GoogleFonts.merriweather(fontSize: 9.5, fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  axisNameWidget: Text("Persons", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold)),
                  axisNameSize: 22,
                  sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, m) => Text("${v.toInt()}", style: GoogleFonts.merriweather(fontSize: 9.5))),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: List.generate(metrics.length, (i) {
                return BarChartGroupData(x: i, barRods: [
                  BarChartRodData(toY: metrics[i].val, color: metrics[i].color, width: 34, borderRadius: BorderRadius.circular(4))
                ]);
              }),
            )),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: metrics.map((m) => _lgItem("${m.label}: ${m.val.toInt()}", m.color)).toList(),
            ),
          ),
        ]);
      }

      Map<String, List<dynamic>> cgLogs = {};
      Map<String, List<dynamic>> cgMembers = {};

      for (var k in keys) {
        cgLogs[k] = [];
        cgMembers[k] = [];
      }

      for (var m in _effectiveMembers) {
        String b = _resolveUnitKeyForRecord(m, lvl);
        if (cgMembers.containsKey(b)) cgMembers[b]!.add(m);
      }
      for (var l in activeLogs) {
        String b = _resolveUnitKeyForRecord(l, lvl);
        if (cgLogs.containsKey(b)) cgLogs[b]!.add(l);
      }

      double maxHeadcount = 10.0;
      for (var key in keys) {
        final s = _calc(cgLogs[key] ?? [], officialMembers: cgMembers[key]);
        final double nVal = (s['n'] as num?)?.toDouble() ?? 0.0;
        final double attVal = (s['att'] as num?)?.toDouble() ?? 0.0;
        final double ipVal = (s['ip'] as num?)?.toDouble() ?? 0.0;
        final double highest = max<double>(nVal, max<double>(attVal, ipVal));
        if (highest > maxHeadcount) maxHeadcount = highest;
      }
      double dynamicMaxY = (maxHeadcount * 1.25).ceilToDouble();

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

    // Historical Trend
    final Set<String> rawDates = {};
    for (var l in activeLogs) {
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
        height: 200, 
        child: Center(
          child: Text(
            "No historical records found for $_selectedEduDay in this period",
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

    final List<String> unitKeys = _getUnitKeysForLevel(lvl);
    final List<Color> palette = [
      pPurple, Colors.blue.shade700, Colors.teal.shade600, Colors.orange.shade800,
      Colors.deepOrange, Colors.pink.shade700, Colors.indigo.shade600, Colors.green.shade800,
      Colors.brown, Colors.amber.shade900, Colors.cyan.shade800, Colors.purpleAccent.shade700, Colors.blueGrey,
    ];

    double maxTrendValue = 10.0;
    final List<LineChartBarData> lineBars = [];

    if (unitKeys.isEmpty || _is24ChurchDept) {
      final List<FlSpot> spots = [];
      for (int d = 0; d < sortedDates.length; d++) {
        final dateStr = sortedDates[d];
        final dateLogs = activeLogs.where((l) => CompPeriod.bucketKey(l, widget.timePeriod) == dateStr).toList();
        final calc = _calc(dateLogs, officialMembers: _effectiveMembers, sessions: CompPeriod.sessionCount(dateLogs));
        double val = _selectedTrendMetric == "General Attendance" ? (calc['att'] as num).toDouble() : (calc['ip'] as num).toDouble();
        if (val > maxTrendValue) maxTrendValue = val;
        spots.add(FlSpot(d.toDouble(), val));
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
          final dateLogs = activeLogs.where((l) {
            final matchesDate = CompPeriod.bucketKey(l, widget.timePeriod) == dateStr;
            final matchesUnit = _resolveUnitKeyForRecord(l, lvl) == unitName;
            return matchesDate && matchesUnit;
          }).toList();

          final calc = _calc(dateLogs, officialMembers: _effectiveMembers, sessions: CompPeriod.sessionCount(dateLogs));
          double val = _selectedTrendMetric == "General Attendance" ? (calc['att'] as num).toDouble() : (calc['ip'] as num).toDouble();
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
    }

    double dynamicMaxY = (maxTrendValue * 1.25).ceilToDouble();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(
              "Trend: $_selectedEduDay Education Sessions (${widget.timePeriod == 'Weekly status' ? 'Weeks 1-5' : 'Months 1-4'})", 
              style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87)), maxLines: 2, overflow: TextOverflow.ellipsis)),
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF3E5F5)), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppPalette.line(Colors.purple.shade200))),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTrendMetric,
                  icon: const Icon(Icons.tune, size: 14),
                  style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)),
                  items: ["General Attendance", "In-person"].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
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
              axisNameWidget: Text(widget.timePeriod == "Weekly status" ? "Weekly Performance (Week 1–5)" : "Education Sessions", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold)),
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
      if (unitKeys.isNotEmpty && !_is24ChurchDept)
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
    if (_is24ChurchDept) return [];
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
        BarChartRodData(toY: (s['ip'] as num).toDouble(), color: Colors.blue.shade600, width: 7, borderRadius: BorderRadius.circular(2)),
      ]);
    }),
  ));

  Widget _buildBarLegend() => Center(
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 20,
      runSpacing: 6,
      children: [
        _lgItem("Saints (Num)", Colors.grey.shade400),
        _lgItem("General Att (Att)", pPurple),
        _lgItem("In-person", Colors.blue.shade600),
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

  Future<void> _printReport() async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Text("All Saints Education Report"))));
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

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

class _AseBarMetric {
  final String label;
  final double val;
  final Color color;
  _AseBarMetric(this.label, this.val, this.color);
}