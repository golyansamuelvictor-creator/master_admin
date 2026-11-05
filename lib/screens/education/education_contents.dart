import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_palette.dart';
import '../../core/i18n.dart';
import '../../widgets/nice_range_picker.dart';
import '../../widgets/home_live_cards.dart' show VerticalMarquee;

const Color _kPurple = Color(0xFF4A148C);
const String _bucket = 'education';
const int _maxBytes = 50 * 1024 * 1024; // Supabase's limit per file

/// The kinds of education contents (app_config.education_content_categories)
/// and who manages them (action "Manage Education Contents", 22_round21.sql).
class EduContents {
  EduContents._();
  static const fallback = ["JSS Articles", "Cell Service Materials", "Revelation Sealing Contents", "Test Contents", "Other Contents"];
  static List<String>? _cats;
  static bool? _manager;

  static Future<List<String>> categories() async {
    if (_cats != null) return _cats!;
    try {
      final r = await Supabase.instance.client.from('app_config').select('config_value').eq('config_key', 'education_content_categories').maybeSingle();
      final v = r?['config_value'];
      _cats = v is List && v.isNotEmpty ? List<String>.from(v) : fallback;
    } catch (_) {
      _cats = fallback;
    }
    return _cats!;
  }

  static Future<bool> isManager() async {
    if (_manager != null) return _manager!;
    try {
      _manager = (await Supabase.instance.client.rpc('has_admin_action', params: {'p_action': 'Manage Education Contents'})) == true;
    } catch (_) {
      _manager = false;
    }
    return _manager!;
  }

  /// The short name shown on the Home card ("Cell Service Materials" → "Cell Service").
  static String short(String c) => c
      .replaceAll(RegExp(r'\s+(Materials|Contents)$'), '')
      .replaceFirst(RegExp(r'^Other$'), 'Other contents');

  static IconData icon(String c) {
    final l = c.toLowerCase();
    if (l.contains('jss') || l.contains('article')) return Icons.article_rounded;
    if (l.contains('cell')) return Icons.groups_rounded;
    if (l.contains('revelation') || l.contains('seal')) return Icons.auto_stories_rounded;
    if (l.contains('test')) return Icons.quiz_rounded;
    return Icons.folder_special_rounded;
  }

  static Color color(String c) {
    final l = c.toLowerCase();
    if (l.contains('jss') || l.contains('article')) return const Color(0xFF1565C0);
    if (l.contains('cell')) return const Color(0xFF2E7D32);
    if (l.contains('revelation') || l.contains('seal')) return const Color(0xFF6A1B9A);
    if (l.contains('test')) return const Color(0xFFE65100);
    return const Color(0xFF455A64);
  }

  static String snippet(Map c, [int n = 180]) {
    final s = (c['summary'] ?? '').toString().trim().isNotEmpty ? c['summary'].toString().trim() : (c['body'] ?? '').toString().trim();
    final one = s.replaceAll(RegExp(r'\s+'), ' ');
    return one.length <= n ? one : '${one.substring(0, n).trimRight()}…';
  }
}

/// One kind of contents: the newest first as summaries with "Read more";
/// search by keyword and by date; the Education Department adds and edits.
class EducationContentsScreen extends StatefulWidget {
  final String category;
  const EducationContentsScreen({super.key, required this.category});
  @override
  State<EducationContentsScreen> createState() => _EducationContentsScreenState();
}

class _EducationContentsScreenState extends State<EducationContentsScreen> {
  final _db = Supabase.instance.client;
  final List<Map<String, dynamic>> _rows = [];
  bool _loading = true, _more = true, _manager = false;
  String _q = '';
  DateTimeRange? _range;
  String? _error;
  Timer? _debounce;
  static const _page = 20;

  @override
  void initState() {
    super.initState();
    EduContents.isManager().then((v) {
      if (mounted) setState(() => _manager = v);
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _rows.clear();
        _more = true;
        _loading = true;
        _error = null;
      });
    }
    try {
      var q = _db.from('edu_contents').select('id, category, title, summary, body, content_date, media, is_published, created_at').eq('category', widget.category);
      if (_range != null) {
        q = q.gte('content_date', DateFormat('yyyy-MM-dd').format(_range!.start)).lte('content_date', DateFormat('yyyy-MM-dd').format(_range!.end));
      }
      final k = _q.trim().replaceAll(RegExp(r'[,()%]'), ' ').trim();
      if (k.isNotEmpty) q = q.or('title.ilike.%$k%,summary.ilike.%$k%,body.ilike.%$k%');
      final r = await q.order('content_date', ascending: false).order('created_at', ascending: false).range(_rows.length, _rows.length + _page - 1);
      if (!mounted) return;
      setState(() {
        _rows.addAll(List<Map<String, dynamic>>.from(r));
        _more = r.length == _page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load (run 22_round21.sql): ${e is PostgrestException ? e.message : e}";
      });
    }
  }

  Future<void> _openEditor([Map<String, dynamic>? c]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EducationEditor(category: widget.category, content: c)));
    if (saved == true) _load(reset: true);
  }

  /// One content: raised card with a coloured edge; the newest one is a
  /// large feature card with its picture on top.
  Widget _card(Map<String, dynamic> c, {bool feature = false}) {
    final color = EduContents.color(widget.category);
    final media = List<Map<String, dynamic>>.from(((c['media'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final image = media.where((m) => m['type'] == 'image').firstOrNull;
    final date = DateTime.tryParse((c['content_date'] ?? '').toString());
    final kinds = {for (final m in media) m['type']};
    void open() => Navigator.push(context, MaterialPageRoute(builder: (_) => EducationContentDetail(content: c, canEdit: _manager, onEdit: () => _openEditor(c))));
    final badges = Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppPalette.bg(color.withValues(alpha: 0.12)), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.event_rounded, size: 12, color: AppPalette.fg(color)),
          const SizedBox(width: 4),
          Text(date == null ? '' : DateFormat('EEE d MMM yyyy').format(date), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(color))),
        ]),
      ),
      const SizedBox(width: 6),
      for (final k in kinds)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            switch (k) { 'image' => Icons.image_outlined, 'audio' => Icons.headphones_rounded, 'video' => Icons.smart_display_outlined, 'link' => Icons.link_rounded, _ => Icons.attach_file_rounded },
            size: 15,
            color: AppPalette.fg(Colors.blueGrey),
          ),
        ),
      if (c['is_published'] == false) Text("Draft", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.orange.shade800))),
      const Spacer(),
      if (feature)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppPalette.solid(color), borderRadius: BorderRadius.circular(20)),
          child: const Text("Latest", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
    ]);
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      badges,
      const SizedBox(height: 8),
      Text((c['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: feature ? 17 : 14.5, height: 1.25)),
      const SizedBox(height: 6),
      Text(EduContents.snippet(c, feature ? 260 : 170), maxLines: feature ? 4 : 3, overflow: TextOverflow.ellipsis,
          style: GoogleFonts.merriweather(fontSize: 12.3, height: 1.45, color: AppPalette.fg(Colors.blueGrey.shade800))),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppPalette.solid(color), AppPalette.solid(Color.lerp(color, Colors.black, 0.25)!)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text("Read more", style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
          ]),
        ),
      ),
    ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.20), blurRadius: 20, spreadRadius: -4, offset: const Offset(0, 10)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: Material(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: feature
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (image != null)
                    AspectRatio(
                      aspectRatio: 16 / 7,
                      child: Image.network(image['url'].toString(), fit: BoxFit.cover, errorBuilder: (a, b, e) => Container(color: AppPalette.bg(color.withValues(alpha: 0.1)))),
                    )
                  else
                    Container(height: 6, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppPalette.solid(color), AppPalette.solid(Color.lerp(color, Colors.white, 0.4)!)]))),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: text),
                ])
              : IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(width: 5, color: AppPalette.solid(color)),
                    Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), child: text)),
                    if (image != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(image['url'].toString(), width: 96, fit: BoxFit.cover, errorBuilder: (a, b, e) => const SizedBox(width: 96)),
                        ),
                      ),
                  ]),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = EduContents.color(widget.category);
    final dark = Color.lerp(color, Colors.black, 0.35)!;
    final rangeText = _range == null
        ? "Any date"
        : (DateUtils.isSameDay(_range!.start, _range!.end)
            ? DateFormat('d MMM yyyy').format(_range!.start)
            : "${DateFormat('d MMM').format(_range!.start)} – ${DateFormat('d MMM yyyy').format(_range!.end)}");
    // a compact header: back, the kind's icon and name on one line, then the search bar
    final header = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppPalette.solid(color), AppPalette.solid(dark)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      padding: const EdgeInsets.fromLTRB(4, 0, 12, 10),
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          Row(children: [
            const BackButton(color: Colors.white),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(EduContents.icon(widget.category), color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(widget.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
                Text(_rows.isEmpty && _loading ? "Loading…" : "Newest first · ${_rows.length}${_more ? '+' : ''} contents",
                    style: GoogleFonts.merriweather(fontSize: 10.5, color: Colors.white70)),
              ]),
            ),
          ]),
          Container(
            height: 40,
            padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
            decoration: BoxDecoration(
              color: AppPalette.bg(Colors.white),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(children: [
              Icon(Icons.search_rounded, size: 19, color: AppPalette.fg(color)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(hintText: tr("Search by keyword"), isDense: true, border: InputBorder.none),
                  onChanged: (v) {
                    _q = v;
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
                  },
                ),
              ),
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.date_range_rounded, size: 15, color: AppPalette.fg(color)),
                label: Text(rangeText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(color))),
                side: BorderSide(color: AppPalette.line(color.withValues(alpha: 0.3))),
                backgroundColor: AppPalette.bg(color.withValues(alpha: 0.06)),
                onPressed: () async {
                  final r = await showNiceRangePicker(context, initial: _range, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)), title: tr('Contents of'));
                  if (r != null) {
                    _range = r;
                    _load(reset: true);
                  }
                },
              ),
              if (_range != null)
                IconButton(
                  tooltip: tr("Any date"),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _range = null;
                    _load(reset: true);
                  },
                ),
            ]),
          ),
        ]),
      ),
    );
    return Scaffold(
      backgroundColor: AppPalette.bg(Color.alphaBlend(color.withValues(alpha: 0.05), const Color(0xFFF7F5FB))),
      floatingActionButton: _manager
          ? FloatingActionButton.extended(backgroundColor: AppPalette.solid(color), foregroundColor: Colors.white, onPressed: () => _openEditor(), icon: const Icon(Icons.add_rounded), label: const Text("Add"))
          : null,
      body: Column(children: [
        header,
        Expanded(
          child: _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
              : _loading && _rows.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _load(reset: true),
                      child: _rows.isEmpty
                          ? ListView(children: [
                              Padding(
                                padding: const EdgeInsets.all(40),
                                child: Column(children: [
                                  Icon(EduContents.icon(widget.category), size: 48, color: AppPalette.fg(color.withValues(alpha: 0.35))),
                                  const SizedBox(height: 10),
                                  Text(_q.isNotEmpty || _range != null ? "Nothing matches." : "No contents yet.",
                                      textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey.shade600))),
                                ]),
                              ),
                            ])
                          // the full width, about 0.6 cm from each side
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(22, 14, 22, 90),
                              itemCount: _rows.length + (_more ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i < _rows.length) {
                                  // each card slides up and fades in, one after the other
                                  return _Rise(
                                    key: ValueKey(_rows[i]['id']),
                                    delay: Duration(milliseconds: 70 * (i % 10)),
                                    child: _card(_rows[i], feature: i == 0 && _q.isEmpty && _range == null),
                                  );
                                }
                                return Center(
                                  child: TextButton.icon(
                                    onPressed: _loading ? null : () => _load(),
                                    icon: const Icon(Icons.expand_more_rounded),
                                    label: const Text("Older contents"),
                                  ),
                                );
                              },
                            ),
                    ),
        ),
      ]),
    );
  }
}

/// Slides its child up and fades it in once, after [delay].
class _Rise extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _Rise({super.key, required this.child, this.delay = Duration.zero});
  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(a), child: widget.child),
    );
  }
}

/// The whole content, laid out like a magazine article: a cover (the first
/// picture or the kind's colours) with the title, the date and reading time,
/// the summary as a highlighted lead, the text in a comfortable column with a
/// large first letter, then the pictures, audio, video, files and links.
class EducationContentDetail extends StatefulWidget {
  final Map<String, dynamic> content;
  final bool canEdit;
  final VoidCallback? onEdit;
  const EducationContentDetail({super.key, required this.content, this.canEdit = false, this.onEdit});

  static Future<void> openById(BuildContext context, String id) async {
    try {
      final c = await Supabase.instance.client.from('edu_contents').select().eq('id', id).maybeSingle();
      if (c == null || !context.mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => EducationContentDetail(content: Map<String, dynamic>.from(c))));
    } catch (_) {}
  }

  @override
  State<EducationContentDetail> createState() => _EducationContentDetailState();
}

class _EducationContentDetailState extends State<EducationContentDetail> {
  final _scroll = ScrollController();
  double _progress = 0;
  double _size = 15.5;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) return;
      final p = (_scroll.offset / _scroll.position.maxScrollExtent).clamp(0.0, 1.0);
      if ((p - _progress).abs() > 0.01) setState(() => _progress = p);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _openImage(String url) => showDialog(
        context: context,
        builder: (ctx) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(children: [
            Center(child: InteractiveViewer(child: Image.network(url))),
            Positioned(top: 8, right: 8, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.content;
    final cat = (c['category'] ?? '').toString();
    final color = EduContents.color(cat);
    final dark = Color.lerp(color, Colors.black, 0.45)!;
    final media = List<Map<String, dynamic>>.from(((c['media'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final images = media.where((m) => m['type'] == 'image').toList();
    final cover = images.isEmpty ? null : images.first['url'].toString();
    final rest = images.skip(1).toList();
    final date = DateTime.tryParse((c['content_date'] ?? '').toString());
    final body = (c['body'] ?? '').toString().trim();
    final summary = (c['summary'] ?? '').toString().trim();
    final words = '$summary $body'.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final minutes = (words / 200).ceil().clamp(1, 120);
    final paras = body.split(RegExp(r'\n\s*\n|\n')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    final textStyle = GoogleFonts.merriweather(fontSize: _size, height: 1.85, color: AppPalette.fg(const Color(0xFF263238)));

    Widget chip(IconData i, String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 13, color: Colors.white),
            const SizedBox(width: 5),
            Text(t, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
          ]),
        );

    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFFAF8F5)),
      body: Stack(children: [
        CustomScrollView(controller: _scroll, slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: cover == null ? 230 : 300,
            backgroundColor: AppPalette.solid(dark),
            foregroundColor: Colors.white,
            title: Text(cat, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white)),
            actions: [
              PopupMenuButton<String>(
                tooltip: tr("Text size"),
                icon: const Icon(Icons.format_size_rounded),
                onSelected: (v) => setState(() => _size = (v == '+' ? _size + 1.5 : _size - 1.5).clamp(12.0, 26.0)),
                itemBuilder: (_) => const [PopupMenuItem(value: '+', child: Text("Larger text")), PopupMenuItem(value: '-', child: Text("Smaller text"))],
              ),
              if (widget.canEdit && widget.onEdit != null)
                IconButton(
                  tooltip: tr("Edit"),
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onEdit!();
                  },
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: Stack(fit: StackFit.expand, children: [
                if (cover != null)
                  Image.network(cover, fit: BoxFit.cover, errorBuilder: (a, b, e) => Container(color: AppPalette.solid(color)))
                else
                  Container(
                    decoration: BoxDecoration(gradient: LinearGradient(colors: [AppPalette.solid(color), AppPalette.solid(dark)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                    child: Align(alignment: const Alignment(0.85, -0.2), child: Icon(EduContents.icon(cat), size: 140, color: Colors.white.withValues(alpha: 0.10))),
                  ),
                // the title sits on a dark fade so it always reads well
                const DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Color(0xCC000000)], begin: Alignment.center, end: Alignment.bottomCenter)),
                ),
                Positioned(
                  left: 22,
                  right: 22,
                  bottom: 18,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text((c['title'] ?? '').toString(),
                        maxLines: 3, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 23, fontWeight: FontWeight.w900, height: 1.25, color: Colors.white)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (date != null) chip(Icons.event_rounded, DateFormat('EEEE d MMMM yyyy').format(date)),
                      chip(Icons.schedule_rounded, "$minutes min read"),
                      if (media.any((m) => m['type'] == 'audio' || m['type'] == 'video')) chip(Icons.play_circle_rounded, "Audio / video"),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: _Rise(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 18, 16, 60),
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
                    decoration: BoxDecoration(
                      color: AppPalette.bg(Colors.white),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: color.withValues(alpha: 0.14), blurRadius: 24, spreadRadius: -6, offset: const Offset(0, 12)),
                        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 3, offset: const Offset(0, 1)),
                      ],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // the lead
                      if (summary.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          decoration: BoxDecoration(
                            color: AppPalette.bg(color.withValues(alpha: 0.07)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border(left: BorderSide(color: AppPalette.solid(color), width: 4)),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(Icons.format_quote_rounded, color: AppPalette.fg(color), size: 26),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(summary,
                                  style: GoogleFonts.merriweather(fontSize: _size + 0.5, fontStyle: FontStyle.italic, height: 1.6, color: AppPalette.fg(Color.lerp(color, Colors.black, 0.3)!))),
                            ),
                          ]),
                        ),
                      // the text: a large first letter, then comfortable paragraphs
                      for (final (i, p) in paras.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: i == 0 && p.length > 1
                              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8, top: 2),
                                    child: Text(p.substring(0, 1), style: GoogleFonts.merriweather(fontSize: _size * 3.2, height: 1, fontWeight: FontWeight.w900, color: AppPalette.fg(color))),
                                  ),
                                  Expanded(child: SelectableText(p.substring(1), style: textStyle)),
                                ])
                              : SelectableText(p, style: textStyle),
                        ),
                      for (final m in media.where((m) => m['type'] == 'audio' || m['type'] == 'video')) ...[
                        const SizedBox(height: 6),
                        EduMediaPlayer(url: m['url'].toString(), name: (m['name'] ?? '').toString(), video: m['type'] == 'video'),
                        const SizedBox(height: 10),
                      ],
                      if (rest.isNotEmpty || (cover != null && paras.isEmpty)) ...[
                        const SizedBox(height: 8),
                        Text("Pictures", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppPalette.fg(color))),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 150,
                          child: ListView(scrollDirection: Axis.horizontal, children: [
                            for (final m in (rest.isEmpty ? images : rest))
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _openImage(m['url'].toString()),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.network(m['url'].toString(), width: 200, height: 150, fit: BoxFit.cover, errorBuilder: (a, b, e) => const SizedBox(width: 200)),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                      ],
                      if (media.any((m) => m['type'] == 'file' || m['type'] == 'link')) ...[
                        const SizedBox(height: 16),
                        Text("Files & links", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppPalette.fg(color))),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final m in media.where((m) => m['type'] == 'file' || m['type'] == 'link'))
                            ActionChip(
                              avatar: Icon(m['type'] == 'link' ? Icons.link_rounded : Icons.attach_file_rounded, size: 16, color: AppPalette.fg(color)),
                              label: Text((m['name'] ?? m['url']).toString(), overflow: TextOverflow.ellipsis),
                              onPressed: () => launchUrl(Uri.parse(m['url'].toString()), mode: LaunchMode.externalApplication),
                            ),
                        ]),
                      ],
                      const SizedBox(height: 18),
                      Center(child: Container(width: 60, height: 3, decoration: BoxDecoration(color: AppPalette.solid(color.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(2)))),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
        // reading progress
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: LinearProgressIndicator(value: _progress, minHeight: 3, backgroundColor: Colors.transparent, color: AppPalette.solid(color)),
        ),
      ]),
    );
  }
}

/// A simple audio / video player (play, pause, seek).
class EduMediaPlayer extends StatefulWidget {
  final String url;
  final String name;
  final bool video;
  const EduMediaPlayer({super.key, required this.url, required this.name, required this.video});
  @override
  State<EduMediaPlayer> createState() => _EduMediaPlayerState();
}

class _EduMediaPlayerState extends State<EduMediaPlayer> {
  VideoPlayerController? _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c = c;
    c.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
    c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  String _t(Duration d) => "${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}";

  @override
  Widget build(BuildContext context) {
    final c = _c!;
    final ready = c.value.isInitialized;
    final pos = c.value.position, dur = c.value.duration;
    return Container(
      decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF3ECFB)), borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        if (widget.video && ready) AspectRatio(aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio, child: VideoPlayer(c)),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
          child: Row(children: [
            IconButton(
              icon: Icon(c.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, size: 34, color: AppPalette.fg(_kPurple)),
              onPressed: !ready ? null : () => c.value.isPlaying ? c.pause() : c.play(),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_failed ? "Couldn't play ${widget.name}" : widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)),
                Slider(
                  value: dur.inMilliseconds == 0 ? 0 : pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                  max: dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds.toDouble(),
                  onChanged: !ready ? null : (v) => c.seekTo(Duration(milliseconds: v.round())),
                ),
              ]),
            ),
            Text(ready ? "${_t(pos)} / ${_t(dur)}" : (_failed ? "" : "…"), style: const TextStyle(fontSize: 11)),
          ]),
        ),
      ]),
    );
  }
}

/// Education Department: add / edit a content (text, pictures, audio, video,
/// files up to 50 MB, links).
class EducationEditor extends StatefulWidget {
  final String category;
  final Map<String, dynamic>? content;
  const EducationEditor({super.key, required this.category, this.content});
  @override
  State<EducationEditor> createState() => _EducationEditorState();
}

class _EducationEditorState extends State<EducationEditor> {
  final _db = Supabase.instance.client;
  late final _title = TextEditingController(text: (widget.content?['title'] ?? '').toString());
  late final _summary = TextEditingController(text: (widget.content?['summary'] ?? '').toString());
  late final _body = TextEditingController(text: (widget.content?['body'] ?? '').toString());
  late String _category = (widget.content?['category'] ?? widget.category).toString();
  late DateTime _date = DateTime.tryParse((widget.content?['content_date'] ?? '').toString()) ?? DateTime.now();
  late bool _published = widget.content?['is_published'] != false;
  late final List<Map<String, dynamic>> _media = List<Map<String, dynamic>>.from(((widget.content?['media'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
  List<String> _cats = EduContents.fallback;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    EduContents.categories().then((c) {
      if (mounted) setState(() => _cats = c);
    });
  }

  static String _kindOf(String name) {
    final e = name.toLowerCase().split('.').last;
    if (const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(e)) return 'image';
    if (const ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'oga', 'opus'].contains(e)) return 'audio';
    if (const ['mp4', 'webm', 'mov', 'm4v', 'mkv'].contains(e)) return 'video';
    return 'file';
  }

  static String _mime(String name) {
    final e = name.toLowerCase().split('.').last;
    return const {
          'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp',
          'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'aac': 'audio/aac', 'wav': 'audio/wav', 'ogg': 'audio/ogg', 'opus': 'audio/opus',
          'mp4': 'video/mp4', 'webm': 'video/webm', 'mov': 'video/quicktime', 'm4v': 'video/mp4',
          'pdf': 'application/pdf', 'doc': 'application/msword', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'ppt': 'application/vnd.ms-powerpoint', 'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        }[e] ??
        'application/octet-stream';
  }

  Future<void> _addFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (res == null) return;
    setState(() => _busy = true);
    for (final f in res.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      if (bytes.length > _maxBytes) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${f.name} is over 50 MB and was not added")));
        continue;
      }
      setState(() => _status = "Uploading ${f.name} …");
      try {
        final safe = f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final path = "${_category.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}/${DateTime.now().millisecondsSinceEpoch}_$safe";
        await _db.storage.from(_bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: _mime(f.name), upsert: false));
        final url = _db.storage.from(_bucket).getPublicUrl(path);
        setState(() => _media.add({'type': _kindOf(f.name), 'url': url, 'path': path, 'name': f.name, 'size': bytes.length}));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't upload ${f.name}: ${e is StorageException ? e.message : e}")));
      }
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _status = null;
      });
    }
  }

  Future<void> _addLink() async {
    final url = TextEditingController(), name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add a link"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: url, decoration: InputDecoration(labelText: tr("Link (https://…)"), border: const OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: name, decoration: InputDecoration(labelText: tr("Name shown"), border: const OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Add")),
        ],
      ),
    );
    if (ok == true && url.text.trim().startsWith('http')) {
      setState(() => _media.add({'type': 'link', 'url': url.text.trim(), 'name': name.text.trim().isEmpty ? url.text.trim() : name.text.trim()}));
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _status = "The title is needed.");
      return;
    }
    setState(() => _busy = true);
    final row = {
      'category': _category,
      'title': _title.text.trim(),
      'summary': _summary.text.trim().isEmpty ? null : _summary.text.trim(),
      'body': _body.text.trim().isEmpty ? null : _body.text.trim(),
      'content_date': DateFormat('yyyy-MM-dd').format(_date),
      'media': _media,
      'is_published': _published,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (widget.content == null) {
        await _db.from('edu_contents').insert(row);
      } else {
        await _db.from('edu_contents').update(row).eq('id', widget.content!['id']);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = "Couldn't save: ${e is PostgrestException ? e.message : e}";
        });
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove this content?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Remove", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final paths = [for (final m in _media) if ((m['path'] ?? '').toString().isNotEmpty) m['path'].toString()];
      if (paths.isNotEmpty) await _db.storage.from(_bucket).remove(paths).catchError((_) => <FileObject>[]);
      await _db.from('edu_contents').delete().eq('id', widget.content!['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _status = "Couldn't remove: ${e is PostgrestException ? e.message : e}");
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String l, {String? hint}) => InputDecoration(labelText: tr(l), hintText: hint == null ? null : tr(hint), border: const OutlineInputBorder(), alignLabelWithHint: true);
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 46,
        title: Text(widget.content == null ? "New content" : "Edit content", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple))),
        actions: [
          if (widget.content != null) IconButton(tooltip: tr("Remove"), icon: const Icon(Icons.delete_outline_rounded), onPressed: _busy ? null : _delete),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_rounded, size: 18), label: const Text("Save")),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.all(14), children: [
            if (_status != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_status!, style: TextStyle(color: AppPalette.fg(_busy ? _kPurple : Colors.red.shade700)))),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  initialValue: _cats.contains(_category) ? _category : null,
                  decoration: deco("Kind"),
                  items: [for (final c in {..._cats, _category}) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.event_rounded, size: 16),
                label: Text(DateFormat('EEE d MMM yyyy').format(_date)),
                onPressed: () async {
                  final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: _date);
                  if (d != null) setState(() => _date = d);
                },
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Switch(value: _published, onChanged: (v) => setState(() => _published = v)),
                Text(_published ? "Published (leaders are notified)" : "Draft (only you see it)"),
              ]),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _title, decoration: deco("Title")),
            const SizedBox(height: 10),
            TextField(controller: _summary, minLines: 2, maxLines: 4, decoration: deco("Summary", hint: "Shown in the list; empty = the start of the text")),
            const SizedBox(height: 10),
            TextField(controller: _body, minLines: 8, maxLines: 30, decoration: deco("Full text")),
            const SizedBox(height: 12),
            Row(children: [
              Text("Pictures, audio, video & files", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(_kPurple))),
              const Spacer(),
              TextButton.icon(onPressed: _busy ? null : _addLink, icon: const Icon(Icons.link_rounded, size: 18), label: const Text("Link")),
              FilledButton.tonalIcon(onPressed: _busy ? null : _addFiles, icon: const Icon(Icons.upload_rounded, size: 18), label: const Text("Upload")),
            ]),
            Text("Up to 50 MB a file.", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
            const SizedBox(height: 6),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              // onReorderItem gives the final position (no adjusting needed)
              onReorderItem: (a, b) => setState(() => _media.insert(b, _media.removeAt(a))),
              children: [
                for (int i = 0; i < _media.length; i++)
                  ListTile(
                    key: ValueKey('${_media[i]['url']}$i'),
                    dense: true,
                    leading: _media[i]['type'] == 'image'
                        ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(_media[i]['url'].toString(), width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (a, b, c) => const Icon(Icons.image_outlined)))
                        : Icon(switch (_media[i]['type']) { 'audio' => Icons.headphones_rounded, 'video' => Icons.smart_display_outlined, 'link' => Icons.link_rounded, _ => Icons.attach_file_rounded }),
                    title: Text((_media[i]['name'] ?? _media[i]['url']).toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text((_media[i]['type'] ?? '').toString()),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () async {
                        final m = _media[i];
                        setState(() => _media.removeAt(i));
                        final p = (m['path'] ?? '').toString();
                        if (p.isNotEmpty && widget.content == null) {
                          try {
                            await _db.storage.from(_bucket).remove([p]);
                          } catch (_) {}
                        }
                      },
                    ),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

/// Home › Education Contents: one button per kind; under each, its newest
/// titles rise up one after the other. Leaders only.
class EducationHomeCard extends StatefulWidget {
  const EducationHomeCard({super.key});
  @override
  State<EducationHomeCard> createState() => _EducationHomeCardState();
}

class _EducationHomeCardState extends State<EducationHomeCard> {
  List<String> _cats = const [];
  Map<String, List<Map<String, dynamic>>> _latest = {};
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = Supabase.instance.client;
      final leader = (await db.rpc('is_leader')) == true;
      if (!leader) return;
      final cats = await EduContents.categories();
      final r = await db.rpc('edu_latest', params: {'p_per': 4});
      final by = <String, List<Map<String, dynamic>>>{};
      for (final x in (r as List)) {
        final m = Map<String, dynamic>.from(x as Map);
        by.putIfAbsent(m['category'].toString(), () => []).add(m);
      }
      for (final v in by.values) {
        v.sort((a, b) => b['content_date'].toString().compareTo(a['content_date'].toString()));
      }
      if (mounted) {
        setState(() {
          _cats = cats;
          _latest = by;
          _show = true;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line(const Color(0xFFE4DAF2))),
        // raised from below, like the other Home cards
        boxShadow: [
          BoxShadow(color: _kPurple.withValues(alpha: 0.16), blurRadius: 22, spreadRadius: -4, offset: const Offset(0, 10)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.local_library_rounded, color: AppPalette.fg(_kPurple), size: 20),
          const SizedBox(width: 8),
          Text("Education Contents", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: AppPalette.fg(_kPurple))),
        ]),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth >= 900 ? 5 : (box.maxWidth >= 560 ? 3 : 2);
          final w = (box.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in _cats) SizedBox(width: w, child: _tile(c)),
          ]);
        }),
      ]),
    );
  }

  Widget _tile(String c) {
    final color = EduContents.color(c);
    final items = _latest[c] ?? const <Map<String, dynamic>>[];
    // raised tile; its newest titles keep moving up (as Quick Reminders)
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: 14, spreadRadius: -3, offset: const Offset(0, 7)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1)),
        ],
      ),
      child: Material(
        color: AppPalette.bg(Color.alphaBlend(color.withValues(alpha: 0.07), Colors.white)),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EducationContentsScreen(category: c))),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppPalette.solid(color), AppPalette.solid(Color.lerp(color, Colors.black, 0.25)!)]),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(EduContents.icon(c), color: Colors.white, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(EduContents.short(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12.5))),
                Icon(Icons.chevron_right_rounded, size: 18, color: AppPalette.fg(color)),
              ]),
              const SizedBox(height: 6),
              // the same height for every kind; each content gives two moving
              // lines (its title, then its summary), so even one keeps moving
              SizedBox(
                height: 60,
                child: items.isEmpty
                    ? Align(alignment: Alignment.centerLeft, child: Text("Nothing new yet", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))))
                    : VerticalMarquee(
                        count: items.length * 2,
                        visible: 2,
                        itemHeight: 30,
                        every: const Duration(milliseconds: 2400),
                        itemBuilder: (_, i) {
                          final m = items[i ~/ 2];
                          final date = DateTime.tryParse((m['content_date'] ?? '').toString());
                          final title = i.isEven;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => EducationContentDetail.openById(context, m['id'].toString()),
                            child: Row(children: [
                              Icon(title ? Icons.circle : Icons.subdirectory_arrow_right_rounded, size: title ? 6 : 12, color: AppPalette.fg(color)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(title ? (m['title'] ?? '').toString() : (EduContents.snippet(m, 80).isEmpty ? "Tap to read" : EduContents.snippet(m, 80)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: title
                                        ? GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppPalette.fg(Colors.black87))
                                        : GoogleFonts.merriweather(fontSize: 10.5, fontStyle: FontStyle.italic, color: AppPalette.fg(Colors.blueGrey.shade700))),
                              ),
                              if (title && date != null) Text(DateFormat('d MMM').format(date), style: TextStyle(fontSize: 10, color: AppPalette.fg(Colors.blueGrey.shade600))),
                            ]),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

