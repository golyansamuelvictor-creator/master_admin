import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/compilation_rules.dart';
import '../core/compilation_style.dart';
import '../core/i18n.dart';
import '../core/table_export.dart';

/// Section frame of the compilation module (title, export, full screen).
typedef GoalsSection = Widget Function(String title, Widget content, {VoidCallback? onExport});

/// Evangelism › Results By Units: Goals vs current results.
///
///  * Summary table (centred): for every stage of `evangelism_stages` marked
///    in_results (Chakki, Possible, New BB, Proceeding, Confirmed) the Goal,
///    what was Achieved in the period and the Total = previous total + new
///    results − those who moved on; then Offline and Online with their Goal
///    and Total prospects (the in_prospects stages, New BB … Confirmed).
///  * Tap a unit to go one level down (location › sub-location › department ›
///    team › cell); the path at the top goes back up.
///  * Column charts of Goal vs Current, and line charts over the weeks /
///    months / days of the period when it isn't a single period.
///
/// Numbers come from evangelism_results / evangelism_results_series
/// (14_round13.sql): bb_students, their stage history, the goals set by the
/// Evangelism Department (duty_goals) and the stages table.
class EvangelismGoalsView extends StatefulWidget {
  final DateTime from;
  final DateTime to;
  final String timePeriod;
  final String level; // compilation level (Location status, Team status …)
  final String location, subLocation, department, team;
  final GoalsSection section;

  const EvangelismGoalsView({
    super.key,
    required this.from,
    required this.to,
    required this.timePeriod,
    required this.level,
    required this.section,
    this.location = '',
    this.subLocation = '',
    this.department = '',
    this.team = '',
  });

  @override
  State<EvangelismGoalsView> createState() => _EvangelismGoalsViewState();
}

class _EvangelismGoalsViewState extends State<EvangelismGoalsView> {
  static const Color _purple = Color(0xFF4A148C);
  static const _groups = ['church', 'location', 'sub_location', 'department', 'team', 'cell'];
  static const _groupNames = ['Church', 'Location', 'Sub-location', 'Department', 'Team', 'Cell'];
  static final _f = DateFormat('yyyy-MM-dd');

  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _series = [];
  String? _error;
  bool _loading = true;

  /// The unit opened by tapping a row: its full path (location, sub-location,
  /// …) from the data; empty = the compilation screen's own selection.
  List<String> _drill = [];
  String _chartUnit = 'General total';
  bool _lineTotals = false; // line chart: new results (false) or totals (true)

  /// The unit path of the compilation screen (its pickers and the leader's
  /// own units): location, sub-location, department, team. A level may be
  /// blank while a lower one is set (a location leader at Cell status picks
  /// only the sub-location, department and team; the location is theirs).
  /// Before, the path stopped at the first blank level, so those picks were
  /// dropped and the Cell status tables came out wrong or empty.
  List<String?> get _base {
    String? v(String s) => s.trim().isEmpty || const {'All', 'Church Wide', 'Sub-location status', 'Dept status', 'Team status', 'N/A'}.contains(s.trim()) ? null : s.trim();
    return [v(widget.location), v(widget.subLocation), v(widget.department), v(widget.team), null];
  }

  /// The unit shown: the opened row, or the compilation screen's selection.
  List<String?> get _fixed => _drill.isNotEmpty ? [..._drill, for (int i = _drill.length; i < 5; i++) null] : _base;

  static int _deepest(List<String?> k) {
    for (int i = k.length - 1; i >= 0; i--) {
      if (k[i] != null) return i + 1;
    }
    return 0;
  }

  int get _baseDepth => _deepest(_base);

  /// The level the rows are grouped by (1 location … 5 cell).
  int get _depth {
    final byLevel = switch (CompLevel.of(widget.level)) {
      CompLevel.subLocation => 2,
      CompLevel.dept => 3,
      CompLevel.team => 4,
      CompLevel.cell => 5,
      _ => 1,
    };
    return math.min(5, math.max(byLevel, _deepest(_fixed) + 1));
  }

  /// Day / week / month buckets for the line chart; null for a single period.
  String? get _bucket {
    if (widget.timePeriod == 'Current status') return null;
    if (widget.timePeriod == 'Weekly status') return 'week';
    if (widget.timePeriod == 'Monthly status') return 'month';
    final days = widget.to.difference(widget.from).inDays;
    if (days < 1) return null;
    if (days <= 14) return 'day';
    if (days <= 120) return 'week';
    return 'month';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EvangelismGoalsView old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from ||
        old.to != widget.to ||
        old.level != widget.level ||
        old.location != widget.location ||
        old.subLocation != widget.subLocation ||
        old.department != widget.department ||
        old.team != widget.team ||
        old.timePeriod != widget.timePeriod) {
      _drill = [];
      _chartUnit = 'General total';
      _load();
    }
  }

  Map<String, dynamic> get _params {
    final k = _fixed;
    String? at(int i) => k[i];
    return {
      'p_from': _f.format(widget.from),
      'p_to': _f.format(widget.to),
      'p_location': at(0),
      'p_sub': at(1),
      'p_dept': at(2),
      'p_team': at(3),
      'p_cell': at(4),
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final db = Supabase.instance.client;
    try {
      final b = _bucket;
      final r = await Future.wait<dynamic>([
        db.rpc('evangelism_results', params: {..._params, 'p_group': _groups[_depth]}),
        if (b != null) db.rpc('evangelism_results_series', params: {..._params, 'p_bucket': b}),
      ]);
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(r[0] as Map);
        _series = r.length > 1 ? List<Map<String, dynamic>>.from((r[1] as List).map((e) => Map<String, dynamic>.from(e as Map))) : [];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't compile the results (run 14_round13.sql): ${e is PostgrestException ? e.message : e}";
        });
      }
    }
  }

  void _open(Map<String, dynamic> row) {
    if (_depth >= 5) return;
    final keys = List<String>.from((row['keys'] as List? ?? const []).map((e) => (e ?? '').toString()));
    if (keys.length <= _deepest(_fixed) || keys.any((k) => k.isEmpty)) return;
    setState(() {
      _drill = keys;
      _chartUnit = 'General total';
    });
    _load();
  }

  // ---- data helpers

  List<Map<String, dynamic>> get _stages => List<Map<String, dynamic>>.from(((_data?['stages'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
  List<Map<String, dynamic>> get _rows => List<Map<String, dynamic>>.from(((_data?['rows'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
  Map<String, dynamic> get _total => Map<String, dynamic>.from((_data?['total'] as Map?) ?? const {});

  static Color _hex(dynamic h) {
    final v = int.tryParse((h ?? '').toString().replaceAll('#', ''), radix: 16);
    return v == null ? _purple : Color(0xFF000000 | v);
  }

  static num? _num(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');
  static String _fmt(dynamic v) => v == null ? '—' : CompPeriod.fmt(_num(v) ?? 0);

  Map<String, dynamic> _st(Map<String, dynamic> row, String stage) => Map<String, dynamic>.from(((row['stages'] as Map?) ?? const {})[stage] as Map? ?? const {});
  Map<String, dynamic> _mode(Map<String, dynamic> row, String m) => Map<String, dynamic>.from((row[m] as Map?) ?? const {});

  // ---- summary table

  static const double _unitW = 150, _subW = 62, _rowH = 26, _headH = 28;

  Widget _cell(String t, double w, {double h = _rowH, Color? bg, Color? fg, bool bold = false, String? tip, int lines = 1}) {
    final box = Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(color: bg == null ? null : AppPalette.bg(bg), border: Border.all(color: AppPalette.line(Colors.black87), width: 0.5)),
      child: Text(t,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.merriweather(fontSize: 10, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: AppPalette.fg(fg ?? Colors.black87))),
    );
    return tip == null ? box : Tooltip(message: tip, child: box);
  }

  /// Green when the total reaches the goal, red when below it.
  Color? _vsGoal(dynamic total, dynamic goal) {
    final g = _num(goal), t = _num(total) ?? 0;
    if (g == null || g <= 0) return null;
    return t >= g ? const Color(0xFF2E7D32) : Colors.red.shade700;
  }

  List<Widget> _rowCells(Map<String, dynamic> row, {bool total = false, Color? bg}) {
    final out = <Widget>[];
    for (final s in _stages) {
      final name = s['stage'].toString();
      final v = _st(row, name);
      out.addAll([
        _cell(_fmt(v['goal']), _subW, bg: bg, bold: total),
        _cell(_fmt(v['new'] ?? 0), _subW, bg: bg, bold: total),
        _cell(_fmt(v['total'] ?? 0), _subW,
            bg: bg,
            bold: true,
            fg: _vsGoal(v['total'], v['goal']),
            tip: "Previous ${_fmt(v['prev'] ?? 0)} + new ${_fmt(v['new'] ?? 0)} − moved on ${_fmt(v['moved'] ?? 0)}"),
      ]);
    }
    for (final m in const ['offline', 'online']) {
      final v = _mode(row, m);
      out.addAll([
        _cell(_fmt(v['goal']), _subW, bg: bg, bold: total),
        _cell(_fmt(v['total'] ?? 0), _subW + 10, bg: bg, bold: true, fg: _vsGoal(v['total'], v['goal'])),
      ]);
    }
    return out;
  }

  Widget _summaryTable() {
    final stages = _stages;
    final head1 = <Widget>[
      _cell(_groupNames[_depth], _unitW, h: _headH * 2, bg: CompStyle.headerBg, fg: CompStyle.headerFg, bold: true, lines: 2),
    ];
    final head2 = <Widget>[];
    for (final s in stages) {
      head1.add(_cell(s['stage'].toString(), _subW * 3, h: _headH, bg: _hex(s['color']), fg: Colors.white, bold: true));
      head2.addAll([
        _cell("Goal", _subW, h: _headH, bg: const Color(0xFF334155), fg: Colors.white, bold: true),
        _cell("Achieved", _subW, h: _headH, bg: const Color(0xFF334155), fg: Colors.white, bold: true),
        _cell("Total", _subW, h: _headH, bg: const Color(0xFF334155), fg: Colors.white, bold: true),
      ]);
    }
    for (final m in const ["Offline", "Online"]) {
      head1.add(_cell(m, _subW * 2 + 10, h: _headH, bg: m == "Offline" ? const Color(0xFF5D4037) : const Color(0xFF1565C0), fg: Colors.white, bold: true));
      head2.addAll([
        _cell("Goal", _subW, h: _headH, bg: const Color(0xFF334155), fg: Colors.white, bold: true),
        _cell("Total prospects", _subW + 10, h: _headH, bg: const Color(0xFF334155), fg: Colors.white, bold: true, lines: 2),
      ]);
    }
    final rows = _rows;
    final canOpen = _depth < 5;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: box.maxWidth),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  head1.first,
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: head1.sublist(1)),
                    Row(mainAxisSize: MainAxisSize.min, children: head2),
                  ]),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _cell("General total", _unitW, bg: CompStyle.totalBg, fg: _purple, bold: true),
                  ..._rowCells(_total, total: true, bg: CompStyle.totalBg),
                ]),
                for (int i = 0; i < rows.length; i++)
                  InkWell(
                    onTap: canOpen ? () => _open(rows[i]) : null,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _cell(rows[i]['unit'].toString(), _unitW,
                          bg: i.isEven ? Colors.white : const Color(0xFFF8FAFC),
                          bold: true,
                          fg: canOpen ? _purple : null,
                          tip: canOpen ? "Open ${rows[i]['unit']} (${_groupNames[_depth + 1].toLowerCase()} level)" : null),
                      ..._rowCells(rows[i], bg: i.isEven ? Colors.white : const Color(0xFFF8FAFC)),
                    ]),
                  ),
                if (rows.isEmpty)
                  Padding(padding: const EdgeInsets.all(16), child: Text("No BB students in this unit yet.", style: TextStyle(color: AppPalette.fg(Colors.grey)))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  ExportTable _export() {
    final stages = _stages.map((s) => s['stage'].toString()).toList();
    List<String> line(Map<String, dynamic> r, String name) => [
          name,
          for (final s in stages) ...[_fmt(_st(r, s)['goal']), _fmt(_st(r, s)['new'] ?? 0), _fmt(_st(r, s)['total'] ?? 0)],
          for (final m in const ['offline', 'online']) ...[_fmt(_mode(r, m)['goal']), _fmt(_mode(r, m)['total'] ?? 0)],
        ];
    return ExportTable(
      title: "Evangelism results by units – goals vs current",
      subtitle: "${_path()} · ${DateFormat('d MMM').format(widget.from)} – ${DateFormat('d MMM yyyy').format(widget.to)}",
      headers: [
        _groupNames[_depth],
        for (final s in stages) ...["$s Goal", "$s Achieved", "$s Total"],
        "Offline Goal",
        "Offline Total prospects",
        "Online Goal",
        "Online Total prospects",
      ],
      rows: [line(_total, 'General total'), for (final r in _rows) line(r, r['unit'].toString())],
    );
  }

  String _path() {
    final k = _fixed.whereType<String>().toList();
    return k.isEmpty ? 'Whole church' : k.join(' › ');
  }

  Widget _breadcrumb() {
    final chips = <Widget>[
      ActionChip(
        avatar: const Icon(Icons.home_rounded, size: 16),
        label: Text(_base.whereType<String>().isEmpty ? "Whole church" : _base.whereType<String>().join(' › ')),
        onPressed: _drill.isEmpty
            ? null
            : () {
                setState(() => _drill = []);
                _load();
              },
      ),
    ];
    for (int i = _baseDepth; i < _drill.length; i++) {
      chips.add(const Icon(Icons.chevron_right_rounded, size: 18));
      chips.add(ActionChip(
        label: Text(_drill[i]),
        onPressed: i == _drill.length - 1
            ? null
            : () {
                setState(() => _drill = i + 1 <= _baseDepth ? [] : _drill.sublist(0, i + 1));
                _load();
              },
      ));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 4, children: [
        ...chips,
        Text("  ·  ${_groupNames[_depth]} level${_depth < 5 ? ' · tap a unit to open it' : ''}", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
      ]),
    );
  }

  // ---- column chart: Goal vs Current

  Widget _unitPills() {
    final units = ['General total', ..._rows.map((r) => r['unit'].toString())];
    if (units.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 42,
      child: Center(
        child: ListView(
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          children: [
            for (final u in units)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(u, style: const TextStyle(fontSize: 11)),
                  selected: _chartUnit == u,
                  onSelected: (_) => setState(() => _chartUnit = u),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _columnChart() {
    final row = _chartUnit == 'General total' ? _total : _rows.firstWhere((r) => r['unit'] == _chartUnit, orElse: () => _total);
    final groups = <(String, Color, num?, num)>[
      for (final s in _stages)
        (s['stage'].toString(), _hex(s['color']), _num(_st(row, s['stage'].toString())['goal']), _num(_st(row, s['stage'].toString())['total']) ?? 0),
      ("Offline", const Color(0xFF5D4037), _num(_mode(row, 'offline')['goal']), _num(_mode(row, 'offline')['total']) ?? 0),
      ("Online", const Color(0xFF1565C0), _num(_mode(row, 'online')['goal']), _num(_mode(row, 'online')['total']) ?? 0),
    ];
    final maxV = groups.fold<double>(1, (a, g) => math.max(a, math.max((g.$3 ?? 0).toDouble(), g.$4.toDouble())));
    final maxY = (maxV * 1.2).ceilToDouble();
    return Column(children: [
      _unitPills(),
      Wrap(alignment: WrapAlignment.center, spacing: 14, children: [
        _legend("Goal", Colors.blueGrey.shade300),
        _legend("Current (total)", _purple),
      ]),
      SizedBox(
        height: 260,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.black12, strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                    "${groups[g.x].$1}\n${ri == 0 ? 'Goal' : 'Current'}: ${ri == 0 ? (groups[g.x].$3 == null ? '—' : CompPeriod.fmt(groups[g.x].$3!)) : CompPeriod.fmt(groups[g.x].$4)}",
                    const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= groups.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(groups[i].$1, style: GoogleFonts.merriweather(fontSize: 9.5, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (int i = 0; i < groups.length; i++)
                  BarChartGroupData(x: i, barsSpace: 3, barRods: [
                    BarChartRodData(toY: (groups[i].$3 ?? 0).toDouble(), width: 12, color: Colors.blueGrey.shade300, borderRadius: BorderRadius.circular(3)),
                    BarChartRodData(toY: groups[i].$4.toDouble(), width: 12, color: groups[i].$2, borderRadius: BorderRadius.circular(3)),
                  ]),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _legend(String t, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(t, style: const TextStyle(fontSize: 11)),
      ]);

  // ---- line chart over the period

  String _bucketLabel(int i, Map<String, dynamic> b) {
    final d = DateTime.tryParse((b['start'] ?? '').toString()) ?? widget.from;
    return switch (_bucket) {
      'week' => "W${i + 1}\n${DateFormat('d MMM').format(d)}",
      'month' => DateFormat('MMM yy').format(d),
      _ => DateFormat('d MMM').format(d),
    };
  }

  Widget _lineChart() {
    final stages = _stages;
    if (_series.length < 2) {
      return const SizedBox(height: 80, child: Center(child: Text("The period has only one week / month so far.")));
    }
    final key = _lineTotals ? 'total' : 'new';
    double maxV = 1;
    final lines = <LineChartBarData>[];
    for (final s in stages) {
      final name = s['stage'].toString();
      final spots = <FlSpot>[];
      for (int i = 0; i < _series.length; i++) {
        final v = (_num(((_series[i]['stages'] as Map?)?[name] as Map?)?[key]) ?? 0).toDouble();
        maxV = math.max(maxV, v);
        spots.add(FlSpot(i.toDouble(), v));
      }
      lines.add(LineChartBarData(spots: spots, color: _hex(s['color']), barWidth: 2.5, isCurved: true, preventCurveOverShooting: true, dotData: const FlDotData(show: true)));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: false, label: Text("New results")),
            ButtonSegment(value: true, label: Text("Totals")),
          ],
          selected: {_lineTotals},
          onSelectionChanged: (v) => setState(() => _lineTotals = v.first),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 4, children: [for (final s in stages) _legend(s['stage'].toString(), _hex(s['color']))]),
      ),
      SizedBox(
        height: 260,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 20, 8),
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: (maxV * 1.2).ceilToDouble(),
              lineBarsData: lines,
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.black12, strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: 1,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= _series.length || v != i.toDouble()) return const SizedBox.shrink();
                      if (_series.length > 12 && i % (_series.length ~/ 8) != 0) return const SizedBox.shrink();
                      return Padding(padding: const EdgeInsets.only(top: 4), child: Text(_bucketLabel(i, _series[i]), style: const TextStyle(fontSize: 9), textAlign: TextAlign.center));
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    if (_error != null) return Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(_error!, textAlign: TextAlign.center)));
    final period = "${DateFormat('d MMM').format(widget.from)} – ${DateFormat('d MMM yyyy').format(widget.to)}";
    final b = _bucket;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      widget.section(
        "Summary: goals vs current results · $period",
        Column(children: [
          _breadcrumb(),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          _summaryTable(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Text(
              "Achieved = reached the stage in the period · Total = previous total + new results − those who moved on · Total prospects = ${(_data?['prospects'] as List? ?? const []).join(', ')} · "
              "goals are set by the Evangelism Department (a unit without its own goal shows the sum of its units' goals) · each student counts in the unit of their guide",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.grey.shade700)),
            ),
          ),
        ]),
        onExport: () => TableExport.showMenu(context, _export),
      ),
      const SizedBox(height: 10),
      widget.section("Goal vs current", _columnChart()),
      if (b != null) ...[
        const SizedBox(height: 10),
        widget.section("${b == 'week' ? 'Weekly' : b == 'month' ? 'Monthly' : 'Daily'} comparison · $period", _lineChart()),
      ],
    ]);
  }
}
