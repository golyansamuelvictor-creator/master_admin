// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';
import '../../core/app_sizes.dart';
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
  const BbWorkspaceScreen({super.key, required this.canEdit, required this.userRole});

  @override
  State<BbWorkspaceScreen> createState() => _BbWorkspaceScreenState();
}

class BbSettings {
  /// Stages, opening months, centers and list options (Evangelism Department settings).
  static Future<BbSettings> load() async {
    final db = Supabase.instance.client;
    final r = await Future.wait<dynamic>([
      db.from('evangelism_stages').select().eq('is_active', true).order('sort_order', ascending: true),
      db.from('evangelism_opening_months').select('label, month_start').eq('is_open', true).order('month_start', ascending: true),
      db.from('evangelism_centers').select('name, location, sub_location').eq('is_active', true).order('sort_order', ascending: true),
      db.from('entry_field_options').select('field_key, option_label, sort_order').eq('sheet_name', 'BB File').eq('is_active', true).order('sort_order', ascending: true),
    ]);
    final c = BbSettings();
    c.stages = List<Map<String, dynamic>>.from(r[0] as List);
    c.months = [for (final m in r[1] as List) m['label'].toString()];
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
      ("Student cards", Icons.badge_outlined),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
        appBar: AppBar(
          centerTitle: true,
          title: Text(widget.canEdit ? "BB File" : "BB File · compiled for your unit",
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple))),
          actions: [IconButton(tooltip: tr("Refresh"), icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: [for (final t in tabs) Tab(icon: Icon(t.$2, size: 18), text: tr(t.$1))],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                : TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
                    BbSheet(key: ValueKey('bb$_rev'), attendance: false, cfg: _cfg, students: _students, attended: _attended, canEdit: widget.canEdit, onSaved: _load),
                    BbSheet(key: ValueKey('at$_rev'), attendance: true, cfg: _cfg, students: _students, attended: _attended, canEdit: widget.canEdit, onSaved: _load),
                    _MissedTab(key: ValueKey('mis$_rev')),
                    _FileTab(cfg: _cfg, students: _students, canEdit: widget.canEdit, onOpen: _openStudent),
                  ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared table helpers

Widget _section(BuildContext context, String title, Widget child, {ExportTable Function()? export, String? subtitle}) {
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
  const BbSummaryView({super.key, required this.cfg, this.location, this.subLocation, this.center, this.month,
      this.sections = const {'goals', 'months', 'centers', 'locations', 'detail', 'checker'}});
  @override
  State<BbSummaryView> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<BbSummaryView> {
  Map<String, dynamic>? _d;
  String? _month;
  String? _error;

  @override
  void initState() {
    super.initState();
    _month = widget.month;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client.rpc('bb_summary', params: {
        'p_detail_month': _month,
        'p_location': widget.location,
        'p_sub_location': widget.subLocation,
        'p_center': widget.center,
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

    final byMonthRaw = List<Map<String, dynamic>>.from(d['by_month'] ?? const []);
    final monthRows = [for (final r in byMonthRaw.where((r) => r['row'] != 'Dropped')) countRow(r['row'].toString(), r['counts'] as Map)];
    final droppedRow = [for (final r in byMonthRaw.where((r) => r['row'] == 'Dropped')) countRow('Dropped', r['counts'] as Map)];
    final byMonth = [...withTotal("Opening months", monthRows), ...droppedRow];

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
      if (sec.contains('goals') && goals.isNotEmpty)
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
      _section(context, "Worthy Prospect + Spirit Creation", _grid(headers, byMonth, boldRows: {0}, headerColors: colors),
          subtitle: "Students counted only when their details are complete and they attended at least once",
          export: () => ex("Worthy Prospect + Spirit Creation", headers, byMonth)),
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
                      return Card(
                        elevation: 0.5,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        child: ExpansionTile(
                          shape: const Border(),
                          dense: true,
                          leading: CircleAvatar(
                            radius: 15,
                            backgroundColor: AppPalette.bg((missed > 0 ? Colors.red : Colors.green).withValues(alpha: 0.12)),
                            child: Text('$missed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(missed > 0 ? Colors.red.shade700 : Colors.green.shade800))),
                          ),
                          title: Text('${r['student_name']}', style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            "Missed $missed · attended ${r['attended']}${r['last_attended'] == null ? '' : ' · last came ${r['last_attended']}'} · ${r['guide_unit'] ?? ''}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
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
