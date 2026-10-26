import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// While a signed-in user registers another account on this device, Supabase
/// briefly signs in as the new account. The sign-in gate (AuthWrapper) ignores
/// those changes until [release], so the current user's screens stay as they
/// are, then it catches up with whatever session is active.
class RegistrationGuard {
  RegistrationGuard._();

  static bool active = false;
  static void Function()? onRelease;

  static void hold() => active = true;

  static void release() {
    if (!active) return;
    active = false;
    onRelease?.call();
  }
}

/// Accounts used on this device, with each account's latest sign-in session.
///
/// Switching accounts used to ask for the other account's PASSWORD, so only
/// email accounts could be added — Google and WhatsApp accounts have none.
/// Now every sign-in (email, Google, WhatsApp) is remembered here, and
/// switching restores the saved session: no password or code needed.
class DeviceAccounts {
  DeviceAccounts._();

  static const String _key = 'device_sessions_v1';
  static StreamSubscription<AuthState>? _sub;

  static SupabaseClient get _client => Supabase.instance.client;

  /// Call once after Supabase.initialize(): keeps the saved session of the
  /// signed-in account up to date (tokens refresh regularly).
  static void startTracking() {
    _sub ??= _client.auth.onAuthStateChange.listen((s) {
      final session = s.session;
      if (session != null) _save(session);
    });
    final current = _client.auth.currentSession;
    if (current != null) _save(current);
  }

  static Future<Map<String, Map<String, dynamic>>> _readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeAll(Map<String, Map<String, dynamic>> all) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(all));
      // Keep the older id list (used to show the account list) in step
      final ids = prefs.getStringList('device_account_ids') ?? [];
      for (final id in all.keys) {
        if (!ids.contains(id)) ids.add(id);
      }
      await prefs.setStringList('device_account_ids', ids);
    } catch (_) {}
  }

  static Future<void> _save(Session session) async {
    final token = session.refreshToken;
    if (token == null || token.isEmpty) return;
    final all = await _readAll();
    final user = session.user;
    all[user.id] = {
      'refresh_token': token,
      'email': user.email ?? '',
      'phone': user.phone ?? '',
      'provider': (user.appMetadata['provider'] ?? 'email').toString(),
      'saved_at': DateTime.now().toIso8601String(),
    };
    await _writeAll(all);
  }

  /// How the account signs in: 'email', 'google' or 'phone' (WhatsApp).
  static Future<String?> providerOf(String userId) async => (await _readAll())[userId]?['provider']?.toString();

  /// Finds a saved account by id, or by email / phone when the id is unknown.
  static Future<String?> findId({String? id, String? email, String? phone}) async {
    final all = await _readAll();
    if (id != null && id.isNotEmpty && all.containsKey(id)) return id;
    final e = (email ?? '').trim().toLowerCase();
    final p = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    for (final entry in all.entries) {
      final se = (entry.value['email'] ?? '').toString().toLowerCase();
      final sp = (entry.value['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (e.isNotEmpty && e.contains('@') && se == e) return entry.key;
      if (p.length >= 9 && sp.isNotEmpty && (sp.endsWith(p) || p.endsWith(sp))) return entry.key;
    }
    return null;
  }

  /// Switches to a saved account without a password. Returns false when the
  /// saved session is missing or no longer valid (then sign in again).
  static Future<bool> restore(String userId) async {
    final all = await _readAll();
    final token = all[userId]?['refresh_token']?.toString();
    if (token == null || token.isEmpty) return false;
    try {
      final res = await _client.auth.setSession(token);
      if (res.session != null) {
        await _save(res.session!);
        return true;
      }
    } catch (_) {}
    // The saved session expired or was revoked: forget it so the app asks to sign in
    all[userId]?.remove('refresh_token');
    await _writeAll(all);
    return false;
  }
}
