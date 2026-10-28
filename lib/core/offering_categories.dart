import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One kind of offering (a column of logs_offering).
class OfferingCategory {
  final String column; // logs_offering column, e.g. offering_weekly
  final String label; // "Weekly Offering"
  final String short; // "Weekly"
  final Color color;
  /// Given every week (Week 1–5, e.g. Weekly Offering). The others are given
  /// once a month, so who offered them is counted for the whole period.
  final bool weekly;
  const OfferingCategory(this.column, this.label, this.short, this.color, {this.weekly = false});
}

/// The kinds of offering shown in the entry form and the compilation, read
/// from `offering_categories` (12_round11.sql) so they can be renamed,
/// reordered or switched off without an app update. The list below is only
/// used until Supabase answers (or if the table is missing).
class OfferingCategories {
  OfferingCategories._();

  static const List<OfferingCategory> _fallback = [
    OfferingCategory('offering_weekly', 'Weekly Offering', 'Weekly', Color(0xFF1565C0), weekly: true),
    OfferingCategory('offering_tithe', 'Tithe', 'Tithe', Color(0xFF4A148C)),
    OfferingCategory('offering_construction', 'Construction Offering', 'Constr.', Color(0xFF00897B)),
    OfferingCategory('offering_thanks', 'Thanksgiving (T.G)', 'T.G', Color(0xFFEF6C00)),
    OfferingCategory('offering_rent', 'Rent', 'Rent', Color(0xFF6D4C41)),
    OfferingCategory('offering_hq', 'HQ', 'HQ', Color(0xFFAD1457)),
  ];

  static List<OfferingCategory> list = _fallback;

  /// Every column that can hold an offering, including "Donation" used by
  /// older reports (still counted so nothing given earlier is lost).
  static List<String> get allColumns => [
        ...list.map((c) => c.column),
        if (!list.any((c) => c.column == 'offering_donation')) 'offering_donation',
      ];

  /// (column, short name) for tables, including older Donation entries.
  static List<(String, String)> get labelled => [
        ...list.map((c) => (c.column, c.short)),
        if (!list.any((c) => c.column == 'offering_donation')) ('offering_donation', 'Donation'),
      ];
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      List<dynamic> rows;
      try {
        rows = await Supabase.instance.client
            .from('offering_categories')
            .select('column_name, label, short_label, color_hex, is_weekly')
            .eq('is_active', true)
            .order('sort_order', ascending: true);
      } on PostgrestException {
        // before 14_round13.sql (no is_weekly column yet)
        rows = await Supabase.instance.client
            .from('offering_categories')
            .select('column_name, label, short_label, color_hex')
            .eq('is_active', true)
            .order('sort_order', ascending: true);
      }
      if (rows.isEmpty) return;
      list = [
        for (final r in rows)
          OfferingCategory(
            r['column_name'].toString(),
            (r['label'] ?? r['column_name']).toString(),
            (r['short_label'] ?? r['label'] ?? '').toString(),
            _hex(r['color_hex']?.toString()),
            weekly: r['is_weekly'] == true || (r['is_weekly'] == null && r['column_name'] == 'offering_weekly'),
          ),
      ];
    } catch (_) {
      _loading = null; // try again next time
    }
  }

  static Color _hex(String? h) {
    final v = int.tryParse((h ?? '').replaceAll('#', ''), radix: 16);
    return v == null ? const Color(0xFF4A148C) : Color(0xFF000000 | v);
  }

  /// The offering week (1–5) of a report: `offering_week` when saved,
  /// otherwise from the day of the month (1–7 → Week 1 … 29–31 → Week 5).
  static int weekOf(Map row) {
    final w = int.tryParse((row['offering_week'] ?? '').toString());
    if (w != null && w >= 1 && w <= 5) return w;
    final d = DateTime.tryParse((row['report_date'] ?? '').toString());
    return d == null ? 1 : weekOfDate(d);
  }

  static int weekOfDate(DateTime d) => ((d.day - 1) ~/ 7 + 1).clamp(1, 5);

  /// "25,000" / "25000" / "UGX 25 000" → 25000 (0 when empty or not a number).
  static num amount(dynamic v) {
    final s = (v ?? '').toString().replaceAll(RegExp(r'[^0-9.\-]'), '');
    return num.tryParse(s) ?? 0;
  }
}
