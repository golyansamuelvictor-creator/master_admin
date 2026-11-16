import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Locks the app after a period without any touch, mouse or key activity.
///
/// - Only while someone is signed in.
/// - Each user has their own PIN, stored (hashed) in Supabase table
///   `user_security` (09_round8.sql), so it follows them to every device.
///   A copy of the hash is kept on the device so unlocking works offline.
/// - A user without a PIN unlocks with their account password instead.
/// - Defaults: on, 5 minutes.
/// - The lock survives a refresh, a new tab or reopening the app: the locked
///   state and the time of the last activity are kept on the device, so a
///   page reload never skips the PIN / password.
class AppLockManager extends ChangeNotifier {
  static final AppLockManager instance = AppLockManager._internal();
  AppLockManager._internal();

  Timer? _inactivityTimer;
  StreamSubscription<AuthState>? _authSub;
  DateTime _lastActivity = DateTime.now();

  bool _isLockEnabled = true;
  int _timeoutSeconds = 300;
  String? _pinHash;
  String? _pinSalt;
  bool _isLocked = false;
  bool _isInitialized = false;
  bool _remoteChecked = false;
  String? _userId;

  bool get isLockEnabled => _isLockEnabled;
  int get timeoutSeconds => _timeoutSeconds;
  bool get hasPin => (_pinHash ?? '').isNotEmpty;
  bool get isLocked => _isLocked;
  bool get isInitialized => _isInitialized;
  /// Signed in, lock on, account settings read, and still no PIN: the app
  /// offers to create one (once per app start).
  bool get needsPinPrompt => _remoteChecked && _signedIn && _isLockEnabled && !hasPin;

  bool get _signedIn => Supabase.instance.client.auth.currentSession != null;

  /// Shown on the lock screen: who is locked out.
  String get userEmail => Supabase.instance.client.auth.currentUser?.email ?? '';

  static const Map<int, String> timeoutOptions = {
    60: "1 minute",
    120: "2 minutes",
    300: "5 minutes",
    600: "10 minutes",
    900: "15 minutes",
    1800: "30 minutes",
  };

  Future<void> init() async {
    _authSub?.cancel();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      final id = s.session?.user.id;
      if (id == null) {
        // signed out: the next sign-in starts unlocked
        final old = _userId;
        _userId = null;
        _pinHash = null;
        _pinSalt = null;
        _isLocked = false;
        _inactivityTimer?.cancel();
        if (old != null && s.event == AuthChangeEvent.signedOut) unawaited(_clearLockState(old));
        notifyListeners();
      } else if (id != _userId) {
        // a sign-in in this page (password, code, switching accounts): fresh
        _isLocked = false;
        _load(id, fresh: true);
      }
    });
    final id = Supabase.instance.client.auth.currentUser?.id;
    // Coming back from Google sign-in is a fresh sign-in too.
    final u = Uri.base;
    final oauth = u.queryParameters.containsKey('code') || u.queryParameters.containsKey('token_hash') || u.fragment.contains('access_token');
    try {
      if (id != null) await _load(id, fresh: oauth);
    } catch (e) {
      debugPrint("App lock: $e");
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  // ---- the lock kept on the device (survives refresh / reopening)
  static String _kLocked(String id) => 'app_lock_locked_$id';
  static String _kLast(String id) => 'app_lock_last_$id';
  DateTime _lastSaved = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _saveLockState({bool force = false}) async {
    final id = _userId;
    if (id == null) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastSaved) < const Duration(seconds: 15)) return;
    _lastSaved = now;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kLocked(id), _isLocked);
      await p.setInt(_kLast(id), _lastActivity.millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<void> _clearLockState(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kLocked(id));
      await p.remove(_kLast(id));
    } catch (_) {}
  }

  Future<void> _load(String userId, {bool fresh = false}) async {
    _userId = userId;
    _remoteChecked = false;
    final prefs = await SharedPreferences.getInstance();
    // Device copy first (works offline), then the account copy.
    _isLockEnabled = prefs.getBool('app_lock_enabled_$userId') ?? prefs.getBool('app_lock_enabled') ?? true;
    _timeoutSeconds = prefs.getInt('app_lock_timeout_$userId') ?? 300;
    if (!timeoutOptions.containsKey(_timeoutSeconds)) _timeoutSeconds = 300;
    _pinHash = prefs.getString('app_lock_hash_$userId');
    _pinSalt = prefs.getString('app_lock_salt_$userId');
    if (fresh) {
      _isLocked = false;
      resetInactivityTimer();
      await _saveLockState(force: true);
    } else {
      // reload / reopened: locked before, or away longer than the timeout
      final wasLocked = prefs.getBool(_kLocked(userId)) ?? false;
      final lastMs = prefs.getInt(_kLast(userId));
      final away = lastMs == null ? 0 : DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastMs)).inSeconds;
      if (_isLockEnabled && (wasLocked || away >= _timeoutSeconds)) {
        _inactivityTimer?.cancel();
        _isLocked = true;
        await _saveLockState(force: true);
      } else {
        resetInactivityTimer();
      }
    }
    notifyListeners();
    unawaited(_loadRemote(userId, prefs));
  }

  /// The account copy of the lock settings (PIN, on/off, timeout).
  Future<void> _loadRemote(String userId, SharedPreferences prefs) async {
    try {
      final row = await Supabase.instance.client.from('user_security').select().eq('user_id', userId).maybeSingle();
      if (_userId != userId) return;
      if (row != null) {
        _isLockEnabled = row['lock_enabled'] != false;
        final t = (row['timeout_seconds'] as num?)?.toInt() ?? 300;
        _timeoutSeconds = timeoutOptions.containsKey(t) ? t : 300;
        _pinHash = row['pin_hash']?.toString();
        _pinSalt = row['pin_salt']?.toString();
        await _saveLocal(prefs);
      } else {
        // Older versions kept a PIN on the device only. Move a PIN the user
        // chose themselves (not the old built-in 1234) to their account.
        final old = prefs.getString('app_lock_pin');
        if (old != null && old.isNotEmpty && old != '1234') await setPin(old);
      }
      _remoteChecked = true;
      if (!_isLockEnabled && _isLocked) {
        _isLocked = false; // the lock was turned off on another device
        await _saveLockState(force: true);
      }
      resetInactivityTimer();
      notifyListeners();
    } catch (e) {
      debugPrint("App lock settings not loaded (run 09_round8.sql): $e");
    }
  }

  Future<void> _saveLocal([SharedPreferences? p]) async {
    final prefs = p ?? await SharedPreferences.getInstance();
    final id = _userId;
    if (id == null) return;
    await prefs.setBool('app_lock_enabled_$id', _isLockEnabled);
    await prefs.setInt('app_lock_timeout_$id', _timeoutSeconds);
    if (hasPin) {
      await prefs.setString('app_lock_hash_$id', _pinHash!);
      await prefs.setString('app_lock_salt_$id', _pinSalt ?? '');
    } else {
      await prefs.remove('app_lock_hash_$id');
      await prefs.remove('app_lock_salt_$id');
    }
  }

  Future<void> _saveRemote() async {
    final id = _userId;
    if (id == null) return;
    await Supabase.instance.client.from('user_security').upsert({
      'user_id': id,
      'pin_hash': _pinHash,
      'pin_salt': _pinSalt,
      'lock_enabled': _isLockEnabled,
      'timeout_seconds': _timeoutSeconds,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static String _hash(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt:$pin');
    for (int i = 0; i < 2000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Url.encode(bytes);
  }

  static String _newSalt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  bool checkPin(String pin) => hasPin && _hash(pin.trim(), _pinSalt ?? '') == _pinHash;

  /// Any activity (touch, mouse, key) restarts the countdown.
  void resetInactivityTimer() {
    if (_isLocked) return; // activity behind the lock screen doesn't count
    _lastActivity = DateTime.now();
    _inactivityTimer?.cancel();
    unawaited(_saveLockState());
    if (!_isLockEnabled || !_signedIn) return;
    _inactivityTimer = Timer(Duration(seconds: _timeoutSeconds), lockScreen);
  }

  /// Called when the app comes back to the front: a phone that slept, or a
  /// browser tab left in the background, locks if it was away too long.
  void checkElapsed() {
    if (!_isLockEnabled || _isLocked || !_signedIn) return;
    if (DateTime.now().difference(_lastActivity).inSeconds >= _timeoutSeconds) {
      lockScreen();
    } else {
      _inactivityTimer?.cancel();
      final left = _timeoutSeconds - DateTime.now().difference(_lastActivity).inSeconds;
      _inactivityTimer = Timer(Duration(seconds: left), lockScreen);
    }
  }

  void lockScreen() {
    if (!_signedIn || !_isLockEnabled) return;
    _inactivityTimer?.cancel();
    _isLocked = true;
    unawaited(_saveLockState(force: true));
    notifyListeners();
  }

  void _unlocked() {
    _isLocked = false;
    resetInactivityTimer();
    unawaited(_saveLockState(force: true));
    notifyListeners();
  }

  /// Unlock with the PIN.
  bool unlock(String inputPin) {
    if (checkPin(inputPin)) {
      _unlocked();
      return true;
    }
    return false;
  }

  /// Unlock with the account password (users without a PIN, or who forgot it).
  Future<bool> unlockWithPassword(String password) async {
    final email = userEmail;
    if (email.isEmpty || password.isEmpty) return false;
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
      _unlocked();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Leaves the account; the sign-in screen shows next.
  Future<void> signOut() async {
    _isLocked = false;
    _inactivityTimer?.cancel();
    notifyListeners();
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> setPin(String pin) async {
    _pinSalt = _newSalt();
    _pinHash = _hash(pin.trim(), _pinSalt!);
    await _saveLocal();
    notifyListeners();
    await _saveRemote();
  }

  Future<void> removePin() async {
    _pinHash = null;
    _pinSalt = null;
    await _saveLocal();
    notifyListeners();
    await _saveRemote();
  }

  Future<void> updateSettings({bool? enabled, int? timeout, String? newPin}) async {
    if (enabled != null) _isLockEnabled = enabled;
    if (timeout != null && timeoutOptions.containsKey(timeout)) _timeoutSeconds = timeout;
    if (newPin != null && newPin.isNotEmpty) {
      _pinSalt = _newSalt();
      _pinHash = _hash(newPin.trim(), _pinSalt!);
    }
    await _saveLocal();
    resetInactivityTimer();
    notifyListeners();
    await _saveRemote();
  }
}
