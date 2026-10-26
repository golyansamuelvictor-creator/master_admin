// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';

import '../core/table_export.dart';
import '../widgets/office_shell.dart';

/// Presentations (PowerPoint style): the original hub + ribbon layout with
/// private decks, layouts, themes, transitions, notes, slide sorter,
/// templates, right-click menus, shortcuts, a full-screen slideshow, PDF
/// download and print preview. The slide is centred and fits the screen.
class PresentationScreen extends StatefulWidget {
  final String title, userEmail, userRole;
  const PresentationScreen({super.key, required this.title, required this.userEmail, required this.userRole});
  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

const Color _kOrange = Color(0xFFB7472A);
const double _kW = 960, _kH = 540; // design size of every slide (16:9)

class _Slide {
  String? id;
  String title;
  String content;
  String layout; // title | title_content | section | two_column | quote | blank
  String? bg;
  String? fg;
  String notes;
  bool dirty;
  _Slide({this.id, this.title = '', this.content = '', this.layout = 'title_content', this.bg, this.fg, this.notes = '', this.dirty = true});

  _Slide copy() => _Slide(title: title, content: content, layout: layout, bg: bg, fg: fg, notes: notes);
}

class _Theme {
  final String key, name;
  final Color bg, fg, accent;
  const _Theme(this.key, this.name, this.bg, this.fg, this.accent);
}

// darkify:off — slide designs keep their own colours in dark mode
const List<_Theme> _themes = [
  _Theme('classic', 'Classic', Colors.white, Color(0xFF212121), _kOrange),
  _Theme('purple', 'Royal', Color(0xFF3B0764), Colors.white, Color(0xFFFFC107)),
  _Theme('dark', 'Night', Color(0xFF111827), Color(0xFFF9FAFB), Color(0xFF60A5FA)),
  _Theme('sky', 'Sky', Color(0xFFE0F2FE), Color(0xFF0C4A6E), Color(0xFF0284C7)),
  _Theme('forest', 'Forest', Color(0xFFECFDF5), Color(0xFF064E3B), Color(0xFF059669)),
  _Theme('sunset', 'Sunset', Color(0xFFFFF7ED), Color(0xFF7C2D12), Color(0xFFEA580C)),
];
// darkify:on

_Theme _themeFor(String? k) => _themes.firstWhere((t) => t.key == k, orElse: () => _themes.first);

const Map<String, String> _layoutNames = {
  'title': 'Title slide',
  'title_content': 'Title and bullets',
  'section': 'Section header',
  'two_column': 'Two columns',
  'quote': 'Quote / verse',
  'blank': 'Text only',
};

const Map<String, String> _transitionNames = {'none': 'None', 'fade': 'Fade', 'slide': 'Push', 'zoom': 'Zoom'};

const List<String> _swatches = ['#FFFFFF', '#FFF7ED', '#F3E8FF', '#E0F2FE', '#DCFCE7', '#3B0764', '#111827', '#B7472A', '#0D47A1', '#1B5E20'];

Color _hex(String? h, Color fallback) {
  if (h == null || h.isEmpty) return fallback;
  final v = int.tryParse(h.replaceFirst('#', ''), radix: 16);
  if (v == null) return fallback;
  return Color(h.replaceFirst('#', '').length == 6 ? 0xFF000000 | v : v);
}

// darkify:off — slide designs keep their own colours in dark mode
/// Draws one slide at its design size (960 x 540). Put it in a FittedBox to scale.
class _SlideView extends StatelessWidget {
  final _Slide slide;
  final _Theme theme;
  final TextEditingController? titleC;
  final TextEditingController? contentC;
  /// Tells the editor which text box has the cursor (for the right-click menu).
  final ValueChanged<TextEditingController>? onFocusText;
  /// On computers the app's own right-click menu replaces the text box menu.
  final bool ownMenus;
  const _SlideView({super.key, required this.slide, required this.theme, this.titleC, this.contentC, this.onFocusText, this.ownMenus = false});

  bool get _edit => titleC != null && contentC != null;

  @override
  Widget build(BuildContext context) {
    final bg = _hex(slide.bg, slide.layout == 'section' ? theme.accent : theme.bg);
    final fg = _hex(slide.fg, slide.layout == 'section' ? Colors.white : theme.fg);
    final accent = slide.layout == 'section' ? Colors.white : theme.accent;

    Widget text(TextEditingController? c, String value, TextStyle style, {TextAlign align = TextAlign.left, int? maxLines, String hint = ''}) {
      if (_edit && c != null) {
        return Focus(
          onFocusChange: (f) {
            if (f) onFocusText?.call(c);
          },
          child: TextField(
            controller: c,
            maxLines: maxLines,
            minLines: 1,
            textAlign: align,
            style: style,
            cursorColor: accent,
            contextMenuBuilder: ownMenus ? null : (ctx, state) => AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
            decoration: InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              hintText: hint,
              hintStyle: style.copyWith(color: fg.withValues(alpha: 0.35)),
            ),
          ),
        );
      }
      return Text(value.isEmpty ? '' : value, textAlign: align, style: style, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis);
    }

    final titleStyle = GoogleFonts.merriweather(fontSize: 40, fontWeight: FontWeight.w900, color: fg, height: 1.2);
    final bodyStyle = GoogleFonts.merriweather(fontSize: 24, color: fg, height: 1.5);

    Widget bullets(String content, {double size = 24}) {
      final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: EdgeInsets.only(top: size * 0.55, right: 14),
                child: Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
              ),
              Expanded(child: Text(l.trim(), style: bodyStyle.copyWith(fontSize: size))),
            ]),
          ),
      ]);
    }

    Widget body;
    switch (slide.layout) {
      case 'title':
        body = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 90),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            text(titleC, slide.title, titleStyle.copyWith(fontSize: 54), align: TextAlign.center, hint: 'Click to add title'),
            const SizedBox(height: 18),
            Container(width: 120, height: 5, color: accent),
            const SizedBox(height: 18),
            text(contentC, slide.content, bodyStyle.copyWith(fontSize: 26, color: fg.withValues(alpha: 0.8)), align: TextAlign.center, hint: 'Subtitle'),
          ]),
        );
      case 'section':
        body = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 90),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            text(titleC, slide.title, titleStyle.copyWith(fontSize: 56), hint: 'Section title'),
            const SizedBox(height: 14),
            text(contentC, slide.content, bodyStyle.copyWith(color: fg.withValues(alpha: 0.85)), hint: 'Optional description'),
          ]),
        );
      case 'quote':
        body = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 110),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('“', style: GoogleFonts.merriweather(fontSize: 110, color: accent, height: 0.8)),
            text(contentC, slide.content, bodyStyle.copyWith(fontSize: 32, fontStyle: FontStyle.italic), align: TextAlign.center, hint: 'Quote or verse'),
            const SizedBox(height: 22),
            text(titleC, slide.title, bodyStyle.copyWith(fontSize: 22, fontWeight: FontWeight.bold, color: accent), align: TextAlign.center, hint: '— Reference'),
          ]),
        );
      case 'blank':
        body = Padding(
          padding: const EdgeInsets.all(70),
          child: Center(child: text(contentC, slide.content, bodyStyle.copyWith(fontSize: 30), align: TextAlign.center, hint: 'Type your text')),
        );
      case 'two_column':
        final parts = slide.content.split(RegExp(r'\n-{3,}\n?'));
        body = Padding(
          padding: const EdgeInsets.fromLTRB(70, 50, 70, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            text(titleC, slide.title, titleStyle, hint: 'Click to add title'),
            Container(margin: const EdgeInsets.symmetric(vertical: 16), width: 90, height: 4, color: accent),
            Expanded(
              child: _edit
                  ? text(contentC, slide.content, bodyStyle, hint: 'Left column…\n---\nRight column…')
                  : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: bullets(parts.isNotEmpty ? parts[0] : '', size: 22)),
                      const SizedBox(width: 40),
                      Expanded(child: bullets(parts.length > 1 ? parts.sublist(1).join('\n') : '', size: 22)),
                    ]),
            ),
          ]),
        );
      default: // title_content
        body = Padding(
          padding: const EdgeInsets.fromLTRB(70, 50, 70, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            text(titleC, slide.title, titleStyle, hint: 'Click to add title'),
            Container(margin: const EdgeInsets.symmetric(vertical: 16), width: 90, height: 4, color: accent),
            Expanded(
              child: _edit
                  ? text(contentC, slide.content, bodyStyle, hint: 'One point per line')
                  : SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: bullets(slide.content)),
            ),
          ]),
        );
    }
    return Container(width: _kW, height: _kH, color: bg, child: body);
  }
}
// darkify:on

// ---------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------
List<_Slide> _templateSlides(String key) {
  switch (key) {
    case 'lesson':
      return [
        _Slide(layout: 'title', title: 'Lesson title', content: 'Speaker · date'),
        _Slide(layout: 'quote', title: '— Reference', content: 'Key verse'),
        _Slide(title: 'Point 1', content: 'Explanation\nSupporting verse\nApplication'),
        _Slide(title: 'Point 2', content: 'Explanation\nSupporting verse\nApplication'),
        _Slide(title: 'Point 3', content: 'Explanation\nSupporting verse\nApplication'),
        _Slide(layout: 'section', title: 'Summary', content: 'What we learned today'),
      ];
    case 'meeting':
      return [
        _Slide(layout: 'title', title: 'Meeting', content: DateFormat('d MMMM yyyy').format(DateTime.now())),
        _Slide(title: 'Agenda', content: 'Opening\nReview of last meeting\nReports\nDecisions\nClosing'),
        _Slide(layout: 'two_column', title: 'Updates', content: 'Done\n---\nIn progress'),
        _Slide(title: 'Decisions', content: ''),
        _Slide(title: 'Next steps', content: 'Who · what · by when'),
      ];
    case 'report':
      return [
        _Slide(layout: 'title', title: 'Activity report', content: 'Unit · period'),
        _Slide(title: 'Key figures', content: 'Attendance\nEvangelism\nOffering\nEducation'),
        _Slide(title: 'Highlights', content: ''),
        _Slide(title: 'Challenges', content: ''),
        _Slide(title: 'Plans', content: ''),
      ];
    case 'announcement':
      return [
        _Slide(layout: 'section', title: 'Announcements', content: DateFormat('d MMMM yyyy').format(DateTime.now())),
        _Slide(title: 'This week', content: 'Event · day · time · place'),
        _Slide(title: 'Coming up', content: ''),
        _Slide(layout: 'blank', content: 'Thank you!'),
      ];
    case 'event':
      return [
        _Slide(layout: 'title', title: 'Event name', content: 'Date · venue'),
        _Slide(title: 'Programme', content: 'Opening prayer\nPraise\nWelcome\nMessage\nClosing'),
        _Slide(layout: 'two_column', title: 'Teams', content: 'Ushering\nMedia\n---\nWelfare\nSecurity'),
        _Slide(layout: 'section', title: 'Welcome!', content: ''),
      ];
    case 'training':
      return [
        _Slide(layout: 'title', title: 'Training / workshop', content: 'Facilitator · date'),
        _Slide(title: 'Objectives', content: 'By the end of this session you will…'),
        _Slide(title: 'Session 1', content: ''),
        _Slide(title: 'Session 2', content: ''),
        _Slide(title: 'Practice', content: 'Activity\nDiscussion'),
        _Slide(title: 'Questions', content: ''),
      ];
    case 'welcome':
      return [
        _Slide(layout: 'section', title: 'Welcome', content: 'We are glad you are here'),
        _Slide(layout: 'quote', title: '— Reference', content: 'Verse of the day'),
        _Slide(title: 'Today', content: 'Praise\nMessage\nFellowship'),
      ];
    default:
      return [_Slide(layout: 'title', title: '', content: '')];
  }
}

const Map<String, String> _templateTheme = {
  'blank': 'classic',
  'lesson': 'purple',
  'meeting': 'classic',
  'report': 'sky',
  'announcement': 'sunset',
  'event': 'dark',
  'training': 'forest',
  'welcome': 'purple',
};

Widget _templatePreview(String key) {
  final s = _templateSlides(key).first;
  if (key == 'blank') {
    s.title = 'Click to add title';
    s.content = 'Subtitle';
  }
  return _SlideView(slide: s, theme: _themeFor(_templateTheme[key]));
}

final List<OfficeTemplate> _templates = [
  OfficeTemplate('blank', 'Blank presentation', 'One title slide', Icons.add_to_photos_outlined, preview: () => _templatePreview('blank')),
  OfficeTemplate('lesson', 'Lesson / sermon', 'Title, verse, 3 points, summary', Icons.menu_book_outlined, preview: () => _templatePreview('lesson')),
  OfficeTemplate('meeting', 'Meeting', 'Agenda, updates, decisions', Icons.groups_outlined, preview: () => _templatePreview('meeting')),
  OfficeTemplate('report', 'Report', 'Figures, highlights, plans', Icons.assessment_outlined, preview: () => _templatePreview('report')),
  OfficeTemplate('announcement', 'Announcements', 'This week and coming up', Icons.campaign_outlined, preview: () => _templatePreview('announcement')),
  OfficeTemplate('event', 'Event', 'Programme and teams', Icons.celebration_outlined, preview: () => _templatePreview('event')),
  OfficeTemplate('training', 'Training / workshop', 'Objectives, sessions, practice', Icons.school_outlined, preview: () => _templatePreview('training')),
  OfficeTemplate('welcome', 'Welcome', 'Welcome, verse, today', Icons.waving_hand_outlined, preview: () => _templatePreview('welcome')),
];

const Map<String, String> _templateTitles = {
  'blank': 'Untitled presentation',
  'lesson': 'Lesson',
  'meeting': 'Meeting',
  'report': 'Activity report',
  'announcement': 'Announcements',
  'event': 'Event',
  'training': 'Training',
  'welcome': 'Welcome',
};

class _PresentationScreenState extends State<PresentationScreen> {
  final _db = Supabase.instance.client;

  // hub
  List<Map<String, dynamic>> _decks = [];
  bool _loadingDecks = true;
  String _search = '';

  // editor
  bool _open = false;
  String? _deckId;
  final _titleC = TextEditingController();
  String _theme = 'classic';
  String _transition = 'fade';
  List<_Slide> _slides = [];
  final List<String> _deletedIds = [];
  bool _orderDirty = false;
  int _current = 0;
  int _tab = 1; // File, Home, Insert, Design, Transitions, Slide Show, View
  double? _zoom; // null = fit
  String _view = 'normal'; // normal | sorter
  bool _showNotes = true;
  Timer? _saveTimer;
  String _saveState = 'saved';
  final Map<_Slide, (TextEditingController, TextEditingController, TextEditingController)> _ctrl = {};
  TextEditingController? _focusedText;
  _Slide? _clipSlide;
  final _vScroll = ScrollController();
  final _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    OfficeBrowserMenu.acquire();
    _loadDecks();
  }

  @override
  void dispose() {
    OfficeBrowserMenu.release();
    _saveTimer?.cancel();
    if (_open && _saveState == 'unsaved') _save();
    _titleC.dispose();
    _disposeControllers();
    _vScroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  void _disposeControllers() {
    for (final c in _ctrl.values) {
      c.$1.dispose();
      c.$2.dispose();
      c.$3.dispose();
    }
    _ctrl.clear();
    _focusedText = null;
  }

  (TextEditingController, TextEditingController, TextEditingController) _controllersFor(_Slide s) {
    return _ctrl.putIfAbsent(s, () {
      final t = TextEditingController(text: s.title);
      final c = TextEditingController(text: s.content);
      final n = TextEditingController(text: s.notes);
      t.addListener(() {
        if (t.text != s.title) {
          s.title = t.text;
          _changed(s);
        }
      });
      c.addListener(() {
        if (c.text != s.content) {
          s.content = c.text;
          _changed(s);
        }
      });
      n.addListener(() {
        if (n.text != s.notes) {
          s.notes = n.text;
          _changed(s, rebuild: false);
        }
      });
      return (t, c, n);
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  _Slide get _slide => _slides[_current];
  _Theme get _th => _themeFor(_theme);

  // ------------------------------------------------------------------
  // Data
  // ------------------------------------------------------------------
  Future<void> _loadDecks() async {
    setState(() => _loadingDecks = true);
    try {
      final r = await _db.from('presentations').select('id, title, last_modified, created_at, theme').order('last_modified', ascending: false);
      if (mounted) {
        setState(() {
          _decks = List<Map<String, dynamic>>.from(r);
          _loadingDecks = false;
        });
      }
    } catch (e) {
      debugPrint("Decks error: $e");
      if (mounted) setState(() => _loadingDecks = false);
    }
  }

  Future<void> _create(OfficeTemplate t) async {
    try {
      if (_open) await _close();
      final deck = await _db
          .from('presentations')
          .insert({'title': _templateTitles[t.key] ?? t.name, 'owner_email': widget.userEmail, 'theme': '${_templateTheme[t.key] ?? 'classic'}|fade'})
          .select('id')
          .single();
      final id = deck['id'].toString();
      final slides = _templateSlides(t.key);
      await _db.from('presentation_slides').insert([
        for (int i = 0; i < slides.length; i++)
          {
            'presentation_id': id,
            'slide_order': i,
            'title': slides[i].title,
            'content': slides[i].content,
            'layout': slides[i].layout,
          }
      ]);
      await _openDeck(id);
    } catch (e) {
      _snack("Couldn't create the presentation: ${e is PostgrestException ? e.message : e}");
    }
  }

  Future<void> _pickTemplate() async {
    final t = await showOfficeTemplates(context, title: "Presentation templates", templates: _templates, accent: _kOrange);
    if (t != null) await _create(t);
  }

  Future<void> _openDeck(String id) async {
    try {
      final deck = await _db.from('presentations').select().eq('id', id).single();
      final rows = await _db.from('presentation_slides').select().eq('presentation_id', id).order('slide_order');
      final slides = (rows as List)
          .map((r) => _Slide(
                id: r['id']?.toString(),
                title: (r['title'] ?? '').toString(),
                content: (r['content'] ?? '').toString(),
                layout: _layoutNames.containsKey(r['layout']) ? r['layout'].toString() : 'title_content',
                bg: r['bg_color']?.toString(),
                fg: r['text_color']?.toString(),
                notes: (r['notes'] ?? '').toString(),
                dirty: false,
              ))
          .toList();
      if (slides.isEmpty) slides.add(_Slide(layout: 'title'));
      _disposeControllers();
      // the theme column holds "theme|transition"
      final parts = (deck['theme'] ?? 'classic').toString().split('|');
      setState(() {
        _deckId = id;
        _titleC.text = (deck['title'] ?? 'Untitled presentation').toString();
        _theme = parts.first.isEmpty ? 'classic' : parts.first;
        _transition = parts.length > 1 && _transitionNames.containsKey(parts[1]) ? parts[1] : 'fade';
        _slides = slides;
        _deletedIds.clear();
        _orderDirty = false;
        _current = 0;
        _view = 'normal';
        _saveState = 'saved';
        _open = true;
      });
    } catch (e) {
      _snack("Couldn't open the presentation.");
    }
  }

  void _changed(_Slide? s, {bool rebuild = true}) {
    s?.dirty = true;
    _saveState = 'unsaved';
    if (rebuild && mounted) setState(() {});
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() async {
    final id = _deckId;
    if (id == null) return;
    _saveTimer?.cancel();
    if (mounted) setState(() => _saveState = 'saving');
    try {
      for (final d in List<String>.from(_deletedIds)) {
        await _db.from('presentation_slides').delete().eq('id', d);
        _deletedIds.remove(d);
      }
      for (int i = 0; i < _slides.length; i++) {
        final s = _slides[i];
        final data = {
          'slide_order': i,
          'title': s.title,
          'content': s.content,
          'layout': s.layout,
          'bg_color': s.bg,
          'text_color': s.fg,
          'notes': s.notes,
        };
        if (s.id == null) {
          final row = await _db.from('presentation_slides').insert({...data, 'presentation_id': id}).select('id').single();
          s.id = row['id'].toString();
        } else if (s.dirty || _orderDirty) {
          await _db.from('presentation_slides').update(data).eq('id', s.id!);
        }
        s.dirty = false;
      }
      _orderDirty = false;
      await _db.from('presentations').update({
        'title': _titleC.text.trim().isEmpty ? 'Untitled presentation' : _titleC.text.trim(),
        'theme': '$_theme|$_transition',
        'last_modified': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      if (mounted) setState(() => _saveState = 'saved');
    } catch (e) {
      debugPrint("Deck save error: $e");
      if (mounted) setState(() => _saveState = 'error');
    }
  }

  Future<void> _close() async {
    if (_saveState != 'saved') await _save();
    if (!mounted) return;
    _disposeControllers();
    setState(() => _open = false);
    _loadDecks();
  }

  // ------------------------------------------------------------------
  // Slide actions
  // ------------------------------------------------------------------
  void _select(int i) {
    if (i < 0 || i >= _slides.length) return;
    setState(() {
      _current = i;
      _focusedText = null;
    });
  }

  void _addSlide(String layout) {
    setState(() {
      _slides.insert(_current + 1, _Slide(layout: layout));
      _current++;
      _orderDirty = true;
    });
    _changed(null);
  }

  void _duplicateSlide() {
    setState(() {
      _slides.insert(_current + 1, _slide.copy());
      _current++;
      _orderDirty = true;
    });
    _changed(null);
  }

  void _deleteSlide() {
    if (_slides.length <= 1) {
      _snack("A presentation needs at least one slide.");
      return;
    }
    setState(() {
      final s = _slides.removeAt(_current);
      if (s.id != null) _deletedIds.add(s.id!);
      final c = _ctrl.remove(s);
      if (c != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          c.$1.dispose();
          c.$2.dispose();
          c.$3.dispose();
        });
      }
      _focusedText = null;
      if (_current >= _slides.length) _current = _slides.length - 1;
      _orderDirty = true;
    });
    _changed(null);
  }

  void _move(int delta) {
    final to = _current + delta;
    if (to < 0 || to >= _slides.length) return;
    setState(() {
      final s = _slides.removeAt(_current);
      _slides.insert(to, s);
      _current = to;
      _orderDirty = true;
    });
    _changed(null);
  }

  void _copySlide() {
    _clipSlide = _slide.copy();
    _snack("Slide copied. Use Paste slide to add it.");
  }

  void _pasteSlide() {
    final c = _clipSlide;
    if (c == null) return;
    setState(() {
      _slides.insert(_current + 1, c.copy());
      _current++;
      _orderDirty = true;
    });
    _changed(null);
  }

  void _setLayout(String v) {
    setState(() => _slide.layout = v);
    _changed(_slide);
  }

  void _setBg(String? h) {
    setState(() => _slide.bg = h);
    _changed(_slide);
  }

  void _setFg(String? h) {
    setState(() => _slide.fg = h);
    _changed(_slide);
  }

  void _present(int from) {
    Navigator.push(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _PresentView(slides: _slides, theme: _th, start: from, transition: _transition)),
    );
  }

  // text in the focused box (right-click menu)
  Future<void> _textCopy({bool cut = false}) async {
    final c = _focusedText;
    if (c == null) return;
    final s = c.selection;
    if (!s.isValid || s.isCollapsed) return;
    await Clipboard.setData(ClipboardData(text: s.textInside(c.text)));
    if (cut) {
      c.value = c.value.copyWith(text: s.textBefore(c.text) + s.textAfter(c.text), selection: TextSelection.collapsed(offset: s.start));
    }
  }

  Future<void> _textPaste() async {
    final c = _focusedText;
    if (c == null) return;
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text;
    if (t == null || t.isEmpty) return;
    final s = c.selection.isValid ? c.selection : TextSelection.collapsed(offset: c.text.length);
    c.value = c.value.copyWith(text: s.textBefore(c.text) + t + s.textAfter(c.text), selection: TextSelection.collapsed(offset: s.start + t.length));
  }

  List<OfficeMenuItem> _slideMenu({bool onCanvas = false}) => [
        if (onCanvas) ...[
          OfficeMenuItem("Cut", icon: Icons.content_cut, shortcut: "Ctrl+X", onTap: _focusedText == null ? null : () => _textCopy(cut: true)),
          OfficeMenuItem("Copy", icon: Icons.content_copy, shortcut: "Ctrl+C", onTap: _focusedText == null ? null : () => _textCopy()),
          OfficeMenuItem("Paste", icon: Icons.content_paste, shortcut: "Ctrl+V", color: Colors.orange.shade800, onTap: _focusedText == null ? null : _textPaste),
          const OfficeMenuItem.divider(),
        ],
        OfficeMenuItem("New slide", icon: Icons.add_box_outlined, shortcut: "Ctrl+M", onTap: () => _addSlide('title_content')),
        OfficeMenuItem("Duplicate slide", icon: Icons.copy_all, shortcut: "Ctrl+D", onTap: _duplicateSlide),
        OfficeMenuItem("Copy slide", icon: Icons.file_copy_outlined, onTap: _copySlide),
        OfficeMenuItem("Paste slide", icon: Icons.content_paste_go, onTap: _clipSlide == null ? null : _pasteSlide),
        OfficeMenuItem("Delete slide", icon: Icons.delete_sweep_outlined, color: Colors.red.shade700, onTap: _slides.length > 1 ? _deleteSlide : null),
        const OfficeMenuItem.divider(),
        OfficeMenuItem("Move up", icon: Icons.arrow_upward_rounded, shortcut: "Ctrl+↑", onTap: _current > 0 ? () => _move(-1) : null),
        OfficeMenuItem("Move down", icon: Icons.arrow_downward_rounded, shortcut: "Ctrl+↓", onTap: _current < _slides.length - 1 ? () => _move(1) : null),
        const OfficeMenuItem.divider(),
        for (final e in _layoutNames.entries)
          OfficeMenuItem("Layout: ${e.value}", icon: e.key == _slide.layout ? Icons.radio_button_checked : Icons.radio_button_unchecked, onTap: () => _setLayout(e.key)),
        const OfficeMenuItem.divider(),
        OfficeMenuItem("Format background…", icon: Icons.wallpaper, onTap: () => setState(() => _tab = 3)),
        OfficeMenuItem("Transitions…", icon: Icons.auto_fix_high, onTap: () => setState(() => _tab = 4)),
        OfficeMenuItem("Present from this slide", icon: Icons.slideshow_rounded, shortcut: "Shift+F5", onTap: () => _present(_current)),
      ];

  // ------------------------------------------------------------------
  // PDF
  // ------------------------------------------------------------------
  Future<Uint8List> _buildPdf([PdfPageFormat? format]) async {
    pw.ThemeData theme;
    try {
      theme = pw.ThemeData.withFont(
        base: await PdfGoogleFonts.merriweatherRegular(),
        bold: await PdfGoogleFonts.merriweatherBold(),
        italic: await PdfGoogleFonts.merriweatherItalic(),
        fontFallback: [await PdfGoogleFonts.notoSansKRRegular()],
      );
    } catch (_) {
      theme = pw.ThemeData();
    }
    final doc = pw.Document(theme: theme, title: _titleC.text.trim());
    final th = _th;
    PdfColor pc(Color c) => PdfColor.fromInt(c.toARGB32());
    for (final s in _slides) {
      final bg = _hex(s.bg, s.layout == 'section' ? th.accent : th.bg);
      final fg = _hex(s.fg, s.layout == 'section' ? Colors.white : th.fg);
      final accent = s.layout == 'section' ? Colors.white : th.accent;
      final lines = s.content.split('\n').where((l) => l.trim().isNotEmpty && !RegExp(r'^-{3,}$').hasMatch(l.trim())).toList();
      final centered = s.layout == 'title' || s.layout == 'quote' || s.layout == 'blank';
      doc.addPage(pw.Page(
        pageFormat: const PdfPageFormat(_kW, _kH),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Container(
          color: pc(bg),
          padding: const pw.EdgeInsets.symmetric(horizontal: 70, vertical: 50),
          child: pw.Column(
            mainAxisAlignment: centered || s.layout == 'section' ? pw.MainAxisAlignment.center : pw.MainAxisAlignment.start,
            crossAxisAlignment: centered ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start,
            children: [
              if (s.layout == 'quote') ...[
                pw.Text(s.content, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 30, fontStyle: pw.FontStyle.italic, color: pc(fg))),
                pw.SizedBox(height: 18),
                pw.Text(s.title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: pc(accent))),
              ] else ...[
                if (s.title.isNotEmpty)
                  pw.Text(s.title,
                      textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left,
                      style: pw.TextStyle(fontSize: s.layout == 'title' || s.layout == 'section' ? 50 : 38, fontWeight: pw.FontWeight.bold, color: pc(fg))),
                pw.SizedBox(height: 12),
                pw.Container(width: 90, height: 4, color: pc(accent)),
                pw.SizedBox(height: 16),
                if (s.layout == 'title' || s.layout == 'blank' || s.layout == 'section')
                  pw.Text(s.content, textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left, style: pw.TextStyle(fontSize: 24, color: pc(fg)))
                else
                  for (final l in lines)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 8),
                      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Container(margin: const pw.EdgeInsets.only(top: 9, right: 12), width: 8, height: 8, decoration: pw.BoxDecoration(color: pc(accent), shape: pw.BoxShape.circle)),
                        pw.Expanded(child: pw.Text(l.trim(), style: pw.TextStyle(fontSize: 22, color: pc(fg)))),
                      ]),
                    ),
              ],
            ],
          ),
        ),
      ));
    }
    return doc.save();
  }

  String get _fileName => (_titleC.text.trim().isEmpty ? 'presentation' : _titleC.text.trim()).replaceAll(RegExp(r'[^A-Za-z0-9가-힣 _-]'), '');

  Future<void> _exportPdf() async {
    try {
      final bytes = await _buildPdf();
      await Printing.sharePdf(bytes: bytes, filename: '$_fileName.pdf');
    } catch (e) {
      _snack("Couldn't make the PDF.");
    }
  }

  Future<void> _print() => TableExport.previewBuilder(context, _titleC.text.trim().isEmpty ? 'Presentation' : _titleC.text.trim(), _buildPdf,
      fileName: '$_fileName.pdf', initial: const PdfPageFormat(_kW, _kH));

  // ------------------------------------------------------------------
  // Hub
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _open ? _editor() : _hub());

  String _when(dynamic v) {
    final t = DateTime.tryParse((v ?? '').toString())?.toLocal();
    return t == null ? '—' : DateFormat('d MMM yyyy, HH:mm').format(t);
  }

  Future<void> _renameDeck(Map<String, dynamic> d) async {
    final name = await officeAsk(context, "Rename presentation", (d['title'] ?? '').toString(), ok: "Rename");
    if (name == null || name.isEmpty) return;
    await _db.from('presentations').update({'title': name}).eq('id', d['id']);
    _loadDecks();
  }

  Future<void> _duplicateDeck(Map<String, dynamic> d) async {
    try {
      final slides = await _db.from('presentation_slides').select().eq('presentation_id', d['id']).order('slide_order');
      final deck = await _db.from('presentations').insert({'title': "${d['title'] ?? 'Presentation'} (copy)", 'owner_email': widget.userEmail, 'theme': d['theme']}).select('id').single();
      final rows = [
        for (final s in slides as List)
          {
            'presentation_id': deck['id'],
            'slide_order': s['slide_order'],
            'title': s['title'],
            'content': s['content'],
            'layout': s['layout'],
            'bg_color': s['bg_color'],
            'text_color': s['text_color'],
            'notes': s['notes'],
          }
      ];
      if (rows.isNotEmpty) await _db.from('presentation_slides').insert(rows);
      _loadDecks();
      _snack("Copy made.");
    } catch (_) {
      _snack("Couldn't duplicate it.");
    }
  }

  Future<void> _deleteDeck(Map<String, dynamic> d) async {
    if (!await officeConfirm(context, "Delete \"${d['title']}\"?", "All its slides are deleted. This can't be undone.")) return;
    await _db.from('presentation_slides').delete().eq('presentation_id', d['id']);
    await _db.from('presentations').delete().eq('id', d['id']);
    _loadDecks();
  }

  Widget _hub() {
    final q = _search.trim().toLowerCase();
    final decks = q.isEmpty ? _decks : _decks.where((d) => (d['title'] ?? '').toString().toLowerCase().contains(q)).toList();
    return CallbackShortcuts(
      key: const ValueKey('hub'),
      bindings: officeKeys({LogicalKeyboardKey.keyN: () => _create(_templates.first)}),
      child: Focus(
        autofocus: true,
        child: OfficeHub(
          title: "Presentation Hub",
          accent: _kOrange,
          accent2: Colors.orange.shade800,
          actions: [
            OfficeHubAction("New Presentation", Icons.add_to_photos, _kOrange, () => _create(_templates.first)),
            OfficeHubAction("Open Existing", Icons.folder_shared, Colors.blue, () => _snack("Pick a presentation from the list, or search for it.")),
            OfficeHubAction("Templates", Icons.style, Colors.green, _pickTemplate),
          ],
          templates: _templates,
          onTemplate: _create,
          onAllTemplates: _pickTemplate,
          files: decks,
          loading: _loadingDecks,
          searchHint: "Search decks…",
          emptyText: _decks.isEmpty ? "No presentations yet. Start one from a template." : "No presentations match.",
          onSearch: (v) => setState(() => _search = v),
          fileIcon: Icons.slideshow,
          fileIconColor: _kOrange,
          fileSubtitle: (d) => "Modified: ${_when(d['last_modified'] ?? d['created_at'])}",
          onOpen: (d) => _openDeck(d['id'].toString()),
          fileMenu: (d) => [
            OfficeMenuItem("Open", icon: Icons.open_in_new, onTap: () => _openDeck(d['id'].toString())),
            OfficeMenuItem("Rename", icon: Icons.drive_file_rename_outline, onTap: () => _renameDeck(d)),
            OfficeMenuItem("Make a copy", icon: Icons.copy_rounded, onTap: () => _duplicateDeck(d)),
            const OfficeMenuItem.divider(),
            OfficeMenuItem("Delete", icon: Icons.delete_outline, color: Colors.red.shade700, onTap: () => _deleteDeck(d)),
          ],
          onRefresh: _loadDecks,
          guideIcon: Icons.lightbulb_outline,
          guideLines: const [
            "Right-click a slide or a thumbnail for slide actions: layouts, duplicate, delete, background, transitions.",
            "F5 presents from the start; Shift+F5 from the current slide. Arrow keys / tap to move, Esc to leave.",
            "Use the scroll arrows for fine movement when zoomed in; Fit keeps the slide centred.",
            "Saves to the cloud automatically (Ctrl+S saves now). Ctrl+M new slide, Ctrl+D duplicate.",
            "Download as PDF or print with a preview (Ctrl+P). Your presentations are private.",
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Editor
  // ------------------------------------------------------------------
  // darkify:off — slide designs keep their own colours in dark mode
  Widget _swatch(String hex, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _hex(hex, Colors.white),
              shape: BoxShape.circle,
              border: Border.all(color: selected ? _kOrange : Colors.black26, width: selected ? 3 : 1),
            ),
            child: hex.isEmpty ? const Icon(Icons.format_color_reset, size: 13, color: Colors.black45) : null,
          ),
        ),
      );

  Widget _themeCard(_Theme t) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Tooltip(
          message: t.name,
          child: InkWell(
            onTap: () {
              setState(() => _theme = t.key);
              _changed(null);
            },
            child: Container(
              width: 46,
              decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(5), border: Border.all(color: _theme == t.key ? _kOrange : Colors.black26, width: _theme == t.key ? 2.5 : 1)),
              child: Center(child: Container(width: 22, height: 4, color: t.accent)),
            ),
          ),
        ),
      );
  // darkify:on

  List<OfficeRibbonTab> _ribbonTabs() {
    OfficeAction a(IconData i, String l, VoidCallback? f, {String? tip, bool sel = false}) => OfficeAction(i, l, f, tooltip: tip, accent: _kOrange, selected: sel);
    final layoutChoices = [for (final e in _layoutNames.entries) (e.key, e.value)];
    return [
      OfficeRibbonTab("File", () => [
            a(Icons.note_add_outlined, "New", _pickTemplate, tip: "New from a template"),
            a(Icons.folder_open, "Open", _close, tip: "Back to my presentations"),
            a(Icons.cloud_upload_outlined, "Save", _save, tip: "Ctrl+S"),
            a(Icons.drive_file_rename_outline, "Rename", () async {
              final n = await officeAsk(context, "Rename presentation", _titleC.text, ok: "Rename");
              if (n != null && n.isNotEmpty) {
                _titleC.text = n;
                _changed(null);
              }
            }),
            const OfficeRibbonGap(),
            a(Icons.picture_as_pdf_outlined, "Download PDF", _exportPdf),
            a(Icons.print_outlined, "Print", _print, tip: "Ctrl+P"),
            const OfficeRibbonGap(),
            a(Icons.close, "Close", _close),
          ]),
      OfficeRibbonTab("Home", () => [
            OfficeMenuAction<String>(Icons.add_box_outlined, "New slide", layoutChoices, _addSlide, accent: _kOrange, tooltip: "Ctrl+M"),
            a(Icons.copy_all_rounded, "Duplicate", _duplicateSlide, tip: "Ctrl+D"),
            a(Icons.delete_outline_rounded, "Delete", _slides.length > 1 ? _deleteSlide : null),
            a(Icons.arrow_upward_rounded, "Move up", _current > 0 ? () => _move(-1) : null),
            a(Icons.arrow_downward_rounded, "Move down", _current < _slides.length - 1 ? () => _move(1) : null),
            const OfficeRibbonGap(),
            OfficeMenuAction<String>(Icons.view_quilt_outlined, "Layout: ${_layoutNames[_slide.layout]}", layoutChoices, _setLayout, accent: _kOrange),
            a(Icons.file_copy_outlined, "Copy slide", _copySlide),
            a(Icons.content_paste_go, "Paste slide", _clipSlide == null ? null : _pasteSlide),
          ]),
      OfficeRibbonTab("Insert", () => [
            for (final e in _layoutNames.entries) a(Icons.add_rounded, e.value, () => _addSlide(e.key)),
            const OfficeRibbonGap(),
            a(Icons.today_outlined, "Date", () {
              final c = _controllersFor(_slide).$2;
              c.text = c.text.isEmpty ? DateFormat('d MMMM yyyy').format(DateTime.now()) : "${c.text}\n${DateFormat('d MMMM yyyy').format(DateTime.now())}";
            }),
            a(Icons.sticky_note_2_outlined, "Speaker notes", () => setState(() => _showNotes = true)),
          ]),
      OfficeRibbonTab("Design", () => [
            const Center(child: Text("Theme ", style: TextStyle(fontSize: 11))),
            for (final t in _themes) _themeCard(t),
            const OfficeRibbonGap(),
            const Center(child: Text("Background ", style: TextStyle(fontSize: 11))),
            _swatch('', _slide.bg == null, () => _setBg(null)),
            for (final h in _swatches) _swatch(h, _slide.bg == h, () => _setBg(h)),
            const OfficeRibbonGap(),
            const Center(child: Text("Text ", style: TextStyle(fontSize: 11))),
            _swatch('', _slide.fg == null, () => _setFg(null)),
            for (final h in const ['#FFFFFF', '#111827', '#3B0764', '#B7472A', '#0D47A1']) _swatch(h, _slide.fg == h, () => _setFg(h)),
            const OfficeRibbonGap(),
            a(Icons.format_paint_outlined, "Apply colours to all slides", () {
              for (final s in _slides) {
                s.bg = _slide.bg;
                s.fg = _slide.fg;
                s.dirty = true;
              }
              _changed(null);
            }),
          ]),
      OfficeRibbonTab("Transitions", () => [
            for (final e in _transitionNames.entries)
              a(
                  e.key == 'none'
                      ? Icons.block
                      : e.key == 'fade'
                          ? Icons.gradient
                          : e.key == 'slide'
                              ? Icons.swipe_left_alt_outlined
                              : Icons.zoom_out_map,
                  e.value, () {
                setState(() => _transition = e.key);
                _changed(null);
              }, sel: _transition == e.key),
            const OfficeRibbonGap(),
            a(Icons.play_arrow_rounded, "Preview", () => _present(_current)),
          ]),
      OfficeRibbonTab("Slide Show", () => [
            a(Icons.play_circle_outline_rounded, "From the beginning", () => _present(0), tip: "F5"),
            a(Icons.slideshow_rounded, "From this slide", () => _present(_current), tip: "Shift+F5"),
            a(Icons.picture_as_pdf_outlined, "Export as PDF", _exportPdf),
          ]),
      OfficeRibbonTab("View", () => [
            a(Icons.crop_original, "Normal", () => setState(() => _view = 'normal'), sel: _view == 'normal'),
            a(Icons.grid_view_rounded, "Slide sorter", () => setState(() => _view = 'sorter'), sel: _view == 'sorter'),
            a(Icons.sticky_note_2_outlined, _showNotes ? "Hide notes" : "Show notes", () => setState(() => _showNotes = !_showNotes), sel: _showNotes),
            const OfficeRibbonGap(),
            for (final z in const [null, 0.5, 0.75, 1.0]) a(Icons.zoom_in, z == null ? 'Fit' : '${(z * 100).round()}%', () => setState(() => _zoom = z), sel: _zoom == z),
          ]),
    ];
  }

  Widget _thumb(int i, {double width = 140}) {
    final sel = i == _current;
    return OfficeRightClick(
      longPress: true,
      onMenu: (p) {
        _select(i);
        showOfficeMenu(context, p, _slideMenu());
      },
      child: GestureDetector(
        onTap: () => _select(i),
        onDoubleTap: () => setState(() {
          _current = i;
          _view = 'normal';
        }),
        child: Container(
          width: width,
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppPalette.bg(sel ? _kOrange.withValues(alpha: 0.1) : Colors.white),
            border: Border.all(color: AppPalette.line(sel ? _kOrange : Colors.grey.shade300), width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(3),
          child: Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: AspectRatio(aspectRatio: 16 / 9, child: FittedBox(fit: BoxFit.contain, child: _SlideView(slide: _slides[i], theme: _th))),
            ),
            Positioned(
              left: 3,
              top: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _canvas(bool desktop) {
    final c = _controllersFor(_slide);
    final view = Container(
      decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 6))]),
      child: _SlideView(
        key: ValueKey(_slide),
        slide: _slide,
        theme: _th,
        titleC: c.$1,
        contentC: c.$2,
        ownMenus: desktop,
        onFocusText: (tc) => _focusedText = tc,
      ),
    );
    final canvas = LayoutBuilder(builder: (context, box) {
      if (_zoom == null) {
        // Default: centred and scaled to fit the space available
        return Center(
          child: Padding(
            padding: EdgeInsets.all(box.maxWidth < 600 ? 10 : 36),
            child: AspectRatio(aspectRatio: 16 / 9, child: FittedBox(fit: BoxFit.contain, child: view)),
          ),
        );
      }
      final w = _kW * _zoom!, h = _kH * _zoom!;
      return SingleChildScrollView(
        controller: _hScroll,
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: box.maxWidth),
          child: SingleChildScrollView(
            controller: _vScroll,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(50),
                  child: SizedBox(width: w, height: h, child: FittedBox(fit: BoxFit.contain, child: view)),
                ),
              ),
            ),
          ),
        ),
      );
    });
    return OfficeRightClick(onMenu: (p) => showOfficeMenu(context, p, _slideMenu(onCanvas: true)), child: canvas);
  }

  Widget _sorter() => LayoutBuilder(
        builder: (context, box) => GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: box.maxWidth < 600 ? 200 : 260, mainAxisExtent: (box.maxWidth < 600 ? 200 : 260) * 9 / 16 + 22, crossAxisSpacing: 4, mainAxisSpacing: 4),
          itemCount: _slides.length,
          itemBuilder: (_, i) => _thumb(i, width: double.infinity),
        ),
      );

  Widget _editor() {
    final status = officeSaveStatus(_saveState);
    return PopScope(
      key: const ValueKey('editor'),
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: CallbackShortcuts(
        bindings: {
          ...officeKeys({
            LogicalKeyboardKey.keyS: _save,
            LogicalKeyboardKey.keyP: _print,
            LogicalKeyboardKey.keyM: () => _addSlide('title_content'),
            LogicalKeyboardKey.keyD: _duplicateSlide,
            LogicalKeyboardKey.arrowUp: () => _move(-1),
            LogicalKeyboardKey.arrowDown: () => _move(1),
          }),
          const SingleActivator(LogicalKeyboardKey.f5): () => _present(0),
          const SingleActivator(LogicalKeyboardKey.f5, shift: true): () => _present(_current),
          const SingleActivator(LogicalKeyboardKey.pageDown): () => _select(_current + 1),
          const SingleActivator(LogicalKeyboardKey.pageUp): () => _select(_current - 1),
        },
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final mobile = box.maxWidth < 600;
          final notesC = _controllersFor(_slide).$3;
          return Scaffold(
            backgroundColor: AppPalette.bg(const Color(0xFFCBCBCB)),
            body: SafeArea(
              child: Column(children: [
                OfficeHeaderCard(
                  accent: _kOrange,
                  titleController: _titleC,
                  onTitleChanged: (_) => _changed(null),
                  subtitle: "Cloud Deck: ${widget.userEmail} · ${status.$1}",
                  subtitleColor: status.$3,
                  onClose: _close,
                  actions: [
                    IconButton(tooltip: "Save now (Ctrl+S)", icon: Icon(status.$2, color: AppPalette.fg(status.$3)), onPressed: _save),
                    IconButton(
                      tooltip: "Present (F5 from the start)",
                      icon: Icon(Icons.play_circle_fill, color: AppPalette.fg(_kOrange), size: 30),
                      onPressed: () => _present(_current),
                    ),
                  ],
                ),
                OfficeRibbon(tabs: _ribbonTabs(), active: _tab, onTab: (i) => setState(() => _tab = i), accent: _kOrange, tint: const Color(0xFFFBE9E7)),
                Expanded(
                  child: _view == 'sorter'
                      ? Container(color: AppPalette.bg(Colors.white), child: _sorter())
                      : wide
                          ? Row(children: [
                              Container(
                                width: 170,
                                color: AppPalette.bg(Colors.white),
                                child: ListView.builder(itemCount: _slides.length, itemBuilder: (_, i) => _thumb(i)),
                              ),
                              Expanded(child: _canvas(true)),
                              if (_zoom != null) OfficeScrollArrows.of(_vScroll, Axis.vertical),
                            ])
                          : Column(children: [
                              Expanded(child: _canvas(!mobile)),
                              Container(
                                height: 86,
                                color: AppPalette.bg(Colors.white),
                                child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _slides.length, itemBuilder: (_, i) => _thumb(i, width: 120)),
                              ),
                            ]),
                ),
                if (wide && _zoom != null && _view == 'normal') OfficeScrollArrows.of(_hScroll, Axis.horizontal, leadingGap: 170),
                if (_showNotes && _view == 'normal')
                  Container(
                    color: AppPalette.bg(Colors.white),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Row(children: [
                      Icon(Icons.sticky_note_2_outlined, size: 16, color: AppPalette.fg(Colors.grey)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: notesC,
                          maxLines: wide ? 2 : 1,
                          style: const TextStyle(fontSize: 12.5),
                          decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: "Speaker notes for this slide"),
                        ),
                      ),
                    ]),
                  ),
                Container(
                  height: 34,
                  color: AppPalette.bg(Colors.white),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Text("Slide ${_current + 1} of ${_slides.length}", style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                    if (!mobile) ...[
                      const SizedBox(width: 12),
                      Text("${_th.name} · ${_transitionNames[_transition]}", style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.grey[700]))),
                    ],
                    const Spacer(),
                    OfficeViewIcon(Icons.crop_original, "Normal", _view == 'normal', () => setState(() => _view = 'normal')),
                    OfficeViewIcon(Icons.grid_view_rounded, "Slide sorter", _view == 'sorter', () => setState(() => _view = 'sorter')),
                    OfficeViewIcon(Icons.menu_book_outlined, "Reading view (from this slide)", false, () => _present(_current)),
                    OfficeViewIcon(Icons.play_arrow_outlined, "Slide show (F5)", false, () => _present(0)),
                    const VerticalDivider(width: 20, indent: 8, endIndent: 8),
                    OfficeZoomPill(
                      zoom: _zoom ?? 0.75,
                      min: 0.25,
                      max: 1.5,
                      label: _zoom == null ? 'Fit' : null,
                      onChanged: (z) => setState(() => _zoom = (z * 100).round() / 100),
                      onReset: () => setState(() => _zoom = null),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

// darkify:off — the slideshow is always black
/// Full-screen slideshow: tap / → / Space / Page Down for next, ← / Page Up
/// for previous, Esc to leave.
class _PresentView extends StatefulWidget {
  final List<_Slide> slides;
  final _Theme theme;
  final int start;
  final String transition;
  const _PresentView({required this.slides, required this.theme, required this.start, this.transition = 'fade'});

  @override
  State<_PresentView> createState() => _PresentViewState();
}

class _PresentViewState extends State<_PresentView> {
  late int _i = widget.start.clamp(0, widget.slides.length - 1).toInt();
  int _dir = 1;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _focus.dispose();
    super.dispose();
  }

  void _go(int d) {
    final n = _i + d;
    if (n < 0) return;
    if (n >= widget.slides.length) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _dir = d;
      _i = n;
    });
  }

  Widget _transition(Widget child, Animation<double> anim) {
    switch (widget.transition) {
      case 'none':
        return child;
      case 'slide':
        final incoming = child.key == ValueKey(_i);
        final begin = Offset(incoming ? _dir.toDouble() : -_dir.toDouble(), 0);
        return SlideTransition(position: Tween<Offset>(begin: begin, end: Offset.zero).animate(anim), child: child);
      case 'zoom':
        return FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween<double>(begin: 0.85, end: 1).animate(anim), child: child));
      default:
        return FadeTransition(opacity: anim, child: child);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.pageDown || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.arrowDown) {
          _go(1);
        } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.pageUp || k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.arrowUp) {
          _go(-1);
        } else if (k == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(builder: (context, box) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _go(d.localPosition.dx < box.maxWidth / 3 ? -1 : 1),
            child: Stack(children: [
              Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: widget.transition == 'none' ? 1 : 350),
                      transitionBuilder: _transition,
                      child: FittedBox(
                        key: ValueKey(_i),
                        fit: BoxFit.contain,
                        child: _SlideView(slide: widget.slides[_i], theme: widget.theme),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: SafeArea(
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: Text("${_i + 1} / ${widget.slides.length}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white70)),
                  ]),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: (_i + 1) / widget.slides.length,
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(widget.theme.accent),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }
}
// darkify:on
