import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/i18n.dart';
import '../services/live_service.dart';

const _bg = Color(0xFF111827);
const _panel = Color(0xFF1F2937);
const _accent = Color(0xFF8B5CF6);

/// A live voice / video chat of a My Home group, like Telegram's:
/// · everyone joins with the microphone off; turn on the mic, the camera or
///   (on a computer) share the screen; raise a hand when only admins speak
/// · "Audio only" stops all video to save data
/// · admins: mute someone / everyone, let someone speak, remove, "only
///   admins can speak", record (video or audio), end for everyone
class LiveRoomScreen extends StatefulWidget {
  final String url, token, liveId, title;
  final bool admin;
  final bool startVideo;
  const LiveRoomScreen({
    super.key,
    required this.url,
    required this.token,
    required this.liveId,
    required this.title,
    required this.admin,
    this.startVideo = false,
  });

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  late final Room _room = Room(
    roomOptions: const RoomOptions(
      adaptiveStream: true, // each person gets the video size their screen needs
      dynacast: true,
      defaultCameraCaptureOptions: CameraCaptureOptions(params: VideoParametersPresets.h360_169),
      defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
      defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(params: VideoParametersPresets.screenShareH720FPS15),
    ),
  );
  EventsListener<RoomEvent>? _events;
  Timer? _tick;
  StreamSubscription<List<Map<String, dynamic>>>? _liveSub;
  Map<String, dynamic> _live = {};
  bool _connecting = true;
  String? _error;
  bool _audioOnly = false;
  bool _busy = false;
  final DateTime _since = DateTime.now();

  LocalParticipant? get _me => _room.localParticipant;
  bool get _canSpeak => _me?.permissions.canPublish ?? false;
  bool get _hand => (_me?.attributes['hand'] ?? '') == '1';

  @override
  void initState() {
    super.initState();
    _connect();
    // speaking rings, timer and new people: a light redraw twice a second
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      if (_audioOnly) _applyAudioOnly();
      setState(() {});
    });
    _liveSub = Supabase.instance.client.from('live_chats').stream(primaryKey: ['id']).eq('id', widget.liveId).listen((rows) {
      if (rows.isEmpty || !mounted) return;
      setState(() => _live = rows.first);
      if (rows.first['status'] == 'ended') _leave(ended: true);
    }, onError: (_) {});
  }

  Future<void> _connect() async {
    try {
      _events = _room.createListener();
      _events!.on<RoomDisconnectedEvent>((_) {
        if (mounted && !_leaving) _leave(ended: true);
      });
      _events!.on<ParticipantPermissionsUpdatedEvent>((e) async {
        // an admin stopped my speaking: mic and camera off
        if (e.participant == _me && !_canSpeak) {
          await _me?.setMicrophoneEnabled(false);
          await _me?.setCameraEnabled(false);
        }
        if (e.participant == _me && _canSpeak && _hand) await _me?.setAttributes({'hand': ''});
        if (mounted) setState(() {});
      });
      await _room.connect(widget.url, widget.token);
      if (widget.startVideo && widget.admin && _canSpeak) {
        try {
          await _me?.setCameraEnabled(true);
        } catch (_) {}
      }
      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = "Couldn't connect to the live chat: $e";
        });
      }
    }
  }

  bool _leaving = false;
  Future<void> _leave({bool ended = false}) async {
    if (_leaving) return;
    _leaving = true;
    try {
      await _room.disconnect();
    } catch (_) {}
    if (mounted) {
      if (ended) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text("The live chat has ended.")));
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _liveSub?.cancel();
    _events?.dispose();
    _room.disconnect();
    _room.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- actions
  Future<void> _toggle(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      _snack("$e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text.rich(TextSpan(text: m))));
  }

  Future<void> _admin(String action, [Map<String, dynamic> body = const {}]) async {
    try {
      await LiveService.call(action, {'live_id': widget.liveId, ...body});
    } catch (e) {
      _snack("$e");
    }
  }

  void _applyAudioOnly() {
    for (final p in _room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        if (_audioOnly && pub.enabled) pub.disable();
        if (!_audioOnly && !pub.enabled) pub.enable();
      }
    }
  }

  // ---------------------------------------------------------------- people
  List<Participant> get _people => [
        if (_me != null) _me!,
        ..._room.remoteParticipants.values,
      ];

  bool _isAdmin(Participant p) {
    try {
      return (jsonDecode(p.metadata ?? '{}') as Map)['role'] == 'admin';
    } catch (_) {
      return false;
    }
  }

  /// The video tiles: screens first, then cameras.
  List<(Participant, VideoTrack, bool)> get _videos {
    final out = <(Participant, VideoTrack, bool)>[];
    if (_audioOnly) return out;
    for (final p in _people) {
      for (final pub in p.videoTrackPublications) {
        final t = pub.track;
        if (t is VideoTrack && !pub.muted) out.add((p, t, pub.isScreenShare));
      }
    }
    out.sort((a, b) => (b.$3 ? 1 : 0) - (a.$3 ? 1 : 0));
    return out;
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final rec = (_live['recording'] ?? 'off').toString();
    final title = (_live['title'] ?? '').toString().isNotEmpty ? _live['title'].toString() : widget.title;
    final d = DateTime.now().difference(_since);
    final time = "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_leaving) {
          _leaving = true;
          _room.disconnect();
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(children: [
            // top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(children: [
                IconButton(
                  tooltip: tr("Minimise"),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(text: title),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                    Row(children: [
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text.rich(TextSpan(text: "${tr('Live')} · ${_people.length} ${tr('people')} · $time"),
                          style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                      if (rec != 'off') ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.fiber_manual_record_rounded, color: Color(0xFFEF4444), size: 12),
                        Text(rec == 'saving' ? "Saving recording…" : "Recording", style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 11.5)),
                      ],
                    ]),
                  ]),
                ),
                if (widget.admin) _adminMenu(rec),
              ]),
            ),
            Expanded(child: _body()),
            _controls(),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    if (_connecting) return const Center(child: CircularProgressIndicator(color: Colors.white));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text.rich(TextSpan(text: _error), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    final videos = _videos;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final grid = videos.isEmpty
          ? null
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: videos.length == 1 ? c.maxWidth : (wide ? 520 : 360),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 16 / 9,
              ),
              itemCount: videos.length,
              itemBuilder: (_, i) => _videoTile(videos[i].$1, videos[i].$2, videos[i].$3),
            );
      final people = _peopleList();
      if (grid == null) return people;
      if (wide) {
        return Row(children: [
          Expanded(child: grid),
          SizedBox(width: 300, child: people),
        ]);
      }
      return Column(children: [
        Expanded(flex: 3, child: grid),
        Expanded(flex: 2, child: people),
      ]);
    });
  }

  Widget _videoTile(Participant p, VideoTrack t, bool screen) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(fit: StackFit.expand, children: [
        Container(color: Colors.black),
        VideoTrackRenderer(t, fit: screen ? VideoViewFit.contain : VideoViewFit.cover),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (screen) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.screen_share_rounded, color: Colors.white, size: 13)),
              Icon(p.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded, color: p.isMuted ? Colors.redAccent : Colors.white, size: 13),
              const SizedBox(width: 4),
              Text.rich(TextSpan(text: p == _me ? tr("You") : p.name), style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
        ),
        if (p.isSpeaking)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: const Color(0xFF22C55E), width: 3), borderRadius: BorderRadius.circular(14))),
            ),
          ),
      ]),
    );
  }

  Widget _peopleList() {
    final people = _people.toList()
      ..sort((a, b) {
        int score(Participant p) => (p.isSpeaking ? 8 : 0) + (p.attributes['hand'] == '1' ? 4 : 0) + (_isAdmin(p) ? 2 : 0) + (!p.isMuted ? 1 : 0);
        return score(b) - score(a);
      });
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: people.length,
        itemBuilder: (_, i) {
          final p = people[i];
          final hand = p.attributes['hand'] == '1';
          final speaking = p.isSpeaking;
          final canSpeak = p.permissions.canPublish;
          return ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: speaking ? const Color(0xFF22C55E) : Colors.transparent, width: 2.5)),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: _accent,
                child: Text.rich(TextSpan(text: p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase()), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            title: Text.rich(TextSpan(text: p == _me ? "${p.name} (${tr('you')})" : p.name),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
            subtitle: Text(
              speaking ? "speaking" : (hand ? "raised a hand ✋" : (_isAdmin(p) ? "admin" : (canSpeak ? "listening" : "listening · can't speak"))),
              style: TextStyle(color: speaking ? const Color(0xFF86EFAC) : (hand ? const Color(0xFFFCD34D) : Colors.white54), fontSize: 11.5),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (hand) const Text("✋", style: TextStyle(fontSize: 18)),
              Icon(p.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded, color: p.isMuted ? Colors.white38 : const Color(0xFF86EFAC), size: 20),
            ]),
            onTap: widget.admin && p != _me ? () => _personMenu(p) : null,
          );
        },
      ),
    );
  }

  Future<void> _personMenu(Participant p) async {
    final canSpeak = p.permissions.canPublish;
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _panel,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text.rich(TextSpan(text: p.name), style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.bold))),
          if (!p.isMuted) _sheetItem(c, 'mute', Icons.mic_off_rounded, "Mute"),
          _sheetItem(c, canSpeak ? 'deny' : 'allow', canSpeak ? Icons.voice_over_off_rounded : Icons.record_voice_over_rounded,
              canSpeak ? "Stop them speaking" : "Let them speak"),
          _sheetItem(c, 'remove', Icons.person_remove_rounded, "Remove from the live chat", red: true),
        ]),
      ),
    );
    switch (v) {
      case 'mute':
        await _admin('mute', {'identity': p.identity});
      case 'allow':
        await _admin('permit', {'identity': p.identity, 'allow': true});
      case 'deny':
        await _admin('permit', {'identity': p.identity, 'allow': false});
      case 'remove':
        await _admin('remove', {'identity': p.identity});
    }
  }

  Widget _sheetItem(BuildContext c, String v, IconData i, String label, {bool red = false}) => ListTile(
        leading: Icon(i, color: red ? Colors.redAccent : Colors.white),
        title: Text(label, style: TextStyle(color: red ? Colors.redAccent : Colors.white)),
        onTap: () => Navigator.pop(c, v),
      );

  Widget _adminMenu(String rec) {
    final joinMuted = (_live['settings'] is Map) && (_live['settings'] as Map)['join_muted'] == true;
    return PopupMenuButton<String>(
      tooltip: tr("Manage"),
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
      onSelected: (v) async {
        switch (v) {
          case 'mute_all':
            await _admin('mute');
          case 'join_muted':
            await _admin('settings', {'join_muted': !joinMuted});
          case 'rec_video':
            await _admin('record_start', {'kind': 'video'});
          case 'rec_audio':
            await _admin('record_start', {'kind': 'audio'});
          case 'rec_stop':
            await _admin('record_stop');
          case 'end':
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text("End the live chat for everyone?"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text("End")),
                ],
              ),
            );
            if (ok == true) {
              await _admin('end');
              await _leave();
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'mute_all', child: Text("Mute everyone")),
        CheckedPopupMenuItem(value: 'join_muted', checked: joinMuted, child: const Text("Only admins can speak")),
        const PopupMenuDivider(),
        if (rec == 'off') ...[
          const PopupMenuItem(value: 'rec_video', child: Text("Record video")),
          const PopupMenuItem(value: 'rec_audio', child: Text("Record audio only")),
        ] else
          const PopupMenuItem(value: 'rec_stop', child: Text("Stop recording")),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'end', child: Text("End live chat", style: TextStyle(color: Colors.red))),
      ],
    );
  }

  Widget _controls() {
    final me = _me;
    final mic = me?.isMicrophoneEnabled() ?? false;
    final cam = me?.isCameraEnabled() ?? false;
    final screen = me?.isScreenShareEnabled() ?? false;
    // screen sharing: computers (web / desktop); the Android app needs a
    // background service for it (not set up yet)
    final canShareScreen = kIsWeb || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
      color: _bg,
      child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
        if (_canSpeak) ...[
          _roundBtn(mic ? Icons.mic_rounded : Icons.mic_off_rounded, mic ? "Mute" : "Unmute", mic ? _accent : const Color(0xFF374151),
              () => _toggle(() async => me?.setMicrophoneEnabled(!mic))),
          _roundBtn(cam ? Icons.videocam_rounded : Icons.videocam_off_rounded, cam ? "Stop video" : "Video", cam ? _accent : const Color(0xFF374151),
              () => _toggle(() async => me?.setCameraEnabled(!cam))),
          if (canShareScreen)
            _roundBtn(Icons.screen_share_rounded, screen ? "Stop sharing" : "Screen", screen ? _accent : const Color(0xFF374151),
                () => _toggle(() async => me?.setScreenShareEnabled(!screen, captureScreenAudio: true))),
        ] else
          _roundBtn(Icons.back_hand_rounded, _hand ? "Lower hand" : "Raise hand", _hand ? const Color(0xFFF59E0B) : const Color(0xFF374151),
              () => _toggle(() async => me?.setAttributes({'hand': _hand ? '' : '1'}))),
        _roundBtn(_audioOnly ? Icons.hearing_rounded : Icons.hd_rounded, _audioOnly ? "Audio only" : "Video on", _audioOnly ? const Color(0xFF0EA5E9) : const Color(0xFF374151), () {
          setState(() => _audioOnly = !_audioOnly);
          _applyAudioOnly();
        }),
        _roundBtn(Icons.call_end_rounded, "Leave", const Color(0xFFDC2626), () => _leave()),
      ]),
    );
  }

  Widget _roundBtn(IconData icon, String label, Color color, VoidCallback onTap) => SizedBox(
        width: 74,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Material(
            color: color,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _connecting || _error != null ? null : onTap,
              child: Padding(padding: const EdgeInsets.all(14), child: Icon(icon, color: Colors.white, size: 24)),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
      );
}
