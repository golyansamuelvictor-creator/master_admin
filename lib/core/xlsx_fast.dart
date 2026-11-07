import 'dart:convert';

import 'package:archive/archive.dart';

/// Fast reader for the first sheet of an .xlsx file: every cell as text
/// (blank cells are null). Dates come back as YYYY-MM-DD.
///
/// The `excel` package builds styles and objects for every cell and, on the
/// web, runs on the same thread as the screen, so a big members file froze
/// the page ("Page unresponsive"). This reads only the values, and pauses
/// now and then so the screen keeps drawing. [onProgress] gets a 0–1 value.
Future<List<List<String?>>> readXlsxFast(List<int> bytes, {void Function(double)? onProgress}) async {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? file(String name) {
    final f = zip.findFile(name);
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  // which file is the first sheet
  var sheetPath = 'xl/worksheets/sheet1.xml';
  final wb = file('xl/workbook.xml') ?? '';
  final rels = file('xl/_rels/workbook.xml.rels') ?? '';
  final firstSheet = RegExp(r'<(?:\w+:)?sheet\b[^>]*?r:id="([^"]+)"').firstMatch(wb);
  if (firstSheet != null) {
    final rid = firstSheet.group(1)!;
    for (final m in RegExp(r'<Relationship\b[^>]*>').allMatches(rels)) {
      final tag = m.group(0)!;
      if (!tag.contains('Id="$rid"')) continue;
      final t = RegExp(r'Target="([^"]+)"').firstMatch(tag)?.group(1);
      if (t != null) sheetPath = t.startsWith('/') ? t.substring(1) : 'xl/${t.replaceFirst(RegExp(r'^\./'), '')}';
    }
  }
  final sheet = file(sheetPath) ?? file('xl/worksheets/sheet1.xml');
  if (sheet == null) throw Exception("The file has no sheet.");
  final date1904 = RegExp(r'date1904="(1|true)"').hasMatch(wb);

  // shared texts
  final shared = <String>[];
  final ss = file('xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in RegExp(r'<(?:\w+:)?si>(.*?)</(?:\w+:)?si>', dotAll: true).allMatches(ss)) {
      final body = si.group(1)!.replaceAll(RegExp(r'<(?:\w+:)?rPh\b.*?</(?:\w+:)?rPh>', dotAll: true), '');
      final b = StringBuffer();
      for (final t in RegExp(r'<(?:\w+:)?t\b[^>]*>(.*?)</(?:\w+:)?t>', dotAll: true).allMatches(body)) {
        b.write(t.group(1));
      }
      shared.add(_unescape(b.toString()));
    }
  }

  // which cell styles are dates
  final dateStyle = <int>{};
  final styles = file('xl/styles.xml');
  if (styles != null) {
    final custom = <int, String>{};
    for (final m in RegExp(r'<(?:\w+:)?numFmt\b[^>]*>').allMatches(styles)) {
      final id = int.tryParse(RegExp(r'numFmtId="(\d+)"').firstMatch(m.group(0)!)?.group(1) ?? '');
      final code = RegExp(r'formatCode="([^"]*)"').firstMatch(m.group(0)!)?.group(1);
      if (id != null && code != null) custom[id] = _unescape(code);
    }
    bool isDate(int id) {
      if ((id >= 14 && id <= 22) || (id >= 27 && id <= 36) || (id >= 45 && id <= 47) || (id >= 50 && id <= 58)) return true;
      final c = custom[id];
      if (c == null) return false;
      final plain = c.replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]|\\.'), '').toLowerCase();
      return plain.contains('y') || plain.contains('d');
    }

    final xfs = RegExp(r'<(?:\w+:)?cellXfs\b[^>]*>(.*?)</(?:\w+:)?cellXfs>', dotAll: true).firstMatch(styles)?.group(1) ?? '';
    var i = 0;
    for (final xf in RegExp(r'<(?:\w+:)?xf\b[^>]*>').allMatches(xfs)) {
      final id = int.tryParse(RegExp(r'numFmtId="(\d+)"').firstMatch(xf.group(0)!)?.group(1) ?? '0') ?? 0;
      if (isDate(id)) dateStyle.add(i);
      i++;
    }
  }

  // the cells
  final rows = <List<String?>>[];
  final cellRe = RegExp(r'<(?:\w+:)?c\b([^>]*?)(?:/>|>(.*?)</(?:\w+:)?c>)', dotAll: true);
  final vRe = RegExp(r'<(?:\w+:)?v>(.*?)</(?:\w+:)?v>', dotAll: true);
  final isRe = RegExp(r'<(?:\w+:)?t\b[^>]*>(.*?)</(?:\w+:)?t>', dotAll: true);
  final refRe = RegExp(r'\br="([A-Z]+)(\d+)"');
  final tRe = RegExp(r'\bt="(\w+)"');
  final sRe = RegExp(r'\bs="(\d+)"');
  final total = sheet.length;
  var n = 0, lastRow = -1, lastCol = -1;
  for (final m in cellRe.allMatches(sheet)) {
    if (++n % 4000 == 0) {
      onProgress?.call(m.start / total);
      await Future<void>.delayed(Duration.zero); // let the screen draw
    }
    final attrs = m.group(1)!;
    final ref = refRe.firstMatch(attrs);
    int r, c;
    if (ref != null) {
      r = int.parse(ref.group(2)!) - 1;
      c = 0;
      for (final u in ref.group(1)!.codeUnits) {
        c = c * 26 + (u - 64);
      }
      c -= 1;
    } else {
      // no reference: next cell of the same row
      r = lastRow < 0 ? 0 : lastRow;
      c = lastCol + 1;
    }
    lastRow = r;
    lastCol = c;
    final body = m.group(2);
    if (body == null) continue;
    final type = tRe.firstMatch(attrs)?.group(1) ?? 'n';
    String? val;
    switch (type) {
      case 's':
        final k = int.tryParse(vRe.firstMatch(body)?.group(1) ?? '');
        val = k != null && k < shared.length ? shared[k] : null;
      case 'inlineStr':
        val = _unescape(isRe.allMatches(body).map((x) => x.group(1)).join());
      case 'b':
        val = vRe.firstMatch(body)?.group(1) == '1' ? 'TRUE' : 'FALSE';
      case 'e':
        val = null;
      case 'str':
      case 'd':
        final v = vRe.firstMatch(body)?.group(1);
        val = v == null ? null : _unescape(v);
      default:
        final v = vRe.firstMatch(body)?.group(1);
        if (v != null) {
          final s = int.tryParse(sRe.firstMatch(attrs)?.group(1) ?? '');
          final num0 = double.tryParse(v);
          if (s != null && dateStyle.contains(s) && num0 != null) {
            val = _serialToDate(num0, date1904);
          } else if (num0 != null && num0 == num0.truncateToDouble() && num0.abs() < 1e15) {
            val = num0.toInt().toString();
          } else {
            val = v;
          }
        }
    }
    val = val?.trim();
    if (val == null || val.isEmpty) continue;
    while (rows.length <= r) {
      rows.add(<String?>[]);
    }
    final row = rows[r];
    while (row.length <= c) {
      row.add(null);
    }
    row[c] = val;
  }
  onProgress?.call(1);
  return rows;
}

String _serialToDate(double serial, bool date1904) {
  final base = date1904 ? DateTime.utc(1904, 1, 1) : DateTime.utc(1899, 12, 30);
  final d = base.add(Duration(days: serial.floor()));
  String two(int x) => x.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

String _unescape(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);'), (m) {
    final e = m.group(1)!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final code = e.startsWith('#x') ? int.parse(e.substring(2), radix: 16) : int.parse(e.substring(1));
    return String.fromCharCode(code);
  });
}
