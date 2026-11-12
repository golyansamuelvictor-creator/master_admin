import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'i18n.dart';

/// Small JSON store on the phone / in the browser (survives closing the app).
class LocalStore {
  LocalStore._();
  static SharedPreferences? _p;
  static Future<SharedPreferences> get _prefs async => _p ??= await SharedPreferences.getInstance();

  static Future<void> put(String key, Object? value) async {
    try {
      final p = await _prefs;
      if (value == null) {
        await p.remove(key);
      } else {
        await p.setString(key, jsonEncode(value));
      }
    } catch (e) {
      debugPrint('LocalStore.put $key: $e'); // full storage: the app keeps working online
    }
  }

  static Future<dynamic> get(String key) async {
    try {
      final s = (await _prefs).getString(key);
      return s == null ? null : jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String key) async {
    try {
      await (await _prefs).remove(key);
    } catch (_) {}
  }
}

/// Is [e] a connection problem (offline, slow, dropped) rather than the
/// database refusing the data?
bool isNetworkError(Object e) {
  if (e is TimeoutException) return true;
  if (e is PostgrestException) {
    final c = (e.code ?? '').toString();
    // PostgREST codes (PGRST…, 23505 …) mean the server answered
    return c.isEmpty && _netText(e.message);
  }
  return _netText(e.toString());
}

bool _netText(String s) {
  final t = s.toLowerCase();
  return t.contains('failed to fetch') ||
      t.contains('xmlhttprequest') ||
      t.contains('socketexception') ||
      t.contains('clientexception') ||
      t.contains('connection') ||
      t.contains('network') ||
      t.contains('timed out') ||
      t.contains('timeout') ||
      t.contains('handshake') ||
      t.contains('host lookup');
}

/// Reports saved while the connection is down wait here (on the phone) and
/// are sent by themselves when it comes back: every 30 seconds, when the app
/// opens, and after any successful save. Each report belongs to the person
/// who saved it; another account on the same phone never sends it.
class Outbox {
  Outbox._();
  static const _key = 'outbox_v1';

  /// Reports of the signed-in user still waiting to be sent.
  static final ValueNotifier<int> pending = ValueNotifier(0);
  static Timer? _timer;
  static bool _flushing = false;

  static String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  static Future<List<Map<String, dynamic>>> _all() async {
    final v = await LocalStore.get(_key);
    if (v is! List) return [];
    return [for (final x in v) Map<String, dynamic>.from(x as Map)];
  }

  static Future<void> _write(List<Map<String, dynamic>> jobs) async {
    await LocalStore.put(_key, jobs);
    final uid = _uid;
    pending.value = jobs.where((j) => j['user'] == uid).length; // refused ones too: shown so they can be fixed or discarded
  }

  /// After sign-in.
  static Future<void> start() async {
    await _write(await _all());
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (pending.value > 0) flush();
    });
    unawaited(flush());
  }

  static Future<void> _send(Map<String, dynamic> j) async {
    final rows = List<Map<String, dynamic>>.from((j['rows'] as List).map((r) => Map<String, dynamic>.from(r as Map)));
    final q = Supabase.instance.client.from(j['table'] as String);
    final oc = j['onConflict'] as String?;
    final dn = j['defaultToNull'] != false;
    await (oc == null ? q.upsert(rows, defaultToNull: dn) : q.upsert(rows, onConflict: oc, defaultToNull: dn)).timeout(const Duration(seconds: 30));
  }

  /// Saves [rows] in [table] now, or keeps them on the phone when the
  /// connection is down. Returns true if sent, false if kept for later.
  /// Throws if the database refused them (wrong data, no permission).
  /// [draftKey]: the form's unsaved-entries copy, removed once sent.
  static Future<bool> submit({
    required String table,
    required List<Map<String, dynamic>> rows,
    String? onConflict,
    bool defaultToNull = true,
    required String label,
    String? draftKey,
  }) async {
    final job = <String, dynamic>{
      'id': '${DateTime.now().microsecondsSinceEpoch}',
      'user': _uid,
      'table': table,
      'rows': rows,
      'onConflict': onConflict,
      'defaultToNull': defaultToNull,
      'label': label,
      'draftKey': draftKey,
      'at': DateTime.now().toIso8601String(),
    };
    try {
      await _send(job);
      if (draftKey != null) await LocalStore.remove(draftKey);
      unawaited(flush()); // the connection works: send what was waiting
      return true;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final jobs = await _all();
      // the same form saved again replaces its waiting copy
      jobs.removeWhere((x) => x['user'] == _uid && x['label'] == label && x['table'] == table);
      jobs.add(job);
      await _write(jobs);
      return false;
    }
  }

  /// Sends what is waiting. Returns how many were sent.
  static Future<int> flush() async {
    if (_flushing || _uid == null) return 0;
    _flushing = true;
    int sent = 0;
    try {
      final jobs = await _all();
      for (final j in List<Map<String, dynamic>>.from(jobs)) {
        if (j['user'] != _uid || j['error'] != null) continue;
        try {
          await _send(j);
          jobs.removeWhere((x) => x['id'] == j['id']);
          final dk = j['draftKey'] as String?;
          if (dk != null) await LocalStore.remove(dk);
          sent++;
        } catch (e) {
          if (isNetworkError(e)) break; // still offline: try later
          j['error'] = e is PostgrestException ? e.message : e.toString(); // refused: shown in the list
        }
      }
      await _write(jobs);
    } finally {
      _flushing = false;
    }
    return sent;
  }

  static Future<List<Map<String, dynamic>>> mine() async => (await _all()).where((j) => j['user'] == _uid).toList();

  static Future<void> discard(String id) async {
    final jobs = await _all();
    jobs.removeWhere((x) => x['id'] == id && x['user'] == _uid);
    await _write(jobs);
  }
}

/// A small pill at the bottom of the screen while reports are waiting to be
/// sent; tap it to see them and send now.
class OutboxBadge extends StatelessWidget {
  const OutboxBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Outbox.pending,
      builder: (context, n, child) {
        if (n == 0) return const SizedBox.shrink();
        return SafeArea(
          child: Material(
              color: const Color(0xFFE65100),
              elevation: 6,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => _showList(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(n == 1 ? "1 report waiting to send" : "$n reports waiting to send",
                        style: GoogleFonts.merriweather(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ),
        );
      },
    );
  }

  /// The app's navigator (the badge sits above it, see main.dart).
  static GlobalKey<NavigatorState>? navigatorKey;

  static Future<void> _showList(BuildContext context) async {
    final ctx = navigatorKey?.currentContext ?? context;
    await showDialog(
      context: ctx,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, set) => FutureBuilder<List<Map<String, dynamic>>>(
          future: Outbox.mine(),
          builder: (_, snap) {
            final jobs = snap.data ?? const [];
            return AlertDialog(
              title: const Text("Waiting to send"),
              content: SizedBox(
                width: 420,
                child: jobs.isEmpty
                    ? const Text("Everything has been sent.")
                    : ListView(shrinkWrap: true, children: [
                        const Text("These reports were saved on this device while the connection was down. They are sent automatically when it comes back."),
                        const SizedBox(height: 8),
                        for (final j in jobs)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(j['error'] == null ? Icons.schedule_rounded : Icons.error_outline_rounded,
                                color: j['error'] == null ? Colors.orange.shade800 : Colors.red),
                            title: Text.rich(TextSpan(text: (j['label'] ?? '').toString())),
                            subtitle: Text.rich(TextSpan(
                                text: j['error'] != null
                                    ? "${tr('Not accepted')}: ${j['error']}"
                                    : "${(j['rows'] as List).length} ${tr('rows')} · ${(j['at'] ?? '').toString().replaceFirst('T', ' ').substring(0, 16)}")),
                            trailing: IconButton(
                              tooltip: tr("Discard"),
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () async {
                                await Outbox.discard(j['id'].toString());
                                set(() {});
                              },
                            ),
                          ),
                      ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx), child: const Text("Close")),
                if (jobs.isNotEmpty)
                  FilledButton.icon(
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text("Send now"),
                    onPressed: () async {
                      final n = await Outbox.flush();
                      set(() {});
                      if (dctx.mounted) {
                        ScaffoldMessenger.maybeOf(dctx)?.showSnackBar(SnackBar(
                          content: Text(n > 0 ? "Sent $n report(s)." : "Still no connection. They'll be sent automatically."),
                        ));
                      }
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
