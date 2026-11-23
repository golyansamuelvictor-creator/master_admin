import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/app_palette.dart';
import '../core/compilation_rules.dart';
import '../core/i18n.dart';
import '../core/rep_table.dart';
import '../core/security.dart';
import '../widgets/bar3d_chart.dart';
import '../widgets/zoom_box.dart';

/// Service Attendance tables in the church's own Excel layout, for the
/// Internal Affairs Department Secretary and the Administration Department
/// (and, for "Current dept status", each group's leaders: their own group).
///
///  * [AttReportKind.region]: one region's SUMMARY (the region, then each
///    sub region: Total, Church/H.Q vs Enrollment, each Book of Life group)
///    and DEPT (the same by current department), like the 와키소지역 file.
///  * [AttReportKind.currentDept]: one group by the current department
///    column (MG, WG, YAG, New Saints, MOU, Church 24 Departments,
///    Theology): Overall by region, by Book of Life, then each Book of Life
///    group by region, with charts (the 장년회 file).
///  * [AttReportKind.bookOfLife]: Group status tapped open: the Book of Life
///    summary, or one group by 24Dept, MOU and each region (the 교자장부청
///    file).
/// Members who are not registered yet (보고예정자 / 보예) are left out; they
/// have their own list ([NonRegisteredListScreen]).
enum AttReportKind { region, currentDept, bookOfLife }

const List<String> kAttResidences = ['Kampala', 'Village', 'Abroad'];
const List<String> kAttDepts = ['장년회', '부녀회', '청년회', '신학부', '새신자', 'MOU'];

/// The groups of "Current dept status": label → key (current department,
/// 'MOU', or '24Dept' for the church's 24 departments).
const List<(String, String)> kAttGroups = [
  ('MG (장년회)', '장년회'),
  ('WG (부녀회)', '부녀회'),
  ('YAG (청년회)', '청년회'),
  ('New Saints (새신자)', '새신자'),
  ('MOU', 'MOU'),
  ('Church 24 Departments', '24Dept'),
  ('Theology (신학부)', '신학부'),
];

List<RepCol> attCols() => [
      const RepCol('Num'),
      const RepCol('Attendees'),
      const RepCol('%', '', '', true),
      const RepCol('In-person', 'Total'),
      const RepCol('In-person', '%', '', true),
      const RepCol('Other Methods', 'Total'),
      const RepCol('Other Methods', '%', '', true),
      const RepCol('Absentees', 'Total'),
      const RepCol('Absentees', '%', '', true),
      const RepCol('H-M'),
      const RepCol('LTA'),
      for (final r in kAttResidences) ...[
        for (final k in const ['In-person', 'Online', 'Call', 'Meet', 'Summary']) RepCol(r, 'Actual', k),
        for (final k in const ['In-person', 'Online', 'Meet', 'Call', 'Summary']) RepCol(r, 'Make up', k),
        RepCol(r, 'Absentees'),
      ],
    ];

/// Counts for any set of members, from their reports of the period.
class AttEngine {
  final String field; // attendance_realtime or attendance_pre
  final int sessions;
  final Map<String, List<Map>> _byMember = {};

  AttEngine({required Iterable<dynamic> logs, required this.field, required this.sessions}) {
    for (final l in logs) {
      if (l is! Map) continue;
      final id = (l['member_id'] ?? (l['members'] is Map ? l['members']['id'] : null))?.toString();
      if (id == null || id.isEmpty) continue;
      _byMember.putIfAbsent(id, () => []).add(l);
    }
  }

  List<Map> logsOf(Map m) => _byMember[(m['id'] ?? '').toString()] ?? const [];

  static String flat(dynamic v) => CompStatus.norm(v).replaceAll(RegExp(r'[\s_\-.]'), '');

  /// '' (did not attend), ip, on, cl, mt or sm (any other way: Summary …)
  static String kind(dynamic v) {
    if (!CompStatus.isPositive(v)) return '';
    final f = flat(v);
    if (f == 'inperson' || f == 'ip' || f == 'present' || f == 'attended' || f == 'offline' || f == 'o') return 'ip';
    if (f == 'online' || f.contains('zoom')) return 'on';
    if (f.contains('call')) return 'cl';
    if (f.startsWith('meet')) return 'mt';
    return 'sm';
  }

  static String residence(Map m) {
    final g = CompStatus.norm(m['geo_category']);
    if (g.startsWith('kampala')) return 'Kampala';
    if (g.startsWith('village')) return 'Village';
    if (g.startsWith('abroad')) return 'Abroad';
    return '';
  }

  /// Active, H-M or LTA (members › Status)
  static String status(Map m) {
    final s = flat(m['member_status']);
    if (s == 'hm') return 'H-M';
    if (s == 'lta') return 'LTA';
    return 'Active';
  }

  static String reg(Map m) => (m['reg_status'] ?? '').toString().trim();
  static bool isNonReg(Map m) {
    final r = reg(m);
    return r == '보고예정자' || r == '보예' || (m['scj_id'] ?? '').toString().toUpperCase().startsWith('PRE');
  }

  static bool isHq(Map m) => const ['교회등록', '총회등록'].contains(reg(m));
  static bool isEnroll(Map m) => reg(m) == '입교';

  static String bol(Map m) {
    final b = (m['book_of_life'] ?? m['bol_dept'] ?? '').toString().trim();
    return b.replaceAll(RegExp(r'[()\s]'), '');
  }

  /// Current-department group: MOU, 24Dept (church departments) or the department.
  static String deptGroup(Map m) {
    if (CompLevel.isMou(m)) return 'MOU';
    if (CompLevel.locationBucket(m) == '24Dept') return '24Dept';
    return (m['department'] ?? '').toString().trim();
  }

  static String region(Map m) => CompLevel.locationBucket(m);

  /// The values of [attCols] for these members.
  List<num?> vals(List<Map<String, dynamic>> mems) {
    final n = mems.length;
    int att = 0, ip = 0, hm = 0, lta = 0;
    final act = {for (final r in kAttResidences) r: <String, int>{}};
    final mu = {for (final r in kAttResidences) r: <String, int>{}};
    final nR = {for (final r in kAttResidences) r: 0};
    final attR = {for (final r in kAttResidences) r: 0};
    for (final m in mems) {
      final st = status(m);
      if (st == 'H-M') hm++;
      if (st == 'LTA') lta++;
      final r = residence(m);
      if (r.isNotEmpty) nR[r] = nR[r]! + 1;
      for (final l in logsOf(m)) {
        final k = kind(l[field]);
        if (k.isNotEmpty) {
          att++;
          if (k == 'ip') ip++;
          if (r.isNotEmpty) {
            act[r]![k] = (act[r]![k] ?? 0) + 1;
            attR[r] = attR[r]! + 1;
          }
        }
        final mk = kind(l['attendance_makeup']);
        if (mk.isNotEmpty && r.isNotEmpty) mu[r]![mk] = (mu[r]![mk] ?? 0) + 1;
      }
    }
    num per(int v) => CompPeriod.avgPerSession(v, sessions);
    double pct(int v) => CompPeriod.pctOf(v, n, sessions);
    final a = per(att);
    num ab = n - a;
    if (ab < 0) ab = 0;
    return [
      n,
      a,
      pct(att),
      per(ip),
      pct(ip),
      per(att - ip),
      pct(att - ip),
      ab,
      n > 0 ? math.max(0.0, 100 - pct(att)) : 0,
      hm,
      lta,
      for (final r in kAttResidences) ...[
        for (final k in const ['ip', 'on', 'cl', 'mt', 'sm']) per(act[r]![k] ?? 0),
        for (final k in const ['ip', 'on', 'mt', 'cl', 'sm']) per(mu[r]![k] ?? 0),
        math.max(0, nR[r]! - per(attR[r]!)),
      ],
    ];
  }

  // ---------------------------------------------------------------- rows

  List<RepRow> head(String label, List<Map<String, dynamic>> mems) => [
        RepRow('', label, vals(mems), total: true),
        RepRow('Status', 'Church/H.Q', vals(mems.where(isHq).toList())),
        RepRow('Status', 'Enrollment', vals(mems.where(isEnroll).toList())),
      ];

  List<RepRow> by(String section, List<Map<String, dynamic>> mems, String Function(Map) key, List<String> order) {
    final g = <String, List<Map<String, dynamic>>>{};
    for (final m in mems) {
      g.putIfAbsent(key(m), () => []).add(m);
    }
    return [for (final k in order) RepRow(section, k, vals(g[k] ?? const []))];
  }

  /// Each key: its total, then Church/H.Q and Enrollment under it.
  List<RepRow> byTriple(String section, List<Map<String, dynamic>> mems, String Function(Map) key, List<String> order) {
    final out = <RepRow>[];
    for (final k in order) {
      final g = mems.where((m) => key(m) == k).toList();
      out.add(RepRow(section, k, vals(g)));
      out.add(RepRow(section, 'Church/H.Q', vals(g.where(isHq).toList()), sub: true));
      out.add(RepRow(section, 'Enrollment', vals(g.where(isEnroll).toList()), sub: true));
    }
    return out;
  }

  static List<String> regionOrder(Iterable<Map> mems) => CompLevel.orderNames(mems.map(region), 'Location status');
  static List<String> bolOrder(Iterable<Map> mems) {
    final have = mems.map(bol).toSet();
    return CompLevel.orderedBOLGroups.where(have.contains).toList();
  }
}

// ---------------------------------------------------------------------------

class AttendanceReports extends StatefulWidget {
  final AttReportKind kind;
  final List<dynamic> logs;
  final List<Map<String, dynamic>> members;
  final String timePeriod;
  final String periodLabel;

  /// Current dept status of a group's leaders: only their group (e.g. '장년회').
  final String? lockedGroup;

  /// Region chosen in the sidebar (Region status).
  final String? region;

  const AttendanceReports({
    super.key,
    required this.kind,
    required this.logs,
    required this.members,
    required this.timePeriod,
    this.periodLabel = '',
    this.lockedGroup,
    this.region,
  });

  @override
  State<AttendanceReports> createState() => _AttendanceReportsState();
}

class _AttendanceReportsState extends State<AttendanceReports> {
  static const Color _purple = Color(0xFF4A148C);
  String _day = 'Sun';
  bool _pre = false;
  String? _region;
  bool _deptView = false; // region report: SUMMARY or DEPT
  late String _group = _initialGroup();
  String _bol = 'Summary';
  bool _wide = false; // the Kampala / Village / Abroad columns

  /// Without the regional columns unless they are expanded.
  RepBlock _shown(RepBlock b) {
    if (_wide || b.cols.length <= 11) return b;
    return RepBlock(
      title: b.title,
      corner: b.corner,
      cols: b.cols.sublist(0, 11),
      rows: [for (final r in b.rows) RepRow(r.section, r.label, r.vals.length > 11 ? r.vals.sublist(0, 11) : r.vals, total: r.total, sub: r.sub)],
    );
  }

  String _initialGroup() {
    final l = widget.lockedGroup;
    if (l != null && l.isNotEmpty) {
      for (final g in kAttGroups) {
        if (g.$2 == l || g.$1.contains(l)) return g.$2;
      }
      return l;
    }
    return kAttGroups.first.$2;
  }

  bool get _current => widget.timePeriod == 'Current status';

  bool _onDay(dynamic l) {
    if (_current) return true;
    final day = CompStatus.norm(l['service_day']);
    if (day.startsWith('sun')) return _day == 'Sun';
    if (day.startsWith('wed')) return _day == 'Wed';
    final d = DateTime.tryParse((l['report_date'] ?? '').toString());
    if (d == null) return false;
    return _day == 'Sun' ? d.weekday == DateTime.sunday : d.weekday == DateTime.wednesday;
  }

  AttEngine _engine() {
    final logs = CompPeriod.onePerMemberWeek(widget.logs.where(_onDay));
    final sessions = _current ? 1 : CompPeriod.sessionCount(logs);
    return AttEngine(logs: logs, field: _pre ? 'attendance_pre' : 'attendance_realtime', sessions: sessions);
  }

  List<Map<String, dynamic>> get _eligible => widget.members.where((m) => !AttEngine.isNonReg(m)).toList();

  String _groupName(String key) => kAttGroups.firstWhere((g) => g.$2 == key, orElse: () => (key, key)).$1;

  // ---------------------------------------------------------------- blocks

  List<RepBlock> _regionBlocks(AttEngine e, List<Map<String, dynamic>> all, String region, {required bool dept}) {
    final mems = all.where((m) => AttEngine.region(m) == region).toList();
    final subs = CompLevel.naturalSort(mems.map((m) => (m['sub_location'] ?? '').toString().trim()).where((s) => s.isNotEmpty).toSet());
    RepBlock one(String name, List<Map<String, dynamic>> g) => RepBlock(
          title: "$name ${dept ? '— by department' : ''}".trim(),
          corner: name,
          cols: attCols(),
          rows: [
            ...e.head('Total', g),
            if (dept)
              ...e.byTriple('Dept', g, (m) => CompLevel.isMou(m) ? 'MOU' : (m['department'] ?? '').toString().trim(),
                  kAttDepts.where((d) => g.any((m) => (CompLevel.isMou(m) ? 'MOU' : (m['department'] ?? '').toString().trim()) == d)).toList())
            else
              ...e.byTriple('Group', g, AttEngine.bol, AttEngine.bolOrder(g)),
          ],
        );
    return [
      one(region, mems),
      for (final s in subs) one(s, mems.where((m) => (m['sub_location'] ?? '').toString().trim() == s).toList()),
    ];
  }

  List<RepBlock> _groupBlocks(AttEngine e, List<Map<String, dynamic>> all, String key) {
    final mems = all.where((m) => AttEngine.deptGroup(m) == key).toList();
    final name = _groupName(key);
    // the church's 24 departments are listed by department, the rest by region
    final is24 = key == '24Dept';
    String rowKey(Map m) => is24 ? ((m['department'] ?? '').toString().trim().isEmpty ? 'Other' : (m['department'] ?? '').toString().trim()) : AttEngine.region(m);
    List<String> rowOrder(List<Map<String, dynamic>> g) =>
        is24 ? CompLevel.naturalSort(g.map(rowKey).toSet()) : AttEngine.regionOrder(g);
    final sec = is24 ? 'Departments' : 'Regions';
    final bols = AttEngine.bolOrder(mems);
    return [
      RepBlock(title: "$name — Overall", corner: 'Overall', cols: attCols(), rows: [...e.head('Total', mems), ...e.by(sec, mems, rowKey, rowOrder(mems))]),
      RepBlock(title: "$name — Book of Life", corner: name, cols: attCols(), rows: [...e.head('Total', mems), ...e.by('Group', mems, AttEngine.bol, bols)]),
      for (final b in bols)
        () {
          final g = mems.where((m) => AttEngine.bol(m) == b).toList();
          return RepBlock(title: "$name ($b)", corner: b, cols: attCols(), rows: [...e.head('Total', g), ...e.by(sec, g, rowKey, rowOrder(g))]);
        }(),
    ];
  }

  RepBlock _bolSummary(AttEngine e, List<Map<String, dynamic>> all) => RepBlock(
        title: 'Book of Life — Summary',
        corner: 'Church',
        cols: attCols(),
        rows: [...e.head('Total', all), ...e.by('Group', all, AttEngine.bol, CompLevel.orderedBOLGroups)],
      );

  RepBlock _bolBlock(AttEngine e, List<Map<String, dynamic>> all, String b) {
    final g = all.where((m) => AttEngine.bol(m) == b).toList();
    return RepBlock(title: b, corner: b, cols: attCols(), rows: [...e.head('Total', g), ...e.by('Regions', g, AttEngine.region, AttEngine.regionOrder(g))]);
  }

  // ---------------------------------------------------------------- Excel

  Future<void> _download() async {
    final e = _engine();
    final all = _eligible;
    final book = RepBook();
    final stamp = "${widget.periodLabel.isEmpty ? '' : '${widget.periodLabel} · '}${_current ? '' : '$_day · '}${_pre ? 'Pre-attendance' : 'Real-time'}";
    String fileName;
    void put(String sheetName, String heading, List<RepBlock> blocks) {
      final s = book.sheet(sheetName);
      s.title(heading);
      s.title(stamp, size: 10);
      s.gap();
      for (final b in blocks) {
        s.block(b);
      }
      s.widths(12, 18, 9, attCols().length + 2);
    }

    switch (widget.kind) {
      case AttReportKind.region: {
        final r = _region ?? '';
        put('SUMMARY', '$r ${tr('final attendance')}', _regionBlocks(e, all, r, dept: false));
        put('DEPT', '$r ${tr('final attendance by department')}', _regionBlocks(e, all, r, dept: true));
        fileName = '${r}_Service_Attendance';
      }
      case AttReportKind.currentDept: {
        final keys = widget.lockedGroup != null ? [_group] : kAttGroups.map((g) => g.$2).toList();
        for (final k in keys) {
          put(_groupName(k), '${_groupName(k)} ${tr('final attendance')}', _groupBlocks(e, all, k));
        }
        fileName = widget.lockedGroup != null ? '${_groupName(_group)}_Attendance' : 'Current_Dept_Status_Attendance';
      }
      case AttReportKind.bookOfLife: {
        put('Summary', tr('Book of Life — Summary'), [_bolSummary(e, all)]);
        for (final b in CompLevel.orderedBOLGroups) {
          put(b, '$b ${tr('final attendance')}', [_bolBlock(e, all, b)]);
        }
        fileName = 'Book_of_Life_Attendance';
      }
    }
    if (!mounted) return;
    await book.save(context, "${fileName.replaceAll(' ', '_')}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}");
  }

  // ---------------------------------------------------------------- charts

  /// Attendance % and In-person % of each row of a section.
  Widget _ratesChart(RepBlock b, String section) {
    final rows = b.rows.where((r) => r.section == section && (r.vals.first ?? 0) > 0).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return _chartCard(
      "Attendance % and In-person % — ${b.corner}",
      Bar3DChart(labels: [for (final r in rows) r.label], height: 270, series: [
        Bar3DSeries(tr("Attendance %"), kLightSeries[0], [for (final r in rows) (r.vals[2] ?? 0).clamp(0, 100).toDouble()], pct: true),
        Bar3DSeries(tr("In-person %"), kLightSeries[3], [for (final r in rows) (r.vals[4] ?? 0).clamp(0, 100).toDouble()], pct: true),
      ]),
    );
  }

  /// Online, Call and Other ways (Meet, Summary) for Kampala / Village / Abroad.
  Widget _methodChart(RepBlock b) {
    final t = b.rows.first.vals;
    double v(int i) => (t.length > i ? (t[i] ?? 0) : 0).toDouble();
    final groups = <(String, double, double, double)>[
      for (int r = 0; r < kAttResidences.length; r++) (kAttResidences[r], v(11 + r * 11 + 1), v(11 + r * 11 + 2), v(11 + r * 11 + 3) + v(11 + r * 11 + 4)),
    ];
    final maxY = groups.map((g) => math.max(g.$2, math.max(g.$3, g.$4))).fold<double>(0, math.max);
    if (maxY <= 0) return const SizedBox.shrink();
    return _chartCard(
      "Other ways of attending, by residence — ${b.corner}",
      Bar3DChart(labels: [for (final g in groups) tr(g.$1)], height: 240, series: [
        Bar3DSeries(tr("Online"), kLightSeries[1], [for (final g in groups) g.$2]),
        Bar3DSeries(tr("Call"), kLightSeries[4], [for (final g in groups) g.$3]),
        Bar3DSeries(tr("Other ways (Meet, Summary)"), kLightSeries[2], [for (final g in groups) g.$4]),
      ]),
    );
  }

  /// A chart in its own card, apart from the tables.
  Widget _chartCard(String title, Widget chart) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.line(const Color(0x224A148C))),
        ),
        child: Column(children: [_chartTitle(title), chart]),
      );

  Widget _chartTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(text: t), textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppPalette.fg(_purple))),
      );

  // ---------------------------------------------------------------- UI

  Widget _dropdown(List<String> items, String value, ValueChanged<String> on, {String Function(String)? label}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.line(Colors.purple.shade200)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: items.contains(value) ? value : (items.isEmpty ? null : items.first),
            isDense: true,
            items: [
              for (final i in items)
                DropdownMenuItem(value: i, child: Text.rich(TextSpan(text: label == null ? i : label(i)), style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold))),
            ],
            onChanged: (v) {
              if (v != null) on(v);
            },
          ),
        ),
      );

  Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(right: 8, bottom: 8), child: w);

  /// Service day, Real-time / Pre, the regional columns, then [extra].
  Widget _toolbar(List<Widget> extra) => Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final w in extra.take(extra.length - 1)) _gap(w),
          if (!_current) _gap(_dropdown(const ['Sun', 'Wed'], _day, (v) => setState(() => _day = v), label: (d) => d == 'Sun' ? tr('Sunday service') : tr('Wednesday service'))),
          _gap(_dropdown(const ['rt', 'pre'], _pre ? 'pre' : 'rt', (v) => setState(() => _pre = v == 'pre'), label: (d) => d == 'pre' ? tr('Pre-attendance') : tr('Real-time'))),
          _gap(TextButton.icon(
            onPressed: () => setState(() => _wide = !_wide),
            icon: Icon(_wide ? Icons.close_fullscreen : Icons.open_in_full, size: 14),
            label: Text(_wide ? "Collapse regional grid" : "Expand regional grid", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(_purple))),
          )),
          if (extra.isNotEmpty) extra.last,
        ],
      );

  Widget _blockCard(RepBlock full, {List<Widget> below = const [], void Function(RepRow)? onTap}) {
    final b = _shown(full);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RepCard(
        title: b.title,
        actions: [
          repAction(Icons.fullscreen_rounded, 'Full screen', () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (c) => Scaffold(
                  appBar: AppBar(title: Text.rich(TextSpan(text: b.title))),
                  body: SingleChildScrollView(padding: const EdgeInsets.all(10), child: ZoomBox(child: _rep(b))),
                ),
              ),
            );
          }),
        ],
        child: ZoomBox(child: _rep(b, onTap: onTap)),
      ),
      ...below,
      if (below.isNotEmpty) const SizedBox(height: 6),
    ]);
  }

  Widget _rep(RepBlock b, {void Function(RepRow)? onTap}) =>
      RepTable(block: b, onTapRow: onTap, fill: true, labelW: 150, sectionW: 84, cellW: 58, maxCell: 120, fontSize: 11, rowH: 26, headH: 30);

  @override
  Widget build(BuildContext context) {
    final e = _engine();
    final all = _eligible;
    final download = ExportOnly(
      child: Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 6),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B7F3B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: _download,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text("Excel"),
        ),
      ),
    );

    final children = <Widget>[];
    switch (widget.kind) {
      case AttReportKind.region: {
        final regions = AttEngine.regionOrder(all).where((r) => r != 'Other').toList();
        _region ??= (widget.region != null && regions.contains(widget.region)) ? widget.region : (regions.isEmpty ? null : regions.first);
        children.add(_toolbar([
          if (regions.isNotEmpty) _dropdown(regions, _region!, (v) => setState(() => _region = v)),
          _dropdown(const ['s', 'd'], _deptView ? 'd' : 's', (v) => setState(() => _deptView = v == 'd'), label: (d) => d == 'd' ? 'DEPT' : 'SUMMARY'),
          download,
        ]));
        if (_region != null) {
          for (final b in _regionBlocks(e, all, _region!, dept: _deptView)) {
            children.add(_blockCard(b));
          }
        }
      }
      case AttReportKind.currentDept: {
        final locked = widget.lockedGroup != null;
        children.add(_toolbar([
          if (!locked) _dropdown(kAttGroups.map((g) => g.$2).toList(), _group, (v) => setState(() => _group = v), label: _groupName),
          download,
        ]));
        final blocks = _groupBlocks(e, all, _group);
        for (int i = 0; i < blocks.length; i++) {
          final b = blocks[i];
          children.add(_blockCard(b, below: [
            if (i == 0) ...[_ratesChart(b, _group == '24Dept' ? 'Departments' : 'Regions'), _methodChart(b)],
            if (i == 1) _ratesChart(b, 'Group'),
          ]));
        }
      }
      case AttReportKind.bookOfLife: {
        children.add(_toolbar([
          _dropdown(['Summary', ...CompLevel.orderedBOLGroups], _bol, (v) => setState(() => _bol = v), label: (g) => tr(g)),
          download,
        ]));
        if (_bol == 'Summary') {
          final b = _bolSummary(e, all);
          children.add(_blockCard(b,
              below: [_ratesChart(b, 'Group'), _methodChart(b)],
              onTap: (r) {
                if (CompLevel.orderedBOLGroups.contains(r.label)) setState(() => _bol = r.label);
              }));
        } else {
          final b = _bolBlock(e, all, _bol);
          children.add(_blockCard(b, below: [_ratesChart(b, 'Regions'), _methodChart(b)]));
        }
      }
    }

    final title = switch (widget.kind) {
      AttReportKind.region => 'Region SUMMARY and DEPT tables',
      AttReportKind.currentDept => 'Current dept status',
      AttReportKind.bookOfLife => 'Group status by Book of Life',
    };
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.bg(const Color(0xFFF8F5FF)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.line(const Color(0x334A148C))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 14.5, fontWeight: FontWeight.w900, color: AppPalette.fg(_purple))),
        const SizedBox(height: 4),
        Text(
          "Laid out like the church's Excel sheets. Non-registered members (보고예정자) are not counted here; they have their own list.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700)),
        ),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 보예: members not registered yet
// ---------------------------------------------------------------------------

class NonRegisteredListScreen extends StatefulWidget {
  final List<dynamic> logs;
  final List<Map<String, dynamic>> members;
  final String periodLabel;
  const NonRegisteredListScreen({super.key, required this.logs, required this.members, this.periodLabel = ''});

  @override
  State<NonRegisteredListScreen> createState() => _NonRegisteredListScreenState();
}

class _NonRegisteredListScreenState extends State<NonRegisteredListScreen> {
  static const Color _purple = Color(0xFF4A148C);
  String _region = 'All';
  String _q = '';

  List<Map<String, dynamic>> get _rows {
    final list = widget.members.where(AttEngine.isNonReg).toList();
    final order = AttEngine.regionOrder(list);
    int rank(Map m) => order.indexOf(AttEngine.region(m));
    String s(Map m, String k) => (m[k] ?? '').toString();
    list.sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      if (c != 0) return c;
      for (final k in const ['sub_location', 'department', 'team', 'cell_group', 'english_name']) {
        final x = CompLevel.naturalSort([s(a, k), s(b, k)]);
        if (s(a, k) != s(b, k)) return x.first == s(a, k) ? -1 : 1;
      }
      return 0;
    });
    return list;
  }

  /// Service dates of the period (from the reports).
  List<DateTime> get _dates {
    final set = <String>{};
    for (final l in widget.logs) {
      if (l is! Map) continue;
      final d = DateTime.tryParse((l['report_date'] ?? '').toString());
      if (d != null && (d.weekday == DateTime.sunday || d.weekday == DateTime.wednesday)) set.add(DateFormat('yyyy-MM-dd').format(d));
    }
    return (set.toList()..sort()).map(DateTime.parse).toList();
  }

  String _ord(int d) {
    if (d >= 11 && d <= 13) return '${d}th';
    return switch (d % 10) { 1 => '${d}st', 2 => '${d}nd', 3 => '${d}rd', _ => '${d}th' };
  }

  String _dateHead(DateTime d) => "${_ord(d.day)}(${d.weekday == DateTime.sunday ? 'Sun' : 'Wed'})";

  @override
  Widget build(BuildContext context) {
    final dates = _dates;
    final byMember = <String, Map<String, dynamic>>{};
    for (final l in widget.logs) {
      if (l is! Map) continue;
      final id = (l['member_id'] ?? (l['members'] is Map ? l['members']['id'] : null))?.toString();
      final d = (l['report_date'] ?? '').toString();
      if (id == null || d.length < 10) continue;
      byMember['$id|${d.substring(0, 10)}'] = Map<String, dynamic>.from(l);
    }
    String mark(Map m, DateTime d) {
      final l = byMember['${m['id']}|${DateFormat('yyyy-MM-dd').format(d)}'];
      return l != null && AttEngine.kind(l['attendance_realtime']).isNotEmpty ? 'O' : 'X';
    }

    final all = _rows;
    final regions = ['All', ...AttEngine.regionOrder(all)];
    final rows = all.where((m) {
      if (_region != 'All' && AttEngine.region(m) != _region) return false;
      if (_q.isEmpty) return true;
      return [m['english_name'], m['korean_name'], m['center_code'], m['scj_id']].any((v) => (v ?? '').toString().toLowerCase().contains(_q));
    }).toList();

    const heads = ['No.', 'Region', 'Sub Region', 'Dept', 'Team', 'Cell', 'Duty', 'English name', 'REG status', 'Center code'];
    const widths = [44.0, 96.0, 110.0, 80.0, 60.0, 50.0, 80.0, 170.0, 90.0, 96.0];
    List<String> cells(int i, Map m) => [
          '${i + 1}',
          AttEngine.region(m),
          (m['sub_location'] ?? '').toString(),
          (m['department'] ?? '').toString(),
          (m['team'] ?? '').toString(),
          (m['cell_group'] ?? '').toString(),
          (m['duty'] ?? '').toString(),
          (m['english_name'] ?? '').toString(),
          AttEngine.reg(m),
          (m['center_code'] ?? '').toString(),
        ];

    Future<void> download() async {
      final book = RepBook();
      final s = book.sheet('보예');
      s.title("${tr('Uganda')} 보고예정자 ${widget.periodLabel}");
      s.gap();
      s.table(
        [...heads, for (final d in dates) _dateHead(d)],
        [
          for (int i = 0; i < rows.length; i++) [...cells(i, rows[i]), for (final d in dates) mark(rows[i], d)],
        ],
      );
      s.widths(6, 14, 16, heads.length + dates.length);
      await book.save(context, "Non_registered_members_${DateFormat('yyyy-MM-dd').format(DateTime.now())}");
    }

    final line = AppPalette.line(Colors.black26);
    Widget cell(String t, double w, {bool head = false, Color? bg, Color? fg}) => Container(
          width: w,
          height: head ? 30 : 26,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(color: AppPalette.bg(bg ?? (head ? const Color(0xFFE9DDFB) : Colors.white)), border: Border.all(color: line, width: 0.5)),
          child: Text.rich(TextSpan(text: head ? tr(t) : t),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: head ? 10.5 : 10.5, fontWeight: head ? FontWeight.w900 : null, color: fg)),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text("Non-registered members (보예)", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900)),
        actions: [
          ExportOnly(child: IconButton(tooltip: tr('Download Excel'), icon: const Icon(Icons.download_rounded), onPressed: rows.isEmpty ? null : download)),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 240,
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: tr('Search name or center code'),
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            DropdownButton<String>(
              value: regions.contains(_region) ? _region : 'All',
              items: [for (final r in regions) DropdownMenuItem(value: r, child: Text.rich(TextSpan(text: r == 'All' ? tr('All Regions') : r)))],
              onChanged: (v) => setState(() => _region = v ?? 'All'),
            ),
            Text.rich(TextSpan(text: "${rows.length} ${tr('members')} · ${dates.length} ${tr('services')}"),
                style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppPalette.fg(_purple))),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, bc) {
            // centred when it is narrower than the screen
            final tableW = widths.fold<double>(0, (a, b) => a + b) + (dates.isEmpty ? 140 : dates.length * 70) + 24;
            return Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableW < bc.maxWidth ? bc.maxWidth : tableW,
                      child: Center(
                      child: SizedBox(
                      width: tableW,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        // with nobody to list, the table still shows its headers and empty rows
                        itemCount: (rows.isEmpty ? 10 : rows.length) + 1,
                        itemBuilder: (c, i) {
                          if (i == 0) {
                            return Row(children: [
                              for (int k = 0; k < heads.length; k++) cell(heads[k], widths[k], head: true),
                              for (final d in dates) cell(_dateHead(d), 70, head: true),
                              if (dates.isEmpty) cell('Services', 140, head: true),
                            ]);
                          }
                          if (rows.isEmpty) {
                            return Row(children: [
                              for (int k = 0; k < heads.length; k++) cell(k == 0 ? '$i' : (i == 1 && k == 7 ? tr('No non-registered members in this view') : ''), widths[k]),
                              for (final _ in dates) cell('', 70),
                              if (dates.isEmpty) cell('', 140),
                            ]);
                          }
                          final m = rows[i - 1];
                          final v = cells(i - 1, m);
                          return Row(children: [
                            for (int k = 0; k < heads.length; k++) cell(v[k], widths[k]),
                            for (final d in dates)
                              () {
                                final o = mark(m, d) == 'O';
                                return cell(o ? 'O' : 'X', 70,
                                    bg: o ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE), fg: o ? const Color(0xFF1B7F3B) : const Color(0xFFB3261E));
                              }(),
                            if (dates.isEmpty) cell('', 140),
                          ]);
                        },
                      ),
                    ),
                    ),
                    ),
                  ),
                );
          }),
        ),
      ]),
    );
  }
}
