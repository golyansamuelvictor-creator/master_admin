import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';

const Color _kPurple = Color(0xFF4A148C);

/// A clean period picker: quick choices (this week, last month …), a month
/// calendar (two months side by side on wide screens) with the chosen range
/// highlighted, and the From – To summary on top. Returns null on Cancel.
Future<DateTimeRange?> showNiceRangePicker(
  BuildContext context, {
  DateTimeRange? initial,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = 'Choose a period',
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (_) => _NiceRangeDialog(
      initial: initial,
      first: firstDate ?? DateTime(2023),
      last: lastDate ?? DateTime.now(),
      title: title,
    ),
  );
}

class _NiceRangeDialog extends StatefulWidget {
  final DateTimeRange? initial;
  final DateTime first, last;
  final String title;
  const _NiceRangeDialog({this.initial, required this.first, required this.last, required this.title});
  @override
  State<_NiceRangeDialog> createState() => _NiceRangeDialogState();
}

class _NiceRangeDialogState extends State<_NiceRangeDialog> {
  DateTime? _from, _to;
  late DateTime _month; // the first month shown

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime get _today => _day(DateTime.now());

  @override
  void initState() {
    super.initState();
    _from = widget.initial == null ? null : _day(widget.initial!.start);
    _to = widget.initial == null ? null : _day(widget.initial!.end);
    final base = _to ?? _today;
    _month = DateTime(base.year, base.month, 1);
  }

  bool _allowed(DateTime d) => !d.isBefore(_day(widget.first)) && !d.isAfter(_day(widget.last));

  void _tap(DateTime d) {
    if (!_allowed(d)) return;
    setState(() {
      if (_from == null || _to != null) {
        _from = d;
        _to = null;
      } else if (d.isBefore(_from!)) {
        _to = _from;
        _from = d;
      } else {
        _to = d;
      }
    });
  }

  void _quick(DateTime a, DateTime b) {
    final last = _day(widget.last);
    setState(() {
      _from = a;
      _to = b.isAfter(last) ? last : b;
      _month = DateTime((_to ?? a).year, (_to ?? a).month, 1);
    });
  }

  List<(String, VoidCallback)> get _quickChoices {
    final t = _today;
    final mon = t.subtract(Duration(days: t.weekday - 1));
    final q = ((t.month - 1) ~/ 3) * 3 + 1;
    return [
      ("This week", () => _quick(mon, t)),
      ("Last week", () => _quick(mon.subtract(const Duration(days: 7)), mon.subtract(const Duration(days: 1)))),
      ("This month", () => _quick(DateTime(t.year, t.month, 1), t)),
      ("Last month", () => _quick(DateTime(t.year, t.month - 1, 1), DateTime(t.year, t.month, 0))),
      ("Last 3 months", () => _quick(DateTime(t.year, t.month - 3, 1), DateTime(t.year, t.month, 0))),
      ("This quarter", () => _quick(DateTime(t.year, q, 1), t)),
      ("This year", () => _quick(DateTime(t.year, 1, 1), t)),
    ];
  }

  Widget _monthView(DateTime m) {
    final first = DateTime(m.year, m.month, 1);
    final daysIn = DateTime(m.year, m.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    final cells = <Widget>[
      for (final w in const ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'])
        Center(child: Text(w, style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(w == 'Su' ? Colors.red.shade400 : Colors.blueGrey.shade600)))),
      for (int i = 0; i < lead; i++) const SizedBox(),
      for (int d = 1; d <= daysIn; d++) _dayCell(DateTime(m.year, m.month, d)),
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(DateFormat('MMMM yyyy').format(m), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppPalette.fg(_kPurple))),
      const SizedBox(height: 6),
      SizedBox(
        width: 7 * 38,
        child: GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 2,
          children: cells,
        ),
      ),
    ]);
  }

  Widget _dayCell(DateTime d) {
    final ok = _allowed(d);
    final isFrom = _from != null && d == _from;
    final isTo = _to != null && d == _to;
    final inside = _from != null && _to != null && d.isAfter(_from!) && d.isBefore(_to!);
    final edge = isFrom || isTo;
    final today = d == _today;
    final band = AppPalette.bg(const Color(0xFFEDE3F8));
    return GestureDetector(
      onTap: ok ? () => _tap(d) : null,
      child: Container(
        // the band joining the two ends
        decoration: BoxDecoration(
          color: inside || (edge && _to != null && _from != _to) ? band : null,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(isFrom || d.weekday == 1 ? 18 : 0),
            right: Radius.circular(isTo || d.weekday == 7 ? 18 : 0),
          ),
        ),
        child: Center(
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: edge ? AppPalette.solid(_kPurple) : null,
              border: today && !edge ? Border.all(color: AppPalette.line(_kPurple), width: 1.4) : null,
            ),
            child: Text(
              "${d.day}",
              style: GoogleFonts.merriweather(
                fontSize: 12,
                fontWeight: edge || today ? FontWeight.w900 : FontWeight.w500,
                color: edge ? Colors.white : AppPalette.fg(ok ? (d.weekday == 7 ? Colors.red.shade400 : Colors.black87) : Colors.grey.shade400),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 720;
    final f = DateFormat('EEE d MMM yyyy');
    final n = _from != null && _to != null ? _to!.difference(_from!).inDays + 1 : 0;
    final canPrev = DateTime(_month.year, _month.month, 1).isAfter(DateTime(widget.first.year, widget.first.month, 1));
    final lastShown = wide ? DateTime(_month.year, _month.month + 1, 1) : _month;
    final canNext = lastShown.isBefore(DateTime(widget.last.year, widget.last.month, 1));
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: AppPalette.bg(Colors.white),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 660 : 380),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // the summary
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppPalette.solid(_kPurple), AppPalette.solid(const Color(0xFF7B4FC0))], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: GoogleFonts.merriweather(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: _end("From", _from == null ? "—" : f.format(_from!))),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: _end("To", _to == null ? (_from == null ? "—" : "Pick the last day") : f.format(_to!))),
                ]),
                if (n > 0) ...[
                  const SizedBox(height: 4),
                  Text("$n day${n == 1 ? '' : 's'}", style: GoogleFonts.merriweather(fontSize: 11, color: Colors.white70)),
                ],
              ]),
            ),
            // quick choices
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
              child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                for (final q in _quickChoices)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(q.$1, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.w600, color: AppPalette.fg(_kPurple))),
                    backgroundColor: AppPalette.bg(const Color(0xFFF6F1FC)),
                    side: BorderSide(color: AppPalette.line(const Color(0xFFDCCBF2))),
                    onPressed: q.$2,
                  ),
              ]),
            ),
            // the calendar
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconButton(
                  tooltip: tr("Previous month"),
                  onPressed: canPrev ? () => setState(() => _month = DateTime(_month.year, _month.month - 1, 1)) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Wrap(alignment: WrapAlignment.center, spacing: 18, runSpacing: 10, children: [
                    _monthView(_month),
                    if (wide) _monthView(DateTime(_month.year, _month.month + 1, 1)),
                  ]),
                ),
                IconButton(
                  tooltip: tr("Next month"),
                  onPressed: canNext ? () => setState(() => _month = DateTime(_month.year, _month.month + 1, 1)) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(children: [
                Expanded(
                  child: Text(_from == null ? "Tap the first day, then the last day." : (_to == null ? "Now tap the last day." : ""),
                      style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppPalette.solid(_kPurple)),
                  onPressed: _from == null ? null : () => Navigator.pop(context, DateTimeRange(start: _from!, end: _to ?? _from!)),
                  child: const Text("Apply"),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _end(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: GoogleFonts.merriweather(fontSize: 10.5, color: Colors.white70)),
        Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
      ]);
}
