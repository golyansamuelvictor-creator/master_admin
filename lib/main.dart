// ignore_for_file: deprecated_member_use, curly_braces_in_flow_control_structures
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/app_lock_manager.dart';
import 'services/profile_refresh.dart';
import 'services/device_accounts.dart';
import 'package:master_admin/core/app_palette.dart';

// ==========================================
// SHARED CONSTANTS
// ==========================================
const Color kPurple = Color(0xFF4A148C);
const Color kGold = Color(0xFFB78103);
const Color kDarkBg = Color(0xFF0F071A);
const Color kLightBg = Color(0xFFF6F2FA);

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://bbottkhzcpzjsufeyryv.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJib3R0a2h6Y3B6anN1ZmV5cnl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzNTg1NTEsImV4cCI6MjA4NDkzNDU1MX0.EwHg23bzbS27WB6-F4lvp1VI2kZ3YmnENVw-OkvSsHk',
  );

  await AppLockManager.instance.init();

  // Remember every account's sign-in on this device (email, Google, WhatsApp)
  // so Switch Account works without a password.
  DeviceAccounts.startTracking();

  try {
    final prefs = await SharedPreferences.getInstance();
    themeNotifier.value = themeModeFromName(prefs.getString('theme_mode'));
  } catch (_) {}

  // Load every Merriweather weight the app uses BEFORE the first screen.
  // Otherwise text first appears in a fallback font and then switches to
  // Merriweather a moment later (each weight was fetched the first time it
  // was drawn). Capped so a slow connection never blocks the app.
  try {
    await GoogleFonts.pendingFonts([
      GoogleFonts.merriweather(),
      GoogleFonts.merriweather(fontWeight: FontWeight.w300),
      GoogleFonts.merriweather(fontWeight: FontWeight.w500),
      GoogleFonts.merriweather(fontWeight: FontWeight.w600),
      GoogleFonts.merriweather(fontWeight: FontWeight.bold),
      GoogleFonts.merriweather(fontWeight: FontWeight.w800),
      GoogleFonts.merriweather(fontWeight: FontWeight.w900),
      GoogleFonts.merriweather(fontStyle: FontStyle.italic),
      GoogleFonts.merriweather(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
    ]).timeout(const Duration(seconds: 6));
  } catch (_) {}

  runApp(const MasterAdminApp());
}

/// Theme choice saved on the device: 'system', 'light' or 'dark'.
ThemeMode themeModeFromName(String? name) {
  switch (name) {
    case 'dark':
      return ThemeMode.dark;
    case 'system':
      return ThemeMode.system;
    default:
      return ThemeMode.light;
  }
}

/// Applies and remembers the theme (System follows the device setting).
Future<void> setAppThemeMode(ThemeMode mode) async {
  themeNotifier.value = mode;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode == ThemeMode.dark ? 'dark' : (mode == ThemeMode.system ? 'system' : 'light'));
  } catch (_) {}
}

class MasterAdminApp extends StatelessWidget {
  const MasterAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'Master Administration',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(seedColor: kPurple, brightness: Brightness.light),
            // Merriweather for every text, including plain TextStyle()s
            fontFamily: GoogleFonts.merriweather().fontFamily,
            textTheme: GoogleFonts.merriweatherTextTheme(ThemeData.light().textTheme),
            scaffoldBackgroundColor: kLightBg,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(seedColor: kPurple, brightness: Brightness.dark),
            fontFamily: GoogleFonts.merriweather().fontFamily,
            textTheme: GoogleFonts.merriweatherTextTheme(ThemeData.dark().textTheme),
            scaffoldBackgroundColor: kDarkBg,
          ),
          themeMode: currentMode,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'US')],
          routes: {
            '/home': (context) => const _SessionGate(child: HomeScreen()),
            '/auth': (context) => const AuthScreen(),
          },
          // Keep text readable on every screen size: phone accessibility settings
          // can enlarge text up to 3x, which pushed labels out of cards.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            // Screens drawn with fixed colours follow this flag (core/app_palette.dart).
            final dark = currentMode == ThemeMode.dark ||
                (currentMode == ThemeMode.system && mq.platformBrightness == Brightness.dark);
            if (dark != AppPalette.isDark) {
              AppPalette.isDark = dark;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) AppPalette.rebuildAll(context);
              });
            }
            return MediaQuery(
              data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15)),
              child: _AppShell(child: child ?? const SizedBox.shrink()),
            );
          },
          home: const AuthWrapper(),
        );
      },
    );
  }
}

// ==========================================
// APP SHELL (inactivity listener + lock overlay)
// ==========================================
class _AppShell extends StatefulWidget {
  final Widget child;
  const _AppShell({required this.child});

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  DateTime _lastPing = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async => AppLockManager.instance.isLocked;

  void _ping() {
    final now = DateTime.now();
    if (now.difference(_lastPing) < const Duration(seconds: 1)) return;
    _lastPing = now;
    AppLockManager.instance.resetInactivityTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _ping(),
      onPointerMove: (_) => _ping(),
      child: AnimatedBuilder(
        animation: AppLockManager.instance,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (AppLockManager.instance.isLocked)
                Positioned.fill(
                  child: Overlay(
                    initialEntries: [
                      OverlayEntry(builder: (_) => const CinematicLockOverlay()),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SessionGate extends StatelessWidget {
  final Widget child;
  const _SessionGate({required this.child});

  @override
  Widget build(BuildContext context) {
    final hasSession = Supabase.instance.client.auth.currentSession != null;
    return hasSession ? child : const AuthScreen();
  }
}

// ==========================================
// SHARED BRAND HEADER (animated logo + title)
// ==========================================
class BrandHeader extends StatefulWidget {
  final bool compact;
  const BrandHeader({super.key, this.compact = false});

  @override
  State<BrandHeader> createState() => _BrandHeaderState();
}

class _BrandHeaderState extends State<BrandHeader> with TickerProviderStateMixin {
  late final AnimationController _zoomController;
  late final Animation<double> _scaleAnimation;
  late final AnimationController _flyController;
  late final Animation<Offset> _flyOffset;
  late final Animation<double> _flyOpacity;

  @override
  void initState() {
    super.initState();
    _zoomController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.06)
        .animate(CurvedAnimation(parent: _zoomController, curve: Curves.easeInOut));

    _flyController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _flyOffset = Tween<Offset>(begin: const Offset(0.0, 0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _flyController, curve: Curves.easeOutCubic));
    _flyOpacity = CurvedAnimation(parent: _flyController, curve: Curves.easeIn);
    _flyController.forward();
  }

  @override
  void dispose() {
    _zoomController.dispose();
    _flyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.compact;
    final double logo = c ? 130 : 140;
    final double titleSize = c ? 24 : 26;
    final double subSize = c ? 11 : 12;
    final double lineWidth = c ? 28 : 32;
    final double hPad = c ? 8 : 10;
    final double gap = c ? 24 : 28;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            width: logo,
            height: logo,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: kPurple.withValues(alpha: 0.45), blurRadius: 40, spreadRadius: 4),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(logo / 2),
              child: Image.asset(
                'assets/images/app_logo.png',
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) =>
                    Icon(Icons.admin_panel_settings_rounded, size: c ? 70 : 80, color: AppPalette.fg(kGold)),
              ),
            ),
          ),
        ),
        SizedBox(height: gap),
        SlideTransition(
          position: _flyOffset,
          child: FadeTransition(
            opacity: _flyOpacity,
            child: Column(
              children: [
                Text("MASTER",
                    style: GoogleFonts.merriweather(
                        fontSize: titleSize, fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.white), letterSpacing: 4.0)),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: lineWidth, height: 1.5, color: AppPalette.bg(kGold)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPad),
                      child: Text("ADMINISTRATION",
                          style: GoogleFonts.merriweather(
                              fontSize: subSize, fontWeight: FontWeight.bold, color: AppPalette.fg(kGold), letterSpacing: 3.0)),
                    ),
                    Container(width: lineWidth, height: 1.5, color: AppPalette.bg(kGold)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// CINEMATIC SPLASH GATEWAY
// ==========================================
class CinematicSplashGateway extends StatelessWidget {
  final String statusText;
  const CinematicSplashGateway({super.key, this.statusText = "Loading Master Administration..."});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(kDarkBg),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandHeader(),
            const SizedBox(height: 36),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: kGold, strokeWidth: 2),
            ),
            const SizedBox(height: 14),
            Text(statusText,
                style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white54), fontSize: 11, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// CINEMATIC LOCK SCREEN OVERLAY
// ==========================================
class CinematicLockOverlay extends StatefulWidget {
  const CinematicLockOverlay({super.key});

  @override
  State<CinematicLockOverlay> createState() => _CinematicLockOverlayState();
}

class _CinematicLockOverlayState extends State<CinematicLockOverlay> {
  static const int _maxAttempts = 5;
  static const Duration _lockout = Duration(seconds: 30);
  static const int _maxPinLength = 8;

  static int _failedAttempts = 0;
  static DateTime? _lockedUntil;

  final TextEditingController _pinController = TextEditingController();
  Timer? _ticker;
  bool _isWrongPin = false;

  bool get _isLockedOut => _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);
  int get _secondsLeft => _isLockedOut ? _lockedUntil!.difference(DateTime.now()).inSeconds + 1 : 0;

  @override
  void initState() {
    super.initState();
    if (_isLockedOut) _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (!_isLockedOut) {
        t.cancel();
        _failedAttempts = 0;
        _lockedUntil = null;
      }
      setState(() {});
    });
  }

  void _verifyPin() {
    if (_isLockedOut) return;

    final input = _pinController.text.trim();
    if (input.isEmpty) return;

    final ok = AppLockManager.instance.unlock(input);
    if (ok) {
      _failedAttempts = 0;
      _lockedUntil = null;
      return;
    }

    _failedAttempts++;
    _pinController.clear();

    if (_failedAttempts >= _maxAttempts) {
      _lockedUntil = DateTime.now().add(_lockout);
      _startTicker();
    }

    setState(() => _isWrongPin = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isWrongPin = false);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  String get _message {
    if (_isLockedOut) return "Too many attempts. Try again in ${_secondsLeft}s.";
    if (_isWrongPin) {
      final left = _maxAttempts - _failedAttempts;
      return "Incorrect PIN. $left ${left == 1 ? 'attempt' : 'attempts'} left.";
    }
    return "App Locked due to inactivity";
  }

  @override
  Widget build(BuildContext context) {
    final bool error = _isWrongPin || _isLockedOut;

    return Material(
      color: AppPalette.bg(kDarkBg),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandHeader(compact: true),
              const SizedBox(height: 30),
              Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppPalette.bg(Colors.white.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppPalette.line(error ? Colors.redAccent : kPurple.withValues(alpha: 0.3)), width: 1.2),
                ),
                child: Column(
                  children: [
                    Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.merriweather(
                          fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(error ? Colors.redAccent : Colors.white70)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pinController,
                      enabled: !_isLockedOut,
                      autofocus: true,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(_maxPinLength),
                      ],
                      style: GoogleFonts.merriweather(
                          fontSize: 20, color: AppPalette.fg(Colors.white), letterSpacing: 8, fontWeight: FontWeight.w900),
                      decoration: InputDecoration(
                        hintText: "••••",
                        hintStyle: TextStyle(color: AppPalette.fg(Colors.white24), letterSpacing: 6),
                        filled: true,
                        fillColor: AppPalette.bg(Colors.black26),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _verifyPin(),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: _isLockedOut ? null : _verifyPin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.bg(kPurple),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text("Unlock",
                            style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.white))),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// AUTH WRAPPER (STRICT GATEKEEPER)
// ==========================================
enum _LoadState { loading, error, ready }

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  final SupabaseClient _client = Supabase.instance.client;

  StreamSubscription<AuthState>? _authSub;
  RealtimeChannel? _profileChannel;

  Session? _session;
  Map<String, dynamic>? _profile;
  _LoadState _state = _LoadState.loading;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    profileRefreshNotifier.addListener(_onRefreshRequested);

    _session = _client.auth.currentSession;
    _authSub = _client.auth.onAuthStateChange.listen(_onAuthChange);
    RegistrationGuard.onRelease = _resyncAfterRegistration;

    final user = _session?.user;
    if (user != null) {
      _listenToProfile(user.id);
      _loadProfile(showSplash: false);
    } else {
      _state = _LoadState.ready;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    profileRefreshNotifier.removeListener(_onRefreshRequested);
    _authSub?.cancel();
    if (RegistrationGuard.onRelease == _resyncAfterRegistration) RegistrationGuard.onRelease = null;
    _disposeChannel();
    super.dispose();
  }

  void _onRefreshRequested() {
    if (_session != null) _loadProfile(showSplash: false);
  }

  void _onAuthChange(AuthState s) {
    if (!mounted) return;
    // Another account is being registered on this device: wait (see RegistrationGuard)
    if (RegistrationGuard.active) return;
    _applySession(s.session, s.event);
  }

  /// After a registration on this device: follow the session that is active now.
  void _resyncAfterRegistration() {
    if (!mounted) return;
    final current = _client.auth.currentSession;
    if (current?.user.id == _session?.user.id) {
      _session = current;
      return;
    }
    _applySession(current, AuthChangeEvent.signedIn);
  }

  void _applySession(Session? session, AuthChangeEvent event) {
    final newUser = session?.user;
    final prevId = _session?.user.id;
    _session = session;

    if (newUser == null) {
      _disposeChannel();
      setState(() {
        _profile = null;
        _state = _LoadState.ready;
      });
      return;
    }

    if (newUser.id != prevId) {
      _profile = null;
      _listenToProfile(newUser.id);
      _loadProfile(showSplash: true);
    } else if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.userUpdated) {
      _loadProfile(showSplash: false);
    }
  }

  Future<void> _loadProfile({bool showSplash = true}) async {
    final session = _session;
    if (session == null) {
      if (mounted) setState(() => _state = _LoadState.ready);
      return;
    }

    final token = ++_loadToken;
    if (showSplash && _profile == null && mounted) {
      setState(() => _state = _LoadState.loading);
    }

    try {
      debugPrint("🔍 AuthWrapper: Fetching profile for UID: ${session.user.id}");

      final res = await _client
          .from('profiles')
          .select()
          .eq('id', session.user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 6));

      debugPrint("📦 AuthWrapper: Profile retrieved: $res");

      if (!mounted || token != _loadToken) return;
      setState(() {
        _profile = res;
        _state = _LoadState.ready;
      });
    } catch (e, stack) {
      debugPrint("AuthWrapper fetch profile error: $e\n$stack");
      if (!mounted || token != _loadToken) return;
      setState(() => _state = _LoadState.ready);
    }
  }

  void _listenToProfile(String userId) {
    _disposeChannel();
    try {
      _profileChannel = _client
          .channel('profile-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'profiles',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: userId),
            callback: (_) => _loadProfile(showSplash: false),
          )
          .subscribe();
    } catch (e) {
      debugPrint("Realtime subscription note: $e");
    }
  }

  void _disposeChannel() {
    final ch = _profileChannel;
    _profileChannel = null;
    if (ch != null) {
      try {
        _client.removeChannel(ch);
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _session != null && !_isReadyForHome) {
      _loadProfile(showSplash: false);
    }
  }

  // SCJ ID is the master key: non-null, non-empty, and cannot be a dummy placeholder
  bool get _hasScjId {
    final raw = _profile?['scj_id'];
    if (raw == null) return false;
    final scjId = raw.toString().trim().toLowerCase();
    return scjId.isNotEmpty && scjId != 'null' && scjId != 'none' && scjId != 'undefined';
  }

  bool get _isApproved => _profile?['is_approved'] == true || _profile?['approval_status'] == 'approved';

  // Requires a valid SCJ ID AND approved status to open HomeScreen
  bool get _isReadyForHome => _profile != null && _hasScjId && _isApproved;

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const AuthScreen();

    switch (_state) {
      case _LoadState.loading:
        return const CinematicSplashGateway(statusText: "Loading jurisdiction profiles...");

      case _LoadState.error:
        return _ProfileErrorScreen(
          onRetry: () => _loadProfile(showSplash: true),
          onSignOut: () => _client.auth.signOut(),
        );

      case _LoadState.ready:
        // 1. Has valid SCJ ID key AND is approved -> HomeScreen
        if (_isReadyForHome) {
          return HomeScreen(key: ValueKey(_session?.user.id ?? 'active_user'));
        }

        // 2. Has valid SCJ ID key, but awaiting admin approval or rejected -> Pending Screen
        if (_profile != null && _hasScjId && !_isApproved) {
          return _AccountPendingScreen(
            approvalStatus: _profile?['approval_status']?.toString() ?? 'pending',
            rejectionReason: _profile?['rejection_reason']?.toString(),
            onRefresh: () => _loadProfile(showSplash: true),
            onSignOut: () => _client.auth.signOut(),
          );
        }

        // 3. Authenticated (e.g. Google), but NO SCJ ID key yet:
        // MUST show AuthScreen so they complete SCJ ID verification before anything else!
        return const AuthScreen();
    }
  }
}

// ==========================================
// CINEMATIC ACCOUNT PENDING SCREEN
// ==========================================
class _AccountPendingScreen extends StatelessWidget {
  final String approvalStatus;
  final String? rejectionReason;
  final VoidCallback onRefresh;
  final VoidCallback onSignOut;

  const _AccountPendingScreen({
    required this.approvalStatus,
    this.rejectionReason,
    required this.onRefresh,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final bool isRejected = approvalStatus == 'rejected';

    return Scaffold(
      backgroundColor: AppPalette.bg(kDarkBg),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandHeader(compact: true),
              const SizedBox(height: 28),
              Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppPalette.bg(Colors.white.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppPalette.line(isRejected ? Colors.redAccent.withValues(alpha: 0.5) : kGold.withValues(alpha: 0.35)),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      isRejected ? Icons.error_outline_rounded : Icons.hourglass_top_rounded,
                      size: 44,
                      color: AppPalette.fg(isRejected ? Colors.redAccent : kGold),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      isRejected ? "Registration Not Approved" : "Account Under Review",
                      style: GoogleFonts.merriweather(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.fg(Colors.white),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isRejected
                          ? (rejectionReason?.isNotEmpty == true
                              ? "Reason: $rejectionReason"
                              : "Your registration was not approved. Please contact your administrator.")
                          : "Your account is currently awaiting administrative approval.",
                      style: GoogleFonts.merriweather(
                        fontSize: 12,
                        color: AppPalette.fg(Colors.white70),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton.icon(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text("Check Approval Status"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.bg(kPurple),
                          foregroundColor: AppPalette.fg(Colors.white),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: onSignOut,
                      child: Text("Sign Out", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white54), fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// PROFILE ERROR SCREEN
// ==========================================
class _ProfileErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onSignOut;
  const _ProfileErrorScreen({required this.onRetry, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(kDarkBg),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 56, color: AppPalette.fg(kGold)),
              const SizedBox(height: 20),
              Text("Couldn't load your profile",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.white))),
              const SizedBox(height: 8),
              Text("Check your connection and try again.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.white54))),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.bg(kPurple),
                  foregroundColor: AppPalette.fg(Colors.white),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text("Retry"),
              ),
              TextButton(
                onPressed: onSignOut,
                child: Text("Sign out", style: TextStyle(color: AppPalette.fg(Colors.white54))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}