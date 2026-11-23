import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';

/// A guide / BB teacher found by name (bb_person_search, 39_round35.sql):
/// name, korean_name, scj_id, location, sub_location, department, team,
/// cell_group. With [students] the guide is a center student
/// (Theology › Students) and the units are theirs.
Future<Map<String, dynamic>?> pickBbPerson(BuildContext context, {bool students = false, String initial = '', String title = ''}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _PersonSearch(students: students, initial: initial, title: title),
  );
}

class _PersonSearch extends StatefulWidget {
  final bool students;
  final String initial, title;
  const _PersonSearch({required this.students, required this.initial, required this.title});
  @override
  State<_PersonSearch> createState() => _PersonSearchState();
}

class _PersonSearchState extends State<_PersonSearch> {
  late final TextEditingController _q = TextEditingController(text: widget.initial);
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = [];
  bool _busy = false;
  String? _note;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initial.trim().length >= 2) _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    final req = ++_req;
    if (q.length < 2) {
      setState(() {
        _rows = [];
        _note = null;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await Supabase.instance.client.rpc('bb_person_search', params: {'p_q': q, 'p_students': widget.students});
      if (!mounted || req != _req) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));
        _busy = false;
        _note = _rows.isEmpty ? tr("No one found. Try another spelling, the Korean name or the SCJ ID.") : null;
      });
    } catch (_) {
      if (!mounted || req != _req) return;
      setState(() {
        _busy = false;
        _note = tr("Couldn't search right now.");
      });
    }
  }

  String _units(Map<String, dynamic> m) => [m['location'], m['sub_location'], m['department'], m['team'], m['cell_group']]
      .where((x) => x != null && x.toString().trim().isNotEmpty && x.toString().toUpperCase() != 'N/A')
      .join(' › ');

  @override
  Widget build(BuildContext context) {
    final title = widget.title.isNotEmpty ? widget.title : (widget.students ? "Find a center student" : "Find a member");
    return AlertDialog(
      title: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16)),
      contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(children: [
          TextField(
            controller: _q,
            autofocus: true,
            onChanged: _changed,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: tr(widget.students ? "Type the student's name" : "Type a name, Korean name or SCJ ID"),
              isDense: true,
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
            ),
          ),
          const SizedBox(height: 8),
          if (_note != null) Padding(padding: const EdgeInsets.all(8), child: Text.rich(TextSpan(text: _note), textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey.shade700), fontSize: 12))),
          Expanded(
            child: ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = _rows[i];
                final ko = (m['korean_name'] ?? '').toString().trim();
                final id = (m['scj_id'] ?? '').toString().trim();
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 16, backgroundColor: AppPalette.bg(const Color(0xFFEDE4FA)), child: const Icon(Icons.person_rounded, size: 18, color: Color(0xFF4A148C))),
                  title: Text.rich(TextSpan(text: "${m['name'] ?? ''}${ko.isEmpty ? '' : '  ($ko)'}"), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text.rich(TextSpan(text: [if (id.isNotEmpty) id, _units(m)].where((x) => x.isNotEmpty).join(' · ')), maxLines: 2),
                  onTap: () => Navigator.pop(context, m),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel"))],
    );
  }
}
