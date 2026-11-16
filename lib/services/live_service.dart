import 'package:material_ui/material_ui.dart' hide Text;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/i18n.dart';
import '../screens/live_room_screen.dart';
import 'call_service.dart';
import 'chat_service.dart';

/// Live voice / video chats in My Home groups (like Telegram) on the
/// LiveKit server. The Supabase function "live-room" checks every
/// permission; this class only calls it and opens the screen.
/// Until the server is set up (app_config "livekit_url" empty), groups keep
/// the built-in small video chat (CallService).
class LiveService {
  LiveService._();

  static SupabaseClient get _db => Supabase.instance.client;
  static String? _url;
  static DateTime? _urlAt;

  /// The live-chat server is set up.
  static Future<bool> enabled() async {
    if (_url == null || _urlAt == null || DateTime.now().difference(_urlAt!) > const Duration(minutes: 10)) {
      try {
        final r = await _db.from('app_config').select('config_value').eq('config_key', 'livekit_url').maybeSingle();
        final v = r?['config_value'];
        _url = v is String ? v.trim() : '';
      } catch (_) {
        _url = '';
      }
      _urlAt = DateTime.now();
    }
    return (_url ?? '').isNotEmpty;
  }

  /// Calls the function; throws a readable message on refusal.
  static Future<Map<String, dynamic>> call(String action, [Map<String, dynamic> body = const {}]) async {
    try {
      final res = await _db.functions.invoke('live-room', body: {'action': action, ...body});
      final data = res.data;
      if (data is Map && data['error'] != null) throw data['error'].toString();
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on FunctionException catch (e) {
      final d = e.details;
      throw (d is Map && d['error'] != null) ? d['error'].toString() : "The live-chat server didn't answer (${e.status}).";
    }
  }

  /// The group's live chat now (null = none).
  static Future<Map<String, dynamic>?> current(String chatRoomId) async {
    try {
      return await _db.from('live_chats').select().eq('chat_room_id', chatRoomId).eq('status', 'live').maybeSingle();
    } catch (_) {
      return null;
    }
  }

  /// The group header's voice / video buttons: join the live chat, or (owner
  /// / admin) start one. Small groups without the server: the built-in chat.
  static Future<void> openFromGroup(BuildContext context, ChatRoom room, {required bool video}) async {
    if (!await enabled()) {
      if (context.mounted) await CallService.call(context, room.id, video: video, roomName: room.name);
      return;
    }
    final live = await current(room.id);
    if (!context.mounted) return;
    if (live != null) {
      await join(context, live['id'].toString(), title: room.name);
      return;
    }
    final admin = room.myRole == 'owner' || room.myRole == 'admin';
    if (!admin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("There's no live chat in this group now. The group's admins can start one.")));
      return;
    }
    final ok = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _StartDialog(video: video, groupName: room.name),
    );
    if (ok == null || !context.mounted) return;
    try {
      final r = await call('start', {'chat_room_id': room.id, 'kind': ok['kind'], 'title': ok['title'], 'join_muted': ok['join_muted']});
      if (context.mounted) await _open(context, r, title: room.name, startVideo: ok['kind'] == 'video');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't start: $e")));
    }
  }

  static Future<void> join(BuildContext context, String liveId, {required String title}) async {
    try {
      final r = await call('join', {'live_id': liveId});
      if (context.mounted) await _open(context, r, title: title, startVideo: false);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't join: $e")));
    }
  }

  static String? _openLive;

  static Future<void> _open(BuildContext context, Map<String, dynamic> r, {required String title, required bool startVideo}) async {
    final id = r['live_id'].toString();
    if (_openLive == id) return;
    _openLive = id;
    try {
      await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LiveRoomScreen(
          url: r['url'].toString(),
          token: r['token'].toString(),
          liveId: id,
          admin: r['admin'] == true,
          title: title,
          startVideo: startVideo,
        ),
      ));
    } finally {
      _openLive = null;
    }
  }

  /// A play link (1 hour) for a recording.
  static Future<String?> recordingUrl(String recordingId) async {
    final r = await call('recording_url', {'recording_id': recordingId});
    return r['url']?.toString();
  }
}

class _StartDialog extends StatefulWidget {
  final bool video;
  final String groupName;
  const _StartDialog({required this.video, required this.groupName});
  @override
  State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  late bool _video = widget.video;
  bool _joinMuted = false;
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text.rich(TextSpan(text: "${tr('Start a live chat')} · ${widget.groupName}"), maxLines: 2),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.mic_rounded), label: Text("Voice chat")),
              ButtonSegment(value: true, icon: Icon(Icons.videocam_rounded), label: Text("Video chat")),
            ],
            selected: {_video},
            onSelectionChanged: (v) => setState(() => _video = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: tr("Title (optional), e.g. Morning Light"), border: const OutlineInputBorder(), isDense: true),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _joinMuted,
            onChanged: (v) => setState(() => _joinMuted = v),
            title: const Text("Only admins can speak"),
            subtitle: const Text("Others raise a hand to be allowed (good for services and Morning Light)"),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        FilledButton.icon(
          icon: Icon(_video ? Icons.videocam_rounded : Icons.mic_rounded, size: 18),
          label: const Text("Start"),
          onPressed: () => Navigator.pop(context, {
            'kind': _video ? 'video' : 'voice',
            'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
            'join_muted': _joinMuted,
          }),
        ),
      ],
    );
  }
}
