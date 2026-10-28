// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/app_sizes.dart';
import '../core/i18n.dart';

const Color _kPurple = Color(0xFF4A148C);

const Map<String, String> kPolicyLevels = {
  'all': 'Every level',
  'church': 'Church',
  'location': 'Location',
  'sub_location': 'Sub-location',
  'department': 'Department',
  'team': 'Team',
  'cell': 'Cell',
};

/// The duty that owns the policies / goals ("BB File" belongs to Evangelism).
String dutyFamily(String duty) =>
    const {'Evangelism Part', 'BB File', 'Evangelism Results', 'BB Results'}.contains(duty) ? 'Evangelism' : duty;

/// Can the signed-in user manage this duty's panel (duty_managers, 12_round11.sql)?
/// With [role] (the role an admin is viewing as), that role is checked
/// against `duty_managers` instead, so the admin sees exactly what the role sees.
Future<bool> canManageDuty(String duty, {String? role}) async {
  final db = Supabase.instance.client;
  try {
    if (role != null && role.isNotEmpty && role != 'admin') {
      final row = await db.from('duty_managers').select('manager_roles').eq('duty_name', dutyFamily(duty)).maybeSingle();
      final roles = List<String>.from(row?['manager_roles'] ?? const []);
      return roles.any((r) => r.contains('%') ? RegExp('^${RegExp.escape(r).replaceAll('%', '.*')}\$').hasMatch(role) : r == role);
    }
    return (await db.rpc('can_manage_duty', params: {'p_duty': duty})) == true;
  } catch (_) {
    return false;
  }
}

/// Duty management panel: policies & standards, monthly goals and — for
/// Evangelism — opening months, centers and stages. Only the managers
/// (duty_managers: the Evangelism Department at church level for Evangelism)
/// see and edit everything; everyone else only reads the policies and goals.
class DutyPanelScreen extends StatefulWidget {
  final String duty;
  final bool canManage;
  const DutyPanelScreen({super.key, required this.duty, this.canManage = false});

  /// Opens the panel, checking who may edit ([role]: the role being viewed as).
  static Future<void> open(BuildContext context, String duty, {String? role}) async {
    final manage = await canManageDuty(duty, role: role);
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => DutyPanelScreen(duty: duty, canManage: manage)));
  }

  @override
  State<DutyPanelScreen> createState() => _DutyPanelScreenState();
}

class _DutyPanelScreenState extends State<DutyPanelScreen> {
  String get _duty => dutyFamily(widget.duty);
  bool get _isEvangelism => _duty == 'Evangelism';

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, IconData, Widget)>[
      ("Policies & standards", Icons.gavel_rounded, PoliciesView(duty: _duty, canManage: widget.canManage)),
      ("Goals", Icons.flag_rounded, GoalsView(duty: _duty, canManage: widget.canManage)),
      if (_isEvangelism && widget.canManage) ...[
        ("Opening months", Icons.calendar_month_rounded, const _OpeningMonthsView()),
        ("Centers", Icons.location_city_rounded, const _CentersView()),
        ("Stages", Icons.stairs_rounded, const _StagesView()),
      ],
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
        appBar: AppBar(
          centerTitle: true,
          title: Text(widget.canManage ? "$_duty · management" : "$_duty · policies & goals",
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(_kPurple))),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: [for (final t in tabs) Tab(icon: Icon(t.$2, size: 18), text: tr(t.$1))],
          ),
        ),
        body: Column(children: [
          if (!widget.canManage)
            Container(
              width: double.infinity,
              color: AppPalette.bg(const Color(0xFFEDE3F8)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                _isEvangelism
                    ? "View only · the Evangelism Department (church level) sets the policies, goals, opening months, centers and stages."
                    : "View only · set by the department that manages this duty.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppPalette.fg(_kPurple)),
              ),
            ),
          Expanded(child: TabBarView(children: [for (final t in tabs) t.$3])),
        ]),
      ),
    );
  }
}

void _snack(BuildContext c, String m, {bool error = false}) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null, behavior: SnackBarBehavior.floating));

String _err(Object e) => e is PostgrestException ? e.message : e.toString();

// ---------------------------------------------------------------------------
// Policies & standards

class PoliciesView extends StatefulWidget {
  final String duty;
  final bool canManage;
  const PoliciesView({super.key, required this.duty, this.canManage = false});
  @override
  State<PoliciesView> createState() => _PoliciesViewState();
}

class _PoliciesViewState extends State<PoliciesView> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String _level = 'any';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db.from('duty_policies').select().eq('duty_name', widget.duty).order('level', ascending: true).order('category', ascending: true).order('sort_order', ascending: true);
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(r);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? p]) async {
    final title = TextEditingController(text: p?['title'] ?? '');
    final body = TextEditingController(text: p?['body'] ?? '');
    final category = TextEditingController(text: p?['category'] ?? 'General');
    String level = (p?['level'] ?? 'all').toString();
    bool active = p?['is_active'] != false;
    DateTime? from = DateTime.tryParse((p?['effective_from'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(p == null ? "New policy / standard" : "Edit policy / standard"),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: title, decoration: InputDecoration(labelText: tr("Title"), border: const OutlineInputBorder())),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: level,
                      decoration: InputDecoration(labelText: tr("Level"), border: const OutlineInputBorder(), isDense: true),
                      items: [for (final e in kPolicyLevels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => set(() => level = v ?? 'all'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: category, decoration: InputDecoration(labelText: tr("Category"), hintText: tr("e.g. BB, Attendance, Reporting"), border: const OutlineInputBorder(), isDense: true))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: body, minLines: 4, maxLines: 12, decoration: InputDecoration(labelText: tr("What the policy / standard says"), border: const OutlineInputBorder(), alignLabelWithHint: true)),
                const SizedBox(height: 6),
                Row(children: [
                  TextButton.icon(
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(from == null ? "In force from (optional)" : "From ${DateFormat('d MMM yyyy').format(from!)}"),
                    onPressed: () async {
                      final d = await showDatePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: from ?? DateTime.now());
                      if (d != null) set(() => from = d);
                    },
                  ),
                  const Spacer(),
                  const Text("Shown"),
                  Switch(value: active, onChanged: (v) => set(() => active = v)),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    final row = {
      'duty_name': widget.duty,
      'title': title.text.trim(),
      'body': body.text.trim(),
      'category': category.text.trim().isEmpty ? 'General' : category.text.trim(),
      'level': level,
      'is_active': active,
      'effective_from': from == null ? null : DateFormat('yyyy-MM-dd').format(from!),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (p == null) {
        await _db.from('duty_policies').insert(row);
      } else {
        await _db.from('duty_policies').update(row).eq('id', p['id']);
      }
      _load();
    } catch (e) {
      _snack(context, "Couldn't save: ${_err(e)}", error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Remove \"${p['title']}\"?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Remove", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('duty_policies').delete().eq('id', p['id']);
      _load();
    } catch (e) {
      _snack(context, "Couldn't remove: ${_err(e)}", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final q = _search.toLowerCase();
    final rows = _rows.where((p) {
      if (_level != 'any' && p['level'] != _level && p['level'] != 'all') return false;
      return q.isEmpty || '${p['title']} ${p['body']} ${p['category']}'.toLowerCase().contains(q);
    }).toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final p in rows) {
      groups.putIfAbsent("${kPolicyLevels[p['level']] ?? p['level']} · ${p['category']}", () => []).add(p);
    }
    return ListView(padding: AppSizes.page, children: [
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 8, children: [
        SizedBox(
          width: 260,
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: tr("Search policies"), isDense: true, border: const OutlineInputBorder()),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        DropdownButton<String>(
          value: _level,
          items: [
            const DropdownMenuItem(value: 'any', child: Text("All levels")),
            for (final e in kPolicyLevels.entries.where((e) => e.key != 'all')) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _level = v ?? 'any'),
        ),
        if (widget.canManage) ElevatedButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text("Add policy")),
      ]),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.all(30),
          child: Text(widget.canManage ? "No policies yet. Add the first one." : "No policies or standards have been published for this duty yet.",
              textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey.shade600))),
        ),
      for (final g in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Text(g.key, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(_kPurple))),
        ),
        for (final p in g.value)
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ExpansionTile(
              shape: const Border(),
              leading: Icon(p['is_active'] == false ? Icons.visibility_off_outlined : Icons.rule_rounded, color: AppPalette.fg(_kPurple), size: 20),
              title: Text((p['title'] ?? '').toString(), style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: p['effective_from'] == null ? null : Text("In force from ${p['effective_from']}", style: const TextStyle(fontSize: 11)),
              trailing: widget.canManage
                  ? PopupMenuButton<String>(
                      onSelected: (v) => v == 'edit' ? _edit(p) : _delete(p),
                      itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text("Edit")), PopupMenuItem(value: 'delete', child: Text("Remove"))],
                    )
                  : null,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [SelectableText((p['body'] ?? '').toString(), style: GoogleFonts.merriweather(fontSize: 12.5, height: 1.35))],
            ),
          ),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------------
// Goals

class GoalsView extends StatefulWidget {
  final String duty;
  final bool canManage;
  const GoalsView({super.key, required this.duty, this.canManage = false});
  @override
  State<GoalsView> createState() => _GoalsViewState();
}

class _GoalsViewState extends State<GoalsView> {
  final _db = Supabase.instance.client;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<Map<String, dynamic>> _rows = [];
  List<String> _metrics = [];
  bool _loading = true;

  String get _monthKey => DateFormat('yyyy-MM-dd').format(_month);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _db.from('duty_goals').select().eq('duty_name', widget.duty).eq('period_month', _monthKey).order('unit_level', ascending: true).order('location', ascending: true).order('metric', ascending: true);
      if (_metrics.isEmpty && widget.duty == 'Evangelism') {
        final st = await _db.from('evangelism_stages').select('stage').eq('is_active', true).order('sort_order', ascending: true);
        // Offline / Online: the prospects goals of Results By Units
        _metrics = ['Students', 'Overall', ...st.map((s) => s['stage'].toString()), 'Offline', 'Online'];
      }
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(r);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? g]) async {
    String level = (g?['unit_level'] ?? 'church').toString();
    final loc = TextEditingController(text: g?['location'] ?? '');
    final sub = TextEditingController(text: g?['sub_location'] ?? '');
    final dept = TextEditingController(text: g?['department'] ?? '');
    final team = TextEditingController(text: g?['team'] ?? '');
    final cell = TextEditingController(text: g?['cell_group'] ?? '');
    const levels = ['church', 'location', 'sub_location', 'department', 'team', 'cell'];
    int depth() => levels.indexOf(level);
    final metric = TextEditingController(text: g?['metric'] ?? (_metrics.isNotEmpty ? _metrics.first : ''));
    final target = TextEditingController(text: g?['target']?.toString() ?? '');
    final note = TextEditingController(text: g?['note'] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text("Goal for ${DateFormat('MMMM yyyy').format(_month)}"),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                  for (final l in levels)
                    ChoiceChip(
                      label: Text(kPolicyLevels[l] ?? l),
                      selected: level == l,
                      onSelected: (_) => set(() => level = l),
                    ),
                ]),
                for (final (i, c, label) in [(1, loc, "Location"), (2, sub, "Sub-location"), (3, dept, "Department"), (4, team, "Team"), (5, cell, "Cell")])
                  if (depth() >= i) ...[
                    const SizedBox(height: 10),
                    TextField(controller: c, decoration: InputDecoration(labelText: tr(label), border: const OutlineInputBorder(), isDense: true)),
                  ],
                const SizedBox(height: 10),
                if (_metrics.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _metrics.contains(metric.text) ? metric.text : _metrics.first,
                    decoration: InputDecoration(labelText: tr("What is counted"), border: const OutlineInputBorder(), isDense: true),
                    items: [for (final m in _metrics) DropdownMenuItem(value: m, child: Text(m))],
                    onChanged: (v) => metric.text = v ?? '',
                  )
                else
                  TextField(controller: metric, decoration: InputDecoration(labelText: tr("What is counted"), hintText: tr("e.g. Attendance %"), border: const OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 10),
                TextField(controller: target, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr("Target"), border: const OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 10),
                TextField(controller: note, decoration: InputDecoration(labelText: tr("Note (optional)"), border: const OutlineInputBorder(), isDense: true)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
          ],
        ),
      ),
    );
    final t = num.tryParse(target.text.replaceAll(',', '').trim());
    if (ok != true || t == null || metric.text.trim().isEmpty) return;
    final row = {
      'duty_name': widget.duty,
      'period_month': _monthKey,
      'unit_level': level,
      'location': depth() < 1 || loc.text.trim().isEmpty ? null : loc.text.trim(),
      'sub_location': depth() < 2 || sub.text.trim().isEmpty ? null : sub.text.trim(),
      if (depth() >= 3) 'department': dept.text.trim().isEmpty ? null : dept.text.trim(),
      if (depth() >= 4) 'team': team.text.trim().isEmpty ? null : team.text.trim(),
      if (depth() >= 5) 'cell_group': cell.text.trim().isEmpty ? null : cell.text.trim(),
      'metric': metric.text.trim(),
      'target': t,
      'note': note.text.trim().isEmpty ? null : note.text.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (g == null) {
        await _db.from('duty_goals').insert(row);
      } else {
        await _db.from('duty_goals').update(row).eq('id', g['id']);
      }
      _load();
    } catch (e) {
      _snack(context, "Couldn't save: ${_err(e)}", error: true);
    }
  }

  Future<void> _copyLastMonth() async {
    final prev = DateFormat('yyyy-MM-dd').format(DateTime(_month.year, _month.month - 1, 1));
    try {
      final r = await _db.from('duty_goals').select().eq('duty_name', widget.duty).eq('period_month', prev);
      final rows = [
        for (final g in r)
          {
            'duty_name': widget.duty,
            'period_month': _monthKey,
            'unit_level': g['unit_level'],
            'location': g['location'],
            'sub_location': g['sub_location'],
            if (g['department'] != null) 'department': g['department'],
            if (g['team'] != null) 'team': g['team'],
            if (g['cell_group'] != null) 'cell_group': g['cell_group'],
            'metric': g['metric'],
            'target': g['target'],
            'note': g['note'],
          }
      ];
      if (rows.isEmpty) {
        _snack(context, "Last month has no goals to copy.");
        return;
      }
      await _db.from('duty_goals').insert(rows);
      _load();
    } catch (e) {
      _snack(context, "Couldn't copy: ${_err(e)}", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: AppSizes.page, children: [
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
        IconButton(
          tooltip: tr("Previous month"),
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () {
            _month = DateTime(_month.year, _month.month - 1, 1);
            _load();
          },
        ),
        Text(DateFormat('MMMM yyyy').format(_month), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15)),
        IconButton(
          tooltip: tr("Next month"),
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () {
            _month = DateTime(_month.year, _month.month + 1, 1);
            _load();
          },
        ),
        if (widget.canManage) ...[
          ElevatedButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text("Add goal")),
          OutlinedButton.icon(onPressed: _copyLastMonth, icon: const Icon(Icons.copy_all_rounded), label: const Text("Copy last month")),
        ],
      ]),
      const SizedBox(height: 10),
      if (_loading)
        const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
      else if (_rows.isEmpty)
        Padding(
          padding: const EdgeInsets.all(30),
          child: Text("No goals set for this month.", textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey.shade600))),
        )
      else
        for (final g in _rows)
          Card(
            elevation: 0.5,
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: ListTile(
              leading: Icon(g['unit_level'] == 'church' ? Icons.church_rounded : (g['unit_level'] == 'location' ? Icons.location_on_rounded : Icons.place_outlined), color: AppPalette.fg(_kPurple)),
              title: Text("${g['metric']}: ${g['target']}", style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text([
                g['unit_level'] == 'church'
                    ? 'Whole church'
                    : [g['location'], g['sub_location'], g['department'], g['team'], g['cell_group']].where((x) => (x ?? '').toString().isNotEmpty).join(' › '),
                if ((g['note'] ?? '').toString().isNotEmpty) g['note'],
              ].join(' · ')),
              trailing: widget.canManage
                  ? PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') return _edit(g);
                        await _db.from('duty_goals').delete().eq('id', g['id']);
                        _load();
                      },
                      itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text("Edit")), PopupMenuItem(value: 'delete', child: Text("Remove"))],
                    )
                  : null,
            ),
          ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Evangelism settings

class _OpeningMonthsView extends StatefulWidget {
  const _OpeningMonthsView();
  @override
  State<_OpeningMonthsView> createState() => _OpeningMonthsViewState();
}

class _OpeningMonthsViewState extends State<_OpeningMonthsView> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _db.from('evangelism_opening_months').select().order('month_start', ascending: true);
    if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(r));
  }

  Future<void> _add() async {
    final d = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime(2035), initialDate: DateTime.now(), helpText: tr("Pick any day of the opening month"));
    if (d == null) return;
    final start = DateTime(d.year, d.month, 1);
    try {
      await _db.from('evangelism_opening_months').insert({'label': DateFormat('MMMM').format(start), 'month_start': DateFormat('yyyy-MM-dd').format(start), 'is_open': true});
      _load();
    } catch (e) {
      _snack(context, "Couldn't add: ${_err(e)}", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: AppSizes.page, children: [
      Text("Opening months decide the months students are counted under in the BB File and the Summary. Switch a month off when it closes.",
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
      const SizedBox(height: 8),
      Center(child: ElevatedButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text("Add opening month"))),
      const SizedBox(height: 8),
      for (final m in _rows)
        Card(
          elevation: 0.5,
          margin: const EdgeInsets.symmetric(vertical: 3),
          child: SwitchListTile(
            value: m['is_open'] == true,
            title: Text("${m['label']} ${DateTime.tryParse(m['month_start'].toString())?.year ?? ''}", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(m['is_open'] == true ? "Open" : "Closed"),
            secondary: IconButton(
              tooltip: tr("Remove"),
              icon: Icon(Icons.delete_outline_rounded, color: AppPalette.fg(Colors.red.shade700)),
              onPressed: () async {
                await _db.from('evangelism_opening_months').delete().eq('id', m['id']);
                _load();
              },
            ),
            onChanged: (v) async {
              await _db.from('evangelism_opening_months').update({'is_open': v}).eq('id', m['id']);
              _load();
            },
          ),
        ),
    ]);
  }
}

class _CentersView extends StatefulWidget {
  const _CentersView();
  @override
  State<_CentersView> createState() => _CentersViewState();
}

class _CentersViewState extends State<_CentersView> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  // Locations and their sub-locations from Supabase (locations / sub_locations)
  Map<String, List<String>> _units = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([
        _db.from('evangelism_centers').select().order('sort_order', ascending: true),
        _db.from('locations').select('id, location').order('location', ascending: true),
        _db.from('sub_locations').select(),
      ]);
      final locs = {for (final l in r[1] as List) l['id'].toString(): (l['location'] ?? '').toString()};
      final units = <String, List<String>>{for (final l in locs.values) if (l.isNotEmpty) l: <String>[]};
      for (final s in r[2] as List) {
        final loc = (locs[(s['location_id'] ?? '').toString()] ?? s['location_name'] ?? s['location'] ?? '').toString();
        final name = (s['name'] ?? s['sub_location'] ?? '').toString();
        if (loc.isEmpty || name.isEmpty) continue;
        units.putIfAbsent(loc, () => []).add(name);
      }
      for (final l in units.values) {
        l.sort();
      }
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(r[0] as List);
          _units = units;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load the centers: ${_err(e)}";
        });
      }
    }
  }

  /// Add or edit a center: name, and its location / sub-location picked from
  /// the church's locations.
  Future<void> _edit([Map<String, dynamic>? c]) async {
    final name = TextEditingController(text: (c?['name'] ?? '').toString());
    String? loc = (c?['location'] ?? '').toString().isEmpty ? null : c!['location'].toString();
    String? sub = (c?['sub_location'] ?? '').toString().isEmpty ? null : c!['sub_location'].toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final locs = [..._units.keys, if (loc != null && !_units.containsKey(loc)) loc!];
        final subs = [...(_units[loc] ?? const <String>[]), if (sub != null && !(_units[loc] ?? const <String>[]).contains(sub)) sub!];
        return AlertDialog(
          title: Text(c == null ? "New center place" : "Edit center place"),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, enabled: c == null, decoration: InputDecoration(labelText: tr("Center name"), border: const OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: loc,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr("Location"), border: const OutlineInputBorder(), isDense: true),
                items: [for (final l in locs) DropdownMenuItem(value: l, child: Text(l, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => set(() {
                  loc = v;
                  sub = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('sub-$loc'),
                initialValue: sub,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr("Sub-location"), border: const OutlineInputBorder(), isDense: true),
                items: [for (final s in subs) DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))],
                onChanged: loc == null ? null : (v) => set(() => sub = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(c == null ? "Add" : "Save")),
          ],
        );
      }),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    if (loc == null || sub == null) {
      _snack(context, "Choose the center's location and sub-location.", error: true);
      return;
    }
    try {
      if (c == null) {
        await _db.from('evangelism_centers').insert({'name': name.text.trim(), 'location': loc, 'sub_location': sub, 'sort_order': _rows.length + 1});
        _snack(context, "Center added");
      } else {
        await _db.from('evangelism_centers').update({'location': loc, 'sub_location': sub}).eq('name', c['name']);
        _snack(context, "Center saved");
      }
      _load();
    } catch (e) {
      _snack(context, "Couldn't save: ${_err(e)}", error: true);
    }
  }

  Widget _cell(String t, double w, {bool head = false, bool bold = false, Color? fg, Color? bg}) => Container(
        width: w,
        height: head ? 36 : 40,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: bg == null ? null : AppPalette.bg(bg), border: Border.all(color: AppPalette.line(Colors.black26), width: 0.5)),
        child: Text(t,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(fontSize: head ? 11 : 11.5, fontWeight: head || bold ? FontWeight.bold : FontWeight.normal, color: AppPalette.fg(fg ?? (head ? Colors.white : Colors.black87)))),
      );

  Widget _box(Widget child, double w, Color? bg) => Container(
        width: w,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg == null ? null : AppPalette.bg(bg), border: Border.all(color: AppPalette.line(Colors.black26), width: 0.5)),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    const w = [40.0, 170.0, 130.0, 140.0, 80.0, 70.0, 56.0];
    const head = ["No.", "Center place", "Location", "Sub-location", "Opening", "In use", ""];
    return ListView(padding: AppSizes.page, children: [
      Text("Each center belongs to a location and sub-location of the church. \"Opening\" centers are listed in the Summary's Opening Centers table; switch off a center that is no longer used.",
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
      const SizedBox(height: 8),
      Center(child: ElevatedButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text("Add center"))),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: Center(
              child: Column(children: [
                Row(mainAxisSize: MainAxisSize.min, children: [for (int i = 0; i < head.length; i++) _cell(head[i], w[i], head: true, bg: const Color(0xFF1E293B))]),
                if (_rows.isEmpty)
                  Padding(padding: const EdgeInsets.all(20), child: Text("No centers yet. Tap \"Add center\".", style: TextStyle(color: AppPalette.fg(Colors.grey)))),
                for (int r = 0; r < _rows.length; r++)
                  Builder(builder: (_) {
                    final c = _rows[r];
                    final off = c['is_active'] == false;
                    final bg = r.isEven ? Colors.white : const Color(0xFFF8FAFC);
                    final missing = (c['location'] ?? '').toString().isEmpty || (c['sub_location'] ?? '').toString().isEmpty;
                    return Row(mainAxisSize: MainAxisSize.min, children: [
                      _cell('${r + 1}', w[0], bg: bg),
                      _cell(c['name'].toString(), w[1], bold: true, fg: off ? Colors.grey : null, bg: bg),
                      _cell(missing && (c['location'] ?? '').toString().isEmpty ? 'Not set' : (c['location'] ?? '').toString(), w[2], fg: (c['location'] ?? '').toString().isEmpty ? Colors.red.shade700 : null, bg: bg),
                      _cell((c['sub_location'] ?? '').toString().isEmpty ? 'Not set' : c['sub_location'].toString(), w[3], fg: (c['sub_location'] ?? '').toString().isEmpty ? Colors.red.shade700 : null, bg: bg),
                      _box(
                          Checkbox(
                            value: c['is_opening'] == true,
                            onChanged: (v) async {
                              await _db.from('evangelism_centers').update({'is_opening': v == true}).eq('name', c['name']);
                              _load();
                            },
                          ),
                          w[4],
                          bg),
                      _box(
                          Transform.scale(
                            scale: 0.8,
                            child: Switch(
                              value: !off,
                              onChanged: (v) async {
                                await _db.from('evangelism_centers').update({'is_active': v}).eq('name', c['name']);
                                _load();
                              },
                            ),
                          ),
                          w[5],
                          bg),
                      _box(IconButton(tooltip: tr("Edit"), icon: Icon(Icons.edit_rounded, size: 18, color: AppPalette.fg(_kPurple)), onPressed: () => _edit(c)), w[6], bg),
                    ]);
                  }),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _StagesView extends StatefulWidget {
  const _StagesView();
  @override
  State<_StagesView> createState() => _StagesViewState();
}

class _StagesViewState extends State<_StagesView> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _db.from('evangelism_stages').select().order('sort_order', ascending: true);
    if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(r));
  }

  Future<void> _set(Map s, String col, bool v) async {
    await _db.from('evangelism_stages').update({col: v}).eq('stage', s['stage']);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: AppSizes.page, children: [
      Text("Overall = the stages ticked \"Overall\". Students = the stages ticked \"Students\". The order here is the order of the columns.",
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
      const SizedBox(height: 8),
      for (final s in _rows)
        Card(
          elevation: 0.5,
          margin: const EdgeInsets.symmetric(vertical: 3),
          child: ListTile(
            leading: CircleAvatar(radius: 12, backgroundColor: Color(0xFF000000 | (int.tryParse(s['color_hex'].toString().replaceAll('#', ''), radix: 16) ?? 0x4A148C))),
            title: Text(s['stage'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: Wrap(spacing: 4, children: [
              FilterChip(label: const Text("Overall"), selected: s['in_overall'] == true, onSelected: (v) => _set(s, 'in_overall', v)),
              FilterChip(label: const Text("Students"), selected: s['in_students'] == true, onSelected: (v) => _set(s, 'in_students', v)),
              FilterChip(label: const Text("Shown"), selected: s['is_active'] != false, onSelected: (v) => _set(s, 'is_active', v)),
            ]),
          ),
        ),
    ]);
  }
}
