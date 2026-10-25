// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_lock_manager.dart';
import 'package:master_admin/core/app_palette.dart';

class CinematicLockScreen extends StatefulWidget {
  final VoidCallback? onUnlocked;

  const CinematicLockScreen({super.key, this.onUnlocked});

  @override
  State<CinematicLockScreen> createState() => _CinematicLockScreenState();
}

class _CinematicLockScreenState extends State<CinematicLockScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  late AnimationController _textFlyController;
  late Animation<Offset> _textSlideAnimation;
  late Animation<double> _textFadeAnimation;

  final TextEditingController _pinController = TextEditingController();
  bool _showPinPrompt = false;
  bool _isWrongPin = false;

  final Color pPurple = const Color(0xFF4A148C);
  final Color pGold = const Color(0xFFB78103);

  @override
  void initState() {
    super.initState();

    // 1. Logo Zoom-in & Zoom-out Breathing Animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 2. Typography Fly-In Animation
    _textFlyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _textSlideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.45),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textFlyController, curve: Curves.easeOutCubic));

    _textFadeAnimation = CurvedAnimation(parent: _textFlyController, curve: Curves.easeIn);

    // Start text entrance animation
    _textFlyController.forward();
  }

  void _onScreenTapped() {
    if (!_showPinPrompt) {
      setState(() => _showPinPrompt = true);
    }
  }

  void _verifyPin() {
    final input = _pinController.text.trim();
    final success = AppLockManager.instance.unlock(input);

    if (success) {
      _textFlyController.reverse(); // Words fly out smoothly
      widget.onUnlocked?.call();
    } else {
      setState(() => _isWrongPin = true);
      _pinController.clear();
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isWrongPin = false);
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textFlyController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFF0F071A)), // Deep royal obsidian
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onScreenTapped,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background Radial Glow
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.85,
                    colors: [
                      AppPalette.solid(pPurple.withValues(alpha: 0.35)),
                      AppPalette.solid(const Color(0xFF0B0414)),
                    ],
                  ),
                ),
              ),
            ),

            Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. ZOOMING & BREATHING LOGO
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: pPurple.withValues(alpha: 0.45),
                                blurRadius: 40,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(70),
                            child: Image.asset(
                              'assets/images/app_logo.png',
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => Icon(
                                Icons.admin_panel_settings_rounded,
                                size: 80,
                                color: AppPalette.fg(pGold),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // 2. FLY-IN TYPOGRAPHY
                      SlideTransition(
                        position: _textSlideAnimation,
                        child: FadeTransition(
                          opacity: _textFadeAnimation,
                          child: Column(
                            children: [
                              Text(
                                "MASTER",
                                style: GoogleFonts.merriweather(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: AppPalette.fg(Colors.white),
                                  letterSpacing: 4.0,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(width: 32, height: 1.5, color: AppPalette.bg(pGold)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    child: Text(
                                      "ADMINISTRATION",
                                      style: GoogleFonts.merriweather(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppPalette.fg(pGold),
                                        letterSpacing: 3.0,
                                      ),
                                    ),
                                  ),
                                  Container(width: 32, height: 1.5, color: AppPalette.bg(pGold)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),

                      // 3. PASSWORD / PIN PROMPT
                      if (!_showPinPrompt) ...[
                        Text(
                          "App Locked • Tap anywhere to enter PIN",
                          style: GoogleFonts.merriweather(
                            fontSize: 12,
                            color: AppPalette.fg(Colors.white54),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ] else ...[
                        Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: AppPalette.bg(Colors.white.withValues(alpha: 0.06)),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppPalette.line(_isWrongPin ? Colors.redAccent : pPurple.withValues(alpha: 0.35)),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                _isWrongPin ? "Incorrect PIN. Try again." : "Enter Lock PIN",
                                style: GoogleFonts.merriweather(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppPalette.fg(_isWrongPin ? Colors.redAccent : Colors.white70),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _pinController,
                                autofocus: true,
                                obscureText: true,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                style: GoogleFonts.merriweather(
                                  fontSize: 22,
                                  color: AppPalette.fg(Colors.white),
                                  letterSpacing: 8,
                                  fontWeight: FontWeight.w900,
                                ),
                                decoration: InputDecoration(
                                  hintText: "••••",
                                  hintStyle: TextStyle(color: AppPalette.fg(Colors.white24), letterSpacing: 6),
                                  filled: true,
                                  fillColor: AppPalette.bg(Colors.black26),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                ),
                                onSubmitted: (_) => _verifyPin(),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 42,
                                child: ElevatedButton(
                                  onPressed: _verifyPin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppPalette.bg(pPurple),
                                    foregroundColor: AppPalette.fg(Colors.white),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: Text(
                                    "Unlock App",
                                    style: GoogleFonts.merriweather(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}