import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';
import '../../core/i18n.dart';
import 'bb_workspace_screen.dart';

const Color _kPurple = Color(0xFF4A148C);

/// Evangelism › Evangelism Results: the Summary sheet's tables (opening months,
/// opening centers, guide's location, center × status, checker, goals) for
/// the user's own unit, with a filter side bar like the Compilation screen.
class EvangelismResultsScreen extends StatefulWidget {
  /// Results By Units (Compilation screen): goals vs current down to the cell.
  final VoidCallback? onOpenClassic;
  const EvangelismResultsScreen({super.key, this.onOpenClassic});
  @override
  State<EvangelismResultsScreen> createState() => _EvangelismResultsScreenState();
}

class _EvangelismResultsScreenState extends State<EvangelismResultsScreen> {
  BbSettings? _cfg;
  List<String> _locations = [];
  String? _location, _center;
  String? _error;
  // The detailed results (center × status) were removed: the BB File has them.
  final Set<String> _sections = {'goals', 'months', 'centers', 'locations', 'checker'};
  int _rev = 0;
  StateSetter? _sheetSet; // the filters sheet on phones

  void _upd(VoidCallback f) {
    setState(f);
    _sheetSet?.call(() {});
  }

  static const Map<String, String> _labels = {
    'goals': 'Goals this month',
    'months': 'Worthy Prospect + Spirit Creation (opening months)',
    'centers': 'Opening centers',
    'locations': "By the guide's location",
    'checker': 'Checker',
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cfg = await BbSettings.load();
      final s = await Supabase.instance.client.rpc('bb_summary');
      final locs = ((s as Map)['locations'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (mounted) {
        setState(() {
          _cfg = cfg;
          _locations = locs..sort();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't load the results (run 12_round11.sql and 13_round12.sql): ${e is PostgrestException ? e.message : e}");
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
        child: Text(t, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12, color: AppPalette.fg(_kPurple))),
      );

  Widget _drop(String hint, String? value, List<String> items, void Function(String?) set) => DropdownButtonFormField<String>(
        initialValue: items.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: tr(hint), isDense: true, border: const OutlineInputBorder()),
        items: [
          DropdownMenuItem<String>(value: null, child: Text("All")),
          for (final i in items) DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => _upd(() {
          set(v);
          _rev++;
        }),
      );

  Widget _sidebar({bool sheet = false}) {
    final cfg = _cfg!;
    return Container(
      width: sheet ? null : 310,
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        border: sheet ? null : Border(right: BorderSide(color: AppPalette.line(Colors.black), width: 1.0)),
      ),
      child: ListView(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), children: [
        Row(children: [
          Icon(Icons.tune_rounded, color: AppPalette.fg(_kPurple), size: 20),
          const SizedBox(width: 8),
          Text("Results filters", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple), fontSize: 15)),
        ]),
        if (widget.onOpenClassic != null) ...[
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: widget.onOpenClassic,
            icon: const Icon(Icons.table_view_rounded, size: 18),
            label: const Text("Results By Units"),
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_kPurple), foregroundColor: AppPalette.fg(Colors.white), padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
          const SizedBox(height: 4),
          Text("Goals vs current results by unit, down to the cell group, with charts.",
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
        ],
        _label("Area"),
        _drop("Guide's location", _location, _locations, (v) => _location = v),
        const SizedBox(height: 10),
        _drop("Center place", _center, cfg.centers, (v) => _center = v),
        const SizedBox(height: 10),
        _label("Tables"),
        for (final e in _labels.entries)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _sections.contains(e.key),
            title: Text(e.value, style: const TextStyle(fontSize: 12.5)),
            onChanged: (v) => _upd(() {
              if (v == true) {
                _sections.add(e.key);
              } else {
                _sections.remove(e.key);
              }
              _rev++;
            }),
          ),
        const SizedBox(height: 10),
        Text("Students count only when their attendance details are complete and they attended at least once. Each student belongs to the unit of their guide.",
            style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final cfg = _cfg;
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
      appBar: AppBar(
        centerTitle: true,
        title: Text("Evangelism results", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(_kPurple))),
        actions: [
          if (!wide && cfg != null)
            IconButton(
              tooltip: tr("Filters"),
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => SizedBox(
                  height: MediaQuery.of(context).size.height * 0.8,
                  child: StatefulBuilder(builder: (_, set) {
                    _sheetSet = set;
                    return _sidebar(sheet: true);
                  }),
                ),
              ).then((_) {
                _sheetSet = null;
                setState(() => _rev++);
              }),
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : cfg == null
              ? const Center(child: CircularProgressIndicator())
              : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (wide) _sidebar(),
                  Expanded(
                    child: BbSummaryView(
                      key: ValueKey('$_rev|$_location|$_center|${_sections.join(',')}'),
                      cfg: cfg,
                      location: _location,
                      center: _center,
                      sections: Set.of(_sections),
                    ),
                  ),
                ]),
    );
  }
}
