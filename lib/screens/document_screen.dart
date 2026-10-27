// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:master_admin/core/app_palette.dart';

import '../core/table_export.dart';
import '../widgets/office_shell.dart';

/// Official Documents (Word style): the original hub + ribbon layout, with a
/// real formatting toolbar, templates, autosave, right-click menu, shortcuts,
/// view modes, zoom, PDF download and print preview. Documents are private.
class DocumentScreen extends StatefulWidget {
  final String title, userEmail, userRole;
  const DocumentScreen({super.key, required this.title, required this.userEmail, required this.userRole});
  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

const Color _kPurple = Color(0xFF4A148C);

// ---------------------------------------------------------------------------
// Templates (Quill delta)
// ---------------------------------------------------------------------------
List<Map<String, dynamic>> _h(String text, int level) => [
      {'insert': text},
      {
        'insert': '\n',
        'attributes': {'header': level}
      },
    ];
List<Map<String, dynamic>> _p(String text) => [
      {'insert': '$text\n'}
    ];
List<Map<String, dynamic>> _center(String text, {bool bold = false}) => [
      {
        'insert': text,
        if (bold) 'attributes': {'bold': true}
      },
      {
        'insert': '\n',
        'attributes': {'align': 'center'}
      },
    ];
List<Map<String, dynamic>> _bullets(List<String> items) => [
      for (final i in items) ...[
        {'insert': i},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'}
        },
      ]
    ];
List<Map<String, dynamic>> _numbers(List<String> items) => [
      for (final i in items) ...[
        {'insert': i},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'}
        },
      ]
    ];
List<Map<String, dynamic>> _checks(List<String> items) => [
      for (final i in items) ...[
        {'insert': i},
        {
          'insert': '\n',
          'attributes': {'list': 'unchecked'}
        },
      ]
    ];
List<Map<String, dynamic>> _boldLine(String label, String rest) => [
      {
        'insert': label,
        'attributes': {'bold': true}
      },
      {'insert': '$rest\n'},
    ];

String _today() => DateFormat('d MMMM yyyy').format(DateTime.now());

final Map<String, List<Map<String, dynamic>> Function()> _templateContent = {
  'blank': () => [
        {'insert': '\n'}
      ],
  'minutes': () => [
        ..._h('Meeting Minutes', 1),
        ..._boldLine('Date: ', _today()),
        ..._boldLine('Venue: ', ''),
        ..._boldLine('Chaired by: ', ''),
        ..._boldLine('Minutes by: ', ''),
        ..._h('Attendance', 2),
        ..._bullets(['Present: ', 'Absent with apology: ']),
        ..._h('Agenda', 2),
        ..._numbers(['Opening prayer', 'Review of last minutes', '', 'Closing prayer']),
        ..._h('Decisions', 2),
        ..._bullets(['']),
        ..._h('Action points', 2),
        ..._checks(['Who / what / by when']),
      ],
  'report': () => [
        ..._h('Activity Report', 1),
        ..._boldLine('Unit: ', ''),
        ..._boldLine('Period: ', ''),
        ..._boldLine('Prepared by: ', ''),
        ..._h('1. Summary', 2),
        ..._p(''),
        ..._h('2. Key figures', 2),
        ..._bullets(['Attendance: ', 'Evangelism: ', 'Offering: ', 'Education: ']),
        ..._h('3. Highlights', 2),
        ..._p(''),
        ..._h('4. Challenges', 2),
        ..._p(''),
        ..._h('5. Plans for next period', 2),
        ..._p(''),
      ],
  'letter': () => [
        ..._p('Shincheonji Church of Jesus'),
        ..._p(_today()),
        ..._p(''),
        ..._p('To: '),
        ..._p(''),
        ..._boldLine('Subject: ', ''),
        ..._p(''),
        ..._p('Dear ,'),
        ..._p(''),
        ..._p(''),
        ..._p('Yours faithfully,'),
        ..._p(''),
        ..._p(''),
      ],
  'memo': () => [
        ..._h('MEMO', 1),
        ..._boldLine('To: ', ''),
        ..._boldLine('From: ', ''),
        ..._boldLine('Date: ', _today()),
        ..._boldLine('Subject: ', ''),
        ..._p('────────────────────────────'),
        ..._p(''),
      ],
  'announcement': () => [
        ..._h('Announcement', 1),
        ..._p(''),
        ..._boldLine('When: ', ''),
        ..._boldLine('Where: ', ''),
        ..._boldLine('Who: ', ''),
        ..._h('Details', 2),
        ..._p(''),
        ..._boldLine('Contact: ', ''),
      ],
  'lesson': () => [
        ..._h('Lesson / Sermon Notes', 1),
        ..._boldLine('Title: ', ''),
        ..._boldLine('Speaker: ', ''),
        ..._boldLine('Date: ', _today()),
        ..._h('Key verse', 2),
        {'insert': '\n', 'attributes': {'blockquote': true}},
        ..._h('Main points', 2),
        ..._numbers(['', '', '']),
        ..._h('Application', 2),
        ..._p(''),
      ],
  'programme': () => [
        ..._center('ORDER OF SERVICE / PROGRAMME', bold: true),
        ..._center(_today()),
        ..._p(''),
        ..._numbers(['Opening prayer — ', 'Praise — ', 'Welcome — ', 'Message — ', 'Announcements — ', 'Closing prayer — ']),
        ..._p(''),
        ..._boldLine('MC: ', ''),
      ],
  'plan': () => [
        ..._h('Weekly Plan', 1),
        ..._boldLine('Week of: ', _today()),
        for (final d in const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']) ...[
          ..._h(d, 3),
          ..._checks(['']),
        ],
      ],
  'certificate': () => [
        ..._p(''),
        ..._center('CERTIFICATE OF APPRECIATION', bold: true),
        ..._p(''),
        ..._center('This certificate is presented to'),
        ..._p(''),
        ..._center('[ Name ]', bold: true),
        ..._p(''),
        ..._center('in recognition of'),
        ..._center(''),
        ..._p(''),
        ..._center('Given on ${_today()}'),
        ..._p(''),
        ..._p('______________________                ______________________'),
        ..._p('Signature                                         Signature'),
      ],
};

const List<OfficeTemplate> _templates = [
  OfficeTemplate('blank', 'Blank document', 'Start from an empty page', Icons.note_add_outlined),
  OfficeTemplate('minutes', 'Meeting minutes', 'Attendance, agenda, decisions, actions', Icons.groups_outlined),
  OfficeTemplate('report', 'Activity report', 'Summary, figures, highlights, plans', Icons.assessment_outlined),
  OfficeTemplate('letter', 'Letter', 'Formal letter layout', Icons.mail_outline_rounded),
  OfficeTemplate('memo', 'Memo', 'To, from, date and subject', Icons.sticky_note_2_outlined),
  OfficeTemplate('announcement', 'Announcement', 'Title, when, where, details', Icons.campaign_outlined),
  OfficeTemplate('lesson', 'Lesson / sermon notes', 'Verse, main points, application', Icons.menu_book_outlined),
  OfficeTemplate('programme', 'Programme', 'Order of service or event', Icons.event_note_outlined),
  OfficeTemplate('plan', 'Weekly plan', 'A checklist for each day', Icons.view_week_outlined),
  OfficeTemplate('certificate', 'Certificate', 'Certificate of appreciation', Icons.workspace_premium_outlined),
];

const Map<String, String> _templateTitles = {
  'blank': 'Untitled document',
  'minutes': 'Meeting minutes',
  'report': 'Activity report',
  'letter': 'Letter',
  'memo': 'Memo',
  'announcement': 'Announcement',
  'lesson': 'Lesson notes',
  'programme': 'Programme',
  'plan': 'Weekly plan',
  'certificate': 'Certificate',
};

class _DocumentScreenState extends State<DocumentScreen> {
  final _db = Supabase.instance.client;

  // hub
  List<Map<String, dynamic>> _docs = [];
  bool _loadingDocs = true;
  String _search = '';

  // editor
  bool _open = false;
  String? _docId;
  final _titleC = TextEditingController();
  QuillController _controller = QuillController.basic();
  StreamSubscription? _changes;
  final _focus = FocusNode();
  final _vScroll = ScrollController();
  final _hScroll = ScrollController();
  Timer? _saveTimer;
  String _saveState = 'saved'; // saved | saving | unsaved | error
  int _words = 0, _chars = 0, _paragraphs = 0;

  // layout
  int _tab = 1; // File, Home, Insert, Layout, Review, View
  double _zoom = 1.0;
  String _view = 'print'; // print | read | web
  String _margins = 'normal'; // narrow | normal | wide
  bool _ruler = true;

  @override
  void initState() {
    super.initState();
    OfficeBrowserMenu.acquire();
    _loadDocs();
  }

  @override
  void dispose() {
    OfficeBrowserMenu.release();
    _saveTimer?.cancel();
    _changes?.cancel();
    if (_open && _saveState == 'unsaved') _save();
    _controller.dispose();
    _titleC.dispose();
    _focus.dispose();
    _vScroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Data
  // ------------------------------------------------------------------
  Future<void> _loadDocs() async {
    setState(() => _loadingDocs = true);
    try {
      final res = await _db.from('documents').select('id, title, word_count, last_modified, created_at').order('last_modified', ascending: false);
      if (!mounted) return;
      setState(() {
        _docs = List<Map<String, dynamic>>.from(res);
        _loadingDocs = false;
      });
    } catch (e) {
      debugPrint("Docs load error: $e");
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  void _attach(QuillController c) {
    _changes?.cancel();
    _controller.dispose();
    _controller = c;
    _controller.readOnly = _view == 'read';
    _countWords();
    _changes = _controller.document.changes.listen((_) {
      _countWords();
      _dirty();
    });
  }

  void _dirty() {
    if (mounted) setState(() => _saveState = 'unsaved');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  void _countWords() {
    final text = _controller.document.toPlainText();
    final t = text.trim();
    _words = t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
    _chars = t.replaceAll('\n', '').length;
    _paragraphs = text.split('\n').where((l) => l.trim().isNotEmpty).length;
  }

  int get _pages => (_words / 450).ceil().clamp(1, 999);

  Future<void> _create(OfficeTemplate t) async {
    final title = _templateTitles[t.key] ?? t.name;
    final content = (_templateContent[t.key] ?? _templateContent['blank']!)();
    try {
      final row = await _db.from('documents').insert({'title': title, 'owner_email': widget.userEmail, 'content': content, 'word_count': 0}).select('id').single();
      await _openDoc(row['id'].toString());
    } catch (e) {
      _snack("Couldn't create the document: ${e is PostgrestException ? e.message : e}");
    }
  }

  Future<void> _pickTemplate() async {
    final t = await showOfficeTemplates(context, title: "Document templates", templates: _templates, accent: _kPurple);
    if (t != null) {
      if (_open) await _close();
      await _create(t);
    }
  }

  Future<void> _openDoc(String id) async {
    try {
      final row = await _db.from('documents').select().eq('id', id).single();
      QuillController c;
      try {
        final content = row['content'];
        c = (content is List && content.isNotEmpty)
            ? QuillController(document: Document.fromJson(content), selection: const TextSelection.collapsed(offset: 0))
            : QuillController.basic();
      } catch (_) {
        c = QuillController.basic();
      }
      setState(() {
        _docId = id;
        _titleC.text = (row['title'] ?? 'Untitled document').toString();
        _attach(c);
        _saveState = 'saved';
        _open = true;
      });
    } catch (e) {
      _snack("Couldn't open the document.");
    }
  }

  Future<void> _save() async {
    if (_docId == null) return;
    _saveTimer?.cancel();
    if (mounted) setState(() => _saveState = 'saving');
    try {
      await _db.from('documents').update({
        'title': _titleC.text.trim().isEmpty ? 'Untitled document' : _titleC.text.trim(),
        'content': _controller.document.toDelta().toJson(),
        'word_count': _words,
        'last_modified': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _docId!);
      if (mounted) setState(() => _saveState = 'saved');
    } catch (e) {
      debugPrint("Doc save error: $e");
      if (mounted) setState(() => _saveState = 'error');
    }
  }

  Future<void> _close() async {
    if (_saveState != 'saved') await _save();
    if (!mounted) return;
    setState(() => _open = false);
    _loadDocs();
  }

  Future<void> _rename(Map<String, dynamic> d) async {
    final name = await officeAsk(context, "Rename document", (d['title'] ?? '').toString(), ok: "Rename");
    if (name == null || name.isEmpty) return;
    await _db.from('documents').update({'title': name}).eq('id', d['id']);
    if (_open && _docId == d['id'].toString()) _titleC.text = name;
    _loadDocs();
  }

  Future<void> _duplicate(Map<String, dynamic> d) async {
    try {
      final full = await _db.from('documents').select().eq('id', d['id']).single();
      await _db.from('documents').insert({
        'title': "${full['title'] ?? 'Document'} (copy)",
        'owner_email': widget.userEmail,
        'content': full['content'],
        'word_count': full['word_count'],
      });
      _loadDocs();
      _snack("Copy made.");
    } catch (_) {
      _snack("Couldn't duplicate it.");
    }
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    if (!await officeConfirm(context, "Delete \"${d['title']}\"?", "This can't be undone.")) return;
    await _db.from('documents').delete().eq('id', d['id']);
    _loadDocs();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  // ------------------------------------------------------------------
  // PDF (headings, bold / italic / underline, alignment, lists, quotes)
  // ------------------------------------------------------------------
  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    pw.ThemeData theme;
    try {
      theme = pw.ThemeData.withFont(
        base: await PdfGoogleFonts.merriweatherRegular(),
        bold: await PdfGoogleFonts.merriweatherBold(),
        italic: await PdfGoogleFonts.merriweatherItalic(),
        boldItalic: await PdfGoogleFonts.merriweatherBoldItalic(),
        fontFallback: [await PdfGoogleFonts.notoSansKRRegular()],
      );
    } catch (_) {
      theme = pw.ThemeData();
    }
    final doc = pw.Document(theme: theme, title: _titleC.text.trim());
    final ops = _controller.document.toDelta().toJson();
    final lines = <(List<(String, Map)>, Map)>[];
    var current = <(String, Map)>[];
    for (final op in ops) {
      final insert = op['insert'];
      if (insert is! String) continue;
      final attrs = (op['attributes'] as Map?) ?? const {};
      final parts = insert.split('\n');
      for (int i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) current.add((parts[i], attrs));
        if (i < parts.length - 1) {
          lines.add((current, attrs));
          current = [];
        }
      }
    }
    if (current.isNotEmpty) lines.add((current, const {}));

    PdfColor? colorOf(dynamic v) {
      final s = (v ?? '').toString().replaceFirst('#', '');
      final n = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
      return n == null ? null : PdfColor.fromInt(n);
    }

    int number = 0;
    final widgets = <pw.Widget>[];
    for (final (spans, lineAttrs) in lines) {
      final header = lineAttrs['header'];
      final list = lineAttrs['list'];
      final align = lineAttrs['align'];
      final quote = lineAttrs['blockquote'] == true;
      number = list == 'ordered' ? number + 1 : 0;
      final size = header == 1 ? 22.0 : header == 2 ? 17.0 : header == 3 ? 14.0 : 11.5;
      final text = pw.RichText(
        textAlign: align == 'center'
            ? pw.TextAlign.center
            : align == 'right'
                ? pw.TextAlign.right
                : align == 'justify'
                    ? pw.TextAlign.justify
                    : pw.TextAlign.left,
        text: pw.TextSpan(children: [
          for (final (t, a) in spans)
            pw.TextSpan(
              text: t,
              style: pw.TextStyle(
                fontSize: double.tryParse((a['size'] ?? '').toString()) ?? size,
                color: colorOf(a['color']),
                background: colorOf(a['background']) == null ? null : pw.BoxDecoration(color: colorOf(a['background'])),
                fontWeight: (a['bold'] == true || header != null) ? pw.FontWeight.bold : pw.FontWeight.normal,
                fontStyle: a['italic'] == true ? pw.FontStyle.italic : pw.FontStyle.normal,
                decoration: a['underline'] == true ? pw.TextDecoration.underline : (a['strike'] == true ? pw.TextDecoration.lineThrough : null),
              ),
            ),
        ]),
      );
      final marker = list == 'ordered'
          ? '$number.'
          : list == 'checked'
              ? '☑'
              : list == 'unchecked'
                  ? '☐'
                  : '•';
      pw.Widget line = list == null
          ? text
          : pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(width: 18, child: pw.Text(marker, style: pw.TextStyle(fontSize: size))),
              pw.Expanded(child: text),
            ]);
      if (quote) {
        line = pw.Container(
          padding: const pw.EdgeInsets.only(left: 10),
          decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(color: PdfColors.grey500, width: 3))),
          child: line,
        );
      }
      widgets.add(pw.Padding(padding: pw.EdgeInsets.only(top: header != null ? 10 : 2, bottom: 2), child: line));
    }
    final m = _margins == 'narrow' ? 28.0 : _margins == 'wide' ? 72.0 : 48.0;
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: pw.EdgeInsets.all(m),
      build: (_) => widgets.isEmpty ? [pw.Text('')] : widgets,
    ));
    return doc.save();
  }

  String get _fileName => (_titleC.text.trim().isEmpty ? 'document' : _titleC.text.trim()).replaceAll(RegExp(r'[^A-Za-z0-9가-힣 _-]'), '');

  Future<void> _exportPdf() async {
    try {
      final bytes = await _buildPdf(PdfPageFormat.a4);
      await Printing.sharePdf(bytes: bytes, filename: '$_fileName.pdf');
    } catch (e) {
      _snack("Couldn't make the PDF.");
    }
  }

  Future<void> _print() => TableExport.previewBuilder(context, _titleC.text.trim().isEmpty ? 'Document' : _titleC.text.trim(), _buildPdf, fileName: '$_fileName.pdf');

  // ------------------------------------------------------------------
  // Editing commands (ribbon, right-click menu, shortcuts)
  // ------------------------------------------------------------------
  bool _has(String key) => _controller.getSelectionStyle().attributes.containsKey(key);
  String? _val(String key) => _controller.getSelectionStyle().attributes[key]?.value?.toString();

  void _toggle(Attribute a) {
    final on = _controller.getSelectionStyle().attributes[a.key]?.value == a.value;
    _controller.formatSelection(on ? Attribute.clone(a, null) : a);
    _focus.requestFocus();
  }

  void _block(Attribute a) => _toggle(a);

  void _heading(int? level) {
    _controller.formatSelection(level == 1
        ? Attribute.h1
        : level == 2
            ? Attribute.h2
            : level == 3
                ? Attribute.h3
                : Attribute.header);
    _focus.requestFocus();
  }

  void _align(Attribute a) {
    _controller.formatSelection(a);
    _focus.requestFocus();
  }

  void _clearFormatting() {
    for (final Attribute a in <Attribute>[Attribute.bold, Attribute.italic, Attribute.underline, Attribute.strikeThrough, Attribute.color, Attribute.background, Attribute.size, Attribute.font, Attribute.link]) {
      if (_has(a.key)) _controller.formatSelection(Attribute.clone(a, null));
    }
    _focus.requestFocus();
  }

  TextSelection get _sel {
    final s = _controller.selection;
    if (s.start < 0) return const TextSelection.collapsed(offset: 0);
    return s;
  }

  String _selectedText() {
    final s = _sel;
    if (s.isCollapsed) return '';
    return _controller.document.getPlainText(s.start, s.end - s.start);
  }

  Future<void> _copy({bool cut = false}) async {
    final s = _sel;
    final text = _selectedText();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (cut && !_controller.readOnly) _controller.replaceText(s.start, s.end - s.start, '', TextSelection.collapsed(offset: s.start));
    _focus.requestFocus();
  }

  Future<void> _paste() async {
    if (_controller.readOnly) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.isEmpty) return;
    final s = _sel;
    _controller.replaceText(s.start, s.end - s.start, t, TextSelection.collapsed(offset: s.start + t.length));
    _focus.requestFocus();
  }

  void _selectAll() {
    _controller.updateSelection(TextSelection(baseOffset: 0, extentOffset: _controller.document.length - 1), ChangeSource.local);
    _focus.requestFocus();
  }

  void _insertText(String t) {
    if (_controller.readOnly) return;
    final s = _sel;
    _controller.replaceText(s.start, s.end - s.start, t, TextSelection.collapsed(offset: s.start + t.length));
    _focus.requestFocus();
  }

  Future<void> _link() async {
    final current = _val(Attribute.link.key) ?? '';
    final url = await officeAsk(context, "Hyperlink", current, ok: "Apply", hint: "https://…");
    if (url == null) return;
    if (_sel.isCollapsed && url.isNotEmpty) {
      final s = _sel;
      _controller.replaceText(s.start, 0, url, TextSelection(baseOffset: s.start, extentOffset: s.start + url.length));
    }
    _controller.formatSelection(url.isEmpty ? Attribute.clone(Attribute.link, null) : LinkAttribute(url));
    _focus.requestFocus();
  }

  Future<void> _web(String base) async {
    final q = _selectedText().trim();
    if (q.isEmpty) {
      _snack("Select a word or sentence first.");
      return;
    }
    await launchUrl(Uri.parse('$base${Uri.encodeComponent(q)}'), mode: LaunchMode.externalApplication);
  }

  void _wordCount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Word count"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (k, v) in [
            ('Pages (about)', '$_pages'),
            ('Words', '$_words'),
            ('Characters (no spaces)', '${_controller.document.toPlainText().replaceAll(RegExp(r'\s'), '').length}'),
            ('Characters (with spaces)', '$_chars'),
            ('Paragraphs', '$_paragraphs'),
          ])
            ListTile(dense: true, title: Text(k), trailing: Text(v, style: const TextStyle(fontWeight: FontWeight.bold))),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
      ),
    );
  }

  void _setView(String v) {
    setState(() {
      _view = v;
      _controller.readOnly = v == 'read';
    });
  }

  void _setZoom(double z) => setState(() => _zoom = (z * 10).round() / 10);

  Future<void> _rightClick(Offset pos) {
    final ro = _controller.readOnly;
    return showOfficeMenu(context, pos, [
      OfficeMenuItem("Cut", icon: Icons.content_cut, shortcut: "Ctrl+X", onTap: ro ? null : () => _copy(cut: true)),
      OfficeMenuItem("Copy", icon: Icons.content_copy, shortcut: "Ctrl+C", onTap: () => _copy()),
      OfficeMenuItem("Paste", icon: Icons.content_paste, shortcut: "Ctrl+V", color: Colors.orange.shade800, onTap: ro ? null : _paste),
      OfficeMenuItem("Select all", icon: Icons.select_all, shortcut: "Ctrl+A", onTap: _selectAll),
      const OfficeMenuItem.divider(),
      OfficeMenuItem("Bold", icon: Icons.format_bold, shortcut: "Ctrl+B", onTap: ro ? null : () => _toggle(Attribute.bold)),
      OfficeMenuItem("Italic", icon: Icons.format_italic, shortcut: "Ctrl+I", onTap: ro ? null : () => _toggle(Attribute.italic)),
      OfficeMenuItem("Underline", icon: Icons.format_underline, shortcut: "Ctrl+U", onTap: ro ? null : () => _toggle(Attribute.underline)),
      OfficeMenuItem("Clear formatting", icon: Icons.format_clear, shortcut: "Ctrl+\\", onTap: ro ? null : _clearFormatting),
      const OfficeMenuItem.divider(),
      OfficeMenuItem("Heading 1", icon: Icons.title, onTap: ro ? null : () => _heading(1)),
      OfficeMenuItem("Heading 2", icon: Icons.text_fields, onTap: ro ? null : () => _heading(2)),
      OfficeMenuItem("Normal text", icon: Icons.notes, onTap: ro ? null : () => _heading(null)),
      OfficeMenuItem("Bullets", icon: Icons.format_list_bulleted, shortcut: "Ctrl+Shift+8", onTap: ro ? null : () => _block(Attribute.ul)),
      OfficeMenuItem("Numbering", icon: Icons.format_list_numbered, shortcut: "Ctrl+Shift+7", onTap: ro ? null : () => _block(Attribute.ol)),
      OfficeMenuItem("Checklist", icon: Icons.checklist, shortcut: "Ctrl+Shift+9", onTap: ro ? null : () => _block(Attribute.unchecked)),
      OfficeMenuItem("Paragraph: centre", icon: Icons.format_align_center, shortcut: "Ctrl+E", onTap: ro ? null : () => _align(Attribute.centerAlignment)),
      const OfficeMenuItem.divider(),
      OfficeMenuItem("Hyperlink…", icon: Icons.link, shortcut: "Ctrl+K", onTap: ro ? null : _link),
      OfficeMenuItem("Insert date", icon: Icons.today_outlined, onTap: ro ? null : () => _insertText(_today())),
      OfficeMenuItem("Look up", icon: Icons.search, onTap: () => _web('https://www.google.com/search?q=')),
      OfficeMenuItem("Translate", icon: Icons.translate, onTap: () => _web('https://translate.google.com/?sl=auto&tl=en&text=')),
      const OfficeMenuItem.divider(),
      OfficeMenuItem("Word count", icon: Icons.numbers, onTap: _wordCount),
    ]);
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _open ? _editor() : _hub());

  String _when(dynamic v) {
    final t = DateTime.tryParse((v ?? '').toString())?.toLocal();
    if (t == null) return '—';
    final now = DateTime.now();
    if (now.difference(t).inHours < 24 && now.day == t.day) return "today ${DateFormat('HH:mm').format(t)}";
    return DateFormat('d MMM yyyy').format(t);
  }

  Widget _hub() {
    final q = _search.trim().toLowerCase();
    final docs = q.isEmpty ? _docs : _docs.where((d) => (d['title'] ?? '').toString().toLowerCase().contains(q)).toList();
    return CallbackShortcuts(
      key: const ValueKey('hub'),
      bindings: officeKeys({LogicalKeyboardKey.keyN: () => _create(_templates.first)}),
      child: Focus(
        autofocus: true,
        child: OfficeHub(
          title: "Official Documents Hub",
          accent: _kPurple,
          accent2: Colors.indigo,
          actions: [
            OfficeHubAction("New Document", Icons.add, Colors.blue, () => _create(_templates.first)),
            OfficeHubAction("Open Existing", Icons.folder, Colors.orange, () => _snack("Pick a document from “My documents”, or search for it.")),
            OfficeHubAction("Templates", Icons.auto_stories, Colors.green, _pickTemplate),
          ],
          templates: _templates,
          onTemplate: _create,
          onAllTemplates: _pickTemplate,
          files: docs,
          loading: _loadingDocs,
          searchHint: "Search my documents…",
          emptyText: _docs.isEmpty ? "No documents yet. Start one from a template." : "No documents match.",
          onSearch: (v) => setState(() => _search = v),
          fileIcon: Icons.description_rounded,
          fileIconColor: Colors.blue,
          fileSubtitle: (d) => "Words: ${d['word_count'] ?? 0} • Last sync: ${_when(d['last_modified'] ?? d['created_at'])}",
          onOpen: (d) => _openDoc(d['id'].toString()),
          fileMenu: (d) => [
            OfficeMenuItem("Open", icon: Icons.open_in_new, onTap: () => _openDoc(d['id'].toString())),
            OfficeMenuItem("Rename", icon: Icons.drive_file_rename_outline, onTap: () => _rename(d)),
            OfficeMenuItem("Make a copy", icon: Icons.copy_rounded, onTap: () => _duplicate(d)),
            const OfficeMenuItem.divider(),
            OfficeMenuItem("Delete", icon: Icons.delete_outline, color: Colors.red.shade700, onTap: () => _delete(d)),
          ],
          onRefresh: _loadDocs,
          guideIcon: Icons.cloud_done,
          guideLines: const [
            "Page and word count update as you type.",
            "Right-click the page for Word-style options: cut, copy, paste, styles, lists, links, look up and translate.",
            "Saves to the cloud automatically (Ctrl+S saves now).",
            "Ctrl+P prints with a preview; File ▸ Download PDF.",
            "Ctrl+N starts a new document. Your documents are private to your account.",
          ],
        ),
      ),
    );
  }

  List<OfficeRibbonTab> _ribbonTabs(bool wide) {
    final ro = _controller.readOnly;
    OfficeAction a(IconData i, String l, VoidCallback? f, {String? tip, bool sel = false}) => OfficeAction(i, l, f, tooltip: tip, accent: _kPurple, selected: sel);
    return [
      OfficeRibbonTab("File", () => [
            a(Icons.note_add_outlined, "New", _pickTemplate, tip: "New from a template"),
            a(Icons.folder_open, "Open", _close, tip: "Back to my documents"),
            a(Icons.cloud_upload_outlined, "Save", _save, tip: "Ctrl+S"),
            a(Icons.drive_file_rename_outline, "Rename", () async {
              final n = await officeAsk(context, "Rename document", _titleC.text, ok: "Rename");
              if (n != null && n.isNotEmpty) {
                _titleC.text = n;
                _dirty();
              }
            }),
            a(Icons.copy_rounded, "Make a copy", _docId == null ? null : () => _duplicate({'id': _docId})),
            const OfficeRibbonGap(),
            a(Icons.picture_as_pdf_outlined, "Download PDF", _exportPdf),
            a(Icons.print_outlined, "Print", _print, tip: "Ctrl+P"),
            const OfficeRibbonGap(),
            a(Icons.close, "Close", _close),
          ]),
      OfficeRibbonTab(
        "Home",
        () => const [],
        custom: () => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: QuillSimpleToolbar(
            controller: _controller,
            config: QuillSimpleToolbarConfig(
              multiRowsDisplay: false,
              showSearchButton: true,
              showSubscript: false,
              showSuperscript: false,
            ),
          ),
        ),
      ),
      OfficeRibbonTab("Insert", () => [
            a(Icons.today_outlined, "Date", ro ? null : () => _insertText(_today())),
            a(Icons.schedule, "Time", ro ? null : () => _insertText(DateFormat('HH:mm').format(DateTime.now()))),
            a(Icons.link, "Link", ro ? null : _link, tip: "Ctrl+K"),
            const OfficeRibbonGap(),
            a(Icons.checklist, "Checklist", ro ? null : () => _block(Attribute.unchecked)),
            a(Icons.format_quote, "Quote", ro ? null : () => _block(Attribute.blockQuote)),
            a(Icons.code, "Code block", ro ? null : () => _block(Attribute.codeBlock)),
            a(Icons.horizontal_rule, "Line", ro ? null : () => _insertText('\n────────────────────────────\n')),
            OfficeMenuAction<String>(Icons.emoji_symbols, "Symbol", const [('©', '© Copyright'), ('®', '® Registered'), ('™', '™ Trademark'), ('•', '• Bullet'), ('→', '→ Arrow'), ('✓', '✓ Tick'), ('✗', '✗ Cross'), ('§', '§ Section'), ('°', '° Degree'), ('UGX ', 'UGX')], (v) => _insertText(v), accent: _kPurple),
            a(Icons.draw_outlined, "Signature block", ro ? null : () => _insertText('\n\n______________________\nName:\nTitle:\nDate: ${_today()}\n')),
          ]),
      OfficeRibbonTab("Layout", () => [
            a(Icons.format_align_left, "Left", ro ? null : () => _align(Attribute.leftAlignment), sel: _val('align') == null),
            a(Icons.format_align_center, "Centre", ro ? null : () => _align(Attribute.centerAlignment), tip: "Ctrl+E", sel: _val('align') == 'center'),
            a(Icons.format_align_right, "Right", ro ? null : () => _align(Attribute.rightAlignment), tip: "Ctrl+R", sel: _val('align') == 'right'),
            a(Icons.format_align_justify, "Justify", ro ? null : () => _align(Attribute.justifyAlignment), tip: "Ctrl+J", sel: _val('align') == 'justify'),
            const OfficeRibbonGap(),
            a(Icons.format_indent_increase, "Indent", ro ? null : () => _controller.indentSelection(true)),
            a(Icons.format_indent_decrease, "Outdent", ro ? null : () => _controller.indentSelection(false)),
            const OfficeRibbonGap(),
            OfficeMenuAction<String>(Icons.border_outer, "Margins: ${_margins[0].toUpperCase()}${_margins.substring(1)}", const [('narrow', 'Narrow'), ('normal', 'Normal'), ('wide', 'Wide')], (v) => setState(() => _margins = v), accent: _kPurple),
          ]),
      OfficeRibbonTab("Review", () => [
            a(Icons.numbers, "Word count", _wordCount),
            a(Icons.format_clear, "Clear formatting", ro ? null : _clearFormatting, tip: "Ctrl+\\"),
            a(Icons.search, "Look up", () => _web('https://www.google.com/search?q=')),
            a(Icons.translate, "Translate", () => _web('https://translate.google.com/?sl=auto&tl=en&text=')),
            a(Icons.undo, "Undo", _controller.hasUndo ? _controller.undo : null, tip: "Ctrl+Z"),
            a(Icons.redo, "Redo", _controller.hasRedo ? _controller.redo : null, tip: "Ctrl+Y"),
          ]),
      OfficeRibbonTab("View", () => [
            a(Icons.description_outlined, "Print layout", () => _setView('print'), sel: _view == 'print'),
            a(Icons.menu_book_outlined, "Reading", () => _setView('read'), sel: _view == 'read'),
            a(Icons.web_asset_outlined, "Web layout", () => _setView('web'), sel: _view == 'web'),
            const OfficeRibbonGap(),
            a(Icons.zoom_in, "Zoom in", () => _setZoom((_zoom + 0.1).clamp(0.5, 2.0).toDouble()), tip: "Ctrl+="),
            a(Icons.zoom_out, "Zoom out", () => _setZoom((_zoom - 0.1).clamp(0.5, 2.0).toDouble()), tip: "Ctrl+-"),
            a(Icons.fit_screen_outlined, "100%", () => _setZoom(1.0), tip: "Ctrl+0"),
            a(Icons.straighten, _ruler ? "Hide ruler" : "Show ruler", () => setState(() => _ruler = !_ruler)),
          ]),
    ];
  }

  Widget _editor() {
    final status = officeSaveStatus(_saveState);
    return PopScope(
      key: const ValueKey('editor'),
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: CallbackShortcuts(
        bindings: officeKeys({
          LogicalKeyboardKey.keyS: _save,
          LogicalKeyboardKey.keyP: _print,
          LogicalKeyboardKey.keyK: _link,
          LogicalKeyboardKey.keyE: () => _align(Attribute.centerAlignment),
          LogicalKeyboardKey.keyR: () => _align(Attribute.rightAlignment),
          LogicalKeyboardKey.keyJ: () => _align(Attribute.justifyAlignment),
          LogicalKeyboardKey.keyL: () => _align(Attribute.leftAlignment),
          LogicalKeyboardKey.backslash: _clearFormatting,
          LogicalKeyboardKey.equal: () => _setZoom((_zoom + 0.1).clamp(0.5, 2.0).toDouble()),
          LogicalKeyboardKey.minus: () => _setZoom((_zoom - 0.1).clamp(0.5, 2.0).toDouble()),
          LogicalKeyboardKey.digit0: () => _setZoom(1.0),
        }, ctrlShift: {
          LogicalKeyboardKey.digit7: () => _block(Attribute.ol),
          LogicalKeyboardKey.digit8: () => _block(Attribute.ul),
          LogicalKeyboardKey.digit9: () => _block(Attribute.unchecked),
        }),
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final mobile = c.maxWidth < 600;
          final printLayout = _view == 'print' && wide;
          final basePage = _view == 'web' ? c.maxWidth - 40 : (wide ? 816.0 : c.maxWidth);
          final pageWidth = (_view == 'web' || !wide) ? basePage : basePage * _zoom;
          final hPad = !wide ? 16.0 : _view == 'web' ? 28.0 : (_margins == 'narrow' ? 40.0 : _margins == 'wide' ? 110.0 : 72.0) * _zoom;
          final tabs = _ribbonTabs(wide);
          return Scaffold(
            backgroundColor: AppPalette.bg(printLayout ? const Color(0xFFE5E7EB) : Colors.white),
            body: SafeArea(
              child: Column(children: [
                OfficeHeaderCard(
                  accent: _kPurple,
                  titleController: _titleC,
                  onTitleChanged: (_) => _dirty(),
                  subtitle: "Cloud Sync: ${widget.userEmail} · ${status.$1}",
                  subtitleColor: status.$3,
                  onClose: _close,
                  actions: [
                    IconButton(tooltip: tr("Save now (Ctrl+S)"), icon: Icon(status.$2, color: AppPalette.fg(status.$3)), onPressed: _save),
                    if (!mobile) IconButton(tooltip: tr("Print preview (Ctrl+P)"), icon: Icon(Icons.print_outlined, color: AppPalette.fg(Colors.blueGrey)), onPressed: _print),
                  ],
                ),
                if (_view != 'read')
                  OfficeRibbon(tabs: tabs, active: _tab, onTab: (i) => setState(() => _tab = i), accent: _kPurple, rowHeight: 42)
                else
                  Container(
                    width: double.infinity,
                    color: AppPalette.bg(const Color(0xFFF3E5F5)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Row(children: [
                      Icon(Icons.menu_book_outlined, size: 16, color: AppPalette.fg(_kPurple)),
                      const SizedBox(width: 8),
                      Expanded(child: Text("Reading mode — the document can't be changed here.", style: TextStyle(fontSize: 12, color: AppPalette.fg(_kPurple)))),
                      TextButton(onPressed: () => _setView('print'), child: const Text("Edit")),
                    ]),
                  ),
                if (_ruler && printLayout)
                  Container(
                    height: 18,
                    decoration: BoxDecoration(color: AppPalette.bg(Colors.white), border: Border(bottom: BorderSide(color: AppPalette.line(Colors.black12)))),
                    child: Center(child: SizedBox(width: pageWidth.clamp(100, c.maxWidth).toDouble(), child: CustomPaint(painter: OfficeRulerPainter(), size: const Size(double.infinity, 18)))),
                  ),
                Expanded(
                  child: Row(children: [
                    Expanded(
                      child: Scrollbar(
                        controller: _hScroll,
                        child: SingleChildScrollView(
                          controller: _hScroll,
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: c.maxWidth - (wide ? 18 : 0)),
                            child: SingleChildScrollView(
                              controller: _vScroll,
                              padding: EdgeInsets.symmetric(vertical: printLayout ? 28 : 8),
                              child: Center(
                                child: OfficeRightClick(
                                  onMenu: _rightClick,
                                  child: Container(
                                    width: pageWidth,
                                    constraints: BoxConstraints(minHeight: printLayout ? 1056 * _zoom : c.maxHeight - 200),
                                    margin: EdgeInsets.symmetric(horizontal: printLayout ? 20 : 0),
                                    padding: EdgeInsets.symmetric(horizontal: hPad, vertical: printLayout ? 64 * _zoom : 16),
                                    decoration: BoxDecoration(
                                      color: AppPalette.bg(Colors.white),
                                      boxShadow: printLayout ? const [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 10))] : null,
                                    ),
                                    child: MediaQuery(
                                      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_view == 'read' ? _zoom * 1.1 : _zoom)),
                                      child: QuillEditor.basic(
                                        controller: _controller,
                                        focusNode: _focus,
                                        config: QuillEditorConfig(
                                          placeholder: "Start typing…",
                                          scrollable: false,
                                          expands: false,
                                          padding: EdgeInsets.zero,
                                          // our own right-click menu replaces the editor's one on computers
                                          contextMenuBuilder: wide ? (ctx, editorState) => const SizedBox.shrink() : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (wide) OfficeScrollArrows.of(_vScroll, Axis.vertical),
                  ]),
                ),
                if (wide) OfficeScrollArrows.of(_hScroll, Axis.horizontal, leadingGap: 20),
                _statusBar(wide),
              ]),
            ),
          );
        }),
      ),
    );
  }

  Widget _statusBar(bool wide) {
    return Container(
      height: 34,
      color: AppPalette.bg(Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        AnimatedBuilder(
          animation: _vScroll,
          builder: (context, child) {
            int page = 1;
            if (_vScroll.hasClients && _vScroll.position.hasContentDimensions && _vScroll.position.maxScrollExtent > 0) {
              page = (_vScroll.offset / _vScroll.position.maxScrollExtent * (_pages - 1)).round() + 1;
            }
            return Text("Page $page of $_pages", style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold));
          },
        ),
        const VerticalDivider(width: 24, indent: 8, endIndent: 8),
        InkWell(onTap: _wordCount, child: Text("$_words words", style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
        if (wide) ...[
          const SizedBox(width: 12),
          Text("$_chars characters", style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.grey[700]))),
        ],
        const Spacer(),
        OfficeViewIcon(Icons.description_outlined, "Print layout", _view == 'print', () => _setView('print')),
        OfficeViewIcon(Icons.menu_book_outlined, "Reading mode", _view == 'read', () => _setView('read')),
        OfficeViewIcon(Icons.web_asset_outlined, "Web layout", _view == 'web', () => _setView('web')),
        const VerticalDivider(width: 20, indent: 8, endIndent: 8),
        OfficeZoomPill(zoom: _zoom, onChanged: _setZoom, onReset: () => _setZoom(1.0)),
      ]),
    );
  }
}
