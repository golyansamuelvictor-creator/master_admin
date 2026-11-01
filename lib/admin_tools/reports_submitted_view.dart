import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/compilation_rules.dart';
import '../core/i18n.dart';

/// Approval Cockpit › Reports submitted.
///
/// The leader's units one level down, for the chosen period: which reported
/// and which did not, who submitted, and (for teams and cells) how many of
/// the units below reported. Tap a unit to open the units inside it (a
/// department → its teams → their cell groups). The leader never sees
/// outside their own area (reports_submitted, 18_round17.sql).
class ReportsSubmittedView extends StatefulWidget {
  final String table; // the duty's log table
  const ReportsSubmittedView({super.key, required this.table});

  @override
  State<ReportsSubmittedView> createState() => _ReportsSubmittedViewState();
}

class _ReportsSubmittedViewState extends State<ReportsSubmittedView> {
  static const _purple = Color(0xFF4A148C);
  static const _levelNames = {
    'location': 'Locations',
    'sub_location': 'Sub-locations',
    'department': 'Departments',
    'team': 'Teams',
    'cell_group': 'Cell groups',
  };
  static const _cols = ['location', 'sub_location', 'department', 'team', 'cell_group'];

  String _period = 'This week';
  final List<MapEntry<String, String>> _focus = []; // opened units: col → value
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  bool _onlyMissing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return switch (_period) {
      'Last week' => (monday.subtract(const Duration(days: 7)), monday.subtract(const Duration(days: 1))),
      'This month' => (DateTime(today.year, today.month, 1), today),
      'Last month' => (DateTime(today.year, today.month - 1, 1), DateTime(today.year, today.month, 0)),
      _ => (monday, today),
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final f = DateFormat('yyyy-MM-dd');
    final (a, b) = _range;
    try {
      final r = await Supabase.instance.client.rpc('reports_submitted', params: {
        'p_table': widget.table,
        'p_from': f.format(a),
        'p_to': f.format(b),
        'p_focus': [for (final e in _focus) {'col': e.key, 'op': 'eq', 'val': e.value}],
      });
      final rows = List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));
      // the Compilation screen's order of units
      if (rows.isNotEmpty) {
        final lv = rows.first['level'].toString();
        final order = CompLevel.orderNames(rows.map((e) => e['unit'].toString()), lv == 'cell_group' ? 'Cell' : lv == 'sub_location' ? 'Sub-location' : lv == 'department' ? 'Dept' : lv);
        rows.sort((x, y) => order.indexOf(x['unit'].toString()).compareTo(order.indexOf(y['unit'].toString())));
      }
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load (run 18_round17.sql): ${e is PostgrestException ? e.message : e}";
        });
      }
    }
  }

  void _open(Map<String, dynamic> r) {
    final lv = r['level'].toString();
    if (lv == 'cell_group') return;
    setState(() => _focus.add(MapEntry(lv, r['unit'].toString())));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final level = _rows.isNotEmpty ? _rows.first['level'].toString() : (_focus.isEmpty ? '' : _cols[_cols.indexOf(_focus.last.key) >= 4 ? 4 : _cols.indexOf(_focus.last.key) + 1]);
    final shown = _onlyMissing ? _rows.where((r) => r['reported'] != true).toList() : _rows;
    final done = _rows.where((r) => r['reported'] == true).length;
    final (a, b) = _range;
    return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 30), children: [
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: [
        for (final p in const ['This week', 'Last week', 'This month', 'Last month'])
          ChoiceChip(
            label: Text(p),
            selected: _period == p,
            onSelected: (_) {
              setState(() => _period = p);
              _load();
            },
          ),
        FilterChip(label: const Text("Not reported only"), selected: _onlyMissing, onSelected: (v) => setState(() => _onlyMissing = v)),
      ]),
      const SizedBox(height: 6),
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
        ActionChip(
          avatar: const Icon(Icons.home_work_outlined, size: 16),
          label: const Text("My area"),
          onPressed: _focus.isEmpty
              ? null
              : () {
                  setState(() => _focus.clear());
                  _load();
                },
        ),
        for (int i = 0; i < _focus.length; i++) ...[
          const Icon(Icons.chevron_right_rounded, size: 18),
          ActionChip(
            label: Text(_focus[i].value),
            onPressed: i == _focus.length - 1
                ? null
                : () {
                    setState(() => _focus.removeRange(i + 1, _focus.length));
                    _load();
                  },
          ),
        ],
      ]),
      const SizedBox(height: 6),
      Text(
        "${_levelNames[level] ?? 'Units'} · ${DateFormat('d MMM').format(a)} – ${DateFormat('d MMM yyyy').format(b)} · $done of ${_rows.length} reported",
        textAlign: TextAlign.center,
        style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(_purple)),
      ),
      const SizedBox(height: 8),
      if (_loading)
        const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
      else if (_error != null)
        Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center))
      else if (shown.isEmpty)
        Padding(padding: const EdgeInsets.all(20), child: Text(_rows.isEmpty ? "No units in your area." : "Every unit reported.", textAlign: TextAlign.center))
      else
        for (final r in shown) _card(r),
    ]);
  }

  Widget _card(Map<String, dynamic> r) {
    final ok = r['reported'] == true;
    final c = ok ? Colors.green.shade700 : Colors.red.shade700;
    final subTotal = (r['sub_total'] as num?)?.toInt() ?? 0;
    final subDone = (r['sub_reported'] as num?)?.toInt() ?? 0;
    final last = DateTime.tryParse((r['last_report'] ?? '').toString());
    final canOpen = r['level'] != 'cell_group';
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppPalette.line(c.withValues(alpha: 0.35)))),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: canOpen ? () => _open(r) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: AppPalette.fg(c)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r['unit'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(
                  [
                    ok ? "Reported · ${r['reports']} entries, ${r['sessions']} session${r['sessions'] == 1 ? '' : 's'}" : "Not reported",
                    if (last != null) "last ${DateFormat('EEE d MMM').format(last)}",
                    if (subTotal > 0) "$subDone of $subTotal ${r['level'] == 'team' ? 'cells' : 'units'} reported",
                    "${r['members']} members",
                  ].join(' · '),
                  style: TextStyle(fontSize: 11.5, color: AppPalette.fg(ok ? Colors.blueGrey.shade700 : Colors.red.shade800)),
                ),
                // the units below it: which reported and which did not (no names)
                if ((r['units_reported'] ?? '').toString().isNotEmpty)
                  Text("Reported: ${r['units_reported']}", maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.green.shade800))),
                if ((r['units_missing'] ?? '').toString().isNotEmpty)
                  Text("Not reported: ${r['units_missing']}", maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.red.shade800))),
              ]),
            ),
            if (canOpen) Icon(Icons.chevron_right_rounded, color: AppPalette.fg(Colors.grey)),
          ]),
        ),
      ),
    );
  }
}
