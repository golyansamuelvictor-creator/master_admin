// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/media_service.dart';
import 'package:master_admin/core/app_palette.dart';

const Color _kBlue = Color(0xFF0D47A1);

/// Upload a song / video, or edit its details. Every field the hub filters
/// and displays by is captured here.
class MediaUploadScreen extends StatefulWidget {
  final List<MediaCategory> categories;
  final MediaItem? existing;
  final String? initialCategoryId;
  const MediaUploadScreen({super.key, required this.categories, this.existing, this.initialCategoryId});

  @override
  State<MediaUploadScreen> createState() => _MediaUploadScreenState();
}

class _MediaUploadScreenState extends State<MediaUploadScreen> {
  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _album = TextEditingController();
  final _language = TextEditingController();
  final _description = TextEditingController();
  final _lyrics = TextEditingController();
  final _tags = TextEditingController();

  List<MediaCategory> _cats = [];
  String? _categoryId;
  String _type = 'audio';
  bool _published = true;

  Uint8List? _file;
  String? _fileName;
  Uint8List? _thumb;
  String? _thumbName;
  bool _saving = false;
  String? _error;

  static const _audioExt = ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'oga', 'flac', 'opus'];
  static const _videoExt = ['mp4', 'm4v', 'mov', 'webm', 'mkv'];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _cats = widget.categories;
    final m = widget.existing;
    if (m != null) {
      _title.text = m.title;
      _artist.text = m.artist ?? '';
      _album.text = m.album ?? '';
      _language.text = m.language ?? '';
      _description.text = m.description ?? '';
      _lyrics.text = m.lyrics ?? '';
      _tags.text = m.tags.join(', ');
      _categoryId = m.categoryId;
      _type = m.isVideo ? 'video' : 'audio';
      _published = m.isPublished;
    } else {
      _categoryId = widget.initialCategoryId;
    }
    if (_cats.isEmpty) {
      MediaService.categories(includeInactive: true).then((c) {
        if (mounted) setState(() => _cats = c);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _artist, _album, _language, _description, _lyrics, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [..._audioExt, ..._videoExt],
      withData: true,
    );
    final f = r?.files.firstOrNull;
    if (f == null || f.bytes == null) return;
    final ext = (f.extension ?? '').toLowerCase();
    setState(() {
      _file = f.bytes;
      _fileName = f.name;
      _type = _videoExt.contains(ext) ? 'video' : 'audio';
      if (_title.text.trim().isEmpty) {
        _title.text = f.name.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '').replaceAll(RegExp(r'[_-]+'), ' ').trim();
      }
    });
  }

  Future<void> _pickThumb() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.firstOrNull;
    if (f == null || f.bytes == null) return;
    setState(() {
      _thumb = f.bytes;
      _thumbName = f.name;
    });
  }

  Future<void> _save() async {
    final problem = _title.text.trim().isEmpty
        ? "Enter a title."
        : _categoryId == null
            ? "Choose a category."
            : (!_isEdit && _file == null)
                ? "Choose the song or video file."
                : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final db = Supabase.instance.client;
    final old = widget.existing;
    final uploaded = <String>[];
    try {
      String? mediaPath = old?.storagePath;
      String? thumbPath = old?.thumbnailPath;
      if (_file != null) {
        mediaPath = await MediaService.upload(_file!, _fileName ?? 'media', folder: _type);
        uploaded.add(mediaPath);
      }
      if (_thumb != null) {
        thumbPath = await MediaService.upload(_thumb!, _thumbName ?? 'cover.jpg', folder: 'thumbs');
        uploaded.add(thumbPath);
      }
      final data = <String, dynamic>{
        'title': _title.text.trim(),
        'artist': _artist.text.trim().isEmpty ? null : _artist.text.trim(),
        'album': _album.text.trim().isEmpty ? null : _album.text.trim(),
        'language': _language.text.trim().isEmpty ? null : _language.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'lyrics': _lyrics.text.trim().isEmpty ? null : _lyrics.text,
        'tags': _tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
        'category_id': _categoryId,
        // older screens read this text column
        'category': _type == 'video' ? 'Video' : 'Music',
        'media_type': _type,
        'storage_path': mediaPath,
        'thumbnail_path': thumbPath,
        'is_published': _published,
        if (_file != null) 'file_size': _file!.length,
        if (_file != null) 'mime_type': MediaService.mimeFor(_fileName ?? ''),
        if (_file != null) 'duration_seconds': null, // measured on first play
        if (!_isEdit) 'owner_email': db.auth.currentUser?.email ?? '',
      };
      await MediaService.saveItem(data, id: old?.id);

      // Replaced files: remove the old ones
      final stale = <String>[
        if (_file != null && (old?.storagePath ?? '').isNotEmpty) old!.storagePath!,
        if (_thumb != null && (old?.thumbnailPath ?? '').isNotEmpty) old!.thumbnailPath!,
      ];
      if (stale.isNotEmpty) {
        try {
          await db.storage.from(MediaService.bucket).remove(stale);
        } catch (_) {}
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint("Media save error: $e");
      if (uploaded.isNotEmpty) {
        try {
          await db.storage.from(MediaService.bucket).remove(uploaded);
        } catch (_) {}
      }
      final msg = e is StorageException
          ? (e.statusCode == '413' || e.message.toLowerCase().contains('size')
              ? "The file is larger than your Supabase upload limit (Storage > Settings)."
              : "Upload failed: ${e.message}")
          : e is PostgrestException
              ? "Couldn't save: ${e.message}"
              : "Couldn't save. Check your connection and try again.";
      if (mounted) {
        setState(() {
          _saving = false;
          _error = msg;
        });
      }
    }
  }

  String _size(int b) => b < 1024 * 1024 ? '${(b / 1024).toStringAsFixed(0)} KB' : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    final catValue = cats.any((c) => c.id == _categoryId) ? _categoryId : null;
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        title: Text(_isEdit ? "Edit media" : "Upload media", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? "SAVING…" : "SAVE", style: TextStyle(fontWeight: FontWeight.w900, color: AppPalette.fg(_kBlue))),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: double.infinity),
          child: ListView(padding: const EdgeInsets.all(18), children: [
            _section("1. File"),
            _fileBox(
              icon: _type == 'video' ? Icons.movie_rounded : Icons.audiotrack_rounded,
              title: _fileName ?? (_isEdit ? "Keep the current file" : "Choose a song or video"),
              subtitle: _file != null
                  ? "${_size(_file!.length)} · ${_type == 'video' ? 'Video' : 'Audio'}"
                  : "MP3, M4A, WAV, OGG, FLAC · MP4, MOV, WEBM",
              button: _isEdit ? "Replace file" : "Choose file",
              onTap: _saving ? null : _pickFile,
            ),
            if (_file != null && _file!.length > 50 * 1024 * 1024)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "Large file: Supabase refuses uploads above the project's limit (50 MB by default; change it in Storage > Settings).",
                  style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.orange[900])),
                ),
              ),
            const SizedBox(height: 8),
            Row(children: [
              const Text("Type:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              ChoiceChip(label: const Text("Audio"), selected: _type == 'audio', onSelected: (_) => setState(() => _type = 'audio')),
              const SizedBox(width: 6),
              ChoiceChip(label: const Text("Video"), selected: _type == 'video', onSelected: (_) => setState(() => _type = 'video')),
            ]),
            const SizedBox(height: 10),
            _fileBox(
              icon: Icons.image_rounded,
              title: _thumbName ?? (widget.existing?.thumbnailPath != null ? "Keep the current cover" : "Cover picture (optional)"),
              subtitle: _thumb != null ? _size(_thumb!.length) : "Shown in lists and the player",
              button: "Choose picture",
              onTap: _saving ? null : _pickThumb,
              preview: _thumb,
            ),
            const SizedBox(height: 18),
            _section("2. Details"),
            _field(_title, "Title *"),
            LayoutBuilder(builder: (_, c) {
              final two = c.maxWidth >= 520;
              final a = _field(_artist, "Artist / minister / choir");
              final b = _field(_album, "Album or series");
              return two ? Row(children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]) : Column(children: [a, b]);
            }),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                initialValue: catValue,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr("Category *"), border: OutlineInputBorder()),
                items: [
                  for (final c in cats)
                    DropdownMenuItem(
                      value: c.id,
                      child: Row(children: [
                        Icon(c.icon, size: 18, color: AppPalette.fg(c.color)),
                        const SizedBox(width: 8),
                        Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ),
            LayoutBuilder(builder: (_, c) {
              final two = c.maxWidth >= 520;
              final a = _field(_language, "Language (e.g. English, Luganda, Korean)");
              final b = _field(_tags, "Tags, separated by commas");
              return two ? Row(children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]) : Column(children: [a, b]);
            }),
            _field(_description, "Description", lines: 3),
            _field(_lyrics, "Lyrics (shown in the player)", lines: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _published,
              onChanged: (v) => setState(() => _published = v),
              title: const Text("Published"),
              subtitle: const Text("When off, only media managers can see it."),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: AppPalette.fg(Colors.red.shade800), fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_kBlue), foregroundColor: AppPalette.fg(Colors.white)),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(_saving ? "Uploading… keep this screen open" : (_isEdit ? "Save changes" : "Upload")),
              ),
            ),
            const SizedBox(height: 8),
            Text("Files are stored privately and play inside the app only; they can't be downloaded from the Media Hub.",
                style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey[600]), fontStyle: FontStyle.italic)),
          ]),
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_kBlue))),
      );

  Widget _field(TextEditingController c, String label, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), alignLabelWithHint: lines > 1),
        ),
      );

  Widget _fileBox({required IconData icon, required String title, required String subtitle, required String button, VoidCallback? onTap, Uint8List? preview}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppPalette.line(Colors.black12))),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 52,
            height: 52,
            color: AppPalette.bg(_kBlue.withValues(alpha: 0.1)),
            child: preview != null ? Image.memory(preview, fit: BoxFit.cover) : Icon(icon, color: AppPalette.fg(_kBlue)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey[600]))),
          ]),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: onTap, child: Text(button)),
      ]),
    );
  }
}

/// Add, edit, reorder, hide or delete Media Hub categories.
class MediaCategoryManager extends StatefulWidget {
  const MediaCategoryManager({super.key});

  @override
  State<MediaCategoryManager> createState() => _MediaCategoryManagerState();
}

class _MediaCategoryManagerState extends State<MediaCategoryManager> {
  List<MediaCategory> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final c = await MediaService.categories(includeInactive: true);
      if (mounted) {
        setState(() {
          _cats = c;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _edit(MediaCategory? c) async {
    final name = TextEditingController(text: c?.name ?? '');
    final desc = TextEditingController(text: c?.description ?? '');
    String kind = c?.mediaKind ?? 'both';
    String icon = c?.iconName ?? 'library_music';
    String color = c?.colorHex ?? MediaService.swatches.first;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(c == null ? "New category" : "Edit category"),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: name, decoration: InputDecoration(labelText: tr("Name"), border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: desc, maxLines: 2, decoration: InputDecoration(labelText: tr("Description (optional)"), border: OutlineInputBorder())),
                const SizedBox(height: 12),
                const Text("Holds", style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(spacing: 6, children: [
                  for (final k in const [('both', 'Audio and video'), ('audio', 'Audio only'), ('video', 'Video only')])
                    ChoiceChip(label: Text(k.$2), selected: kind == k.$1, onSelected: (_) => setD(() => kind = k.$1)),
                ]),
                const SizedBox(height: 12),
                // darkify:off — show the real category colours
                const Text("Icon", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in MediaService.icons.entries)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setD(() => icon = e.key),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: icon == e.key ? MediaService.colorFromHex(color) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(e.value, color: icon == e.key ? Colors.white : Colors.grey.shade700, size: 22),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
                const Text("Colour", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final h in MediaService.swatches)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setD(() => color = h),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: MediaService.colorFromHex(h),
                          shape: BoxShape.circle,
                          border: Border.all(color: color == h ? Colors.black87 : Colors.white, width: 3),
                        ),
                      ),
                    ),
                ]),
              ]),
            ),
          ),
          // darkify:on
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
          ],
        ),
      ),
    );
    if (saved != true || name.text.trim().isEmpty) return;
    try {
      await MediaService.saveCategory(
        MediaCategory(
          id: c?.id ?? '',
          name: name.text.trim(),
          description: desc.text.trim().isEmpty ? null : desc.text.trim(),
          mediaKind: kind,
          iconName: icon,
          colorHex: color,
          sortOrder: c?.sortOrder ?? (_cats.isEmpty ? 1 : _cats.map((x) => x.sortOrder).reduce((a, b) => a > b ? a : b) + 1),
          isActive: c?.isActive ?? true,
        ),
        isNew: c == null,
      );
      _load();
    } catch (e) {
      _snack(e is PostgrestException && e.code == '23505' ? "A category with that name already exists." : "Couldn't save the category.");
    }
  }

  Future<void> _toggleActive(MediaCategory c, bool v) async {
    try {
      await MediaService.saveCategory(
        MediaCategory(
          id: c.id,
          name: c.name,
          description: c.description,
          mediaKind: c.mediaKind,
          iconName: c.iconName,
          colorHex: c.colorHex,
          sortOrder: c.sortOrder,
          isActive: v,
        ),
      );
      _load();
    } catch (_) {
      _snack("Couldn't update the category.");
    }
  }

  Future<void> _delete(MediaCategory c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete \"${c.name}\"?"),
        content: Text(c.itemCount == 0
            ? "The category is empty."
            : "Its ${c.itemCount} item(s) stay in the Media Hub under \"All media\" without a category. To keep the category but hide it, switch it off instead."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Delete", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MediaService.deleteCategory(c.id);
      _load();
    } catch (_) {
      _snack("Couldn't delete the category.");
    }
  }

  // newIndex already allows for the removed item (onReorderItem)
  Future<void> _reorder(int oldIndex, int newIndex) async {
    setState(() {
      final c = _cats.removeAt(oldIndex);
      _cats.insert(newIndex, c);
    });
    try {
      for (int i = 0; i < _cats.length; i++) {
        final c = _cats[i];
        if (c.sortOrder == i + 1) continue;
        await Supabase.instance.client.from('media_categories').update({'sort_order': i + 1}).eq('id', c.id);
      }
      _load();
    } catch (_) {
      _snack("Couldn't save the new order.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Media categories", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17))),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add_rounded),
        label: const Text("New category"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: double.infinity),
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: _cats.length,
                  onReorderItem: _reorder,
                  header: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Text("Drag to change the order on the Media Hub. Switch a category off to hide it without deleting.",
                        style: TextStyle(color: AppPalette.fg(Colors.grey[700]), fontSize: 12.5)),
                  ),
                  itemBuilder: (_, i) {
                    final c = _cats[i];
                    return Card(
                      key: ValueKey(c.id),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: AppPalette.bg(c.color), child: Icon(c.icon, color: AppPalette.fg(Colors.white), size: 20)),
                        title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          "${c.itemCount} item(s) · ${c.mediaKind == 'both' ? 'audio and video' : '${c.mediaKind} only'}${c.isActive ? '' : ' · hidden'}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Switch(value: c.isActive, onChanged: (v) => _toggleActive(c, v)),
                          PopupMenuButton<String>(
                            onSelected: (v) => v == 'edit' ? _edit(c) : _delete(c),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text("Edit")),
                              PopupMenuItem(value: 'delete', child: Text("Delete")),
                            ],
                          ),
                          const SizedBox(width: 24), // room for the drag handle
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}
