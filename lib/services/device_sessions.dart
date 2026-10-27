import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Settings › Devices (like Telegram): every place the person is signed in,
/// with device name, platform, approximate city / country and last activity.
///
/// Each device keeps a random key; its row lives in `user_devices`
/// (09_round8.sql). "Terminate" marks a device revoked: it signs itself out
/// the next time it checks (on start, when it comes back to the front, and
/// every 2 minutes while open).
class DeviceSessions {
  DeviceSessions._();

  static const String appVersion = '10.3';
  static String? _key;
  static Timer? _timer;
  static StreamSubscription<AuthState>? _sub;
  static Map<String, dynamic>? _place;
  static String? _name;
  static String? _platform;

  static SupabaseClient get _db => Supabase.instance.client;

  static Future<String> deviceKey() async {
    if (_key != null) return _key!;
    final prefs = await SharedPreferences.getInstance();
    var k = prefs.getString('device_key');
    if (k == null) {
      final r = Random.secure();
      k = List.generate(24, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)]).join();
      await prefs.setString('device_key', k);
    }
    return _key = k;
  }

  static void start() {
    _sub?.cancel();
    _sub = _db.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn || s.event == AuthChangeEvent.initialSession) {
        if (s.session != null) check(register: true);
      }
      if (s.session == null) _timer?.cancel();
    });
    if (_db.auth.currentSession != null) check(register: true);
  }

  static String _browser(BrowserName b) => switch (b) {
        BrowserName.chrome => 'Chrome',
        BrowserName.edge => 'Edge',
        BrowserName.firefox => 'Firefox',
        BrowserName.safari => 'Safari',
        BrowserName.opera => 'Opera',
        BrowserName.samsungInternet => 'Samsung Internet',
        BrowserName.msie => 'Internet Explorer',
        _ => 'Browser',
      };

  static String _os() => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'Android',
        TargetPlatform.iOS => 'iPhone / iPad',
        TargetPlatform.windows => 'Windows',
        TargetPlatform.macOS => 'Mac',
        TargetPlatform.linux => 'Linux',
        _ => 'Unknown',
      };

  static Future<void> _describe() async {
    if (_name != null) return;
    final info = DeviceInfoPlugin();
    _platform = kIsWeb ? 'web' : _os().toLowerCase();
    try {
      if (kIsWeb) {
        final w = await info.webBrowserInfo;
        _name = "${_browser(w.browserName)} on ${_os()}";
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await info.androidInfo;
        _name = "${a.manufacturer} ${a.model}".trim();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final i = await info.iosInfo;
        _name = i.name.isNotEmpty ? i.name : i.model;
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        _name = "Windows · ${(await info.windowsInfo).computerName}";
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        _name = "Mac · ${(await info.macOsInfo).computerName}";
      }
    } catch (_) {}
    _name ??= _os();
  }

  /// Approximate place from the internet address (city level). Best effort.
  static Future<void> _locate() async {
    if (_place != null) return;
    try {
      final r = await http.get(Uri.parse('https://ipwho.is/?fields=ip,city,country,success')).timeout(const Duration(seconds: 4));
      final j = jsonDecode(r.body);
      if (j is Map && j['success'] != false) _place = Map<String, dynamic>.from(j);
    } catch (_) {
      _place = {};
    }
  }

  /// Registers this device / updates its activity, and signs out if it was terminated.
  static Future<void> check({bool register = false}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final key = await deviceKey();
      final row = await _db.from('user_devices').select('id, revoked_at').eq('user_id', uid).eq('device_key', key).maybeSingle();
      if (row != null && row['revoked_at'] != null) {
        // Terminated from another device: a fresh sign-in starts a new session row.
        await _db.from('user_devices').delete().eq('id', row['id']);
        await _db.auth.signOut(scope: SignOutScope.local);
        return;
      }
      if (register || row == null) {
        await _describe();
        await _locate();
      }
      await _db.from('user_devices').upsert({
        'user_id': uid,
        'device_key': key,
        if (_name != null) 'device_name': _name,
        if (_platform != null) 'platform': _platform,
        'app_version': appVersion,
        if ((_place?['city'] ?? '').toString().isNotEmpty) 'city': _place!['city'],
        if ((_place?['country'] ?? '').toString().isNotEmpty) 'country': _place!['country'],
        if ((_place?['ip'] ?? '').toString().isNotEmpty) 'ip': _place!['ip'],
        'last_active': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,device_key');
      _timer ??= Timer.periodic(const Duration(minutes: 2), (_) => check());
    } catch (e) {
      debugPrint("Device check skipped (run 09_round8.sql): $e");
    }
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _db.from('user_devices').select().eq('user_id', uid).isFilter('revoked_at', null).order('last_active', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> terminate(String id) =>
      _db.from('user_devices').update({'revoked_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);

  /// Signs out everywhere else: revokes the other sessions' tokens and marks their devices.
  static Future<void> terminateOthers() async {
    final uid = _db.auth.currentUser?.id;
    final key = await deviceKey();
    if (uid == null) return;
    await _db
        .from('user_devices')
        .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', uid)
        .neq('device_key', key)
        .isFilter('revoked_at', null);
    try {
      await _db.auth.signOut(scope: SignOutScope.others);
    } catch (_) {}
  }
}
