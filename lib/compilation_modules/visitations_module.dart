// ignore_for_file: camel_case_types, curly_braces_in_flow_control_structures, unused_element, dead_null_aware_expression, unused_import
import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/compilation_rules.dart';
import '../core/table_export.dart';
import '../core/compilation_style.dart';
import 'package:master_admin/core/app_palette.dart';

class VisitationsModule extends StatefulWidget {
  final List<dynamic> logs;
  final List<Map<String, dynamic>>? masterMembers;
  final String level;
  final String category;
  final String timePeriod;
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

  const VisitationsModule({
    super.key,
    required this.logs,
    this.masterMembers,
    required this.level,
    this.category = 'All',
    this.timePeriod = 'Weekly status',
    this.analyticsMode = 'Summary',
    this.groupBy = 'Church',
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
  State<VisitationsModule> createState() => _VisitationsModuleState();
}

class _VisitationsModuleState extends State<VisitationsModule> {
  final Color pPurple = const Color(0xFF4A148C);
  late String _activeCategory;
  String _selectedChartUnit = "General total";

  final List<String> _categories = ["All", "Lta", "H.m", "Offline", "Offering", "Evangelism", "Education"];


  // Headcount comes only from the screen's scoped member list. (The old
  // fallback loaded ALL church members when the scoped list was empty.)
  List<Map<String, dynamic>> get _effectiveMembers => widget.masterMembers ?? const [];

  int get _sessions => widget.timePeriod == "Current status" ? 1 : CompPeriod.sessionCount(widget.logs);

  static const double rh = 24.0;
  static const double hh = 28.0;
  static const double sh = 18.0;
  // Column widths grow with the card so the table fills it, keeping about
  // 1 cm free on each side (set by _buildExcelGrid before the rows are built).
  double _scale = 1.0;
  double get cw => 60.0 * _scale;
  double get lw => 115.0 * _scale;
  static const double _naturalWidth = 115.0 * 2 + 60.0 * 8;
  static const double totalHeaderHeight = hh + hh + sh;

  @override
  void initState() {
    super.initState();
    _activeCategory = (widget.category.isNotEmpty && widget.category.toLowerCase() != 'lta') ? widget.category : "All";
  }

  @override
  void didUpdateWidget(covariant VisitationsModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level ||
        oldWidget.selectedLocation != widget.selectedLocation ||
        oldWidget.selectedSubLocation != widget.selectedSubLocation ||
        oldWidget.selectedDepartment != widget.selectedDepartment ||
        oldWidget.selectedTeam != widget.selectedTeam) {
      _selectedChartUnit = "General total";
    }
  }



  bool _matchCategory(String? dbValue, String target) {
    if (dbValue == null || dbValue.trim().isEmpty) return false;
    final a = dbValue.toLowerCase().replaceAll('.', '').replaceAll(' ', '').trim();
    final b = target.toLowerCase().replaceAll('.', '').replaceAll(' ', '').trim();
    return a == b;
  }

  bool _isPositive(dynamic val) {
    if (val == null) return false;
    final s = val.toString().trim().toLowerCase();
    return s == 'positive' || s == 'pos' || s.startsWith('pos');
  }

  bool _isNegative(dynamic val) {
    if (val == null) return false;
    final s = val.toString().trim().toLowerCase();
    return s == 'negative' || s == 'neg' || s.startsWith('neg');
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

  List<dynamic> _filterLogsByCategory(List<dynamic> list) {
    if (_activeCategory.toLowerCase() == "all") return list;
    return list.where((l) => _matchCategory(l['visitation_reason']?.toString(), _activeCategory)).toList();
  }

  // Visits are counted over the whole period (not averaged); [sessions] is accepted for a shared signature.
  Map<String, dynamic> _calc(List<dynamic> logsList, {List<dynamic>? officialMembers, int sessions = 1}) {
    int n = officialMembers != null ? officialMembers.length : logsList.length;

    // Count PEOPLE visited, not visits: three visits to one member is one
    // person out of the headcount (before, it could push a cell over 100%).
    final catLogs = _filterLogsByCategory(logsList);
    final visitedLogs = catLogs.where((l) {
      final r = (l['visitation_reason'] ?? '').toString().trim();
      final s = (l['status_detail'] ?? '').toString().trim();
      return r.isNotEmpty || s.isNotEmpty;
    }).toList();
    int pos = CompPeriod.distinctMembers(visitedLogs.where((l) => _isPositive(l['status_detail'])));
    int neg = CompPeriod.distinctMembers(visitedLogs.where((l) => _isNegative(l['status_detail'])));
    int visited = CompPeriod.distinctMembers(visitedLogs);
    if (pos + neg > visited) neg = (visited - pos).clamp(0, visited).toInt();

    int couns = logsList.where((l) {
      final r = (l['visitation_reason'] ?? '').toString();
      return _matchCategory(r, 'Education') || _matchCategory(r, 'Lta') || _matchCategory(r, 'LTA');
    }).length;

    return {
      "n": n,
      "visited": visited,
      "visp": n > 0 ? (visited / n * 100) : 0.0,
      "couns": couns,
      "pos": pos,
      "posp": visited > 0 ? (pos / visited * 100) : 0.0,
      "neg": neg,
      "negp": visited > 0 ? (neg / visited * 100) : 0.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    _capRows.clear();
    final Map<String, dynamic> totS = _calc(
      widget.logs,
      officialMembers: _effectiveMembers.isNotEmpty ? _effectiveMembers : null,
    );

    final Map<String, Map<String, dynamic>> blockData = _getCalculatedBlocksMap();

    Map<String, dynamic> activeChartData = totS;
    if (_selectedChartUnit != "General total" && blockData.containsKey(_selectedChartUnit)) {
      activeChartData = blockData[_selectedChartUnit]!;
    }

    return Column(children: [
      _buildToolbar(),
      _buildCategoryPillBar(),
      const SizedBox(height: 8),
      _section("Member care & visitations summary ($_activeCategory)", _buildExcelGrid(totS), context),
      const SizedBox(height: 8),
      _section(
        "Outcomes 3D pizza chart - $_selectedChartUnit",
        _buildPizzaSection(totS, blockData, activeChartData),
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

  Widget _buildCategoryPillBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppPalette.line(Colors.black), width: 1.0)),
    child: Row(children: [
      Text("Category: ", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple))),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _categories.map((cat) {
              final isSel = _activeCategory.toLowerCase() == cat.toLowerCase();
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () => setState(() => _activeCategory = cat),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppPalette.bg(isSel ? pPurple : const Color(0xFFF1F5F9)), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppPalette.line(isSel ? Colors.black : Colors.black26))),
                    child: Text(cat, style: GoogleFonts.merriweather(fontSize: 10, fontWeight: isSel ? FontWeight.bold : FontWeight.w600, color: AppPalette.fg(isSel ? Colors.white : Colors.black87))),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    ]),
  );

  Widget _buildExcelGrid(Map<String, dynamic> tot) => LayoutBuilder(builder: (context, constraints) {
        final double avail = constraints.maxWidth.isFinite ? constraints.maxWidth - 2 * CompStyle.tableSideMargin : _naturalWidth;
        _scale = avail > _naturalWidth ? avail / _naturalWidth : 1.0;
        return _buildExcelGridScaled(tot);
      });

  Widget _buildExcelGridScaled(Map<String, dynamic> tot) {
    Widget? childRows = _buildDynamicHierarchicalRows();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(_scale > 1.0 ? CompStyle.tableSideMargin : 0, 0, _scale > 1.0 ? CompStyle.tableSideMargin : 0, 12),
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
  List<Map<String, dynamic>> get _chartMembers => _effectiveMembers;
  List<dynamic> get _chartLogs => widget.logs;

  // One entry per unit at the selected level; the table, the unit chips and
  // the charts all read this map, so they always show the same units.
  Map<String, Map<String, dynamic>> _getCalculatedBlocksMap() {
    final members = _chartMembers;
    final activeLogs = _chartLogs;
    final keys = CompLevel.orderedUnits(members, activeLogs, widget.level);
    final groupedLogs = CompLevel.groupBy(activeLogs, widget.level);
    final groupedMembers = CompLevel.groupBy(members, widget.level);
    final int sessions = 1;

    final Map<String, Map<String, dynamic>> calculatedBlocks = {};
    for (final k in keys) {
      calculatedBlocks[k] = _calc(groupedLogs[k] ?? [], officialMembers: groupedMembers[k], sessions: sessions);
    }
    return calculatedBlocks;
  }

  Widget? _buildDynamicHierarchicalRows() {
    final blockData = _getCalculatedBlocksMap();
    // A single unit row would just repeat the General total
    if (blockData.length <= 1) return null;

    String categoryName = widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : "Unit";
    return _mergedBlock(categoryName, blockData);
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
          _cell("Care & Visitation Metrics", w: cw * 8, h: hh, b: true, bg: const Color(0xFFF8FAFC)),
        ]),
        Row(children: [
          _cell("Base", w: cw, h: hh, b: true),
          _cell("Visited", w: cw * 2, h: hh, b: true),
          _cell("Counselled", w: cw, h: hh, b: true),
          _cell("Positive", w: cw * 2, h: hh, b: true),
          _cell("Negative", w: cw * 2, h: hh, b: true),
        ]),
        Row(children: [
          _cell("Saints", w: cw, h: sh),
          _cell("Total", w: cw, h: sh), _cell("%", w: cw, h: sh),
          _cell("Total", w: cw, h: sh),
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
    final unit = (widget.activeUnitLabel).isNotEmpty ? widget.activeUnitLabel : CompLevel.unitTitle(widget.level);
    final heads = <String>[unit, ...['Saints', 'Visited', 'Visited %', 'Counselled', 'Positive', 'Positive %', 'Negative', 'Negative %']];
    return ExportTable(
      title: "Visitations and Counselling – $unit",
      subtitle: "Period: ${widget.timePeriod} · Level: ${widget.level}",
      headers: heads,
      rows: [for (final r in _capRows) r],
    );
  }

  Widget _dataRowRaw(String label, Map<String, dynamic> d, {bool b = false}) {
    return Row(children: [
      _cell(label, w: lw, h: rh, b: b, a: Alignment.center),
      _cell("${d['n']}", a: Alignment.center),
      _cell("${d['visited']}", color: pPurple, b: true, a: Alignment.center),
      _cell("${d['visp'].toStringAsFixed(1)}%", color: pPurple, b: true, a: Alignment.center),
      _cell("${d['couns']}", a: Alignment.center),
      _cell("${d['pos']}", color: Colors.green[800], b: true, a: Alignment.center),
      _cell("${d['posp'].toStringAsFixed(1)}%", color: Colors.green[800], a: Alignment.center),
      _cell("${d['neg']}", color: Colors.red[800], b: true, a: Alignment.center),
      _cell("${d['negp'].toStringAsFixed(1)}%", color: Colors.red[800], a: Alignment.center),
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

  // --- DYNAMIC UNIT SELECTOR + 3D SOLID PIZZA PIE CHART (NO HOLE) ---
  Widget _buildPizzaSection(Map<String, dynamic> totS, Map<String, Map<String, dynamic>> blockData, Map<String, dynamic> chartData) {
    List<String> unitsList = ["General total", ...blockData.keys];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        children: [
          if (unitsList.length > 1)
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
          const SizedBox(height: 10),
          _build3DPizzaVisual(chartData),
        ],
      ),
    );
  }

  Widget _build3DPizzaVisual(Map<String, dynamic> d) {
    int saints = d['n'] as int;
    int visited = d['visited'] as int;
    int pos = d['pos'] as int;
    int neg = d['neg'] as int;
    int pending = math.max(0, saints - visited);

    double visPct = d['visp'] as double;
    double posPct = d['posp'] as double;
    double negPct = d['negp'] as double;
    double pendingPct = saints > 0 ? (pending / saints * 100) : 0.0;

    if (visited == 0 && pos == 0 && neg == 0) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Text(
          "No visitations logged yet for '$_selectedChartUnit' under '$_activeCategory'",
          style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey.shade600), fontStyle: FontStyle.italic),
        ),
      );
    }

    final List<_PizzaSlice> slices = [
      if (pos > 0)
        _PizzaSlice(
          label: "Positive",
          count: pos,
          percentage: posPct,
          topColor: const Color(0xFF10B981),
          sideColor: const Color(0xFF047857),
        ),
      if (neg > 0)
        _PizzaSlice(
          label: "Negative",
          count: neg,
          percentage: negPct,
          topColor: const Color(0xFFEF4444),
          sideColor: const Color(0xFFB91C1C),
        ),
      if (pending > 0)
        _PizzaSlice(
          label: "Pending",
          count: pending,
          percentage: pendingPct,
          topColor: const Color(0xFF94A3B8),
          sideColor: const Color(0xFF475569),
        ),
    ];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _metricPill("Total Saints", "$saints", Colors.blueGrey.shade800),
            const SizedBox(width: 8),
            _metricPill("Visited", "$visited (${visPct.toStringAsFixed(1)}%)", pPurple),
            const SizedBox(width: 8),
            _metricPill("Positive", "$pos (${posPct.toStringAsFixed(1)}%)", Colors.green.shade800),
            const SizedBox(width: 8),
            _metricPill("Negative", "$neg (${negPct.toStringAsFixed(1)}%)", Colors.red.shade800),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 280,
          width: double.infinity,
          child: CustomPaint(
            painter: _3DPizzaPainter(slices: slices),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            _legendDot("Positive ($pos)", const Color(0xFF10B981)),
            _legendDot("Negative ($neg)", const Color(0xFFEF4444)),
            _legendDot("Pending ($pending)", const Color(0xFF94A3B8)),
          ],
        ),
      ],
    );
  }

  Widget _metricPill(String t, String v, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: AppPalette.bg(c.withValues(alpha: 0.08)), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppPalette.line(c.withValues(alpha: 0.3)))),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("$t: ", style: GoogleFonts.merriweather(fontSize: 10, color: AppPalette.fg(Colors.black87))),
        Text(v, style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.w900, color: AppPalette.fg(c))),
      ],
    ),
  );

  Widget _legendDot(String l, Color c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: AppPalette.bg(c), borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(l, style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey.shade800))),
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

class _PizzaSlice {
  final String label;
  final int count;
  final double percentage;
  final Color topColor;
  final Color sideColor;

  _PizzaSlice({
    required this.label,
    required this.count,
    required this.percentage,
    required this.topColor,
    required this.sideColor,
  });
}

class _3DPizzaPainter extends CustomPainter {
  final List<_PizzaSlice> slices;

  _3DPizzaPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty) return;

    final Offset center = Offset(size.width / 2, (size.height / 2) - 10);
    final double radiusX = math.min(130.0, (size.width / 2) - 30);
    final double radiusY = radiusX * 0.65;
    const double depth = 26.0;

    double totalVal = slices.fold(0.0, (sum, s) => sum + s.count);
    if (totalVal == 0) totalVal = 1.0;

    final shadowRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + depth + 10),
      width: (radiusX * 2) + 20,
      height: (radiusY * 2) + 12,
    );
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(shadowRect, shadowPaint);

    double startAngle = -math.pi / 2;
    for (var slice in slices) {
      final sweepAngle = (slice.count / totalVal) * (2 * math.pi);
      _draw3DExtrudedEdge(canvas, center, radiusX, radiusY, depth, startAngle, sweepAngle, slice.sideColor);
      startAngle += sweepAngle;
    }

    startAngle = -math.pi / 2;
    for (var slice in slices) {
      final sweepAngle = (slice.count / totalVal) * (2 * math.pi);

      final slicePath = Path();
      slicePath.moveTo(center.dx, center.dy);

      const int steps = 40;
      for (int i = 0; i <= steps; i++) {
        final double theta = startAngle + (sweepAngle * (i / steps));
        final double x = center.dx + radiusX * math.cos(theta);
        final double y = center.dy + radiusY * math.sin(theta);
        slicePath.lineTo(x, y);
      }
      slicePath.close();

      final slicePaint = Paint()
        ..shader = RadialGradient(
          center: Alignment.topLeft,
          radius: 0.9,
          colors: [
            AppPalette.solid(Color.lerp(slice.topColor, Colors.white, 0.2)!),
            AppPalette.solid(slice.topColor),
          ],
        ).createShader(Rect.fromCenter(center: center, width: radiusX * 2, height: radiusY * 2));
      canvas.drawPath(slicePath, slicePaint);

      final cutBorderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(slicePath, cutBorderPaint);

      final midAngle = startAngle + (sweepAngle / 2);
      final labelX = center.dx + (radiusX * 0.65) * math.cos(midAngle);
      final labelY = center.dy + (radiusY * 0.65) * math.sin(midAngle);

      if (sweepAngle > 0.35) {
        _drawSliceLabel(canvas, Offset(labelX, labelY), "${slice.percentage.toStringAsFixed(0)}%");
      }

      startAngle += sweepAngle;
    }
  }

  void _draw3DExtrudedEdge(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    double depth,
    double startAngle,
    double sweepAngle,
    Color sideColor,
  ) {
    const int steps = 30;
    for (int i = 0; i < steps; i++) {
      final double a1 = startAngle + sweepAngle * (i / steps);
      final double a2 = startAngle + sweepAngle * ((i + 1) / steps);

      if (math.sin(a1) >= -0.05 || math.sin(a2) >= -0.05) {
        final double x1 = center.dx + rx * math.cos(a1);
        final double y1 = center.dy + ry * math.sin(a1);
        final double x2 = center.dx + rx * math.cos(a2);
        final double y2 = center.dy + ry * math.sin(a2);

        final edgePath = Path()
          ..moveTo(x1, y1)
          ..lineTo(x2, y2)
          ..lineTo(x2, y2 + depth)
          ..lineTo(x1, y1 + depth)
          ..close();

        final edgePaint = Paint()..color = sideColor;
        canvas.drawPath(edgePath, edgePaint);
      }
    }
  }

  void _drawSliceLabel(Canvas canvas, Offset pos, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: GoogleFonts.merriweather(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: AppPalette.fg(Colors.white),
          shadows: [
            const Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1.5)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    tp.paint(canvas, Offset(pos.dx - (tp.width / 2), pos.dy - (tp.height / 2)));
  }

  @override
  bool shouldRepaint(covariant _3DPizzaPainter oldDelegate) => true;
}