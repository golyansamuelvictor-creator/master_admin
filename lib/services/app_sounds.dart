import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

/// The person's notification and sound choices (Supabase `user_settings`,
/// 09_round8.sql), and the sounds the app plays.
///
/// Sounds are the files in assets/sounds/. A new notification plays the
/// notification sound; a new chat message plays the message sound.
class AppSounds {
  AppSounds._();

  /// key → name shown in Settings. Files: `assets/sounds/<key>.wav`
  static const Map<String, String> catalog = {
    'chime': 'Chime',
    'crystal': 'Crystal',
    'bell': 'Bell',
    'harp': 'Harp',
    'marimba': 'Marimba',
    'rise': 'Rise',
    'ping': 'Ping',
    'pop': 'Pop',
    'chirp': 'Chirp',
    'triple': 'Triple beep',
    'none': 'No sound',
  };

  // Old names saved by earlier versions
  static const Map<String, String> _legacy = {
    'Default Chime': 'chime',
    'Crystal Wave': 'crystal',
    'Electronic Chirp': 'chirp',
    'Simple Ping': 'ping',
  };

  static final ValueNotifier<Map<String, dynamic>> prefs = ValueNotifier({});
  static String? _loadedFor;

  static T _get<T>(String k, T fallback) {
    final v = prefs.value[k];
    return v is T ? v : fallback;
  }

  static bool get soundsOn => _get('sounds_enabled', true);
  static bool get bannersOn => _get('banners_enabled', true);
  static double get volume => (prefs.value['sound_volume'] as num?)?.toDouble() ?? 0.8;
  static String get notifSound => _norm(_get<String>('notif_sound', 'chime'));
  static String get messageSound => _norm(_get<String>('message_sound', 'pop'));
  static bool wants(String kind) => switch (kind) {
        'report' => _get('notify_reports', true),
        'transfer' => _get('notify_transfers', true),
        'account' => _get('notify_accounts', true),
        'message' => _get('notify_messages', true),
        _ => true,
      };

  static String _norm(String k) => _legacy[k] ?? (catalog.containsKey(k) ? k : 'chime');

  static Future<Map<String, dynamic>> load({bool force = false}) async {
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    if (uid == null) return {};
    if (!force && _loadedFor == uid) return prefs.value;
    try {
      final row = await db.from('user_settings').select().eq('user_id', uid).maybeSingle();
      prefs.value = Map<String, dynamic>.from(row ?? {});
      _loadedFor = uid;
    } catch (e) {
      debugPrint("Settings not loaded: $e");
    }
    return prefs.value;
  }

  /// Saves one or more choices (and updates [prefs] at once).
  static Future<void> save(Map<String, dynamic> values) async {
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    if (uid == null) return;
    prefs.value = {...prefs.value, ...values};
    await db.from('user_settings').upsert({'user_id': uid, ...values, 'updated_at': DateTime.now().toUtc().toIso8601String()});
  }

  static VideoPlayerController? _player;

  /// Plays a sound by key (used by the preview buttons too).
  static Future<void> play(String key, {double? vol}) async {
    if (key == 'none') return;
    try {
      final old = _player;
      _player = VideoPlayerController.asset('assets/sounds/${_norm(key)}.wav');
      await old?.dispose();
      await _player!.initialize();
      await _player!.setVolume((vol ?? volume).clamp(0.0, 1.0));
      await _player!.play();
    } catch (e) {
      debugPrint("Sound not played: $e");
    }
  }

  static Future<void> notification(String kind) async {
    if (!soundsOn || !wants(kind)) return;
    await play(notifSound);
  }

  static Future<void> message() async {
    if (!soundsOn || !wants('message')) return;
    await play(messageSound);
  }
}