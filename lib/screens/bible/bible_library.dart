import 'package:material_ui/material_ui.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_palette.dart';
import '../../core/i18n.dart';
import 'bible_screen.dart';

const Color _kPurple = Color(0xFF4A148C);
const Color _kGold = Color(0xFFB8860B);
const Color _kPaper = Color(0xFFFDFBF7);

/// Holy Bible › the library: the title, a search bar (words, or a reference
/// such as "John 3:16"), then two columns — the Old Testament's books and
/// the New Testament's books. A book opens its chapters; a chapter opens
/// the reading screen.
class BibleLibraryScreen extends StatefulWidget {
  const BibleLibraryScreen({super.key});
  @override
  State<BibleLibraryScreen> createState() => _BibleLibraryScreenState();
}

class _BibleLibraryScreenState extends State<BibleLibraryScreen> {
  List<BibleBook>? _books;
  String? _error;
  final _q = TextEditingController();
  (int, int)? _last; // last chapter read

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() => _error = null);
    try {
      final b = await Bible.load();
      (int, int)? last;
      try {
        final p = await SharedPreferences.getInstance();
        final l = p.getStringList('bible_last');
        if (l != null && l.length == 2) last = (int.tryParse(l[0]) ?? 42, int.tryParse(l[1]) ?? 1);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _books = b;
          _last = last;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = "The Bible text could not be opened. Check that assets/bible/web.json is in the app and rebuild.");
    }
  }

  /// "John 3:16", "1 Cor 13", "psalm 23" → (book, chapter, verse)
  (int, int, int?)? _reference(String q) {
    final books = _books;
    if (books == null) return null;
    final m = RegExp(r'^\s*((?:[1-3]\s*)?[A-Za-z][A-Za-z .]*?)\s*(\d+)(?:\s*[:.]\s*(\d+))?\s*$').firstMatch(q);
    if (m == null) return null;
    final name = m[1]!.toLowerCase().replaceAll(RegExp(r'[\s.]'), '');
    if (name.length < 2) return null;
    BibleBook? hit;
    for (final b in books) {
      final n = b.name.toLowerCase().replaceAll(RegExp(r'[\s.]'), '');
      if (n == name || n.startsWith(name) || (name == 'psalm' && n == 'psalms')) {
        hit = b;
        break;
      }
    }
    if (hit == null) return null;
    final c = int.parse(m[2]!);
    if (c < 1 || c > hit.chapters.length) return null;
    final v = m[3] == null ? null : int.parse(m[3]!);
    return (hit.index, c, v);
  }

  void _search() {
    final q = _q.text.trim();
    if (q.isEmpty || _books == null) return;
    final ref = _reference(q);
    if (ref != null) {
      _read(ref.$1, ref.$2, verse: ref.$3);
      return;
    }
    Navigator.push<(int, int, int)>(
      context,
      MaterialPageRoute(builder: (_) => BibleSearchScreen(books: _books!, current: 42, initialQuery: q)),
    ).then((r) {
      if (r != null) _read(r.$1, r.$2, verse: r.$3);
    });
  }

  void _read(int book, int chapter, {int? verse}) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => BibleScreen(book: book, chapter: chapter, verse: verse))).then((_) => _open());
  }

  void _chapters(BibleBook b) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => BibleChaptersScreen(book: b))).then((_) => _open());
  }

  Widget _column(String title, List<BibleBook> books) => Container(
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.line(const Color(0x1F4A148C))),
          boxShadow: AppPalette.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            color: AppPalette.bg(const Color(0xFFF3ECFC)),
            child: Column(children: [
              Text(title, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: AppPalette.fg(_kPurple))),
              Text.rich(TextSpan(text: "${books.length} ${tr('books')}"), style: GoogleFonts.merriweather(fontSize: 10.5, color: AppPalette.fg(Colors.grey.shade700))),
            ]),
          ),
          for (final b in books)
            InkWell(
              onTap: () => _chapters(b),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppPalette.line(const Color(0x0F000000))))),
                child: Row(children: [
                  Expanded(
                    child: Text.rich(TextSpan(text: b.name),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.w600, color: AppPalette.fg(Colors.black87))),
                  ),
                  Text.rich(TextSpan(text: '${b.chapters.length}'), style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.grey.shade500))),
                ]),
              ),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final books = _books;
    return Scaffold(
      backgroundColor: AppPalette.bg(_kPaper),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: AppPalette.bg(_kPaper),
        surfaceTintColor: Colors.transparent,
        title: Text("Holy Bible", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 20, color: AppPalette.fg(_kPurple))),
      ),
      body: books == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text.rich(TextSpan(text: _error), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(onPressed: _open, icon: const Icon(Icons.refresh_rounded), label: const Text("Try again")),
                      ]),
                    ),
            )
          : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 90), children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(Bible.version, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(_kGold))),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _q,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: tr('Search a verse, words or a reference (John 3:16)'),
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _search),
                        filled: true,
                        fillColor: AppPalette.bg(Colors.white),
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                      ),
                    ),
                    if (_last != null && _last!.$1 < books.length) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: ActionChip(
                          avatar: Icon(Icons.bookmark_rounded, size: 18, color: AppPalette.fg(_kGold)),
                          label: Text.rich(TextSpan(text: "${tr('Continue reading')}: ${books[_last!.$1].name} ${_last!.$2}"),
                              style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, color: AppPalette.fg(_kPurple))),
                          backgroundColor: AppPalette.bg(Colors.white),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          onPressed: () => _read(_last!.$1, _last!.$2),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _column("Old Testament", books.where((b) => b.oldTestament).toList())),
                      const SizedBox(width: 10),
                      Expanded(child: _column("New Testament", books.where((b) => !b.oldTestament).toList())),
                    ]),
                  ]),
                ),
              ),
            ]),
    );
  }
}

/// A book's chapters: tap one to read it.
class BibleChaptersScreen extends StatelessWidget {
  final BibleBook book;
  const BibleChaptersScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(_kPaper),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: AppPalette.bg(_kPaper),
        surfaceTintColor: Colors.transparent,
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          Text.rich(TextSpan(text: book.name), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 19, color: AppPalette.fg(_kPurple))),
          Text.rich(TextSpan(text: "${book.chapters.length} ${tr(book.chapters.length == 1 ? 'chapter' : 'chapters')} · ${tr(book.oldTestament ? 'Old Testament' : 'New Testament')}"),
              style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
        ]),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 76, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1),
            itemCount: book.chapters.length,
            itemBuilder: (c, i) => Material(
              color: AppPalette.bg(Colors.white),
              borderRadius: BorderRadius.circular(14),
              elevation: 1,
              shadowColor: const Color(0x334A148C),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BibleScreen(book: book.index, chapter: i + 1))),
                child: Center(
                  child: Text.rich(TextSpan(text: '${i + 1}'), style: GoogleFonts.merriweather(fontWeight: FontWeight.w800, fontSize: 17, color: AppPalette.fg(_kPurple))),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
