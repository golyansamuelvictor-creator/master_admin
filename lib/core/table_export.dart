
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'app_palette.dart';

/// A table to export: what the screen shows, as text.
class ExportTable {
  final String title;
  final String subtitle;
  final List<String> headers;
  final List<List<String>> rows;

  const ExportTable({required this.title, this.subtitle = '', required this.headers, required this.rows});

  bool get isEmpty => rows.isEmpty;

  /// Rows padded/trimmed to the header width.
  List<List<String>> get fitted => rows
      .map((r) => List<String>.generate(headers.length, (i) => i < r.length ? r[i] : ''))
      .toList();

  String get safeName {
    final base = title.replaceAll(RegExp(r'[^A-Za-z0-9가-힣 _-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    return '${base.isEmpty ? 'Report' : base}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}';
  }
}

/// Real file exports for every table in the app:
/// Excel (.xlsx download), PDF (download) and Print (preview with page size,
/// orientation and printer options, like WPS / Excel print preview).
class TableExport {
  TableExport._();

  // ------------------------------------------------------------ Excel
  static Future<void> excel(BuildContext context, ExportTable t) async {
    try {
      final book = xl.Excel.createExcel();
      final sheetName = book.getDefaultSheet() ?? 'Sheet1';
      final sheet = book[sheetName];
      final bold = xl.CellStyle(bold: true);
      final head = xl.CellStyle(
        bold: true,
        backgroundColorHex: xl.ExcelColor.fromHexString('#4A148C'),
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: xl.HorizontalAlign.Center,
      );

      int r = 0;
      void put(int row, int col, String text, [xl.CellStyle? style]) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
        final clean = text.replaceAll(',', '').trim();
        final n = clean.endsWith('%') ? null : num.tryParse(clean);
        if (n != null && clean.isNotEmpty) {
          cell.value = n is int ? xl.IntCellValue(n) : xl.DoubleCellValue(n.toDouble());
        } else if (clean.endsWith('%') && double.tryParse(clean.substring(0, clean.length - 1)) != null) {
          cell.value = xl.DoubleCellValue(double.parse(clean.substring(0, clean.length - 1)) / 100);
          cell.cellStyle = xl.CellStyle(bold: style?.isBold ?? false, numberFormat: xl.NumFormat.standard_10);
          return;
        } else {
          cell.value = xl.TextCellValue(text);
        }
        if (style != null) cell.cellStyle = style;
      }

      put(r++, 0, t.title, bold);
      if (t.subtitle.isNotEmpty) put(r++, 0, t.subtitle);
      r++;
      for (int c = 0; c < t.headers.length; c++) {
        put(r, c, t.headers[c], head);
      }
      r++;
      for (final row in t.fitted) {
        for (int c = 0; c < row.length; c++) {
          put(r, c, row[c], c == 0 ? bold : null);
        }
        r++;
      }
      for (int c = 0; c < t.headers.length; c++) {
        sheet.setColumnWidth(c, c == 0 ? 26.0 : 12.0);
      }

      final name = '${t.safeName}.xlsx';
      if (kIsWeb) {
        book.save(fileName: name); // the browser downloads it
      } else {
        final bytes = book.encode();
        if (bytes == null) throw 'Could not build the file';
        await FilePicker.platform.saveFile(dialogTitle: 'Save Excel file', fileName: name, bytes: Uint8List.fromList(bytes));
      }
      if (!context.mounted) return;
      _toast(context, 'Excel file downloaded: $name');
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, 'Excel export failed: $e', error: true);
    }
  }

  // ------------------------------------------------------------ PDF
  static Future<pw.ThemeData> _theme() async {
    try {
      final base = await PdfGoogleFonts.merriweatherRegular();
      final bold = await PdfGoogleFonts.merriweatherBold();
      final kr = await PdfGoogleFonts.notoSansKRRegular(); // Korean unit names
      return pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [kr]);
    } catch (_) {
      return pw.ThemeData(); // offline: built-in font
    }
  }

  static Future<Uint8List> pdfBytes(ExportTable t, PdfPageFormat format) async {
    final theme = await _theme();
    final doc = pw.Document(theme: theme, title: t.title);
    final wide = t.headers.length > 8;
    final fs = t.headers.length > 14 ? 6.5 : (wide ? 7.5 : 9.0);
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(24),
      header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(t.title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
        if (t.subtitle.isNotEmpty) pw.Text(t.subtitle, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
      ]),
      footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Printed ${DateFormat('d MMM yyyy, HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
      ]),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          headers: t.headers,
          data: t.fitted,
          headerStyle: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.purple900),
          cellStyle: pw.TextStyle(fontSize: fs),
          cellAlignment: pw.Alignment.center,
          cellAlignments: {0: pw.Alignment.centerLeft},
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.4),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        ),
      ],
    ));
    return doc.save();
  }

  static PdfPageFormat _fmtFor(ExportTable t) => t.headers.length > 8 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

  static Future<void> pdf(BuildContext context, ExportTable t) async {
    try {
      final bytes = await pdfBytes(t, _fmtFor(t));
      await Printing.sharePdf(bytes: bytes, filename: '${t.safeName}.pdf'); // downloads on the web
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, 'PDF export failed: $e', error: true);
    }
  }

  // ------------------------------------------------------------ Print preview
  static Future<void> preview(BuildContext context, ExportTable t) =>
      previewBuilder(context, t.title, (format) => pdfBytes(t, format), fileName: '${t.safeName}.pdf', initial: _fmtFor(t));

  /// Opens a print preview for any PDF: page size, portrait/landscape,
  /// Print (printer, copies, pages in the system dialog) and Download.
  static Future<void> previewBuilder(BuildContext context, String title, LayoutCallback build,
      {String? fileName, PdfPageFormat? initial}) {
    return Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        appBar: AppBar(
          title: Text('Print preview · $title', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        body: PdfPreview(
          build: build,
          initialPageFormat: initial ?? PdfPageFormat.a4,
          pdfFileName: fileName ?? 'report.pdf',
          canChangePageFormat: true,
          canChangeOrientation: true,
          canDebug: false,
          allowPrinting: true,
          allowSharing: true,
          pageFormats: const {'A4': PdfPageFormat.a4, 'A3': PdfPageFormat.a3, 'Letter': PdfPageFormat.letter, 'Legal': PdfPageFormat.legal},
        ),
      ),
    ));
  }

  /// Print preview for a ready-made document.
  static Future<void> previewDoc(BuildContext context, String title, pw.Document doc, {String? fileName}) async {
    final bytes = await doc.save();
    if (!context.mounted) return;
    return previewBuilder(context, title, (_) async => bytes, fileName: fileName);
  }

  // ------------------------------------------------------------ Copy
  static Future<void> copy(BuildContext context, ExportTable t) async {
    final b = StringBuffer()..writeln(t.headers.join('\t'));
    for (final r in t.fitted) {
      b.writeln(r.join('\t'));
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!context.mounted) return;
    _toast(context, 'Table copied – paste it into Excel or Sheets');
  }

  // ------------------------------------------------------------ UI
  /// Download menu: Excel, PDF, Print preview, Copy.
  static Future<void> showMenu(BuildContext context, ExportTable Function() build) async {
    final t = build();
    if (t.isEmpty) {
      _toast(context, 'Nothing to export yet', error: true);
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Export “${t.title}”', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          _opt(ctx, 'excel', Icons.grid_on_rounded, const Color(0xFF1D6F42), 'Excel (.xlsx)', 'Download a spreadsheet file'),
          _opt(ctx, 'pdf', Icons.picture_as_pdf_rounded, const Color(0xFFC62828), 'PDF', 'Download a PDF file'),
          _opt(ctx, 'print', Icons.print_rounded, const Color(0xFF37474F), 'Print…', 'Preview, page size, orientation, printer'),
          _opt(ctx, 'copy', Icons.copy_all_rounded, const Color(0xFF4A148C), 'Copy table', 'Paste into Excel, Sheets or a message'),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'excel':
        await excel(context, t);
      case 'pdf':
        await pdf(context, t);
      case 'print':
        await preview(context, t);
      case 'copy':
        await copy(context, t);
    }
  }

  static Widget _opt(BuildContext ctx, String v, IconData i, Color c, String title, String sub) => ListTile(
        leading: CircleAvatar(backgroundColor: AppPalette.bg(c.withValues(alpha: 0.1)), child: Icon(i, color: AppPalette.fg(c), size: 20)),
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(sub, style: GoogleFonts.inter(fontSize: 12)),
        onTap: () => Navigator.pop(ctx, v),
      );

  /// Print + Download buttons for a module toolbar.
  static Widget buttons(BuildContext context, ExportTable Function() build) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Print preview (Ctrl+P)',
          onPressed: () {
            final t = build();
            if (t.isEmpty) {
              _toast(context, 'Nothing to print yet', error: true);
            } else {
              preview(context, t);
            }
          },
          icon: Icon(Icons.print_rounded, color: AppPalette.fg(Colors.blueGrey), size: 19),
        ),
        IconButton(
          tooltip: 'Download Excel / PDF',
          onPressed: () => showMenu(context, build),
          icon: Icon(Icons.download_rounded, color: AppPalette.fg(Colors.green.shade700), size: 19),
        ),
      ]);

  static void _toast(BuildContext context, String msg, {bool error = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.red.shade700 : const Color(0xFF1D6F42),
      ));
  }
}
