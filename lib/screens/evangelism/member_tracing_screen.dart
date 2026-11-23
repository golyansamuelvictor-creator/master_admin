import 'package:material_ui/material_ui.dart' hide Text;
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

const Color _kPurple = Color(0xFF4A148C);

/// Evangelism results › Member evangelism tracing: every member of the
/// viewer's units with the BB students they guided and taught as BB teacher,
/// and how far each student got: Chakki → BB stages → center levels →
/// enrolled in the church. Leaders see their own units; the Evangelism
/// Department and administrators the whole church (member_evangelism_trace,
/// 39_round35.sql).
///
/// Opens with a choice: the Dashboard (summary by unit, tables and charts)
/// or Check by name list.
Future<void> openMemberTracing(BuildContext context) async {
  final pick = await showDialog<int>(
    context: context,
    builder: (ctx) {
      Widget tile(int v, IconData icon, String title, String sub) => InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.pop(ctx, v),
            child: Container(
              width: 230,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppPalette.bg(const Color(0xFFF7F2FD)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppPalette.line(const Color(0x334A148C))),
                boxShadow: AppPalette.cardShadow,
              ),
              child: Column(children: [
                CircleAvatar(radius: 24, backgroundColor: AppPalette.bg(const Color(0xFFE9DDFB)), child: Icon(icon, color: _kPurple)),
                const SizedBox(height: 10),
                Text(title, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: AppPalette.fg(_kPurple))),
                const SizedBox(height: 4),
                Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
              ]),
            ),
          );
      return AlertDialog(
        title: Text("Member evangelism tracing", textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16)),
        content: Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 14, children: [
          tile(0, Icons.space_dashboard_rounded, "Open dashboard", "The summary of your units: tables and charts, level by level."),
          tile(1, Icons.format_list_numbered_rounded, "Check by name list", "Every member with the students they guided and taught."),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
      );
    },
  );
  if (pick == null || !context.mounted) return;
  Navigator.push(context, MaterialPageRoute(builder: (_) => pick == 0 ? const MemberTracingDashboard() : const MemberTracingScreen()));
}

// ------------------------------------------------------------------ data

class _Mem {
  final String scj, name, ko, loc, sub, dept, team, cell;
  /// Dubai Official (members.official; 41_round37.sql)
  final bool official;
  _Mem(List r)
      : scj = (r[0] ?? '').toString(),
        name = (r[1] ?? '').toString(),
        ko = (r[2] ?? '').toString(),
        // MouWakiso, MouLubaga … all count as MOU; Church as 24Dept (as in the Compilation screen)
        loc = _region((r[3] ?? '').toString(), (r[5] ?? '').toString()),
        official = r.length > 8 && r[8] == true,
        sub = (r[4] ?? '').toString(),
        dept = (r[5] ?? '').toString(),
        team = (r[6] ?? '').toString(),
        cell = (r[7] ?? '').toString();

  static String _region(String loc, String dept) {
    final b = CompLevel.locationBucket({'location': loc, 'department': dept});
    return b == 'Other' ? loc : b;
  }

  /// The member's unit at a level (0 region … 4 cell).
  String at(int level) => switch (level) { 0 => loc, 1 => sub, 2 => dept, 3 => team, _ => cell };
}

class _Stu {
  final String guide, teacher, name, stage, center, month, bb, kind;
  final bool dropped;
  _Stu(List r)
      : guide = (r[0] ?? '').toString(),
        teacher = (r[1] ?? '').toString(),
        name = (r[2] ?? '').toString(),
        stage = (r[3] ?? '').toString(),
        center = (r[4] ?? '').toString(),
        month = (r[5] ?? '').toString(),
        bb = (r[6] ?? '').toString(),
        dropped = r[7] == true,
        kind = (r[8] ?? '').toString();
}

/// The tracing data, loaded once and kept 5 minutes for both views.
class _Trace {
  final bool whole;
  final List<String> stages;
  final List<_Mem> members;
  final Map<String, List<_Stu>> guided, taught;
  _Trace(this.whole, this.stages, this.members, this.guided, this.taught);

  static _Trace? _cache;
  static DateTime? _at;

  static Future<_Trace> load({bool fresh = false}) async {
    if (!fresh && _cache != null && _at != null && DateTime.now().difference(_at!) < const Duration(minutes: 5)) return _cache!;
    final r = Map<String, dynamic>.from(await Supabase.instance.client.rpc('member_evangelism_trace') as Map);
    final mem = [for (final m in (r['members'] as List? ?? [])) _Mem(m as List)];
    final stu = [for (final s in (r['students'] as List? ?? [])) _Stu(s as List)];
    final g = <String, List<_Stu>>{}, t = <String, List<_Stu>>{};
    for (final s in stu) {
      if (s.guide.isNotEmpty) g.putIfAbsent(s.guide, () => []).add(s);
      if (s.teacher.isNotEmpty) t.putIfAbsent(s.teacher, () => []).add(s);
    }
    // the path: BB stages, then the center levels and the church
    final bb = [for (final x in (r['stages'] as List? ?? [])) x.toString()];
    final extra = <String>[];
    for (final s in stu) {
      if (!bb.contains(s.stage) && !extra.contains(s.stage)) extra.add(s.stage);
    }
    int rank(String x) => x == 'Church enrolled' ? 3 : (x.contains('Advanced') ? 2 : (x.contains('Intermediate') ? 1 : 0));
    extra.sort((a, b) => rank(a).compareTo(rank(b)));
    _cache = _Trace(r['whole_church'] == true, [...bb, ...extra], mem, g, t);
    _at = DateTime.now();
    return _cache!;
  }

  /// Dubai Official, kept apart like the Compilation screen:
  ///  · whole church: Uganda Church (without them) · Dubai Official · Total
  ///  · UAE only: Total · Dubai (without them) · Dubai Official
  bool get hasOfficial => members.any((m) => m.official);
  bool get uaeOnly => members.isNotEmpty && members.every((m) => _isUae(m.loc));
  static bool _isUae(String l) => const {'uae', 'dubai'}.contains(l.trim().toLowerCase());
  List<String> get views => !hasOfficial ? const [] : (uaeOnly ? const ['Total', 'Dubai', 'Dubai Official'] : const ['Uganda Church', 'Dubai Official', 'Total']);
  static bool inView(_Mem m, String v) => switch (v) {
        'Uganda Church' || 'Dubai' => !m.official,
        'Dubai Official' => m.official,
        _ => true,
      };

  /// A member's students: as guide, as BB teacher or both (each student once).
  List<_Stu> of(_Mem m, String as) {
    final g = as == 'BB teacher' ? const <_Stu>[] : (guided[m.scj] ?? const <_Stu>[]);
    final t = as == 'Guide' ? const <_Stu>[] : (taught[m.scj] ?? const <_Stu>[]);
    if (t.isEmpty) return g;
    final out = <_Stu>[...g];
    for (final s in t) {
      if (!out.contains(s)) out.add(s);
    }
    return out;
  }
}

const _kLevels = ['Region', 'Sub Region', 'Department', 'Team', 'Cell'];
const _kLevelRule = ['Location', 'Sub-location', 'Dept', 'Team', 'Cell'];

/// A light, centred dropdown with a label.
Widget _drop(String label, String value, List<String> items, ValueChanged<String> on, {String all = 'All', double width = 170, String Function(String)? show}) => Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: SizedBox(
        width: width,
        child: DropdownButtonFormField<String>(
          initialValue: value.isEmpty || items.contains(value) ? value : '',
          isExpanded: true,
          decoration: InputDecoration(labelText: tr(label), isDense: true, filled: true, fillColor: AppPalette.bg(Colors.white), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
          items: [
            if (all.isNotEmpty) DropdownMenuItem(value: '', child: Text(all)),
            for (final i in items) DropdownMenuItem(value: i, child: Text.rich(TextSpan(text: show != null ? show(i) : i), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => on(v ?? ''),
        ),
      ),
    );

/// One member's students, or everyone's at one stage.
void _drill(BuildContext context, List<String> stages, String title, List<_Stu> list, {_Mem? m}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
          child: Row(children: [
            Expanded(child: Text.rich(TextSpan(text: title), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: AppPalette.fg(_kPurple)))),
            Text.rich(TextSpan(text: "${list.length}"), style: const TextStyle(fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            for (final st in stages)
              if (list.any((s) => s.stage == st))
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text.rich(TextSpan(text: "$st · ${list.where((s) => s.stage == st).length}"), style: const TextStyle(fontSize: 11.5)),
                  backgroundColor: AppPalette.bg(const Color(0xFFF3ECFC)),
                ),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = list[i];
              final role = m == null ? '' : [if (s.guide == m.scj) tr('Guide'), if (s.teacher == m.scj) tr('BB teacher')].join(' + ');
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: AppPalette.bg(s.dropped ? const Color(0xFFFFEBEE) : (s.stage == 'Church enrolled' ? const Color(0xFFE8F5E9) : const Color(0xFFEDE4FA))),
                  child: Icon(s.dropped ? Icons.close_rounded : (s.stage == 'Church enrolled' ? Icons.church_rounded : Icons.school_rounded), size: 16, color: _kPurple),
                ),
                title: Text.rich(TextSpan(text: s.name), style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text.rich(TextSpan(text: [s.stage, if (s.center.isNotEmpty) s.center, if (s.month.isNotEmpty) s.month, if (s.dropped) tr('Dropped'), if (role.isNotEmpty) role].join(' · '))),
              );
            },
          ),
        ),
      ]),
    ),
  );
}

// ------------------------------------------------------------------ name list

class MemberTracingScreen extends StatefulWidget {
  const MemberTracingScreen({super.key});
  @override
  State<MemberTracingScreen> createState() => _MemberTracingScreenState();
}

class _MemberTracingScreenState extends State<MemberTracingScreen> {
  static const int _pageSize = 1000;
  bool _loading = true;
  String? _error;
  _Trace? _t;

  // filters
  String _loc = '', _sub = '', _dept = '', _team = '';
  String _as = 'Guide or BB teacher';
  String _stageFilter = '';
  bool _onlyActive = true; // members with at least one student
  String _q = '';
  String _sort = 'Students';
  String _view = '';
  int _page = 0;

  static const _unitCols = ['Region', 'Sub-region', 'Department', 'Team', 'Cell'];
  final Set<String> _hidden = {'Korean name', 'Cell'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool fresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await _Trace.load(fresh: fresh);
      if (!mounted) return;
      setState(() {
        _t = t;
        if (!t.views.contains(_view)) _view = t.views.isEmpty ? '' : t.views.first;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load the tracing${friendlyTail(e)}";
        });
      }
    }
  }

  List<_Stu> _studentsOf(_Mem m) {
    final l = _t!.of(m, _as);
    return _stageFilter.isEmpty ? l : l.where((s) => s.stage == _stageFilter).toList();
  }

  bool _unitOk(_Mem m, {String? skip}) =>
      (skip == 'loc' || _loc.isEmpty || m.loc == _loc) &&
      (skip == 'sub' || _sub.isEmpty || m.sub == _sub) &&
      (skip == 'dept' || _dept.isEmpty || m.dept == _dept) &&
      (skip == 'team' || _team.isEmpty || m.team == _team);

  List<String> _opts(String key, String Function(_Mem) f, String level) {
    final set = {for (final m in _t!.members) if (_unitOk(m, skip: key)) f(m)}..removeWhere((x) => x.trim().isEmpty);
    return CompLevel.orderNames(set, level);
  }

  List<_Mem> get _rows {
    final q = _q.trim().toLowerCase();
    final list = _t!.members.where((m) {
      if (_view.isNotEmpty && !_Trace.inView(m, _view)) return false;
      if (!_unitOk(m)) return false;
      if (q.isNotEmpty && !'${m.name} ${m.ko} ${m.scj}'.toLowerCase().contains(q)) return false;
      if (_onlyActive && _studentsOf(m).isEmpty) return false;
      return true;
    }).toList();
    final stages = _t!.stages;
    if (_sort == 'Name') {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (_sort == 'Furthest stage') {
      int far(_Mem m) => _studentsOf(m).fold<int>(-1, (a, s) => stages.indexOf(s.stage) > a ? stages.indexOf(s.stage) : a);
      list.sort((a, b) => far(b).compareTo(far(a)));
    } else {
      list.sort((a, b) => _studentsOf(b).length.compareTo(_studentsOf(a).length));
    }
    return list;
  }

  void _set(VoidCallback f) => setState(() {
        f();
        _page = 0;
      });

  Widget _columnsButton() => PopupMenuButton<String>(
        tooltip: tr("Show / hide columns"),
        icon: const Icon(Icons.view_column_rounded, color: _kPurple),
        itemBuilder: (_) => [
          for (final c in ['Korean name', ..._unitCols, 'Guided', 'Taught', ..._t!.stages, 'Dropped'])
            CheckedPopupMenuItem(value: c, checked: !_hidden.contains(c), child: Text.rich(TextSpan(text: c))),
        ],
        onSelected: (c) => setState(() => _hidden.contains(c) ? _hidden.remove(c) : _hidden.add(c)),
      );

  Future<void> _excel(List<_Mem> rows, List<String> cols) async {
    final book = RepBook();
    final sh = book.sheet('Member tracing');
    sh.title(tr('Member evangelism tracing'));
    sh.title("${tr('As of')} ${DateFormat('d MMM yyyy HH:mm').format(DateTime.now())}", size: 10);
    sh.gap();
    sh.block(RepBlock(
      title: 'Member tracing',
      corner: 'Member',
      cols: [for (final c in cols) RepCol(c)],
      rows: [for (final m in rows) RepRow('', m.name, [for (final c in cols) _num(m, c)])],
    ));
    sh.widths(2, 28, 12, cols.length + 2);
    await book.save(context, 'Member_tracing_${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
  }

  num? _num(_Mem m, String c) {
    final t = _t!;
    final l = _studentsOf(m);
    if (c == 'Guided') return (t.guided[m.scj] ?? const <_Stu>[]).where((s) => _stageFilter.isEmpty || s.stage == _stageFilter).length;
    if (c == 'Taught') return (t.taught[m.scj] ?? const <_Stu>[]).where((s) => _stageFilter.isEmpty || s.stage == _stageFilter).length;
    if (c == 'Dropped') return l.where((s) => s.dropped).length;
    return l.where((s) => s.stage == c).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
      appBar: AppBar(
        centerTitle: true,
        title: Text("Member evangelism tracing", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 20, color: AppPalette.fg(_kPurple))),
        actions: [
          if (!_loading && _error == null) _columnsButton(),
          IconButton(tooltip: tr("Reload"), icon: const Icon(Icons.refresh_rounded), onPressed: () => _load(fresh: true)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text.rich(TextSpan(text: _error), textAlign: TextAlign.center)))
              : _body(),
    );
  }

  Widget _body() {
    final t = _t!;
    final all = _rows;
    final pages = all.isEmpty ? 1 : ((all.length - 1) ~/ _pageSize) + 1;
    if (_page >= pages) _page = pages - 1;
    final rows = all.sublist(_page * _pageSize, ((_page + 1) * _pageSize).clamp(0, all.length));
    final valueCols = ['Guided', 'Taught', ...t.stages, 'Dropped'].where((c) => !_hidden.contains(c)).toList();
    final unitCols = _unitCols.where((c) => !_hidden.contains(c)).toList();
    final showKo = !_hidden.contains('Korean name');
    const numW = 52.0, nameW = 190.0, koW = 110.0, unitW = 110.0, valW = 92.0, rowH = 32.0;
    final width = numW + nameW + (showKo ? koW : 0) + unitCols.length * unitW + valueCols.length * valW;
    String unit(_Mem m, String c) => switch (c) { 'Region' => m.loc, 'Sub-region' => m.sub, 'Department' => m.dept, 'Team' => m.team, _ => m.cell };
    final allStu = <_Stu>{for (final m in all) ..._studentsOf(m)}.toList();

    Widget cell(String txt, double w, {bool bold = false, Color? bg, VoidCallback? tap, bool left = false}) => InkWell(
          onTap: tap,
          child: Container(
            width: w,
            height: rowH,
            alignment: left ? Alignment.centerLeft : Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(color: AppPalette.bg(bg ?? Colors.white), border: Border.all(color: AppPalette.line(Colors.black12), width: 0.5)),
            child: Text.rich(TextSpan(text: txt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: AppPalette.fg(tap != null ? _kPurple : Colors.black87))),
          ),
        );

    // the header: bigger, white on purple, so it stands apart
    Widget head(String txt, double w) => Container(
          width: w,
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            border: Border.all(color: Colors.white24, width: 0.5),
          ),
          child: Text.rich(TextSpan(text: tr(txt)),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.white, height: 1.15)),
        );

    const totalBg = Color(0xFFF6F0FD);
    final header = Row(children: [
      head('#', numW),
      head('Member', nameW),
      if (showKo) head('Korean name', koW),
      for (final c in unitCols) head(c, unitW),
      for (final c in valueCols) head(c, valW),
    ]);
    // total row: tap a stage to see every student at it
    final total = Row(children: [
      cell('', numW, bg: totalBg),
      cell("${tr('Total')} (${all.length})", nameW, bold: true, bg: totalBg, left: true),
      if (showKo) cell('', koW, bg: totalBg),
      for (int k = 0; k < unitCols.length; k++) cell('', unitW, bg: totalBg),
      for (final c in valueCols)
        () {
          final list = c == 'Guided' || c == 'Taught'
              ? allStu.where((s) => all.any((m) => (c == 'Guided' ? s.guide : s.teacher) == m.scj)).toList()
              : c == 'Dropped'
                  ? allStu.where((s) => s.dropped).toList()
                  : allStu.where((s) => s.stage == c).toList();
          return cell('${list.length}', valW, bold: true, bg: totalBg, tap: list.isEmpty ? null : () => _drill(context, t.stages, "$c — ${tr('all members')}", list));
        }(),
    ]);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(38, 12, 38, 0),
        child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (t.views.isNotEmpty) _drop('Reports', _view, t.views, (v) => _set(() => _view = v), all: '', width: 170),
          _drop('Region', _loc, _opts('loc', (m) => m.loc, 'Location'), (v) => _set(() {
                _loc = v;
                _sub = _dept = _team = '';
              })),
          _drop('Sub-region', _sub, _opts('sub', (m) => m.sub, 'Sub-location'), (v) => _set(() {
                _sub = v;
                _dept = _team = '';
              })),
          _drop('Department', _dept, _opts('dept', (m) => m.dept, 'Dept'), (v) => _set(() {
                _dept = v;
                _team = '';
              })),
          _drop('Team', _team, _opts('team', (m) => m.team, 'Team'), (v) => _set(() => _team = v), width: 140),
          _drop('As', _as, const ['Guide or BB teacher', 'Guide', 'BB teacher'], (v) => _set(() => _as = v.isEmpty ? 'Guide or BB teacher' : v), all: '', width: 190),
          _drop('Stage reached', _stageFilter, t.stages, (v) => _set(() => _stageFilter = v), all: 'Any stage', width: 190),
          _drop('Sort by', _sort, const ['Students', 'Furthest stage', 'Name'], (v) => _set(() => _sort = v.isEmpty ? 'Students' : v), all: '', width: 160),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 8),
            child: SizedBox(
              width: 200,
              child: TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: tr("Search a member"), isDense: true, filled: true, fillColor: AppPalette.bg(Colors.white), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
                onChanged: (v) => _set(() => _q = v),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 8),
            child: FilterChip(label: const Text("Only members with students"), selected: _onlyActive, onSelected: (v) => _set(() => _onlyActive = v)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ExportOnly(child: OutlinedButton.icon(onPressed: () => _excel(all, valueCols), icon: const Icon(Icons.download_rounded, size: 18), label: const Text("Excel"))),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(
          TextSpan(text: t.whole ? tr("The whole church. Tap a member to see their students; tap a number to see those students.") : tr("Your units. Tap a member to see their students; tap a number to see those students.")),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700)),
        ),
      ),
      // about 1 cm free on the left and right of the table
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 38),
          child: LayoutBuilder(
            builder: (_, bc) => Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width < bc.maxWidth ? bc.maxWidth : width,
                  height: bc.maxHeight,
                  child: Center(
                    child: SizedBox(
                      width: width,
                      // the header and total rows stay; the members scroll under them
                      child: Column(children: [
                        header,
                        total,
                        Expanded(
                          child: rows.isEmpty
                              ? Center(child: Text("No members to show.", style: TextStyle(color: AppPalette.fg(Colors.grey))))
                              : ListView.builder(
                                  itemCount: rows.length,
                                  itemExtent: rowH,
                                  itemBuilder: (_, i) {
                                    final m = rows[i];
                                    final bg = i.isEven ? Colors.white : const Color(0xFFFAF7FF);
                                    final mine = _studentsOf(m);
                                    return Row(children: [
                                      cell('${_page * _pageSize + i + 1}', numW, bg: bg),
                                      cell(m.name, nameW, bold: true, bg: bg, left: true, tap: mine.isEmpty ? null : () => _drill(context, t.stages, m.name, mine, m: m)),
                                      if (showKo) cell(m.ko, koW, bg: bg),
                                      for (final c in unitCols) cell(unit(m, c), unitW, bg: bg),
                                      for (final c in valueCols)
                                        () {
                                          final v = _num(m, c) ?? 0;
                                          final list = c == 'Guided'
                                              ? (t.guided[m.scj] ?? const <_Stu>[]).where((s) => _stageFilter.isEmpty || s.stage == _stageFilter).toList()
                                              : c == 'Taught'
                                                  ? (t.taught[m.scj] ?? const <_Stu>[]).where((s) => _stageFilter.isEmpty || s.stage == _stageFilter).toList()
                                                  : c == 'Dropped'
                                                      ? mine.where((s) => s.dropped).toList()
                                                      : mine.where((s) => s.stage == c).toList();
                                          return cell(v == 0 ? '' : '$v', valW, bg: bg, tap: list.isEmpty ? null : () => _drill(context, t.stages, "${m.name} — $c", list, m: m));
                                        }(),
                                    ]);
                                  },
                                ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      // 1000 members at a time
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton.icon(
              onPressed: _page > 0 ? () => setState(() => _page--) : null,
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text("Previous"),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text.rich(
                TextSpan(text: all.isEmpty ? '0' : "${_page * _pageSize + 1}–${_page * _pageSize + rows.length} ${tr('of')} ${all.length}"),
                style: GoogleFonts.merriweather(fontWeight: FontWeight.w800, color: AppPalette.fg(_kPurple)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _page < pages - 1 ? () => setState(() => _page++) : null,
              icon: const Icon(Icons.chevron_right_rounded),
              label: const Text("Next"),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ dashboard

/// The tracing summary by unit, level by level, like the Compilation screen:
/// side bar (level, units, as guide / BB teacher), key figures, a table of
/// the units (tap one to go down a level) and charts.
class MemberTracingDashboard extends StatefulWidget {
  const MemberTracingDashboard({super.key});
  @override
  State<MemberTracingDashboard> createState() => _MemberTracingDashboardState();
}

class _MemberTracingDashboardState extends State<MemberTracingDashboard> {
  bool _loading = true;
  String? _error;
  _Trace? _t;
  int _level = 0; // the rows: 0 region … 4 cell
  int _min = 0; // the viewer's own level (no higher)
  final List<String> _path = ['', '', '', '']; // region, sub region, department, team ('' = all)
  String _as = 'Guide or BB teacher';
  String _view = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool fresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await _Trace.load(fresh: fresh);
      if (!mounted) return;
      if (!t.views.contains(_view)) _view = t.views.isEmpty ? '' : t.views.first;
      // start at the first level where the viewer has more than one unit
      int min = 0;
      while (min < 4 && t.members.map((m) => m.at(min)).where((x) => x.isNotEmpty).toSet().length <= 1) {
        final only = t.members.map((m) => m.at(min)).firstWhere((x) => x.isNotEmpty, orElse: () => '');
        if (only.isEmpty) break;
        _path[min] = only;
        min++;
      }
      setState(() {
        _t = t;
        _min = min;
        _level = min;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load the tracing${friendlyTail(e)}";
        });
      }
    }
  }

  /// The members inside the picked units (levels above the rows).
  List<_Mem> get _scope => _t!.members.where((m) {
        if (_view.isNotEmpty && !_Trace.inView(m, _view)) return false;
        for (int i = 0; i < _level && i < 4; i++) {
          if (_path[i].isNotEmpty && m.at(i) != _path[i]) return false;
        }
        return true;
      }).toList();

  List<String> _opts(int i) {
    final set = <String>{
      for (final m in _t!.members)
        if (List.generate(i, (k) => _path[k].isEmpty || m.at(k) == _path[k]).every((x) => x)) m.at(i),
    }..removeWhere((x) => x.trim().isEmpty);
    return CompLevel.orderNames(set, _kLevelRule[i]);
  }

  /// Row key at the level: the unit with the units above it that the picks
  /// leave open, so equal names (1팀) under different parents stay apart.
  String _key(_Mem m) {
    final parts = <String>[];
    for (int i = 0; i <= _level; i++) {
      if (i < _level && i < 4 && _path[i].isNotEmpty) continue;
      parts.add(m.at(i).isEmpty ? '—' : m.at(i));
    }
    return parts.join(' › ');
  }

  ({int members, int active, Set<_Stu> students, int guided, int taught}) _stats(Iterable<_Mem> l) {
    int n = 0, a = 0, g = 0, t = 0;
    final s = <_Stu>{};
    for (final m in l) {
      n++;
      final mine = _t!.of(m, _as);
      if (mine.isNotEmpty) a++;
      s.addAll(mine);
      if (_as != 'BB teacher') g += _t!.guided[m.scj]?.length ?? 0;
      if (_as != 'Guide') t += _t!.taught[m.scj]?.length ?? 0;
    }
    return (members: n, active: a, students: s, guided: g, taught: t);
  }

  List<num?> _vals(Iterable<_Mem> l) {
    final st = _stats(l);
    return [
      st.members,
      st.active,
      st.members == 0 ? 0 : st.active / st.members * 100,
      st.guided,
      st.taught,
      st.students.length,
      for (final x in _t!.stages) st.students.where((s) => s.stage == x).length,
      st.students.where((s) => s.dropped).length,
    ];
  }

  List<RepCol> get _cols => [
        const RepCol('Members'),
        const RepCol('Taking part', 'Num'),
        const RepCol('Taking part', '%', '', true),
        const RepCol('Students', 'Guided'),
        const RepCol('Students', 'Taught'),
        const RepCol('Students', 'Total'),
        for (final x in _t!.stages) RepCol('Stage reached', x),
        const RepCol('Dropped'),
      ];

  RepBlock _block() {
    final l = _scope;
    final keys = <String, List<_Mem>>{};
    for (final m in l) {
      keys.putIfAbsent(_key(m), () => []).add(m);
    }
    final order = CompLevel.orderNames(keys.keys, _kLevelRule[_level]);
    return RepBlock(
      title: "${tr('By')} ${tr(_kLevels[_level])}",
      corner: _kLevels[_level],
      cols: _cols,
      rows: [
        RepRow('', 'Total', _vals(l), total: true),
        for (final k in order) RepRow('', k, _vals(keys[k]!)),
      ],
    );
  }

  void _down(RepRow r) {
    if (_level >= 4 || r.total) return;
    final l = _scope.where((m) => _key(m) == r.label).toList();
    if (l.isEmpty) return;
    setState(() {
      for (int i = 0; i <= _level && i < 4; i++) {
        _path[i] = l.first.at(i);
      }
      _level++;
    });
  }

  Widget _sidebar() {
    final children = <Widget>[
      Text("Filters", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: AppPalette.fg(_kPurple))),
      const SizedBox(height: 10),
      if (_t!.views.isNotEmpty) _drop('Reports', _view, _t!.views, (v) => setState(() => _view = v), all: '', width: 240),
      _drop('Level', '$_level', [for (int i = _min; i < 5; i++) '$i'], (v) => setState(() {
            _level = int.tryParse(v) ?? _level;
            for (int i = _level; i < 4; i++) {
              if (i >= _min) _path[i] = '';
            }
          }), all: '', width: 240, show: (v) => "${tr(_kLevels[int.parse(v)])} ${tr('status')}"),
      for (int i = _min; i < _level && i < 4; i++)
        _drop(_kLevels[i], _path[i], _opts(i), (v) => setState(() {
              _path[i] = v;
              for (int k = i + 1; k < 4; k++) {
                if (k >= _min) _path[k] = '';
              }
            }), all: "${tr('All')} ${tr(_kLevels[i])}", width: 240),
      _drop('As', _as, const ['Guide or BB teacher', 'Guide', 'BB teacher'], (v) => setState(() => _as = v.isEmpty ? 'Guide or BB teacher' : v), all: '', width: 240),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MemberTracingScreen())),
        icon: const Icon(Icons.format_list_numbered_rounded, size: 18),
        label: const Text("Check by name list"),
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _kpi(String label, String value, IconData icon, Color c) => Container(
        width: 200,
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.line(c.withValues(alpha: 0.25))),
          boxShadow: AppPalette.cardShadow,
        ),
        child: Row(children: [
          CircleAvatar(radius: 17, backgroundColor: AppPalette.bg(c.withValues(alpha: 0.12)), child: Icon(icon, size: 18, color: c)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(text: value), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(c))),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, height: 1.2, color: AppPalette.fg(Colors.grey.shade700))),
            ]),
          ),
        ]),
      );

  Widget _chartCard(String title, Widget chart) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.line(const Color(0x224A148C))),
        ),
        child: Column(children: [
          Text.rich(TextSpan(text: tr(title)), textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppPalette.fg(_kPurple))),
          const SizedBox(height: 6),
          chart,
        ]),
      );

  Future<void> _excel(RepBlock b) async {
    final book = RepBook();
    final sh = book.sheet('Tracing');
    sh.title(tr('Member evangelism tracing'));
    sh.title("${tr('As of')} ${DateFormat('d MMM yyyy HH:mm').format(DateTime.now())}", size: 10);
    sh.gap();
    sh.block(b);
    sh.widths(2, 26, 11, b.cols.length + 2);
    await book.save(context, 'Member_tracing_dashboard_${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1000;
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
      appBar: AppBar(
        centerTitle: true,
        title: Text("Member tracing · Dashboard", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 20, color: AppPalette.fg(_kPurple))),
        actions: [IconButton(tooltip: tr("Reload"), icon: const Icon(Icons.refresh_rounded), onPressed: () => _load(fresh: true))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text.rich(TextSpan(text: _error), textAlign: TextAlign.center)))
              : wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 280,
                        margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppPalette.bg(Colors.white),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppPalette.line(const Color(0x224A148C))),
                        ),
                        child: SingleChildScrollView(child: _sidebar()),
                      ),
                      Expanded(child: _content()),
                    ])
                  : _content(top: Padding(padding: const EdgeInsets.only(bottom: 8), child: Center(child: Wrap(alignment: WrapAlignment.center, children: [_sidebar()])))),
    );
  }

  Widget _content({Widget? top}) {
    final t = _t!;
    final b = _block();
    final st = _stats(_scope);
    final rows = b.rows.where((r) => !r.total).toList();
    final enrolled = st.students.where((s) => s.stage == 'Church enrolled').length;
    // path: where the view is (tap to go back up)
    final crumbs = <Widget>[
      for (int i = _min; i < _level && i < 4; i++)
        if (_path[i].isNotEmpty)
          ActionChip(
            visualDensity: VisualDensity.compact,
            label: Text.rich(TextSpan(text: _path[i])),
            onPressed: () => setState(() {
              _level = i + 1;
              for (int k = i + 1; k < 4; k++) {
                _path[k] = '';
              }
            }),
          ),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      if (top != null) top,
      if (crumbs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Icon(Icons.account_tree_rounded, size: 16, color: AppPalette.fg(_kPurple)),
            ...crumbs,
          ]),
        ),
      Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
        _kpi("Members", '${st.members}', Icons.groups_rounded, const Color(0xFF4A148C)),
        _kpi("Taking part (guide or BB teacher)", '${st.active} · ${st.members == 0 ? 0 : (st.active * 100 / st.members).round()}%', Icons.volunteer_activism_rounded, const Color(0xFF1565C0)),
        _kpi("Students guided", '${st.guided}', Icons.person_search_rounded, const Color(0xFF00695C)),
        _kpi("Students taught", '${st.taught}', Icons.menu_book_rounded, const Color(0xFF6A1B9A)),
        _kpi("Enrolled in the church", '$enrolled', Icons.church_rounded, const Color(0xFF2E7D32)),
        _kpi("Dropped", '${st.students.where((s) => s.dropped).length}', Icons.person_off_rounded, const Color(0xFFC62828)),
      ]),
      const SizedBox(height: 14),
      RepCard(
        title: b.title,
        actions: [
          repAction(Icons.fullscreen_rounded, 'Full screen', () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (c) => Scaffold(
                  appBar: AppBar(title: Text.rich(TextSpan(text: b.title))),
                  body: SingleChildScrollView(padding: const EdgeInsets.all(10), child: RepTable(block: b, labelW: 150, cellW: 54, fontSize: 11.5, rowH: 26, headH: 30)),
                ),
              ),
            );
          }),
          ExportOnly(child: repAction(Icons.download_rounded, 'Excel', () => _excel(b))),
        ],
        child: Column(children: [
          RepTable(block: b, labelW: 150, cellW: 54, fontSize: 11.5, rowH: 26, headH: 30, onTapRow: _level < 4 ? _down : null),
          if (_level < 4)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text("Tap a unit to see the units inside it.", textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
            ),
        ]),
      ),
      if (rows.isNotEmpty)
        _chartCard(
          "Members taking part, by ${_kLevels[_level].toLowerCase()} (%)",
          Bar3DChart(labels: [for (final r in rows) r.label], height: 260, series: [
            Bar3DSeries(tr("Taking part %"), kLightSeries[0], [for (final r in rows) (r.vals[2] ?? 0).toDouble()], pct: true),
          ]),
        ),
      if (rows.isNotEmpty)
        _chartCard(
          "Students guided and taught, by ${_kLevels[_level].toLowerCase()}",
          Bar3DChart(labels: [for (final r in rows) r.label], height: 260, series: [
            Bar3DSeries(tr("Guided"), kLightSeries[3], [for (final r in rows) (r.vals[3] ?? 0).toDouble()]),
            Bar3DSeries(tr("Taught"), kLightSeries[1], [for (final r in rows) (r.vals[4] ?? 0).toDouble()]),
          ]),
        ),
      _chartCard(
        "How far the students got",
        Bar3DChart(labels: [for (final x in t.stages) x], height: 260, series: [
          Bar3DSeries(tr("Students"), kLightSeries[2], [for (final x in t.stages) st.students.where((s) => s.stage == x).length.toDouble()]),
        ]),
      ),
    ]);
  }
}
