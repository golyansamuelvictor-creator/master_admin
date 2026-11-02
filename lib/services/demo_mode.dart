import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// ICT demo: the same app connected to a separate DEMO Supabase project that
/// holds only generated people and reports (see demo/DEMO_SETUP.md). The demo
/// accounts are administrators there, so the ICT team can show every screen
/// without touching the church's real data. The live project only stores the
/// demo project's address (app_config › demo_backend: {url, anon_key}).
class DemoMode {
  DemoMode._();

  static const _kOn = 'demo_mode_on', _kUrl = 'demo_mode_url', _kKey = 'demo_mode_key';

  /// True while the app is connected to the demo project.
  static bool active = false;

  /// Bumped to rebuild the whole app after switching (not on the web, where
  /// the page reloads).
  static final ValueNotifier<int> restart = ValueNotifier(0);

  /// Where to connect at start-up: the demo project when demo mode is on.
  static Future<(String, String)?> savedBackend() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(_kOn) != true) return null;
      final url = p.getString(_kUrl) ?? '', key = p.getString(_kKey) ?? '';
      if (url.isEmpty || key.isEmpty) return null;
      return (url, key);
    } catch (_) {
      return null;
    }
  }

  /// The demo project's address from the live project (null = no demo set up).
  static Future<(String, String)?> liveConfig() async {
    try {
      final r = await Supabase.instance.client.from('app_config').select('config_value').eq('config_key', 'demo_backend').maybeSingle();
      final v = r?['config_value'];
      if (v is Map && (v['url'] ?? '').toString().isNotEmpty && (v['anon_key'] ?? '').toString().isNotEmpty) {
        return (v['url'].toString(), v['anon_key'].toString());
      }
    } catch (_) {}
    return null;
  }

  static Future<void> enter(String url, String key, {required String liveUrl, required String liveKey}) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOn, true);
    await p.setString(_kUrl, url);
    await p.setString(_kKey, key);
    await _switch(url, key);
  }

  static Future<void> exit({required String liveUrl, required String liveKey}) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOn, false);
    await _switch(liveUrl, liveKey);
  }

  static Future<void> _switch(String url, String key) async {
    if (kIsWeb) {
      // a fresh start of the page connects to the right project
      await launchUrl(Uri.base.replace(queryParameters: const {}), webOnlyWindowName: '_self');
      return;
    }
    try {
      await Supabase.instance.dispose();
    } catch (_) {}
    await Supabase.initialize(url: url, publishableKey: key);
    active = (await savedBackend()) != null;
    restart.value++;
  }
}

/// The red band shown on every screen in demo mode.
class DemoBanner extends StatelessWidget {
  final VoidCallback onExit;
  const DemoBanner({super.key, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFC62828),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 26,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.science_rounded, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            const Flexible(
              child: Text("DEMO · generated data only, not the church's records",
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: onExit,
              style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 24)),
              child: const Text("Exit demo", style: TextStyle(fontSize: 11.5, decoration: TextDecoration.underline, decorationColor: Colors.white)),
            ),
          ]),
        ),
      ),
    );
  }
}