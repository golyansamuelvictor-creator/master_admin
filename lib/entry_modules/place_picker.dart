import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';

/// Service Attendance › Place: where the member attended the service.
///
/// The first choice is one of the Place options (entry_field_options):
///  * Main Location  → the member's own location name
///  * Sub Location   → one of the sub-locations of the member's location
///  * Nansana Temple (or any other fixed place) → returned as it is
///  * Other Location → any location, then one of its sub-locations
///  * Home Cell      → one of the home cells (home_cells, 18_round17.sql)
/// The answer is saved as text, e.g. "Sub Location: Kyebando", so the
/// Detailed results show where the member offered service from.
class PlacePicker {
  PlacePicker._();

  static List<Map<String, dynamic>>? _locations; // {id, location}
  static List<Map<String, dynamic>>? _subs; // {name, location_id}
  static List<Map<String, dynamic>>? _homeCells;

  static Future<void> _load() async {
    final db = Supabase.instance.client;
    if (_locations == null) {
      try {
        _locations = List<Map<String, dynamic>>.from(await db.from('locations').select('id, location').order('location'));
      } catch (_) {
        _locations = [];
      }
    }
    if (_subs == null) {
      try {
        _subs = List<Map<String, dynamic>>.from(await db.from('sub_locations').select());
      } catch (_) {
        _subs = [];
      }
    }
    if (_homeCells == null) {
      try {
        _homeCells = List<Map<String, dynamic>>.from(
            await db.from('home_cells').select('id, name, location, sub_location').eq('is_active', true).order('name'));
      } catch (_) {
        _homeCells = []; // before 18_round17.sql
      }
    }
  }

  static String _kind(String option) {
    final o = option.toLowerCase();
    if (o.contains('home')) return 'home';
    if (o.contains('other')) return 'other';
    if (o.contains('sub')) return 'sub';
    if (o.contains('main')) return 'main';
    return 'fixed';
  }

  static List<String> _subsOf(String location) {
    final loc = (_locations ?? []).firstWhere(
      (l) => (l['location'] ?? '').toString().toLowerCase() == location.toLowerCase(),
      orElse: () => const {},
    );
    final id = loc['id']?.toString();
    return {
      for (final s in _subs ?? const <Map<String, dynamic>>[])
        if ((id != null && s['location_id']?.toString() == id) ||
            (s['location'] ?? s['location_name'] ?? '').toString().toLowerCase() == location.toLowerCase())
          (s['name'] ?? s['sub_location'] ?? '').toString()
    }.where((x) => x.isNotEmpty).toList()
      ..sort();
  }

  /// Asks for the place; returns the text to save, or null when cancelled.
  static Future<String?> pick(BuildContext context, {required List<String> options, required Map member, String? current}) async {
    final opts = options.isNotEmpty ? options : const ['Main Location', 'Sub Location', 'Nansana Temple', 'Other Location', 'Home Cell'];
    final first = await _choose(context, "Where did they attend?", opts, current: current?.split(':').first.trim());
    if (first == null || !context.mounted) return null;
    await _load();
    if (!context.mounted) return null;
    final myLoc = (member['location'] ?? member['members']?['location'] ?? '').toString().trim();
    switch (_kind(first)) {
      case 'main':
        return myLoc.isEmpty ? first : "$first: $myLoc";
      case 'sub':
        final s = await _choose(context, "Which sub-location of $myLoc?", _subsOf(myLoc), search: true);
        return s == null ? null : "$first: $s";
      case 'other':
        final locs = [for (final l in _locations ?? const []) (l['location'] ?? '').toString()]
          ..removeWhere((x) => x.isEmpty || x.toLowerCase() == myLoc.toLowerCase() || x.toLowerCase() == 'church');
        final l = await _choose(context, "Which location?", locs, search: true);
        if (l == null || !context.mounted) return null;
        final subs = _subsOf(l);
        if (subs.isEmpty) return "$first: $l";
        final s = await _choose(context, "Which sub-location of $l?", subs, search: true);
        return s == null ? null : "$first: $l › $s";
      case 'home':
        final cells = _homeCells ?? const [];
        String label(Map c) => [c['name'], c['sub_location'], c['location']].where((x) => (x ?? '').toString().trim().isNotEmpty).join(' · ');
        // the member's own location first
        final mine = cells.where((c) => (c['location'] ?? '').toString().toLowerCase() == myLoc.toLowerCase()).toList();
        final rest = cells.where((c) => !mine.contains(c)).toList();
        final h = await _choose(context, "Which home cell?", [for (final c in [...mine, ...rest]) label(c)], search: true,
            empty: "No home cells yet. The administrator adds them in Supabase (home_cells).");
        return h == null ? null : "$first: ${h.split(' · ').first}";
      default:
        return first;
    }
  }

  static Future<String?> _choose(BuildContext context, String title, List<String> items, {bool search = false, String? current, String? empty}) {
    String q = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final shown = items.where((i) => q.isEmpty || i.toLowerCase().contains(q.toLowerCase())).toList();
        return AlertDialog(
          title: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15)),
          contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          content: SizedBox(
            width: 380,
            height: (shown.length * 46.0 + (search ? 56 : 0)).clamp(80.0, 420.0),
            child: Column(children: [
              if (search)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => set(() => q = v),
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: tr("Search"), isDense: true, border: const OutlineInputBorder()),
                  ),
                ),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: Text(empty ?? "Nothing to choose.", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey))))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemExtent: 46,
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          selected: shown[i] == current,
                          title: Text(shown[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                          onTap: () => Navigator.pop(ctx, shown[i]),
                        ),
                      ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel"))],
        );
      }),
    );
  }
}
