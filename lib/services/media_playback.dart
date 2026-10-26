import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'media_service.dart';

/// Lets the mini player (which sits above every screen) open the full player.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

enum MediaRepeat { off, all, one }

/// The one media player for the whole app.
///
/// Playback keeps going while you move around the app (the mini player shows
/// it), and in the background where the platform allows it. Files are played
/// from short-lived private links; there is no download.
class MediaPlayback extends ChangeNotifier {
  MediaPlayback._();
  static final MediaPlayback instance = MediaPlayback._();

  VideoPlayerController? controller;
  List<MediaItem> _queue = [];
  List<int> _order = []; // play order (shuffled or not)
  int _pos = 0; // position in _order
  bool shuffle = false;
  MediaRepeat repeat = MediaRepeat.off;
  double speed = 1.0;
  double volume = 1.0;
  bool muted = false;
  String aspect = 'fit'; // fit | fill | stretch | 16:9 | 4:3 | 1:1
  bool fullPlayerOpen = false;
  bool popupVideo = true; // video keeps showing in a small floating window
  bool loading = false;
  String? error;
  DateTime? sleepAt;
  Timer? _sleepTimer;
  bool _endHandled = false;
  bool _playRecorded = false;
  int _loadToken = 0;

  List<MediaItem> get queue => _queue;
  MediaItem? get current => _queue.isEmpty || _order.isEmpty ? null : _queue[_order[_pos]];
  int get currentIndex => _order.isEmpty ? -1 : _order[_pos];
  bool get hasMedia => current != null;
  bool get isPlaying => controller?.value.isPlaying ?? false;
  bool get showMini => hasMedia && !fullPlayerOpen;

  Future<void> playQueue(List<MediaItem> items, {int start = 0, bool shuffled = false}) async {
    final playable = items.where((m) => !m.isYoutube && (m.storagePath ?? '').isNotEmpty).toList();
    if (playable.isEmpty) return;
    final startItem = start < items.length ? items[start] : playable.first;
    _queue = playable;
    shuffle = shuffled;
    final startIdx = max(0, _queue.indexWhere((m) => m.id == startItem.id));
    _buildOrder(startIdx);
    await _load();
  }

  void _buildOrder(int startIdx) {
    _order = List.generate(_queue.length, (i) => i);
    if (shuffle) {
      _order.remove(startIdx);
      _order.shuffle();
      _order.insert(0, startIdx);
      _pos = 0;
    } else {
      _pos = startIdx;
    }
  }

  Future<void> playAt(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= _queue.length) return;
    final p = _order.indexOf(queueIndex);
    _pos = p < 0 ? 0 : p;
    await _load();
  }

  Future<void> _load() async {
    final item = current;
    if (item == null) return;
    final token = ++_loadToken;
    loading = true;
    error = null;
    _endHandled = false;
    _playRecorded = false;
    notifyListeners();

    final old = controller;
    controller = null;
    old?.removeListener(_onTick);
    await old?.pause();
    await old?.dispose();

    final url = await MediaService.link(item.storagePath);
    if (token != _loadToken) return;
    if (url == null) {
      loading = false;
      error = "This file can't be played right now.";
      notifyListeners();
      return;
    }
    final c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true, mixWithOthers: false),
    );
    try {
      await c.initialize();
    } catch (e) {
      if (token != _loadToken) return;
      loading = false;
      error = "This file can't be played. It may be in a format this device doesn't support.";
      await c.dispose();
      notifyListeners();
      return;
    }
    if (token != _loadToken) {
      await c.dispose();
      return;
    }
    controller = c;
    await c.setLooping(repeat == MediaRepeat.one);
    await c.setPlaybackSpeed(speed);
    await c.setVolume(muted ? 0 : volume);
    c.addListener(_onTick);
    loading = false;
    notifyListeners();
    await c.play();
  }

  void _onTick() {
    final c = controller;
    if (c == null) return;
    final v = c.value;
    if (!_playRecorded && v.isPlaying && v.position > const Duration(seconds: 5)) {
      _playRecorded = true;
      final item = current;
      if (item != null) MediaService.recordPlay(item.id, v.duration.inSeconds > 0 ? v.duration.inSeconds : null);
    }
    final ended = v.isInitialized &&
        v.duration > Duration.zero &&
        !v.isPlaying &&
        v.position >= v.duration - const Duration(milliseconds: 400);
    if (ended && !_endHandled && repeat != MediaRepeat.one) {
      _endHandled = true;
      next(auto: true);
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    final c = controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      if (c.value.position >= c.value.duration - const Duration(milliseconds: 400)) await c.seekTo(Duration.zero);
      _endHandled = false;
      await c.play();
    }
    notifyListeners();
  }

  Future<void> seekTo(Duration d) async {
    final c = controller;
    if (c == null) return;
    final dur = c.value.duration;
    await c.seekTo(d < Duration.zero ? Duration.zero : (d > dur ? dur : d));
    _endHandled = false;
  }

  Future<void> seekBy(int seconds) async {
    final c = controller;
    if (c == null) return;
    await seekTo(c.value.position + Duration(seconds: seconds));
  }

  Future<void> next({bool auto = false}) async {
    if (_order.isEmpty) return;
    if (_pos < _order.length - 1) {
      _pos++;
    } else if (repeat == MediaRepeat.all) {
      _pos = 0; // start the list again
    } else {
      notifyListeners();
      return; // end of the list
    }
    await _load();
  }

  Future<void> previous() async {
    final c = controller;
    if (c != null && c.value.position > const Duration(seconds: 3)) {
      await seekTo(Duration.zero);
      return;
    }
    if (_pos > 0) {
      _pos--;
    } else if (repeat == MediaRepeat.all) {
      _pos = _order.length - 1;
    } else {
      await seekTo(Duration.zero);
      return;
    }
    await _load();
  }

  Future<void> setSpeed(double s) async {
    speed = s;
    await controller?.setPlaybackSpeed(s);
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0).toDouble();
    if (volume > 0) muted = false;
    await controller?.setVolume(muted ? 0 : volume);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    muted = !muted;
    await controller?.setVolume(muted ? 0 : volume);
    notifyListeners();
  }

  Future<void> cycleRepeat() async {
    repeat = MediaRepeat.values[(repeat.index + 1) % MediaRepeat.values.length];
    await controller?.setLooping(repeat == MediaRepeat.one);
    notifyListeners();
  }

  void toggleShuffle() {
    if (_queue.isEmpty) return;
    final cur = currentIndex;
    shuffle = !shuffle;
    _buildOrder(cur);
    if (!shuffle) _pos = _order.indexOf(cur);
    notifyListeners();
  }

  void setAspect(String a) {
    aspect = a;
    notifyListeners();
  }

  void setPopupVideo(bool v) {
    popupVideo = v;
    notifyListeners();
  }

  void setFullPlayerOpen(bool open) {
    if (fullPlayerOpen == open) return;
    fullPlayerOpen = open;
    // notify after the current frame (called from initState / dispose)
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  /// Stop after [minutes] (null cancels).
  void setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    if (minutes == null) {
      sleepAt = null;
    } else {
      sleepAt = DateTime.now().add(Duration(minutes: minutes));
      _sleepTimer = Timer(Duration(minutes: minutes), () async {
        await controller?.pause();
        sleepAt = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _loadToken++;
    _sleepTimer?.cancel();
    sleepAt = null;
    final c = controller;
    controller = null;
    c?.removeListener(_onTick);
    await c?.pause();
    await c?.dispose();
    _queue = [];
    _order = [];
    _pos = 0;
    loading = false;
    error = null;
    notifyListeners();
  }

  /// Aspect ratio to draw the video at.
  double videoAspect() {
    final c = controller;
    final natural = (c != null && c.value.isInitialized && c.value.aspectRatio > 0) ? c.value.aspectRatio : 16 / 9;
    switch (aspect) {
      case '16:9':
        return 16 / 9;
      case '4:3':
        return 4 / 3;
      case '1:1':
        return 1;
      default:
        return natural;
    }
  }

  BoxFit videoFit() => switch (aspect) {
        'fill' => BoxFit.cover,
        'stretch' || '16:9' || '4:3' || '1:1' => BoxFit.fill,
        _ => BoxFit.contain,
      };
}
