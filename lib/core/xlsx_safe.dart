import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

/// Opens an .xlsx file with the `excel` package, repairing files it refuses.
///
/// Files saved by Excel, Google Sheets or WPS often list some of Excel's
/// built-in number formats (ids below 164, e.g. 42 = accounting) as if they
/// were custom ones. The `excel` package then stops with
/// "custom numFmtId starts at 164 but found a value of 42". Those entries
/// are only copies of the built-in formats, so they are taken out of
/// xl/styles.xml and the file is read again. The cells and columns are not
/// touched.
Excel decodeExcelSafe(List<int> bytes) {
  try {
    return Excel.decodeBytes(bytes);
  } catch (e) {
    final fixed = _withoutBuiltInNumFmts(bytes);
    if (fixed == null) rethrow;
    return Excel.decodeBytes(fixed);
  }
}

List<int>? _withoutBuiltInNumFmts(List<int> bytes) {
  try {
    final src = ZipDecoder().decodeBytes(bytes);
    final out = Archive();
    var changed = false;
    for (final f in src.files) {
      if (!f.isFile) continue;
      var data = List<int>.from(f.content as List);
      if (f.name == 'xl/styles.xml') {
        final xml = utf8.decode(data, allowMalformed: true);
        var removed = 0;
        var fixedXml = xml.replaceAllMapped(
          RegExp(r'<(\w+:)?numFmt\b[^>]*?numFmtId="(\d+)"[^>]*?(/>|>.*?</(\w+:)?numFmt>)', dotAll: true),
          (m) {
            final id = int.tryParse(m.group(2) ?? '') ?? 999;
            if (id >= 164) return m.group(0)!;
            removed++;
            return '';
          },
        );
        if (removed > 0) {
          // keep the count attribute right (or drop an empty list)
          fixedXml = fixedXml.replaceAllMapped(RegExp(r'<((\w+:)?numFmts)\b([^>]*?)count="(\d+)"'), (m) {
            final n = (int.tryParse(m.group(4) ?? '') ?? removed) - removed;
            return '<${m.group(1)}${m.group(3)}count="${n < 0 ? 0 : n}"';
          });
          fixedXml = fixedXml.replaceAll(RegExp(r'<(\w+:)?numFmts\b[^>]*?count="0"[^>]*?>\s*</(\w+:)?numFmts>'), '');
          data = utf8.encode(fixedXml);
          changed = true;
        }
      }
      out.addFile(ArchiveFile(f.name, data.length, data));
    }
    if (!changed) return null;
    final List<int>? zipped = ZipEncoder().encode(out);
    return zipped;
  } catch (_) {
    return null;
  }
}
