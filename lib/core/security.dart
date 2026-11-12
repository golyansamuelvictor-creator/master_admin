import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'i18n.dart';
import 'offline.dart';
import 'security_stub.dart' if (dart.library.js_interop) 'security_web.dart';

/// Data protection:
/// · Downloading, printing and sharing files out of the app is for the roles
///   with the action "Download & Print" (church-level secretaries and the
///   administrators; edit the list in role settings).
/// · Every screen carries a faint watermark with the user's SCJ ID and the
///   date, so a photo or screenshot of the screen shows who it came from.
///   Exported files carry it too.
/// · On the web: no right-click menu, no Ctrl+P / Ctrl+S, the browser's own
///   print gives a blank page, and the screen blurs while the app is not in
///   front (most snipping tools take the focus).
class AppSecurity {
  AppSecurity._();

  static const action = 'Download & Print';
  static bool? _canExport;
  static String? _forUser;
  static String _scjId = '';
  static String? _name;

  /// The SCJ ID and date shown in the watermark ('' before sign-in).
  static final ValueNotifier<String> watermark = ValueNotifier('');

  /// After sign-in (Home): loads the permission and the watermark text.
  static Future<void> start() async {
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    if (uid == null) return;
    if (_forUser != uid) {
      _forUser = uid;
      _canExport = null;
    }
    try {
      final p = await db.from('profiles').select('scj_id, full_name').eq('id', uid).maybeSingle();
      _scjId = (p?['scj_id'] ?? '').toString().trim();
      _name = (p?['full_name'] ?? '').toString().trim();
    } catch (_) {}
    _refreshMark();
    await canExport();
    installWebGuards();
  }

  static void stop() {
    _forUser = null;
    _canExport = null;
    _scjId = '';
    watermark.value = '';
  }

  static void _refreshMark() {
    if (_scjId.isEmpty && (_name ?? '').isEmpty) return;
    watermark.value = "${_scjId.isNotEmpty ? _scjId : _name} · ${DateFormat('d MMM yyyy').format(DateTime.now())}";
  }

  /// For files: "SCJ ID · date time".
  static String get exportStamp =>
      "${_scjId.isNotEmpty ? _scjId : (_name ?? '')} · ${DateFormat('d MMM yyyy, HH:mm').format(DateTime.now())}".trim();

  static Future<bool> canExport() async {
    if (_canExport != null) return _canExport!;
    try {
      _canExport = (await Supabase.instance.client.rpc('has_admin_action', params: {'p_action': action})) == true;
    } catch (_) {
      _canExport = false;
    }
    return _canExport!;
  }

  /// Before any download, print or "share to other apps": false (and a
  /// message) for everyone else.
  static Future<bool> checkExport(BuildContext context) async {
    if (await canExport()) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("For data protection, downloading and printing are limited to the church secretaries. Ask them if you need a copy."),
        duration: Duration(seconds: 5),
      ));
    }
    return false;
  }
}

/// The faint, repeated SCJ ID + date over every screen (it never catches
/// taps). Wrap the app's pages with it (MaterialApp.builder).
class SecurityWatermark extends StatelessWidget {
  final Widget child;
  const SecurityWatermark({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      const Positioned(left: 12, bottom: 12, child: OutboxBadge()), // reports waiting to be sent
      Positioned.fill(
        child: IgnorePointer(
          child: ValueListenableBuilder<String>(
            valueListenable: AppSecurity.watermark,
            builder: (context, text, child) => text.isEmpty
                ? const SizedBox.shrink()
                : RepaintBoundary(child: CustomPaint(painter: _MarkPainter(text, Theme.of(context).brightness == Brightness.dark))),
          ),
        ),
      ),
    ]);
  }
}

class _MarkPainter extends CustomPainter {
  final String text;
  final bool dark;
  _MarkPainter(this.text, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.055)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const gapX = 90.0, gapY = 110.0;
    canvas.save();
    canvas.rotate(-math.pi / 8);
    final w = tp.width + gapX;
    // cover the rotated screen
    for (double y = -size.width * 0.5; y < size.height * 1.4; y += gapY) {
      final shift = ((y / gapY).round().isEven) ? 0.0 : w / 2;
      for (double x = -size.height * 0.6 - shift; x < size.width * 1.4; x += w) {
        tp.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.text != text || old.dark != dark;
}
