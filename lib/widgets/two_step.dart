import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_palette.dart';

const Color _kPurple = Color(0xFF4A148C);

/// Two-step verification with an authenticator app (Google Authenticator,
/// Microsoft Authenticator, Authy ...), using Supabase Auth MFA (TOTP).
/// After turning it on, signing in asks for the 6-digit code from the app.
class TwoStep {
  TwoStep._();
  static GoTrueMFAApi get _mfa => Supabase.instance.client.auth.mfa;

  /// Signed in with the password but the account needs the code too.
  static bool get codeNeeded {
    try {
      final a = _mfa.getAuthenticatorAssuranceLevel();
      return a.nextLevel == AuthenticatorAssuranceLevels.aal2 && a.currentLevel != AuthenticatorAssuranceLevels.aal2;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Factor>> verifiedFactors() async {
    final r = await _mfa.listFactors();
    return r.totp.where((f) => f.status == FactorStatus.verified).toList();
  }
}

/// Settings › Privacy & Security › Two-step verification.
class TwoStepSettingsPanel extends StatefulWidget {
  const TwoStepSettingsPanel({super.key});
  @override
  State<TwoStepSettingsPanel> createState() => _TwoStepSettingsPanelState();
}

class _TwoStepSettingsPanelState extends State<TwoStepSettingsPanel> {
  final _mfa = Supabase.instance.client.auth.mfa;
  List<Factor> _factors = [];
  bool _loading = true;
  String? _error;

  // enrolment in progress
  String? _factorId;
  String? _secret;
  String? _uri;
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await TwoStep.verifiedFactors();
      if (mounted) {
        setState(() {
          _factors = f;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Two-step verification isn't available: ${e is AuthException ? e.message : e}";
        });
      }
    }
  }

  void _snack(String m, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null, behavior: SnackBarBehavior.floating));

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      // remove an unfinished earlier attempt
      final all = await _mfa.listFactors();
      for (final f in all.totp.where((f) => f.status != FactorStatus.verified)) {
        await _mfa.unenroll(f.id);
      }
      final r = await _mfa.enroll(factorType: FactorType.totp, issuer: 'Master Admin', friendlyName: 'Authenticator ${DateTime.now().millisecondsSinceEpoch % 10000}');
      setState(() {
        _factorId = r.id;
        _secret = r.totp?.secret;
        _uri = r.totp?.uri;
      });
    } catch (e) {
      _snack("Couldn't start: ${e is AuthException ? e.message : e}", error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final id = _factorId;
    if (id == null || _code.text.trim().length != 6) return;
    setState(() => _busy = true);
    try {
      final ch = await _mfa.challenge(factorId: id);
      await _mfa.verify(factorId: id, challengeId: ch.id, code: _code.text.trim());
      _snack("Two-step verification is on");
      setState(() {
        _factorId = null;
        _secret = null;
        _uri = null;
        _code.clear();
      });
      _load();
    } catch (e) {
      _snack("That code didn't work. Check the time on your phone and try again.", error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOff(Factor f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Turn off two-step verification?"),
        content: const Text("Signing in will only need your password again."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Turn off", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _mfa.unenroll(f.id);
      _snack("Two-step verification is off");
      _load();
    } catch (e) {
      _snack("Couldn't turn it off: ${e is AuthException ? e.message : e}", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    if (_error != null) return Padding(padding: const EdgeInsets.all(16), child: Text(_error!));
    final on = _factors.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(on ? Icons.verified_user_rounded : Icons.shield_outlined, color: AppPalette.fg(on ? Colors.green.shade700 : _kPurple), size: 30),
          title: Text(on ? "On" : "Off", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900)),
          subtitle: Text(on
              ? "Signing in asks for a 6-digit code from your authenticator app."
              : "Add a second step: after your password, a 6-digit code from an authenticator app on your phone."),
        ),
        if (on)
          for (final f in _factors)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phonelink_lock_rounded),
              title: Text(f.friendlyName ?? 'Authenticator app'),
              trailing: TextButton(onPressed: () => _turnOff(f), child: Text("Turn off", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
            )
        else if (_factorId == null)
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_kPurple), foregroundColor: Colors.white),
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text("Set up"),
            ),
          )
        else ...[
          const Text("1. Open your authenticator app and scan this code (or tap the link on this phone, or type the key)."),
          const SizedBox(height: 10),
          if (_uri != null)
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(10),
                child: QrImageView(data: _uri!, size: 190, backgroundColor: Colors.white),
              ),
            ),
          const SizedBox(height: 8),
          if (_secret != null)
            Row(children: [
              Expanded(child: SelectableText(_secret!, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1.2))),
              IconButton(
                tooltip: tr("Copy key"),
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _secret!));
                  _snack("Key copied");
                },
              ),
              if (_uri != null)
                IconButton(tooltip: tr("Open in authenticator app"), icon: const Icon(Icons.open_in_new_rounded, size: 18), onPressed: () => launchUrl(Uri.parse(_uri!))),
            ]),
          const SizedBox(height: 12),
          const Text("2. Enter the 6-digit code the app shows."),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(isDense: true, counterText: '', border: OutlineInputBorder(), hintText: "123456"),
                onSubmitted: (_) => _confirm(),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(onPressed: _busy ? null : _confirm, child: const Text("Turn on")),
          ]),
        ],
      ]),
    );
  }
}

/// Shown after the password when two-step verification is on.
class TwoStepCodeScreen extends StatefulWidget {
  final VoidCallback onVerified;
  const TwoStepCodeScreen({super.key, required this.onVerified});
  @override
  State<TwoStepCodeScreen> createState() => _TwoStepCodeScreenState();
}

class _TwoStepCodeScreenState extends State<TwoStepCodeScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final factors = await TwoStep.verifiedFactors();
      if (factors.isEmpty) {
        widget.onVerified();
        return;
      }
      final mfa = Supabase.instance.client.auth.mfa;
      final ch = await mfa.challenge(factorId: factors.first.id);
      await mfa.verify(factorId: factors.first.id, challengeId: ch.id, code: code);
      widget.onVerified();
    } catch (e) {
      setState(() => _error = "Wrong code. Check your authenticator app and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFF0F071A)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.phonelink_lock_rounded, size: 52, color: AppPalette.fg(const Color(0xFFD1B3FF))),
              const SizedBox(height: 14),
              Text("Two-step verification", style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              Text("Enter the 6-digit code from your authenticator app.", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.white70))),
              const SizedBox(height: 18),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.w900),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _verify(),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _kPurple, foregroundColor: Colors.white),
                  onPressed: _busy ? null : _verify,
                  child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Verify"),
                ),
              ),
              TextButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: Text("Sign out", style: TextStyle(color: AppPalette.fg(Colors.white54))),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
