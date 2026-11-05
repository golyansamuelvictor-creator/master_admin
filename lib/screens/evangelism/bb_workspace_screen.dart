// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';
import '../../core/app_sizes.dart';
import '../../core/compilation_rules.dart';
import '../../core/i18n.dart';
import '../../core/table_export.dart';
import 'bb_sheets.dart';
import 'bb_student_form.dart';

const Color _kPurple = Color(0xFF4A148C);

/// Evangelism › BB File.
///
/// The location evangelism secretary enters students and attendance; every
/// other role with the duty gets the compilation of its own unit (the
/// database only returns students guided, taught or entered in that unit):
///  - Summary: opening months × stage, opening centers × stage, one month by
///    center × stage × Active / Not Active / Dropped, the checker and goals;
///  - BB File: every student and their details;
///  - Attendance: the month's sessions with A / missed marks;
///  - Missed & reasons: how many times each student missed and why;
///  - Policies & goals set by the Evangelism Department.
class BbWorkspaceScreen extends StatefulWidget {
  final bool canEdit;
  final String userRole;
  /// Theology: only the BB students guided by center students (their units'
  /// centers / locations; the database decides who is visible).
  final bool studentsOnly;
  const BbWorkspaceScreen({super.key, required this.canEdit, required this.userRole, this.studentsOnly = false});

  @override
  State<BbWorkspaceScreen> createState() => _BbWorkspaceScreenState();
}

class BbSettings {
  /// Stages, opening months, centers and list options (Evangelism Department settings).
  static Future<BbSettings> load() async {
    final db = Supabase.instance.client;
    final r = await Future.wait<dynamic>([
      db.from('evangelism_stages').select().eq('is_active', true).order('sort_order', ascending: true),
      db.from('evangelism_opening_months').select('label, month_start, is_open').order('month_start', ascending: true),
      db.from('evangelism_centers').select('name, location, sub_location').eq('is_active', true).order('sort_order', ascending: true),
      db.from('entry_field_options').select('field_key, option_label, sort_order').eq('sheet_name', 'BB File').eq('is_active', true).order('sort_order', ascending: true),
    ]);
    final c = BbSettings();
    c.stages = List<Map<String, dynamic>>.from(r[0] as List);
    c.months = [for (final m in r[1] as List) if (m['is_open'] == true) m['label'].toString()];
    // months the Evangelism Department closed: their students go to History
    c.closedMonths = [for (final m in r[1] as List) if (m['is_open'] != true) m['label'].toString()];
    c.centers = [for (final x in r[2] as List) x['name'].toString()];
    c.centerUnits = {
      for (final x in r[2] as List) x['name'].toString(): [x['location'], x['sub_location']].where((v) => (v ?? '').toString().isNotEmpty).join(' - '),
    };
    for (final o in r[3] as List) {
      c.options.putIfAbsent(o['field_key'].toString(), () => []).add(o['option_label'].toString());
    }
    return c;
  }

  List<Map<String, dynamic>> stages = [];
  List<String> months = [];
  List<String> closedMonths = [];

  /// The same settings listing other months (History lists the closed ones).
  BbSettings withMonths(List<String> m) => BbSettings()
    ..stages = stages
    ..months = m
    ..closedMonths = closedMonths
    ..centers = centers
    ..centerUnits = centerUnits
    ..options = options;
  List<String> centers = [];
  /// center → "Location - Sub-location" (from the Evangelism Department's centers table)
  Map<String, String> centerUnits = {};
  Map<String, List<String>> options = {};
  List<String> get stageNames => stages.map((s) => s['stage'].toString()).toList();
  Color stageColor(String s) {
    final row = stages.firstWhere((x) => x['stage'] == s, orElse: () => {});
    final v = int.tryParse((row['color_hex'] ?? '').toString().replaceAll('#', ''), radix: 16);
    return v == null ? _kPurple : Color(0xFF000000 | v);
  }
}

class _BbWorkspaceScreenState extends State<BbWorkspaceScreen> {
  final _db = Supabase.instance.client;
  bool _history = false;
  final BbSettings _cfg = BbSettings();
  List<Map<String, dynamic>> _students = [];
  bool _loading = true;
  String? _error;
  Map<String, int> _attended = {}; // all-time sessions attended (BB times)
  int _rev = 0; // bumps when data changes, so the tabs reload

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final r = await Future.wait<dynamic>([
        BbSettings.load(),
        _db.from('bb_students').select().order('student_no', ascending: true, nullsFirst: false).order('student_name', ascending: true),
        _db.rpc('bb_attendance_summary', params: {'p_from': '2000-01-01', 'p_to': today}),
      ]);
      final cfg = r[0] as BbSettings;
      _cfg
        ..stages = cfg.stages
        ..months = cfg.months
        ..closedMonths = cfg.closedMonths
        ..centers = cfg.centers
        ..centerUnits = cfg.centerUnits
        ..options = cfg.options;
      _attended = {for (final x in r[2] as List) x['student_id'].toString(): ((x['attended'] ?? 0) as num).toInt()};
      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(r[1] as List);
          _loading = false;
          _error = null;
          _rev++;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load the BB File (run 12_round11.sql and 13_round12.sql): ${e is PostgrestException ? e.message : e}";
        });
      }
    }
  }

  Future<void> _openStudent([Map<String, dynamic>? s]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => BbStudentForm(student: s, cfg: _cfg, readOnly: !widget.canEdit),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    // BB File: the BB File sheet and the Attendance sheet (as in the Excel
    // file); the summary is under Evangelism Results, policies and goals in
    // the Evangelism menu.
    final tabs = <(String, IconData)>[
      ("BB File", Icons.table_chart_rounded),
      ("Attendance", Icons.how_to_reg_rounded),
      ("Missed & reasons", Icons.report_problem_outlined),
      ("Dropped", Icons.person_off_outlined),
      ("Student cards", Icons.badge_outlined),
    ];
    // Current: the open months' students (not dropped). History: the months
    // the Evangelism Department closed and the dropped students.
    bool closed(Map s) => (s['month'] ?? '').toString().isNotEmpty && _cfg.closedMonths.contains(s['month']);
    bool dropped(Map s) => (s['bb_status'] ?? '').toString().toLowerCase().startsWith('drop');
    bool mine(Map s) => !widget.studentsOnly || (s['guided_by_type'] ?? '').toString().toLowerCase().contains('student');
    final pool = _students.where(mine).toList();
    final shown = pool.where((s) => _history ? (closed(s) || dropped(s)) : !(closed(s) || dropped(s))).toList();
    final droppedPool = pool.where((s) => _history ? closed(s) : !closed(s)).toList();
    final cfg = _history ? _cfg.withMonths([..._cfg.closedMonths, ..._cfg.months]) : _cfg;
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
        appBar: AppBar(
          centerTitle: true,
          toolbarHeight: 46,
          title: Text("${widget.studentsOnly ? "Students' BB File" : (widget.canEdit ? "BB File" : "BB File · compiled for your unit")}${_history ? ' · History' : ''}",
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple))),
          actions: [
            // History: closed opening months and dropped students (read only)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FilterChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.history_rounded, size: 16, color: AppPalette.fg(_kPurple)),
                label: const Text("History"),
                selected: _history,
                onSelected: (v) => setState(() => _history = v),
              ),
            ),
            IconButton(tooltip: tr("Refresh"), icon: const Icon(Icons.refresh_rounded), onPressed: _load),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: [for (final t in tabs) Tab(height: 38, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(t.$2, size: 16), const SizedBox(width: 6), Text(t.$1)]))],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                : TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
                    BbSheet(key: ValueKey('bb$_rev$_history'), attendance: false, cfg: cfg, students: shown, attended: _attended, canEdit: widget.canEdit && !_history, onSaved: _load),
                    BbSheet(key: ValueKey('at$_rev$_history'), attendance: true, cfg: cfg, students: shown, attended: _attended, canEdit: widget.canEdit && !_history, onSaved: _load),
                    _MissedTab(key: ValueKey('mis$_rev')),
                    _DroppedTab(key: ValueKey('drop$_rev$_history'), students: droppedPool, canEdit: widget.canEdit, onSaved: _load),
                    _FileTab(cfg: cfg, students: shown, canEdit: widget.canEdit && !_history, onOpen: _openStudent),
                  ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared table helpers

Widget _section(BuildContext context, String title, Widget child, {ExportTable Function()? export, String? subtitle, Widget? trailing}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: AppPalette.bg(Colors.white),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppPalette.line(Colors.black12)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(_kPurple))),
              if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
            ]),
          ),
          if (trailing != null) trailing,
          if (export != null)
            IconButton(tooltip: tr('Excel / PDF / Print'), icon: Icon(Icons.download_rounded, color: AppPalette.fg(_kPurple), size: 20), onPressed: () => TableExport.showMenu(context, export)),
          IconButton(
            tooltip: tr('Fullscreen View'),
            icon: Icon(Icons.open_in_full_rounded, color: AppPalette.fg(Colors.blueGrey), size: 19),
            onPressed: () => bbFullScreen(
              context,
              title,
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (export != null)
                    Center(
                      child: TextButton.icon(
                        onPressed: () => TableExport.showMenu(context, export),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text("Excel / PDF / Print"),
                      ),
                    ),
                  child,
                ]),
              ),
            ),
          ),
        ]),
      ),
      const Divider(height: 1),
      child,
    ]),
  );
}

/// A centred table that scrolls sideways when it doesn't fit.
Widget _grid(List<String> headers, List<List<String>> rows, {Set<int> boldRows = const {}, List<Color?>? headerColors, double first = 130, double col = 74}) {
  Widget cell(String t, double w, {bool head = false, bool bold = false, Color? bg, Color? fg}) => Container(
        width: w,
        height: head ? 34 : 26,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(color: bg == null ? null : AppPalette.bg(bg), border: Border.all(color: AppPalette.line(Colors.black26), width: 0.5)),
        child: Text(t,
            maxLines: head ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(fontSize: head ? 10 : 10.5, fontWeight: head || bold ? FontWeight.bold : FontWeight.normal, color: AppPalette.fg(fg ?? (head ? Colors.white : Colors.black87)))),
      );
  return LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: c.maxWidth),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (int i = 0; i < headers.length; i++)
                  cell(headers[i], i == 0 ? first : col, head: true, bg: (headerColors != null && i < headerColors.length ? headerColors[i] : null) ?? const Color(0xFF1E293B)),
              ]),
              for (int r = 0; r < rows.length; r++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  for (int i = 0; i < rows[r].length; i++)
                    cell(rows[r][i], i == 0 ? first : col,
                        bold: boldRows.contains(r) || i == 0, bg: boldRows.contains(r) ? const Color(0xFFF1E8FB) : (r.isEven ? Colors.white : const Color(0xFFF8FAFC))),
                ]),
            ]),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Summary

/// Evangelism Results: the Summary sheet's tables, compiled for the caller's
/// unit (bb_summary). [sections] picks which tables to show.
class BbSummaryView extends StatefulWidget {
  final BbSettings cfg;
  final String? location;
  final String? subLocation;
  final String? center;
  final String? month;
  final Set<String> sections; // goals, months, centers, locations, detail, checker
  /// Students' evangelism: the BB students guided by center students (23_round22.sql)
  final bool studentsOnly;
  const BbSummaryView({super.key, required this.cfg, this.location, this.subLocation, this.center, this.month,
      this.sections = const {'goals', 'months', 'centers', 'locations', 'detail', 'checker'}, this.studentsOnly = false});
  @override
  State<BbSummaryView> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<BbSummaryView> {
  Map<String, dynamic>? _d;
  Map<String, dynamic>? _ev; // Goals this month by unit (evangelism_results)
  bool _evFailed = false;
  // Goals this month: the level shown and the units picked above it
  // (Location → Sub-location → Department → Team), like the Compilation sidebar
  static const _gLevels = ['location', 'sub_location', 'department', 'team', 'cell'];
  static const _gNames = ['Location goals', 'Sub-location goals', 'Department goals', 'Team goals', 'Cell group goals'];
  static const _gPickNames = ['Location', 'Sub-location', 'Department', 'Team'];
  int _gLevel = -1; // -1 = not chosen yet (follows the side bar)
  int _gMin = 0; // the viewer's own level: a team leader sees team goals and below
  final List<String?> _gPick = [null, null, null, null];
  final Map<String, List<String>> _gOpts = {}; // "level|parents" → units
  String? _month;
  String? _error;

  @override
  void initState() {
    super.initState();
    _month = widget.month;
    // the goals table and the summary load side by side
    _loadGoals();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client.rpc('bb_summary', params: {
        'p_detail_month': _month,
        'p_location': widget.location,
        'p_sub_location': widget.subLocation,
        'p_center': widget.center,
        if (widget.studentsOnly) 'p_students': true,
      });
      if (mounted) {
        setState(() {
          _d = Map<String, dynamic>.from(r as Map);
          _month ??= _d!['detail_month']?.toString();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't compile: ${e is PostgrestException ? e.message : e}");
    }
  }

  /// Goals this month as a table: each unit's goal and what is achieved,
  /// in total and split offline / online (evangelism_results, 14_round13.sql).
  Future<Map<String, dynamic>> _evQuery(int level, List<String?> picks) {
    final now = DateTime.now();
    String f(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    String? at(int i) => i < level ? picks[i] : null;
    return Supabase.instance.client.rpc('evangelism_results', params: {
      'p_from': f(DateTime(now.year, now.month, 1)),
      'p_to': f(DateTime(now.year, now.month, now.day)),
      'p_group': _gLevels[level],
      'p_location': at(0),
      'p_sub': at(1),
      'p_dept': at(2),
      'p_team': at(3),
      if (widget.studentsOnly) 'p_students': true,
    }).then((r) => Map<String, dynamic>.from(r as Map));
  }

  /// The viewer's own level and units (my_report_filters): the goals start
  /// there and can go down, never up or sideways.
  Future<void> _myLevel() async {
    try {
      final r = await Supabase.instance.client.rpc('my_report_filters');
      const cols = ['location', 'sub_location', 'department', 'team', 'cell_group'];
      final vals = <String, String>{
        for (final x in (r as List? ?? const []))
          if ((x as Map)['op'] == 'eq' && cols.contains(x['col'])) x['col'].toString(): (x['val'] ?? '').toString(),
      };
      int depth = 0;
      while (depth < cols.length && (vals[cols[depth]] ?? '').isNotEmpty) {
        depth++;
      }
      if (depth > 0) {
        _gMin = depth - 1;
        for (int i = 0; i < _gMin && i < 4; i++) {
          _gPick[i] = vals[cols[i]];
        }
        _gLevel = _gMin;
      }
    } catch (_) {}
  }

  Future<void> _loadGoals() async {
    if (!widget.sections.contains('goals')) return;
    if (_gLevel < 0) await _myLevel();
    if (_gLevel < 0) {
      // start at the side bar's choice: the guide's location → its sub-locations
      if ((widget.location ?? '').isNotEmpty) {
        _gPick[0] = widget.location;
        _gPick[1] = widget.subLocation;
        _gLevel = (widget.subLocation ?? '').isNotEmpty ? 2 : 1;
      } else {
        _gLevel = 0;
      }
    }
    setState(() {
      _ev = null;
      _evFailed = false;
    });
    try {
      final r = await _evQuery(_gLevel, _gPick);
      if (mounted) setState(() => _ev = r);
    } catch (_) {
      if (mounted) setState(() => _evFailed = true); // the goal cards as before
    }
  }

  /// The units a picker offers (the level's units under the picks above)
  final Set<String> _gLoading = {};
  Future<void> _loadOptions(int k) async {
    final key = "$k|${_gPick.take(k).join('|')}";
    if (_gOpts.containsKey(key) || !_gLoading.add(key)) return;
    try {
      // quick list of the units (22_round21.sql)
      String? at(int i) => i < k ? _gPick[i] : null;
      final names = List<String>.from(await Supabase.instance.client.rpc('ev_unit_options', params: {
        'p_level': _gLevels[k],
        'p_location': at(0),
        'p_sub': at(1),
        'p_dept': at(2),
        'p_team': at(3),
      }) as List);
      final order = CompLevel.orderNames(names, const ['Location', 'Sub-location', 'Dept', 'Team', 'Cell'][k]);
      if (mounted) setState(() => _gOpts[key] = order);
      return;
    } catch (_) {}
    try {
      final r = await _evQuery(k, _gPick);
      final names = [for (final x in (r['rows'] as List? ?? const [])) (x as Map)['unit'].toString()].where((n) => n != 'Not set').toList();
      final order = CompLevel.orderNames(names, const ['Location', 'Sub-location', 'Dept', 'Team', 'Cell'][k]);
      if (mounted) setState(() => _gOpts[key] = order);
    } catch (_) {
      _gOpts[key] = const [];
    }
  }

  List<String> _optsFor(int k) => _gOpts["$k|${_gPick.take(k).join('|')}"] ?? const [];

  Widget _goalPickers() {
    Widget drop<T>(String hint, T? value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged) => Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppPalette.line(Colors.black26))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              hint: Text(hint, style: const TextStyle(fontSize: 11.5)),
              isDense: true,
              style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(_kPurple)),
              items: items,
              onChanged: onChanged,
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: [
        // the cascade: each picker lists the units under the one before it
        for (int k = _gMin; k < _gLevel && k < 4; k++)
          () {
            final opts = _optsFor(k);
            if (opts.isEmpty) _loadOptions(k);
            final v = opts.contains(_gPick[k]) ? _gPick[k] : null;
            return drop<String>(
              "All ${_gPickNames[k].toLowerCase()}s",
              v,
              [
                DropdownMenuItem<String>(value: null, child: Text("All ${_gPickNames[k].toLowerCase()}s")),
                for (final o in opts) DropdownMenuItem<String>(value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
              ],
              (x) {
                setState(() {
                  _gPick[k] = x;
                  for (int j = k + 1; j < 4; j++) {
                    _gPick[j] = null;
                  }
                });
                _loadGoals();
              },
            );
          }(),
      ]),
    );
  }

  Widget _goalLevelDrop() => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF3E5F5)), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppPalette.line(Colors.purple.shade200))),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _gLevel < _gMin ? _gMin : _gLevel,
            isDense: true,
            style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(_kPurple)),
            items: [for (int i = _gMin; i < _gNames.length; i++) DropdownMenuItem(value: i, child: Text(_gNames[i]))],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _gLevel = v;
                for (int j = v; j < 4; j++) {
                  _gPick[j] = null;
                }
              });
              _loadGoals();
            },
          ),
        ),
      );

  List<List<String>> _goalRows() {
    final ev = _ev!;
    double? g(Map? m) => (m?['goal'] as num?)?.toDouble();
    int t(Map? m) => (m?['total'] as num?)?.toInt() ?? 0;
    String num0(double? v) => v == null ? '–' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));
    String pct(int a, double? goal) => goal == null || goal == 0 ? '–' : '${(a * 100 / goal).round()}%';
    List<String> row(String label, Map r) {
      final off = r['offline'] as Map?, on = r['online'] as Map?;
      final go = g(off), gn = g(on);
      final tot = go == null && gn == null ? null : (go ?? 0) + (gn ?? 0);
      final a = t(off) + t(on);
      return [label, num0(tot), '$a', pct(a, tot), num0(go), '${t(off)}', pct(t(off), go), num0(gn), '${t(on)}', pct(t(on), gn)];
    }
    final rows = List<Map<String, dynamic>>.from((ev['rows'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final level = const ['Location', 'Sub-location', 'Dept', 'Team', 'Cell'][_gLevel < 0 ? 0 : _gLevel];
    final order = CompLevel.orderNames(rows.map((r) => r['unit'].toString()), level);
    rows.sort((x, y) => order.indexOf(x['unit'].toString()).compareTo(order.indexOf(y['unit'].toString())));
    return [
      if (ev['total'] is Map) row("General total", ev['total'] as Map),
      for (final r in rows) row(r['unit'].toString(), r),
    ];
  }

  static const _goalHeaders = ["Units", "Total Goal", "Achieved", "%", "Offline", "Achieved", "%", "Online", "Achieved", "%"];

  int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final stages = List<Map<String, dynamic>>.from(d['stages'] ?? const []);
    final names = [for (final s in stages) s['stage'].toString()];
    final overall = [for (final s in stages) if (s['in_overall'] == true) s['stage'].toString()];
    final studentsSet = [for (final s in stages) if (s['in_students'] == true) s['stage'].toString()];
    final colors = <Color?>[null, ...names.map(widget.cfg.stageColor), const Color(0xFF4A148C), const Color(0xFF283593)];
    final headers = ["", ...names, "Overall", "Students"];

    List<String> countRow(String label, Map counts) {
      final c = {for (final n in names) n: _n(counts[n])};
      final o = overall.fold<int>(0, (a, n) => a + (c[n] ?? 0));
      final st = studentsSet.fold<int>(0, (a, n) => a + (c[n] ?? 0));
      return [label, ...names.map((n) => '${c[n]}'), '$o', '$st'];
    }

    List<List<String>> withTotal(String label, List<List<String>> rows) {
      final total = <String>[label];
      for (int i = 1; i < headers.length; i++) {
        total.add('${rows.fold<int>(0, (a, r) => a + (int.tryParse(r[i]) ?? 0))}');
      }
      return [total, ...rows];
    }

    // Worthy Prospect + Spirit Creation: Dropped is a column (the drops of
    // each opening month); before 22_round21.sql it stays a row
    final byMonthRaw = List<Map<String, dynamic>>.from(d['by_month'] ?? const []);
    final monthsRaw = byMonthRaw.where((r) => r['row'] != 'Dropped').toList();
    final dropCol = monthsRaw.isNotEmpty && monthsRaw.every((r) => r.containsKey('dropped'));
    final monthHeaders = dropCol ? [...headers, "Dropped"] : headers;
    final monthColors = dropCol ? [...colors, const Color(0xFFC62828)] : colors;
    final monthRows = [
      for (final r in monthsRaw) [...countRow(r['row'].toString(), r['counts'] as Map), if (dropCol) '${_n(r['dropped'])}'],
    ];
    final droppedRow = dropCol ? const <List<String>>[] : [for (final r in byMonthRaw.where((r) => r['row'] == 'Dropped')) countRow('Dropped', r['counts'] as Map)];
    final monthTotal = <String>["Opening months", for (int i = 1; i < monthHeaders.length; i++) '${monthRows.fold<int>(0, (a, r) => a + (int.tryParse(r[i]) ?? 0))}'];
    final byMonth = [monthTotal, ...monthRows, ...droppedRow];

    final byCenter = withTotal("Opening centers", [for (final r in List<Map<String, dynamic>>.from(d['by_center'] ?? const [])) countRow(r['row'].toString(), r['counts'] as Map)]);

    // detail: center × stage × status
    final detailRaw = List<Map<String, dynamic>>.from(d['detail'] ?? const []);
    final dHeaders = ["Center place"];
    for (final n in names) {
      dHeaders.addAll(["$n · Active", "$n · Not active", "$n · Dropped", "$n · Current", "$n · Total"]);
    }
    final detailRows = <List<String>>[];
    for (final r in detailRaw) {
      final cells = r['cells'] as Map;
      final row = [r['row'].toString()];
      for (final n in names) {
        final c = (cells[n] ?? {}) as Map;
        final a = _n(c['active']), na = _n(c['not_active']), dr = _n(c['dropped']);
        row.addAll(['$a', '$na', '$dr', '${a + na}', '${a + na + dr}']);
      }
      detailRows.add(row);
    }
    final detailTotal = ["Total", for (int i = 1; i < dHeaders.length; i++) '${detailRows.fold<int>(0, (a, r) => a + (int.tryParse(r[i]) ?? 0))}'];

    final checks = Map<String, dynamic>.from(d['checks'] ?? const {});
    final byStage = Map<String, dynamic>.from(checks['by_stage'] ?? const {});
    final checkRows = [
      ["BB File", '${checks['bb_total']}', '${checks['bb_complete']}', checks['bb_total'] == checks['bb_complete'] ? 'OK' : 'Not matching'],
      ["Students", '${checks['students_total']}', '${checks['students_qualified']}', checks['students_total'] == checks['students_qualified'] ? 'OK' : 'Not matching'],
      for (final n in names)
        [n, '${(byStage[n] ?? {})['total'] ?? 0}', '${(byStage[n] ?? {})['qualified'] ?? 0}', (byStage[n] ?? {})['total'] == (byStage[n] ?? {})['qualified'] ? 'OK' : 'Not matching'],
    ];
    final goals = List<Map<String, dynamic>>.from(d['goals'] ?? const []);

    ExportTable ex(String t, List<String> h, List<List<String>> r) => ExportTable(title: t, subtitle: "BB File summary", headers: h, rows: r);

    final byLocation = withTotal("Guide's location", [for (final r in List<Map<String, dynamic>>.from(d['by_location'] ?? const [])) countRow(r['row'].toString(), r['counts'] as Map)]);
    final sec = widget.sections;

    return ListView(padding: AppSizes.page, children: [
      if (sec.contains('goals') && !_evFailed)
        _section(
          context,
          "Goals this month",
          trailing: _goalLevelDrop(),
          Column(children: [
            if (_gLevel > _gMin) _goalPickers(),
            _ev == null
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                : _grid(_goalHeaders, _goalRows(), boldRows: {0}, col: 70, headerColors: const [
                    null, Color(0xFF4A148C), Color(0xFF4A148C), Color(0xFF4A148C),
                    Color(0xFF00695C), Color(0xFF00695C), Color(0xFF00695C),
                    Color(0xFF1565C0), Color(0xFF1565C0), Color(0xFF1565C0),
                  ]),
          ]),
          export: () => ExportTable(title: "Goals this month", subtitle: "Evangelism results", headers: _goalHeaders, rows: _ev == null ? const [] : _goalRows()),
        )
      else if (sec.contains('goals') && goals.isNotEmpty)
        _section(
          context,
          "Goals this month",
          Padding(
            padding: const EdgeInsets.all(10),
            child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
              for (final g in goals)
                SizedBox(
                  width: 220,
                  child: Card(
                    elevation: 0.5,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(children: [
                        Text("${g['metric']}", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12.5)),
                        Text(g['level'] == 'church' ? 'Whole church' : [g['location'], g['sub_location']].where((x) => (x ?? '').toString().isNotEmpty).join(' › '),
                            style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: ((_n(g['actual'])) / ((g['target'] as num?)?.toDouble() ?? 1)).clamp(0.0, 1.0),
                          minHeight: 7,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 4),
                        Text("${g['actual']} of ${g['target']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      if (sec.contains('months'))
      _section(context, "Worthy Prospect + Spirit Creation", _grid(monthHeaders, byMonth, boldRows: {0}, headerColors: monthColors),
          subtitle: "Students counted only when their details are complete and they attended at least once${dropCol ? ' · Dropped: the students of that opening month who dropped' : ''}",
          export: () => ex("Worthy Prospect + Spirit Creation", monthHeaders, byMonth)),
      if (sec.contains('centers'))
      _section(context, "Opening centers", _grid(headers, byCenter, boldRows: {0}, headerColors: colors), export: () => ex("Opening centers", headers, byCenter)),
      if (sec.contains('locations'))
        _section(context, "By the guide's location", _grid(headers, byLocation, boldRows: {0}, headerColors: colors),
            subtitle: "Each student counts once, under the location of the guide who brought them",
            export: () => ex("By the guide's location", headers, byLocation)),
      if (sec.contains('detail'))
      _section(
        context,
        "By center and status",
        Column(children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: DropdownButton<String>(
                value: widget.cfg.months.contains(_month) ? _month : null,
                hint: Text(_month ?? "Month"),
                items: [for (final m in widget.cfg.months) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (v) {
                  _month = v;
                  _load();
                },
              ),
            ),
          ),
          _grid(dHeaders, [detailTotal, ...detailRows], boldRows: {0}, col: 62),
        ]),
        subtitle: "Current = Active + Not active",
        export: () => ex("By center and status – $_month", dHeaders, [detailTotal, ...detailRows]),
      ),
      if (sec.contains('checker'))
      _section(context, "Checker", _grid(["", "Entered", "Qualify", "Check"], checkRows, col: 100),
          subtitle: "Entered vs complete: fill in the missing details of the students that don't qualify yet",
          export: () => ex("Checker", ["", "Entered", "Qualify", "Check"], checkRows)),
    ]);
  }
}

// ---------------------------------------------------------------------------
// BB File list

class _FileTab extends StatefulWidget {
  final BbSettings cfg;
  final List<Map<String, dynamic>> students;
  final bool canEdit;
  final void Function([Map<String, dynamic>?]) onOpen;
  final bool fullScreen;
  const _FileTab({required this.cfg, required this.students, required this.canEdit, required this.onOpen, this.fullScreen = false});
  @override
  State<_FileTab> createState() => _FileTabState();
}

class _FileTabState extends State<_FileTab> {
  String _q = '';
  String? _center, _month, _stage, _status;

  String _v(Map s, String k) => (s[k] ?? '').toString();

  Widget _filter(String label, String? value, List<String> options, void Function(String?) set) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: PopupMenuButton<String>(
          tooltip: tr(label),
          onSelected: (v) => setState(() => set(v == '\u0000' ? null : v)),
          itemBuilder: (_) => [const PopupMenuItem(value: '\u0000', child: Text("All")), for (final o in options) PopupMenuItem(value: o, child: Text(o))],
          child: Chip(
            avatar: Icon(value == null ? Icons.filter_list_rounded : Icons.check_rounded, size: 16),
            label: Text(value ?? label),
            backgroundColor: AppPalette.bg(value == null ? Colors.white : const Color(0xFFEDE3F8)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = widget.students.where((s) {
      if (_center != null && _v(s, 'center_place') != _center) return false;
      if (_month != null && _v(s, 'month') != _month) return false;
      if (_stage != null && _v(s, 'level_status') != _stage) return false;
      if (_status != null && _v(s, 'bb_status') != _status) return false;
      return q.isEmpty || '${s['student_name']} ${s['guide_name']} ${s['teacher_name']} ${s['contact']}'.toLowerCase().contains(q);
    }).toList();
    final headers = ["No.", "Name", "Center", "Month", "Stage", "Status", "Guide (unit)", "Teacher (unit)", "Contact"];
    String unit(Map s, String p) => [_v(s, '${p}_location'), _v(s, '${p}_sub_location'), _v(s, '${p}_dept'), _v(s, '${p}_team'), _v(s, '${p}_cell')]
        .where((x) => x.isNotEmpty && x.toUpperCase() != 'N/A')
        .join(' › ');
    List<String> row(Map s) => [
          _v(s, 'student_no'),
          _v(s, 'student_name'),
          _v(s, 'center_place'),
          _v(s, 'month'),
          _v(s, 'level_status'),
          _v(s, 'bb_status'),
          "${_v(s, 'guide_name')} (${unit(s, 'guide')})",
          "${_v(s, 'teacher_name')} (${unit(s, 'teacher')})",
          _v(s, 'contact'),
        ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSizes.gutter, 10, AppSizes.gutter, 4),
        child: TextField(
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr("Search student, guide, teacher or phone"), isDense: true, border: const OutlineInputBorder()),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      SizedBox(
        height: 46,
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _filter("Center", _center, widget.cfg.centers, (v) => _center = v),
              _filter("Month", _month, widget.cfg.months, (v) => _month = v),
              _filter("Stage", _stage, widget.cfg.stageNames, (v) => _stage = v),
              _filter("Status", _status, widget.cfg.options['bb_status'] ?? const ['Active', 'Not Active', 'Dropped'], (v) => _status = v),
              IconButton(
                tooltip: tr('Excel / PDF / Print'),
                icon: Icon(Icons.download_rounded, color: AppPalette.fg(_kPurple)),
                onPressed: () => TableExport.showMenu(context, () => ExportTable(title: "BB File", headers: headers, rows: [for (final s in list) row(s)])),
              ),
              if (!widget.fullScreen)
                IconButton(
                  tooltip: tr('Fullscreen View'),
                  icon: Icon(Icons.open_in_full_rounded, color: AppPalette.fg(Colors.blueGrey)),
                  onPressed: () => bbFullScreen(context, "Student cards",
                      _FileTab(cfg: widget.cfg, students: widget.students, canEdit: widget.canEdit, onOpen: widget.onOpen, fullScreen: true)),
                ),
              if (widget.canEdit)
                TextButton.icon(onPressed: () => widget.onOpen(), icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text("Add student")),
            ]),
          ),
        ),
      ),
      Text("${list.length} of ${widget.students.length} students", style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
      const SizedBox(height: 4),
      Expanded(
        child: list.isEmpty
            ? Center(child: Text(widget.canEdit ? "No students yet. Tap \"Add student\"." : "No students in your unit yet.", style: TextStyle(color: AppPalette.fg(Colors.grey))))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(AppSizes.gutter, 0, AppSizes.gutter, 90),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  final stage = _v(s, 'level_status');
                  final c = widget.cfg.stageColor(stage);
                  final status = _v(s, 'bb_status');
                  return Card(
                    elevation: 0.5,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: SizedBox(
                      height: AppSizes.listCard,
                      child: InkWell(
                        onTap: () => widget.onOpen(s),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(children: [
                            CircleAvatar(radius: 15, backgroundColor: AppPalette.bg(c.withValues(alpha: 0.15)), child: Text(_v(s, 'student_no'), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(c)))),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text(_v(s, 'student_name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                Text([_v(s, 'center_place'), _v(s, 'month'), "Guide: ${_v(s, 'guide_name')}", unit(s, 'guide')].where((x) => x.isNotEmpty).join(' • '),
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
                              ]),
                            ),
                            if (stage.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(color: AppPalette.bg(c.withValues(alpha: 0.12)), borderRadius: BorderRadius.circular(8)),
                                child: Text(stage, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(c))),
                              ),
                            if (status.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(status == 'Active' ? Icons.circle : (status == 'Dropped' ? Icons.cancel : Icons.pause_circle_filled),
                                    size: 14, color: AppPalette.fg(status == 'Active' ? Colors.green : (status == 'Dropped' ? Colors.red : Colors.orange))),
                              ),
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Dropped: date, stage at the time and the reason (the same student record
// as the BB File: setting the status to Dropped there puts them here)

class _DroppedTab extends StatefulWidget {
  final List<Map<String, dynamic>> students;
  final bool canEdit;
  final VoidCallback onSaved;
  const _DroppedTab({super.key, required this.students, required this.canEdit, required this.onSaved});
  @override
  State<_DroppedTab> createState() => _DroppedTabState();
}

class _DroppedTabState extends State<_DroppedTab> {
  String _q = '';

  List<Map<String, dynamic>> get _dropped => widget.students
      .where((s) => (s['bb_status'] ?? '').toString().toLowerCase().startsWith('drop'))
      .where((s) => _q.isEmpty || "${s['student_name']} ${s['guide_name']} ${s['center_place']}".toLowerCase().contains(_q.toLowerCase()))
      .toList()
    ..sort((a, b) => (b['dropped_at'] ?? '').toString().compareTo((a['dropped_at'] ?? '').toString()));

  Future<void> _edit(Map<String, dynamic> s) async {
    final reason = TextEditingController(text: (s['drop_reason'] ?? '').toString());
    DateTime date = DateTime.tryParse((s['dropped_at'] ?? '').toString()) ?? DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
            title: Text("Dropped: ${s['student_name']}", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15)),
            content: SizedBox(
              width: 380,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text("Dropped on ${DateFormat('d MMM yyyy').format(date)}"),
                  onPressed: () async {
                    final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2023), lastDate: DateTime.now());
                    if (d != null) set(() => date = d);
                  },
                ),
                const SizedBox(height: 8),
                Text("Stage when dropped: ${s['drop_stage'] ?? s['level_status'] ?? '-'}", style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                TextField(controller: reason, maxLines: 3, decoration: InputDecoration(labelText: tr("Reason"), border: const OutlineInputBorder())),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
            ],
          )),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.from('bb_students').update({
        'drop_reason': reason.text.trim().isEmpty ? null : reason.text.trim(),
        'dropped_at': DateFormat('yyyy-MM-dd').format(date),
      }).eq('id', s['id']);
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save (run 18_round17.sql): ${e is PostgrestException ? e.message : e}"), backgroundColor: Colors.red.shade700));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _dropped;
    String d(dynamic v) {
      final t = DateTime.tryParse((v ?? '').toString());
      return t == null ? '' : DateFormat('d MMM yyyy').format(t);
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
          SizedBox(
            width: 240,
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: tr("Search student, guide, center"), isDense: true, border: const OutlineInputBorder()),
            ),
          ),
          Text("${list.length} dropped", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.red.shade800))),
          IconButton(
            tooltip: tr('Excel / PDF / Print'),
            icon: Icon(Icons.download_rounded, color: AppPalette.fg(_kPurple)),
            onPressed: () => TableExport.showMenu(
              context,
              () => ExportTable(
                title: "BB File – dropped students",
                subtitle: DateFormat('d MMM yyyy').format(DateTime.now()),
                headers: const ["No.", "Student", "Center", "Month", "Dropped on", "Stage when dropped", "Reason", "Guide", "Teacher"],
                rows: [
                  for (final s in list)
                    [
                      '${s['student_no'] ?? ''}',
                      '${s['student_name'] ?? ''}',
                      '${s['center_place'] ?? ''}',
                      '${s['month'] ?? ''}',
                      d(s['dropped_at']),
                      '${s['drop_stage'] ?? s['level_status'] ?? ''}',
                      '${s['drop_reason'] ?? ''}',
                      '${s['guide_name'] ?? ''}',
                      '${s['teacher_name'] ?? ''}',
                    ]
                ],
              ),
            ),
          ),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? Center(child: Text("No dropped students. A student appears here when their status in the BB File is set to Dropped.",
                textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey))))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(AppSizes.gutter, 0, AppSizes.gutter, 24),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  final reason = (s['drop_reason'] ?? '').toString();
                  // rows at 60% of the earlier height, like Missed & reasons
                  return Card(
                    elevation: 0.5,
                    margin: const EdgeInsets.symmetric(vertical: 1.5),
                    child: ListTile(
                      dense: true,
                      minTileHeight: 32,
                      visualDensity: const VisualDensity(vertical: -4),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      leading: CircleAvatar(radius: 11, backgroundColor: AppPalette.bg(Colors.red.withValues(alpha: 0.12)), child: Icon(Icons.person_off_rounded, size: 13, color: AppPalette.fg(Colors.red.shade700))),
                      title: Text('${s['student_name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        [
                          if (d(s['dropped_at']).isNotEmpty) "Dropped ${d(s['dropped_at'])}",
                          "at ${s['drop_stage'] ?? s['level_status'] ?? '-'}",
                          reason.isEmpty ? "no reason yet" : reason,
                          if ((s['guide_name'] ?? '').toString().isNotEmpty) "guide ${s['guide_name']}",
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: AppPalette.fg(reason.isEmpty ? Colors.orange.shade900 : Colors.black87)),
                      ),
                      trailing: widget.canEdit
                          ? IconButton(
                              tooltip: tr("Reason and date"),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              icon: const Icon(Icons.edit_note_rounded, size: 20),
                              onPressed: () => _edit(s))
                          : null,
                      onTap: widget.canEdit ? () => _edit(s) : null,
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

// Missed & reasons

class _MissedTab extends StatefulWidget {
  final bool fullScreen;
  const _MissedTab({super.key, this.fullScreen = false});
  @override
  State<_MissedTab> createState() => _MissedTabState();
}

class _MissedTabState extends State<_MissedTab> {
  DateTimeRange _range = DateTimeRange(start: DateTime(DateTime.now().year, DateTime.now().month - 2, 1), end: DateTime.now());
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _onlyMissed = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final f = DateFormat('yyyy-MM-dd');
    try {
      final r = await Supabase.instance.client.rpc('bb_attendance_summary', params: {'p_from': f.format(_range.start), 'p_to': f.format(_range.end)});
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(r as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('d MMM');
    final list = _onlyMissed ? _rows.where((r) => ((r['missed'] ?? 0) as num) > 0).toList() : _rows;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text("${f.format(_range.start)} – ${f.format(_range.end)}"),
            onPressed: () async {
              final r = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now(), initialDateRange: _range);
              if (r != null) {
                _range = r;
                _load();
              }
            },
          ),
          FilterChip(label: const Text("Only students who missed"), selected: _onlyMissed, onSelected: (v) => setState(() => _onlyMissed = v)),
          IconButton(
            tooltip: tr('Excel / PDF / Print'),
            icon: Icon(Icons.download_rounded, color: AppPalette.fg(_kPurple)),
            onPressed: () => TableExport.showMenu(
              context,
              () => ExportTable(
                title: "BB attendance – missed and reasons",
                subtitle: "${f.format(_range.start)} – ${f.format(_range.end)}",
                headers: const ["No.", "Student", "Center", "Stage", "Status", "Guide", "Attended", "Missed", "Reasons"],
                rows: [
                  for (final r in list)
                    [
                      '${r['student_no'] ?? ''}',
                      '${r['student_name']}',
                      '${r['center_place'] ?? ''}',
                      '${r['stage'] ?? ''}',
                      '${r['bb_status'] ?? ''}',
                      '${r['guide_name'] ?? ''}',
                      '${r['attended']}',
                      '${r['missed']}',
                      (r['reasons'] as List).map((x) => "${x['date']}: ${x['reason']}").join('; '),
                    ]
                ],
              ),
            ),
          ),
          if (!widget.fullScreen)
            IconButton(
              tooltip: tr('Fullscreen View'),
              icon: Icon(Icons.open_in_full_rounded, color: AppPalette.fg(Colors.blueGrey)),
              onPressed: () => bbFullScreen(context, "Missed & reasons", const _MissedTab(fullScreen: true)),
            ),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : list.isEmpty
                ? Center(child: Text("Nobody missed in this period.", style: TextStyle(color: AppPalette.fg(Colors.grey))))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(AppSizes.gutter, 0, AppSizes.gutter, 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final r = list[i];
                      final reasons = List<Map<String, dynamic>>.from(r['reasons'] ?? const []);
                      final missed = ((r['missed'] ?? 0) as num).toInt();
                      // rows at 60% of the earlier height
                      return Card(
                        elevation: 0.5,
                        margin: const EdgeInsets.symmetric(vertical: 1.5),
                        child: ExpansionTile(
                          shape: const Border(),
                          dense: true,
                          minTileHeight: 32,
                          visualDensity: const VisualDensity(vertical: -4),
                          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                          leading: CircleAvatar(
                            radius: 11,
                            backgroundColor: AppPalette.bg((missed > 0 ? Colors.red : Colors.green).withValues(alpha: 0.12)),
                            child: Text('$missed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(missed > 0 ? Colors.red.shade700 : Colors.green.shade800))),
                          ),
                          title: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: '${r['student_name']}', style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)),
                              TextSpan(
                                text: "   Missed $missed · attended ${r['attended']}${r['last_attended'] == null ? '' : ' · last came ${r['last_attended']}'} · ${r['guide_unit'] ?? ''}",
                                style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.blueGrey.shade700)),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (reasons.isEmpty) const Text("No missed sessions."),
                            for (final x in reasons)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  SizedBox(width: 90, child: Text(DateFormat('d MMM yyyy').format(DateTime.parse(x['date'].toString())), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold))),
                                  Expanded(child: Text(x['reason'].toString(), style: const TextStyle(fontSize: 11.5))),
                                ]),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
