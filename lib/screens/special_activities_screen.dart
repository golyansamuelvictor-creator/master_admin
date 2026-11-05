import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/compilation_rules.dart';
import '../core/i18n.dart';
import '../core/table_export.dart';
import 'theology/student_duties.dart' show FrozenGrid;

const Color _kPurple = Color(0xFF4A148C);
final _f = DateFormat('yyyy-MM-dd');
String _err(Object e) => e is PostgrestException ? e.message : e.toString();

const _subjects = {'workers': 'Workers', 'saints': 'Saints', 'all': 'All members', 'students': 'Center students'};
const _entryModes = {
  'creator': 'Only me (the creator)',
  'unit_leaders': "The units' leaders",
  'unit_secretaries': "The units' secretaries",
};
const _levels = {
  'location': 'Location',
  'sub_location': 'Sub-location',
  'department': 'Department',
  'team': 'Team',
  'cell_group': 'Cell group',
  'church_department': 'Church (24) department',
};
/// The kinds of special activity (the user's list; "Others" lets one type a kind).
const kActivityKinds = [
  'Special Workers Training',
  'Saints Special Training',
  'Workers Workshop',
  'Saints Workshop',
  'Seminar',
  'Retreat',
  'Special Evangelism Period',
  'Campaign',
  'Test',
  'Others',
];

IconData activityIcon(String? kind) {
  final k = (kind ?? '').toLowerCase();
  if (k.contains('training')) return Icons.school_rounded;
  if (k.contains('workshop')) return Icons.handyman_rounded;
  if (k.contains('seminar')) return Icons.co_present_rounded;
  if (k.contains('retreat')) return Icons.forest_rounded;
  if (k.contains('evangel')) return Icons.campaign_rounded;
  if (k.contains('campaign')) return Icons.flag_rounded;
  if (k.contains('test')) return Icons.quiz_rounded;
  return Icons.event_note_rounded;
}

Color activityColor(String? kind) {
  final k = (kind ?? '').toLowerCase();
  if (k.contains('training')) return const Color(0xFF1565C0);
  if (k.contains('workshop')) return const Color(0xFF00897B);
  if (k.contains('seminar')) return const Color(0xFF6A1B9A);
  if (k.contains('retreat')) return const Color(0xFF2E7D32);
  if (k.contains('evangel')) return const Color(0xFFEF6C00);
  if (k.contains('campaign')) return const Color(0xFFC62828);
  if (k.contains('test')) return const Color(0xFF5D4037);
  return const Color(0xFF4A148C);
}

/// The level of a role (for "who enters the records").
String roleLevel(Map r) {
  final k = (r['role_key'] ?? '').toString().toLowerCase();
  final g = (r['Grouping'] ?? '').toString().toLowerCase();
  final s = (r['approval_scope'] ?? '').toString().toLowerCase();
  if (k.contains('cell') || s == 'cell_group' || g.startsWith('cell')) return 'Cell';
  if (k.contains('team') || s == 'team' || s == 'location_team' || g.startsWith('team')) return 'Team';
  if (k.startsWith('sub_loc') || s == 'sub_location' || g.startsWith('sub')) return 'Sub-location';
  if (k.startsWith('dept_') || s == 'department' || s == 'location_department' || g.startsWith('dept')) return 'Department';
  return 'Location';
}

bool _churchRole(Map r) {
  final k = (r['role_key'] ?? '').toString().toLowerCase();
  final g = (r['Grouping'] ?? '').toString().toLowerCase();
  final s = (r['approval_scope'] ?? '').toString().toLowerCase();
  return k == 'admin' || k == 'member' || k == 'saint' || k.startsWith('church_') || k.startsWith('korean_') ||
      g.startsWith('24-dept') || g.startsWith('church') || g == 'saint' || s == 'church' || s == 'church_department';
}

const _fieldTypes = {'yesno': 'Yes / No', 'choice': 'Choice list', 'number': 'Number / score', 'text': 'Text'};

/// The days an activity meets, from its start to its end (or today).
List<DateTime> activitySessions(Map a, {DateTime? until}) {
  final start = DateTime.tryParse((a['start_date'] ?? '').toString());
  if (start == null) return const [];
  final end = DateTime.tryParse((a['end_date'] ?? '').toString()) ?? start;
  final last = until != null && until.isBefore(end) ? until : end;
  final sch = Map<String, dynamic>.from((a['schedule'] as Map?) ?? const {});
  final mode = (sch['mode'] ?? 'once').toString();
  final days = {...((sch['days'] as List?) ?? const []).map((e) => (e as num).toInt())};
  if (mode == 'once') return last.isBefore(start) ? const [] : [start];
  final out = <DateTime>[];
  for (var d = start; !d.isAfter(last) && out.length < 400; d = DateTime(d.year, d.month, d.day + 1)) {
    if (mode == 'daily' || days.contains(d.weekday)) out.add(d);
  }
  return out;
}

/// Dashboard › Special Activities: activities shared with me and those I
/// created; any worker can create one.
class SpecialActivitiesScreen extends StatefulWidget {
  const SpecialActivitiesScreen({super.key});
  @override
  State<SpecialActivitiesScreen> createState() => _SpecialActivitiesScreenState();
}

class _SpecialActivitiesScreenState extends State<SpecialActivitiesScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  Map<String, int> _unitCount = {};
  bool _loading = true;
  String? _error;
  String _q = '';
  bool _closed = false;

  String? get _uid => _db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db.from('special_activities').select().order('start_date', ascending: false);
      final u = await _db.from('special_activity_units').select('activity_id');
      final n = <String, int>{};
      for (final x in u) {
        n.update(x['activity_id'].toString(), (v) => v + 1, ifAbsent: () => 1);
      }
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(r);
        _unitCount = n;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load (run 23_round22.sql): ${_err(e)}";
      });
    }
  }

  Future<void> _new() async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ActivityEditor()));
    if (saved == true) _load();
  }

  Widget _card(Map<String, dynamic> a, int i) {
    final start = DateTime.tryParse((a['start_date'] ?? '').toString());
    final end = DateTime.tryParse((a['end_date'] ?? '').toString());
    final active = a['status'] == 'Active';
    final mine = a['owner_id'] == _uid;
    final color = activityColor(a['kind']?.toString());
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final all = activitySessions(a).length;
    final done = activitySessions(a, until: today).length;
    final dates = start == null
        ? ''
        : (end == null || end == start ? DateFormat('d MMM yyyy').format(start) : "${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(end)}");
    return TweenAnimationBuilder<double>(
      key: ValueKey(a['id']),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + 60 * (i % 8)),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.20), blurRadius: 20, spreadRadius: -5, offset: const Offset(0, 10)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 3, offset: const Offset(0, 1)),
          ],
        ),
        child: Material(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityScreen(activityId: a['id'].toString())));
              _load();
            },
            child: Column(children: [
              // coloured top with the kind's icon
              Container(
                height: 58,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppPalette.solid(color), AppPalette.solid(Color.lerp(color, Colors.black, 0.3)!)]),
                ),
                child: Stack(children: [
                  Positioned(right: -8, top: -10, child: Icon(activityIcon(a['kind']?.toString()), size: 76, color: Colors.white.withValues(alpha: 0.12))),
                  Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(activityIcon(a['kind']?.toString()), color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text((a['kind'] ?? 'Special activity').toString(), style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                    ]),
                  ),
                  Positioned(
                    right: 10,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: active ? 0.95 : 0.6), borderRadius: BorderRadius.circular(12)),
                      child: Text(active ? "Active" : "Closed", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: active ? Colors.green.shade800 : Colors.grey.shade700)),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(children: [
                  Text((a['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14.5)),
                  const SizedBox(height: 8),
                  Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 4, children: [
                    _info(Icons.event_rounded, dates),
                    _info(Icons.people_alt_rounded, _subjects[a['subjects']] ?? ''),
                    _info(Icons.account_tree_rounded, "${_unitCount[a['id'].toString()] ?? 0} unit${(_unitCount[a['id'].toString()] ?? 0) == 1 ? '' : 's'}"),
                    _info(mine ? Icons.person_rounded : Icons.share_rounded, mine ? "Created by me" : "By ${a['owner_name'] ?? 'a leader'}"),
                  ]),
                  const SizedBox(height: 10),
                  // how far along the sessions are
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(value: all == 0 ? 0 : done / all, minHeight: 7, color: AppPalette.solid(color), backgroundColor: AppPalette.bg(color.withValues(alpha: 0.12))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text("$done of $all sessions", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(color))),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _info(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 14, color: AppPalette.fg(Colors.blueGrey.shade600)),
        const SizedBox(width: 4),
        Text(t, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.blueGrey.shade700))),
      ]);

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    bool show(Map a) => (_closed || a['status'] == 'Active') && (q.isEmpty || "${a['title']} ${a['kind']} ${a['description']} ${a['owner_name']}".toLowerCase().contains(q));
    final shared = _rows.where((a) => a['owner_id'] != _uid && show(a)).toList();
    final mine = _rows.where((a) => a['owner_id'] == _uid && show(a)).toList();
    final activeCount = _rows.where((a) => a['status'] == 'Active').length;
    Widget list(List<Map<String, dynamic>> l, String empty) => _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
            : RefreshIndicator(
                onRefresh: _load,
                child: l.isEmpty
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(children: [
                            Icon(Icons.event_note_rounded, size: 52, color: AppPalette.fg(_kPurple.withValues(alpha: 0.3))),
                            const SizedBox(height: 10),
                            Text(empty, textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey.shade600))),
                          ]),
                        ),
                      ])
                    : LayoutBuilder(builder: (context, box) {
                        final cols = box.maxWidth >= 1100 ? 3 : (box.maxWidth >= 700 ? 2 : 1);
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: 196, crossAxisSpacing: 14, mainAxisSpacing: 14),
                          itemCount: l.length,
                          itemBuilder: (_, i) => _card(l[i], i),
                        );
                      }),
              );
    Widget stat(String n, String label) => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(n, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          Text(label, style: GoogleFonts.merriweather(fontSize: 10.5, color: Colors.white70)),
        ]);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
        body: Column(children: [
          // header: title, numbers, search and the two lists
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF2A1458), Color(0xFF4A148C), Color(0xFF7B4FC0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
              boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: SafeArea(
              bottom: false,
              child: Column(children: [
                Row(children: [
                  const BackButton(color: Colors.white),
                  Expanded(
                    child: Text("Special Activities", textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
                  ),
                  IconButton(tooltip: tr("Reload"), icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _load),
                ]),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  stat("$activeCount", "active"),
                  stat("${_rows.where((a) => a['owner_id'] != _uid).length}", "shared with me"),
                  stat("${_rows.where((a) => a['owner_id'] == _uid).length}", "created by me"),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(children: [
                    Expanded(
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(20)),
                        child: Row(children: [
                          Icon(Icons.search_rounded, size: 18, color: AppPalette.fg(_kPurple)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              decoration: InputDecoration(hintText: tr("Search activities"), isDense: true, border: InputBorder.none),
                              onChanged: (v) => setState(() => _q = v),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: const Text("Closed too"),
                      selected: _closed,
                      onSelected: (v) => setState(() => _closed = v),
                      backgroundColor: Colors.white,
                    ),
                  ]),
                ),
                TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: const Color(0xFFFFD54F),
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(height: 38, text: "${tr('Shared with me')} (${shared.length})"),
                    Tab(height: 38, text: "${tr('Created by me')} (${mine.length})"),
                  ],
                ),
              ]),
            ),
          ),
          Expanded(
            child: TabBarView(children: [
              list(shared, "No activity has been shared with your units yet."),
              list(mine, "You haven't created an activity yet. Tap \"New activity\"."),
            ]),
          ),
        ]),
        floatingActionButton: FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.add_rounded), label: const Text("New activity")),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create / edit

class ActivityEditor extends StatefulWidget {
  final Map<String, dynamic>? activity;
  final List<Map<String, dynamic>> units;
  const ActivityEditor({super.key, this.activity, this.units = const []});
  @override
  State<ActivityEditor> createState() => _ActivityEditorState();
}

class _ActivityEditorState extends State<ActivityEditor> {
  final _db = Supabase.instance.client;
  late final _title = TextEditingController(text: (widget.activity?['title'] ?? '').toString());
  late final _kind = TextEditingController(text: (widget.activity?['kind'] ?? '').toString());
  late final _desc = TextEditingController(text: (widget.activity?['description'] ?? '').toString());
  late DateTime _start = DateTime.tryParse((widget.activity?['start_date'] ?? '').toString()) ?? DateTime.now();
  late DateTime? _end = DateTime.tryParse((widget.activity?['end_date'] ?? '').toString());
  late String _mode = ((widget.activity?['schedule'] as Map?)?['mode'] ?? 'once').toString();
  late final Set<int> _days = {...(((widget.activity?['schedule'] as Map?)?['days'] as List?) ?? const []).map((e) => (e as num).toInt())};
  late String _subj = (widget.activity?['subjects'] ?? 'workers').toString();
  late final String _entry = (widget.activity?['entry_mode'] ?? 'creator').toString();
  // who enters: these roles in the shared units (the creator always can)
  late final _otherKind = TextEditingController(text: kActivityKinds.contains(_kind.text) ? '' : _kind.text);
  late final Set<String> _roles = {...List<String>.from((widget.activity?['entry_roles'] as List?) ?? const [])};
  List<Map<String, dynamic>> _appRoles = [];

  @override
  void initState() {
    super.initState();
    _db.from('app_roles').select('role_key, display_name, "Grouping", approval_scope').order('display_name').then((r) {
      if (mounted) setState(() => _appRoles = List<Map<String, dynamic>>.from(r).where((x) => !_churchRole(x)).toList());
    }).catchError((_) {});
  }
  late final List<Map<String, dynamic>> _fields = widget.activity == null
      ? [
          {'key': 'attended', 'label': 'Attended', 'type': 'yesno', 'options': <String>[]},
        ]
      : List<Map<String, dynamic>>.from(((widget.activity!['fields'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
  late final List<Map<String, dynamic>> _units = [for (final u in widget.units) Map<String, dynamic>.from(u)];
  bool _saving = false;
  String? _note;

  Future<void> _editField([int? i]) async {
    final f = i == null ? <String, dynamic>{'label': '', 'type': 'yesno', 'options': <String>[]} : Map<String, dynamic>.from(_fields[i]);
    final label = TextEditingController(text: (f['label'] ?? '').toString());
    final opts = TextEditingController(text: List<String>.from((f['options'] as List?) ?? const []).join(', '));
    String type = (f['type'] ?? 'yesno').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(i == null ? "What to record" : "Edit what is recorded"),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: label, decoration: InputDecoration(labelText: tr("Name (e.g. Attended, Test score, Remarks)"), border: const OutlineInputBorder())),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(labelText: tr("Kind of answer"), border: const OutlineInputBorder()),
                items: [for (final e in _fieldTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => set(() => type = v ?? 'yesno'),
              ),
              if (type == 'choice') ...[
                const SizedBox(height: 10),
                TextField(controller: opts, decoration: InputDecoration(labelText: tr("Choices, separated by commas"), border: const OutlineInputBorder())),
              ],
            ]),
          ),
          actions: [
            if (i != null)
              TextButton(
                onPressed: () {
                  setState(() => _fields.removeAt(i));
                  Navigator.pop(ctx, false);
                },
                child: Text("Remove", style: TextStyle(color: AppPalette.fg(Colors.red.shade700))),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("OK")),
          ],
        ),
      ),
    );
    if (ok != true || label.text.trim().isEmpty) return;
    final key = (f['key'] ?? '').toString().isNotEmpty
        ? f['key'].toString()
        : "${label.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_${DateTime.now().millisecondsSinceEpoch % 10000}";
    final row = {
      'key': key,
      'label': label.text.trim(),
      'type': type,
      'options': type == 'choice' ? opts.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() : <String>[],
    };
    setState(() => i == null ? _fields.add(row) : _fields[i] = row);
  }

  Future<void> _addUnit() async {
    String level = 'location';
    final picks = <String?>[null, null, null, null, null];
    Map<String, dynamic>? dept; // church (24) department
    List<Map<String, dynamic>> depts = [];
    bool deptAsked = false;
    final opts = <int, List<String>>{};
    const cols = ['location', 'sub_location', 'department', 'team', 'cell_group'];
    Future<void> loadOpts(int k, void Function(void Function()) set) async {
      try {
        final r = await _db.rpc('sa_unit_options', params: {
          'p_level': cols[k],
          'p_location': k > 0 ? picks[0] : null,
          'p_sub': k > 1 ? picks[1] : null,
          'p_dept': k > 2 ? picks[2] : null,
          'p_team': k > 3 ? picks[3] : null,
        });
        final names = List<String>.from(r as List);
        set(() => opts[k] = CompLevel.orderNames(names, const ['Location', 'Sub-location', 'Dept', 'Team', 'Cell'][k]));
      } catch (_) {
        set(() => opts[k] = const []);
      }
    }

    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final depth = cols.indexOf(level);
        if (level == 'church_department' && !deptAsked) {
          deptAsked = true;
          _db.from('official_departments').select('id, name, name_en, name_ko, parent_id').order('name').then((r) {
            set(() => depts = List<Map<String, dynamic>>.from(r).where((d) => d['parent_id'] == null).toList());
          }).catchError((_) {});
        }
        if (depth >= 0) {
          for (int k = 0; k <= depth; k++) {
            if (!opts.containsKey(k) && (k == 0 || picks[k - 1] != null)) {
              opts[k] = const [];
              loadOpts(k, set);
            }
          }
        }
        String name(Map d) => [d['name_en'], d['name'], d['name_ko']].firstWhere((x) => (x ?? '').toString().isNotEmpty, orElse: () => '').toString();
        final ready = level == 'church_department' ? dept != null : (depth >= 0 && picks[depth] != null);
        return AlertDialog(
          title: const Text("Share with a unit"),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: level,
                decoration: InputDecoration(labelText: tr("Level"), border: const OutlineInputBorder()),
                items: [for (final e in _levels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => set(() {
                  level = v ?? 'location';
                  for (int k = 0; k < 5; k++) {
                    if (k > cols.indexOf(level)) picks[k] = null;
                  }
                }),
              ),
              const SizedBox(height: 10),
              if (level == 'church_department')
                DropdownButtonFormField<String>(
                  initialValue: dept?['id']?.toString(),
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr("Department"), border: const OutlineInputBorder()),
                  items: [for (final d in depts) DropdownMenuItem(value: d['id'].toString(), child: Text(name(d), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => set(() => dept = depts.firstWhere((d) => d['id'].toString() == v)),
                )
              else
                for (int k = 0; k <= depth; k++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('p$k|${picks.take(k).join('|')}'),
                      initialValue: (opts[k] ?? const []).contains(picks[k]) ? picks[k] : null,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: tr(_levels[cols[k]]!), border: const OutlineInputBorder(), isDense: true),
                      items: [for (final o in opts[k] ?? const <String>[]) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
                      onChanged: k > 0 && picks[k - 1] == null
                          ? null
                          : (v) => set(() {
                                picks[k] = v;
                                for (int j = k + 1; j < 5; j++) {
                                  picks[j] = null;
                                  opts.remove(j);
                                }
                              }),
                    ),
                  ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            FilledButton(
              onPressed: !ready
                  ? null
                  : () => Navigator.pop(ctx, level == 'church_department'
                      ? {'level': level, 'department': name(dept!), 'official_dept_id': dept!['id'], 'label': name(dept!)}
                      : {
                          'level': level,
                          for (int k = 0; k <= depth; k++) cols[k]: picks[k],
                          'label': [for (int k = 0; k <= depth; k++) picks[k]].join(' › '),
                        }),
              child: const Text("Add"),
            ),
          ],
        );
      }),
    );
    if (res != null && !_units.any((u) => u['label'] == res['label'] && u['level'] == res['level'])) setState(() => _units.add(res));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return setState(() => _note = "Give the activity a title.");
    if (_fields.isEmpty) return setState(() => _note = "Add at least one thing to record.");
    if (_units.isEmpty) return setState(() => _note = "Share it with at least one unit.");
    if (_mode == 'days' && _days.isEmpty) return setState(() => _note = "Choose the days it meets.");
    setState(() {
      _saving = true;
      _note = null;
    });
    try {
      String? ownerName;
      try {
        final p = await _db.from('profiles').select('full_name').eq('id', _db.auth.currentUser!.id).maybeSingle();
        ownerName = p?['full_name']?.toString();
      } catch (_) {}
      final row = {
        'title': _title.text.trim(),
        'kind': _kind.text.trim().isEmpty ? null : _kind.text.trim(),
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'start_date': _f.format(_start),
        'end_date': _end == null ? null : _f.format(_end!),
        'schedule': {'mode': _mode, if (_mode == 'days') 'days': (_days.toList()..sort())},
        'subjects': _subj,
        'fields': _fields,
        'entry_mode': _roles.isEmpty ? 'creator' : _entry,
        'entry_roles': _roles.toList()..sort(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      String id;
      if (widget.activity == null) {
        final r = await _db.from('special_activities').insert({...row, 'owner_id': _db.auth.currentUser!.id, 'owner_name': ownerName}).select('id').single();
        id = r['id'].toString();
      } else {
        id = widget.activity!['id'].toString();
        await _db.from('special_activities').update(row).eq('id', id);
      }
      // units: the removed ones go (with their records), the new ones are added
      final keep = {for (final u in _units) if (u['id'] != null) u['id'].toString()};
      for (final u in widget.units) {
        if (!keep.contains(u['id'].toString())) await _db.from('special_activity_units').delete().eq('id', u['id']);
      }
      final add = [
        for (final u in _units)
          if (u['id'] == null) {...u, 'activity_id': id},
      ];
      if (add.isNotEmpty) await _db.from('special_activity_units').insert(add);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _note = "Couldn't save (run 23_round22.sql): ${_err(e)}";
        });
      }
    }
  }

  Widget _step(int n, String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.10), blurRadius: 14, spreadRadius: -3, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircleAvatar(radius: 12, backgroundColor: AppPalette.solid(_kPurple), child: Text("$n", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: AppPalette.fg(_kPurple))),
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String l, {String? hint}) => InputDecoration(labelText: tr(l), hintText: hint == null ? null : tr(hint), border: const OutlineInputBorder(), isDense: true, alignLabelWithHint: true);
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 46,
        title: Text(widget.activity == null ? "New special activity" : "Edit activity", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple))),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.send_rounded, size: 18), label: Text(widget.activity == null ? "Create & share" : "Save")),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.all(12), children: [
            if (_note != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_note!, style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
            if (_saving) const LinearProgressIndicator(minHeight: 2),
            _step(1, "What it is", [
              TextField(controller: _title, decoration: deco("Title", hint: "e.g. Workers' special training 2026")),
              const SizedBox(height: 10),
              Text("Kind of special activity", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey.shade700))),
              const SizedBox(height: 6),
              Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                for (final k in kActivityKinds)
                  ChoiceChip(
                    avatar: Icon(activityIcon(k), size: 16, color: AppPalette.fg(activityColor(k))),
                    label: Text(k),
                    selected: k == 'Others' ? (_kind.text.isNotEmpty && !kActivityKinds.contains(_kind.text)) || _kind.text == 'Others' : _kind.text == k,
                    onSelected: (_) => setState(() => _kind.text = k),
                  ),
              ]),
              if (_kind.text == 'Others' || (_kind.text.isNotEmpty && !kActivityKinds.contains(_kind.text))) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _otherKind,
                  decoration: deco("Name the kind"),
                  onChanged: (v) => _kind.text = v.trim().isEmpty ? 'Others' : v.trim(),
                ),
              ],
              const SizedBox(height: 10),
              TextField(controller: _desc, minLines: 2, maxLines: 6, decoration: deco("Details", hint: "Purpose, venue, who should attend …")),
            ]),
            _step(2, "When", [
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text("Starts ${DateFormat('EEE d MMM yyyy').format(_start)}"),
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2024), lastDate: DateTime(2035));
                    if (d != null) setState(() => _start = d);
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_available_rounded, size: 18),
                  label: Text(_end == null ? "Ends: same day" : "Ends ${DateFormat('EEE d MMM yyyy').format(_end!)}"),
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: _end ?? _start, firstDate: _start, lastDate: DateTime(2035));
                    if (d != null) setState(() => _end = d);
                  },
                ),
              ]),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'once', label: Text("Once")),
                  ButtonSegment(value: 'daily', label: Text("Every day")),
                  ButtonSegment(value: 'days', label: Text("Chosen days")),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
              if (_mode == 'days') ...[
                const SizedBox(height: 8),
                Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [
                  for (int d = 1; d <= 7; d++)
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1]),
                      selected: _days.contains(d),
                      onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
                    ),
                ]),
              ],
              const SizedBox(height: 6),
              Text("${activitySessions({'start_date': _f.format(_start), 'end_date': _end == null ? null : _f.format(_end!), 'schedule': {'mode': _mode, 'days': _days.toList()}}).length} session(s)",
                  style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.blueGrey.shade700))),
            ]),
            _step(3, "Who is tracked", [
              Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                for (final e in _subjects.entries) ChoiceChip(label: Text(e.value), selected: _subj == e.key, onSelected: (_) => setState(() => _subj = e.key)),
              ]),
            ]),
            _step(4, "What is recorded for each person", [
              for (int i = 0; i < _fields.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(switch (_fields[i]['type']) { 'number' => Icons.pin_rounded, 'text' => Icons.notes_rounded, 'choice' => Icons.list_rounded, _ => Icons.check_box_rounded }, color: AppPalette.fg(_kPurple)),
                  title: Text((_fields[i]['label'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${_fieldTypes[_fields[i]['type']] ?? ''}${(_fields[i]['options'] as List?)?.isNotEmpty == true ? ': ${(_fields[i]['options'] as List).join(', ')}' : ''}"),
                  trailing: IconButton(icon: const Icon(Icons.edit_rounded, size: 18), onPressed: () => _editField(i)),
                ),
              TextButton.icon(onPressed: () => _editField(), icon: const Icon(Icons.add_rounded), label: const Text("Add")),
            ]),
            _step(5, "Shared with", [
              if (_units.isEmpty) Text("Add the locations, departments, teams … that take part.", style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade600))),
              Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                for (final u in _units)
                  InputChip(
                    avatar: Icon(u['level'] == 'church_department' ? Icons.apartment_rounded : Icons.account_tree_rounded, size: 16),
                    label: Text("${u['label']}"),
                    tooltip: _levels[u['level']],
                    onDeleted: () => setState(() => _units.remove(u)),
                  ),
              ]),
              const SizedBox(height: 6),
              TextButton.icon(onPressed: _addUnit, icon: const Icon(Icons.add_rounded), label: const Text("Add a unit")),
            ]),
            _step(6, "Who enters the records", [
              Text("You can always enter. Pick the roles that also enter for their own unit (e.g. Cell Leader: the cell leaders of the units above).",
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.blueGrey.shade700))),
              const SizedBox(height: 8),
              if (_appRoles.isEmpty) const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              for (final lv in const ['Location', 'Sub-location', 'Department', 'Team', 'Cell'])
                if (_appRoles.any((r) => roleLevel(r) == lv)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text("$lv level", textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
                  ),
                  Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                    for (final r in _appRoles.where((r) => roleLevel(r) == lv))
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text((r['display_name'] ?? r['role_key']).toString(), style: const TextStyle(fontSize: 11.5)),
                        selected: _roles.contains(r['role_key']),
                        onSelected: (v) => setState(() => v ? _roles.add(r['role_key'].toString()) : _roles.remove(r['role_key'])),
                      ),
                  ]),
                ],
              const SizedBox(height: 6),
              Text(_roles.isEmpty ? "Only you will enter the records." : "${_roles.length} role${_roles.length == 1 ? '' : 's'} chosen",
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(_kPurple))),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One activity: enter, progress, details

class ActivityScreen extends StatefulWidget {
  final String activityId;
  const ActivityScreen({super.key, required this.activityId});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _db = Supabase.instance.client;
  Map<String, dynamic>? _a;
  List<Map<String, dynamic>> _units = [];
  final Set<String> _canEnter = {};
  String? _error;

  bool get _owner => _a?['owner_id'] == _db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await _db.from('special_activities').select().eq('id', widget.activityId).single();
      final u = await _db.from('special_activity_units').select().eq('activity_id', widget.activityId).order('label');
      final units = List<Map<String, dynamic>>.from(u);
      final can = await Future.wait([for (final x in units) _db.rpc('sa_can_enter', params: {'p_unit': x['id']}).then((v) => v == true, onError: (_) => false)]);
      if (!mounted) return;
      setState(() {
        _a = Map<String, dynamic>.from(a);
        _units = units;
        _canEnter
          ..clear()
          ..addAll([for (int i = 0; i < units.length; i++) if (can[i]) units[i]['id'].toString()]);
      });
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't open the activity: ${_err(e)}");
    }
  }

  Future<void> _ownerAction(String v) async {
    final a = _a!;
    if (v == 'edit') {
      final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ActivityEditor(activity: a, units: _units)));
      if (ok == true) _load();
    } else if (v == 'close' || v == 'open') {
      await _db.from('special_activities').update({'status': v == 'close' ? 'Closed' : 'Active'}).eq('id', a['id']);
      _load();
    } else if (v == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Delete \"${a['title']}\" and all its records?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Delete", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
          ],
        ),
      );
      if (ok != true) return;
      await _db.from('special_activities').delete().eq('id', a['id']);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(appBar: AppBar(), body: Center(child: Text(_error!)));
    final a = _a;
    if (a == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final tabs = <(String, IconData, Widget)>[
      if (_canEnter.isNotEmpty && a['status'] == 'Active')
        ("Enter", Icons.edit_note_rounded, _EnterTab(activity: a, units: _units.where((u) => _canEnter.contains(u['id'].toString())).toList())),
      ("Progress", Icons.insights_rounded, _ProgressTab(activity: a, units: _units)),
      ("Details", Icons.info_outline_rounded, _DetailsTab(activity: a, units: _units)),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
        appBar: AppBar(
          centerTitle: true,
          toolbarHeight: 58,
          foregroundColor: Colors.white,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppPalette.solid(activityColor(a['kind']?.toString())),
                AppPalette.solid(Color.lerp(activityColor(a['kind']?.toString()), Colors.black, 0.35)!),
              ]),
            ),
          ),
          title: Column(mainAxisSize: MainAxisSize.min, children: [
            Text((a['title'] ?? '').toString(), overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15.5, color: Colors.white)),
            Text("${a['kind'] ?? 'Special activity'} · ${a['start_date']}${a['end_date'] == null ? '' : ' – ${a['end_date']}'}",
                overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 10.5, color: Colors.white70)),
          ]),
          actions: [
            if (_owner)
              PopupMenuButton<String>(
                onSelected: _ownerAction,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text("Edit / share with more units")),
                  PopupMenuItem(value: a['status'] == 'Active' ? 'close' : 'open', child: Text(a['status'] == 'Active' ? "Close the activity" : "Open it again")),
                  const PopupMenuItem(value: 'delete', child: Text("Delete")),
                ],
              ),
          ],
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: const Color(0xFFFFD54F),
            dividerColor: Colors.transparent,
            tabs: [for (final t in tabs) Tab(height: 38, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(t.$2, size: 16), const SizedBox(width: 6), Text(t.$1)]))],
          ),
        ),
        body: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [for (final t in tabs) t.$3]),
      ),
    );
  }
}

class _EnterTab extends StatefulWidget {
  final Map<String, dynamic> activity;
  final List<Map<String, dynamic>> units;
  const _EnterTab({required this.activity, required this.units});
  @override
  State<_EnterTab> createState() => _EnterTabState();
}

class _EnterTabState extends State<_EnterTab> {
  final _db = Supabase.instance.client;
  late Map<String, dynamic> _unit = widget.units.first;
  late DateTime _date;
  List<Map<String, dynamic>> _people = [];
  final Map<String, Map<String, dynamic>> _vals = {};
  final Set<String> _had = {};
  final Map<String, TextEditingController> _ctl = {};
  bool _loading = true, _saving = false;
  int _changes = 0;
  String _q = '';

  List<Map<String, dynamic>> get _fields => List<Map<String, dynamic>>.from(((widget.activity['fields'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));

  @override
  void initState() {
    super.initState();
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final s = activitySessions(widget.activity, until: today);
    _date = s.isEmpty ? (DateTime.tryParse(widget.activity['start_date'].toString()) ?? today) : s.last;
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
      final p = await _db.rpc('sa_people', params: {'p_unit': _unit['id']});
      final r = await _db.from('special_activity_records').select().eq('activity_id', widget.activity['id']).eq('unit_id', _unit['id']).eq('session_date', _f.format(_date));
      _vals.clear();
      _had.clear();
      for (final c in _ctl.values) {
        c.dispose();
      }
      _ctl.clear();
      for (final x in r) {
        _had.add(x['person_id'].toString());
        _vals[x['person_id'].toString()] = Map<String, dynamic>.from((x['vals'] as Map?) ?? const {});
      }
      if (!mounted) return;
      setState(() {
        _people = List<Map<String, dynamic>>.from(p as List);
        _loading = false;
        _changes = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load: ${_err(e)}")));
    }
  }

  void _set(String id, String k, dynamic v) => setState(() {
        final m = _vals.putIfAbsent(id, () => {});
        if (v == null || (v is String && v.trim().isEmpty)) {
          m.remove(k);
        } else {
          m[k] = v;
        }
        _changes++;
      });

  Future<void> _save() async {
    setState(() => _saving = true);
    final now = DateTime.now().toUtc().toIso8601String();
    final up = <Map<String, dynamic>>[];
    final del = <String>[];
    for (final p in _people) {
      final id = p['id'].toString();
      final v = _vals[id] ?? const {};
      if (v.isEmpty) {
        if (_had.contains(id)) del.add(id);
        continue;
      }
      up.add({
        'activity_id': widget.activity['id'],
        'unit_id': _unit['id'],
        'person_id': id,
        'person_kind': p['kind'],
        'person_name': p['name'],
        'session_date': _f.format(_date),
        'vals': v,
        'updated_at': now,
      });
    }
    try {
      for (int i = 0; i < up.length; i += 200) {
        await _db.from('special_activity_records').upsert(up.sublist(i, (i + 200).clamp(0, up.length)), onConflict: 'activity_id,person_id,session_date');
      }
      if (del.isNotEmpty) {
        await _db.from('special_activity_records').delete().eq('activity_id', widget.activity['id']).eq('session_date', _f.format(_date)).inFilter('person_id', del);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved ${up.length} record${up.length == 1 ? '' : 's'}"), backgroundColor: Colors.green.shade700));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: ${_err(e)}")));
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _cell(Map p, Map<String, dynamic> f) {
    final id = p['id'].toString();
    final k = f['key'].toString();
    final v = _vals[id]?[k];
    switch (f['type']) {
      case 'yesno':
        // two small pills that fit the low rows
        return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final o in const ['Yes', 'No'])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _set(id, k, v == o ? null : o),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 19,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppPalette.bg(v == o ? (o == 'Yes' ? Colors.green.shade600 : Colors.red.shade600) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppPalette.line(Colors.black12)),
                  ),
                  child: Text(o, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: v == o ? Colors.white : AppPalette.fg(Colors.grey.shade700))),
                ),
              ),
            ),
        ]);
      case 'choice':
        final opts = List<String>.from((f['options'] as List?) ?? const []);
        return DropdownButton<String>(
          value: opts.contains(v) ? v as String : null,
          isExpanded: true,
          isDense: true,
          iconSize: 16,
          style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.black87)),
          underline: const SizedBox(),
          alignment: Alignment.center,
          hint: const Text("—", textAlign: TextAlign.center),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text("—")),
            for (final o in opts) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (x) => _set(id, k, x),
        );
      default:
        final number = f['type'] == 'number';
        final c = _ctl.putIfAbsent('$id|$k', () => TextEditingController(text: (v ?? '').toString()));
        return TextField(
          controller: c,
          textAlign: TextAlign.center,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
          style: GoogleFonts.merriweather(fontSize: 11),
          decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 4)),
          onChanged: (x) => _set(id, k, number ? num.tryParse(x) : x),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = _fields;
    final q = _q.toLowerCase();
    final list = _people.where((p) => q.isEmpty || "${p['name']} ${p['team']} ${p['cell_group']}".toLowerCase().contains(q)).toList();
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final sessions = activitySessions(widget.activity, until: today);
    final cols = <(String, double)>[
      ("Name", 180.0),
      ("Unit", 150.0),
      for (final f in fields) ((f['label'] ?? '').toString(), f['type'] == 'yesno' ? 140.0 : (f['type'] == 'text' ? 200.0 : 130.0)),
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: [
          if (widget.units.length > 1)
            DropdownButton<String>(
              value: _unit['id'].toString(),
              items: [for (final u in widget.units) DropdownMenuItem(value: u['id'].toString(), child: Text((u['label'] ?? '').toString()))],
              onChanged: (v) {
                _unit = widget.units.firstWhere((u) => u['id'].toString() == v);
                _load();
              },
            )
          else
            Chip(avatar: const Icon(Icons.account_tree_rounded, size: 16), label: Text((_unit['label'] ?? '').toString())),
          ActionChip(
            avatar: const Icon(Icons.event_rounded, size: 16),
            label: Text("Session: ${DateFormat('EEE d MMM yyyy').format(_date)}"),
            onPressed: sessions.length <= 1
                ? null
                : () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: sessions.first,
                      lastDate: sessions.last,
                      selectableDayPredicate: (x) => sessions.any((s) => DateUtils.isSameDay(s, x)),
                    );
                    if (d != null) {
                      _date = d;
                      _load();
                    }
                  },
          ),
          SizedBox(
            width: 200,
            height: 34,
            child: TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 17), hintText: tr("Search name"), isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 6), border: const OutlineInputBorder()),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Text("${list.length}", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
          FilledButton.icon(
            onPressed: _changes == 0 || _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded, size: 18),
            label: Text(_changes == 0 ? "Saved" : "Save"),
          ),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : list.isEmpty
                ? Center(child: Text("Nobody to track in this unit.", style: TextStyle(color: AppPalette.fg(Colors.grey))))
                : FrozenGrid(
                    key: ValueKey('${_unit['id']}|${_f.format(_date)}|$_q'),
                    columns: cols,
                    rows: list.length,
                    rowHeight: 24,
                    textOf: (r, c) {
                      final p = list[r];
                      if (c == 0) return (p['name'] ?? '').toString();
                      if (c == 1) return [p['team'], p['cell_group']].where((x) => (x ?? '').toString().isNotEmpty).join(' › ');
                      return (_vals[p['id'].toString()]?[fields[c - 2]['key']] ?? '').toString();
                    },
                    cell: (r, c) {
                      final p = list[r];
                      if (c == 0) return Text((p['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold));
                      if (c == 1) {
                        return Text([p['team'], p['cell_group']].where((x) => (x ?? '').toString().isNotEmpty).join(' › '), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11));
                      }
                      return _cell(p, fields[c - 2]);
                    },
                  ),
      ),
    ]);
  }
}

class _ProgressTab extends StatefulWidget {
  final Map<String, dynamic> activity;
  final List<Map<String, dynamic>> units;
  const _ProgressTab({required this.activity, required this.units});
  @override
  State<_ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<_ProgressTab> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _recs = [];
  Map<String, int> _people = {};
  bool _loading = true;
  String? _error;
  int _metric = -1; // -1 = completion, else the field index

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final recs = <Map<String, dynamic>>[];
      for (int from = 0;; from += 1000) {
        final page = await _db.from('special_activity_records').select('unit_id, person_id, session_date, vals').eq('activity_id', widget.activity['id']).order('id').range(from, from + 999);
        recs.addAll(List<Map<String, dynamic>>.from(page));
        if (page.length < 1000) break;
      }
      final c = await _db.rpc('sa_unit_counts', params: {'p_activity': widget.activity['id']});
      if (!mounted) return;
      setState(() {
        _recs = recs;
        _people = {for (final x in (c as List)) x['unit_id'].toString(): ((x['people'] ?? 0) as num).toInt()};
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load: ${_err(e)}";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final fields = List<Map<String, dynamic>>.from(((widget.activity['fields'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final sessions = activitySessions(widget.activity, until: today).length;
    final units = widget.units.where((u) => _people.containsKey(u['id'].toString())).toList();
    String summary(Map<String, dynamic> f, List<Map<String, dynamic>> rs) {
      final vals = rs.map((r) => ((r['vals'] as Map?) ?? const {})[f['key']]).where((v) => v != null && v.toString().isNotEmpty).toList();
      if (vals.isEmpty) return '–';
      switch (f['type']) {
        case 'yesno':
          return "${(vals.where((v) => v == 'Yes').length * 100 / vals.length).toStringAsFixed(0)}% yes";
        case 'number':
          final n = vals.map((v) => num.tryParse(v.toString()) ?? 0);
          return "avg ${(n.fold<num>(0, (a, b) => a + b) / vals.length).toStringAsFixed(1)}";
        case 'choice':
          final c = <String, int>{};
          for (final v in vals) {
            c.update(v.toString(), (x) => x + 1, ifAbsent: () => 1);
          }
          final top = c.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          return top.take(2).map((e) => "${e.key} ${e.value}").join(', ');
        default:
          return "${vals.length} filled";
      }
    }

    double value(Map<String, dynamic>? f, List<Map<String, dynamic>> rs, int people) {
      if (f == null) return people * sessions == 0 ? 0 : (rs.length * 100 / (people * sessions)).clamp(0, 100).toDouble();
      final vals = rs.map((r) => ((r['vals'] as Map?) ?? const {})[f['key']]).where((v) => v != null && v.toString().isNotEmpty).toList();
      if (vals.isEmpty) return 0;
      if (f['type'] == 'yesno') return vals.where((v) => v == 'Yes').length * 100 / vals.length;
      if (f['type'] == 'number') return vals.map((v) => num.tryParse(v.toString()) ?? 0).fold<num>(0, (a, b) => a + b) / vals.length;
      return vals.length.toDouble();
    }

    final headers = ["Unit", "People", "Sessions", "Records", "Completion", for (final f in fields) (f['label'] ?? '').toString()];
    List<String> row(String label, List<Map<String, dynamic>> rs, int people) => [
          label,
          '$people',
          '${{for (final r in rs) r['session_date']}.length} of $sessions',
          '${rs.length}',
          people * sessions == 0 ? '–' : "${(rs.length * 100 / (people * sessions)).clamp(0, 100).toStringAsFixed(0)}%",
          for (final f in fields) summary(f, rs),
        ];
    final byUnit = {for (final u in units) u['id'].toString(): _recs.where((r) => r['unit_id'].toString() == u['id'].toString()).toList()};
    final rows = [
      row("All units", _recs, _people.values.fold(0, (a, b) => a + b)),
      for (final u in units) row((u['label'] ?? '').toString(), byUnit[u['id'].toString()]!, _people[u['id'].toString()] ?? 0),
    ];
    final metricField = _metric < 0 || _metric >= fields.length ? null : fields[_metric];
    final values = [for (final u in units) value(metricField, byUnit[u['id'].toString()]!, _people[u['id'].toString()] ?? 0)];
    final isPct = metricField == null || metricField['type'] == 'yesno';
    final maxV = values.fold<double>(0, (a, b) => b > a ? b : a);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        Row(children: [
          Expanded(child: Text("Units compared", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: AppPalette.fg(_kPurple)))),
          IconButton(
            tooltip: tr('Excel / PDF / Print'),
            icon: Icon(Icons.download_rounded, color: AppPalette.fg(_kPurple)),
            onPressed: () => TableExport.showMenu(context, () => ExportTable(title: (widget.activity['title'] ?? 'Special activity').toString(), subtitle: "Progress by unit", headers: headers, rows: rows)),
          ),
        ]),
        // filters on every column, columns can be hidden
        SizedBox(
          height: (rows.length * 24.0 + 70).clamp(120.0, 520.0),
          child: FrozenGrid(
            columns: [for (final h in headers) (h, h == "Unit" ? 170.0 : 110.0)],
            rows: rows.length,
            rowHeight: 24,
            boldRows: const {0},
            textOf: (r, c) => rows[r][c],
            cell: (r, c) => Text(rows[r][c], maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, fontWeight: r == 0 || c == 0 ? FontWeight.bold : FontWeight.normal)),
          ),
        ),
        if (units.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            ChoiceChip(label: const Text("Completion %"), selected: _metric < 0, onSelected: (_) => setState(() => _metric = -1)),
            for (int i = 0; i < fields.length; i++)
              if (fields[i]['type'] == 'yesno' || fields[i]['type'] == 'number')
                ChoiceChip(label: Text((fields[i]['label'] ?? '').toString()), selected: _metric == i, onSelected: (_) => setState(() => _metric = i)),
          ]),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, box) {
            final w = (units.length * 90.0).clamp(box.maxWidth, 4000.0);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: w,
                height: 260,
                child: Padding(
                  padding: const EdgeInsets.only(top: 22, right: 8),
                  child: BarChart(BarChartData(
                    minY: 0,
                    maxY: isPct ? 100 : (maxV <= 0 ? 1 : maxV * 1.2),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(
                      enabled: false,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => Colors.transparent,
                        tooltipPadding: EdgeInsets.zero,
                        tooltipMargin: 2,
                        getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                          isPct ? "${values[g.x].toStringAsFixed(0)}%" : values[g.x].toStringAsFixed(1),
                          TextStyle(color: AppPalette.fg(_kPurple), fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (x, m) => Text(isPct ? "${x.toInt()}%" : x.toStringAsFixed(0), style: const TextStyle(fontSize: 9.5)))),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 34,
                          getTitlesWidget: (x, m) {
                            final i = x.toInt();
                            if (i < 0 || i >= units.length) return const SizedBox();
                            return SideTitleWidget(
                              meta: m,
                              space: 4,
                              child: SizedBox(width: 82, child: Text((units[i]['label'] ?? '').toString().split(' › ').last, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600))),
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
    );
  }
}

class _DetailsTab extends StatelessWidget {
  final Map<String, dynamic> activity;
  final List<Map<String, dynamic>> units;
  const _DetailsTab({required this.activity, required this.units});

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final sch = Map<String, dynamic>.from((a['schedule'] as Map?) ?? const {});
    final days = List.from((sch['days'] as List?) ?? const []).map((d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][(d as num).toInt() - 1]).join(', ');
    final fields = List<Map<String, dynamic>>.from(((a['fields'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    Widget kv(String k, String v) => v.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 140, child: Text(k, style: TextStyle(color: AppPalette.fg(Colors.blueGrey.shade600)))),
              Expanded(child: SelectableText(v, style: GoogleFonts.merriweather(fontWeight: FontWeight.w600))),
            ]),
          );
    return ListView(padding: const EdgeInsets.all(16), children: [
      Icon(activityIcon(a['kind']?.toString()), size: 44, color: AppPalette.fg(activityColor(a['kind']?.toString()))),
      const SizedBox(height: 6),
      Text((a['title'] ?? '').toString(), textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      if ((a['description'] ?? '').toString().isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: SelectableText(a['description'].toString(), textAlign: TextAlign.center, style: GoogleFonts.merriweather(height: 1.5))),
      kv("Kind", (a['kind'] ?? '').toString()),
      kv("Dates", "${a['start_date']}${a['end_date'] == null ? '' : ' – ${a['end_date']}'}"),
      kv("Meets", switch (sch['mode']) { 'daily' => 'Every day', 'days' => days, _ => 'Once' }),
      kv("Sessions", "${activitySessions(a).length}"),
      kv("Who is tracked", _subjects[a['subjects']] ?? ''),
      kv("Recorded", fields.map((f) => "${f['label']} (${_fieldTypes[f['type']] ?? ''})").join(', ')),
      kv("Entered by", List.from((a['entry_roles'] as List?) ?? const []).isEmpty
          ? (_entryModes[a['entry_mode']] ?? '')
          : "The creator, and in each unit: ${List.from(a['entry_roles'] as List).map((r) => r.toString().replaceAll('_', ' ')).join(', ')}"),
      kv("Created by", (a['owner_name'] ?? '').toString()),
      kv("Status", (a['status'] ?? '').toString()),
      const SizedBox(height: 8),
      Text("Shared with", textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
      const SizedBox(height: 6),
      Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
        for (final u in units) Chip(avatar: Icon(u['level'] == 'church_department' ? Icons.apartment_rounded : Icons.account_tree_rounded, size: 16), label: Text((u['label'] ?? '').toString())),
      ]),
    ]);
  }
}