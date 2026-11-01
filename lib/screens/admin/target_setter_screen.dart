// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:master_admin/core/app_palette.dart';

/// Set unit targets — cascading goals.
///
/// The goal comes from the top and is divided down the units:
/// church → location → sub-location / department → team → cell group.
/// Who sets which level is configured in Supabase (goal_setters, 17_round16.sql):
///  - Service Attendance Status: IA maintenance manager → locations, location
///    maintenance manager → sub-locations and departments, sub-location
///    gen. sec → departments, department gen. sec → teams, assistant team
///    leader → cell groups.
///  - Evangelism: Evangelism Department → locations, location evangelism
///    manager → sub-locations and departments, sub-location evangelism team
///    leader → departments, department leader → teams, team leader → cells.
/// The goals are entered in a table for a period (daily, weekly, monthly,
/// 2 or 3 months). The table divides each goal into its segments (per month,
/// week and day) and totals them against the goal of the unit above.
class TargetSetterScreen extends StatefulWidget {
  final String? userRole;
  final List<String>? allowedDuties;
  /// The duty to open first (e.g. Evangelism from the Evangelism panel)
  final String? initialDuty;
  /// Shown inside another screen (the Evangelism panel's Goals tab): no top
  /// bar, and the duty stays the panel's duty.
  final bool embedded;

  const TargetSetterScreen({
    super.key,
    this.userRole,
    this.allowedDuties,
    this.initialDuty,
    this.embedded = false,
    required String userLoc,
    required String userSub,
    required String userDept,
  });

  @override
  State<TargetSetterScreen> createState() => _TargetSetterScreenState();
}

class _Level {
  final String child, parent, note;
  final Map<String, String?> keys; // the parent unit
  const _Level(this.child, this.parent, this.note, this.keys);
}

class _TargetSetterScreenState extends State<TargetSetterScreen> {
  final _db = Supabase.instance.client;
  static const pPurple = Color(0xFF4A148C);
  static const _cascadeDuties = ['Service Attendance Status', 'Evangelism'];
  static const _kinds = ['daily', 'weekly', 'monthly', '2 months', '3 months'];
  static const _levelNames = {
    'church': 'Church',
    'location': 'Locations',
    'sub_location': 'Sub-locations',
    'department': 'Departments',
    'team': 'Teams',
    'cell': 'Cell groups',
  };
  static const _keyOrder = ['location', 'sub_location', 'department', 'team', 'cell_group'];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<String> _duties = [];
  String? _duty;
  final Map<String, List<_Level>> _levels = {};
  List<Map<String, dynamic>> _metrics = [];
  String? _metric;
  String _kind = 'monthly';
  DateTime _start = DateTime(DateTime.now().year, DateTime.now().month);

  /// Where the table is: my own level, or a unit I opened from it.
  final List<_Level> _path = [];
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _parentRow;
  final Map<String, TextEditingController> _ctrl = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final res = await Future.wait<dynamic>([
        for (final d in _cascadeDuties) _db.rpc('goal_my_levels', params: {'p_duty': d}),
      ]);
      for (var i = 0; i < _cascadeDuties.length; i++) {
        final list = [
          for (final e in (res[i] as List))
            _Level(
              e['child_level'].toString(),
              e['parent_level'].toString(),
              (e['note'] ?? '').toString(),
              {for (final k in _keyOrder) k: e[k]?.toString()},
            ),
        ];
        // a level whose parent unit is not known (e.g. an administrator with
        // no location) is reached by opening the units from the level above
        bool known(_Level l) {
          if (l.parent == 'church') return true;
          final loc = (l.keys['location'] ?? '').trim().toLowerCase();
          return loc.isNotEmpty && loc != 'n/a' && !loc.startsWith('church');
        }
        list.retainWhere(known);
        if (list.isNotEmpty) _levels[_cascadeDuties[i]] = list;
      }
      _duties = _levels.keys.toList();
      // inside the Evangelism panel: only that duty
      if (widget.embedded && widget.initialDuty != null) _duties = _duties.where((d) => d == widget.initialDuty).toList();
      if (_duties.isEmpty) {
        setState(() {
          _loading = false;
          _error = "Goals are set from the top down. Your role does not set goals for the units below you.";
        });
        return;
      }
      await _selectDuty(_duties.contains(widget.initialDuty) ? widget.initialDuty! : _duties.first);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = "Couldn't load goal setting. Ask the administrator to run 17_round16.sql.\n${e is PostgrestException ? e.message : e}";
      });
    }
  }

  Future<void> _selectDuty(String d) async {
    _duty = d;
    try {
      final m = await _db.from('goal_metrics').select().eq('duty_name', d).order('sort_order');
      _metrics = List<Map<String, dynamic>>.from(m);
      if (d == 'Evangelism') {
        // the stages are goals too (Results By Units)
        final st = await _db.from('evangelism_stages').select('stage').eq('is_active', true).order('sort_order', ascending: true);
        for (final s in st) {
          final name = s['stage'].toString();
          if (!_metrics.any((x) => x['metric'] == name)) _metrics.insert(_metrics.length >= 2 ? 2 : _metrics.length, {'metric': name, 'is_rate': false});
        }
      }
    } catch (_) {
      _metrics = [];
    }
    _metric = _metrics.isNotEmpty ? _metrics.first['metric'].toString() : null;
    _path
      ..clear()
      ..add(_levels[d]!.first);
    await _load();
  }

  bool get _isRate => _metrics.firstWhere((m) => m['metric'] == _metric, orElse: () => const {})['is_rate'] == true;

  int get _daysInMonth => DateTime(_start.year, _start.month + 1, 0).day;

  /// Month value → the value for [kind]
  double _fromMonth(double m, String kind) {
    if (_isRate) return m;
    return switch (kind) {
      'daily' => m / _daysInMonth,
      'weekly' => m * 7 / _daysInMonth,
      '2 months' => m * 2,
      '3 months' => m * 3,
      _ => m,
    };
  }

  /// Value for the chosen period → per month
  double _toMonth(double v) {
    if (_isRate) return v;
    return switch (_kind) {
      'daily' => v * _daysInMonth,
      'weekly' => v * _daysInMonth / 7,
      '2 months' => v / 2,
      '3 months' => v / 3,
      _ => v,
    };
  }

  String _fmt(double? v) {
    if (v == null) return '–';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(v.abs() < 10 ? 1 : 0);
  }

  String _rowKey(Map<String, dynamic> r) => _keyOrder.map((k) => (r[k] ?? '').toString()).join('|');

  Future<void> _load() async {
    final lv = _path.last;
    if (_metric == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _db.rpc('goal_table', params: {
        'p_duty': _duty,
        'p_metric': _metric,
        'p_level': lv.child,
        'p_month': DateFormat('yyyy-MM-dd').format(_start),
        'p_loc': lv.keys['location'],
        'p_sub': lv.keys['sub_location'],
        'p_dept': lv.keys['department'],
        'p_team': lv.keys['team'],
      });
      final all = List<Map<String, dynamic>>.from((res as List).map((e) => Map<String, dynamic>.from(e as Map)));
      for (final c in _ctrl.values) {
        c.dispose();
      }
      _ctrl.clear();
      _parentRow = all.isNotEmpty && all.first['unit_level'] == lv.parent ? all.first : null;
      _rows = all.where((r) => r['unit_level'] == lv.child).toList();
      for (final r in _rows) {
        final m = (r['target'] as num?)?.toDouble();
        final sameKind = r['period_kind'] == _kind && r['period_total'] != null;
        final v = sameKind ? (r['period_total'] as num).toDouble() : (m == null ? null : _fromMonth(m, _kind));
        _ctrl[_rowKey(r)] = TextEditingController(text: v == null ? '' : _fmt(v));
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e is PostgrestException ? e.message : e.toString();
      });
    }
  }

  double? _entered(Map<String, dynamic> r) => double.tryParse((_ctrl[_rowKey(r)]?.text ?? '').trim().replaceAll(',', ''));

  Future<void> _save() async {
    final lv = _path.last;
    final rows = [
      for (final r in _rows)
        if (r['can_edit'] == true)
          {
            for (final k in _keyOrder) k: r[k],
            'value': _ctrl[_rowKey(r)]?.text.trim().replaceAll(',', '') ?? '',
          },
    ];
    if (rows.isEmpty) return;
    setState(() => _saving = true);
    try {
      final n = await _db.rpc('goal_save', params: {
        'p_duty': _duty,
        'p_metric': _metric,
        'p_level': lv.child,
        'p_start': DateFormat('yyyy-MM-dd').format(_start),
        'p_kind': _kind,
        'p_rows': rows,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text("Goals saved for $n ${_levelNames[lv.child]!.toLowerCase()}."),
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text("Couldn't save: ${e is PostgrestException ? e.message : e}"),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The levels below a unit of [level] that can be opened from the table.
  List<String> _below(String level) => switch (level) {
        'location' => ['sub_location', 'department'],
        'sub_location' => ['department'],
        'department' => ['team'],
        'team' => ['cell'],
        _ => const [],
      };

  void _open(Map<String, dynamic> r, String child) {
    final lv = _path.last;
    final keys = <String, String?>{for (final k in _keyOrder) k: null};
    final depth = _keyOrder.indexOf(lv.child == 'cell' ? 'cell_group' : lv.child);
    for (var i = 0; i <= depth && i < 4; i++) {
      keys[_keyOrder[i]] = r[_keyOrder[i]]?.toString();
    }
    setState(() => _path.add(_Level(child, lv.child, '', keys)));
    _load();
  }

  // ==========================================
  // UI
  // ==========================================
  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _body();
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        title: Text("Set unit targets", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple), fontSize: 18)),
        centerTitle: true,
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppPalette.fg(pPurple)),
          onPressed: () {
            if (_path.length > 1) {
              setState(() => _path.removeLast());
              _load();
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    return _duties.isEmpty
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator(color: pPurple)
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error ?? '', textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 13, height: 1.5)),
                    ),
            )
          : LayoutBuilder(builder: (context, c) {
              return SingleChildScrollView(
                // the whole width of the screen, with the usual small margin
                // the whole width, leaving only about 0.5 cm on each side
                padding: const EdgeInsets.fromLTRB(_side, 10, _side, 30),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: double.infinity),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _settingsCard(),
                      const SizedBox(height: 10),
                      _breadcrumb(),
                      const SizedBox(height: 6),
                      if (_loading)
                        const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: pPurple)))
                      else if (_error != null)
                        Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.red.shade800))))
                      else
                        _table(c.maxWidth < 560),
                    ]),
                  ),
                ),
              );
            });
  }

  /// About 0.5 cm on each side of the screen
  static const double _side = 19;

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.line(Colors.grey.shade200)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: child,
      );

  Widget _pick(String label, List<String> items, String? value, ValueChanged<String> onChanged, {String Function(String)? show}) {
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: items.contains(value) ? value : null,
        decoration: InputDecoration(labelText: tr(label), isDense: true, border: const OutlineInputBorder()),
        items: [for (final i in items) DropdownMenuItem(value: i, child: Text(show?.call(i) ?? i, overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _settingsCard() {
    final mine = _levels[_duty] ?? const <_Level>[];
    final lv = _path.first;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppPalette.bg(pPurple.withValues(alpha: 0.10)), borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.track_changes_rounded, size: 18, color: AppPalette.fg(pPurple)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text("Goal settings", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: AppPalette.fg(pPurple))),
            ),
            if (_duty != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppPalette.bg(pPurple), borderRadius: BorderRadius.circular(20)),
                child: Text(_duty!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ]),
        ),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
        if (!widget.embedded) _pick("Duty", _duties, _duty, (v) => _selectDuty(v)),
        if (mine.length > 1)
          _pick("Goals for", [for (var i = 0; i < mine.length; i++) '$i'], '${mine.indexOf(lv)}', (v) {
            setState(() => _path
              ..clear()
              ..add(mine[int.parse(v)]));
            _load();
          }, show: (i) {
            final l = mine[int.parse(i)];
            return "${_levelNames[l.child]} of ${l.parent == 'church' ? 'the church' : 'my ${_levelNames[l.parent]!.toLowerCase().replaceAll(RegExp(r's$'), '')}'}";
          }),
        _pick("What is counted", [for (final m in _metrics) m['metric'].toString()], _metric, (v) {
          setState(() => _metric = v);
          _load();
        }),
        _pick("Goal period", _kinds, _kind, (v) {
          setState(() => _kind = v);
          _load();
        }, show: (k) => k[0].toUpperCase() + k.substring(1)),
        SizedBox(
          width: 200,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: Text(_kind.contains('months')
                ? "${DateFormat('MMM yyyy').format(_start)} – ${DateFormat('MMM yyyy').format(DateTime(_start.year, _start.month + (_kind == '2 months' ? 1 : 2)))}"
                : DateFormat('MMMM yyyy').format(_start)),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              final p = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2023), lastDate: DateTime(2035), helpText: tr("Pick any day of the starting month"));
              if (p != null) {
                setState(() => _start = DateTime(p.year, p.month));
                _load();
              }
            },
          ),
        ),
        ]),
      ]),
    );
  }

  Widget _breadcrumb() {
    final lv = _path.last;
    final unit = [for (final k in _keyOrder) lv.keys[k]].whereType<String>().where((x) => x.isNotEmpty).join(' › ');
    return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
      if (_path.length > 1)
        TextButton.icon(
          onPressed: () {
            setState(() => _path.removeLast());
            _load();
          },
          icon: const Icon(Icons.arrow_upward_rounded, size: 16),
          label: const Text("Up"),
        ),
      Text(
        "${_levelNames[lv.child]} of ${unit.isEmpty ? 'the church' : unit}",
        textAlign: TextAlign.center,
        style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: AppPalette.fg(pPurple)),
      ),
    ]);
  }

  Widget _table(bool narrow) {
    if (_rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(30),
        child: Text("No ${_levelNames[_path.last.child]!.toLowerCase()} found in this unit.", textAlign: TextAlign.center),
      );
    }
    final kindLabel = _kind[0].toUpperCase() + _kind.substring(1);
    double sumMonth = 0;
    var counted = 0;
    for (final r in _rows) {
      final v = _entered(r);
      if (v != null) {
        sumMonth += _toMonth(v);
        counted++;
      }
    }
    if (_isRate && counted > 0) sumMonth = sumMonth / counted; // a rate: the average
    final parentMonth = (_parentRow?['target'] as num?)?.toDouble();
    final canEditAny = _rows.any((r) => r['can_edit'] == true);
    final below = _below(_path.last.child);

    final left = parentMonth == null || _isRate ? null : parentMonth - sumMonth;
    final unitTitle = _levelNames[_path.last.child]!.replaceAll(RegExp(r's$'), '');
    const head = Color(0xFF3B0D78);
    final line = AppPalette.line(Colors.grey.shade300);

    // one table cell; numbers are right-aligned like a spreadsheet
    Widget cell(Widget child, {Alignment align = Alignment.center}) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1), child: SizedBox(height: 26, child: Align(alignment: align, child: child)));
    Widget h(String t, {Alignment align = Alignment.center}) => cell(
        Text(t, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w800, fontSize: 11.5, color: Colors.white, letterSpacing: .2)),
        align: align);
    Widget n(String t, {bool bold = false, Color? color}) => cell(
        Text(t,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: AppPalette.fg(color ?? Colors.blueGrey.shade900))),
        align: Alignment.centerRight);

    // the summary tiles above the table
    Widget tile(IconData icon, String label, String value, Color c, {String? sub}) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppPalette.bg(c.withValues(alpha: 0.07)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.line(c.withValues(alpha: 0.25))),
            ),
            child: Row(children: [
              Icon(icon, size: 20, color: AppPalette.fg(c)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.w900, color: AppPalette.fg(c))),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppPalette.fg(Colors.blueGrey.shade700))),
                  if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, color: AppPalette.fg(Colors.grey.shade600))),
                ]),
              ),
            ]),
          ),
        );
    final shared = parentMonth == null || parentMonth == 0 || _isRate ? null : (sumMonth / parentMonth).clamp(0.0, 1.5);
    final leftColor = left == null ? Colors.blueGrey : (left.abs() < 0.05 ? Colors.green.shade700 : (left > 0 ? Colors.orange.shade800 : Colors.red.shade700));

    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // summary: the goal of the unit above, what is shared out, what is left
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Row(children: [
            tile(Icons.flag_rounded, _parentRow == null ? "Goal above" : "Goal of ${_parentRow!['label']}",
                parentMonth == null ? "Not set" : _fmt(_fromMonth(parentMonth, _kind)), pPurple,
                sub: parentMonth == null || _isRate ? null : "${_fmt(parentMonth)} per month"),
            tile(Icons.call_split_rounded, _isRate ? "Average given" : "Shared out", counted == 0 ? "–" : _fmt(_fromMonth(sumMonth, _kind)), Colors.blue.shade700,
                sub: "$counted of ${_rows.length} ${_levelNames[_path.last.child]!.toLowerCase()}"),
            if (left != null)
              tile(left.abs() < 0.05 ? Icons.check_circle_rounded : (left > 0 ? Icons.hourglass_bottom_rounded : Icons.warning_amber_rounded),
                  left.abs() < 0.05 ? "Fully shared" : (left > 0 ? "Still to share" : "Over the goal"),
                  _fmt(_fromMonth(left.abs(), _kind)), leftColor),
          ]),
        ),
        if (shared != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: shared > 1 ? 1 : shared.toDouble(), minHeight: 6, color: leftColor, backgroundColor: Colors.grey.shade200),
            ),
          ),
        // The table fills the card's whole width; on a small phone it
        // scrolls sideways. Lines between every row and column.
        LayoutBuilder(builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            width: box.maxWidth < 560 ? 560 : box.maxWidth,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: line),
              boxShadow: [BoxShadow(color: pPurple.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Table(
                border: TableBorder(horizontalInside: BorderSide(color: line, width: 0.8), verticalInside: BorderSide(color: line, width: 0.8)),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: const {
                  0: FixedColumnWidth(42),
                  1: FlexColumnWidth(2.4),
                  2: FlexColumnWidth(1.6),
                  3: FlexColumnWidth(1),
                  4: FlexColumnWidth(1),
                  5: FlexColumnWidth(1),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(gradient: LinearGradient(colors: [head, Color(0xFF6A1B9A)])),
                    children: [h("#"), h(unitTitle, align: Alignment.centerLeft), h("Goal ($kindLabel)"), h("Per month"), h("Per week"), h("Per day")],
                  ),
                  for (var i = 0; i < _rows.length; i++)
                    () {
                      final r = _rows[i];
                      final v = _entered(r);
                      final m = v == null ? null : _toMonth(v);
                      final editable = r['can_edit'] == true;
                      return TableRow(
                        decoration: BoxDecoration(color: AppPalette.bg(i.isEven ? Colors.white : const Color(0xFFF7F4FB))),
                        children: [
                          cell(Text("${i + 1}", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600)))),
                          cell(
                            Row(children: [
                              Icon(Icons.account_tree_outlined, size: 14, color: AppPalette.fg(pPurple.withValues(alpha: 0.7))),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text((r['label'] ?? '').toString(),
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, fontSize: 12)),
                              ),
                              for (final b in below)
                                Tooltip(
                                  message: tr("Open its ${_levelNames[b]!.toLowerCase()}"),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () => _open(r, b),
                                    child: Container(
                                      margin: const EdgeInsets.only(left: 2),
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(color: AppPalette.bg(pPurple.withValues(alpha: 0.08)), borderRadius: BorderRadius.circular(6)),
                                      child: Icon(Icons.chevron_right_rounded, size: 18, color: AppPalette.fg(pPurple)),
                                    ),
                                  ),
                                ),
                            ]),
                            align: Alignment.centerLeft,
                          ),
                          editable
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  child: SizedBox(
                                    height: 26,
                                    child: TextField(
                                      controller: _ctrl[_rowKey(r)],
                                      textAlign: TextAlign.right,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      onChanged: (_) => setState(() {}),
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        filled: true,
                                        fillColor: AppPalette.bg(const Color(0xFFFFFDF2)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppPalette.line(Colors.amber.shade300))),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: pPurple, width: 1.4)),
                                        suffixText: _isRate ? '%' : null,
                                        hintText: '–',
                                      ),
                                    ),
                                  ),
                                )
                              : n(_fmt(v)),
                          n(_fmt(m == null ? null : _fromMonth(m, 'monthly'))),
                          n(_fmt(m == null ? null : _fromMonth(m, 'weekly'))),
                          n(_fmt(m == null ? null : _fromMonth(m, 'daily'))),
                        ],
                      );
                    }(),
                  TableRow(
                    decoration: BoxDecoration(
                      color: AppPalette.bg(const Color(0xFFFFF4D6)),
                      border: Border(top: BorderSide(color: AppPalette.line(Colors.amber.shade400), width: 1.6)),
                    ),
                    children: [
                      cell(const Icon(Icons.functions_rounded, size: 15)),
                      cell(Text(_isRate ? "Average" : "Total", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12.5)), align: Alignment.centerLeft),
                      n(_fmt(counted == 0 ? null : _fromMonth(sumMonth, _kind)), bold: true),
                      n(_fmt(counted == 0 ? null : sumMonth), bold: true),
                      n(_fmt(counted == 0 ? null : _fromMonth(sumMonth, 'weekly')), bold: true),
                      n(_fmt(counted == 0 ? null : _fromMonth(sumMonth, 'daily')), bold: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
        )),
        if (left != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              left.abs() < 0.05
                  ? "The goal of ${_parentRow!['label']} is fully shared out."
                  : left > 0
                      ? "Still to share out: ${_fmt(_fromMonth(left, _kind))} (${_fmt(left)} per month)"
                      : "Shared out ${_fmt(_fromMonth(-left, _kind))} more than the goal of ${_parentRow!['label']}",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, color: AppPalette.fg(leftColor)),
            ),
          ),
        const SizedBox(height: 10),
        if (canEditAny)
          Center(
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text("Save goals", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: pPurple,
                foregroundColor: Colors.white,
                elevation: 3,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          )
        else
          Text("You can see these goals; they are set by the leader of this level.",
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
        const SizedBox(height: 6),
        Text(
          _kind.contains('months')
              ? "A $_kind goal is divided equally over its months, then into weeks and days."
              : "The goal is stored per month and divided into weeks and days.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600)),
        ),
      ]),
    );
  }
}
