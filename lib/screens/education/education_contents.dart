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
import '../../widgets/h_scroll.dart';
import '../../widgets/nice_range_picker.dart';

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

  Widget _card(Map<String, dynamic> c) {
    final color = EduContents.color(widget.category);
    final media = List<Map<String, dynamic>>.from(((c['media'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final image = media.where((m) => m['type'] == 'image').firstOrNull;
    final date = DateTime.tryParse((c['content_date'] ?? '').toString());
    final kinds = {for (final m in media) m['type']};
    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EducationContentDetail(content: c, canEdit: _manager, onEdit: () => _openEditor(c)))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (image != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(image['url'].toString(), width: 86, height: 86, fit: BoxFit.cover, errorBuilder: (a, b, c) => const SizedBox(width: 86, height: 86)),
                ),
              ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: AppPalette.bg(color.withValues(alpha: 0.1)), borderRadius: BorderRadius.circular(6)),
                    child: Text(date == null ? '' : DateFormat('EEE d MMM yyyy').format(date), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(color))),
                  ),
                  const SizedBox(width: 6),
                  for (final k in kinds)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Icon(
                        switch (k) { 'image' => Icons.image_outlined, 'audio' => Icons.headphones_rounded, 'video' => Icons.smart_display_outlined, 'link' => Icons.link_rounded, _ => Icons.attach_file_rounded },
                        size: 14,
                        color: AppPalette.fg(Colors.blueGrey),
                      ),
                    ),
                  if (c['is_published'] == false) Text(" · Draft", style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.orange.shade800))),
                ]),
                const SizedBox(height: 5),
                Text((c['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 4),
                Text(EduContents.snippet(c), maxLines: 3, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 12, height: 1.35, color: AppPalette.fg(Colors.black87))),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text("Read more →", style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(color))),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = EduContents.color(widget.category);
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 46,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(EduContents.icon(widget.category), color: AppPalette.fg(color), size: 20),
          const SizedBox(width: 8),
          Flexible(child: Text(widget.category, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple)))),
        ]),
      ),
      floatingActionButton: _manager
          ? FloatingActionButton.extended(onPressed: () => _openEditor(), icon: const Icon(Icons.add_rounded), label: const Text("Add"))
          : null,
      body: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(color: AppPalette.bg(Colors.white), border: Border(bottom: BorderSide(color: AppPalette.line(Colors.black12)))),
          child: HScroll(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
              SizedBox(
                width: 240,
                height: 36,
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: tr("Search by keyword"),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onChanged: (v) {
                    _q = v;
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
                  },
                ),
              ),
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.date_range_rounded, size: 16),
                label: Text(_range == null
                    ? "Any date"
                    : (DateUtils.isSameDay(_range!.start, _range!.end)
                        ? DateFormat('d MMM yyyy').format(_range!.start)
                        : "${DateFormat('d MMM').format(_range!.start)} – ${DateFormat('d MMM yyyy').format(_range!.end)}")),
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
        ),
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
                                child: Text(_q.isNotEmpty || _range != null ? "Nothing matches." : "No contents yet.",
                                    textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey.shade600))),
                              ),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(10, 10, 10, 90),
                              itemCount: _rows.length + (_more ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i < _rows.length) {
                                  // newest first; a date heading where the day changes
                                  return _card(_rows[i]);
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

/// The whole content: text, pictures, audio, video, files and links.
class EducationContentDetail extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = content;
    final cat = (c['category'] ?? '').toString();
    final color = EduContents.color(cat);
    final media = List<Map<String, dynamic>>.from(((c['media'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final images = media.where((m) => m['type'] == 'image').toList();
    final date = DateTime.tryParse((c['content_date'] ?? '').toString());
    return Scaffold(
      backgroundColor: AppPalette.bg(Colors.white),
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 46,
        title: Text(cat, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: AppPalette.fg(_kPurple))),
        actions: [
          if (canEdit && onEdit != null)
            IconButton(
              tooltip: tr("Edit"),
              icon: const Icon(Icons.edit_rounded),
              onPressed: () {
                Navigator.pop(context);
                onEdit!();
              },
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 60), children: [
            if (date != null)
              Text(DateFormat('EEEE d MMMM yyyy').format(date), style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(color))),
            const SizedBox(height: 6),
            SelectableText((c['title'] ?? '').toString(), style: GoogleFonts.merriweather(fontSize: 21, fontWeight: FontWeight.w900, height: 1.25)),
            if ((c['summary'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(c['summary'].toString(), style: GoogleFonts.merriweather(fontSize: 13.5, fontStyle: FontStyle.italic, color: AppPalette.fg(Colors.blueGrey.shade700), height: 1.45)),
            ],
            for (final m in images) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => Dialog.fullscreen(
                      backgroundColor: Colors.black,
                      child: Stack(children: [
                        Center(child: InteractiveViewer(child: Image.network(m['url'].toString()))),
                        Positioned(top: 8, right: 8, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))),
                      ]),
                    ),
                  ),
                  child: Image.network(m['url'].toString(), fit: BoxFit.cover, errorBuilder: (a, b, c) => const SizedBox.shrink()),
                ),
              ),
            ],
            for (final m in media.where((m) => m['type'] == 'audio' || m['type'] == 'video')) ...[
              const SizedBox(height: 12),
              EduMediaPlayer(url: m['url'].toString(), name: (m['name'] ?? '').toString(), video: m['type'] == 'video'),
            ],
            if ((c['body'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              SelectableText(c['body'].toString(), style: GoogleFonts.merriweather(fontSize: 14.5, height: 1.65)),
            ],
            for (final m in media.where((m) => m['type'] == 'file' || m['type'] == 'link')) ...[
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: AppPalette.line(Colors.black12))),
                leading: Icon(m['type'] == 'link' ? Icons.link_rounded : Icons.attach_file_rounded, color: AppPalette.fg(color)),
                title: Text((m['name'] ?? m['url']).toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => launchUrl(Uri.parse(m['url'].toString()), mode: LaunchMode.externalApplication),
              ),
            ],
          ]),
        ),
      ),
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
        boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 5))],
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
    return Material(
      color: AppPalette.bg(color.withValues(alpha: 0.06)),
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
                decoration: BoxDecoration(color: AppPalette.solid(color), borderRadius: BorderRadius.circular(9)),
                child: Icon(EduContents.icon(c), color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(EduContents.short(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12.5))),
              Icon(Icons.chevron_right_rounded, size: 18, color: AppPalette.fg(color)),
            ]),
            const SizedBox(height: 6),
            SizedBox(
              height: 46,
              child: items.isEmpty
                  ? Align(alignment: Alignment.centerLeft, child: Text("Nothing new yet", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))))
                  : _RisingTicker(items: items, color: color),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The newest titles, each rising from the bottom and moving on after a few
/// seconds. Tap one to read it.
class _RisingTicker extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final Color color;
  const _RisingTicker({required this.items, required this.color});
  @override
  State<_RisingTicker> createState() => _RisingTickerState();
}

class _RisingTickerState extends State<_RisingTicker> {
  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (widget.items.length > 1) {
      _t = Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) setState(() => _i = (_i + 1) % widget.items.length);
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.items[_i % widget.items.length];
    final date = DateTime.tryParse((m['content_date'] ?? '').toString());
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        transitionBuilder: (child, anim) {
          // the new one rises from below; the old one goes up and fades
          final rise = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
          return SlideTransition(position: rise, child: FadeTransition(opacity: anim, child: child));
        },
        layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, if (current != null) current]),
        child: InkWell(
          key: ValueKey(m['id']),
          onTap: () => EducationContentDetail.openById(context, m['id'].toString()),
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text((m['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87))),
              Text(
                [if (date != null) DateFormat('d MMM').format(date), EduContents.snippet(m, 70)].where((x) => x.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.blueGrey.shade600)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}