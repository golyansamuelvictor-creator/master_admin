// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/media_playback.dart';
import '../services/media_service.dart';
import '../services/notice_permissions.dart';
import 'media_admin_screens.dart';
import 'media_full_player.dart';
import 'media_player_screen.dart';
import 'package:master_admin/core/app_palette.dart';

const Color _kBlue = Color(0xFF2563EB);

/// A bright, clear version of a category colour (old categories were dark).
Color mediaBright(Color c) {
  final h = HSLColor.fromColor(c);
  return h.withLightness(h.lightness.clamp(0.45, 0.58).toDouble()).withSaturation((h.saturation * 1.15).clamp(0.6, 1.0).toDouble()).toColor();
}

/// A light tint of a category colour (t = 0 bright … 1 white).
Color mediaTint(Color c, double t) => Color.lerp(mediaBright(c), Colors.white, t)!;

/// Deep text colour that matches a category colour.
Color mediaInk(Color c) {
  final h = HSLColor.fromColor(mediaBright(c));
  return h.withLightness(0.26).toColor();
}

/// Media Hub landing page: pick a category (Praise Songs, Center Songs ...),
/// or search everything. Categories are edited in the app, not in code.
class MediaHubScreen extends StatefulWidget {
  final String title;
  final String userEmail;
  final String userRole;

  const MediaHubScreen({super.key, required this.title, required this.userEmail, required this.userRole});

  @override
  State<MediaHubScreen> createState() => _MediaHubScreenState();
}

class _MediaHubScreenState extends State<MediaHubScreen> {
  List<MediaCategory> _cats = [];
  List<MediaItem> _recent = [];
  List<MediaItem> _results = [];
  bool _loading = true;
  bool _searching = false;
  String _search = '';
  String? _error;
  bool _canManage = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Show the last results straight away, then refresh
    final cc = MediaService.cachedCategories, cr = MediaService.cachedRecent;
    if (cc != null) {
      _cats = cc;
      _recent = cr ?? const [];
      _loading = false;
    }
    NoticePermissions.load().then((p) {
      if (mounted) setState(() => _canManage = p.can(MediaService.manageAction));
    });
    _load(quiet: cc != null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await Future.wait<dynamic>([MediaService.categories(), MediaService.items(limit: 12)]);
      final cats = r[0] as List<MediaCategory>;
      final recent = r[1] as List<MediaItem>;
      MediaService.cachedRecent = recent;
      if (!mounted) return;
      setState(() {
        _cats = cats;
        _recent = recent;
        _loading = false;
        _error = null;
      });
      // pictures arrive after the page is already showing
      await MediaService.preloadThumbs(recent);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Media hub error: $e");
      if (!mounted || quiet) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load the Media Hub. If this keeps happening, ask the admin to run 06_round6.sql.";
      });
    }
  }

  void _runSearch(String q) {
    final local = q.trim().toLowerCase();
    setState(() {
      _search = q;
      _searching = local.isNotEmpty;
      // instant matches from what is already loaded, while the full search runs
      if (_searching) {
        _results = _recent.where((m) => m.title.toLowerCase().contains(local) || (m.artist ?? '').toLowerCase().contains(local)).toList();
      }
    });
    _debounce?.cancel();
    if (!_searching) return;
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final r = await MediaService.items(search: q);
        if (mounted && _search == q) setState(() => _results = r);
        await MediaService.preloadThumbs(r);
        if (mounted && _search == q) setState(() {});
      } catch (_) {}
    });
  }

  Future<void> _openCategory(MediaCategory? c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MediaCategoryScreen(category: c, categories: _cats, canManage: _canManage)),
    );
    _load();
  }

  Future<void> _upload() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => MediaUploadScreen(categories: _cats)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        centerTitle: true,
        title: Text("Media Hub", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18, color: AppPalette.fg(_kBlue))),
        actions: [
          if (_canManage)
            IconButton(
              tooltip: "Manage categories",
              icon: Icon(Icons.category_rounded, color: AppPalette.fg(_kBlue)),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaCategoryManager()));
                _load();
              },
            ),
          IconButton(tooltip: "Refresh", icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              backgroundColor: AppPalette.bg(_kBlue),
              foregroundColor: Colors.white,
              onPressed: _upload,
              icon: const Icon(Icons.upload_rounded),
              label: const Text("Upload"),
            )
          : null,
      body: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final cols = w >= 1300 ? 5 : w >= 1000 ? 4 : w >= 650 ? 3 : 2;
        final maxW = w > 1400 ? 1400.0 : w;
        final hPad = w >= 1000 ? 32.0 : 16.0;
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: EdgeInsets.fromLTRB(hPad + (w - maxW) / 2, 14, hPad + (w - maxW) / 2, 110), children: [
            _searchBar(),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.red.shade800))),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: _load, child: const Text("Retry")),
                ]),
              )
            else if (_searching)
              ..._searchResults(w)
            else ...[
              _sectionTitle("Browse by category"),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: w < 400 ? 1.0 : 1.25,
                children: [
                  _categoryCard(null),
                  for (final cat in _cats) _categoryCard(cat),
                ],
              ),
              if (_recent.isNotEmpty) ...[
                const SizedBox(height: 24),
                _sectionTitle("Recently added"),
                const SizedBox(height: 10),
                SizedBox(
                  height: 196,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _recent.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => MediaCard(item: _recent[i], width: 150, onTap: () => playMediaList(context, _recent, i)),
                  ),
                ),
              ],
            ],
          ]),
        );
      }),
    );
  }

  Widget _sectionTitle(String t) => Text(t, style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.blueGrey[900])));

  Widget _searchBar() => Container(
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: TextField(
          onChanged: _runSearch,
          style: GoogleFonts.merriweather(fontSize: 14),
          decoration: InputDecoration(
            hintText: "Search songs, videos, artists...",
            hintStyle: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey), fontSize: 13),
            prefixIcon: Icon(Icons.search, color: AppPalette.fg(_kBlue)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      );

  List<Widget> _searchResults(double w) {
    if (_results.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(30),
          child: Center(child: Text("Nothing matches \"$_search\".", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey)))),
        ),
      ];
    }
    return [
      _sectionTitle("${_results.length} result${_results.length == 1 ? '' : 's'}"),
      const SizedBox(height: 8),
      for (int i = 0; i < _results.length; i++)
        MediaTile(
          item: _results[i],
          categoryName: _cats.where((c) => c.id == _results[i].categoryId).firstOrNull?.name,
          onTap: () => playMediaList(context, _results, i),
        ),
    ];
  }

  Widget _categoryCard(MediaCategory? c) {
    final color = c?.color ?? const Color(0xFF6366F1);
    final bright = mediaBright(color);
    final total = _cats.fold<int>(0, (a, x) => a + x.itemCount);
    final count = c?.itemCount ?? total;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openCategory(c),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [AppPalette.solid(mediaTint(color, 0.86)), AppPalette.solid(mediaTint(color, 0.70))],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: AppPalette.line(bright.withValues(alpha: 0.25))),
            boxShadow: [BoxShadow(color: bright.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 5))],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            // everything centred in the card
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [bright, mediaTint(color, 0.3)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: bright.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Icon(c?.icon ?? Icons.apps_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 10),
              Text(c?.name ?? "All media",
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.merriweather(color: AppPalette.fg(mediaInk(color)), fontWeight: FontWeight.w900, fontSize: 14.5, height: 1.25)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(color: AppPalette.bg(Colors.white.withValues(alpha: 0.75)), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  "$count item${count == 1 ? '' : 's'}"
                  "${c == null || c.mediaKind == 'both' ? '' : (c.mediaKind == 'audio' ? ' · audio' : ' · video')}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppPalette.fg(mediaInk(color)), fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Plays [items] starting at [index] and opens the full player.
/// Old YouTube entries open the previous YouTube player.
Future<void> playMediaList(BuildContext context, List<MediaItem> items, int index, {bool shuffled = false}) async {
  final item = items[index];
  if (item.isYoutube) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MediaPlayerScreen(mediaItem: item.raw)));
    return;
  }
  if ((item.storagePath ?? '').isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This item has no file to play.")));
    return;
  }
  MediaPlayback.instance.playQueue(items, start: index, shuffled: shuffled);
  Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaFullPlayer()));
}

class MediaThumb extends StatelessWidget {
  final MediaItem item;
  final double size;
  final double radius;
  const MediaThumb({super.key, required this.item, this.size = 56, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    final url = MediaService.cachedLink(item.thumbnailPath) ?? item.legacyThumbUrl;
    final video = item.isVideo || item.isYoutube;
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: video ? const [Color(0xFF38BDF8), Color(0xFF6366F1)] : const [Color(0xFFC084FC), Color(0xFFF472B6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(video ? Icons.smart_display_rounded : Icons.music_note_rounded, color: Colors.white, size: size * 0.45),
    );
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: (url ?? '').isEmpty
            ? fallback
            : Image.network(url!, fit: BoxFit.cover, cacheWidth: px, gaplessPlayback: true, errorBuilder: (context, error, stack) => fallback),
      ),
    );
  }
}

class MediaCard extends StatelessWidget {
  final MediaItem item;
  final double width;
  final VoidCallback onTap;
  const MediaCard({super.key, required this.item, required this.width, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            MediaThumb(item: item, size: width, radius: 14),
            Positioned(
              right: 6,
              bottom: 6,
              child: CircleAvatar(radius: 15, backgroundColor: AppPalette.bg(Colors.white), child: Icon(Icons.play_arrow_rounded, color: AppPalette.fg(_kBlue), size: 20)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 12.5)),
          Text(item.artist ?? (item.isVideo ? 'Video' : 'Audio'),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey[600]))),
        ]),
      ),
    );
  }
}

class MediaTile extends StatelessWidget {
  final MediaItem item;
  final String? categoryName;
  final VoidCallback onTap;
  final Widget? trailing;
  const MediaTile({super.key, required this.item, required this.onTap, this.categoryName, this.trailing});

  @override
  Widget build(BuildContext context) {
    final playing = MediaPlayback.instance.current?.id == item.id;
    final meta = [
      if ((item.artist ?? '').isNotEmpty) item.artist!,
      if ((categoryName ?? '').isNotEmpty) categoryName!,
      if (item.durationSeconds != null) MediaService.formatDuration(Duration(seconds: item.durationSeconds!)),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppPalette.bg(playing ? const Color(0xFFEFF6FF) : Colors.white),
        border: Border.all(color: AppPalette.line(playing ? _kBlue.withValues(alpha: 0.35) : const Color(0xFFE2E8F0))),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            MediaThumb(item: item, size: 60),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(item.isVideo || item.isYoutube ? Icons.movie_outlined : Icons.music_note_outlined, size: 14, color: AppPalette.fg(Colors.grey[600])),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(item.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ]),
                if (meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey[600]))),
                  ),
                if (!item.isPublished)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppPalette.bg(Colors.orange.withValues(alpha: 0.15)), borderRadius: BorderRadius.circular(5)),
                    child: Text("Hidden (not published)", style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.orange[900]), fontWeight: FontWeight.bold)),
                  ),
              ]),
            ),
            if (trailing != null) trailing!,
            Icon(playing ? Icons.graphic_eq_rounded : Icons.play_circle_fill_rounded, color: AppPalette.fg(_kBlue), size: 30),
            const SizedBox(width: 4),
          ]),
        ),
      ),
    );
  }
}

/// Songs and videos of one category (or all), filtered and sorted.
class MediaCategoryScreen extends StatefulWidget {
  final MediaCategory? category; // null = all media
  final List<MediaCategory> categories;
  final bool canManage;
  const MediaCategoryScreen({super.key, required this.category, required this.categories, required this.canManage});

  @override
  State<MediaCategoryScreen> createState() => _MediaCategoryScreenState();
}

class _MediaCategoryScreenState extends State<MediaCategoryScreen> {
  // Everything in the category is loaded once; type, search and sort are
  // applied on the phone, so they react at once.
  List<MediaItem> _all = [];
  bool _loading = true;
  String? _type; // null | audio | video
  String _sort = 'newest';
  String _search = '';

  String get _cacheKey => widget.category?.id ?? '*';

  @override
  void initState() {
    super.initState();
    final k = widget.category?.mediaKind;
    if (k == 'audio' || k == 'video') _type = k;
    final cached = MediaService.cachedLists[_cacheKey];
    if (cached != null) {
      _all = cached;
      _loading = false;
    }
    _load(quiet: cached != null);
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final r = await MediaService.items(categoryId: widget.category?.id, sort: 'newest', limit: 500);
      MediaService.cachedLists[_cacheKey] = r;
      if (mounted) {
        setState(() {
          _all = r;
          _loading = false;
        });
      }
      await MediaService.preloadThumbs(r);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Media list error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MediaItem> get _items {
    final q = _search.trim().toLowerCase();
    final list = _all.where((m) {
      if (_type == 'audio' && m.mediaType != 'audio') return false;
      if (_type == 'video' && !(m.isVideo || m.isYoutube)) return false;
      if (q.isEmpty) return true;
      return m.title.toLowerCase().contains(q) || (m.artist ?? '').toLowerCase().contains(q) || (m.album ?? '').toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case 'az':
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 'popular':
        list.sort((a, b) => b.playCount.compareTo(a.playCount));
      default:
        list.sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
    }
    return list;
  }

  Future<void> _edit(MediaItem m) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => MediaUploadScreen(categories: widget.categories, existing: m)),
    );
    if (saved == true) _load(quiet: true);
  }

  Future<void> _delete(MediaItem m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete \"${m.title}\"?"),
        content: const Text("The file is removed from the Media Hub for everyone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Delete", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (MediaPlayback.instance.current?.id == m.id) await MediaPlayback.instance.stop();
      await MediaService.deleteItem(m);
      setState(() => _all.removeWhere((x) => x.id == m.id));
      _load(quiet: true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't delete it.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    final color = cat?.color ?? _kBlue;
    final bright = mediaBright(color);
    final ink = mediaInk(color);
    final items = _items;
    final playable = items.where((m) => !m.isYoutube && (m.storagePath ?? '').isNotEmpty).toList();
    Widget typeChip(String? t, String label, IconData icon) {
      final sel = _type == t;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ChoiceChip(
          avatar: Icon(icon, size: 16, color: AppPalette.fg(sel ? Colors.white : bright)),
          label: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppPalette.fg(sel ? Colors.white : ink))),
          selected: sel,
          showCheckmark: false,
          selectedColor: AppPalette.bg(bright),
          backgroundColor: AppPalette.bg(Colors.white),
          side: BorderSide(color: AppPalette.line(bright.withValues(alpha: 0.35))),
          onSelected: (_) => setState(() => _type = t),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(mediaTint(color, 0.86)),
        foregroundColor: AppPalette.fg(ink),
        elevation: 0,
        centerTitle: true,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bright),
            child: Icon(cat?.icon ?? Icons.apps_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(cat?.name ?? "All media", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(ink)))),
        ]),
        actions: [
          PopupMenuButton<String>(
            tooltip: "Sort",
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'newest', child: Text("Newest first")),
              PopupMenuItem(value: 'az', child: Text("Title A–Z")),
              PopupMenuItem(value: 'popular', child: Text("Most played")),
            ],
          ),
          if (widget.canManage)
            IconButton(
              tooltip: "Upload to this category",
              icon: const Icon(Icons.upload_rounded),
              onPressed: () async {
                final saved = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => MediaUploadScreen(categories: widget.categories, initialCategoryId: cat?.id)),
                );
                if (saved == true) _load(quiet: true);
              },
            ),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        // content is centred and kept to a comfortable width
        final contentW = c.maxWidth > 1160 ? 1160.0 : c.maxWidth;
        final hPad = (c.maxWidth - contentW) / 2 + (c.maxWidth >= 1000 ? 24.0 : 14.0);
        final twoCols = contentW >= 900;
        final tileW = twoCols ? (c.maxWidth - hPad * 2 - 12) / 2 : c.maxWidth - hPad * 2;
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 110), children: [
            if ((cat?.description ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(cat!.description!, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey[700]))),
              ),
            TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: "Search in ${cat?.name ?? 'all media'}",
                prefixIcon: Icon(Icons.search, color: AppPalette.fg(bright)),
                filled: true,
                fillColor: AppPalette.bg(Colors.white),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppPalette.line(const Color(0xFFE2E8F0)))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppPalette.line(const Color(0xFFE2E8F0)))),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 8, children: [
              if (cat == null || cat.mediaKind == 'both') ...[
                typeChip(null, "All", Icons.apps_rounded),
                typeChip('audio', "Audio", Icons.headphones_rounded),
                typeChip('video', "Video", Icons.smart_display_rounded),
                const SizedBox(width: 8),
              ],
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(bright), foregroundColor: Colors.white, shape: const StadiumBorder()),
                onPressed: playable.isEmpty ? null : () => playMediaList(context, playable, 0),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text("Play all"),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppPalette.fg(ink), side: BorderSide(color: AppPalette.line(bright.withValues(alpha: 0.5))), shape: const StadiumBorder()),
                onPressed: playable.isEmpty ? null : () => playMediaList(context, playable, 0, shuffled: true),
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text("Shuffle"),
              ),
            ]),
            const SizedBox(height: 6),
            Center(
              child: Text(
                _loading ? '' : "${items.length} item${items.length == 1 ? '' : 's'}",
                style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey[600])),
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  Icon(Icons.library_music_outlined, size: 48, color: AppPalette.fg(mediaTint(color, 0.4))),
                  const SizedBox(height: 8),
                  Text(_search.isEmpty ? "Nothing here yet." : "Nothing matches \"$_search\".", textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey))),
                ]),
              )
            else
              Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
                for (int i = 0; i < items.length; i++)
                  SizedBox(
                    width: tileW,
                    child: MediaTile(
                      item: items[i],
                      categoryName: cat == null ? widget.categories.where((x) => x.id == items[i].categoryId).firstOrNull?.name : null,
                      onTap: () => playMediaList(context, items, i),
                      trailing: widget.canManage
                          ? PopupMenuButton<String>(
                              tooltip: "Edit or delete",
                              onSelected: (v) => v == 'edit' ? _edit(items[i]) : _delete(items[i]),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text("Edit details")),
                                PopupMenuItem(value: 'delete', child: Text("Delete")),
                              ],
                            )
                          : null,
                    ),
                  ),
              ]),
          ]),
        );
      }),
    );
  }
}
