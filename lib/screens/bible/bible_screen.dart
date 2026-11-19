import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/gestures.dart' show LongPressGestureRecognizer;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_palette.dart';
import '../../core/i18n.dart';
import '../../services/speech.dart';
import 'bible_library.dart';
import 'bible_reader.dart';

const Color _kPurple = Color(0xFF4A148C);
const Color _kGold = Color(0xFFB8860B);

/// The World English Bible (public domain), bundled with the app
/// (assets/bible/web.json): 66 books → chapters → verses.
class Bible {
  Bible._();
  static const version = 'World English Bible (WEB)';
  static List<BibleBook>? _books;
  static Future<List<BibleBook>>? _loading;

  static Future<List<BibleBook>> load() {
    if (_books != null) return Future.value(_books);
    return _loading ??= rootBundle.load('assets/bible/web.json').then((data) {
      final s = utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final j = jsonDecode(s) as Map<String, dynamic>;
      _books = [
        for (final (i, b) in (j['books'] as List).indexed)
          BibleBook(i, (b['n'] ?? '').toString(), (b['t'] ?? '').toString() == 'OT', [
            for (final c in (b['c'] as List)) List<String>.from(c as List),
          ]),
      ];
      return _books!;
    }).catchError((Object e) {
      _loading = null; // try again next time
      throw e;
    });
  }

  /// Well-loved verses for the verse of the day: (book index, chapter, verse).
  static const daily = <(int, int, int)>[
    (42, 3, 16), (18, 23, 1), (19, 3, 5), (49, 4, 13), (44, 8, 28), (22, 40, 31), (23, 29, 11), (39, 11, 28),
    (18, 46, 1), (43, 1, 9), (45, 13, 4), (18, 119, 105), (39, 6, 33), (48, 2, 8), (57, 11, 1), (64, 1, 9),
    (42, 14, 6), (49, 4, 6), (58, 1, 5), (59, 5, 7), (19, 16, 3), (22, 41, 10), (5, 1, 9), (18, 37, 4),
    (44, 12, 2), (46, 5, 17), (46, 12, 9), (42, 16, 33), (39, 5, 14), (18, 27, 1), (44, 15, 13), (57, 13, 8),
    (61, 4, 8), (42, 15, 13), (18, 34, 8), (22, 26, 3), (41, 1, 37), (49, 4, 19), (18, 121, 1), (39, 7, 7),
    (65, 21, 4), (43, 2, 38), (46, 4, 18), (51, 5, 16), (42, 11, 25), (18, 90, 12), (59, 4, 8), (44, 5, 8),
    (22, 53, 5), (39, 28, 20), (18, 100, 4), (48, 5, 22), (19, 18, 10), (61, 3, 18), (24, 3, 22), (32, 6, 8),
  ];

  static (int, int, int) dailyRef([int offset = 0]) {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day).difference(DateTime(2024)).inDays;
    return daily[(day + offset) % daily.length];
  }
}

class BibleBook {
  final int index;
  final String name;
  final bool oldTestament;
  final List<List<String>> chapters;
  const BibleBook(this.index, this.name, this.oldTestament, this.chapters);
}

/// Home › Bible: the verse of the day, then other well-loved verses rising
/// one after the other; tap to open the Bible there.
class BibleHomeCard extends StatefulWidget {
  const BibleHomeCard({super.key});
  @override
  State<BibleHomeCard> createState() => _BibleHomeCardState();
}

class _BibleHomeCardState extends State<BibleHomeCard> {
  List<BibleBook>? _books;
  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    Bible.load().then((b) {
      if (!mounted) return;
      setState(() => _books = b);
      _t = Timer.periodic(const Duration(seconds: 9), (_) {
        if (mounted) setState(() => _i = (_i + 1) % 6);
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    final ref = Bible.dailyRef(_i);
    final verse = books == null ? null : books[ref.$1].chapters[ref.$2 - 1][ref.$3 - 1];
    final where = books == null ? '' : "${books[ref.$1].name} ${ref.$2}:${ref.$3}";
    // a light card like the others in its column, raised from below
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppPalette.bg(Theme.of(context).colorScheme.surface),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.line(_kPurple.withValues(alpha: 0.10)), width: 1.2),
        boxShadow: [
          BoxShadow(color: _kPurple.withValues(alpha: 0.16), blurRadius: 22, spreadRadius: -4, offset: const Offset(0, 10)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // the card opens the Bible (books); the verse opens that verse
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BibleLibraryScreen())),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.menu_book_rounded, color: AppPalette.fg(_kGold), size: 20),
                const SizedBox(width: 6),
                Expanded(child: Text("Holy Bible", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: AppPalette.fg(_kPurple)))),
                Text(_i == 0 ? "Verse of the day" : "Words of life", style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(_kGold))),
                Icon(Icons.chevron_right_rounded, color: AppPalette.fg(_kPurple)),
              ]),
              const Divider(height: 14),
              SizedBox(
                height: 66,
                child: verse == null
                    ? Center(child: Text("Tap to open the Bible", style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey))))
                    : ClipRect(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 700),
                          transitionBuilder: (child, anim) => SlideTransition(
                            position: Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                            child: FadeTransition(opacity: anim, child: child),
                          ),
                          child: GestureDetector(
                            key: ValueKey(where),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BibleScreen(book: ref.$1, chapter: ref.$2, verse: ref.$3))),
                            child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text("“$verse”",
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.merriweather(fontSize: 12.5, height: 1.45, fontStyle: FontStyle.italic, color: AppPalette.fg(const Color(0xFF263238)))),
                              ),
                              Text("— $where", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(_kPurple))),
                            ],
                          )),
                        ),
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The Bible: books (Old / New Testament), chapters, reading with verse
/// numbers, search (whole Bible, OT, NT or one book), listening to a chapter,
/// copying verses.
class BibleScreen extends StatefulWidget {
  final int? book, chapter, verse;
  const BibleScreen({super.key, this.book, this.chapter, this.verse});
  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  List<BibleBook>? _books;
  int _book = 42, _chapter = 1; // John 1
  int? _mark; // the verse to show (from a search or the Home card)
  final Set<int> _picked = {}; // verses picked for copying
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  double _size = 16;
  // reading style (Aa): font, line spacing, verse numbers, one verse per
  // line or as a paragraph, paper colour
  String _font = 'Merriweather';
  double _line = 1.75;
  bool _numbers = true, _paragraph = false;
  int _paperI = 0;
  static const _fonts = ['Merriweather', 'Lora', 'Noto Serif', 'EB Garamond', 'Open Sans', 'Nunito'];
  static const _papers = [(Color(0xFFFDFBF7), 'Cream'), (Colors.white, 'White'), (Color(0xFFF4ECD8), 'Sepia'), (Color(0xFFEFF4FA), 'Blue-grey')];
  Color get _paper => _papers[_paperI.clamp(0, _papers.length - 1)].$1;
  // highlights ("book:chapter:verse" → colour) and bookmarks, on this device
  Map<String, int> _hl = {};
  Set<String> _bm = {};
  static const _hlColors = [Color(0xFFFFF59D), Color(0xFFC8E6C9), Color(0xFFBBDEFB), Color(0xFFF8BBD0)];
  String _key(int v) => '$_book:$_chapter:$v';

  TextStyle _font0({double? size, FontWeight? weight, Color? color, double? height, FontStyle? style}) {
    try {
      return GoogleFonts.getFont(_font, fontSize: size, fontWeight: weight, color: color, height: height, fontStyle: style);
    } catch (_) {
      return GoogleFonts.merriweather(fontSize: size, fontWeight: weight, color: color, height: height, fontStyle: style);
    }
  }
  int? _reading; // the verse being read aloud
  bool _speaking = false, _paused = false;
  String? _error;

  BibleReader get _reader => BibleReader.instance;

  @override
  void initState() {
    super.initState();
    if (widget.book != null) BibleReaderBar.onBibleScreen.value = true;
    _reader.addListener(_onReader);
    _prefs();
    _open();
  }

  /// The background reader moved on (next verse, next chapter, stopped).
  void _onReader() {
    if (!mounted) return;
    final r = _reader;
    if (r.speaking && _follow && (r.book != _book || r.chapter != _chapter) && _books != null) {
      // it went on to the next chapter: follow it
      setState(() {
        _book = r.book;
        _chapter = r.chapter;
        _picked.clear();
        _keys.clear();
        _mark = null;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _remember();
    }
    final here = r.isReading(_book, _chapter);
    setState(() {
      _speaking = here;
      _paused = here && r.paused;
      _reading = here ? r.verse : null;
    });
    final k = _reading == null ? null : _keys[_reading];
    if (k?.currentContext != null) Scrollable.ensureVisible(k!.currentContext!, alignment: 0.3, duration: const Duration(milliseconds: 300));
  }

  /// This screen follows the reader to the next chapter (it was started here
  /// or the screen was opened on what is being read).
  bool _follow = false;

  void _open() {
    if (_error != null) setState(() => _error = null);
    Bible.load().then((b) {
      if (!mounted) return;
      setState(() {
        _books = b;
        if (widget.book != null) {
          _book = widget.book!;
          _chapter = widget.chapter ?? 1;
          _mark = widget.verse;
        }
      });
      if (_reader.isReading(_book, _chapter)) {
        _follow = true;
        _onReader();
      }
      _jumpToMark();
    }).catchError((e) {
      if (mounted) {
        setState(() => _error = "The Bible text could not be opened. Check that assets/bible/web.json is in the app (pubspec.yaml lists assets/bible/) and rebuild.");
      }
    });
  }

  Future<void> _prefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getDouble('bible_font');
      final last = p.getStringList('bible_last');
      final st = p.getStringList('bible_style');
      final hl = p.getStringList('bible_hl') ?? const [];
      final bm = p.getStringList('bible_bm') ?? const [];
      if (!mounted) return;
      setState(() {
        if (s != null) _size = s;
        if (st != null && st.length >= 5) {
          _font = _fonts.contains(st[0]) ? st[0] : _font;
          _line = double.tryParse(st[1]) ?? _line;
          _numbers = st[2] != '0';
          _paragraph = st[3] == '1';
          _paperI = int.tryParse(st[4]) ?? 0;
        }
        _hl = {for (final x in hl) if (x.contains('=')) x.split('=').first: int.tryParse(x.split('=').last) ?? 0};
        _bm = bm.toSet();
        if (widget.book == null && last != null && last.length == 2) {
          _book = int.tryParse(last[0]) ?? _book;
          _chapter = int.tryParse(last[1]) ?? _chapter;
        }
      });
    } catch (_) {}
  }

  Future<void> _remember() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('bible_last', ['$_book', '$_chapter']);
      await p.setDouble('bible_font', _size);
      await p.setStringList('bible_style', [_font, '$_line', _numbers ? '1' : '0', _paragraph ? '1' : '0', '$_paperI']);
      await p.setStringList('bible_hl', [for (final e in _hl.entries) '${e.key}=${e.value}']);
      await p.setStringList('bible_bm', _bm.toList());
    } catch (_) {}
  }

  @override
  void dispose() {
    // the reading goes on in the background (bar at the bottom)
    _reader.removeListener(_onReader);
    if (widget.book != null) BibleReaderBar.onBibleScreen.value = false;
    _clearRecognizers();
    _scroll.dispose();
    super.dispose();
  }

  BibleBook get _b => _books![_book];
  List<String> get _verses => _b.chapters[_chapter - 1];
  String _ref(int v) => "${_b.name} $_chapter:$v";

  void _go(int book, int chapter, {int? verse}) {
    if (_reader.speaking) _reader.stop();
    _follow = false;
    _clearRecognizers();
    setState(() {
      _book = book;
      _chapter = chapter;
      _mark = verse;
      _picked.clear();
      _speaking = false;
      _paused = false;
      _reading = null;
      _keys.clear();
    });
    _remember();
    if (verse == null) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } else {
      _jumpToMark();
    }
  }

  void _jumpToMark() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final k = _mark == null ? null : _keys[_mark];
      if (k?.currentContext != null) Scrollable.ensureVisible(k!.currentContext!, alignment: 0.2, duration: const Duration(milliseconds: 400));
    });
  }

  void _step(int d) {
    var b = _book, c = _chapter + d;
    if (c < 1) {
      if (b == 0) return;
      b--;
      c = _books![b].chapters.length;
    } else if (c > _books![b].chapters.length) {
      if (b == _books!.length - 1) return;
      b++;
      c = 1;
    }
    _go(b, c);
  }

  void _listen({int from = 1}) {
    if (!speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Listening needs a browser with speech (Chrome, Edge, Safari).")));
      return;
    }
    _follow = true;
    _reader.start(_book, _chapter, from: from);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Reading aloud. It keeps reading if you leave this screen, and goes on to the next chapter."),
      duration: Duration(seconds: 3),
    ));
  }

  Future<void> _pickBook() async {
    final books = _books!;
    final r = await showModalBottomSheet<(int, int)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.bg(Colors.white),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => _BookPicker(books: books, book: _book),
    );
    if (r != null) _go(r.$1, r.$2);
  }

  Future<void> _search() async {
    final r = await Navigator.push<(int, int, int)>(context, MaterialPageRoute(builder: (_) => BibleSearchScreen(books: _books!, current: _book)));
    if (r != null) _go(r.$1, r.$2, verse: r.$3);
  }

  // ------------------------------------------------------------ verse menu

  String _quote(List<int> vs, {bool withRef = true}) {
    vs.sort();
    final text = vs.map((v) => vs.length == 1 ? _verses[v - 1] : "$v ${_verses[v - 1]}").join(' ');
    final ref = vs.length == 1 ? _ref(vs.first) : "${_b.name} $_chapter:${vs.first}${vs.last != vs.first ? '-${vs.last}' : ''}";
    return withRef ? "“$text” — $ref (WEB)" : text;
  }

  /// Long press (phones) or right click (computers) on a verse.
  Future<void> _verseMenu(int v) async {
    final vs = _picked.isEmpty || !_picked.contains(v) ? [v] : (_picked.toList()..sort());
    final label = vs.length == 1 ? _ref(v) : "${_b.name} $_chapter:${vs.first}-${vs.last}";
    final marked = _bm.contains(_key(v));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppPalette.bg(Colors.white),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        Widget item(IconData i, String t, VoidCallback f) => ListTile(
              dense: true,
              leading: Icon(i, color: AppPalette.fg(_kPurple)),
              title: Text(t, style: GoogleFonts.merriweather(fontSize: 13.5)),
              onTap: () {
                Navigator.pop(ctx);
                f();
              },
            );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text.rich(TextSpan(text: label), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: AppPalette.fg(_kPurple))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: Text.rich(TextSpan(text: _quote([...vs], withRef: false)),
                    maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: _font0(size: 12.5, color: AppPalette.fg(Colors.black54), style: FontStyle.italic)),
              ),
              // highlight colours
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (int i = 0; i < _hlColors.length; i++)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() {
                          for (final x in vs) {
                            _hl[_key(x)] = i;
                          }
                          _picked.clear();
                        });
                        _remember();
                      },
                      child: CircleAvatar(radius: 15, backgroundColor: _hlColors[i]),
                    ),
                  ),
                if (vs.any((x) => _hl.containsKey(_key(x))))
                  IconButton(
                    tooltip: tr("Remove highlight"),
                    icon: const Icon(Icons.format_color_reset_rounded),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        for (final x in vs) {
                          _hl.remove(_key(x));
                        }
                      });
                      _remember();
                    },
                  ),
              ]),
              const Divider(height: 10),
              item(Icons.content_copy_rounded, tr("Copy"), () => _copyVerses(vs, withRef: false)),
              item(Icons.format_quote_rounded, tr("Copy with reference"), () => _copyVerses(vs)),
              item(Icons.ios_share_rounded, tr("Share"), () => _share(vs)),
              item(Icons.checklist_rounded, tr("Select more verses"), () => setState(() => _picked.add(v))),
              item(marked ? Icons.bookmark_remove_rounded : Icons.bookmark_add_rounded, tr(marked ? "Remove bookmark" : "Bookmark"), () {
                setState(() => marked ? _bm.remove(_key(v)) : _bm.add(_key(v)));
                _remember();
              }),
              item(Icons.record_voice_over_rounded, tr("Read aloud from here"), () {
                setState(() => _picked.clear());
                _listen(from: v);
              }),
              if (_bm.isNotEmpty) item(Icons.bookmarks_rounded, tr("My bookmarks"), _showBookmarks),
              const SizedBox(height: 8),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _copyVerses(List<int> vs, {bool withRef = true}) async {
    await Clipboard.setData(ClipboardData(text: _quote([...vs], withRef: withRef)));
    if (!mounted) return;
    setState(() => _picked.clear());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Copied"), backgroundColor: Colors.green.shade700));
  }

  Future<void> _share(List<int> vs) async {
    final text = _quote([...vs]);
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied: paste it where you want to share it.")));
    }
    if (mounted) setState(() => _picked.clear());
  }

  void _showBookmarks() {
    final books = _books!;
    final list = _bm.map((k) => k.split(':').map(int.tryParse).toList()).where((x) => x.length == 3 && !x.contains(null)).map((x) => (x[0]!, x[1]!, x[2]!)).toList()
      ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : (a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3)));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppPalette.bg(Colors.white),
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Center(child: Text("My bookmarks", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: AppPalette.fg(_kPurple)))),
          for (final b in list)
            if (b.$1 < books.length && b.$2 <= books[b.$1].chapters.length && b.$3 <= books[b.$1].chapters[b.$2 - 1].length)
              ListTile(
                leading: Icon(Icons.bookmark_rounded, color: AppPalette.fg(_kGold)),
                title: Text.rich(TextSpan(text: "${books[b.$1].name} ${b.$2}:${b.$3}"), style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text.rich(TextSpan(text: books[b.$1].chapters[b.$2 - 1][b.$3 - 1]), maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(ctx);
                  _go(b.$1, b.$2, verse: b.$3);
                },
              ),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------ text style

  void _styleSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppPalette.bg(Colors.white),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        void change(VoidCallback f) {
          setState(f);
          set(() {});
          _remember();
        }

        Widget label(String t) => Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(t, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppPalette.fg(_kPurple))),
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Text("Text style", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple)))),
              // preview
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppPalette.bg(_paper), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppPalette.line(Colors.black12))),
                child: Text.rich(
                  TextSpan(children: [
                    if (_numbers) TextSpan(text: '16 ', style: _font0(size: _size * 0.62, weight: FontWeight.bold, color: AppPalette.fg(_kGold))),
                    TextSpan(text: "For God so loved the world, that he gave his one and only Son…", style: _font0(size: _size, height: _line, color: AppPalette.fg(Colors.black87))),
                  ]),
                ),
              ),
              label("Font"),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in _fonts)
                  ChoiceChip(
                    label: Text.rich(TextSpan(text: f), style: (() {
                      try {
                        return GoogleFonts.getFont(f, fontSize: 12.5);
                      } catch (_) {
                        return const TextStyle(fontSize: 12.5);
                      }
                    })()),
                    selected: _font == f,
                    onSelected: (_) => change(() => _font = f),
                  ),
              ]),
              label("Size"),
              Row(children: [
                const Text("A", style: TextStyle(fontSize: 12)),
                Expanded(child: Slider(value: _size.clamp(12, 30).toDouble(), min: 12, max: 30, divisions: 12, label: _size.round().toString(), onChanged: (v) => change(() => _size = v))),
                const Text("A", style: TextStyle(fontSize: 22)),
              ]),
              label("Line spacing"),
              Wrap(spacing: 6, children: [
                for (final l in const [(1.4, 'Close'), (1.75, 'Normal'), (2.1, 'Wide')])
                  ChoiceChip(label: Text(l.$2), selected: (_line - l.$1).abs() < 0.05, onSelected: (_) => change(() => _line = l.$1)),
              ]),
              label("Layout"),
              Wrap(spacing: 6, children: [
                ChoiceChip(label: const Text("One verse per line"), selected: !_paragraph, onSelected: (_) => change(() => _paragraph = false)),
                ChoiceChip(label: const Text("Paragraph"), selected: _paragraph, onSelected: (_) => change(() => _paragraph = true)),
              ]),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: _numbers, onChanged: (v) => change(() => _numbers = v), title: const Text("Verse numbers")),
              label("Page colour"),
              Wrap(spacing: 10, children: [
                for (int i = 0; i < _papers.length; i++)
                  InkWell(
                    onTap: () => change(() => _paperI = i),
                    borderRadius: BorderRadius.circular(10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 44,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _papers[i].$1,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _paperI == i ? _kPurple : Colors.black26, width: _paperI == i ? 2 : 1),
                        ),
                      ),
                      Text(_papers[i].$2, style: const TextStyle(fontSize: 10.5)),
                    ]),
                  ),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  // ------------------------------------------------------------ verses

  Color? _verseBg(int v) {
    if (_reading == v) return const Color(0xFFFFF3C4);
    if (_picked.contains(v)) return const Color(0xFFEDE3F8);
    final h = _hl[_key(v)];
    if (h != null) return _hlColors[h.clamp(0, _hlColors.length - 1)];
    if (_mark == v) return const Color(0xFFFFF8E1);
    return null;
  }

  void _tapVerse(int v) => setState(() => _picked.contains(v) ? _picked.remove(v) : _picked.add(v));

  Widget _verseLine(int v, String text) => GestureDetector(
        key: _keys.putIfAbsent(v, () => GlobalKey()),
        onTap: () => _tapVerse(v),
        onLongPress: () => _verseMenu(v),
        onSecondaryTap: () => _verseMenu(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(color: AppPalette.bg(_verseBg(v) ?? Colors.transparent), borderRadius: BorderRadius.circular(8)),
          child: Text.rich(
            TextSpan(children: [
              if (_numbers)
                WidgetSpan(
                  alignment: PlaceholderAlignment.top,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Text("$v", style: _font0(size: _size * 0.62, weight: FontWeight.bold, color: AppPalette.fg(_kGold))),
                  ),
                ),
              TextSpan(
                text: text,
                style: _font0(size: _size, height: _line, color: AppPalette.fg(Colors.black87)).copyWith(
                  decoration: _picked.contains(v) ? TextDecoration.underline : null,
                  decorationColor: _kPurple,
                  decorationStyle: TextDecorationStyle.dotted,
                ),
              ),
              if (_bm.contains(_key(v))) WidgetSpan(child: Icon(Icons.bookmark_rounded, size: _size * 0.8, color: AppPalette.fg(_kGold))),
            ]),
          ),
        ),
      );

  /// Paragraph layout: the verses run on; each verse still reacts to taps,
  /// long presses and right clicks.
  Widget _paragraphText(List<String> verses) {
    final spans = <InlineSpan>[];
    for (int v = 1; v <= verses.length; v++) {
      if (verses[v - 1].isEmpty) continue;
      final bg = _verseBg(v);
      if (_numbers) {
        spans.add(TextSpan(text: ' $v ', style: _font0(size: _size * 0.62, weight: FontWeight.bold, color: AppPalette.fg(_kGold))));
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: SizedBox.shrink(key: _keys.putIfAbsent(v, () => GlobalKey())),
      ));
      spans.add(TextSpan(
        text: "${verses[v - 1]} ",
        style: _font0(size: _size, height: _line, color: AppPalette.fg(Colors.black87)).copyWith(
          backgroundColor: bg == null ? null : AppPalette.bg(bg),
          decoration: _picked.contains(v) ? TextDecoration.underline : null,
          decorationColor: _kPurple,
          decorationStyle: TextDecorationStyle.dotted,
        ),
        recognizer: _recognizer(v),
      ));
    }
    return Text.rich(TextSpan(children: spans), textAlign: TextAlign.justify);
  }

  final Map<int, LongPressGestureRecognizer> _recs = {};
  LongPressGestureRecognizer _recognizer(int v) => _recs.putIfAbsent(
        v,
        () {
          final r = LongPressGestureRecognizer();
          r.onLongPress = () => _verseMenu(v);
          r.onSecondaryLongPress = () => _verseMenu(v);
          return r;
        },
      );

  void _clearRecognizers() {
    for (final r in _recs.values) {
      r.dispose();
    }
    _recs.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.book == null) return const BibleLibraryScreen();
    if (_error != null || _books == null) {
      return Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFFDFBF7)),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(const Color(0xFFFDFBF7)),
          title: Text("Holy Bible", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
        ),
        body: Center(
          child: _error == null
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text("Opening the Bible …", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey.shade700))),
                ])
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.menu_book_rounded, size: 46, color: AppPalette.fg(_kGold)),
                    const SizedBox(height: 10),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: _open, icon: const Icon(Icons.refresh_rounded), label: const Text("Try again")),
                  ]),
                ),
        ),
      );
    }
    final verses = _verses;
    if (_paragraph) {
      // the verse a long press opens must match the chapter shown
      if (_recs.isNotEmpty && _recs.keys.any((v) => v > verses.length)) _clearRecognizers();
    }
    final paper = _paper;
    return Scaffold(
      backgroundColor: AppPalette.bg(paper),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(paper),
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        toolbarHeight: 56,
        title: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _pickBook,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text("${_b.name} $_chapter", overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18, color: AppPalette.fg(_kPurple)))),
              Icon(Icons.arrow_drop_down_rounded, color: AppPalette.fg(_kPurple)),
            ]),
          ),
        ),
        actions: [
          IconButton(tooltip: tr("Search"), icon: const Icon(Icons.search_rounded), onPressed: _search),
          IconButton(tooltip: tr("Text style"), icon: const Icon(Icons.text_fields_rounded), onPressed: _styleSheet),
          if (_bm.isNotEmpty) IconButton(tooltip: tr("My bookmarks"), icon: const Icon(Icons.bookmarks_outlined), onPressed: _showBookmarks),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), children: [
            Center(
              child: Column(children: [
                Text(_b.name.toUpperCase(), style: _font0(size: 12, weight: FontWeight.bold, color: AppPalette.fg(_kGold)).copyWith(letterSpacing: 3)),
                Text("$_chapter", style: _font0(size: 46, weight: FontWeight.w900, color: AppPalette.fg(_kPurple), height: 1.1)),
                const SizedBox(height: 4),
                Container(width: 40, height: 2, color: AppPalette.solid(_kGold)),
                const SizedBox(height: 14),
              ]),
            ),
            if (_paragraph)
              _paragraphText(verses)
            else
              for (int v = 1; v <= verses.length; v++)
                if (verses[v - 1].isNotEmpty) _verseLine(v, verses[v - 1]),
            const SizedBox(height: 16),
            Center(child: Text(Bible.version, style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.grey.shade500)))),
            const SizedBox(height: 4),
            Center(child: Text("Tap verses to select them · long press or right click for more", style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.grey.shade500)))),
          ]),
        ),
      ),
      // picked verses: copy / share / listen; otherwise Previous · Read aloud · Next
      bottomNavigationBar: SafeArea(
        child: Container(
          constraints: const BoxConstraints(maxHeight: 72),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          decoration: BoxDecoration(
            color: AppPalette.bg(Colors.white),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, -2))],
          ),
          child: _picked.isNotEmpty
              ? Row(children: [
                  Text("${_picked.length} verse${_picked.length == 1 ? '' : 's'}", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(tooltip: tr("Copy"), icon: const Icon(Icons.content_copy_rounded), onPressed: () => _copyVerses(_picked.toList(), withRef: false)),
                  IconButton(tooltip: tr("Copy with reference"), icon: const Icon(Icons.format_quote_rounded), onPressed: () => _copyVerses(_picked.toList())),
                  IconButton(tooltip: tr("Share"), icon: const Icon(Icons.ios_share_rounded), onPressed: () => _share(_picked.toList())),
                  IconButton(tooltip: tr("More"), icon: const Icon(Icons.more_horiz_rounded), onPressed: () => _verseMenu((_picked.toList()..sort()).first)),
                  IconButton(tooltip: tr("Clear"), icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _picked.clear())),
                ])
              : Row(children: [
                  OutlinedButton.icon(onPressed: () => _step(-1), icon: const Icon(Icons.chevron_left_rounded), label: const Text("Previous")),
                  // (a plain Center here grew to the whole screen height: the
                  // bottom bar then covered the Bible text)
                  Expanded(
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Tooltip(
                        message: tr(_speaking ? (_paused ? "Resume" : "Pause") : "Read aloud"),
                        child: Material(
                          color: AppPalette.bg(const Color(0xFFF3ECFC)),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              if (!_speaking) return _listen();
                              if (_paused) {
                                _reader.resume();
                              } else {
                                _reader.pause();
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(_speaking ? (_paused ? Icons.play_arrow_rounded : Icons.pause_rounded) : Icons.record_voice_over_rounded, color: AppPalette.fg(_kPurple)),
                            ),
                          ),
                        ),
                      ),
                      if (_speaking) IconButton(tooltip: tr("Stop"), icon: Icon(Icons.stop_rounded, color: AppPalette.fg(_kPurple)), onPressed: _reader.stop),
                    ]),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _step(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                    label: const Text("Next"),
                    iconAlignment: IconAlignment.end,
                  ),
                ]),
        ),
      ),
    );
  }
}

class _BookPicker extends StatefulWidget {
  final List<BibleBook> books;
  final int book;
  const _BookPicker({required this.books, required this.book});
  @override
  State<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<_BookPicker> {
  late bool _ot = widget.books[widget.book].oldTestament;
  int? _open;

  @override
  Widget build(BuildContext context) {
    final list = widget.books.where((b) => b.oldTestament == _ot).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: Column(children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(10),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: true, label: Text("Old Testament")), ButtonSegment(value: false, label: Text("New Testament"))],
            selected: {_ot},
            onSelectionChanged: (v) => setState(() {
              _ot = v.first;
              _open = null;
            }),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), children: [
            for (final b in list) ...[
              ListTile(
                dense: true,
                title: Text(b.name, style: GoogleFonts.merriweather(fontWeight: b.index == widget.book ? FontWeight.w900 : FontWeight.w600, color: AppPalette.fg(b.index == widget.book ? _kPurple : Colors.black87))),
                trailing: Text("${b.chapters.length}", style: TextStyle(color: AppPalette.fg(Colors.grey.shade600))),
                onTap: () => setState(() => _open = _open == b.index ? null : b.index),
              ),
              if (_open == b.index)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (int c = 1; c <= b.chapters.length; c++)
                      SizedBox(
                        width: 46,
                        height: 40,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          onPressed: () => Navigator.pop(context, (b.index, c)),
                          child: Text("$c"),
                        ),
                      ),
                  ]),
                ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Search the Bible: whole Bible, Old Testament, New Testament or one book.
class BibleSearchScreen extends StatefulWidget {
  final List<BibleBook> books;
  final int current;
  final String initialQuery;
  const BibleSearchScreen({super.key, required this.books, required this.current, this.initialQuery = ''});
  @override
  State<BibleSearchScreen> createState() => BibleSearchScreenState();
}

class BibleSearchScreenState extends State<BibleSearchScreen> {
  late final _q = TextEditingController(text: widget.initialQuery);

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  String _scope = 'all'; // all | ot | nt | book:<i>
  List<(int, int, int, String)> _hits = [];
  bool _more = false;
  Timer? _debounce;

  void _run() {
    final words = _q.text.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final out = <(int, int, int, String)>[];
    var more = false;
    if (words.isNotEmpty) {
      outer:
      for (final b in widget.books) {
        if (_scope == 'ot' && !b.oldTestament) continue;
        if (_scope == 'nt' && b.oldTestament) continue;
        if (_scope.startsWith('book:') && b.index != int.parse(_scope.substring(5))) continue;
        for (int c = 0; c < b.chapters.length; c++) {
          final vs = b.chapters[c];
          for (int v = 0; v < vs.length; v++) {
            final t = vs[v].toLowerCase();
            if (words.every(t.contains)) {
              if (out.length >= 500) {
                more = true;
                break outer;
              }
              out.add((b.index, c + 1, v + 1, vs[v]));
            }
          }
        }
      }
    }
    setState(() {
      _hits = out;
      _more = more;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  /// The verse with the searched words in bold.
  TextSpan _highlight(String text) {
    final words = _q.text.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return TextSpan(text: text);
    final re = RegExp(words.map(RegExp.escape).join('|'), caseSensitive: false);
    final spans = <TextSpan>[];
    int i = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
      spans.add(TextSpan(text: m[0], style: TextStyle(fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple), backgroundColor: const Color(0x33FFD54F))));
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.books;
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFFDFBF7)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(const Color(0xFFFDFBF7)),
        titleSpacing: 0,
        title: TextField(
          controller: _q,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: tr("Search words, e.g. love one another"), border: InputBorder.none),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), _run);
          },
          onSubmitted: (_) => _run(),
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(spacing: 6, children: [
                  for (final s in const [('all', 'Whole Bible'), ('ot', 'Old Testament'), ('nt', 'New Testament')])
                    ChoiceChip(
                      label: Text(s.$2),
                      selected: _scope == s.$1,
                      onSelected: (_) {
                        setState(() => _scope = s.$1);
                        _run();
                      },
                    ),
                  PopupMenuButton<int>(
                    onSelected: (i) {
                      setState(() => _scope = 'book:$i');
                      _run();
                    },
                    itemBuilder: (_) => [for (final b in books) PopupMenuItem(value: b.index, child: Text(b.name))],
                    child: Chip(
                      avatar: const Icon(Icons.book_rounded, size: 16),
                      label: Text(_scope.startsWith('book:') ? books[int.parse(_scope.substring(5))].name : "One book"),
                      backgroundColor: AppPalette.bg(_scope.startsWith('book:') ? const Color(0xFFEDE3F8) : Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        if (_q.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(_hits.isEmpty ? "No verses found" : "${_hits.length}${_more ? '+' : ''} verses",
                style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(_kPurple))),
          ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
                itemCount: _hits.length,
                separatorBuilder: (_, i) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final h = _hits[i];
                  return ListTile(
                    onTap: () => Navigator.pop(context, (h.$1, h.$2, h.$3)),
                    title: Text("${books[h.$1].name} ${h.$2}:${h.$3}", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppPalette.fg(_kGold))),
                    subtitle: Text.rich(_highlight(h.$4), style: GoogleFonts.merriweather(fontSize: 13, height: 1.5, color: AppPalette.fg(Colors.black87))),
                    trailing: IconButton(
                      tooltip: tr("Copy"),
                      icon: const Icon(Icons.content_copy_rounded, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: "“${h.$4}” — ${books[h.$1].name} ${h.$2}:${h.$3} (WEB)"));
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied")));
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ]),
    );
  }
}