// ignore_for_file: curly_braces_in_flow_control_structures, unused_element
import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../core/compilation_rules.dart';
import '../core/offering_categories.dart';
import '../core/table_export.dart';
import '../core/compilation_style.dart';
import 'package:master_admin/core/app_palette.dart';

class _OfferingUnitStat {
  final String unitName;
  final int totalSaints;
  final num givers; // members who gave anything in the period (each counted once)
  final Map<String, num> giversBy; // per kind: weekly kinds = average per week, monthly kinds = members in the period
  final Map<String, num> amountBy; // money given in the period, per kind
  final num amount;

  _OfferingUnitStat({
    required this.unitName,
    required this.totalSaints,
    required this.givers,
    required this.giversBy,
    required this.amountBy,
    required this.amount,
  });

  double pct(num v) => totalSaints > 0 ? (v / totalSaints * 100.0) : 0.0;
  double get giversPct => pct(givers);
  double pctOf(String col) => pct(giversBy[col] ?? 0);
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

  /// Offered week shown: 0 = all weeks, 1–5 = that week only.
  int _week = 0;

  /// The reports of the chosen week (all reports for "All weeks").
  List<dynamic> get _logs => _week == 0
      ? widget.logs
      : widget.logs.where((l) => l is Map && OfferingCategories.weekOf(l) == _week).toList();

  // Headcount comes only from the screen's scoped member list. (The old
  // fallback loaded ALL church members when the scoped list was empty.)
  List<Map<String, dynamic>> get _effectiveMembers => widget.masterMembers ?? const [];

  int get _sessions => widget.timePeriod == "Current status" || _week != 0 ? 1 : CompPeriod.sessionCount(_logs);

  static final NumberFormat _money = NumberFormat.decimalPattern();
  List<OfferingCategory> get _cats => OfferingCategories.list;

  @override
  void initState() {
    super.initState();
    // kinds of offering (Weekly, Tithe, Construction, T.G, Rent, HQ …) from Supabase
    OfferingCategories.load().then((_) {
      if (mounted) setState(() {});
    });
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
    final cascadedLogs = _logs.where((l) {
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

      // Weekly kinds (Weekly Offering, Week 1–5): average per week over the
      // weeks THIS unit reported in (one week for "Current status" or a
      // chosen week). Monthly kinds (Tithe, Construction, T.G, Rent, HQ …)
      // are given once a month, so each member who offered in the period
      // is counted once (accumulated).
      final int sessions = widget.timePeriod == "Current status" || _week != 0 ? 1 : CompPeriod.sessionCount(uLogs);
      num per(int v) => CompPeriod.avgPerSession(v, sessions);
      Object who(dynamic l) => l['member_id'] ?? l['members']?['id'] ?? l['id'] ?? l.hashCode;
      int distinct(bool Function(dynamic) f) => uLogs.where(f).map(who).toSet().length;
      final giversBy = <String, num>{
        for (final c in _cats)
          c.column: c.weekly ? per(uLogs.where((l) => _isPaid(l[c.column])).length) : distinct((l) => _isPaid(l[c.column])),
      };
      final amountBy = <String, num>{
        for (final c in _cats) c.column: uLogs.fold<num>(0, (a, l) => a + OfferingCategories.amount(l[c.column])),
      };
      num givers = distinct((l) => _cats.any((c) => _isPaid(l[c.column])));

      final most = giversBy.values.fold<num>(givers, (a, b) => math.max(a, b));
      saints = math.max(saints, most.ceil());

      stats.add(_OfferingUnitStat(
        unitName: u,
        totalSaints: saints,
        givers: givers,
        giversBy: giversBy,
        amountBy: amountBy,
        amount: amountBy.values.fold<num>(0, (a, b) => a + b),
      ));
    }

    return stats;
  }

  _OfferingUnitStat _calculateTotalStat(List<_OfferingUnitStat> stats) {
    int totalSaints = 0;
    num givers = 0;
    final giversBy = <String, num>{for (final c in _cats) c.column: 0};
    final amountBy = <String, num>{for (final c in _cats) c.column: 0};
    for (var s in stats) {
      totalSaints += s.totalSaints;
      givers += s.givers;
      for (final c in _cats) {
        giversBy[c.column] = giversBy[c.column]! + (s.giversBy[c.column] ?? 0);
        amountBy[c.column] = amountBy[c.column]! + (s.amountBy[c.column] ?? 0);
      }
    }
    return _OfferingUnitStat(
      unitName: 'General total',
      totalSaints: totalSaints,
      givers: givers,
      giversBy: giversBy,
      amountBy: amountBy,
      amount: amountBy.values.fold<num>(0, (a, b) => a + b),
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

  Widget _header(String title, double h) => SizedBox(
        height: h,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Text(title,
                style: GoogleFonts.merriweather(color: AppPalette.fg(CompStyle.headerFg), fontSize: CompStyle.headerFont, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis),
          ),
        ),
      );

  /// How many members gave each kind of offering (average per week) and the share of all members.
  Widget _buildOfferingTable(List<_OfferingUnitStat> stats, _OfferingUnitStat totalStat) {
    const double rh = 20.0;
    const double hh = 26.0;
    final cats = _cats;
    final Map<int, double> colWidths = {0: 130, 1: 60, 2: 60, 3: 50};
    for (int k = 0; k < cats.length; k++) {
      colWidths[4 + k * 2] = 55;
      colWidths[5 + k * 2] = 48;
    }
    final headers = [
      widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : "Unit name",
      "Saints", "Offered", "%",
      for (final c in cats) ...[c.short, "%"],
    ];
    List<Widget> cells(_OfferingUnitStat u, double h, {bool total = false}) => [
          _cellText(total ? "General total" : u.unitName, h, isBold: true, color: total ? pPurple : null),
          _cellText("${u.totalSaints}", h, isBold: total),
          _cellText(CompPeriod.fmt(u.givers), h, isBold: true, color: pPurple),
          _cellPercent(u.giversPct, h, pPurple, isBold: total),
          for (final c in cats) ...[
            _cellText(CompPeriod.fmt(u.giversBy[c.column] ?? 0), h, isBold: total),
            _cellPercent(u.pctOf(c.column), h, c.color, isBold: total),
          ],
        ];
    return _fitTable(colWidths, (cols) => Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: cols,
          border: TableBorder.all(color: Colors.black87, width: 1.0),
          children: [
            TableRow(decoration: BoxDecoration(color: AppPalette.bg(CompStyle.headerBg)), children: headers.map((t) => _header(t, hh)).toList()),
            TableRow(decoration: BoxDecoration(color: AppPalette.bg(CompStyle.totalBg)), children: cells(totalStat, 22.0, total: true)),
            // A single unit row would just repeat the General total
            if (stats.length > 1)
              ...stats.asMap().entries.map((e) => TableRow(
                    decoration: BoxDecoration(color: AppPalette.bg(e.key.isEven ? Colors.white : const Color(0xFFF8FAFC))),
                    children: cells(e.value, rh),
                  )),
          ],
        ));
  }

  /// Money given in the period, per kind of offering (consolidated from the treasurers' entries).
  Widget _buildAmountTable(List<_OfferingUnitStat> stats, _OfferingUnitStat totalStat) {
    const double rh = 20.0;
    const double hh = 26.0;
    final cats = _cats;
    final Map<int, double> colWidths = {0: 130};
    for (int k = 0; k < cats.length; k++) {
      colWidths[1 + k] = 92;
    }
    colWidths[1 + cats.length] = 104;
    colWidths[2 + cats.length] = 92;
    final headers = [
      widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : "Unit name",
      for (final c in cats) c.label,
      "Total",
      "Per person offered",
    ];
    List<Widget> cells(_OfferingUnitStat u, double h, {bool total = false}) => [
          _cellText(total ? "General total" : u.unitName, h, isBold: true, color: total ? pPurple : null),
          for (final c in cats) _cellText(_money.format(u.amountBy[c.column] ?? 0), h, isBold: total, color: c.color),
          _cellText(_money.format(u.amount), h, isBold: true, color: pPurple),
          _cellText(u.givers > 0 ? _money.format((u.amount / math.max(1, u.givers)).round()) : '-', h, isBold: total),
        ];
    return _fitTable(colWidths, (cols) => Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: cols,
          border: TableBorder.all(color: Colors.black87, width: 1.0),
          children: [
            TableRow(decoration: BoxDecoration(color: AppPalette.bg(CompStyle.headerBg)), children: headers.map((t) => _header(t, hh)).toList()),
            TableRow(decoration: BoxDecoration(color: AppPalette.bg(CompStyle.totalBg)), children: cells(totalStat, 22.0, total: true)),
            if (stats.length > 1)
              ...stats.asMap().entries.map((e) => TableRow(
                    decoration: BoxDecoration(color: AppPalette.bg(e.key.isEven ? Colors.white : const Color(0xFFF8FAFC))),
                    children: cells(e.value, rh),
                  )),
          ],
        ));
  }

  // weeks in the period (givers are an average per week, amounts are a sum)
  int _sessionsOf(_OfferingUnitStat u) => widget.timePeriod == "Current status" ? 1 : math.max(1, _sessions);

  // --- OFFERED WEEK: toggle (All weeks / Week 1–5) and week comparison ---
  Widget _weekBar() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              segments: [
                const ButtonSegment(value: 0, label: Text("All weeks"), icon: Icon(Icons.calendar_view_month_rounded, size: 16)),
                for (int w = 1; w <= 5; w++) ButtonSegment(value: w, label: Text("Week $w")),
              ],
              selected: {_week},
              onSelectionChanged: (s) => setState(() {
                _week = s.first;
                _selectedChartUnit = 'General total';
              }),
            ),
          ),
        ),
      );

  /// One row per offered week: who gave the weekly offering(s), money per
  /// kind and in total, with the best and the weakest week marked.
  List<Map<String, dynamic>> _weekRows(int saints) {
    final logs = widget.logs.where((l) => l is Map && _matchesCascade(Map<String, dynamic>.from(l))).toList();
    final weekly = _cats.where((c) => c.weekly).toList();
    final rows = <Map<String, dynamic>>[];
    for (int w = 1; w <= 5; w++) {
      final wl = logs.where((l) => OfferingCategories.weekOf(l as Map) == w).toList();
      // the same week of several months is averaged (e.g. Week 1 of Sep and Oct)
      final months = wl.map((l) => (l['report_date'] ?? '').toString().padRight(7).substring(0, 7)).toSet().length;
      final n = months < 1 ? 1 : months;
      final offered = weekly.isEmpty
          ? 0
          : CompPeriod.avgPerSession(wl.where((l) => weekly.any((c) => _isPaid(l[c.column]))).map((l) => l['member_id'] ?? l['id']).length, n);
      final amountBy = {for (final c in _cats) c.column: wl.fold<num>(0, (a, l) => a + OfferingCategories.amount(l[c.column]))};
      rows.add({
        'week': w,
        'reported': wl.isNotEmpty,
        'offered': offered,
        'pct': saints > 0 ? offered / saints * 100 : 0.0,
        'weeklyAmount': weekly.fold<num>(0, (a, c) => a + (amountBy[c.column] ?? 0)),
        'amount': amountBy.values.fold<num>(0, (a, b) => a + b),
        'anyone': wl.where((l) => _cats.any((c) => _isPaid(l[c.column]))).map((l) => l['member_id'] ?? l['id']).toSet().length,
      });
    }
    return rows;
  }

  Widget _buildWeekTable(int saints) {
    final rows = _weekRows(saints);
    final reported = rows.where((r) => r['reported'] == true).toList();
    int? best, worst;
    if (reported.length > 1) {
      reported.sort((a, b) => (b['pct'] as num).compareTo(a['pct'] as num));
      best = reported.first['week'] as int;
      worst = reported.last['week'] as int;
      if ((reported.first['pct'] as num) == (reported.last['pct'] as num)) best = worst = null;
    }
    final avgPct = reported.isEmpty ? 0.0 : reported.fold<double>(0, (a, r) => a + (r['pct'] as num)) / reported.length;
    final weeklyName = _cats.where((c) => c.weekly).map((c) => c.short).join(' + ');
    const double rh = 22, hh = 30;
    final headers = ["Offered week", "$weeklyName offered", "%", "$weeklyName (UGX)", "All kinds (UGX)", "Offered anything", "Result"];
    List<Widget> cells(Map<String, dynamic> r) {
      final w = r['week'] as int;
      final tag = !(r['reported'] as bool) ? 'No reports' : w == best ? 'Best week' : w == worst ? 'Weakest week' : '';
      final c = w == best ? const Color(0xFF2E7D32) : w == worst ? Colors.red.shade700 : null;
      return [
        _cellText("Week $w", rh, isBold: true, color: c),
        _cellText(CompPeriod.fmt(r['offered']), rh, isBold: true),
        _cellPercent((r['pct'] as num).toDouble(), rh, c ?? pPurple),
        _cellText(_money.format(r['weeklyAmount']), rh),
        _cellText(_money.format(r['amount']), rh, isBold: true, color: pPurple),
        _cellText("${r['anyone']}", rh),
        _cellText(tag, rh, isBold: tag.isNotEmpty, color: c ?? Colors.blueGrey),
      ];
    }

    final all = rows.fold<num>(0, (a, r) => a + (r['amount'] as num));
    final allWeekly = rows.fold<num>(0, (a, r) => a + (r['weeklyAmount'] as num));
    return Column(children: [
      _fitTable({0: 95, 1: 95, 2: 60, 3: 110, 4: 110, 5: 90, 6: 105}, (cols) => Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: cols,
            border: TableBorder.all(color: Colors.black87, width: 1.0),
            children: [
              TableRow(decoration: BoxDecoration(color: AppPalette.bg(CompStyle.headerBg)), children: headers.map((t) => _header(t, hh)).toList()),
              for (final r in rows)
                TableRow(
                  decoration: BoxDecoration(
                      color: AppPalette.bg(r['week'] == best
                          ? const Color(0xFFE8F5E9)
                          : r['week'] == worst
                              ? const Color(0xFFFFEBEE)
                              : Colors.white)),
                  children: cells(r),
                ),
              TableRow(decoration: BoxDecoration(color: AppPalette.bg(CompStyle.totalBg)), children: [
                _cellText("Overall", 24, isBold: true, color: pPurple),
                _cellText("avg", 24, isBold: true),
                _cellPercent(avgPct, 24, pPurple, isBold: true),
                _cellText(_money.format(allWeekly), 24, isBold: true),
                _cellText(_money.format(all), 24, isBold: true, color: pPurple),
                _cellText("$saints saints", 24, isBold: true),
                _cellText("${reported.length} of 5 weeks", 24, isBold: true),
              ]),
            ],
          )),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Text(
          "$weeklyName is given every week; ${_cats.where((c) => !c.weekly).map((c) => c.short).join(', ')} once a month, so in the other tables each member who offered them in the period is counted once.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700)),
        ),
      ),
    ]);
  }

  ExportTable _exportWeeks(int saints) => ExportTable(
        title: "Offering by week – ${widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : widget.level}",
        subtitle: _exportSubtitle,
        headers: const ['Offered week', 'Weekly offered', '%', 'Weekly (UGX)', 'All kinds (UGX)', 'Offered anything'],
        rows: [
          for (final r in _weekRows(saints))
            ['Week ${r['week']}', CompPeriod.fmt(r['offered']), '${(r['pct'] as num).toStringAsFixed(1)}%', _money.format(r['weeklyAmount']), _money.format(r['amount']), '${r['anyone']}'],
        ],
      );

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
    final cascadedLogs = _logs.where((l) {
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
                children: [for (final c in _cats) _legItem(c.short, c.color)],
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
              lineBarsData: [for (final c in _cats) _lineData(sortedDates, timeMap, c.column, c.color)],
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
            "Saints: ${item.totalSaints} | Offered: ${CompPeriod.fmt(item.givers)} | Amount: ${_money.format(item.amount)}",
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
  String get _exportSubtitle => 'Level: ${widget.level} | Group By: ${widget.groupBy} | Period: ${widget.timePeriod}'
      '${widget.selectedLocation.isNotEmpty ? ' | Loc: ${widget.selectedLocation}' : ''}'
      '${widget.selectedSubLocation.isNotEmpty ? ' | Sub: ${widget.selectedSubLocation}' : ''}'
      '${widget.selectedDepartment.isNotEmpty ? ' | Dept: ${widget.selectedDepartment}' : ''}'
      '${widget.selectedTeam.isNotEmpty ? ' | Team: ${widget.selectedTeam}' : ''}';

  ExportTable _exportTable(List<_OfferingUnitStat> stats, _OfferingUnitStat totalStat) {
    List<String> row(_OfferingUnitStat u, String name) => [
          name,
          '${u.totalSaints}',
          CompPeriod.fmt(u.givers),
          '${u.giversPct.toStringAsFixed(0)}%',
          for (final c in _cats) ...[CompPeriod.fmt(u.giversBy[c.column] ?? 0), '${u.pctOf(c.column).toStringAsFixed(0)}%'],
        ];
    return ExportTable(
      title: "Members who offered – ${widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : widget.level}",
      subtitle: _exportSubtitle,
      headers: <String>[
        widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : 'Unit',
        'Saints',
        'Offered',
        'Offered %',
        for (final c in _cats) ...[c.short, '${c.short} %'],
      ],
      rows: <List<String>>[...stats.map((u) => row(u, u.unitName)), row(totalStat, 'General Total')],
    );
  }

  ExportTable _exportAmounts(List<_OfferingUnitStat> stats, _OfferingUnitStat totalStat) {
    List<String> row(_OfferingUnitStat u, String name) => [
          name,
          for (final c in _cats) _money.format(u.amountBy[c.column] ?? 0),
          _money.format(u.amount),
        ];
    return ExportTable(
      title: "Offering amounts – ${widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : widget.level}",
      subtitle: _exportSubtitle,
      headers: <String>[widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : 'Unit', for (final c in _cats) c.label, 'Total'],
      rows: <List<String>>[...stats.map((u) => row(u, u.unitName)), row(totalStat, 'General Total')],
    );
  }

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
    final List<_OfferingUnitStat> unitStats = _calculateStats();
    final _OfferingUnitStat totalStat = _calculateTotalStat(unitStats);

    return Column(
      children: [
        if (widget.analyticsMode == 'Ranking') ...[
          _section(
            "Top offering units",
            _buildRankingList(unitStats, true),
            context,
          ),
          _section(
            "Units requiring financial counseling",
            _buildRankingList(unitStats, false),
            context,
          ),
        ] else ...[
          _weekBar(),
          _section(
            "Offering by week (Week 1–5)",
            _buildWeekTable(totalStat.totalSaints),
            context,
            onPdf: () => TableExport.showMenu(context, () => _exportWeeks(totalStat.totalSaints)),
          ),
          const SizedBox(height: 10),
          _section(
            _week == 0 ? "Offering amounts (UGX)" : "Offering amounts (UGX) – Week $_week",
            _buildAmountTable(unitStats, totalStat),
            context,
            onPdf: () => TableExport.showMenu(context, () => _exportAmounts(unitStats, totalStat)),
          ),
          const SizedBox(height: 10),
          _section(
            _week == 0 ? "Members who offered" : "Members who offered – Week $_week",
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