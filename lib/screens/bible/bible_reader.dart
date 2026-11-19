import 'package:material_ui/material_ui.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';

import '../../core/app_palette.dart';
import '../../core/i18n.dart';
import '../../services/media_playback.dart' show appNavigatorKey;
import '../../services/speech.dart';
import 'bible_screen.dart';

/// Reading the Bible aloud in the background: it keeps reading while the
/// person uses other screens, and goes on to the next chapter by itself.
/// A small bar ([BibleReaderBar]) shows what is being read, with pause /
/// resume, stop and "open". It uses the device's voice (browser speech).
class BibleReader extends ChangeNotifier {
  BibleReader._();
  static final BibleReader instance = BibleReader._();

  List<BibleBook>? _books;
  int book = 0, chapter = 1;
  int? verse; // the verse being read (null: the chapter's title)
  bool speaking = false, paused = false;

  /// Go on to the next chapter at the end of one.
  bool continueNext = true;
  int _run = 0; // stale callbacks (after stop / a new start) are ignored

  String get bookName => _books == null || book >= _books!.length ? '' : _books![book].name;
  String get label => "$bookName $chapter${verse != null ? ':$verse' : ''}";

  bool isReading(int b, int c) => speaking && book == b && chapter == c;

  Future<void> start(int b, int c, {int from = 1}) async {
    if (!speechAvailable) return;
    _books ??= await Bible.load();
    final books = _books!;
    if (b < 0 || b >= books.length || c < 1 || c > books[b].chapters.length) return;
    final verses = books[b].chapters[c - 1];
    final first = from.clamp(1, verses.length);
    book = b;
    chapter = c;
    verse = null;
    speaking = true;
    paused = false;
    final run = ++_run;
    notifyListeners();
    speak(
      ["${books[b].name}, chapter $c.", for (int v = first; v <= verses.length; v++) verses[v - 1]],
      onPart: (i) {
        if (run != _run) return;
        verse = i == 0 ? null : first + i - 1;
        notifyListeners();
      },
      onDone: () {
        if (run != _run) return;
        _next();
      },
    );
  }

  void _next() {
    final books = _books;
    if (!continueNext || books == null) return stop();
    var b = book, c = chapter + 1;
    if (c > books[b].chapters.length) {
      if (b == books.length - 1) return stop();
      b++;
      c = 1;
    }
    start(b, c);
  }

  void pause() {
    if (!speaking || paused) return;
    pauseSpeaking();
    paused = true;
    notifyListeners();
  }

  void resume() {
    if (!speaking || !paused) return;
    resumeSpeaking();
    paused = false;
    notifyListeners();
  }

  void stop() {
    _run++;
    stopSpeaking();
    speaking = false;
    paused = false;
    verse = null;
    notifyListeners();
  }
}

/// The small "now reading" bar, shown over every screen while the Bible is
/// being read aloud (hidden on the Bible screen itself, which has its own
/// buttons).
class BibleReaderBar extends StatelessWidget {
  const BibleReaderBar({super.key});

  static const Color _purple = Color(0xFF4A148C);

  /// The Bible screen is open (its own controls are enough there).
  static final ValueNotifier<bool> onBibleScreen = ValueNotifier(false);

  @override
  Widget build(BuildContext context) {
    final r = BibleReader.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([r, onBibleScreen]),
      builder: (context, _) {
        if (!r.speaking || onBibleScreen.value) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 72),
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(16),
              color: AppPalette.bg(Colors.white),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 460),
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppPalette.line(_purple.withValues(alpha: 0.25))),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.menu_book_rounded, color: AppPalette.fg(_purple), size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: InkWell(
                      onTap: () => appNavigatorKey.currentState?.push(
                        MaterialPageRoute(builder: (_) => BibleScreen(book: r.book, chapter: r.chapter, verse: r.verse)),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.paused ? "Paused" : "Reading aloud", style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.grey.shade600))),
                        Text.rich(TextSpan(text: r.label),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(_purple))),
                      ]),
                    ),
                  ),
                  IconButton(
                    tooltip: tr(r.paused ? "Resume" : "Pause"),
                    icon: Icon(r.paused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: AppPalette.fg(_purple)),
                    onPressed: r.paused ? r.resume : r.pause,
                  ),
                  IconButton(tooltip: tr("Stop"), icon: Icon(Icons.stop_rounded, color: AppPalette.fg(_purple)), onPressed: r.stop),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
