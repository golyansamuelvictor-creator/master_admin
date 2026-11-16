import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/i18n.dart';
import '../screens/call_screen.dart';
import '../screens/communication_screen.dart';
import 'app_sounds.dart';
import 'chat_service.dart';
import 'media_playback.dart' show appNavigatorKey;

/// My Home calls (voice, video, group video chats) and invite links.
///
/// Calls run straight between the devices (WebRTC, `screens/call_screen.dart`);
/// Supabase only rings people and passes the connection messages
/// (`chat_calls`, `chat_call_people`, `chat_call_signals`, 11_round10.sql).
class CallService {
  CallService._();

  static SupabaseClient get _db => Supabase.instance.client;
  static RealtimeChannel? _ringChannel;
  static String? _listeningFor;

  /// The call open on this device (one at a time).
  static String? activeCall;
  static final Set<String> _shown = {};
  static Timer? _ringTone;

  /// Start listening for incoming calls (after signing in).
  static void start() {
    final me = _db.auth.currentUser?.id;
    if (me == null || _listeningFor == me) return;
    stop();
    _listeningFor = me;
    _ringChannel = _db
        .channel('calls-ring-$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_call_people',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: me),
          callback: (p) {
            if (p.newRecord['state'] == 'ringing') _checkRinging();
          },
        )
        .subscribe();
    _checkRinging();
    checkPendingInvite();
  }

  static void stop() {
    final ch = _ringChannel;
    if (ch != null) _db.removeChannel(ch);
    _ringChannel = null;
    _listeningFor = null;
    _stopTone();
  }

  /// Someone is calling me: show the incoming call screen.
  static Future<void> _checkRinging() async {
    try {
      final rows = List<Map<String, dynamic>>.from(await _db.rpc('my_ringing_calls') as List);
      for (final r in rows) {
        final id = r['call_id'].toString();
        if (_shown.contains(id) || activeCall == id) continue;
        if (activeCall != null) continue; // busy in another call
        _shown.add(id);
        _showIncoming(r);
        break;
      }
    } catch (e) {
      debugPrint('Calls not ready (run 11_round10.sql): $e');
    }
  }

  static void _startTone() {
    _ringTone?.cancel();
    AppSounds.play('triple');
    _ringTone = Timer.periodic(const Duration(seconds: 3), (_) => AppSounds.play('triple'));
  }

  static void _stopTone() {
    _ringTone?.cancel();
    _ringTone = null;
  }

  static void _showIncoming(Map<String, dynamic> r) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    _startTone();
    nav.push(PageRouteBuilder(
      opaque: false,
      pageBuilder: (_, __, ___) => IncomingCallScreen(
        info: r,
        onAnswer: () {
          _stopTone();
          nav.pop();
          openCall(r['call_id'].toString(), roomName: (r['is_group'] == true ? r['room_name'] : r['caller_name'])?.toString() ?? '', video: r['kind'] == 'video');
        },
        onDecline: () async {
          _stopTone();
          nav.pop();
          try {
            await _db.rpc('leave_call', params: {'p_call': r['call_id'], 'p_decline': true});
          } catch (_) {}
        },
        onGone: () {
          _stopTone();
          if (nav.canPop()) nav.pop();
        },
      ),
    ));
  }

  /// Calls everyone in [roomId] (or joins the call already running there).
  static Future<void> call(BuildContext context, String roomId, {required bool video, required String roomName}) async {
    if (activeCall != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You're already in a call.")));
      return;
    }
    try {
      final id = (await _db.rpc('start_call', params: {'p_room': roomId, 'p_kind': video ? 'video' : 'voice'})).toString();
      await openCall(id, roomName: roomName, video: video);
    } catch (e) {
      if (!context.mounted) return;
      final m = e is PostgrestException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't start the call: $m")));
    }
  }

  static Future<void> openCall(String callId, {required String roomName, required bool video}) async {
    final nav = appNavigatorKey.currentState;
    if (nav == null || activeCall == callId) return;
    activeCall = callId;
    _shown.add(callId);
    try {
      await nav.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => CallScreen(callId: callId, title: roomName, startWithVideo: video)));
    } finally {
      activeCall = null;
    }
  }

  /// Connection servers (app_config 'call_ice_servers'; STUN by default).
  static Future<List<Map<String, dynamic>>> iceServers() async {
    try {
      final row = await _db.from('app_config').select('config_value').eq('config_key', 'call_ice_servers').maybeSingle();
      final v = row?['config_value'];
      if (v is List && v.isNotEmpty) return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
    return [
      {
        'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']
      }
    ];
  }

  // ---------------------------------------------------------------------------
  // Invite links

  /// The link people open to join (web: this site with ?join=CODE).
  static String inviteLink(String code) {
    final base = Uri.base;
    final origin = base.hasScheme && base.scheme.startsWith('http') ? '${base.origin}${base.path}' : '';
    return origin.isEmpty ? code : '$origin?join=$code';
  }

  /// The code inside a pasted link (or the code itself).
  static String? codeFrom(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final uri = Uri.tryParse(t);
    final q = uri?.queryParameters['join'];
    if (q != null && q.isNotEmpty) return q;
    final m = RegExp(r'join[=/]([A-Za-z0-9_\-]{6,})').firstMatch(t);
    if (m != null) return m.group(1);
    return RegExp(r'^[A-Za-z0-9_\-]{6,}$').hasMatch(t) ? t : null;
  }

  /// Opened the app with ?join=CODE: remember it until signed in.
  static Future<void> rememberInviteFromUrl() async {
    final code = Uri.base.queryParameters['join'];
    if (code == null || code.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('pending_invite', code);
    } catch (_) {}
  }

  static Future<void> checkPendingInvite() async {
    try {
      final p = await SharedPreferences.getInstance();
      final code = p.getString('pending_invite');
      if (code == null) return;
      await p.remove('pending_invite');
      // give the home screen a moment to open
      await Future.delayed(const Duration(seconds: 2));
      final ctx = appNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) await joinWithCode(ctx, code);
    } catch (_) {}
  }

  /// Shows what the link is for, then joins.
  static Future<void> joinWithCode(BuildContext context, String code) async {
    Map<String, dynamic>? info;
    try {
      final rows = List<Map<String, dynamic>>.from(await _db.rpc('chat_invite_info', params: {'p_code': code}) as List);
      info = rows.firstOrNull;
    } catch (_) {}
    if (!context.mounted) return;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This invite link doesn't exist.")));
      return;
    }
    final valid = info['valid'] == true;
    final member = info['already_member'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.group_rounded, size: 34),
        title: Text(info!['name']?.toString() ?? 'Group'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if ((info['description'] ?? '').toString().isNotEmpty) Text(info['description'].toString(), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text("${info['members']} members", style: const TextStyle(fontWeight: FontWeight.bold)),
          if (!valid) Padding(padding: const EdgeInsets.only(top: 8), child: Text(info['reason']?.toString() ?? '', style: const TextStyle(color: Colors.red))),
          if (valid && !member && info['needs_approval'] == true)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text("A group admin approves new members.", textAlign: TextAlign.center)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          if (member || valid)
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(member ? "Open chat" : (info['needs_approval'] == true ? "Ask to join" : "Join group"))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final room = await _db.rpc('join_chat_by_invite', params: {'p_code': code});
      if (!context.mounted) return;
      if (room == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request sent. You'll see the group once an admin accepts.")));
        return;
      }
      final me = await ChatService.myProfile();
      if (!context.mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CommunicationScreen(
          userEmail: _db.auth.currentUser?.email ?? '',
          userRole: (me['role'] ?? '').toString(),
          openRoomId: room.toString(),
        ),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is PostgrestException ? e.message : "Couldn't join: $e")));
    }
  }
}
