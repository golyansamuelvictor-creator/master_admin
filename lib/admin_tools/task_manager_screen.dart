// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:master_admin/core/app_palette.dart';

/// Accountability tasks.
///  - Everyone: "My tasks" — only the tasks for their own role and unit
///    (accountability_tasks, 17_round16.sql), plus leader tasks assigned to them.
///  - Administration Department (and administrators): upload tasks for roles,
///    departments and units with a form, and follow how far each task is.
class TaskManagerScreen extends StatefulWidget {
  const TaskManagerScreen({super.key});
  @override
  State<TaskManagerScreen> createState() => _TaskManagerScreenState();
}

class _TaskManagerScreenState extends State<TaskManagerScreen> {
  final _supabase = Supabase.instance.client;
  static const pPurple = Color(0xFF4A148C);
  bool _isLoading = true;
  bool _canUpload = false;
  String? _error;
  List<Map<String, dynamic>> _mine = [];
  List<dynamic> _tasks = []; // leader tasks (earlier feature)
  List<Map<String, dynamic>> _uploaded = [];
  List<Map<String, dynamic>> _roles = [];

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  // ==========================================
  // DATA
  // ==========================================
  Future<void> _fetchTasks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final r = await Future.wait<dynamic>([
        _supabase.rpc('my_accountability_tasks'),
        _supabase.rpc('can_upload_tasks').then<dynamic>((v) => v, onError: (_) => false),
      ]);
      _mine = List<Map<String, dynamic>>.from((r[0] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      _canUpload = r[1] == true;
      if (_canUpload) {
        final p = await _supabase.rpc('accountability_task_progress');
        _uploaded = List<Map<String, dynamic>>.from((p as List).map((e) => Map<String, dynamic>.from(e as Map)));
        if (_roles.isEmpty) await _loadRoles();
      }
    } catch (e) {
      debugPrint("Accountability tasks: $e");
      _error = "Couldn't load the accountability tasks. Ask the administrator to run 17_round16.sql.";
    }
    // leader tasks assigned to me (kept from the earlier version)
    try {
      final me = _supabase.auth.currentUser?.id;
      final res = await _supabase.from('leader_tasks').select('*, assigned_to:profiles(full_name, role)').eq('assigned_to', me ?? '').order('due_date');
      _tasks = res as List;
    } catch (_) {
      _tasks = [];
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _setStatus(Map<String, dynamic> t, String status) async {
    String? note;
    if (status == 'Completed') {
      final c = TextEditingController(text: (t['note'] ?? '').toString());
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Mark as done"),
          content: TextField(controller: c, maxLines: 3, decoration: InputDecoration(labelText: tr("What was done (optional)"), border: const OutlineInputBorder())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Done")),
          ],
        ),
      );
      if (ok != true) return;
      note = c.text.trim();
    }
    try {
      await _supabase.rpc('set_my_task_status', params: {'p_task': t['id'], 'p_status': status, 'p_note': note});
      _fetchTasks();
    } catch (e) {
      _snack("Couldn't update: ${e is PostgrestException ? e.message : e}", error: true);
    }
  }

  Future<void> _updateTaskStatus(String id, String newStatus) async {
    await _supabase.from('leader_tasks').update({'status': newStatus}).eq('id', id);
    _fetchTasks();
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700));
  }

  // ==========================================
  // UI
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final tabs = [Tab(text: tr("My tasks")), if (_canUpload) Tab(text: tr("Uploaded tasks"))];
    return DefaultTabController(
      key: ValueKey(_canUpload),
      length: tabs.length,
      child: Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
        appBar: AppBar(
          title: Text("Accountability Tasks", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple), fontSize: 18)),
          centerTitle: true,
          elevation: 0.5,
          backgroundColor: AppPalette.bg(Colors.white),
          actions: [IconButton(tooltip: tr("Reload"), icon: const Icon(Icons.refresh_rounded), onPressed: _fetchTasks)],
          bottom: tabs.length > 1 ? TabBar(tabs: tabs, labelColor: AppPalette.fg(pPurple), indicatorColor: pPurple) : null,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                _myTasks(),
                if (_canUpload) _uploadedTasks(),
              ]),
        floatingActionButton: _canUpload
            ? FloatingActionButton.extended(
                backgroundColor: AppPalette.bg(pPurple),
                onPressed: _showCreateTaskDialog,
                icon: Icon(Icons.upload_file_rounded, color: AppPalette.fg(Colors.white)),
                label: Text("Upload tasks", style: TextStyle(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold)),
              )
            : null,
      ),
    );
  }

  Widget _centered(Widget child) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: child));

  Widget _myTasks() {
    if (_error != null && _mine.isEmpty && _tasks.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    }
    if (_mine.isEmpty && _tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text("No tasks for your role and unit right now.", textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey))),
        ),
      );
    }
    final done = _mine.where((t) => t['status'] == 'Completed').length;
    return _centered(RefreshIndicator(
      onRefresh: _fetchTasks,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 90), children: [
        if (_mine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(children: [
              Text("$done of ${_mine.length} done", textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple))),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: _mine.isEmpty ? 0 : done / _mine.length, minHeight: 8, color: Colors.green.shade600, backgroundColor: Colors.grey.shade200),
              ),
            ]),
          ),
        for (final t in _mine) _myTaskCard(t),
        for (final t in _tasks) _buildTaskCard(t),
      ]),
    ));
  }

  Color _statusColor(String s) => s == 'Completed' ? Colors.green : s == 'In Progress' ? Colors.blue : Colors.orange;

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: AppPalette.bg(c.withValues(alpha: 0.1)), borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(color: AppPalette.fg(c), fontWeight: FontWeight.bold, fontSize: 10.5)),
      );

  Widget _myTaskCard(Map<String, dynamic> t) {
    final status = (t['status'] ?? 'Pending').toString();
    final due = DateTime.tryParse((t['due_date'] ?? '').toString());
    final late = due != null && status != 'Completed' && due.isBefore(DateTime.now().subtract(const Duration(days: 1)));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            _chip(status, _statusColor(status)),
            if ((t['frequency'] ?? 'once') != 'once') _chip(t['frequency'].toString()[0].toUpperCase() + t['frequency'].toString().substring(1), Colors.purple),
            if ((t['duty_name'] ?? '').toString().isNotEmpty) _chip(t['duty_name'].toString(), Colors.blueGrey),
            if (due != null) _chip("Due ${DateFormat('d MMM yyyy').format(due)}", late ? Colors.red : Colors.grey.shade700),
          ]),
          const SizedBox(height: 10),
          Text((t['title'] ?? '').toString(), style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 15)),
          if ((t['description'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(t['description'].toString(), style: TextStyle(fontSize: 13, color: AppPalette.fg(Colors.black54))),
          ],
          if ((t['note'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text("My note: ${t['note']}", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppPalette.fg(Colors.blueGrey.shade700))),
          ],
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.end, spacing: 6, children: [
            if (status == 'Pending') TextButton(onPressed: () => _setStatus(t, 'In Progress'), child: const Text("Start")),
            if (status != 'Completed')
              ElevatedButton.icon(
                onPressed: () => _setStatus(t, 'Completed'),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text("Mark done"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
              )
            else
              TextButton(onPressed: () => _setStatus(t, 'Pending'), child: const Text("Not done yet")),
          ]),
        ]),
      ),
    );
  }

  Widget _buildTaskCard(dynamic task) {
    String status = (task['status'] ?? 'Pending').toString();
    Color statusColor = _statusColor(status);
    final due = DateTime.tryParse((task['due_date'] ?? '').toString());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _chip(status, statusColor),
            if (due != null) Flexible(child: Text("Due: ${DateFormat('dd MMM').format(due)}", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey)))),
          ]),
          const SizedBox(height: 12),
          Text((task['title'] ?? '').toString(), style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 5),
          Text(task['description'] ?? "No description provided.", style: TextStyle(fontSize: 13, color: AppPalette.fg(Colors.black54))),
          const Divider(height: 24),
          Row(children: [
            Icon(Icons.person_outline, size: 14, color: AppPalette.fg(Colors.blueGrey)),
            const SizedBox(width: 8),
            Flexible(child: Text("Leader task: ${task['assigned_to']?['full_name'] ?? ''}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
            const Spacer(),
            if (status != 'Completed')
              TextButton(
                onPressed: () => _updateTaskStatus(task['id'].toString(), 'Completed'),
                child: const Text("Mark done", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
          ]),
        ]),
      ),
    );
  }

  String _roleName(String key) {
    final r = _roles.firstWhere((x) => x['role_key'] == key, orElse: () => const {});
    return (r['display_name'] ?? key).toString();
  }

  Widget _uploadedTasks() {
    if (_uploaded.isEmpty) {
      return Center(child: Text("No tasks uploaded yet. Use \"Upload tasks\".", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey))));
    }
    return _centered(ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 90), children: [
      for (final t in _uploaded)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text((t['title'] ?? '').toString(), style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 14))),
                Switch(
                  value: t['is_active'] == true,
                  onChanged: (v) async {
                    await _supabase.from('accountability_tasks').update({'is_active': v}).eq('id', t['id']);
                    _fetchTasks();
                  },
                ),
                IconButton(
                  tooltip: tr("Delete"),
                  icon: Icon(Icons.delete_outline_rounded, color: AppPalette.fg(Colors.red.shade700)),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("Delete this task?"),
                        content: Text((t['title'] ?? '').toString()),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete")),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await _supabase.from('accountability_tasks').delete().eq('id', t['id']);
                      _fetchTasks();
                    }
                  },
                ),
              ]),
              Text(
                [
                  (t['target_roles'] as List?)?.isNotEmpty == true ? (t['target_roles'] as List).map((k) => _roleName(k.toString())).join(', ') : 'Everyone',
                  if ((t['location'] ?? '').toString().isNotEmpty) t['location'],
                  if ((t['department'] ?? '').toString().isNotEmpty) t['department'],
                  t['frequency'],
                  if (t['due_date'] != null) "due ${t['due_date']}",
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.blueGrey.shade700)),
              ),
              const SizedBox(height: 8),
              () {
                final a = (t['assigned'] as num?)?.toInt() ?? 0;
                final c = (t['completed'] as num?)?.toInt() ?? 0;
                return Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: a == 0 ? 0 : c / a, minHeight: 7, color: Colors.green.shade600, backgroundColor: Colors.grey.shade200),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text("$c of $a done · ${t['in_progress'] ?? 0} in progress", style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                ]);
              }(),
            ]),
          ),
        ),
    ]));
  }

  Future<void> _loadRoles() async {
    try {
      final r = await _supabase.from('app_roles').select('role_key, display_name, category').order('display_name');
      if (mounted) setState(() => _roles = List<Map<String, dynamic>>.from(r));
    } catch (_) {}
  }

  // ==========================================
  // UPLOAD FORM
  // ==========================================
  Future<void> _showCreateTaskDialog() async {
    if (_roles.isEmpty) await _loadRoles();
    if (!mounted) return;
    final titles = TextEditingController();
    final desc = TextEditingController();
    // Location and department lists from the database (not typed here):
    // locations; the location departments (Men's, Women's, Young Adults …,
    // from the departments table); the 24 church departments.
    const church = 'Church';
    List<String> locs = [], locDepts = [], churchDepts = [];
    try {
      final r = await Future.wait<dynamic>([
        _supabase.from('locations').select('location').order('location'),
        _supabase.from('departments').select('name'),
        _supabase.from('official_departments').select('name, parent_id').order('name'),
      ]);
      locs = {for (final x in r[0] as List) (x['location'] ?? '').toString().trim()}.where((x) => x.isNotEmpty && x.toLowerCase() != 'church').toList();
      locDepts = ({for (final x in r[1] as List) (x['name'] ?? '').toString().trim()}..remove('')).toList()..sort();
      churchDepts = [for (final x in r[2] as List) if (x['parent_id'] == null) (x['name'] ?? '').toString().trim()]..removeWhere((x) => x.isEmpty);
    } catch (_) {}
    if (!mounted) return;
    String? loc; // null = every location
    String? dept; // null = every department
    final duty = TextEditingController();
    final picked = <String>{};
    String freq = 'once';
    DateTime? due = DateTime.now().add(const Duration(days: 7));
    String roleSearch = '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final shown = _roles.where((r) => roleSearch.isEmpty || '${r['display_name']} ${r['role_key']}'.toLowerCase().contains(roleSearch.toLowerCase())).toList();
        return AlertDialog(
          title: Text("Upload accountability tasks", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16)),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: titles,
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(labelText: tr("Task(s) — one per line"), hintText: tr("Each line becomes its own task"), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(controller: desc, maxLines: 3, decoration: InputDecoration(labelText: tr("Details (optional)"), border: const OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: duty, decoration: InputDecoration(labelText: tr("Duty (optional)"), hintText: tr("e.g. Service Attendance Status"), border: const OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 12),
                Text("For which roles? (none picked = everyone)", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 12.5)),
                const SizedBox(height: 6),
                TextField(
                  onChanged: (v) => set(() => roleSearch = v),
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: tr("Find a role"), isDense: true, border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 170,
                  decoration: BoxDecoration(border: Border.all(color: AppPalette.line(Colors.grey.shade300)), borderRadius: BorderRadius.circular(8)),
                  child: ListView(children: [
                    for (final r in shown)
                      CheckboxListTile(
                        dense: true,
                        value: picked.contains(r['role_key']),
                        title: Text((r['display_name'] ?? r['role_key']).toString(), style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text(r['role_key'].toString(), style: const TextStyle(fontSize: 10.5)),
                        onChanged: (v) => set(() => v == true ? picked.add(r['role_key'].toString()) : picked.remove(r['role_key'])),
                      ),
                  ]),
                ),
                if (picked.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text("${picked.length} role(s) picked", style: TextStyle(fontSize: 11.5, color: AppPalette.fg(pPurple)))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: loc ?? '',
                      decoration: InputDecoration(labelText: tr("Location"), border: const OutlineInputBorder(), isDense: true),
                      items: [
                        const DropdownMenuItem(value: '', child: Text("All locations")),
                        const DropdownMenuItem(value: church, child: Text("Church (24 departments)")),
                        for (final l in locs) DropdownMenuItem(value: l, child: Text(l, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => set(() {
                        loc = (v ?? '').isEmpty ? null : v;
                        dept = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('dept-$loc'),
                      isExpanded: true,
                      initialValue: dept ?? '',
                      decoration: InputDecoration(labelText: tr("Department"), border: const OutlineInputBorder(), isDense: true),
                      items: [
                        const DropdownMenuItem(value: '', child: Text("All departments")),
                        for (final d in (loc == church ? churchDepts : locDepts)) DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => set(() => dept = (v ?? '').isEmpty ? null : v),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: freq,
                      decoration: InputDecoration(labelText: tr("How often"), border: const OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'once', child: Text("Once")),
                        DropdownMenuItem(value: 'daily', child: Text("Daily")),
                        DropdownMenuItem(value: 'weekly', child: Text("Weekly")),
                        DropdownMenuItem(value: 'monthly', child: Text("Monthly")),
                      ],
                      onChanged: (v) => set(() => freq = v ?? 'once'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text(due == null ? "No due date" : DateFormat('d MMM yyyy').format(due!)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: () async {
                        final d = await showDatePicker(context: ctx, initialDate: due ?? DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2035));
                        set(() => due = d);
                      },
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Upload & send")),
          ],
        );
      }),
    );
    if (ok != true) return;
    final lines = titles.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return;
    try {
      await _supabase.from('accountability_tasks').insert([
        for (final l in lines)
          {
            'title': l,
            'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
            'duty_name': duty.text.trim().isEmpty ? null : duty.text.trim(),
            'target_roles': picked.toList(),
            'location': loc,
            'department': dept,
            'frequency': freq,
            'due_date': due == null ? null : DateFormat('yyyy-MM-dd').format(due!),
          },
      ]);
      _snack("${lines.length} task(s) uploaded and sent to the people they are for.");
      _fetchTasks();
    } catch (e) {
      _snack("Couldn't upload: ${e is PostgrestException ? e.message : e}", error: true);
    }
  }
}
