import 'package:material_ui/material_ui.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_palette.dart';
import 'i18n.dart';

const Color _kPurple = Color(0xFF4A148C);

/// "Forgot password?": the reset email, the link it holds, and the page to
/// choose a new password.
///
/// The email's link is `https://masteradministration.com/?token_hash=…&type=recovery`
/// (Supabase › Authentication › Emails › Reset password, see the guide). It
/// works on any phone or computer, not only the one that asked for it.
class PasswordReset {
  PasswordReset._();

  /// A reset link was opened: show "Choose a new password".
  static final ValueNotifier<bool> pending = ValueNotifier(false);
  static String? linkError;

  /// Before anything else at start-up: a reset link in the address bar signs
  /// the person in for the reset.
  static Future<void> handleLinkAtStartup() async {
    final q = Uri.base.queryParameters;
    final hash = q['token_hash'];
    if (hash != null && hash.isNotEmpty && q['type'] == 'recovery') {
      try {
        await Supabase.instance.client.auth.verifyOTP(tokenHash: hash, type: OtpType.recovery);
        pending.value = true;
      } catch (e) {
        linkError = "This reset link has expired or was already used. Ask for a new one.";
        debugPrint("Password reset link: $e");
      }
    }
    // a link of the older kind (?code=…) arrives as this event
    Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery) pending.value = true;
    });
  }

  /// Sign-in screen: ask for the email and send the reset link.
  static Future<void> ask(BuildContext context, {String email = ''}) async {
    final ctrl = TextEditingController(text: email);
    String? msg;
    bool sending = false, sent = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> send() async {
          final e = ctrl.text.trim();
          if (!e.contains('@')) {
            set(() => msg = "Enter the email address of your account.");
            return;
          }
          set(() {
            sending = true;
            msg = null;
          });
          try {
            await Supabase.instance.client.auth.resetPasswordForEmail(e, redirectTo: Uri.base.origin);
            set(() => sent = true);
          } on AuthException catch (err) {
            set(() => msg = err.statusCode == '429' ? "Too many requests. Please wait a few minutes and try again." : err.message);
          } catch (_) {
            set(() => msg = "Couldn't send. Check your connection and try again.");
          } finally {
            set(() => sending = false);
          }
        }

        return AlertDialog(
          title: Text("Reset your password", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
          content: SizedBox(
            width: 380,
            child: sent
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.mark_email_read_rounded, size: 48, color: AppPalette.fg(Colors.green.shade700)),
                    const SizedBox(height: 10),
                    Text.rich(
                      TextSpan(text: "${tr('If an account uses')} ${ctrl.text.trim()}, ${tr('a reset link is on its way. Open the email and tap “Reset my password”. Also look in Spam / Promotions. The link works for 1 hour.')}"),
                      textAlign: TextAlign.center,
                    ),
                  ])
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text("Enter your account's email. We'll send you a link to choose a new password."),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.emailAddress,
                      autofocus: true,
                      decoration: InputDecoration(labelText: tr("Email"), prefixIcon: const Icon(Icons.email_outlined), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
                      onSubmitted: (_) => sending ? null : send(),
                    ),
                    if (msg != null) ...[
                      const SizedBox(height: 8),
                      Text.rich(TextSpan(text: msg), style: TextStyle(color: AppPalette.fg(Colors.red.shade700), fontSize: 12.5)),
                    ],
                    const SizedBox(height: 8),
                    Text("Signed up with WhatsApp or Google only? Ask your secretary or the administrator to reset it.",
                        style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade600))),
                  ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(sent ? "Close" : "Cancel")),
            if (!sent)
              FilledButton(
                onPressed: sending ? null : send,
                child: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Send reset link"),
              ),
          ],
        );
      }),
    );
  }
}

/// After opening the reset link: choose the new password.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});
  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool _show = false, _saving = false;
  String? _msg;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p = _a.text;
    if (p.length < 8) return setState(() => _msg = "Use at least 8 characters.");
    if (p != _b.text) return setState(() => _msg = "The two passwords are not the same.");
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: p));
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text("Your password was changed.")));
      PasswordReset.pending.value = false;
    } on AuthException catch (e) {
      setState(() => _msg = e.message);
    } catch (_) {
      setState(() => _msg = "Couldn't save. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    InputDecoration deco(String l) => InputDecoration(
          labelText: tr(l),
          border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show)),
        );
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F2FA)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.key_rounded, size: 46, color: AppPalette.fg(_kPurple)),
                  const SizedBox(height: 8),
                  Text("Choose a new password", textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 19, fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text.rich(TextSpan(text: email), style: TextStyle(color: AppPalette.fg(Colors.grey.shade700))),
                  ],
                  const SizedBox(height: 18),
                  TextField(controller: _a, obscureText: !_show, decoration: deco("New password")),
                  const SizedBox(height: 12),
                  TextField(controller: _b, obscureText: !_show, decoration: deco("Type it again"), onSubmitted: (_) => _saving ? null : _save()),
                  if (_msg != null) ...[
                    const SizedBox(height: 10),
                    Text.rich(TextSpan(text: _msg), style: TextStyle(color: AppPalette.fg(Colors.red.shade700))),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _kPurple, padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text("Save new password"),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      PasswordReset.pending.value = false;
                      await Supabase.instance.client.auth.signOut();
                    },
                    child: const Text("Cancel and sign out"),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
