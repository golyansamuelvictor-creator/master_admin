import 'dart:math' as math;

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';
import 'compilation_rules.dart';
import 'compilation_style.dart';
import 'i18n.dart';
import 'security.dart';

/// Report tables laid out like the church's Excel sheets: up to three header
/// lines with merged titles (e.g. Kampala › Actual › In-person), a section
/// column ("Status", "Regions") and a label column. The same description is
/// drawn on screen ([RepTable]) and written to Excel ([RepBook]).

/// One value column. [g1] top header, [g2] second, [g3] third ('' = none).
class RepCol {
  final String g1, g2, g3;
  final bool pct;
  const RepCol(this.g1, [this.g2 = '', this.g3 = '', this.pct = false]);
  int get depth => g3.isNotEmpty ? 3 : (g2.isNotEmpty ? 2 : 1);
}

/// One line: [section] (merged down while it repeats), [label] and values
/// (null = empty cell). Percentages are 0–100.
class RepRow {
  final String section, label;
  final List<num?> vals;
  final bool total, sub;
  const RepRow(this.section, this.label, this.vals, {this.total = false, this.sub = false});
}

class RepBlock {
  final String title;
  final String corner; // top-left header text
  final List<RepCol> cols;
  final List<RepRow> rows;
  const RepBlock({required this.title, required this.corner, required this.cols, required this.rows});
}

/// A merged header rectangle (columns / header lines, inclusive).
class RepHead {
  final int c1, c2, r1, r2;
  final String text;
  const RepHead(this.c1, this.c2, this.r1, this.r2, this.text);
}

int repHeadLines(List<RepCol> cols) => cols.isEmpty ? 1 : cols.map((c) => c.depth).reduce(math.max);

List<RepHead> repHeads(List<RepCol> cols) {
  final h = repHeadLines(cols);
  final out = <RepHead>[];
  // line 1
  int i = 0;
  while (i < cols.length) {
    int j = i;
    while (j + 1 < cols.length && cols[j + 1].g1 == cols[i].g1 && cols[i].depth > 1 && cols[j + 1].depth > 1) {
      j++;
    }
    out.add(RepHead(i, j, 0, cols[i].depth == 1 ? h - 1 : 0, cols[i].g1));
    i = j + 1;
  }
  // line 2
  i = 0;
  while (i < cols.length) {
    if (cols[i].depth < 2) {
      i++;
      continue;
    }
    int j = i;
    while (j + 1 < cols.length && cols[j + 1].depth >= 2 && cols[j + 1].g1 == cols[i].g1 && cols[j + 1].g2 == cols[i].g2 && cols[i].depth == 3 && cols[j + 1].depth == 3) {
      j++;
    }
    out.add(RepHead(i, j, 1, cols[i].depth == 2 ? h - 1 : 1, cols[i].g2));
    i = j + 1;
  }
  // line 3
  for (int k = 0; k < cols.length; k++) {
    if (cols[k].depth == 3) out.add(RepHead(k, k, 2, 2, cols[k].g3));
  }
  return out;
}

String repFmt(num? v, bool pct) {
  if (v == null) return '';
  if (pct) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? '${r.round()}%' : '${r.toStringAsFixed(1)}%';
  }
  return CompPeriod.fmt(v);
}

// ---------------------------------------------------------------------------
// On screen
// ---------------------------------------------------------------------------

class RepTable extends StatelessWidget {
  final RepBlock block;
  final double cellW, sectionW, labelW;
  final void Function(RepRow row)? onTapRow;

  /// Text size of the cells and headers; line heights.
  final double fontSize, rowH, headH;

  /// Widen the value columns so the table fills the space it has (up to
  /// [maxCell] each) instead of leaving empty room on the right.
  final bool fill;
  final double maxCell;
  const RepTable({
    super.key,
    required this.block,
    this.cellW = 50,
    this.sectionW = 70,
    this.labelW = 128,
    this.onTapRow,
    this.fontSize = 9.5,
    this.rowH = 23,
    this.headH = 30,
    this.fill = false,
    this.maxCell = 150,
  });

  static const Color _purple = Color(0xFF4A148C);

  /// No section column when no row has a section.
  double get _sectionW => block.rows.every((r) => r.section.isEmpty) ? 0 : sectionW;

  /// The narrowest value column that shows every header on one line.
  double get _headFit {
    double w = cellW;
    final cw = fontSize * 0.66;
    for (final h in repHeads(block.cols)) {
      final span = h.c2 - h.c1 + 1;
      final need = (tr(h.text).length * cw + 12) / span;
      if (need > w) w = need;
    }
    return math.min(w, math.max(cellW, 220));
  }

  @override
  Widget build(BuildContext context) {
    final base = _headFit;
    if (!fill || block.cols.isEmpty) return _build(context, base);
    return LayoutBuilder(builder: (ctx, bc) {
      double cw = base;
      if (bc.maxWidth.isFinite) {
        final want = (bc.maxWidth - 4 - _sectionW - labelW) / block.cols.length;
        if (want > cw) cw = math.min(want, math.max(maxCell, base));
      }
      return _build(ctx, cw);
    });
  }

  Widget _build(BuildContext context, double cellW) {
    final sectionW = _sectionW;
    final double hh = headH, rh = rowH;
    final cols = block.cols;
    final lines = repHeadLines(cols);
    final heads = repHeads(cols);
    final lead = sectionW + labelW;
    final width = lead + cols.length * cellW;
    final line = AppPalette.line(Colors.black26);
    final hs = GoogleFonts.merriweather(fontSize: fontSize, fontWeight: FontWeight.w900, color: AppPalette.fg(CompStyle.headerFg));
    final cs = GoogleFonts.merriweather(fontSize: fontSize, color: AppPalette.fg(Colors.black87));

    Widget box(double l, double t, double w, double h, Widget child, Color bg) => Positioned(
          left: l,
          top: t,
          width: w,
          height: h,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(color: AppPalette.bg(bg), border: Border.all(color: line, width: 0.5)),
            child: child,
          ),
        );

    final header = SizedBox(
      width: width,
      height: lines * hh,
      child: Stack(children: [
        box(0, 0, lead, lines * hh, Text.rich(TextSpan(text: block.corner), style: hs, textAlign: TextAlign.center), CompStyle.headerBg),
        for (final h in heads)
          box(lead + h.c1 * cellW, h.r1 * hh, (h.c2 - h.c1 + 1) * cellW, (h.r2 - h.r1 + 1) * hh,
              Text.rich(TextSpan(text: tr(h.text)), style: hs, textAlign: TextAlign.center, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis), CompStyle.headerBg),
      ]),
    );

    // the section column: one merged cell per run of the same section
    final rows = block.rows;
    final sectionCells = <Widget>[];
    int i = sectionW == 0 ? rows.length : 0;
    while (i < rows.length) {
      int j = i;
      while (j + 1 < rows.length && rows[j + 1].section == rows[i].section && rows[i].section.isNotEmpty) {
        j++;
      }
      sectionCells.add(box(0, i * rh, sectionW, (j - i + 1) * rh,
          Text.rich(TextSpan(text: tr(rows[i].section)), style: cs.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          rows[i].total ? CompStyle.totalBg : CompStyle.labelBg));
      i = j + 1;
    }

    final body = SizedBox(
      width: width,
      height: rows.length * rh,
      child: Stack(children: [
        ...sectionCells,
        for (int r = 0; r < rows.length; r++) ...[
          Positioned(
            left: sectionW,
            top: r * rh,
            width: labelW,
            height: rh,
            child: InkWell(
              onTap: onTapRow == null ? null : () => onTapRow!(rows[r]),
              child: Container(
                alignment: rows[r].sub ? Alignment.centerLeft : Alignment.center,
                padding: EdgeInsets.only(left: rows[r].sub ? 14 : 4, right: 4),
                decoration: BoxDecoration(
                    color: AppPalette.bg(rows[r].total ? CompStyle.totalBg : (rows[r].sub ? Colors.white : CompStyle.labelBg)),
                    border: Border.all(color: line, width: 0.5)),
                child: Text.rich(TextSpan(text: rows[r].label),
                    maxLines: 1,
                    textAlign: rows[r].sub ? TextAlign.left : TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: cs.copyWith(
                        fontWeight: rows[r].sub ? FontWeight.normal : FontWeight.bold,
                        color: onTapRow != null ? AppPalette.fg(_purple) : null,
                        decoration: onTapRow != null && !rows[r].total ? TextDecoration.underline : null)),
              ),
            ),
          ),
          for (int c = 0; c < cols.length; c++)
            box(
              lead + c * cellW,
              r * rh,
              cellW,
              rh,
              Text.rich(
                TextSpan(text: c < rows[r].vals.length ? repFmt(rows[r].vals[c], cols[c].pct) : ''),
                style: cs.copyWith(
                  fontWeight: rows[r].total ? FontWeight.bold : null,
                  color: cols[c].pct && c < rows[r].vals.length && rows[r].vals[c] != null && cols[c].g1 != 'Absentees'
                      ? AppPalette.fg(CompStyle.rateColor(rows[r].vals[c]!.toDouble()))
                      : null,
                ),
              ),
              rows[r].total ? CompStyle.totalBg : (r.isEven ? Colors.white : const Color(0xFFFAF7FF)),
            ),
        ],
      ]),
    );

    // centred when narrower than the room it has; scrolls sideways when wider
    return LayoutBuilder(
      builder: (_, bc) => Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 10),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: bc.maxWidth.isFinite ? bc.maxWidth : 0),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [header, body]),
          ),
        ),
      ),
    );
  }
}

/// A titled card around one or more report tables, with the full-screen and
/// download buttons.
class RepCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  const RepCard({super.key, required this.title, required this.child, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.line(const Color(0x334A148C))),
          boxShadow: AppPalette.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 3, 6, 3),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppPalette.bg(const Color(0xFFF1E9FC))!, AppPalette.bg(const Color(0xFFE8EEFB))!]),
              border: Border(bottom: BorderSide(color: AppPalette.line(const Color(0x224A148C)))),
            ),
            child: Row(children: [
              // same room on the left as the buttons take, so the title is centred
              SizedBox(width: 34.0 * actions.length),
              Expanded(
                child: Column(children: [
                  Text.rich(TextSpan(text: tr(title)),
                      textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: AppPalette.fg(const Color(0xFF3B0764)), fontWeight: FontWeight.w900, fontSize: 13)),
                  if ((subtitle ?? '').isNotEmpty)
                    Text.rich(TextSpan(text: subtitle), textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey.shade700), fontSize: 11)),
                ]),
              ),
              ...actions,
            ]),
          ),
          Padding(padding: const EdgeInsets.all(10), child: child),
        ]),
      );
}

/// Icon button for a [RepCard] header.
Widget repAction(IconData icon, String tip, VoidCallback? onTap) => IconButton(
      tooltip: tr(tip),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 28),
      icon: Icon(icon, color: AppPalette.fg(const Color(0xFF4A148C)), size: 18),
      onPressed: onTap,
    );

// ---------------------------------------------------------------------------
// Excel
// ---------------------------------------------------------------------------

class RepBook {
  final xl.Excel _book = xl.Excel.createExcel();
  String? _default;
  final Set<String> _names = {};

  RepBook() {
    _default = _book.getDefaultSheet();
  }

  RepSheet sheet(String name) {
    var n = name.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ').trim();
    if (n.isEmpty) n = 'Sheet';
    if (n.length > 31) n = n.substring(0, 31);
    var unique = n;
    int k = 2;
    while (_names.contains(unique)) {
      unique = '${n.substring(0, math.min(n.length, 28))} $k';
      k++;
    }
    _names.add(unique);
    if (_default != null) {
      _book.rename(_default!, unique);
      _default = null;
    }
    return RepSheet(_book[unique]);
  }

  /// Downloads the workbook (checks the export permission first).
  Future<void> save(BuildContext context, String fileName) async {
    if (!await AppSecurity.checkExport(context)) return;
    try {
      final name = fileName.endsWith('.xlsx') ? fileName : '$fileName.xlsx';
      if (kIsWeb) {
        _book.save(fileName: name);
      } else {
        final bytes = _book.encode();
        if (bytes == null) throw 'Could not build the file';
        await FilePicker.platform.saveFile(dialogTitle: 'Save Excel file', fileName: name, bytes: Uint8List.fromList(bytes));
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text.rich(TextSpan(text: "${tr('Downloaded')} $name")), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text.rich(TextSpan(text: "${tr('Excel export failed')}: $e")), backgroundColor: Colors.red.shade700));
    }
  }
}

class RepSheet {
  final xl.Sheet s;
  int row = 0;
  RepSheet(this.s);

  static final xl.Border _thin = xl.Border(borderStyle: xl.BorderStyle.Thin);
  xl.CellIndex _at(int c, int r) => xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);

  xl.CellStyle _st({String? bg, bool bold = false, bool pct = false, bool left = false, bool wrap = false, int size = 10}) => xl.CellStyle(
        bold: bold,
        fontSize: size,
        backgroundColorHex: bg == null ? xl.ExcelColor.none : xl.ExcelColor.fromHexString(bg),
        horizontalAlign: left ? xl.HorizontalAlign.Left : xl.HorizontalAlign.Center,
        verticalAlign: xl.VerticalAlign.Center,
        textWrapping: wrap ? xl.TextWrapping.WrapText : null,
        leftBorder: _thin,
        rightBorder: _thin,
        topBorder: _thin,
        bottomBorder: _thin,
        numberFormat: pct ? xl.NumFormat.standard_10 : xl.NumFormat.standard_0,
      );

  void text(int c, int r, String v, {String? bg, bool bold = false, bool left = false, bool border = true, int size = 10}) {
    final cell = s.cell(_at(c, r));
    cell.value = xl.TextCellValue(I18n.term(v));
    if (border) {
      cell.cellStyle = _st(bg: bg, bold: bold, left: left, size: size);
    } else {
      cell.cellStyle = xl.CellStyle(bold: bold, fontSize: size);
    }
  }

  void number(int c, int r, num? v, {bool pct = false, String? bg, bool bold = false}) {
    final cell = s.cell(_at(c, r));
    if (v == null) {
      cell.value = xl.TextCellValue('');
    } else if (pct) {
      cell.value = xl.DoubleCellValue(v.toDouble() / 100);
    } else if (v is int || v == v.roundToDouble()) {
      cell.value = xl.IntCellValue(v.round());
    } else {
      cell.value = xl.DoubleCellValue(v.toDouble());
    }
    cell.cellStyle = _st(bg: bg, bold: bold, pct: pct);
  }

  void merge(int c1, int r1, int c2, int r2, String v, {String? bg, bool bold = true, bool wrap = true}) {
    if (c1 == c2 && r1 == r2) {
      text(c1, r1, v, bg: bg, bold: bold);
      return;
    }
    s.merge(_at(c1, r1), _at(c2, r2), customValue: xl.TextCellValue(I18n.term(v)));
    for (int c = c1; c <= c2; c++) {
      for (int r = r1; r <= r2; r++) {
        s.cell(_at(c, r)).cellStyle = _st(bg: bg, bold: bold, wrap: wrap);
      }
    }
  }

  /// A bold title line.
  void title(String t, {int size = 13}) {
    text(0, row, t, bold: true, border: false, size: size);
    row++;
  }

  void gap([int n = 1]) => row += n;

  /// Writes a [RepBlock] at the current line (2 label columns, then values).
  void block(RepBlock b) {
    const head = '#E9DDFB', total = '#FFF1CC', label = '#F6F0FF';
    if (b.title.isNotEmpty) title(b.title, size: 12);
    final lines = repHeadLines(b.cols);
    final r0 = row;
    merge(0, r0, 1, r0 + lines - 1, b.corner, bg: head);
    for (final h in repHeads(b.cols)) {
      merge(2 + h.c1, r0 + h.r1, 2 + h.c2, r0 + h.r2, h.text, bg: head);
    }
    row = r0 + lines;
    int i = 0;
    while (i < b.rows.length) {
      int j = i;
      while (j + 1 < b.rows.length && b.rows[j + 1].section == b.rows[i].section && b.rows[i].section.isNotEmpty) {
        j++;
      }
      merge(0, row + i, 0, row + j, b.rows[i].section, bg: b.rows[i].total ? total : label);
      i = j + 1;
    }
    for (int r = 0; r < b.rows.length; r++) {
      final x = b.rows[r];
      final bg = x.total ? total : null;
      text(1, row + r, x.sub ? '  ${x.label}' : x.label, bg: x.total ? total : (x.sub ? null : label), bold: !x.sub, left: true);
      for (int c = 0; c < b.cols.length; c++) {
        number(2 + c, row + r, c < x.vals.length ? x.vals[c] : null, pct: b.cols[c].pct, bg: bg, bold: x.total);
      }
    }
    row += b.rows.length + 1;
  }

  /// A plain table: one header line, then rows of text / numbers.
  void table(List<String> headers, List<List<Object?>> rows, {Set<int> pctCols = const {}}) {
    const head = '#E9DDFB';
    for (int c = 0; c < headers.length; c++) {
      text(c, row, headers[c], bg: head, bold: true);
    }
    row++;
    for (final r in rows) {
      for (int c = 0; c < r.length; c++) {
        final v = r[c];
        if (v is num) {
          number(c, row, v, pct: pctCols.contains(c));
        } else {
          text(c, row, (v ?? '').toString(), left: c < 2);
        }
      }
      row++;
    }
    row++;
  }

  void widths(double first, double second, double rest, int count) {
    s.setColumnWidth(0, first);
    s.setColumnWidth(1, second);
    for (int c = 2; c < count; c++) {
      s.setColumnWidth(c, rest);
    }
  }
}
