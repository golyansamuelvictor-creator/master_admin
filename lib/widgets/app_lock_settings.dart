import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_palette.dart';
import '../services/app_lock_manager.dart';

const Color _kPurple = Color(0xFF4A148C);

/// Create or change the app PIN (4–8 digits). Returns true when saved.
/// When the user already has a PIN, the current one is asked first.
Future<bool> showPinSetupDialog(BuildContext context, {bool intro = false}) async {
  final lock = AppLockManager.instance;
  final cur = TextEditingController(), pin = TextEditingController(), again = TextEditingController();
  String? error;
  bool saving = false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: !intro,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      InputDecoration deco(String label) => InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder(), counterText: '');
      Widget field(TextEditingController c, String label, {bool focus = false}) => TextField(
            controller: c,
            autofocus: focus,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: deco(label),
          );
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          Icon(Icons.lock_outline_rounded, color: AppPalette.fg(_kPurple)),
          const SizedBox(width: 10),
          Expanded(child: Text(lock.hasPin ? "Change your PIN" : "Create your app PIN", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17))),
        ]),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              intro
                  ? "For safety the app locks after ${AppLockManager.timeoutOptions[lock.timeoutSeconds] ?? '5 minutes'} without activity. Choose a 4–8 digit PIN to unlock it quickly. Without a PIN you unlock with your password."
                  : "Use 4–8 digits. The PIN works on every device you sign in on.",
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppPalette.fg(Colors.grey.shade800)),
            ),
            const SizedBox(height: 14),
            if (lock.hasPin) ...[field(cur, "Current PIN", focus: true), const SizedBox(height: 10)],
            field(pin, "New PIN", focus: !lock.hasPin),
            const SizedBox(height: 10),
            field(again, "Repeat new PIN"),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: TextStyle(color: AppPalette.fg(Colors.red.shade700), fontSize: 12.5))),
          ]),
        ),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: Text(intro ? "Later" : "Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_kPurple), foregroundColor: Colors.white),
            onPressed: saving
                ? null
                : () async {
                    if (lock.hasPin && !lock.checkPin(cur.text)) {
                      setD(() => error = "The current PIN is wrong.");
                      return;
                    }
                    if (pin.text.length < 4) {
                      setD(() => error = "Use at least 4 digits.");
                      return;
                    }
                    if (pin.text != again.text) {
                      setD(() => error = "The two PINs don't match.");
                      return;
                    }
                    if (RegExp(r'^(\d)\1+$').hasMatch(pin.text) || '0123456789'.contains(pin.text) || '9876543210'.contains(pin.text)) {
                      {
                      setD(() => error = "That PIN is too easy to guess. Try another.");
                      return;
                    }
                    }
                    setD(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await lock.setPin(pin.text);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (_) {
                      // Saved on this device; the account copy failed.
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    }
                  },
            child: Text(saving ? "Saving…" : "Save PIN"),
          ),
        ],
      );
    }),
  );
  return ok == true;
}

/// Settings › Privacy & Security › App Lock.
class AppLockSettingsPanel extends StatefulWidget {
  const AppLockSettingsPanel({super.key});
  @override
  State<AppLockSettingsPanel> createState() => _AppLockSettingsPanelState();
}

class _AppLockSettingsPanelState extends State<AppLockSettingsPanel> {
  final lock = AppLockManager.instance;

  @override
  void initState() {
    super.initState();
    lock.addListener(_changed);
  }

  @override
  void dispose() {
    lock.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SwitchListTile(
        secondary: Icon(Icons.lock_clock_outlined, color: AppPalette.fg(_kPurple)),
        title: const Text("Lock when inactive", style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text("The app locks itself when you stop using it"),
        value: lock.isLockEnabled,
        activeThumbColor: _kPurple,
        onChanged: (v) async {
          if (!v && lock.hasPin) {
            final ok = await _confirmPin();
            if (!ok) return;
          }
          await lock.updateSettings(enabled: v);
        },
      ),
      const Divider(height: 1),
      ListTile(
        enabled: lock.isLockEnabled,
        leading: Icon(Icons.timer_outlined, color: AppPalette.fg(_kPurple)),
        title: const Text("Lock after", style: TextStyle(fontWeight: FontWeight.bold)),
        trailing: DropdownButton<int>(
          value: lock.timeoutSeconds,
          underline: const SizedBox.shrink(),
          items: [for (final e in AppLockManager.timeoutOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: lock.isLockEnabled ? (v) => lock.updateSettings(timeout: v) : null,
        ),
      ),
      const Divider(height: 1),
      ListTile(
        leading: Icon(Icons.pin_outlined, color: AppPalette.fg(_kPurple)),
        title: Text(lock.hasPin ? "Change PIN" : "Create PIN", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(lock.hasPin ? "Your PIN is set" : "No PIN yet: you unlock with your password"),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          if (await showPinSetupDialog(context)) _snack("PIN saved");
        },
      ),
      if (lock.hasPin) ...[
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.no_encryption_gmailerrorred_outlined, color: AppPalette.fg(Colors.red.shade700)),
          title: Text("Remove PIN", style: TextStyle(fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.red.shade700))),
          subtitle: const Text("You will unlock with your password"),
          onTap: () async {
            if (!await _confirmPin()) return;
            await lock.removePin();
            _snack("PIN removed");
          },
        ),
      ],
      const Divider(height: 1),
      ListTile(
        leading: Icon(Icons.lock_rounded, color: AppPalette.fg(_kPurple)),
        title: const Text("Lock now", style: TextStyle(fontWeight: FontWeight.bold)),
        enabled: lock.isLockEnabled,
        onTap: lock.isLockEnabled ? lock.lockScreen : null,
      ),
    ]);
  }

  Future<bool> _confirmPin() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Enter your PIN"),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => Navigator.pop(ctx, lock.checkPin(c.text)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, lock.checkPin(c.text)), child: const Text("OK")),
        ],
      ),
    );
    if (ok != true && mounted) _snack("Wrong PIN");
    return ok == true;
  }
}
