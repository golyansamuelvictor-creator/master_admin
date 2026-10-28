import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';
import '../core/offering_categories.dart';

/// Offering entry (department treasurer): the amount each member gave this
/// week for every kind of offering (Weekly, Tithe, Construction, T.G, Rent,
/// HQ … from `offering_categories`), with the member's units like the other
/// entry forms. Totals per member and per kind update as you type.
/// The "Offered week" (Week 1–5) is saved with every row, so the weeks can
/// be compared in the compilation; Weekly Offering is given every week, the
/// other kinds once a month.
class OfferingEntry extends StatefulWidget {
  final List<dynamic> members;
  final Map<String, Map<String, dynamic>> reportData;
  final Color pPurple;
  final VoidCallback onChanged;
  /// The report date: its week of the month is the default offered week.
  final DateTime? reportDate;

  const OfferingEntry({super.key, required this.members, required this.reportData, required this.pPurple, required this.onChanged, this.reportDate});

  @override
  State<OfferingEntry> createState() => _OfferingEntryState();
}

class _OfferingEntryState extends State<OfferingEntry> {
  final Map<String, TextEditingController> _ctl = {};
  final _hScroll = ScrollController();
  String _search = '';
  bool _ready = false;
  late int _week = _initialWeek();
  static final _fmt = NumberFormat.decimalPattern();

  int _initialWeek() {
    for (final r in widget.reportData.values) {
      final w = int.tryParse((r['offering_week'] ?? '').toString());
      if (w != null && w >= 1 && w <= 5) return w;
    }
    return OfferingCategories.weekOfDate(widget.reportDate ?? DateTime.now());
  }

  bool _hasAmount(Map<String, dynamic> r) => OfferingCategories.allColumns.any((c) => OfferingCategories.amount(r[c]) != 0);

  /// The week applies to every row that has an amount (empty rows stay empty).
  void _setWeek(int w) {
    setState(() => _week = w);
    for (final r in widget.reportData.values) {
      if (_hasAmount(r)) r['offering_week'] = w;
    }
    widget.onChanged();
  }

  static const double _rowH = 32;
  static const List<(String, String, double)> _unitCols = [
    ('location', 'Location', 110),
    ('sub_location', 'Sub-Location', 110),
    ('department', 'Department', 110),
    ('team', 'Team', 80),
    ('cell_group', 'Cell', 80),
  ];
  static const double _nameW = 170;
  static const double _amountW = 112;
  static const double _totalW = 112;

  @override
  void initState() {
    super.initState();
    OfferingCategories.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    _hScroll.dispose();
    super.dispose();
  }

  TextEditingController _c(String mid, String col) => _ctl.putIfAbsent('$mid|$col', () {
        final v = OfferingCategories.amount(widget.reportData[mid]?[col]);
        return TextEditingController(text: v == 0 ? '' : _fmt.format(v));
      });

  void _set(String mid, String col, String text) {
    final n = OfferingCategories.amount(text);
    final row = widget.reportData.putIfAbsent(mid, () => {});
    if (n == 0) {
      row[col] = null;
    } else {
      row[col] = n % 1 == 0 ? n.toInt().toString() : n.toString();
    }
    if (_hasAmount(row)) row['offering_week'] = _week;
    widget.onChanged();
    setState(() {});
  }

  num _rowTotal(String mid) {
    final r = widget.reportData[mid];
    if (r == null) return 0;
    return OfferingCategories.list.fold<num>(0, (a, c) => a + OfferingCategories.amount(r[c.column]));
  }

  num _colTotal(String col) =>
      widget.members.fold<num>(0, (a, m) => a + OfferingCategories.amount(widget.reportData[m['id'].toString()]?[col]));

  int _givers(String col) => widget.members.where((m) => OfferingCategories.amount(widget.reportData[m['id'].toString()]?[col]) > 0).length;

  Widget _cell(String text, double w, {bool bold = false, Color? color, TextAlign align = TextAlign.center, Color? bg}) => Container(
        width: w,
        height: _rowH,
        alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: bg == null ? null : AppPalette.bg(bg),
          border: Border(right: BorderSide(color: AppPalette.line(Colors.black12)), bottom: BorderSide(color: AppPalette.line(Colors.black12))),
        ),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: AppPalette.fg(color ?? Colors.black87))),
      );

  @override
  Widget build(BuildContext context) {
    final cats = OfferingCategories.list;
    final q = _search.trim().toLowerCase();
    final rows = q.isEmpty
        ? widget.members
        : widget.members.where((m) => '${m['english_name']} ${m['cell_group']} ${m['team']}'.toLowerCase().contains(q)).toList();
    final width = _unitCols.fold<double>(0, (a, c) => a + c.$3) + _nameW + cats.length * _amountW + _totalW;
    final grand = cats.fold<num>(0, (a, c) => a + _colTotal(c.column));
    final givers = widget.members.where((m) => _rowTotal(m['id'].toString()) > 0).length;

    final header = Row(children: [
      for (final c in _unitCols) _cell(c.$2, c.$3, bold: true, color: Colors.white, bg: widget.pPurple),
      _cell("English Name", _nameW, bold: true, color: Colors.white, bg: widget.pPurple),
      for (final c in cats) _cell(c.label, _amountW, bold: true, color: Colors.white, bg: widget.pPurple),
      _cell("Total", _totalW, bold: true, color: Colors.white, bg: widget.pPurple),
    ]);
    final totals = Row(children: [
      _cell("General total", _unitCols.fold<double>(0, (a, c) => a + c.$3) + _nameW, bold: true, color: widget.pPurple, bg: const Color(0xFFF1E8FB)),
      for (final c in cats) _cell(_fmt.format(_colTotal(c.column)), _amountW, bold: true, color: c.color, bg: const Color(0xFFF1E8FB)),
      _cell(_fmt.format(grand), _totalW, bold: true, color: widget.pPurple, bg: const Color(0xFFF1E8FB)),
    ]);
    final giverRow = Row(children: [
      _cell("Offered", _unitCols.fold<double>(0, (a, c) => a + c.$3) + _nameW, bold: true, bg: const Color(0xFFF8FAFC)),
      for (final c in cats) _cell("${_givers(c.column)} of ${widget.members.length}", _amountW, bg: const Color(0xFFF8FAFC)),
      _cell("$givers of ${widget.members.length}", _totalW, bold: true, bg: const Color(0xFFF8FAFC)),
    ]);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text("Offered week", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(widget.pPurple))),
            const SizedBox(width: 8),
            FittedBox(
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [for (int w = 1; w <= 5; w++) ButtonSegment(value: w, label: Text("Week $w"))],
                selected: {_week},
                onSelectionChanged: (s) => _setWeek(s.first),
              ),
            ),
          ]),
          SizedBox(
            width: 280,
            child: TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: tr("Search name, team or cell"), isDense: true, border: const OutlineInputBorder()),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Text("Type the amount each member gave (UGX). Empty = nothing given. Weekly Offering is given every week; the other kinds once a month.",
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
        ]),
      ),
      if (!_ready) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(children: [
                header,
                totals,
                giverRow,
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemExtent: _rowH,
                    itemBuilder: (_, i) {
                      final m = rows[i];
                      final mid = m['id'].toString();
                      final bg = i.isEven ? Colors.white : const Color(0xFFF8FAFC);
                      return Row(children: [
                        for (final c in _unitCols) _cell((m[c.$1] ?? '').toString(), c.$3, bg: bg),
                        _cell((m['english_name'] ?? '').toString(), _nameW, bold: true, align: TextAlign.left, bg: bg),
                        for (final c in cats)
                          Container(
                            width: _amountW,
                            height: _rowH,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppPalette.bg(bg),
                              border: Border(right: BorderSide(color: AppPalette.line(Colors.black12)), bottom: BorderSide(color: AppPalette.line(Colors.black12))),
                            ),
                            child: TextField(
                              controller: _c(mid, c.column),
                              textAlign: TextAlign.center,
                              keyboardType: const TextInputType.numberWithOptions(decimal: false),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))],
                              style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(c.color), fontWeight: FontWeight.bold),
                              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4), border: OutlineInputBorder(), hintText: '0'),
                              onChanged: (v) => _set(mid, c.column, v),
                            ),
                          ),
                        _cell(_fmt.format(_rowTotal(mid)), _totalW, bold: true, color: widget.pPurple, bg: bg),
                      ]);
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
