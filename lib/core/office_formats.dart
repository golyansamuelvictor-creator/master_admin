import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'pptx_base.dart';

/// Word (.docx) and PowerPoint (.pptx) files for Docs and Slides: open a file
/// made in Word / WPS / Google (text, headings, lists, bold / italic /
/// underline / colour, alignment, quotes, tables as lines; slide titles, text
/// and speaker notes) and save back to the same format.

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------
String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '');

String _unesc(String s) {
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
    return String.fromCharCode(e.startsWith('#x') ? int.parse(e.substring(2), radix: 16) : int.parse(e.substring(1)));
  });
}

Archive _unzip(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

String? _text(Archive z, String name) {
  final f = z.findFile(name);
  if (f == null) return null;
  return utf8.decode(List<int>.from(f.content as List), allowMalformed: true);
}

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, body) {
    final b = utf8.encode(body);
    a.addFile(ArchiveFile(name, b.length, b));
  });
  final List<int>? out = ZipEncoder().encode(a);
  return Uint8List.fromList(out ?? const <int>[]);
}

RegExp _re(String p) => RegExp(p, dotAll: true);

// ---------------------------------------------------------------------------
// Word → document (Quill delta)
// ---------------------------------------------------------------------------
/// The text of a .docx as Quill delta operations.
List<Map<String, dynamic>> deltaFromDocx(Uint8List bytes) {
  final z = _unzip(bytes);
  final doc = _text(z, 'word/document.xml');
  if (doc == null) throw const FormatException("This isn't a Word (.docx) file.");
  final num = _text(z, 'word/numbering.xml') ?? '';

  // numbering: numId → bullet / ordered
  final absFmt = <String, String>{};
  for (final m in _re(r'<w:abstractNum\b[^>]*w:abstractNumId="(\d+)"[^>]*>(.*?)</w:abstractNum>').allMatches(num)) {
    final f = _re(r'<w:lvl\b[^>]*w:ilvl="0"[^>]*>.*?<w:numFmt w:val="(\w+)"').firstMatch(m.group(2)!);
    absFmt[m.group(1)!] = f?.group(1) ?? 'bullet';
  }
  final numFmt = <String, String>{};
  for (final m in _re(r'<w:num\b[^>]*w:numId="(\d+)"[^>]*>.*?<w:abstractNumId w:val="(\d+)"').allMatches(num)) {
    numFmt[m.group(1)!] = absFmt[m.group(2)!] ?? 'bullet';
  }

  final body = _re(r'<w:body>(.*)</w:body>').firstMatch(doc)?.group(1) ?? '';
  final ops = <Map<String, dynamic>>[];
  bool on(String? v) => v == null || !(v == '0' || v == 'false' || v == 'none');

  void para(String p) {
    final ppr = _re(r'<w:pPr>(.*?)</w:pPr>').firstMatch(p)?.group(1) ?? '';
    final la = <String, dynamic>{};
    final st = (RegExp(r'<w:pStyle w:val="([^"]+)"').firstMatch(ppr)?.group(1) ?? '').toLowerCase();
    if (st == 'title' || st == 'heading1') {
      la['header'] = 1;
    } else if (st == 'heading2' || st == 'subtitle') {
      la['header'] = 2;
    } else if (st.startsWith('heading')) {
      la['header'] = 3;
    } else if (st.contains('quote')) {
      la['blockquote'] = true;
    }
    final n = RegExp(r'<w:numId w:val="(\d+)"').firstMatch(ppr)?.group(1);
    if (n != null && n != '0') {
      final f = numFmt[n] ?? 'bullet';
      la['list'] = (f == 'bullet' || f == 'none') ? 'bullet' : 'ordered';
    } else if (st.contains('listbullet')) {
      la['list'] = 'bullet';
    } else if (st.contains('listnumber')) {
      la['list'] = 'ordered';
    }
    final jc = RegExp(r'<w:jc w:val="(\w+)"').firstMatch(ppr)?.group(1);
    const aligns = {'center': 'center', 'right': 'right', 'end': 'right', 'both': 'justify'};
    if (jc != null && aligns.containsKey(jc)) la['align'] = aligns[jc];

    final runs = p.replaceAll(_re(r'<w:pPr>.*?</w:pPr>'), '');
    for (final r in _re(r'<w:r\b[^>]*>(.*?)</w:r>').allMatches(runs)) {
      final rb = r.group(1)!;
      final rpr = _re(r'<w:rPr>(.*?)</w:rPr>').firstMatch(rb)?.group(1) ?? '';
      final a = <String, dynamic>{};
      bool flag(String tag) {
        final m = RegExp('<w:$tag(?: w:val="(\\w+)")?\\s*/>').firstMatch(rpr);
        return m != null && on(m.group(1));
      }

      if (flag('b')) a['bold'] = true;
      if (flag('i')) a['italic'] = true;
      if (flag('strike')) a['strike'] = true;
      final u = RegExp(r'<w:u w:val="(\w+)"').firstMatch(rpr)?.group(1);
      if (u != null && on(u)) a['underline'] = true;
      final c = RegExp(r'<w:color w:val="([0-9A-Fa-f]{6})"').firstMatch(rpr)?.group(1);
      if (c != null && c.toUpperCase() != '000000') a['color'] = '#${c.toUpperCase()}';

      final text = StringBuffer();
      for (final t in _re(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>|<w:tab/>|<w:br/>').allMatches(rb)) {
        final whole = t.group(0)!;
        if (whole == '<w:tab/>') {
          text.write('\t');
        } else if (whole == '<w:br/>') {
          text.write(' ');
        } else if (t.group(1) != null) {
          text.write(_unesc(t.group(1)!));
        }
      }
      if (text.isNotEmpty) ops.add({'insert': text.toString(), if (a.isNotEmpty) 'attributes': a});
    }
    ops.add({'insert': '\n', if (la.isNotEmpty) 'attributes': la});
  }

  for (final m in _re(r'<w:tbl>.*?</w:tbl>|<w:p\b[^>]*/>|<w:p\b.*?</w:p>').allMatches(body)) {
    final x = m.group(0)!;
    if (x.startsWith('<w:tbl>')) {
      // tables: one line per row, cells separated by " | "
      for (final tr in _re(r'<w:tr\b.*?</w:tr>').allMatches(x)) {
        final cells = [
          for (final tc in _re(r'<w:tc\b.*?</w:tc>').allMatches(tr.group(0)!))
            _re(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>').allMatches(tc.group(0)!).map((t) => _unesc(t.group(1)!)).join(' ').trim(),
        ];
        ops.add({'insert': cells.join(' | ')});
        ops.add({'insert': '\n'});
      }
    } else if (!x.endsWith('</w:p>')) {
      ops.add({'insert': '\n'});
    } else {
      para(x);
    }
  }
  if (ops.isEmpty) ops.add({'insert': '\n'});
  return ops;
}

// ---------------------------------------------------------------------------
// document (Quill delta) → Word
// ---------------------------------------------------------------------------
const _ctDocx = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>';
const _relsDocx = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>';

String _hStyle(int i, int sz) => '<w:style w:type="paragraph" w:styleId="Heading$i"><w:name w:val="heading $i"/><w:basedOn w:val="Normal"/>'
    '<w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="${i - 1}"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="$sz"/></w:rPr></w:style>';

String get _stylesDocx => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Merriweather" w:hAnsi="Merriweather" w:eastAsia="Malgun Gothic" w:cs="Merriweather"/>'
    '<w:sz w:val="23"/><w:szCs w:val="23"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr><w:spacing w:after="80" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
    '${_hStyle(1, 44)}${_hStyle(2, 34)}${_hStyle(3, 28)}'
    '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:pBdr>'
    '<w:left w:val="single" w:sz="18" w:space="8" w:color="9E9E9E"/></w:pBdr><w:ind w:left="284"/></w:pPr><w:rPr><w:i/></w:rPr></w:style>'
    '<w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="1155CC"/><w:u w:val="single"/></w:rPr></w:style>'
    '</w:styles>';

String _lvl(String fmt, String text) => '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="$fmt"/><w:lvlText w:val="$text"/>'
    '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>';

String get _numberingDocx => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/>${_lvl('bullet', '•')}</w:abstractNum>'
    '<w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="singleLevel"/>${_lvl('decimal', '%1.')}</w:abstractNum>'
    '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num><w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num></w:numbering>';

/// A Word file from Quill delta operations.
Uint8List docxFromDelta(List ops, String title) {
  // lines: (spans, line attributes)
  final lines = <(List<(String, Map)>, Map)>[];
  var cur = <(String, Map)>[];
  for (final op in ops) {
    final ins = (op as Map)['insert'];
    if (ins is! String) continue;
    final a = (op['attributes'] as Map?) ?? const {};
    final parts = ins.split('\n');
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) cur.add((parts[i], a));
      if (i < parts.length - 1) {
        lines.add((cur, a));
        cur = [];
      }
    }
  }
  if (cur.isNotEmpty) lines.add((cur, const {}));

  final links = <(String, String)>[];
  final body = StringBuffer();
  for (final (spans, la) in lines) {
    final ppr = StringBuffer();
    final h = la['header'];
    if (h == 1 || h == 2 || h == 3) {
      ppr.write('<w:pStyle w:val="Heading$h"/>');
    } else if (la['blockquote'] == true) {
      ppr.write('<w:pStyle w:val="Quote"/>');
    }
    final lst = la['list'];
    if (lst == 'bullet' || lst == 'ordered') {
      ppr.write('<w:numPr><w:ilvl w:val="0"/><w:numId w:val="${lst == 'bullet' ? 1 : 2}"/></w:numPr>');
    }
    const aligns = {'center': 'center', 'right': 'right', 'justify': 'both'};
    final al = aligns[la['align']];
    if (al != null) ppr.write('<w:jc w:val="$al"/>');

    final runs = StringBuffer();
    if (lst == 'checked' || lst == 'unchecked') {
      runs.write('<w:r><w:t xml:space="preserve">${lst == 'checked' ? '☑ ' : '☐ '}</w:t></w:r>');
    }
    for (final (t, a) in spans) {
      final rpr = StringBuffer();
      if (a['bold'] == true) rpr.write('<w:b/>');
      if (a['italic'] == true) rpr.write('<w:i/>');
      if (a['underline'] == true) rpr.write('<w:u w:val="single"/>');
      if (a['strike'] == true) rpr.write('<w:strike/>');
      final c = (a['color'] ?? '').toString().replaceFirst('#', '');
      if (RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(c)) rpr.write('<w:color w:val="${c.toUpperCase()}"/>');
      final bg = (a['background'] ?? '').toString().replaceFirst('#', '');
      if (RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(bg)) rpr.write('<w:shd w:val="clear" w:color="auto" w:fill="${bg.toUpperCase()}"/>');
      final sz = double.tryParse((a['size'] ?? '').toString());
      if (sz != null) rpr.write('<w:sz w:val="${(sz * 2).round()}"/>');
      final link = a['link']?.toString();
      if (link != null && link.isNotEmpty) {
        final rid = 'rIdL${links.length + 1}';
        links.add((rid, link));
        runs.write('<w:hyperlink r:id="$rid"><w:r><w:rPr><w:rStyle w:val="Hyperlink"/>$rpr</w:rPr><w:t xml:space="preserve">${_esc(t)}</w:t></w:r></w:hyperlink>');
      } else {
        runs.write('<w:r>${rpr.isEmpty ? '' : '<w:rPr>$rpr</w:rPr>'}<w:t xml:space="preserve">${_esc(t)}</w:t></w:r>');
      }
    }
    body.write('<w:p>${ppr.isEmpty ? '' : '<w:pPr>$ppr</w:pPr>'}$runs</w:p>');
  }
  final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>$body'
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" '
      'w:header="709" w:footer="709" w:gutter="0"/></w:sectPr></w:body></w:document>';
  final docRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>'
      '${links.map((l) => '<Relationship Id="${l.$1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="${_esc(l.$2)}" TargetMode="External"/>').join()}'
      '</Relationships>';
  final core = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>${_esc(title)}</dc:title><dc:creator>Master Admin</dc:creator></cp:coreProperties>';
  return _zip({
    '[Content_Types].xml': _ctDocx,
    '_rels/.rels': _relsDocx,
    'word/document.xml': document,
    'word/_rels/document.xml.rels': docRels,
    'word/styles.xml': _stylesDocx,
    'word/numbering.xml': _numberingDocx,
    'docProps/core.xml': core,
  });
}

// ---------------------------------------------------------------------------
// PowerPoint ↔ slides
// ---------------------------------------------------------------------------
/// One slide for export: colours as 6-digit hex (no #).
class SlideOut {
  final String title, content, layout, bg, fg, accent;
  const SlideOut({required this.title, required this.content, required this.layout, required this.bg, required this.fg, required this.accent});
}

const _ns = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
const _u = 12700; // EMU per design unit (slides are 960 x 540)

String _run(String t, int sz, String color, {bool b = false, bool i = false}) =>
    '<a:r><a:rPr lang="en-US" sz="${sz * 100}"${b ? ' b="1"' : ''}${i ? ' i="1"' : ''} dirty="0"><a:solidFill><a:srgbClr val="$color"/></a:solidFill>'
    '<a:latin typeface="Merriweather"/></a:rPr><a:t>${_esc(t)}</a:t></a:r>';

String _para(String t, int sz, String color, {String algn = 'l', String? bullet, bool b = false, bool i = false}) {
  final ppr = bullet != null
      ? '<a:pPr algn="$algn" marL="342900" indent="-342900"><a:buClr><a:srgbClr val="$bullet"/></a:buClr><a:buFont typeface="Arial"/><a:buChar char="&#8226;"/></a:pPr>'
      : '<a:pPr algn="$algn"><a:buNone/></a:pPr>';
  return '<a:p>$ppr${t.isEmpty ? '' : _run(t, sz, color, b: b, i: i)}<a:endParaRPr lang="en-US" sz="${sz * 100}"/></a:p>';
}

String _box(int id, int x, int y, int w, int h, List<String> paras, {String anchor = 't'}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Text $id"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
    '<p:spPr><a:xfrm><a:off x="${x * _u}" y="${y * _u}"/><a:ext cx="${w * _u}" cy="${h * _u}"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>'
    '<p:txBody><a:bodyPr wrap="square" lIns="0" rIns="0" anchor="$anchor"><a:normAutofit/></a:bodyPr><a:lstStyle/>'
    '${paras.isEmpty ? '<a:p/>' : paras.join()}</p:txBody></p:sp>';

String _bar(int id, int x, int y, int w, int h, String color) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Accent $id"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
    '<p:spPr><a:xfrm><a:off x="${x * _u}" y="${y * _u}"/><a:ext cx="${w * _u}" cy="${h * _u}"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="$color"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>';

String _slideXml(SlideOut s) {
  final fg = s.fg, ac = s.accent, l = s.layout;
  final lines = s.content.split('\n').where((x) => x.trim().isNotEmpty && !RegExp(r'^-{3,}$').hasMatch(x.trim())).map((x) => x.trim()).toList();
  final sh = <String>[];
  if (l == 'quote') {
    sh.add(_box(2, 70, 90, 820, 280, [_para(s.content.trim(), 30, fg, algn: 'ctr', i: true)], anchor: 'ctr'));
    sh.add(_box(3, 70, 390, 820, 60, [_para(s.title, 20, ac, algn: 'ctr', b: true)]));
  } else if (l == 'title' || l == 'section' || l == 'blank') {
    final al = l == 'section' ? 'l' : 'ctr';
    if (s.title.isNotEmpty) {
      sh.add(_box(2, 70, 130, 820, 150, [_para(s.title, l == 'blank' ? 38 : 50, fg, algn: al, b: true)], anchor: 'b'));
      sh.add(_bar(3, l == 'section' ? 70 : 435, 292, 90, 4, ac));
    }
    sh.add(_box(4, 70, 310, 820, 160, [for (final x in lines) _para(x, 24, fg, algn: al)]));
  } else {
    sh.add(_box(2, 70, 45, 820, 80, [_para(s.title, 38, fg, b: true)], anchor: 'b'));
    sh.add(_bar(3, 70, 132, 90, 4, ac));
    if (l == 'two_column') {
      final parts = s.content.split(RegExp(r'\n-{3,}\n'));
      final left = parts.first, right = parts.length > 1 ? parts.sublist(1).join('\n') : '';
      sh.add(_box(4, 70, 155, 400, 340, [for (final x in left.split('\n')) if (x.trim().isNotEmpty) _para(x.trim(), 22, fg, bullet: ac)]));
      sh.add(_box(5, 490, 155, 400, 340, [for (final x in right.split('\n')) if (x.trim().isNotEmpty) _para(x.trim(), 22, fg, bullet: ac)]));
    } else {
      sh.add(_box(4, 70, 155, 820, 340, [for (final x in lines) _para(x, 22, fg, bullet: ac)]));
    }
  }
  const tree = '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/>'
      '<a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<p:sld $_ns><p:cSld>'
      '<p:bg><p:bgPr><a:solidFill><a:srgbClr val="${s.bg}"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>'
      '<p:spTree>$tree${sh.join()}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
}

const _slideRel = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout7.xml"/></Relationships>';

/// A PowerPoint file (16:9) from the slides.
Uint8List pptxFromSlides(List<SlideOut> slides, String title) {
  final base = _unzip(base64Decode(kPptxBase));
  final files = <String, String>{};
  for (final f in base.files) {
    if (!f.isFile) continue;
    var d = utf8.decode(List<int>.from(f.content as List), allowMalformed: true);
    final n = slides.length;
    if (f.name == 'ppt/presentation.xml') {
      final ids = [for (int i = 0; i < n; i++) '<p:sldId id="${256 + i}" r:id="rIdS${i + 1}"/>'].join();
      d = d.replaceFirst('</p:sldMasterIdLst>', '</p:sldMasterIdLst><p:sldIdLst>$ids</p:sldIdLst>');
    } else if (f.name == 'ppt/_rels/presentation.xml.rels') {
      final rels = [
        for (int i = 0; i < n; i++)
          '<Relationship Id="rIdS${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>',
      ].join();
      d = d.replaceFirst('</Relationships>', '$rels</Relationships>');
    } else if (f.name == '[Content_Types].xml') {
      final ov = [
        for (int i = 0; i < n; i++)
          '<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
      ].join();
      d = d.replaceFirst('</Types>', '$ov</Types>');
    } else if (f.name == 'docProps/core.xml') {
      d = d.replaceFirst(RegExp(r'<dc:title>.*?</dc:title>|<dc:title/>'), '<dc:title>${_esc(title)}</dc:title>');
    }
    files[f.name] = d;
  }
  for (int i = 0; i < slides.length; i++) {
    files['ppt/slides/slide${i + 1}.xml'] = _slideXml(slides[i]);
    files['ppt/slides/_rels/slide${i + 1}.xml.rels'] = _slideRel;
  }
  return _zip(files);
}

/// The slides of a .pptx: title, text (one line per paragraph), notes and a
/// layout guess ('title' for a title slide, else 'title_content').
List<Map<String, String>> slidesFromPptx(Uint8List bytes) {
  final z = _unzip(bytes);
  final pres = _text(z, 'ppt/presentation.xml');
  if (pres == null) throw const FormatException("This isn't a PowerPoint (.pptx) file.");
  final rels = _text(z, 'ppt/_rels/presentation.xml.rels') ?? '';
  final target = <String, String>{};
  for (final m in RegExp(r'<Relationship\b[^>]*>').allMatches(rels)) {
    final tag = m.group(0)!;
    final id = RegExp(r'\bId="([^"]+)"').firstMatch(tag)?.group(1);
    final t = RegExp(r'\bTarget="([^"]+)"').firstMatch(tag)?.group(1);
    if (id != null && t != null) target[id] = t;
  }
  String paraText(String p) => _re(r'<a:t>(.*?)</a:t>').allMatches(p).map((t) => _unesc(t.group(1)!)).join().trim();

  final out = <Map<String, String>>[];
  final ids = RegExp(r'<p:sldId\b[^>]*r:id="([^"]+)"').allMatches(pres).map((m) => m.group(1)!).toList();
  for (int i = 0; i < ids.length; i++) {
    final t = target[ids[i]];
    if (t == null) continue;
    final path = t.startsWith('/') ? t.substring(1) : 'ppt/${t.replaceFirst(RegExp(r'^(\./)?'), '')}';
    final x = _text(z, path);
    if (x == null) continue;
    var title = '';
    var isTitle = false;
    final body = <String>[];
    for (final sp in _re(r'<p:sp>.*?</p:sp>').allMatches(x)) {
      final s = sp.group(0)!;
      final ph = RegExp(r'<p:ph\b([^>]*)/?>').firstMatch(s);
      final type = ph == null ? '' : (RegExp(r'type="(\w+)"').firstMatch(ph.group(1)!)?.group(1) ?? 'body');
      final paras = [for (final p in _re(r'<a:p>.*?</a:p>').allMatches(s)) paraText(p.group(0)!)].where((p) => p.isNotEmpty).toList();
      if (paras.isEmpty || type == 'sldNum' || type == 'dt' || type == 'ftr') continue;
      if ((type == 'title' || type == 'ctrTitle') && title.isEmpty) {
        title = paras.join(' ');
        isTitle = type == 'ctrTitle';
      } else {
        body.addAll(paras);
      }
    }
    if (title.isEmpty && body.isNotEmpty) title = body.removeAt(0);

    // speaker notes
    var notes = '';
    final relPath = '${path.substring(0, path.lastIndexOf('/'))}/_rels/${path.substring(path.lastIndexOf('/') + 1)}.rels';
    final sr = _text(z, relPath);
    final nt = sr == null ? null : RegExp(r'Target="([^"]*notesSlide[^"]*)"').firstMatch(sr)?.group(1);
    if (nt != null) {
      final nx = _text(z, 'ppt/notesSlides/${nt.split('/').last}');
      if (nx != null) {
        for (final sp in _re(r'<p:sp>.*?</p:sp>').allMatches(nx)) {
          if (!sp.group(0)!.contains('type="body"')) continue;
          notes = [for (final p in _re(r'<a:p>.*?</a:p>').allMatches(sp.group(0)!)) paraText(p.group(0)!)].join('\n').trim();
        }
      }
    }
    out.add({
      'title': title,
      'content': body.join('\n'),
      'layout': isTitle || (i == 0 && body.length <= 2) ? 'title' : 'title_content',
      'notes': notes,
    });
  }
  return out;
}

