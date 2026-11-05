import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';
import '../../core/compilation_rules.dart';
import '../../core/i18n.dart';
import '../../core/table_export.dart';
import '../../widgets/h_scroll.dart';
import '../../widgets/nice_range_picker.dart';
import 'center_students_tab.dart';

const Color _kPurple = Color(0xFF4A148C);
final _f = DateFormat('yyyy-MM-dd');

/// The Theology Department's student duties (22_round21.sql). Each has its own
/// records table; the students are center_students (the center they attend).
class StudentDuties {
  StudentDuties._();
  static const attendance = 'Center Attendance';
  static const evangelism = 'Students Evangelism';
  static const offering = 'Students Offering';
  static const visitations = 'Students Visitations';
  static const all = [attendance, evangelism, offering, visitations];

  static String table(String duty) => switch (duty) {
        attendance => 'logs_center_attendance',
        evangelism => 'logs_student_evangelism',
        offering => 'logs_student_offering',
        _ => 'logs_student_visitations',
      };

  static IconData icon(String duty) => switch (duty) {
        attendance => Icons.how_to_reg_rounded,
        evangelism => Icons.campaign_rounded,
        offering => Icons.volunteer_activism_rounded,
        _ => Icons.support_agent_rounded,
      };

  /// Theology workers (enter) — the patterns are in app_config.
  static Future<bool> isTheology() async {
    try {
      return (await Supabase.instance.client.rpc('is_theology')) == true;
    } catch (_) {
      return false;
    }
  }

  static bool _like(String role, String pattern) =>
      RegExp('^${RegExp.escape(pattern).replaceAll('%', '.*').replaceAll('_', '.')}\$').hasMatch(role.toLowerCase());

  /// Does one of these roles see the students? Theology workers (location
  /// and church), and the location, sub-location, department, team and cell
  /// leaders and secretaries (app_config.student_viewer_roles) for their own
  /// units' students. No church (24) department except Theology.
  static Future<bool> viewsStudents(List<String?> roles) async {
    final rs = roles.whereType<String>().where((r) => r.isNotEmpty).map((r) => r.toLowerCase()).toList();
    if (rs.isEmpty) return false;
    if (rs.contains('admin')) return true;
    var theology = const ['theo_%', 'theology_dept_%', 'church_head_instructor'];
    var viewers = const ['loc_%', 'sub_loc_%', 'dept_%', 'team_%', '%cell_leader%', '%cell_sec%'];
    final grouping = <String, String>{};
    try {
      final db = Supabase.instance.client;
      final rows = await db
          .from('app_config')
          .select('config_key, config_value')
          .inFilter('config_key', ['theology_church_roles', 'theology_location_roles', 'student_viewer_roles']);
      final t = <String>[], v = <String>[];
      for (final r in rows) {
        final list = List<String>.from((r['config_value'] as List?) ?? const []);
        (r['config_key'] == 'student_viewer_roles' ? v : t).addAll(list);
      }
      if (t.isNotEmpty) theology = t;
      if (v.isNotEmpty) viewers = v;
      final g = await db.from('app_roles').select('role_key, "Grouping"').inFilter('role_key', rs);
      for (final r in g) {
        grouping[r['role_key'].toString().toLowerCase()] = (r['Grouping'] ?? '').toString();
      }
    } catch (_) {}
    if (rs.any((r) => theology.any((p) => _like(r, p)))) return true;
    // church departments (24-Dept …) and church-level roles never see them
    bool church(String r) {
      final g = (grouping[r] ?? '').toLowerCase();
      return g.startsWith('24-dept') || g.startsWith('church') || r.startsWith('church_');
    }
    return rs.any((r) => !church(r) && viewers.any((p) => _like(r, p)));
  }
}

/// Settings of the student duties (app_config + entry_field_options).
class StudentsConfig {
  List<String> levels = const ['Introductory', 'Intermediate', 'Advanced'];
  List<String> classDays = const ['Mon', 'Tue', 'Thu', 'Fri'];
  List<String> fellowshipDays = const ['Wed', 'Sun'];
  List<String> fellowshipLevels = const ['Advanced'];
  List<String> styles = const ['In-person', 'Online', 'Other methods'];
  Map<String, List<String>> offeringItems = const {
    'Introductory': ['Monthly fee'],
    'Intermediate': ['Monthly fee', 'Tithe', 'Weekly offering'],
    'Advanced': ['Monthly fee', 'Tithe', 'Weekly offering', 'Thanksgiving', 'Construction'],
  };
  Map<String, Map<String, List<String>>> options = {}; // sheet → field → answers
  List<String> centers = const [];
  bool canEnter = false;

  List<String> get allOfferingItems {
    final out = <String>[];
    for (final l in levels) {
      for (final i in offeringItems[l] ?? const <String>[]) {
        if (!out.contains(i)) out.add(i);
      }
    }
    for (final v in offeringItems.values) {
      for (final i in v) {
        if (!out.contains(i)) out.add(i);
      }
    }
    return out;
  }

  List<String> opts(String sheet, String field, [List<String> fallback = const []]) {
    final o = options[sheet]?[field] ?? const <String>[];
    return o.isEmpty ? fallback : o;
  }

  static Future<StudentsConfig> load() async {
    final db = Supabase.instance.client;
    final c = StudentsConfig();
    await Future.wait([
      () async {
        try {
          final rows = await db.from('app_config').select('config_key, config_value').inFilter('config_key', [
            'student_class_levels', 'center_class_days', 'fellowship_days', 'center_attendance_styles', 'student_offering_items',
          ]);
          for (final r in rows) {
            final v = r['config_value'];
            switch (r['config_key']) {
              case 'student_class_levels':
                if (v is List && v.isNotEmpty) c.levels = List<String>.from(v);
              case 'center_class_days':
                if (v is List && v.isNotEmpty) c.classDays = List<String>.from(v);
              case 'fellowship_days':
                if (v is Map) {
                  c.fellowshipDays = List<String>.from(v['days'] ?? const []);
                  c.fellowshipLevels = List<String>.from(v['levels'] ?? const []);
                }
              case 'center_attendance_styles':
                if (v is List && v.isNotEmpty) c.styles = List<String>.from(v);
              case 'student_offering_items':
                if (v is Map) c.offeringItems = {for (final e in v.entries) e.key.toString(): List<String>.from(e.value as List)};
            }
          }
        } catch (_) {}
      }(),
      () async {
        try {
          final rows = await db
              .from('entry_field_options')
              .select('sheet_name, field_key, option_label, sort_order')
              .inFilter('sheet_name', StudentDuties.all)
              .eq('is_active', true)
              .order('sort_order', ascending: true);
          for (final r in rows) {
            c.options.putIfAbsent(r['sheet_name'].toString(), () => {}).putIfAbsent(r['field_key'].toString(), () => []).add(r['option_label'].toString());
          }
        } catch (_) {}
      }(),
      () async {
        try {
          final rows = await db.from('evangelism_centers').select('name').eq('is_active', true).order('sort_order', ascending: true);
          c.centers = [for (final r in rows) r['name'].toString()];
        } catch (_) {}
      }(),
      () async {
        c.canEnter = await StudentDuties.isTheology();
      }(),
    ]);
    return c;
  }
}

/// One student duty: Enter (Theology workers), Results, Students.
class StudentDutyScreen extends StatefulWidget {
  final String duty;
  const StudentDutyScreen({super.key, required this.duty});
  @override
  State<StudentDutyScreen> createState() => _StudentDutyScreenState();
}

class _StudentDutyScreenState extends State<StudentDutyScreen> {
  StudentsConfig? _cfg;

  @override
  void initState() {
    super.initState();
    StudentsConfig.load().then((c) {
      if (mounted) setState(() => _cfg = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    final tabs = <(String, IconData, Widget)>[
      if (cfg != null && cfg.canEnter) ("Enter", Icons.edit_note_rounded, _EntryTab(duty: widget.duty, cfg: cfg)),
      if (cfg != null) ("Results", Icons.insights_rounded, _ResultsTab(duty: widget.duty, cfg: cfg)),
      if (cfg != null) ("Students", Icons.school_rounded, CenterStudentsTab(canEdit: cfg.canEnter, cfg: cfg)),
    ];
    return DefaultTabController(
      length: tabs.isEmpty ? 1 : tabs.length,
      child: Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
        appBar: AppBar(
          centerTitle: true,
          toolbarHeight: 46,
          title: Text(widget.duty, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple))),
          bottom: tabs.isEmpty
              ? null
              : TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  tabs: [for (final t in tabs) Tab(height: 38, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(t.$2, size: 16), const SizedBox(width: 6), Text(t.$1)]))],
                ),
        ),
        body: tabs.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(physics: const NeverScrollableScrollPhysics(), children: [for (final t in tabs) t.$3]),
      ),
    );
  }
}

/// A table with the header rows fixed on top and the row numbers fixed on the
/// left; everything else scrolls both ways and is centred. With [textOf]
/// each column header gets a filter (pick the values to show) and columns can
/// be hidden / shown again (the corner button).
class FrozenGrid extends StatefulWidget {
  final List<(String, double)> columns;
  final int rows;
  final Widget Function(int row, int col) cell;
  final double rowHeight;
  /// The text of a cell, for the filters (null: no filters).
  final String Function(int row, int col)? textOf;
  /// Rows drawn in bold with a tint (e.g. a total on top).
  final Set<int> boldRows;
  const FrozenGrid({super.key, required this.columns, required this.rows, required this.cell, this.rowHeight = 40, this.textOf, this.boldRows = const {}});
  @override
  State<FrozenGrid> createState() => _FrozenGridState();
}

class _FrozenGridState extends State<FrozenGrid> {
  final _left = ScrollController(), _right = ScrollController(), _h = ScrollController();
  bool _sync = false;
  final Set<int> _hidden = {};
  final Map<int, Set<String>> _filters = {}; // column → the values shown

  @override
  void initState() {
    super.initState();
    void link(ScrollController a, ScrollController b) => a.addListener(() {
          if (_sync || !b.hasClients) return;
          _sync = true;
          b.jumpTo(a.offset.clamp(0, b.position.maxScrollExtent));
          _sync = false;
        });
    link(_left, _right);
    link(_right, _left);
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    _h.dispose();
    super.dispose();
  }

  List<int> get _rows {
    final t = widget.textOf;
    final all = [for (int r = 0; r < widget.rows; r++) r];
    if (t == null || _filters.isEmpty) return all;
    return all.where((r) => _filters.entries.every((f) => f.value.contains(t(r, f.key).trim()))).toList();
  }

  Future<void> _filter(int c) async {
    final t = widget.textOf!;
    final values = {for (int r = 0; r < widget.rows; r++) t(r, c).trim()}.toList()..sort();
    final chosen = {...(_filters[c] ?? values.toSet())};
    String q = '';
    final res = await showDialog<Set<String>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final shown = values.where((v) => q.isEmpty || v.toLowerCase().contains(q.toLowerCase())).toList();
        return AlertDialog(
          title: Text("Filter: ${widget.columns[c].$1}", textAlign: TextAlign.center),
          content: SizedBox(
            width: 340,
            height: 380,
            child: Column(children: [
              TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: tr("Search"), isDense: true, border: const OutlineInputBorder()), onChanged: (v) => set(() => q = v)),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                TextButton(onPressed: () => set(() => chosen.addAll(shown)), child: const Text("All")),
                TextButton(onPressed: () => set(() => chosen.removeAll(shown)), child: const Text("None")),
              ]),
              Expanded(
                child: ListView(children: [
                  for (final v in shown)
                    CheckboxListTile(
                      dense: true,
                      value: chosen.contains(v),
                      title: Text(v.isEmpty ? "(empty)" : v),
                      onChanged: (x) => set(() => x == true ? chosen.add(v) : chosen.remove(v)),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, <String>{'\u0000clear'}), child: const Text("Clear filter")),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.pop(ctx, chosen), child: const Text("Apply")),
          ],
        );
      }),
    );
    if (res == null) return;
    setState(() {
      if (res.contains('\u0000clear') || res.length == values.length) {
        _filters.remove(c);
      } else {
        _filters[c] = res;
      }
    });
  }

  Future<void> _chooseColumns() async {
    final hidden = {..._hidden};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text("Show / hide columns", textAlign: TextAlign.center),
          content: SizedBox(
            width: 320,
            child: ListView(shrinkWrap: true, children: [
              for (int c = 0; c < widget.columns.length; c++)
                CheckboxListTile(
                  dense: true,
                  value: !hidden.contains(c),
                  title: Text(widget.columns[c].$1),
                  onChanged: (v) => set(() => v == true ? hidden.remove(c) : hidden.add(c)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => set(hidden.clear), child: const Text("Show all")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("OK")),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        _hidden
          ..clear()
          ..addAll(hidden.length >= widget.columns.length ? const <int>{} : hidden);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final numW = 40.0, headH = widget.rowHeight < 30 ? 34.0 : 38.0;
    final rowH = widget.rowHeight;
    final line = AppPalette.line(Colors.black12);
    final rows = _rows;
    final cols = [for (int c = 0; c < widget.columns.length; c++) if (!_hidden.contains(c)) c];
    return LayoutBuilder(builder: (context, box) {
      final base = cols.fold<double>(0, (a, c) => a + widget.columns[c].$2);
      final scale = base > 0 && box.maxWidth - numW > base ? (box.maxWidth - numW) / base : 1.0;
      final widths = {for (final c in cols) c: widget.columns[c].$2 * scale};
      final total = widths.values.fold<double>(0, (a, w) => a + w);
      Widget head(int c) {
        final filtered = _filters.containsKey(c);
        return Container(
          width: widths[c],
          height: headH,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: const BoxDecoration(color: Color(0xFF1E293B), border: Border(right: BorderSide(color: Colors.white24))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text(widget.columns[c].$1, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            if (widget.textOf != null)
              InkWell(
                onTap: () => _filter(c),
                child: Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Icon(filtered ? Icons.filter_alt : Icons.filter_alt_outlined, size: 13, color: filtered ? const Color(0xFFF59E0B) : Colors.white70),
                ),
              ),
          ]),
        );
      }

      return Column(children: [
        if (_filters.isNotEmpty || _hidden.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Wrap(alignment: WrapAlignment.center, spacing: 6, children: [
              if (_filters.isNotEmpty)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.filter_alt_off_rounded, size: 15),
                  label: Text("${rows.length} of ${widget.rows} · clear filters", style: const TextStyle(fontSize: 11)),
                  onPressed: () => setState(_filters.clear),
                ),
              if (_hidden.isNotEmpty)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.visibility_rounded, size: 15),
                  label: Text("${_hidden.length} hidden · show all", style: const TextStyle(fontSize: 11)),
                  onPressed: () => setState(_hidden.clear),
                ),
            ]),
          ),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: numW,
              child: Column(children: [
                // the corner: show / hide columns
                InkWell(
                  onTap: _chooseColumns,
                  child: Container(
                    width: numW,
                    height: headH,
                    color: const Color(0xFF334155),
                    child: const Tooltip(message: "Show / hide columns", child: Icon(Icons.view_week_rounded, size: 16, color: Colors.white)),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _left,
                    itemCount: rows.length,
                    itemExtent: rowH,
                    itemBuilder: (_, i) => Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF1F5F9)), border: Border(bottom: BorderSide(color: line), right: BorderSide(color: line))),
                      child: Text("${i + 1}", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.grey.shade700))),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: Scrollbar(
                controller: _h,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _h,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: total,
                    child: Column(children: [
                      Row(children: [for (final c in cols) head(c)]),
                      Expanded(
                        child: ListView.builder(
                          controller: _right,
                          itemCount: rows.length,
                          itemExtent: rowH,
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            final bold = widget.boldRows.contains(r);
                            return Row(children: [
                              for (final c in cols)
                                Container(
                                  width: widths[c],
                                  height: rowH,
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppPalette.bg(bold ? const Color(0xFFFFF8E1) : (i.isEven ? Colors.white : const Color(0xFFF8FAFC))),
                                    border: Border(bottom: BorderSide(color: line), right: BorderSide(color: line)),
                                  ),
                                  child: widget.cell(r, c),
                                ),
                            ]);
                          },
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]);
    });
  }
}

// ---------------------------------------------------------------------------
// Enter

class _EntryTab extends StatefulWidget {
  final String duty;
  final StudentsConfig cfg;
  const _EntryTab({required this.duty, required this.cfg});
  @override
  State<_EntryTab> createState() => _EntryTabState();
}

class _EntryTabState extends State<_EntryTab> {
  final _db = Supabase.instance.client;
  DateTime _date = DateTime.now();
  String? _center, _level;
  String _q = '';
  bool _loading = true, _saving = false;
  List<Map<String, dynamic>> _students = [];
  final Map<String, Map<String, dynamic>> _vals = {}; // student → field → value
  final Set<String> _had = {}; // students with a saved record on this date
  final Map<String, TextEditingController> _ctl = {};
  int _changes = 0;

  String get _sheet => widget.duty;
  String get _dayName => DateFormat('EEE').format(_date);
  bool get _isAttendance => widget.duty == StudentDuties.attendance;
  bool get _fellowship => _isAttendance && widget.cfg.fellowshipDays.contains(_dayName) && !widget.cfg.classDays.contains(_dayName);
  bool get _noClass => _isAttendance && !widget.cfg.classDays.contains(_dayName) && !widget.cfg.fellowshipDays.contains(_dayName);

  @override
  void initState() {
    super.initState();
    if (_isAttendance) {
      // the latest class or fellowship day up to today
      var d = DateTime(_date.year, _date.month, _date.day);
      for (int i = 0; i < 7 && !widget.cfg.classDays.contains(DateFormat('EEE').format(d)) && !widget.cfg.fellowshipDays.contains(DateFormat('EEE').format(d)); i++) {
        d = d.subtract(const Duration(days: 1));
      }
      _date = d;
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final st = await _db.from('center_students').select('id, student_name, korean_name, center_place, center_location, class_level, status, guide_cell').eq('status', 'Active').order('student_name');
      final students = List<Map<String, dynamic>>.from(st);
      final logs = await _db.from(StudentDuties.table(widget.duty)).select().eq('report_date', _f.format(_date));
      _vals.clear();
      _had.clear();
      for (final c in _ctl.values) {
        c.dispose();
      }
      _ctl.clear();
      for (final l in logs) {
        final id = l['student_id'].toString();
        _had.add(id);
        _vals[id] = widget.duty == StudentDuties.offering
            ? {for (final e in Map<String, dynamic>.from((l['amounts'] as Map?) ?? const {}).entries) e.key: e.value}
            : Map<String, dynamic>.from(l)..removeWhere((k, _) => const ['id', 'student_id', 'report_date', 'entered_by', 'updated_at', 'class_day'].contains(k));
      }
      if (!mounted) return;
      setState(() {
        _students = students;
        _changes = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load (run 22_round21.sql): ${e is PostgrestException ? e.message : e}")));
    }
  }

  List<Map<String, dynamic>> get _shown {
    final q = _q.toLowerCase();
    return _students.where((s) {
      if (_center != null && s['center_place'] != _center) return false;
      if (_level != null && s['class_level'] != _level) return false;
      // fellowship (Wed / Sun): only the levels that attend it
      if (_fellowship && !widget.cfg.fellowshipLevels.contains(s['class_level'])) return false;
      return q.isEmpty || '${s['student_name']} ${s['korean_name']} ${s['center_place']}'.toLowerCase().contains(q);
    }).toList();
  }

  void _set(String id, String k, dynamic v) {
    setState(() {
      final m = _vals.putIfAbsent(id, () => {});
      if (v == null || (v is String && v.trim().isEmpty)) {
        m.remove(k);
      } else {
        m[k] = v;
      }
      // Attended: no reason / solution; Absentee: no style
      if (_isAttendance && k == 'status') {
        if (v == 'Attended' || (v ?? '').toString().toLowerCase().startsWith('attend')) {
          m.remove('reason');
          m.remove('solution');
          _ctl['$id|reason']?.clear();
          _ctl['$id|solution']?.clear();
        } else {
          m.remove('style');
        }
      }
      _changes++;
    });
  }

  TextEditingController _c(String id, String k) => _ctl.putIfAbsent('$id|$k', () => TextEditingController(text: (_vals[id]?[k] ?? '').toString()));

  Future<void> _save() async {
    setState(() => _saving = true);
    final t = StudentDuties.table(widget.duty);
    final now = DateTime.now().toUtc().toIso8601String();
    final up = <Map<String, dynamic>>[];
    final del = <String>[];
    for (final s in _students) {
      final id = s['id'].toString();
      final v = _vals[id] ?? const {};
      final empty = v.values.every((x) => x == null || x.toString().trim().isEmpty);
      if (empty) {
        if (_had.contains(id)) del.add(id);
        continue;
      }
      up.add({
        'student_id': id,
        'report_date': _f.format(_date),
        'updated_at': now,
        if (widget.duty == StudentDuties.offering)
          'amounts': {for (final e in v.entries) if (num.tryParse(e.value.toString().replaceAll(',', '')) != null) e.key: num.parse(e.value.toString().replaceAll(',', ''))}
        else ...{
          for (final e in v.entries) e.key: e.key == 'fruits' ? int.tryParse(e.value.toString()) : e.value,
          if (_isAttendance) 'class_day': _dayName,
        },
      });
    }
    try {
      for (int i = 0; i < up.length; i += 200) {
        await _db.from(t).upsert(up.sublist(i, (i + 200).clamp(0, up.length)), onConflict: 'student_id,report_date');
      }
      if (del.isNotEmpty) await _db.from(t).delete().eq('report_date', _f.format(_date)).inFilter('student_id', del);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved ${up.length} record${up.length == 1 ? '' : 's'}"), backgroundColor: Colors.green.shade700));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: ${e is PostgrestException ? e.message : e}")));
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _drop(String id, String k, List<String> options, {bool enabled = true}) {
    final v = _vals[id]?[k]?.toString();
    return DropdownButton<String>(
      value: options.contains(v) ? v : null,
      isExpanded: true,
      isDense: true,
      underline: const SizedBox(),
      hint: Text(enabled ? "—" : "", style: const TextStyle(fontSize: 11.5)),
      style: GoogleFonts.merriweather(fontSize: 11.5, color: AppPalette.fg(Colors.black87)),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text("—")),
        for (final o in options) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: enabled ? (x) => _set(id, k, x) : null,
    );
  }

  Widget _text(String id, String k, {bool number = false, bool enabled = true, String hint = ''}) => TextField(
        controller: _c(id, k),
        enabled: enabled,
        textAlign: TextAlign.center,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))] : null,
        style: GoogleFonts.merriweather(fontSize: 11.5),
        decoration: InputDecoration(isDense: true, hintText: enabled ? hint : '', border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 8)),
        onChanged: (x) => _set(id, k, x),
      );

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final list = _shown;
    final items = cfg.allOfferingItems;
    final cols = <(String, double)>[
      ("Student", 170.0),
      ("Center", 110.0),
      ("Level", 100.0),
      ...switch (widget.duty) {
        StudentDuties.attendance => [("Attendance", 120.0), ("Style", 120.0), ("Reason", 180.0), ("Solution", 180.0)],
        StudentDuties.offering => [for (final i in items) (i, 110.0)],
        StudentDuties.evangelism => [("Status", 170.0), ("Fruits", 80.0), ("Notes", 220.0)],
        _ => [("Reason", 170.0), ("Result", 170.0), ("Notes", 220.0)],
      },
    ];
    Widget cell(int r, int c) {
      final s = list[r];
      final id = s['id'].toString();
      switch (c) {
        case 0:
          return Text("${s['student_name']}", maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold));
        case 1:
          return Text((s['center_place'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11));
        case 2:
          return Text((s['class_level'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11));
      }
      final k = c - 3;
      switch (widget.duty) {
        case StudentDuties.attendance:
          final st = (_vals[id]?['status'] ?? '').toString();
          final attended = st.toLowerCase().startsWith('attend');
          return switch (k) {
            0 => _drop(id, 'status', cfg.opts(_sheet, 'status', const ['Attended', 'Absentee'])),
            1 => _drop(id, 'style', cfg.styles, enabled: attended),
            2 => _text(id, 'reason', enabled: st.isNotEmpty && !attended, hint: "Why absent"),
            _ => _text(id, 'solution', enabled: st.isNotEmpty && !attended, hint: "What will be done"),
          };
        case StudentDuties.offering:
          final allowed = cfg.offeringItems[s['class_level']] ?? (cfg.offeringItems.values.isEmpty ? const <String>[] : cfg.offeringItems.values.first);
          final item = items[k];
          return allowed.contains(item) ? _text(id, item, number: true, hint: "0") : Text("—", style: TextStyle(color: AppPalette.fg(Colors.grey.shade400)));
        case StudentDuties.evangelism:
          return switch (k) {
            0 => _drop(id, 'status', cfg.opts(_sheet, 'status_detail', cfg.opts(_sheet, 'status', const ['Evangelised', 'Did Not Evangelize']))),
            1 => _text(id, 'fruits', number: true, hint: "0"),
            _ => _text(id, 'notes'),
          };
        default:
          return switch (k) {
            0 => _drop(id, 'reason', cfg.opts(_sheet, 'visitation_reason', const ['Visitation', 'Counselling'])),
            1 => _drop(id, 'result', cfg.opts(_sheet, 'status_detail', const ['Done', 'Not done'])),
            _ => _text(id, 'notes'),
          };
      }
    }

    final centers = {for (final s in _students) (s['center_place'] ?? '').toString()}.where((c) => c.isNotEmpty).toList()..sort();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        child: HScroll(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
            ActionChip(
              avatar: const Icon(Icons.event_rounded, size: 16),
              label: Text(DateFormat('EEE d MMM yyyy').format(_date), style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                  initialDate: _date,
                  // attendance: the class and fellowship days only
                  selectableDayPredicate: _isAttendance
                      ? (x) => cfg.classDays.contains(DateFormat('EEE').format(x)) || cfg.fellowshipDays.contains(DateFormat('EEE').format(x))
                      : null,
                );
                if (d != null) {
                  _date = d;
                  _load();
                }
              },
            ),
            SizedBox(
              width: 190,
              height: 34,
              child: TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 17), hintText: tr("Search student"), isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 6), border: const OutlineInputBorder()),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => setState(() => _center = v == '\u0000' ? null : v),
              itemBuilder: (_) => [const PopupMenuItem(value: '\u0000', child: Text("All centers")), for (final c in centers) PopupMenuItem(value: c, child: Text(c))],
              child: Chip(visualDensity: VisualDensity.compact, avatar: const Icon(Icons.location_city_rounded, size: 16), label: Text(_center ?? "All centers")),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => setState(() => _level = v == '\u0000' ? null : v),
              itemBuilder: (_) => [const PopupMenuItem(value: '\u0000', child: Text("All levels")), for (final l in cfg.levels) PopupMenuItem(value: l, child: Text(l))],
              child: Chip(visualDensity: VisualDensity.compact, avatar: const Icon(Icons.stairs_rounded, size: 16), label: Text(_level ?? "All levels")),
            ),
            Text("${list.length}", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
            FilledButton.icon(
              onPressed: _changes == 0 || _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded, size: 18),
              label: Text(_changes == 0 ? "Saved" : "Save"),
            ),
          ]),
        ),
      ),
      if (_isAttendance && (_fellowship || _noClass))
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            _noClass ? "No class on ${DateFormat('EEEE').format(_date)}s. Pick a class day (${cfg.classDays.join(', ')})." : "Fellowship day: ${cfg.fellowshipLevels.join(', ')} students",
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(_noClass ? Colors.red.shade700 : _kPurple)),
          ),
        ),
      if (widget.duty == StudentDuties.offering)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text("Amounts in UGX. Each level gives its own kinds: ${[for (final l in cfg.levels) "$l: ${(cfg.offeringItems[l] ?? const []).join(', ')}"].join(' · ')}",
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
        ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _noClass || list.isEmpty
                ? Center(child: Text(_noClass ? "" : "No students here. Add them in the Students tab.", style: TextStyle(color: AppPalette.fg(Colors.grey))))
                : FrozenGrid(key: ValueKey('${_f.format(_date)}|$_center|$_level|$_q'), columns: cols, rows: list.length, cell: cell),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Results

class _ResultsTab extends StatefulWidget {
  final String duty;
  final StudentsConfig cfg;
  const _ResultsTab({required this.duty, required this.cfg});
  @override
  State<_ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends State<_ResultsTab> {
  final _db = Supabase.instance.client;
  late DateTimeRange _range;
  String _period = 'This month';
  String _by = 'Center';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    final t = DateTime.now();
    _range = DateTimeRange(start: DateTime(t.year, t.month, 1), end: DateTime(t.year, t.month, t.day));
    _load();
  }

  Future<void> _setPeriod(String p) async {
    final t = DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    DateTimeRange? r;
    switch (p) {
      case 'This week':
        r = DateTimeRange(start: today.subtract(Duration(days: today.weekday - 1)), end: today);
      case 'This month':
        r = DateTimeRange(start: DateTime(t.year, t.month, 1), end: today);
      case 'Last month':
        r = DateTimeRange(start: DateTime(t.year, t.month - 1, 1), end: DateTime(t.year, t.month, 0));
      case 'Custom':
        r = await showNiceRangePicker(context, initial: _range, title: tr('Custom period'));
    }
    if (r == null) return;
    setState(() {
      _period = p;
      _range = r!;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final st = await _db.from('center_students').select('id, student_name, center_place, center_location, class_level, status, guide_location, guide_cell');
      final logs = <Map<String, dynamic>>[];
      for (int from = 0;; from += 1000) {
        final page = await _db
            .from(StudentDuties.table(widget.duty))
            .select()
            .gte('report_date', _f.format(_range.start))
            .lte('report_date', _f.format(_range.end))
            .order('id')
            .range(from, from + 999);
        logs.addAll(List<Map<String, dynamic>>.from(page));
        if (page.length < 1000) break;
      }
      if (!mounted) return;
      setState(() {
        _students = List<Map<String, dynamic>>.from(st);
        _logs = logs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load (run 22_round21.sql): ${e is PostgrestException ? e.message : e}";
      });
    }
  }

  String _unitOf(Map s) => switch (_by) {
        'Location' => (s['center_location'] ?? '').toString().isEmpty ? 'Center location not set' : s['center_location'].toString(),
        'Class level' => (s['class_level'] ?? '').toString().isEmpty ? 'Level not set' : s['class_level'].toString(),
        _ => (s['center_place'] ?? '').toString().isEmpty ? 'Center not set' : s['center_place'].toString(),
      };

  /// (headers, rows, main value per row for the chart, chart title)
  (List<String>, List<List<String>>, List<double>, String) _table() {
    final cfg = widget.cfg;
    final byId = {for (final s in _students) s['id'].toString(): s};
    final units = <String>{};
    for (final s in _students.where((s) => s['status'] == 'Active')) {
      units.add(_unitOf(s));
    }
    for (final l in _logs) {
      final s = byId[l['student_id'].toString()];
      if (s != null) units.add(_unitOf(s));
    }
    var names = units.toList()..sort();
    if (_by == 'Class level') names = [for (final l in cfg.levels) if (units.contains(l)) l, ...names.where((n) => !cfg.levels.contains(n))];
    if (_by == 'Location') names = CompLevel.orderNames(names, 'Location');
    int students(String u) => _students.where((s) => s['status'] == 'Active' && _unitOf(s) == u).length;
    List<Map<String, dynamic>> logsOf(String u) => _logs.where((l) {
          final s = byId[l['student_id'].toString()];
          return s != null && _unitOf(s) == u;
        }).toList();
    final fmt = NumberFormat('#,##0');
    String pct(num a, num b) => b == 0 ? '–' : '${(a * 100 / b).toStringAsFixed(1)}%';
    final unitCol = _by == 'Class level' ? 'Level' : _by;

    switch (widget.duty) {
      case StudentDuties.attendance: {
        final styles = cfg.styles;
        List<String> rowA(String label, List<Map<String, dynamic>> ls, int n) {
          final att = ls.where((l) => (l['status'] ?? '').toString().toLowerCase().startsWith('attend')).toList();
          final abs = ls.length - att.length;
          final sessions = {for (final l in ls) l['report_date']}.length;
          return [label, '$n', '$sessions', '${ls.length}', '${att.length}', for (final st in styles) '${att.where((l) => l['style'] == st).length}', '$abs', pct(att.length, ls.length)];
        }
        final rows = [for (final u in names) rowA(u, logsOf(u), students(u))];
        return (
          [unitCol, "Students", "Class days", "Records", "Attended", ...styles, "Absent", "Attendance %"],
          [rowA("General total", _logs, _students.where((s) => s['status'] == 'Active').length), ...rows],
          [for (final r in rows) double.tryParse(r.last.replaceAll('%', '')) ?? 0],
          "Attendance % by ${unitCol.toLowerCase()}",
        );
      }
      case StudentDuties.offering: {
        final items = cfg.allOfferingItems;
        List<String> rowO(String label, List<Map<String, dynamic>> ls, int n) {
          num sum(String i) => ls.fold<num>(0, (a, l) => a + ((((l['amounts'] as Map?) ?? const {})[i] as num?) ?? 0));
          final givers = {for (final l in ls) if (((l['amounts'] as Map?) ?? const {}).values.any((v) => (v as num? ?? 0) > 0)) l['student_id']}.length;
          final total = items.fold<num>(0, (a, i) => a + sum(i));
          return [label, '$n', '$givers', for (final i in items) fmt.format(sum(i)), fmt.format(total)];
        }
        final rows = [for (final u in names) rowO(u, logsOf(u), students(u))];
        return (
          [unitCol, "Students", "Gave", ...items, "Total (UGX)"],
          [rowO("General total", _logs, _students.where((s) => s['status'] == 'Active').length), ...rows],
          [for (final r in rows) (num.tryParse(r.last.replaceAll(',', '')) ?? 0).toDouble()],
          "Total offering (UGX) by ${unitCol.toLowerCase()}",
        );
      }
      case StudentDuties.evangelism: {
        final statuses = {for (final l in _logs) (l['status'] ?? '').toString()}.where((s) => s.isNotEmpty).toList()..sort();
        List<String> rowE(String label, List<Map<String, dynamic>> ls, int n) => [
              label, '$n', '${ls.length}',
              for (final st in statuses) '${ls.where((l) => l['status'] == st).length}',
              '${ls.fold<int>(0, (a, l) => a + ((l['fruits'] as num?)?.toInt() ?? 0))}',
            ];
        final rows = [for (final u in names) rowE(u, logsOf(u), students(u))];
        return (
          [unitCol, "Students", "Reports", ...statuses, "Fruits"],
          [rowE("General total", _logs, _students.where((s) => s['status'] == 'Active').length), ...rows],
          [for (final r in rows) double.tryParse(r.last) ?? 0],
          "Fruits by ${unitCol.toLowerCase()}",
        );
      }
      default: {
        final results = {for (final l in _logs) (l['result'] ?? '').toString()}.where((s) => s.isNotEmpty).toList()..sort();
        List<String> rowV(String label, List<Map<String, dynamic>> ls, int n) => [
              label, '$n', '${ls.length}', '${{for (final l in ls) l['student_id']}.length}',
              for (final st in results) '${ls.where((l) => l['result'] == st).length}',
            ];
        final rows = [for (final u in names) rowV(u, logsOf(u), students(u))];
        return (
          [unitCol, "Students", "Visits", "Students visited", ...results],
          [rowV("General total", _logs, _students.where((s) => s['status'] == 'Active').length), ...rows],
          [for (final r in rows) double.tryParse(r[2]) ?? 0],
          "Visits by ${unitCol.toLowerCase()}",
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final head = Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      child: HScroll(
        child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
          for (final p in const ['This week', 'This month', 'Last month', 'Custom'])
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              label: Text(p == 'Custom' && _period == 'Custom' ? "${DateFormat('d MMM').format(_range.start)} – ${DateFormat('d MMM').format(_range.end)}" : p),
              selected: _period == p,
              onSelected: (_) => _setPeriod(p),
            ),
          const SizedBox(width: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 'Center', label: Text("Center")),
              ButtonSegment(value: 'Location', label: Text("Location")),
              ButtonSegment(value: 'Class level', label: Text("Level")),
            ],
            selected: {_by},
            onSelectionChanged: (v) => setState(() => _by = v.first),
          ),
        ]),
      ),
    );
    if (_loading) return Column(children: [head, const Expanded(child: Center(child: CircularProgressIndicator()))]);
    if (_error != null) return Column(children: [head, Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center))))]);
    final (headers, rows, values, chartTitle) = _table();
    final labels = [for (final r in rows.skip(1)) r.first];
    final maxV = values.fold<double>(0, (a, v) => v > a ? v : a);
    final isPct = widget.duty == StudentDuties.attendance;
    return Column(children: [
      head,
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(10, 4, 10, 40), children: [
          Row(children: [
            Expanded(
              child: Text("${widget.duty} · ${DateFormat('d MMM yyyy').format(_range.start)} – ${DateFormat('d MMM yyyy').format(_range.end)}",
                  style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(_kPurple))),
            ),
            IconButton(
              tooltip: tr('Excel / PDF / Print'),
              icon: Icon(Icons.download_rounded, color: AppPalette.fg(_kPurple)),
              onPressed: () => TableExport.showMenu(
                context,
                () => ExportTable(title: widget.duty, subtitle: "${DateFormat('d MMM yyyy').format(_range.start)} – ${DateFormat('d MMM yyyy').format(_range.end)} · by ${_by.toLowerCase()}", headers: headers, rows: rows),
              ),
            ),
          ]),
          // the table fills the width (centred) and scrolls sideways when it is wider
          LayoutBuilder(builder: (context, box) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth),
              child: DataTable(
              border: TableBorder.all(color: AppPalette.line(Colors.grey.shade300), width: 0.8),
              headingRowColor: WidgetStateProperty.all(AppPalette.bg(const Color(0xFFF3E5F5))),
              headingRowHeight: 40,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 34,
              columnSpacing: 18,
              columns: [
                for (int i = 0; i < headers.length; i++)
                  DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text(headers[i], textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: [
                for (int r = 0; r < rows.length; r++)
                  DataRow(
                    color: r == 0 ? WidgetStateProperty.all(AppPalette.bg(const Color(0xFFFFF8E1))) : null,
                    cells: [for (final v in rows[r]) DataCell(Center(child: Text(v, textAlign: TextAlign.center, style: TextStyle(fontWeight: r == 0 ? FontWeight.bold : FontWeight.normal))))],
                  ),
              ],
            ),
            ),
          )),
          if (labels.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(chartTitle, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppPalette.fg(_kPurple))),
            const SizedBox(height: 6),
            LayoutBuilder(builder: (context, box) {
              final w = (labels.length * 80.0).clamp(box.maxWidth, 4000.0);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: w,
                  height: 260,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20, right: 8),
                    child: BarChart(BarChartData(
                      minY: 0,
                      maxY: isPct ? 100 : (maxV <= 0 ? 1 : maxV * 1.15),
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        enabled: false,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => Colors.transparent,
                          tooltipPadding: EdgeInsets.zero,
                          tooltipMargin: 2,
                          getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                            isPct ? "${values[g.x].toStringAsFixed(1)}%" : NumberFormat.compact().format(values[g.x]),
                            TextStyle(color: AppPalette.fg(_kPurple), fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (x, m) => Text(isPct ? "${x.toInt()}%" : NumberFormat.compact().format(x), style: const TextStyle(fontSize: 9.5)))),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            getTitlesWidget: (x, m) {
                              final i = x.toInt();
                              if (i < 0 || i >= labels.length) return const SizedBox();
                              return SideTitleWidget(
                                meta: m,
                                space: 4,
                                child: SizedBox(width: 74, child: Text(labels[i], maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600))),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (int i = 0; i < values.length; i++)
                          BarChartGroupData(x: i, showingTooltipIndicators: const [0], barRods: [
                            BarChartRodData(toY: values[i], width: 22, color: AppPalette.solid(_kPurple), borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                          ]),
                      ],
                    )),
                  ),
                ),
              );
            }),
          ],
        ]),
      ),
    ]);
  }
}
