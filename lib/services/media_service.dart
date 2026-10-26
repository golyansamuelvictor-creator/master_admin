import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A Media Hub category (edited in the app; stored in media_categories).
class MediaCategory {
  final String id;
  final String name;
  final String? description;
  final String mediaKind; // audio | video | both
  final String iconName;
  final String colorHex;
  final int sortOrder;
  final bool isActive;
  final int itemCount;

  const MediaCategory({
    required this.id,
    required this.name,
    this.description,
    this.mediaKind = 'both',
    this.iconName = 'library_music',
    this.colorHex = '#4A148C',
    this.sortOrder = 0,
    this.isActive = true,
    this.itemCount = 0,
  });

  Color get color => MediaService.colorFromHex(colorHex);
  IconData get icon => MediaService.iconFor(iconName, name);

  factory MediaCategory.fromMap(Map m, {int count = 0}) => MediaCategory(
        id: m['id'].toString(),
        name: (m['name'] ?? '').toString(),
        description: m['description']?.toString(),
        mediaKind: (m['media_kind'] ?? 'both').toString(),
        iconName: (m['icon_name'] ?? 'library_music').toString(),
        colorHex: (m['color_hex'] ?? '#4A148C').toString(),
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        isActive: m['is_active'] != false,
        itemCount: count,
      );
}

/// One song or video.
class MediaItem {
  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String? categoryId;
  final String mediaType; // audio | video | youtube
  final String? storagePath;
  final String? thumbnailPath;
  final String? legacyUrl; // old media_url (YouTube links)
  final String? legacyThumbUrl;
  final String? description;
  final String? lyrics;
  final String? language;
  final List<String> tags;
  final int? durationSeconds;
  final int? fileSize;
  final String? mimeType;
  final bool isPublished;
  final int playCount;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  const MediaItem({
    required this.id,
    required this.title,
    required this.mediaType,
    required this.raw,
    this.artist,
    this.album,
    this.categoryId,
    this.storagePath,
    this.thumbnailPath,
    this.legacyUrl,
    this.legacyThumbUrl,
    this.description,
    this.lyrics,
    this.language,
    this.tags = const [],
    this.durationSeconds,
    this.fileSize,
    this.mimeType,
    this.isPublished = true,
    this.playCount = 0,
    this.createdAt,
  });

  bool get isVideo => mediaType == 'video';
  bool get isAudio => mediaType == 'audio';
  bool get isYoutube => mediaType == 'youtube';

  factory MediaItem.fromMap(Map m) {
    final url = m['media_url']?.toString();
    String type = (m['media_type'] ?? '').toString();
    if (type.isEmpty) {
      type = (url ?? '').contains('youtu') ? 'youtube' : ((m['category'] ?? '').toString().toLowerCase().startsWith('video') ? 'video' : 'audio');
    }
    return MediaItem(
      id: m['id'].toString(),
      title: (m['title'] ?? 'Untitled').toString(),
      artist: m['artist']?.toString(),
      album: m['album']?.toString(),
      categoryId: m['category_id']?.toString(),
      mediaType: type,
      storagePath: m['storage_path']?.toString(),
      thumbnailPath: m['thumbnail_path']?.toString(),
      legacyUrl: url,
      legacyThumbUrl: m['thumbnail_url']?.toString(),
      description: m['description']?.toString(),
      lyrics: m['lyrics']?.toString(),
      language: m['language']?.toString(),
      tags: (m['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      durationSeconds: (m['duration_seconds'] as num?)?.toInt(),
      fileSize: (m['file_size'] as num?)?.toInt(),
      mimeType: m['mime_type']?.toString(),
      isPublished: m['is_published'] != false,
      playCount: (m['play_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal(),
      raw: Map<String, dynamic>.from(m),
    );
  }
}

/// Media Hub data. Files live in the private "media" bucket and are only
/// played through short-lived links inside the app (no download links).
class MediaService {
  MediaService._();

  static const String bucket = 'media';
  static const String manageAction = 'Manage Media';
  static SupabaseClient get _db => Supabase.instance.client;

  static const Map<String, IconData> icons = {
    'church': Icons.church_rounded,
    'school': Icons.school_rounded,
    'graphic_eq': Icons.graphic_eq_rounded,
    'mic': Icons.mic_rounded,
    'library_music': Icons.library_music_rounded,
    'music_note': Icons.music_note_rounded,
    'queue_music': Icons.queue_music_rounded,
    'headphones': Icons.headphones_rounded,
    'album': Icons.album_rounded,
    'piano': Icons.piano_rounded,
    'movie': Icons.movie_rounded,
    'video_library': Icons.video_library_rounded,
    'live_tv': Icons.live_tv_rounded,
    'celebration': Icons.celebration_rounded,
    'favorite': Icons.favorite_rounded,
    'star': Icons.star_rounded,
    'campaign': Icons.campaign_rounded,
    'auto_stories': Icons.auto_stories_rounded,
    'lyrics': Icons.lyrics_rounded,
    'music_video': Icons.music_video_rounded,
    'mic_external': Icons.mic_external_on_rounded,
    'record_voice': Icons.record_voice_over_rounded,
    'podcasts': Icons.podcasts_rounded,
    'radio': Icons.radio_rounded,
    'groups': Icons.groups_rounded,
    'child_care': Icons.child_care_rounded,
    'volunteer': Icons.volunteer_activism_rounded,
    'menu_book': Icons.menu_book_rounded,
    'audiotrack': Icons.audiotrack_rounded,
    'speaker': Icons.speaker_rounded,
    'theaters': Icons.theaters_rounded,
    'videocam': Icons.videocam_rounded,
  };

  /// Bright, light colours for new categories.
  static const List<String> swatches = ['#7C3AED', '#2563EB', '#DB2777', '#F97316', '#16A34A', '#0D9488', '#0EA5E9', '#E11D48', '#CA8A04', '#9333EA'];

  /// The chosen icon; for categories still on the default icon, one that
  /// fits the name (Praise songs → playlist, Sermons → speaker, Kids → child …).
  static IconData iconFor(String key, String name) {
    if (key != 'library_music' && icons[key] != null) return icons[key]!;
    final n = name.toLowerCase();
    bool has(List<String> words) => words.any(n.contains);
    if (has(['praise', 'worship', 'hymn', 'song'])) return Icons.queue_music_rounded;
    if (has(['center', 'centre', 'church', 'zion'])) return Icons.church_rounded;
    if (has(['sermon', 'word', 'message', 'preach', 'lecture', 'teaching'])) return Icons.record_voice_over_rounded;
    if (has(['choir', 'group', 'chorus'])) return Icons.groups_rounded;
    if (has(['kid', 'child', 'youth', 'sunday school'])) return Icons.child_care_rounded;
    if (has(['instrument', 'piano', 'keyboard', 'guitar'])) return Icons.piano_rounded;
    if (has(['video', 'film', 'movie', 'clip'])) return Icons.video_library_rounded;
    if (has(['podcast', 'radio', 'talk'])) return Icons.podcasts_rounded;
    if (has(['event', 'celebrat', 'festival', 'wedding'])) return Icons.celebration_rounded;
    if (has(['bible', 'scripture', 'study', 'education'])) return Icons.auto_stories_rounded;
    if (has(['announce', 'news'])) return Icons.campaign_rounded;
    return icons[key] ?? Icons.library_music_rounded;
  }

  static Color colorFromHex(String hex) {
    final h = hex.replaceFirst('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return Color(v ?? 0xFF4A148C);
  }

  // Last results, so screens show something at once and refresh in the background.
  static List<MediaCategory>? cachedCategories;
  static List<MediaItem>? cachedRecent;
  static final Map<String, List<MediaItem>> cachedLists = {};

  static Future<List<MediaCategory>> categories({bool includeInactive = false}) async {
    var q = _db.from('media_categories').select();
    if (!includeInactive) q = q.eq('is_active', true);
    // categories and item counts at the same time
    final results = await Future.wait<dynamic>([
      q.order('sort_order').order('name'),
      _db.from('media_library').select('category_id').then<dynamic>((v) => v, onError: (_) => const []),
    ]);
    final rows = results[0] as List;
    final Map<String, int> counts = {};
    for (final r in results[1] as List) {
      final k = ((r as Map)['category_id'] ?? '').toString();
      if (k.isNotEmpty) counts[k] = (counts[k] ?? 0) + 1;
    }
    final list = rows.map((r) => MediaCategory.fromMap(r as Map, count: counts[(r)['id'].toString()] ?? 0)).toList();
    if (!includeInactive) cachedCategories = list;
    return list;
  }

  static Future<void> saveCategory(MediaCategory c, {bool isNew = false}) async {
    final data = {
      'name': c.name,
      'description': c.description,
      'media_kind': c.mediaKind,
      'icon_name': c.iconName,
      'color_hex': c.colorHex,
      'sort_order': c.sortOrder,
      'is_active': c.isActive,
    };
    if (isNew) {
      await _db.from('media_categories').insert(data);
    } else {
      await _db.from('media_categories').update(data).eq('id', c.id);
    }
  }

  static Future<void> deleteCategory(String id) => _db.from('media_categories').delete().eq('id', id);

  /// [categoryId] null = all categories. [type] audio | video | null.
  static Future<List<MediaItem>> items({String? categoryId, String? type, String search = '', String sort = 'newest', int limit = 300}) async {
    var q = _db.from('media_library').select();
    if (categoryId != null) q = q.eq('category_id', categoryId);
    if (type != null) q = q.eq('media_type', type);
    final s = search.trim().replaceAll(',', ' ');
    if (s.isNotEmpty) q = q.or('title.ilike.%$s%,artist.ilike.%$s%,album.ilike.%$s%');
    final ordered = switch (sort) {
      'az' => q.order('title', ascending: true),
      'popular' => q.order('play_count', ascending: false),
      _ => q.order('created_at', ascending: false),
    };
    final rows = await ordered.limit(limit);
    return (rows as List).map((r) => MediaItem.fromMap(r as Map)).toList();
  }

  static Future<void> deleteItem(MediaItem m) async {
    final paths = [if ((m.storagePath ?? '').isNotEmpty) m.storagePath!, if ((m.thumbnailPath ?? '').isNotEmpty) m.thumbnailPath!];
    if (paths.isNotEmpty) {
      try {
        await _db.storage.from(bucket).remove(paths);
      } catch (_) {}
    }
    await _db.from('media_library').delete().eq('id', m.id);
  }

  static String mimeFor(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    const map = {
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'oga': 'audio/ogg',
      'flac': 'audio/flac',
      'opus': 'audio/opus',
      'mp4': 'video/mp4',
      'm4v': 'video/mp4',
      'mov': 'video/quicktime',
      'webm': 'video/webm',
      'mkv': 'video/x-matroska',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  static Future<String> upload(Uint8List bytes, String fileName, {required String folder}) async {
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _db.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeFor(fileName), upsert: false));
    return path;
  }

  static Future<void> saveItem(Map<String, dynamic> data, {String? id}) async {
    data['updated_at'] = DateTime.now().toUtc().toIso8601String();
    if (id == null) {
      await _db.from('media_library').insert(data);
    } else {
      await _db.from('media_library').update(data).eq('id', id);
    }
  }

  static Future<void> recordPlay(String id, int? seconds) async {
    try {
      await _db.rpc('media_record_play', params: {'p_id': id, 'p_duration': seconds});
    } catch (_) {}
  }

  // Short-lived links (cached a little under their lifetime)
  static final Map<String, (String, DateTime)> _links = {};

  static Future<String?> link(String? path, {int seconds = 4 * 3600}) async {
    if (path == null || path.isEmpty) return null;
    final hit = _links[path];
    if (hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
    try {
      final url = await _db.storage.from(bucket).createSignedUrl(path, seconds);
      _links[path] = (url, DateTime.now().add(Duration(seconds: seconds - 300)));
      return url;
    } catch (_) {
      return null;
    }
  }

  static Future<void> preloadThumbs(List<MediaItem> items) async {
    final need = items.map((m) => m.thumbnailPath).whereType<String>().where((p) => p.isNotEmpty && !_links.containsKey(p)).toSet().toList();
    if (need.isEmpty) return;
    try {
      // ignore: deprecated_member_use
      final res = await _db.storage.from(bucket).createSignedUrls(need, 4 * 3600);
      for (final s in res) {
        _links[s.path] = (s.signedUrl, DateTime.now().add(const Duration(hours: 3, minutes: 55)));
      }
    } catch (_) {}
  }

  static String? cachedLink(String? path) {
    if (path == null) return null;
    final hit = _links[path];
    return hit != null && hit.$2.isAfter(DateTime.now()) ? hit.$1 : null;
  }

  static String formatDuration(Duration d) {
    final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    return h > 0 ? '$h:$mm:${s.toString().padLeft(2, '0')}' : '$mm:${s.toString().padLeft(2, '0')}';
  }
}
