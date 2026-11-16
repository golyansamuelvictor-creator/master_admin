import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/i18n.dart';
import '../services/call_service.dart';

const Color _kCallBg = Color(0xFF14101C);

/// One person in the call (not me).
class _Peer {
  final String id;
  RTCPeerConnection? pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  bool rendererReady = false;
  bool hasVideo = false;
  bool connected = false;
  final List<RTCIceCandidate> pendingIce = [];
  bool remoteSet = false;
  _Peer(this.id);
}

/// A voice call, video call or group video chat (WebRTC, every person
/// connected to every other person; best for up to about 8 people).
class CallScreen extends StatefulWidget {
  final String callId;
  final String title;
  final bool startWithVideo;
  const CallScreen({super.key, required this.callId, required this.title, required this.startWithVideo});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _db = Supabase.instance.client;
  String get _me => _db.auth.currentUser?.id ?? '';

  MediaStream? _local;
  MediaStream? _screen;
  final RTCVideoRenderer _localView = RTCVideoRenderer();
  final Map<String, _Peer> _peers = {};
  final Map<String, Map<String, dynamic>> _people = {}; // user id → name, photo, state, mic, cam
  final Set<int> _seenSignals = {};
  List<Map<String, dynamic>> _ice = [];

  RealtimeChannel? _channel;
  Timer? _ringTimeout;
  Timer? _clock;
  DateTime? _connectedAt;
  String _status = 'Connecting…';
  String _callStatus = 'ringing';
  String _startedBy = '';
  bool _mic = true;
  bool _cam = false;
  bool _speaker = true;
  bool _sharing = false;
  bool _closing = false;
  String? _error;

  bool get _mobile => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _cam = widget.startWithVideo;
    _start();
  }

  Future<void> _start() async {
    try {
      await _localView.initialize();
      _ice = await CallService.iceServers();
      try {
        _local = await navigator.mediaDevices.getUserMedia({
          'audio': {'echoCancellation': true, 'noiseSuppression': true},
          'video': widget.startWithVideo ? {'facingMode': 'user', 'width': {'ideal': 640}, 'height': {'ideal': 480}} : false,
        });
      } catch (_) {
        // no camera (or it was refused): carry on with sound only
        _local = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
        _cam = false;
      }
      _localView.srcObject = _local;
      if (_mobile) {
        try {
          await Helper.setSpeakerphoneOn(widget.startWithVideo);
          _speaker = widget.startWithVideo;
        } catch (_) {}
      }

      final call = await _db.from('chat_calls').select('status, started_by, kind').eq('id', widget.callId).maybeSingle();
      _callStatus = (call?['status'] ?? 'ringing').toString();
      _startedBy = (call?['started_by'] ?? '').toString();
      if (_callStatus == 'ended' || _callStatus == 'missed' || _callStatus == 'declined') {
        setState(() => _error = "This call has ended.");
        return;
      }

      _listen();
      await _loadPeople();
      // everyone already in the call: connect to each of them
      final others = List<Map<String, dynamic>>.from(await _db.rpc('join_call', params: {'p_call': widget.callId}) as List);
      await _db.from('chat_call_people').update({'cam_on': _cam, 'mic_on': _mic}).eq('call_id', widget.callId).eq('user_id', _me);
      // signals that arrived before listening started
      final early = await _db.from('chat_call_signals').select().eq('call_id', widget.callId).eq('to_user', _me).order('id', ascending: true);
      for (final s in early) {
        await _onSignal(s);
      }
      for (final o in others) {
        await _offerTo(o['user_id'].toString());
      }
      if (_startedBy == _me && others.isEmpty) {
        _status = 'Ringing…';
        _ringTimeout = Timer(const Duration(seconds: 45), () async {
          if (_peers.values.any((p) => p.connected) || _connectedAt != null) return;
          try {
            await _db.rpc('call_timeout', params: {'p_call': widget.callId});
          } catch (_) {}
          _close(reason: 'No answer');
        });
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't start the call: ${e is PostgrestException ? e.message : e}");
    }
  }

  void _listen() {
    _channel = _db
        .channel('call-${widget.callId}-$_me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_call_signals',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'to_user', value: _me),
          callback: (p) {
            if (p.newRecord['call_id']?.toString() == widget.callId) _onSignal(p.newRecord);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_call_people',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'call_id', value: widget.callId),
          callback: (p) => _onPerson(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_calls',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.callId),
          callback: (p) {
            _callStatus = (p.newRecord['status'] ?? _callStatus).toString();
            if (_callStatus == 'ended' || _callStatus == 'missed' || _callStatus == 'declined') {
              _close(reason: _callStatus == 'declined' ? 'Call declined' : (_callStatus == 'missed' ? 'No answer' : 'Call ended'));
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadPeople() async {
    final rows = List<Map<String, dynamic>>.from(await _db.rpc('call_people', params: {'p_call': widget.callId}) as List);
    for (final r in rows) {
      _people[r['user_id'].toString()] = r;
    }
    if (mounted) setState(() {});
  }

  void _onPerson(Map<String, dynamic> row) {
    final id = row['user_id']?.toString() ?? '';
    if (id.isEmpty) return;
    final p = _people.putIfAbsent(id, () => {'user_id': id});
    p['state'] = row['state'];
    p['mic_on'] = row['mic_on'];
    p['cam_on'] = row['cam_on'];
    if (id != _me && (row['state'] == 'left' || row['state'] == 'declined' || row['state'] == 'missed')) {
      _dropPeer(id);
      final name = (p['full_name'] ?? 'Someone').toString();
      if (row['state'] == 'left' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$name left the call"), duration: const Duration(seconds: 2)));
      }
      if (row['state'] == 'declined' && mounted && _people.length <= 2) _status = 'Call declined';
    }
    if (mounted) setState(() {});
  }

  Future<_Peer> _peer(String id) async {
    final existing = _peers[id];
    if (existing?.pc != null) return existing!;
    final p = existing ?? _Peer(id);
    _peers[id] = p;
    if (!p.rendererReady) {
      await p.renderer.initialize();
      p.rendererReady = true;
    }
    final pc = await createPeerConnection({'iceServers': _ice, 'sdpSemantics': 'unified-plan'});
    p.pc = pc;
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(t, _local!);
    }
    // always ready to receive video, so a camera can be turned on later
    if (_local?.getVideoTracks().isEmpty ?? true) {
      await pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeVideo, init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv));
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _send(id, 'ice', {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    };
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        p.renderer.srcObject = e.streams.first;
        if (e.track.kind == 'video') p.hasVideo = true;
        if (mounted) setState(() {});
      }
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        p.connected = true;
        _connectedAt ??= DateTime.now();
        _ringTimeout?.cancel();
        _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        p.connected = false;
        if (mounted) setState(() => _status = 'Connection lost. Reconnecting…');
        _offerTo(id, restart: true);
      }
      if (mounted) setState(() {});
    };
    return p;
  }

  Future<void> _send(String to, String kind, Map<String, dynamic> payload) async {
    try {
      await _db.from('chat_call_signals').insert({'call_id': widget.callId, 'to_user': to, 'kind': kind, 'payload': payload});
    } catch (e) {
      debugPrint('call signal failed: $e');
    }
  }

  Future<void> _offerTo(String id, {bool restart = false}) async {
    final p = await _peer(id);
    final offer = await p.pc!.createOffer(restart ? {'iceRestart': true} : {});
    await p.pc!.setLocalDescription(offer);
    await _send(id, 'offer', {'sdp': offer.sdp, 'type': offer.type});
  }

  Future<void> _onSignal(Map<String, dynamic> s) async {
    final sid = (s['id'] as num?)?.toInt();
    if (sid != null && !_seenSignals.add(sid)) return;
    final from = s['from_user']?.toString() ?? '';
    if (from.isEmpty || from == _me) return;
    final payload = Map<String, dynamic>.from((s['payload'] ?? {}) as Map);
    try {
      switch (s['kind']) {
        case 'offer':
          final p = await _peer(from);
          await p.pc!.setRemoteDescription(RTCSessionDescription(payload['sdp'], payload['type'] ?? 'offer'));
          p.remoteSet = true;
          await _flushIce(p);
          final answer = await p.pc!.createAnswer({});
          await p.pc!.setLocalDescription(answer);
          await _send(from, 'answer', {'sdp': answer.sdp, 'type': answer.type});
          if (!_people.containsKey(from)) await _loadPeople();
        case 'answer':
          final p = _peers[from];
          if (p?.pc == null) return;
          await p!.pc!.setRemoteDescription(RTCSessionDescription(payload['sdp'], payload['type'] ?? 'answer'));
          p.remoteSet = true;
          await _flushIce(p);
        case 'ice':
          final c = RTCIceCandidate(payload['candidate'], payload['sdpMid'], (payload['sdpMLineIndex'] as num?)?.toInt());
          final p = await _peer(from);
          if (p.remoteSet) {
            await p.pc!.addCandidate(c);
          } else {
            p.pendingIce.add(c);
          }
        case 'bye':
          _dropPeer(from);
      }
    } catch (e) {
      debugPrint('call signal error: $e');
    }
  }

  Future<void> _flushIce(_Peer p) async {
    for (final c in p.pendingIce) {
      try {
        await p.pc!.addCandidate(c);
      } catch (_) {}
    }
    p.pendingIce.clear();
  }

  void _dropPeer(String id) {
    final p = _peers.remove(id);
    if (p == null) return;
    p.pc?.close();
    p.renderer.srcObject = null;
    p.renderer.dispose();
  }

  // ---------------------------------------------------------------------------
  // Controls

  Future<void> _toggleMic() async {
    _mic = !_mic;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = _mic;
    }
    setState(() {});
    _db.from('chat_call_people').update({'mic_on': _mic}).eq('call_id', widget.callId).eq('user_id', _me).then((_) {}, onError: (_) {});
  }

  Future<void> _toggleCam() async {
    final tracks = _local?.getVideoTracks() ?? [];
    if (tracks.isEmpty) {
      // a voice call: add the camera now
      try {
        final v = await navigator.mediaDevices.getUserMedia({'audio': false, 'video': {'facingMode': 'user'}});
        final track = v.getVideoTracks().first;
        await _local?.addTrack(track);
        for (final p in _peers.values) {
          final senders = await p.pc!.getTransceivers();
          final free = senders.where((t) => t.receiver.track?.kind == 'video' || t.sender.track?.kind == 'video').firstOrNull;
          if (free != null) {
            await free.sender.replaceTrack(track);
          } else {
            await p.pc!.addTrack(track, _local!);
            await _offerTo(p.id);
          }
        }
        _localView.srcObject = _local;
        _cam = true;
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't open the camera: $e")));
        return;
      }
    } else {
      _cam = !_cam;
      for (final t in tracks) {
        t.enabled = _cam;
      }
    }
    setState(() {});
    _db.from('chat_call_people').update({'cam_on': _cam}).eq('call_id', widget.callId).eq('user_id', _me).then((_) {}, onError: (_) {});
  }

  Future<void> _switchCamera() async {
    final t = _local?.getVideoTracks().firstOrNull;
    if (t != null) await Helper.switchCamera(t);
  }

  Future<void> _toggleSpeaker() async {
    _speaker = !_speaker;
    try {
      await Helper.setSpeakerphoneOn(_speaker);
    } catch (_) {}
    setState(() {});
  }

  Future<void> _toggleShare() async {
    try {
      MediaStreamTrack? track;
      if (_sharing) {
        track = _local?.getVideoTracks().firstOrNull;
        for (final t in _screen?.getTracks() ?? <MediaStreamTrack>[]) {
          await t.stop();
        }
        _screen = null;
      } else {
        _screen = await navigator.mediaDevices.getDisplayMedia({'video': true, 'audio': false});
        track = _screen!.getVideoTracks().first;
        track.onEnded = () {
          if (_sharing) _toggleShare();
        };
      }
      for (final p in _peers.values) {
        final ts = await p.pc!.getTransceivers();
        final v = ts.where((t) => t.sender.track?.kind == 'video' || t.receiver.track?.kind == 'video').firstOrNull;
        if (v != null) await v.sender.replaceTrack(track);
      }
      _localView.srcObject = _sharing ? _local : _screen;
      _sharing = !_sharing;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't share the screen: $e")));
    }
  }

  Future<void> _hangUp() async {
    try {
      await _db.rpc('leave_call', params: {'p_call': widget.callId});
    } catch (_) {}
    _close();
  }

  void _close({String? reason}) {
    if (_closing) return;
    _closing = true;
    if (reason != null && mounted) setState(() => _status = reason);
    Future.delayed(Duration(milliseconds: reason == null ? 0 : 1200), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _ringTimeout?.cancel();
    _clock?.cancel();
    final ch = _channel;
    if (ch != null) _db.removeChannel(ch);
    if (!_closing) {
      _db.rpc('leave_call', params: {'p_call': widget.callId}).then((_) {}, onError: (_) {});
    }
    for (final id in _peers.keys.toList()) {
      _dropPeer(id);
    }
    for (final MediaStreamTrack t in <MediaStreamTrack>[...?_local?.getTracks(), ...?_screen?.getTracks()]) {
      t.stop();
    }
    _local?.dispose();
    _localView.srcObject = null;
    _localView.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Layout

  String get _statusLine {
    if (_connectedAt != null && _peers.values.any((p) => p.connected)) {
      final d = DateTime.now().difference(_connectedAt!);
      final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return d.inHours > 0 ? "${d.inHours}:$mm:$ss" : "$mm:$ss";
    }
    return _status;
  }

  Widget _avatar(Map<String, dynamic>? p, double size) {
    final name = (p?['full_name'] ?? '?').toString();
    final photo = (p?['photo'] ?? '').toString();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFF4A148C),
      backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
      child: photo.isEmpty ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.bold)) : null,
    );
  }

  Widget _tile(String id, {bool me = false}) {
    final info = _people[id];
    final peer = _peers[id];
    final camOn = me ? (_cam || _sharing) : (info?['cam_on'] == true && (peer?.hasVideo ?? false));
    final micOn = me ? _mic : info?['mic_on'] != false;
    final name = me ? 'You' : (info?['full_name'] ?? '…').toString();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: const Color(0xFF221B2E),
        child: Stack(fit: StackFit.expand, children: [
          if (camOn)
            RTCVideoView(me ? _localView : peer!.renderer, mirror: me && !_sharing, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          else
            Center(child: LayoutBuilder(builder: (_, c) => _avatar(me ? _people[_me] : info, (c.maxHeight * 0.4).clamp(40.0, 110.0)))),
          // keep the remote sound playing even when the picture is hidden
          if (!me && !camOn && peer != null) Positioned(left: 0, top: 0, width: 1, height: 1, child: Opacity(opacity: 0, child: RTCVideoView(peer.renderer))),
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: Row(children: [
              if (!micOn) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.mic_off_rounded, size: 16, color: Colors.redAccent)),
              Flexible(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5, shadows: [Shadow(blurRadius: 4)])),
              ),
              if (!me && peer != null && !peer.connected)
                const Padding(padding: EdgeInsets.only(left: 6), child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap, {bool on = true, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Material(
          color: color ?? (on ? Colors.white.withValues(alpha: 0.14) : Colors.white),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 54, height: 54, child: Icon(icon, color: color != null ? Colors.white : (on ? Colors.white : Colors.black87))),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inCall = _people.entries
        .where((e) => e.key != _me && (e.value['state'] == 'joined' || _peers.containsKey(e.key)))
        .map((e) => e.key)
        .toList();
    final ringing = _people.entries.where((e) => e.key != _me && e.value['state'] == 'ringing').length;
    final tiles = [...inCall.map((id) => _tile(id)), _tile(_me, me: true)];

    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangUp();
      },
      child: Scaffold(
        backgroundColor: _kCallBg,
        body: SafeArea(
          child: _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white))),
                    TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text("Close")),
                  ]),
                )
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Column(children: [
                      Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(
                        [_statusLine, if (ringing > 0 && inCall.isNotEmpty) "$ringing still ringing"].join(' · '),
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: inCall.isEmpty
                          ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              _avatar(_people.entries.where((e) => e.key != _me).map((e) => e.value).firstOrNull, 110),
                              const SizedBox(height: 14),
                              Text(_status, style: const TextStyle(color: Colors.white70)),
                              const SizedBox(height: 18),
                              if (_cam) SizedBox(width: 160, height: 220, child: _tile(_me, me: true)),
                            ])
                          : LayoutBuilder(builder: (_, c) {
                              final n = tiles.length;
                              final wide = c.maxWidth > c.maxHeight;
                              final cols = n <= 1 ? 1 : (n <= 2 ? (wide ? 2 : 1) : (n <= 4 ? 2 : 3));
                              final rows = (n / cols).ceil();
                              final h = (c.maxHeight - (rows - 1) * 8) / rows;
                              final w = (c.maxWidth - (cols - 1) * 8) / cols;
                              return Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                                for (final t in tiles) SizedBox(width: w, height: h, child: t),
                              ]);
                            }),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _btn(_mic ? Icons.mic_rounded : Icons.mic_off_rounded, _mic ? "Mute" : "Unmute", _toggleMic, on: _mic),
                        _btn(_cam ? Icons.videocam_rounded : Icons.videocam_off_rounded, "Camera", _toggleCam, on: _cam),
                        if (_mobile && _cam) _btn(Icons.cameraswitch_rounded, "Flip", _switchCamera),
                        if (_mobile) _btn(_speaker ? Icons.volume_up_rounded : Icons.hearing_rounded, _speaker ? "Speaker" : "Phone", _toggleSpeaker, on: _speaker),
                        if (!_mobile) _btn(Icons.screen_share_rounded, _sharing ? "Stop sharing" : "Share screen", _toggleShare, on: !_sharing),
                        _btn(Icons.call_end_rounded, "End", _hangUp, color: Colors.red.shade600),
                      ]),
                    ),
                  ),
                ]),
        ),
      ),
    );
  }
}

/// Full-screen ringing: Answer / Decline.
class IncomingCallScreen extends StatefulWidget {
  final Map<String, dynamic> info;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;
  final VoidCallback onGone;
  const IncomingCallScreen({super.key, required this.info, required this.onAnswer, required this.onDecline, required this.onGone});
  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  RealtimeChannel? _ch;
  Timer? _giveUp;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final db = Supabase.instance.client;
    final id = widget.info['call_id'].toString();
    // stop ringing when the caller hangs up or someone else's answer ends it
    _ch = db
        .channel('call-ring-$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_calls',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
          callback: (p) {
            final s = p.newRecord['status'];
            if (s == 'ended' || s == 'missed' || s == 'declined') _gone();
          },
        )
        .subscribe();
    _giveUp = Timer(const Duration(seconds: 50), _gone);
  }

  void _gone() {
    if (_done) return;
    _done = true;
    widget.onGone();
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    final ch = _ch;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.info;
    final video = i['kind'] == 'video';
    final group = i['is_group'] == true;
    final name = (i['caller_name'] ?? 'Someone').toString();
    final photo = (i['caller_photo'] ?? '').toString();
    return Scaffold(
      backgroundColor: _kCallBg.withValues(alpha: 0.97),
      body: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
              radius: 56,
              backgroundColor: const Color(0xFF4A148C),
              backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
              child: photo.isEmpty ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)) : null,
            ),
            const SizedBox(height: 16),
            Text(name, textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              group ? (video ? "Video chat in ${i['room_name']}" : "Voice chat in ${i['room_name']}") : (video ? "Video call" : "Voice call"),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 40),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _round(Icons.call_end_rounded, "Decline", Colors.red.shade600, () {
                _done = true;
                widget.onDecline();
              }),
              const SizedBox(width: 48),
              _round(video ? Icons.videocam_rounded : Icons.call_rounded, "Answer", Colors.green.shade600, () {
                _done = true;
                widget.onAnswer();
              }),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _round(IconData icon, String label, Color color, VoidCallback onTap) => Column(mainAxisSize: MainAxisSize.min, children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 68, height: 68, child: Icon(icon, color: Colors.white, size: 30))),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ]);
}
