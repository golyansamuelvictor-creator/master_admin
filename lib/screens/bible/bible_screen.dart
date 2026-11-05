import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_palette.dart';
import '../../core/i18n.dart';
import '../../services/speech.dart';

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
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BibleScreen(book: ref.$1, chapter: ref.$2, verse: ref.$3))),
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
                          child: Column(
                            key: ValueKey(where),
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
                          ),
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
  int? _reading; // the verse being read aloud
  bool _speaking = false, _paused = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefs();
    _open();
  }

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
      if (!mounted) return;
      setState(() {
        if (s != null) _size = s;
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
    } catch (_) {}
  }

  @override
  void dispose() {
    stopSpeaking();
    _scroll.dispose();
    super.dispose();
  }

  BibleBook get _b => _books![_book];
  List<String> get _verses => _b.chapters[_chapter - 1];
  String _ref(int v) => "${_b.name} $_chapter:$v";

  void _go(int book, int chapter, {int? verse}) {
    stopSpeaking();
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

  Future<void> _copy({bool withRef = true}) async {
    final vs = _picked.toList()..sort();
    if (vs.isEmpty) return;
    final text = vs.map((v) => vs.length == 1 ? _verses[v - 1] : "$v ${_verses[v - 1]}").join(' ');
    final ref = vs.length == 1 ? _ref(vs.first) : "${_b.name} $_chapter:${vs.first}${vs.last != vs.first ? '-${vs.last}' : ''}";
    await Clipboard.setData(ClipboardData(text: withRef ? "“$text” — $ref (WEB)" : text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Copied $ref"), backgroundColor: Colors.green.shade700));
    setState(() => _picked.clear());
  }

  void _listen({int from = 1}) {
    if (!speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Listening needs a browser with speech (Chrome, Edge, Safari).")));
      return;
    }
    final parts = ["${_b.name}, chapter $_chapter.", for (int v = from; v <= _verses.length; v++) _verses[v - 1]];
    setState(() {
      _speaking = true;
      _paused = false;
    });
    speak(parts, onPart: (i) {
      if (!mounted) return;
      setState(() => _reading = i == 0 ? null : from + i - 1);
      final k = _reading == null ? null : _keys[_reading];
      if (k?.currentContext != null) Scrollable.ensureVisible(k!.currentContext!, alignment: 0.3, duration: const Duration(milliseconds: 300));
    }, onDone: () {
      if (mounted) {
        setState(() {
          _speaking = false;
          _reading = null;
        });
      }
    });
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
    final r = await Navigator.push<(int, int, int)>(context, MaterialPageRoute(builder: (_) => _BibleSearch(books: _books!, current: _book)));
    if (r != null) _go(r.$1, r.$2, verse: r.$3);
  }

  @override
  Widget build(BuildContext context) {
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
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFFDFBF7)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(const Color(0xFFFDFBF7)),
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 52,
        titleSpacing: 0,
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
          IconButton(
            tooltip: tr(_speaking ? (_paused ? "Resume" : "Pause") : "Listen to this chapter"),
            icon: Icon(_speaking ? (_paused ? Icons.play_arrow_rounded : Icons.pause_rounded) : Icons.headphones_rounded),
            onPressed: () {
              if (!_speaking) return _listen();
              if (_paused) {
                resumeSpeaking();
              } else {
                pauseSpeaking();
              }
              setState(() => _paused = !_paused);
            },
          ),
          if (_speaking)
            IconButton(
              tooltip: tr("Stop"),
              icon: const Icon(Icons.stop_rounded),
              onPressed: () {
                stopSpeaking();
                setState(() {
                  _speaking = false;
                  _reading = null;
                });
              },
            ),
          PopupMenuButton<String>(
            tooltip: tr("Text size"),
            icon: const Icon(Icons.format_size_rounded),
            onSelected: (v) {
              setState(() => _size = (v == '+' ? _size + 1.5 : _size - 1.5).clamp(12, 30).toDouble());
              _remember();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: '+', child: Text("Larger text")), PopupMenuItem(value: '-', child: Text("Smaller text"))],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), children: [
                Center(
                  child: Column(children: [
                    Text(_b.name.toUpperCase(), style: GoogleFonts.merriweather(fontSize: 12, letterSpacing: 3, fontWeight: FontWeight.bold, color: AppPalette.fg(_kGold))),
                    Text("$_chapter", style: GoogleFonts.merriweather(fontSize: 46, fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple), height: 1.1)),
                    const SizedBox(height: 4),
                    Container(width: 40, height: 2, color: AppPalette.solid(_kGold)),
                    const SizedBox(height: 14),
                  ]),
                ),
                for (int v = 1; v <= verses.length; v++)
                  if (verses[v - 1].isNotEmpty)
                    GestureDetector(
                      key: _keys.putIfAbsent(v, () => GlobalKey()),
                      onTap: () => setState(() => _picked.contains(v) ? _picked.remove(v) : _picked.add(v)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppPalette.bg(_reading == v
                              ? const Color(0xFFFFF3C4)
                              : (_picked.contains(v) ? const Color(0xFFEDE3F8) : (_mark == v ? const Color(0xFFFFF8E1) : Colors.transparent))),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text.rich(
                          TextSpan(children: [
                            WidgetSpan(
                              alignment: PlaceholderAlignment.top,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: Text("$v", style: GoogleFonts.merriweather(fontSize: _size * 0.62, fontWeight: FontWeight.bold, color: AppPalette.fg(_kGold))),
                              ),
                            ),
                            TextSpan(
                              text: verses[v - 1],
                              style: GoogleFonts.merriweather(
                                fontSize: _size,
                                height: 1.75,
                                color: AppPalette.fg(Colors.black87),
                                decoration: _picked.contains(v) ? TextDecoration.underline : null,
                                decorationColor: _kPurple,
                                decorationStyle: TextDecorationStyle.dotted,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                const SizedBox(height: 16),
                Center(child: Text(Bible.version, style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.grey.shade500)))),
              ]),
            ),
          ),
        ),
      ]),
      // picked verses: copy / listen; otherwise previous / next chapter
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          decoration: BoxDecoration(
            color: AppPalette.bg(Colors.white),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, -2))],
          ),
          child: _picked.isNotEmpty
              ? Row(children: [
                  Text("${_picked.length} verse${_picked.length == 1 ? '' : 's'}", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(onPressed: () => _copy(withRef: false), icon: const Icon(Icons.content_copy_rounded, size: 18), label: const Text("Copy text")),
                  FilledButton.icon(onPressed: _copy, icon: const Icon(Icons.format_quote_rounded, size: 18), label: const Text("Copy with reference")),
                  IconButton(
                    tooltip: tr("Listen from here"),
                    icon: const Icon(Icons.headphones_rounded),
                    onPressed: () {
                      final from = (_picked.toList()..sort()).first;
                      setState(() => _picked.clear());
                      _listen(from: from);
                    },
                  ),
                  IconButton(tooltip: tr("Clear"), icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _picked.clear())),
                ])
              : Row(children: [
                  OutlinedButton.icon(onPressed: () => _step(-1), icon: const Icon(Icons.chevron_left_rounded), label: const Text("Previous")),
                  Expanded(child: Center(child: Text("Tap verses to copy or listen", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))))),
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
class _BibleSearch extends StatefulWidget {
  final List<BibleBook> books;
  final int current;
  const _BibleSearch({required this.books, required this.current});
  @override
  State<_BibleSearch> createState() => _BibleSearchState();
}

class _BibleSearchState extends State<_BibleSearch> {
  final _q = TextEditingController();
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
