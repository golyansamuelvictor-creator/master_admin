import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';
import '../../core/compilation_rules.dart';
import '../../core/friendly_error.dart';
import '../../core/i18n.dart';
import '../../core/rep_table.dart';
import '../../core/security.dart';
import '../../widgets/bar3d_chart.dart';
import '../../widgets/zoom_box.dart';

const Color _kPurple = Color(0xFF4A148C);
const Color _kGreen = Color(0xFF2E7D32);
const Color _kLight = Color(0xFFEDE4FA); // selected chips, headers
const Color _kGoal = Color(0xFFB0BEC5);
const Color _kOverall = Color(0xFFB39DDB);

/// Evangelism Department (church level): the 전도부 sheets in the app.
///  * Evangelism results › Center reports (4 sections): Results By Center
///    (current status, or a week day by day), Results By Groups (guide's
///    current department), 24 Depts Results (General / In-person / Online),
///    Results By Opening Month (D-day, achievement, Telegram text).
///  * Evangelism Participation: participation by group (guide / BB teacher).
///  * Evangelism policies, standards & goals: Goals › By center place and
///    24 Departments; Opening months (dates).
/// Data: evangelism_center_report / evangelism_daily_snapshot (33_round32.sql).
/// What the screen shows: the 4 results sections (Evangelism results), the
/// participation section (Evangelism Participation), or one of the settings
/// parts (Evangelism policies, standards & goals: Goals, Opening months).
enum CenterView { results, participation, centerGoals, deptGoals, months }

class CenterReportsScreen extends StatefulWidget {
  final CenterView view;

  /// Inside another screen (no title bar of its own).
  final bool embedded;
  const CenterReportsScreen({super.key, this.view = CenterView.results, this.embedded = false});
  @override
  State<CenterReportsScreen> createState() => _CenterReportsScreenState();
}

class _Stu {
  final String center, month, stage, bb, gLoc, gDept, gOdept;
  final bool q, g24, byStudent;
  final String region; // guide's region bucket (Wakiso … / MOU / 24Dept)
  _Stu(List r)
      : center = (r[0] ?? '').toString().trim(),
        month = (r[1] ?? '').toString().trim(),
        stage = (r[2] ?? '').toString().trim(),
        bb = (r[3] ?? '').toString(),
        q = r[4] == true,
        gLoc = (r[5] ?? '').toString().trim(),
        gDept = (r[6] ?? '').toString().trim(),
        g24 = r[7] == true,
        gOdept = (r[8] ?? '').toString().trim(),
        byStudent = r.length > 9 && r[9] == true,
        region = CompLevel.locationBucket({'location': (r[5] ?? '').toString(), 'department': (r[6] ?? '').toString()});
}

class _Center {
  final String id, region, center, month;
  final int goal, sort;
  final bool online;
  _Center(Map m)
      : id = (m['id'] ?? '').toString(),
        region = (m['region'] ?? '').toString(),
        center = (m['center'] ?? '').toString(),
        month = (m['month'] ?? '').toString(),
        goal = (m['goal'] as num?)?.toInt() ?? 0,
        sort = (m['sort'] as num?)?.toInt() ?? 100,
        online = m['online'] == true;
}

/// Group of a guide by current department (Groups / Participation).
const List<(String, String)> _kGroups = [
  ('General', ''),
  ('24 Depts', '24'),
  ('MG (장년회)', '장년회'),
  ('WG (부녀회)', '부녀회'),
  ('YAG (청년회)', '청년회'),
  ('Theology (신학부)', '신학부'),
  ('New Saints (새신자)', '새신자'),
  ('MOU', 'MOU'),
];

String _n(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');

class _CenterReportsScreenState extends State<CenterReportsScreen> with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  TabController? _tabsC;
  TabController get _tabs => _tabsC ??= TabController(length: 4, vsync: this);

  bool _loading = true;
  String? _error;
  List<String> _stages = [];
  Set<String> _overall = {};
  List<Map<String, dynamic>> _months = [];
  List<_Center> _centers = [];
  List<Map<String, dynamic>> _deptGoals = [];
  List<_Stu> _students = [];
  List<List> _members = [];
  DateTime? _asOf;

  String? _month; // Opening month tab
  String _groupsMonth = 'General';
  String _deptMonth = 'General';
  DateTime _week = _monday(DateTime.now());
  List<List>? _snap;
  bool _snapLoading = false;

  static DateTime _monday(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabsC?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('evangelism_center_report') as Map);
      final st = List<Map<String, dynamic>>.from((r['stages'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
      if (!mounted) return;
      setState(() {
        _stages = [for (final s in st) s['stage'].toString()];
        _overall = {for (final s in st) if (s['in_overall'] == true) s['stage'].toString()};
        _months = List<Map<String, dynamic>>.from((r['months'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
        _centers = [for (final c in (r['centers'] as List? ?? [])) _Center(c as Map)]..sort((a, b) => a.sort.compareTo(b.sort));
        _deptGoals = List<Map<String, dynamic>>.from((r['dept_goals'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
        _students = [for (final s in (r['students'] as List? ?? [])) _Stu(s as List)];
        _members = [for (final m in (r['members'] as List? ?? [])) m as List];
        _asOf = DateTime.tryParse((r['as_of'] ?? '').toString())?.toLocal();
        final ms = _goalMonths;
        if (_month == null || !ms.contains(_month)) _month = ms.isEmpty ? null : ms.first;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load the center reports${friendlyTail(e)}";
        });
      }
    }
  }

  // ------------------------------------------------------------------ numbers

  /// Opening months that have centers, in calendar order.
  List<String> get _goalMonths {
    final have = _centers.map((c) => _n(c.month)).toSet();
    final out = <String>[
      for (final m in _months)
        if (have.contains(_n(m['label'].toString()))) m['label'].toString(),
    ];
    for (final c in _centers) {
      if (!out.any((m) => _n(m) == _n(c.month))) out.add(c.month);
    }
    return out;
  }

  Map<String, dynamic>? _monthInfo(String label) {
    for (final m in _months) {
      if (_n(m['label'].toString()) == _n(label)) return m;
    }
    return null;
  }

  bool _isCenter(_Stu s, _Center c) => _n(s.center) == _n(c.center) && _n(s.month) == _n(c.month);

  _Center? _centerOf(_Stu s) {
    for (final c in _centers) {
      if (_isCenter(s, c)) return c;
    }
    return null;
  }

  /// Stage counts of the qualified students, then Overall.
  List<int> _counts(Iterable<_Stu> list) {
    final m = <String, int>{};
    for (final s in list) {
      if (!s.q) continue;
      m[s.stage] = (m[s.stage] ?? 0) + 1;
    }
    final row = [for (final st in _stages) m[st] ?? 0];
    final overall = [for (int i = 0; i < _stages.length; i++) if (_overall.contains(_stages[i])) row[i]].fold<int>(0, (a, b) => a + b);
    return [...row, overall];
  }

  int _stageCount(List<int> c, String stage) {
    final i = _stages.indexOf(stage);
    return i < 0 ? 0 : c[i];
  }

  /// Possible → the end (every stage after the first, Chakki)
  int _posToCon(List<int> c) => c.length <= 2 ? 0 : c.sublist(1, _stages.length).fold<int>(0, (a, b) => a + b);

  List<RepCol> get _stageCols => [for (final s in _stages) RepCol(s), const RepCol('Overall')];

  bool _inGroup(_Stu s, String key) {
    if (key.isEmpty) return true;
    if (key == '24') return s.g24;
    if (key == 'MOU') return s.region == CompLevel.mou;
    return _n(s.gDept) == _n(key) && s.region != CompLevel.mou;
  }

  String _regionLabel(String r) => r == '24Dept' ? 'Church' : r;

  List<String> _regionOrder(Iterable<String> keys) {
    final ord = CompLevel.orderNames(keys.where((k) => k != '24Dept' && k != CompLevel.mou), 'Location status');
    return [...ord, if (keys.contains('24Dept')) '24Dept', if (keys.contains(CompLevel.mou)) CompLevel.mou];
  }

  String _slash(List<int> c) => c.join('/');

  // ------------------------------------------------------------------ UI bits

  Widget _chip(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 6),
        child: ChoiceChip(
          label: Text.rich(TextSpan(text: tr(label)), style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: on ? FontWeight.w900 : FontWeight.w600, color: AppPalette.fg(_kPurple))),
          selected: on,
          showCheckmark: false,
          backgroundColor: AppPalette.bg(Colors.white),
          selectedColor: AppPalette.bg(_kLight),
          side: BorderSide(color: AppPalette.line(on ? const Color(0x664A148C) : const Color(0x224A148C))),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onSelected: (_) => tap(),
        ),
      );

  Widget _excelButton(VoidCallback onTap) => ExportOnly(
        child: Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: AppPalette.bg(const Color(0xFFE3F2E5)),
                foregroundColor: AppPalette.fg(_kGreen),
                side: BorderSide(color: AppPalette.line(const Color(0x552E7D32))),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
            onPressed: onTap,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text("Excel"),
          ),
        ),
      );

  Widget _table(RepBlock b, {List<Widget> below = const []}) => RepCard(
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [ZoomBox(child: _rep(b)), ...below]),
      );

  Widget _rep(RepBlock b) => RepTable(block: b, sectionW: 96, labelW: 176, cellW: 64, maxCell: 130, fill: true, fontSize: 12, rowH: 30, headH: 38);

  /// The page of a section: centred, at most 1400 wide; inside another
  /// screen it is a plain column.
  Widget _page(List<Widget> children) {
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    if (widget.embedded && widget.view == CenterView.participation) return body;
    return ListView(padding: const EdgeInsets.fromLTRB(12, 14, 12, 24), children: [
      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1400), child: body)),
    ]);
  }

  /// A centred row of chips / buttons.
  Widget _bar(List<Widget> items) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: items),
      );

  Widget _copyBox(String title, String text) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppPalette.bg(const Color(0xFFF1F8FF)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.line(const Color(0x331E3A8A))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.send_rounded, size: 16, color: Color(0xFF1E3A8A)),
            const SizedBox(width: 6),
            Expanded(child: Text.rich(TextSpan(text: tr(title)), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12.5))),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied. Paste it in Telegram."), behavior: SnackBarBehavior.floating));
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text("Copy"),
            ),
          ]),
          SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4)),
        ]),
      );

  Widget _goalChart(String title, List<(String, int, int)> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(children: [
        Text.rich(TextSpan(text: tr(title)), textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
        const SizedBox(height: 8),
        Bar3DChart(
          labels: [for (final r in rows) r.$1],
          series: [
            Bar3DSeries(tr('Goal'), _kGoal, [for (final r in rows) r.$2.toDouble()]),
            Bar3DSeries(tr('Overall'), _kOverall, [for (final r in rows) r.$3.toDouble()]),
          ],
        ),
      ]),
    );
  }

  String _stamp() => _asOf == null ? '' : "${tr('As of')} ${DateFormat('d MMM yyyy HH:mm').format(_asOf!)}";

  // ------------------------------------------------------------------ 1. Centers

  RepBlock _centersBlock() {
    final cols = <RepCol>[
      const RepCol('Month'),
      const RepCol('Goal'),
      ..._stageCols,
      const RepCol('Students', 'Total'),
      const RepCol('Students', 'Qualified'),
      const RepCol('Students', 'Lacking'),
    ];
    // month shown as its number in the calendar (column), name in the label
    final rows = <RepRow>[];
    final totalGoal = _centers.fold<int>(0, (a, c) => a + c.goal);
    rows.add(RepRow('', 'Total', [null, totalGoal, ..._counts(_students), _students.length, _students.where((s) => s.q).length, _students.where((s) => !s.q).length], total: true));
    for (final c in _centers) {
      final list = _students.where((s) => _isCenter(s, c)).toList();
      rows.add(RepRow(c.region, "${c.center} (${c.month})", [null, c.goal, ..._counts(list), list.length, list.where((s) => s.q).length, list.where((s) => !s.q).length]));
    }
    // students at a center / month that has no goal yet
    final other = _students.where((s) => _centerOf(s) == null).toList();
    final keys = <String>{for (final s in other) "${s.center} (${s.month.isEmpty ? '—' : s.month})"};
    for (final k in CompLevel.naturalSort(keys)) {
      final list = other.where((s) => "${s.center} (${s.month.isEmpty ? '—' : s.month})" == k).toList();
      rows.add(RepRow('No goal yet', k, [null, null, ..._counts(list), list.length, list.where((s) => s.q).length, list.where((s) => !s.q).length]));
    }
    return RepBlock(title: 'Results By Center', corner: 'Region · Center Place (Month)', cols: cols.sublist(1), rows: [for (final r in rows) RepRow(r.section, r.label, r.vals.sublist(1), total: r.total)]);
  }

  /// Results By Center: the current status, or a week day by day.
  bool _weekView = false;

  Widget _centerSwitch() => _bar([
        _chip('Current status', !_weekView, () => setState(() => _weekView = false)),
        _chip('Week by day', _weekView, () => setState(() => _weekView = true)),
      ]);

  Widget _note(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
      );

  Widget _centersTab() {
    if (_weekView) return _weeklyTab();
    final b = _centersBlock();
    return _page([
      _centerSwitch(),
      _bar([
        _excelButton(() async {
          final book = RepBook();
          final s = book.sheet('General');
          s.title(tr('Center Status'));
          s.title(_stamp(), size: 10);
          s.gap();
          s.block(b);
          s.widths(14, 26, 10, b.cols.length + 2);
          await book.save(context, 'Center_Status_${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
        }),
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 6),
          child: Text.rich(TextSpan(text: _stamp()), style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
        ),
      ]),
      _table(b, below: [
        _goalChart('Goal and Overall by center place', [
          for (final c in _centers) ("${c.center} (${c.month.length > 3 ? c.month.substring(0, 3) : c.month})", c.goal, _counts(_students.where((s) => _isCenter(s, c))).last),
        ]),
      ]),
    ]);
  }

  // ------------------------------------------------------------------ 2. Opening month

  String _dday(dynamic v) {
    final d = DateTime.tryParse((v ?? '').toString());
    if (d == null) return '';
    final today = DateTime.now();
    final diff = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    final when = DateFormat('EEE d MMM yyyy').format(d);
    if (diff == 0) return "$when · D-day";
    return diff > 0 ? "$when · D-$diff" : "$when · D+${-diff}";
  }

  /// Goal, Con, Con %, Interview pass, Interview %, 0.6C goal, Pos→Con, 0.6C %, stages…, Overall
  List<num?> _monthVals(int goal, List<int> c) {
    final con = c.last;
    final pass = _stageCount(c, 'Passed Interview');
    final c06 = goal / 0.6;
    final p2c = _posToCon(c);
    return [
      goal,
      con,
      goal > 0 ? con / goal * 100 : null,
      pass,
      goal > 0 ? pass / goal * 100 : null,
      (c06 * 10).round() / 10,
      p2c,
      c06 > 0 ? p2c / c06 * 100 : null,
      ...c,
    ];
  }

  List<RepCol> get _monthCols => [
        const RepCol('Goal'),
        const RepCol('Con'),
        const RepCol('Con Ach%', '', '', true),
        const RepCol('Interview Pass'),
        const RepCol('Interview Ach%', '', '', true),
        const RepCol('0.6C Goal'),
        const RepCol('Pos to Con'),
        const RepCol('0.6C Ach%', '', '', true),
        ..._stageCols,
      ];

  List<RepBlock> _monthBlocks(String month) {
    final cs = _centers.where((c) => _n(c.month) == _n(month)).toList();
    List<_Stu> of(Iterable<_Center> list) => _students.where((s) => list.any((c) => _isCenter(s, c))).toList();
    int goal(Iterable<_Center> list) => list.fold<int>(0, (a, c) => a + c.goal);
    final ip = cs.where((c) => !c.online).toList(), on = cs.where((c) => c.online).toList();
    final summary = RepBlock(
      title: "$month — Church status",
      corner: month,
      cols: _monthCols,
      rows: [
        RepRow('', 'Total', _monthVals(goal(cs), _counts(of(cs))), total: true),
        RepRow('Way', 'In-person', _monthVals(goal(ip), _counts(of(ip)))),
        RepRow('Way', 'Online', _monthVals(goal(on), _counts(of(on)))),
      ],
    );
    final centers = RepBlock(
      title: "$month — Center places",
      corner: 'Region · Center Place',
      cols: _monthCols,
      rows: [
        RepRow('', 'Total', _monthVals(goal(cs), _counts(of(cs))), total: true),
        for (final c in cs) RepRow(c.region, "${c.center}${c.online ? ' (Online)' : ''}", _monthVals(c.goal, _counts(of([c])))),
      ],
    );
    // the 24 departments: students of this month's centers whose guide works in one
    final dg = _deptGoals.where((g) => _n(g['month'].toString()) == _n(month)).toList()..sort((a, b) => ((a['sort'] as num?) ?? 0).compareTo((b['sort'] as num?) ?? 0));
    final mStudents = of(cs).where((s) => s.g24).toList();
    final depts = <String>[for (final g in dg) g['dept'].toString()];
    for (final s in mStudents) {
      if (s.gOdept.isNotEmpty && !depts.any((d) => _n(d) == _n(s.gOdept))) depts.add(s.gOdept);
    }
    int dGoal(String d) => dg.where((g) => _n(g['dept'].toString()) == _n(d)).fold<int>(0, (a, g) => a + ((g['goal'] as num?)?.toInt() ?? 0));
    final deptBlock = RepBlock(
      title: "$month — 24 Departments",
      corner: '24 Departments',
      cols: _monthCols,
      rows: [
        RepRow('', 'Total', _monthVals(depts.fold<int>(0, (a, d) => a + dGoal(d)), _counts(mStudents)), total: true),
        for (final d in depts) RepRow('24Dept', d, _monthVals(dGoal(d), _counts(mStudents.where((s) => _n(s.gOdept) == _n(d))))),
      ],
    );
    return [summary, centers, deptBlock];
  }

  String _monthText(String month) {
    final cs = _centers.where((c) => _n(c.month) == _n(month)).toList();
    final all = _students.where((s) => cs.any((c) => _isCenter(s, c))).toList();
    final g = cs.fold<int>(0, (a, c) => a + c.goal);
    final b = StringBuffer()
      ..writeln('▪️$month')
      ..writeln('${tr('Center Place')}:[$g] ${_slash(_counts(all))}');
    for (final c in cs) {
      b.writeln('${c.center}:[${c.goal}]${_slash(_counts(all.where((s) => _isCenter(s, c))))}');
    }
    b.write('(${_stages.join('/')}/Overall)');
    return b.toString();
  }

  Widget _monthTab() {
    final months = _goalMonths;
    if (months.isEmpty) return const Center(child: Text("No opening months with centers yet. Add them in Evangelism policies, standards & goals › Goals."));
    final m = _month ?? months.first;
    final info = _monthInfo(m);
    final blocks = _monthBlocks(m);
    final cs = _centers.where((c) => _n(c.month) == _n(m)).toList();
    return _page([
      _bar([
        for (final x in months) _chip(x, x == m, () => setState(() => _month = x)),
        _excelButton(() async {
          final book = RepBook();
          for (final mo in months) {
            final s = book.sheet(mo);
            final inf = _monthInfo(mo);
            s.title("$mo ${tr('Center Places')}");
            s.title("${tr('Interviews')}: ${_dday(inf?['interview'])}   ${tr('Opening')}: ${_dday(inf?['opening'])}", size: 10);
            s.gap();
            for (final bl in _monthBlocks(mo)) {
              s.block(bl);
            }
            s.widths(12, 24, 10, _monthCols.length + 2);
          }
          await book.save(context, 'Opening_months_${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
        }),
      ]),
      Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
        _dateCard(Icons.record_voice_over_rounded, 'Interviews', _dday(info?['interview'])),
        _dateCard(Icons.celebration_rounded, 'Opening', _dday(info?['opening'])),
      ]),
      const SizedBox(height: 10),
      _table(blocks[0]),
      _table(blocks[1], below: [
        _goalChart('Goal and Overall', [for (final c in cs) (c.center, c.goal, _counts(_students.where((s) => _isCenter(s, c))).last)]),
      ]),
      _table(blocks[2]),
      _copyBox('Telegram text', _monthText(m)),
    ]);
  }

  Widget _dateCard(IconData icon, String label, String value) => Container(
        width: 260,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppPalette.cardShadow,
          border: Border.all(color: AppPalette.line(const Color(0x224A148C))),
        ),
        child: Row(children: [
          Icon(icon, color: _kPurple),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
              Text.rich(TextSpan(text: value.isEmpty ? tr('Not set (Settings)') : value), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12.5)),
            ]),
          ),
        ]),
      );

  // ------------------------------------------------------------------ 3. Groups

  List<_Stu> _monthStudents(String month) {
    if (month == 'General') return _students;
    final cs = _centers.where((c) => _n(c.month) == _n(month)).toList();
    return _students.where((s) => cs.any((c) => _isCenter(s, c)) || (_centerOf(s) == null && _n(s.month) == _n(month))).toList();
  }

  RepBlock _groupBlock(String month, (String, String) g) {
    final list = _monthStudents(month).where((s) => _inGroup(s, g.$2)).toList();
    final keys = list.map((s) => s.region).toSet();
    final order = _regionOrder(keys);
    return RepBlock(
      title: "$month — ${g.$1}",
      corner: 'Region',
      cols: _stageCols,
      rows: [
        RepRow('', 'Total', _counts(list), total: true),
        for (final r in order) RepRow('', _regionLabel(r), _counts(list.where((s) => s.region == r))),
      ],
    );
  }

  String _groupText(RepBlock b) {
    final out = StringBuffer('▪️${b.title}\n');
    for (final r in b.rows) {
      out.writeln('${r.label}:${r.vals.map((v) => (v ?? 0).toString()).join('/')}');
    }
    return out.toString().trim();
  }

  Widget _groupsTab() {
    final months = ['General', ..._goalMonths];
    final m = months.contains(_groupsMonth) ? _groupsMonth : 'General';
    final blocks = [for (final g in _kGroups) _groupBlock(m, g)];
    return _page([
      _note("Students count under their guide's current department and region."),
      _bar([
        for (final x in months) _chip(x, x == m, () => setState(() => _groupsMonth = x)),
        _excelButton(() async {
          final book = RepBook();
          for (final mo in months) {
            final s = book.sheet(mo);
            s.title("$mo — ${tr('Groups')}");
            s.gap();
            for (final g in _kGroups) {
              s.block(_groupBlock(mo, g));
            }
            s.widths(4, 18, 10, _stageCols.length + 2);
          }
          await book.save(context, 'Evangelism_Groups_${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
        }),
      ]),
      for (final b in blocks) ...[
        _table(b),
      ],
      _copyBox('Telegram text', blocks.map(_groupText).join('\n\n')),
    ]);
  }

  // ------------------------------------------------------------------ 4. 24 Depts

  List<RepBlock> _deptBlocks(String month) {
    final list = _monthStudents(month).where((s) => s.g24).toList();
    final depts = <String>[];
    final goals = _deptGoals.toList()..sort((a, b) => ((a['sort'] as num?) ?? 0).compareTo((b['sort'] as num?) ?? 0));
    for (final g in goals) {
      final d = g['dept'].toString();
      if (!depts.any((x) => _n(x) == _n(d))) depts.add(d);
    }
    for (final s in list) {
      if (s.gOdept.isNotEmpty && !depts.any((x) => _n(x) == _n(s.gOdept))) depts.add(s.gOdept);
    }
    bool online(_Stu s) => _centerOf(s)?.online ?? false;
    RepBlock one(String way, bool Function(_Stu) f) {
      final l = list.where(f).toList();
      return RepBlock(
        title: "$month — 24 Departments ($way)",
        corner: '24 Departments',
        cols: _stageCols,
        rows: [
          RepRow('', 'Total', _counts(l), total: true),
          for (final d in depts) RepRow('', d, _counts(l.where((s) => _n(s.gOdept) == _n(d)))),
        ],
      );
    }

    return [one('General', (s) => true), one('In-person', (s) => !online(s)), one('Online', online)];
  }

  Widget _deptTab() {
    final months = ['General', ..._goalMonths];
    final m = months.contains(_deptMonth) ? _deptMonth : 'General';
    return _page([
      _bar([
        for (final x in months) _chip(x, x == m, () => setState(() => _deptMonth = x)),
        _excelButton(() async {
          final book = RepBook();
          for (final mo in months) {
            final s = book.sheet(mo);
            s.title("$mo — ${tr('24 Departments')}");
            s.gap();
            for (final b in _deptBlocks(mo)) {
              s.block(b);
            }
            s.widths(4, 18, 10, _stageCols.length + 2);
          }
          await book.save(context, 'Evangelism_24_Depts_${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
        }),
      ]),
      for (final b in _deptBlocks(m)) _table(b),
    ]);
  }

  // ------------------------------------------------------------------ 5. Participation

  /// [region, department, is24, members, guides, teachers, either]
  List<RepBlock> _participationBlocks() {
    final cols = const [
      RepCol('Total'),
      RepCol('As Guide', 'Num'),
      RepCol('As Guide', '%', '', true),
      RepCol('As BB Teacher', 'Num'),
      RepCol('As BB Teacher', '%', '', true),
      RepCol('General', 'Num'),
      RepCol('General', '%', '', true),
    ];
    String regionOf(List m) => CompLevel.locationBucket({'location': (m[0] ?? '').toString(), 'department': (m[1] ?? '').toString()});
    bool inGroup(List m, String key) {
      if (key.isEmpty) return true;
      if (key == '24') return m[2] == true;
      if (key == 'MOU') return regionOf(m) == CompLevel.mou;
      return _n((m[1] ?? '').toString()) == _n(key) && regionOf(m) != CompLevel.mou;
    }

    List<num?> vals(Iterable<List> l) {
      int n = 0, g = 0, t = 0, e = 0;
      for (final m in l) {
        n += (m[3] as num?)?.toInt() ?? 0;
        g += (m[4] as num?)?.toInt() ?? 0;
        t += (m[5] as num?)?.toInt() ?? 0;
        e += (m[6] as num?)?.toInt() ?? 0;
      }
      double p(int x) => n > 0 ? x / n * 100 : 0;
      return [n, g, p(g), t, p(t), e, p(e)];
    }

    return [
      for (final grp in _kGroups)
        () {
          final l = _members.where((m) => inGroup(m, grp.$2)).toList();
          final order = _regionOrder(l.map(regionOf).toSet());
          return RepBlock(
            title: "Participation — ${grp.$1}",
            corner: grp.$1,
            cols: cols,
            rows: [
              RepRow('', 'Total', vals(l), total: true),
              for (final r in order) RepRow('', _regionLabel(r), vals(l.where((m) => regionOf(m) == r))),
            ],
          );
        }(),
    ];
  }

  /// Weekly member: per group, members, Overall reached by their guides,
  /// the guides, and the stages.
  RepBlock _weeklyMemberBlock() {
    final cols = <RepCol>[
      const RepCol('Num'),
      const RepCol('Confirmed', 'Num'),
      const RepCol('Confirmed', 'Ach%', '', true),
      const RepCol('Guide', 'Num'),
      const RepCol('Guide', '%', '', true),
      for (final s in _stages) RepCol('Status by stage', s),
    ];
    String regionOf(List m) => CompLevel.locationBucket({'location': (m[0] ?? '').toString(), 'department': (m[1] ?? '').toString()});
    RepRow row(String label, Iterable<List> mem, Iterable<_Stu> stu, {bool total = false}) {
      final n = mem.fold<int>(0, (a, m) => a + ((m[3] as num?)?.toInt() ?? 0));
      final g = mem.fold<int>(0, (a, m) => a + ((m[4] as num?)?.toInt() ?? 0));
      final c = _counts(stu);
      return RepRow('', label, [n, c.last, n > 0 ? c.last / n * 100 : null, g, n > 0 ? g / n * 100 : null, ...c.sublist(0, _stages.length)], total: total);
    }

    final rows = <RepRow>[row('All Saints', _members, _students.where((s) => !s.byStudent), total: true)];
    for (final grp in _kGroups.skip(1)) {
      bool inG(List m) {
        if (grp.$2 == '24') return m[2] == true;
        if (grp.$2 == 'MOU') return regionOf(m) == CompLevel.mou;
        return _n((m[1] ?? '').toString()) == _n(grp.$2) && regionOf(m) != CompLevel.mou;
      }

      rows.add(row(grp.$1, _members.where(inG), _students.where((s) => !s.byStudent && _inGroup(s, grp.$2))));
    }
    rows.add(row('Guided by students', const [], _students.where((s) => s.byStudent)));
    return RepBlock(title: 'Weekly member summary', corner: 'Dept', cols: cols, rows: rows);
  }

  Widget _participationTab() {
    final blocks = _participationBlocks();
    final weekly = _weeklyMemberBlock();
    return _page([
      _note("Members who are the guide or the BB teacher of at least one BB student (registered members only)."),
      _bar([
        _excelButton(() async {
          final book = RepBook();
          final s = book.sheet('Participation');
          s.title(tr('Participation'));
          s.title(_stamp(), size: 10);
          s.gap();
          for (final b in blocks) {
            s.block(b);
          }
          s.widths(4, 18, 11, 9);
          final w = book.sheet('Weekly member');
          w.title(tr('Weekly member summary'));
          w.gap();
          w.block(weekly);
          w.widths(4, 20, 10, weekly.cols.length + 2);
          await book.save(context, 'Evangelism_Participation_${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
        }),
      ]),
      _table(weekly),
      for (final b in blocks) _table(b),
    ]);
  }

  // ------------------------------------------------------------------ 6. Weekly analysis

  Future<void> _loadWeek() async {
    setState(() => _snapLoading = true);
    try {
      final from = _week.subtract(const Duration(days: 1)); // the day before: "Back up"
      final to = _week.add(const Duration(days: 6));
      final r = await _db.rpc('evangelism_daily_snapshot', params: {'p_from': DateFormat('yyyy-MM-dd').format(from), 'p_to': DateFormat('yyyy-MM-dd').format(to)});
      if (!mounted) return;
      setState(() {
        _snap = [for (final x in (r as List)) x as List];
        _snapLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _snapLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text.rich(TextSpan(text: "${tr("Couldn't load the week")}${friendlyTail(e)}"))));
    }
  }

  /// Stages up to Confirmed (Chakki → Confirmed).
  List<String> get _toConfirmed {
    final i = _stages.indexOf('Confirmed');
    return i < 0 ? _stages : _stages.sublist(0, i + 1);
  }

  Map<String, int> _dayCounts(DateTime day, _Center c) {
    final d = DateFormat('yyyy-MM-dd').format(day);
    final out = <String, int>{};
    for (final x in _snap ?? const <List>[]) {
      if (x[0].toString().substring(0, 10) != d) continue;
      if (_n(x[1].toString()) != _n(c.center) || _n(x[2].toString()) != _n(c.month)) continue;
      out[x[3].toString()] = (out[x[3].toString()] ?? 0) + ((x[4] as num?)?.toInt() ?? 0);
    }
    return out;
  }

  int _chToCon(DateTime day, _Center c) {
    final m = _dayCounts(day, c);
    return _toConfirmed.fold<int>(0, (a, s) => a + (m[s] ?? 0));
  }

  RepBlock _weekSummary() {
    final days = [for (int i = 0; i < 7; i++) _week.add(Duration(days: i))];
    final back = _week.subtract(const Duration(days: 1));
    final cols = <RepCol>[
      const RepCol('Back Up'),
      for (final d in days) RepCol(DateFormat('EEE d').format(d)),
      const RepCol('Min'),
      const RepCol('Median'),
      const RepCol('Average'),
      const RepCol('Max'),
      for (final d in days) RepCol('Daily change', DateFormat('EEE').format(d)),
    ];
    List<num?> vals(List<_Center> cs) {
      int sum(DateTime d) => cs.fold<int>(0, (a, c) => a + _chToCon(d, c));
      final b = sum(back);
      final v = [for (final d in days) sum(d)];
      final sorted = [...v]..sort();
      final median = sorted.length.isOdd ? sorted[sorted.length ~/ 2] : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
      final avg = v.fold<int>(0, (a, x) => a + x) / v.length;
      return [
        b,
        ...v,
        sorted.first,
        median,
        (avg * 10).round() / 10,
        sorted.last,
        for (int i = 0; i < v.length; i++) v[i] - (i == 0 ? b : v[i - 1]),
      ];
    }

    return RepBlock(
      title: "Chakki to Confirmed — week of ${DateFormat('d MMM yyyy').format(_week)}",
      corner: 'Region · Center Place',
      cols: cols,
      rows: [
        RepRow('', 'Total', vals(_centers), total: true),
        for (final c in _centers) RepRow(c.region, "${c.center} (${c.month})", vals([c])),
      ],
    );
  }

  RepBlock _dayBlock(DateTime day) => RepBlock(
        title: "Centre status — ${DateFormat('EEEE d MMM').format(day)}",
        corner: 'Region · Center Place',
        cols: [for (final s in _toConfirmed) RepCol(s)],
        rows: [
          RepRow('', 'Total', [
            for (final s in _toConfirmed) _centers.fold<int>(0, (a, c) => a + (_dayCounts(day, c)[s] ?? 0)),
          ], total: true),
          for (final c in _centers)
            () {
              final m = _dayCounts(day, c);
              return RepRow(c.region, "${c.center} (${c.month})", [for (final s in _toConfirmed) m[s] ?? 0]);
            }(),
        ],
      );

  int _day = 0;

  Widget _weeklyTab() {
    if (_snap == null && !_snapLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _snap == null && !_snapLoading) _loadWeek();
      });
    }
    final days = [for (int i = 0; i < 7; i++) _week.add(Duration(days: i))];
    return _page([
      _centerSwitch(),
      _bar([
        IconButton(
          tooltip: tr('Previous week'),
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () {
            setState(() {
              _week = _week.subtract(const Duration(days: 7));
              _snap = null;
            });
          },
        ),
        Text.rich(TextSpan(text: "${DateFormat('d MMM').format(_week)} – ${DateFormat('d MMM yyyy').format(_week.add(const Duration(days: 6)))}"),
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900)),
        IconButton(
          tooltip: tr('Next week'),
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: _week.add(const Duration(days: 7)).isAfter(DateTime.now())
              ? null
              : () {
                  setState(() {
                    _week = _week.add(const Duration(days: 7));
                    _snap = null;
                  });
                },
        ),
        const SizedBox(width: 8),
        if (_snap != null)
          _excelButton(() async {
            final book = RepBook();
            final s = book.sheet('Summary');
            s.block(_weekSummary());
            s.widths(12, 24, 9, _weekSummary().cols.length + 2);
            for (final d in days) {
              final ds = book.sheet(DateFormat('EEEE').format(d));
              ds.block(_dayBlock(d));
              ds.widths(12, 24, 10, _toConfirmed.length + 2);
            }
            await book.save(context, 'Weekly_Analysis_${DateFormat('yyyy-MM-dd').format(_week)}');
          }),
      ]),
      if (_snapLoading || _snap == null)
        const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
      else ...[
        _table(_weekSummary()),
        _bar([for (int i = 0; i < 7; i++) _chip(DateFormat('EEE').format(days[i]), _day == i, () => setState(() => _day = i))]),
        _table(_dayBlock(days[_day])),
      ],
    ]);
  }

  // ------------------------------------------------------------------ 7. Settings

  static const List<String> _stdRegions = ['Wakiso', 'Lubaga', 'Busega', 'Kawempe', 'Makerere', 'Makindye', 'Nakawa', 'Mukono', 'Entebbe', 'New Region', 'UAE'];

  Future<void> _saveCenter(_Center? c) async {
    final region = TextEditingController(text: c?.region ?? '');
    final center = TextEditingController(text: c?.center ?? '');
    final goal = TextEditingController(text: c == null ? '' : '${c.goal}');
    final months = [for (final m in _months) m['label'].toString()];
    String month = c?.month ?? (months.isEmpty ? '' : months.first);
    bool online = c?.online ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(c == null ? "Add center place" : "Change center place", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Autocomplete<String>(
                initialValue: TextEditingValue(text: region.text),
                optionsBuilder: (v) => [..._stdRegions, ...months].where((r) => r.toLowerCase().contains(v.text.toLowerCase())),
                onSelected: (v) => region.text = v,
                fieldViewBuilder: (ctx, ctrl, focus, submit) => TextField(
                  controller: ctrl,
                  focusNode: focus,
                  onChanged: (v) => region.text = v,
                  decoration: InputDecoration(
                    labelText: tr('Region (or the batch month for MOU / online)'),
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: center,
                decoration: InputDecoration(labelText: tr('Center place'), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: months.contains(month) ? month : null,
                items: [for (final m in months) DropdownMenuItem(value: m, child: Text.rich(TextSpan(text: m)))],
                onChanged: (v) => set(() => month = v ?? month),
                decoration: InputDecoration(labelText: tr('Opening month'), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: goal,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Goal'), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: online,
                onChanged: (v) => set(() => online = v),
                title: const Text("Online center"),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
          ],
        ),
      ),
    );
    if (ok != true || center.text.trim().isEmpty || month.isEmpty) return;
    final row = {
      'region': region.text.trim(),
      'center_place': center.text.trim(),
      'month_label': month,
      'goal': int.tryParse(goal.text.trim()) ?? 0,
      'is_online': online,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (c == null) {
        await _db.from('evangelism_center_goals').insert({...row, 'sort_order': (_centers.isEmpty ? 0 : _centers.map((x) => x.sort).reduce(math.max)) + 1});
        try {
          // the BB form lists it too
          await _db.from('evangelism_centers').upsert({'name': center.text.trim(), 'is_opening': true}, onConflict: 'name', ignoreDuplicates: true);
        } catch (_) {}
      } else {
        await _db.from('evangelism_center_goals').update(row).eq('id', c.id);
      }
      await _load();
    } catch (e) {
      _snack("${tr("Couldn't save")}${friendlyTail(e)}");
    }
  }

  Future<void> _deleteCenter(_Center c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove center place?"),
        content: Text.rich(TextSpan(text: "${c.center} (${c.month}) ${tr('is removed from the goals. Its BB students stay in the BB File.')}")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700), onPressed: () => Navigator.pop(ctx, true), child: const Text("Remove")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('evangelism_center_goals').delete().eq('id', c.id);
      await _load();
    } catch (e) {
      _snack("${tr("Couldn't remove")}${friendlyTail(e)}");
    }
  }

  Future<void> _moveCenter(int i, int dir) async {
    final j = i + dir;
    if (j < 0 || j >= _centers.length) return;
    final a = _centers[i], b = _centers[j];
    try {
      await _db.from('evangelism_center_goals').update({'sort_order': b.sort}).eq('id', a.id);
      await _db.from('evangelism_center_goals').update({'sort_order': a.sort == b.sort ? a.sort + dir : a.sort}).eq('id', b.id);
      await _load();
    } catch (e) {
      _snack("${tr("Couldn't save")}${friendlyTail(e)}");
    }
  }

  Future<void> _editMonth(Map<String, dynamic>? m) async {
    final label = TextEditingController(text: m?['label']?.toString() ?? '');
    DateTime? start = DateTime.tryParse((m?['start'] ?? '').toString());
    DateTime? interview = DateTime.tryParse((m?['interview'] ?? '').toString());
    DateTime? opening = DateTime.tryParse((m?['opening'] ?? '').toString());
    Future<DateTime?> pick(BuildContext ctx, DateTime? d) =>
        showDatePicker(context: ctx, initialDate: d ?? DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2032));
    String show(DateTime? d) => d == null ? tr('Not set') : DateFormat('EEE d MMM yyyy').format(d);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(m == null ? "Add opening month" : "Opening month", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: label,
                enabled: m == null,
                decoration: InputDecoration(labelText: tr('Name (e.g. February)'), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Month starts"),
                subtitle: Text.rich(TextSpan(text: show(start))),
                trailing: const Icon(Icons.event_rounded),
                enabled: m == null,
                onTap: () async {
                  final d = await pick(ctx, start);
                  if (d != null) set(() => start = DateTime(d.year, d.month, 1));
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Interview date"),
                subtitle: Text.rich(TextSpan(text: show(interview))),
                trailing: const Icon(Icons.event_rounded),
                onTap: () async {
                  final d = await pick(ctx, interview);
                  if (d != null) set(() => interview = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Opening date"),
                subtitle: Text.rich(TextSpan(text: show(opening))),
                trailing: const Icon(Icons.event_rounded),
                onTap: () async {
                  final d = await pick(ctx, opening);
                  if (d != null) set(() => opening = d);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
          ],
        ),
      ),
    );
    if (ok != true) return;
    String? f(DateTime? d) => d == null ? null : DateFormat('yyyy-MM-dd').format(d);
    try {
      if (m == null) {
        if (label.text.trim().isEmpty || start == null) return;
        await _db.from('evangelism_opening_months').insert({
          'label': label.text.trim(),
          'month_start': f(start),
          'is_open': true,
          'interview_date': f(interview),
          'opening_date': f(opening),
        });
      } else {
        await _db.from('evangelism_opening_months').update({'interview_date': f(interview), 'opening_date': f(opening)}).eq('label', m['label'].toString());
      }
      await _load();
    } catch (e) {
      _snack("${tr("Couldn't save")}${friendlyTail(e)}");
    }
  }

  Future<void> _editDeptGoals(String month) async {
    const depts = ['행정서무부', '내무부', '기획부', '재정부', '교육부', '신학부', '전도부', '문화부', '정통부', '찬양부', '섭외부', '국제부', '국내선교부', '홍보부', '봉교부', '건설부', '체육부', '사업부', '후생복지부', '여성그룹부'];
    final names = <String>[...depts];
    for (final g in _deptGoals) {
      final d = g['dept'].toString();
      if (!names.contains(d)) names.add(d);
    }
    final ctrls = {
      for (final d in names)
        d: TextEditingController(
            text: '${_deptGoals.where((g) => _n(g['month'].toString()) == _n(month) && g['dept'].toString() == d).map((g) => (g['goal'] as num?)?.toInt() ?? 0).fold<int>(0, (a, b) => a + b)}'),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text.rich(TextSpan(text: "${tr('24 Departments goals')} — $month"), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 360,
          height: 460,
          child: ListView(children: [
            for (final d in names)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(child: Text.rich(TextSpan(text: d))),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: ctrls[d],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('evangelism_dept_goals').upsert([
        for (int i = 0; i < names.length; i++)
          {'month_label': month, 'department': names[i], 'goal': int.tryParse(ctrls[names[i]]!.text.trim()) ?? 0, 'sort_order': i + 1},
      ], onConflict: 'month_label,department');
      await _load();
    } catch (e) {
      _snack("${tr("Couldn't save")}${friendlyTail(e)}");
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text.rich(TextSpan(text: m)), behavior: SnackBarBehavior.floating));
  }

  // Settings parts, shown in Evangelism policies, standards & goals.

  Widget _head(String title, {Widget? action, String? sub}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(children: [
          Text(title, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple))),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text.rich(TextSpan(text: sub), textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
          ],
          if (action != null) ...[const SizedBox(height: 8), action],
        ]),
      );

  Widget _lightButton(String label, IconData icon, VoidCallback onTap) => FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppPalette.bg(_kLight),
          foregroundColor: AppPalette.fg(_kPurple),
          side: BorderSide(color: AppPalette.line(const Color(0x444A148C))),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text.rich(TextSpan(text: tr(label))),
      );

  Widget _rowCard({required Widget leading, required String title, required String sub, required List<Widget> actions, Widget? trailing}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.line(const Color(0x1F4A148C))),
          boxShadow: AppPalette.cardShadow,
        ),
        child: Row(children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(text: title), style: GoogleFonts.merriweather(fontWeight: FontWeight.w800, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text.rich(TextSpan(text: sub), style: GoogleFonts.merriweather(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
            ]),
          ),
          if (trailing != null) trailing,
          ...actions,
        ]),
      );

  /// Goals › Center place goals: goal of each center place and opening month.
  Widget _centerGoalsView() {
    final total = _centers.fold<int>(0, (a, c) => a + c.goal);
    return _page([
      _head("Goals per center place",
          sub: "${_centers.length} ${tr('center places')} · ${tr('Goal')} $total",
          action: _lightButton('Add a center place goal', Icons.add_rounded, () => _saveCenter(null))),
      for (int i = 0; i < _centers.length; i++)
        _rowCard(
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: AppPalette.bg(_centers[i].online ? const Color(0xFFE3F2FD) : _kLight),
            child: Icon(_centers[i].online ? Icons.wifi_rounded : Icons.location_city_rounded, size: 18, color: AppPalette.fg(_kPurple)),
          ),
          title: "${_centers[i].center}  ·  ${_centers[i].region}",
          sub: "${_centers[i].month} · ${tr('Goal')} ${_centers[i].goal}${_centers[i].online ? ' · ${tr('Online')}' : ''}",
          actions: [
            IconButton(tooltip: tr('Up'), icon: const Icon(Icons.arrow_upward_rounded, size: 18), onPressed: i == 0 ? null : () => _moveCenter(i, -1)),
            IconButton(tooltip: tr('Down'), icon: const Icon(Icons.arrow_downward_rounded, size: 18), onPressed: i == _centers.length - 1 ? null : () => _moveCenter(i, 1)),
            IconButton(tooltip: tr('Change'), icon: const Icon(Icons.edit_rounded, size: 18), onPressed: () => _saveCenter(_centers[i])),
            IconButton(tooltip: tr('Remove'), icon: Icon(Icons.delete_outline_rounded, size: 18, color: AppPalette.fg(Colors.red.shade400)), onPressed: () => _deleteCenter(_centers[i])),
          ],
        ),
    ]);
  }

  String _goalsMonth = '';

  /// Goals › 24 Departments: each department's goal for an opening month.
  Widget _deptGoalsView() {
    final months = [for (final m in _months) m['label'].toString()];
    if (months.isEmpty) return const Center(child: Text("Add an opening month first (Opening months)."));
    final m = months.contains(_goalsMonth) ? _goalsMonth : months.first;
    final goals = _deptGoals.where((g) => _n(g['month'].toString()) == _n(m)).toList()
      ..sort((a, b) => ((a['sort'] as num?) ?? 0).compareTo((b['sort'] as num?) ?? 0));
    final total = goals.fold<int>(0, (a, g) => a + ((g['goal'] as num?)?.toInt() ?? 0));
    final block = RepBlock(
      title: "$m — ${tr('24 Departments goals')}",
      corner: '24 Departments',
      cols: const [RepCol('Goal')],
      rows: [
        RepRow('', 'Total', [total], total: true),
        for (final g in goals) RepRow('', g['dept'].toString(), [(g['goal'] as num?) ?? 0]),
      ],
    );
    return _page([
      _head("Goals of the 24 departments", sub: "Per opening month", action: _lightButton('Set the goals', Icons.edit_rounded, () => _editDeptGoals(m))),
      _bar([for (final x in months) _chip(x, x == m, () => setState(() => _goalsMonth = x))]),
      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: _table(block))),
    ]);
  }

  /// Opening months: add months with their interview and opening dates,
  /// open or close them, change the dates, remove.
  Widget _monthsView() => _page([
        _head("Opening months",
            sub: "They decide the months students are counted under in the BB File and the reports. Switch a month off when it closes.",
            action: _lightButton('Add opening month', Icons.add_rounded, () => _editMonth(null))),
        for (final m in _months)
          _rowCard(
            leading: CircleAvatar(radius: 18, backgroundColor: AppPalette.bg(_kLight), child: Icon(Icons.calendar_month_rounded, size: 18, color: AppPalette.fg(_kPurple))),
            title: "${m['label']} ${DateTime.tryParse((m['start'] ?? '').toString())?.year ?? ''}",
            sub: "${tr('Interviews')}: ${_dday(m['interview']).isEmpty ? tr('Not set') : _dday(m['interview'])}\n${tr('Opening')}: ${_dday(m['opening']).isEmpty ? tr('Not set') : _dday(m['opening'])}",
            trailing: Switch(
              value: m['open'] == true,
              onChanged: (v) async {
                try {
                  await _db.from('evangelism_opening_months').update({'is_open': v}).eq('label', m['label'].toString()).eq('month_start', (m['start'] ?? '').toString());
                  await _load();
                } catch (e) {
                  _snack("${tr("Couldn't save")}${friendlyTail(e)}");
                }
              },
            ),
            actions: [
              IconButton(tooltip: tr('Dates'), icon: const Icon(Icons.event_rounded, size: 18), onPressed: () => _editMonth(m)),
              IconButton(
                tooltip: tr('Remove'),
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: AppPalette.fg(Colors.red.shade400)),
                onPressed: () async {
                  try {
                    await _db.from('evangelism_opening_months').delete().eq('label', m['label'].toString()).eq('month_start', (m['start'] ?? '').toString());
                    await _load();
                  } catch (e) {
                    _snack("${tr("Couldn't remove")}${friendlyTail(e)}");
                  }
                },
              ),
            ],
          ),
      ]);

  // ------------------------------------------------------------------ build

  Widget _body() {
    if (_loading) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text.rich(TextSpan(text: _error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text("Try again")),
          ]),
        ),
      );
    }
    return switch (widget.view) {
      CenterView.participation => _participationTab(),
      CenterView.centerGoals => _centerGoalsView(),
      CenterView.deptGoals => _deptGoalsView(),
      CenterView.months => _monthsView(),
      CenterView.results => TabBarView(controller: _tabs, children: [_centersTab(), _groupsTab(), _deptTab(), _monthTab()]),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded || widget.view != CenterView.results) {
      if (widget.view == CenterView.participation) {
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _head("Participation by group", sub: _stamp().isEmpty ? null : _stamp()),
            _body(),
          ]),
        );
      }
      return _body();
    }
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF7F4FC)),
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 64,
        backgroundColor: AppPalette.bg(const Color(0xFFF7F4FC)),
        surfaceTintColor: Colors.transparent,
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Center Reports", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 19, color: AppPalette.fg(_kPurple))),
          const SizedBox(height: 2),
          Text.rich(TextSpan(text: _stamp().isEmpty ? tr('Evangelism results') : "${tr('Evangelism results')} · ${_stamp()}"),
              style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
        ]),
        actions: [IconButton(tooltip: tr('Refresh'), icon: Icon(Icons.refresh_rounded, color: AppPalette.fg(_kPurple)), onPressed: _loading ? null : _load)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(maxWidth: 820),
            decoration: BoxDecoration(
              color: AppPalette.bg(Colors.white),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppPalette.line(const Color(0x224A148C))),
              boxShadow: AppPalette.cardShadow,
            ),
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(color: AppPalette.bg(_kLight), borderRadius: BorderRadius.circular(20)),
              labelColor: AppPalette.fg(_kPurple),
              unselectedLabelColor: AppPalette.fg(Colors.grey.shade700),
              labelStyle: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12.5),
              unselectedLabelStyle: GoogleFonts.merriweather(fontWeight: FontWeight.w600, fontSize: 12.5),
              tabs: [
                Tab(height: 36, text: tr('Results By Center')),
                Tab(height: 36, text: tr('Results By Groups')),
                Tab(height: 36, text: tr('24 Depts Results')),
                Tab(height: 36, text: tr('Results By Opening Month')),
              ],
            ),
          ),
        ),
      ),
      body: _body(),
    );
  }
}
