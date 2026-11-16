import 'package:flutter/material.dart' hide Text;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/i18n.dart';

/// The unit of a secondary role, when it sits in another department of the
/// same sub-location (a Theology worker who is also a 장년회 cell leader).
/// Picks Department › Team › Cell group; [depth] = 1 (department), 2 (team)
/// or 3 (cell group). Calls [onChanged] with the picks (null = not chosen).
class SecondaryUnitPicker extends StatefulWidget {
  final String location;
  final String subLocation;
  final int depth;
  final String? department, team, cell;
  final void Function(String? department, String? team, String? cell) onChanged;

  const SecondaryUnitPicker({
    super.key,
    required this.location,
    required this.subLocation,
    required this.depth,
    required this.onChanged,
    this.department,
    this.team,
    this.cell,
  });

  @override
  State<SecondaryUnitPicker> createState() => _SecondaryUnitPickerState();
}

class _SecondaryUnitPickerState extends State<SecondaryUnitPicker> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _depts = [], _teams = [];
  List<String> _cells = [];
  late String? _d = widget.department, _t = widget.team, _c = widget.cell;
  bool _loading = true;

  static String _n(Object? s) => (s ?? '').toString().trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _loadDepts();
  }

  @override
  void didUpdateWidget(covariant SecondaryUnitPicker old) {
    super.didUpdateWidget(old);
    if (old.location != widget.location || old.subLocation != widget.subLocation) {
      _d = _t = _c = null;
      _loadDepts();
    }
  }

  Future<void> _loadDepts() async {
    setState(() => _loading = true);
    try {
      final loc = await _db.from('locations').select('id, location');
      final l = List<Map<String, dynamic>>.from(loc).firstWhere((e) => _n(e['location']) == _n(widget.location), orElse: () => {});
      if (l.isEmpty) throw Exception('location');
      final subs = await _db.from('sub_locations').select('id, name').eq('location_id', l['id']);
      final s = List<Map<String, dynamic>>.from(subs).firstWhere((e) => _n(e['name']) == _n(widget.subLocation), orElse: () => {});
      if (s.isEmpty) throw Exception('sub-location');
      _depts = List<Map<String, dynamic>>.from(await _db.from('departments').select('id, name').eq('sub_location_id', s['id']));
      if (_d != null) await _loadTeams(keep: true);
    } catch (_) {
      _depts = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadTeams({bool keep = false}) async {
    final d = _depts.firstWhere((e) => _n(e['name']) == _n(_d), orElse: () => {});
    _teams = d.isEmpty ? [] : List<Map<String, dynamic>>.from(await _db.from('teams').select('id, name').eq('dept_id', d['id']));
    if (!keep) _t = _c = null;
    if (keep && _t != null) await _loadCells(keep: true);
    if (mounted) setState(() {});
  }

  Future<void> _loadCells({bool keep = false}) async {
    final t = _teams.firstWhere((e) => _n(e['name']) == _n(_t), orElse: () => {});
    _cells = t.isEmpty ? [] : List<String>.from((await _db.from('cell_groups').select('name').eq('team_id', t['id'])).map((e) => e['name'].toString()));
    if (!keep) _c = null;
    if (mounted) setState(() {});
  }

  void _emit() => widget.onChanged(_d, widget.depth >= 2 ? _t : null, widget.depth >= 3 ? _c : null);

  Widget _drop(String label, List<String> items, String? value, ValueChanged<String?>? onChanged) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label|${items.length}|$value'),
          initialValue: items.contains(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr(label), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))), isDense: true),
          items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))],
          onChanged: onChanged,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 2));
    if (_depts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text("Choose the location and sub-location first.", style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _drop("Department of the secondary role", [for (final d in _depts) d['name'].toString()], _d, (v) {
        _d = v;
        _emit();
        _loadTeams();
      }),
      if (widget.depth >= 2)
        _drop("Team of the secondary role", [for (final t in _teams) t['name'].toString()], _t, _d == null
            ? null
            : (v) {
                _t = v;
                _emit();
                _loadCells();
              }),
      if (widget.depth >= 3)
        _drop("Cell group of the secondary role", _cells, _c, _t == null
            ? null
            : (v) {
                setState(() => _c = v);
                _emit();
              }),
    ]);
  }
}
