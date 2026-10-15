import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLockManager extends ChangeNotifier {
  static final AppLockManager instance = AppLockManager._internal();
  AppLockManager._internal();

  Timer? _inactivityTimer;

  bool _isLockEnabled = true;
  int _timeoutSeconds = 300; // Default: 5 minutes
  String _savedPin = "1234"; // Default PIN if none set
  bool _isLocked = false;
  bool _isInitialized = false;

  bool get isLockEnabled => _isLockEnabled;
  int get timeoutSeconds => _timeoutSeconds;
  String get savedPin => _savedPin;
  bool get isLocked => _isLocked;
  bool get isInitialized => _isInitialized;

  // The 6 exact timeout choices requested
  static const Map<int, String> timeoutOptions = {
    15: "15 Seconds",
    30: "30 Seconds",
    60: "1 Minute",
    300: "5 Minutes",
    600: "10 Minutes",
    900: "15 Minutes",
  };

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isLockEnabled = prefs.getBool('app_lock_enabled') ?? true;
    _timeoutSeconds = prefs.getInt('app_lock_timeout_seconds') ?? 300;
    _savedPin = prefs.getString('app_lock_pin') ?? "1234";
    _isInitialized = true;
    resetInactivityTimer();
    notifyListeners();
  }

  // Resets countdown whenever user touches screen or moves mouse
  void resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (!_isLockEnabled || _isLocked) return;

    _inactivityTimer = Timer(Duration(seconds: _timeoutSeconds), () {
      lockScreen();
    });
  }

  void lockScreen() {
    _inactivityTimer?.cancel();
    _isLocked = true;
    notifyListeners();
  }

  bool unlock(String inputPin) {
    if (inputPin.trim() == _savedPin.trim()) {
      _isLocked = false;
      resetInactivityTimer();
      notifyListeners();
      return true;
    }
    return false;
  }

  // Update Settings from Settings Screen
  Future<void> updateSettings({bool? enabled, int? timeout, String? newPin}) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled != null) {
      _isLockEnabled = enabled;
      await prefs.setBool('app_lock_enabled', enabled);
    }
    if (timeout != null) {
      _timeoutSeconds = timeout;
      await prefs.setInt('app_lock_timeout_seconds', timeout);
    }
    if (newPin != null && newPin.isNotEmpty) {
      _savedPin = newPin;
      await prefs.setString('app_lock_pin', newPin);
    }
    resetInactivityTimer();
    notifyListeners();
  }
}