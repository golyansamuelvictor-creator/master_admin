// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../services/media_playback.dart';
import '../services/media_service.dart';

/// Full player (VLC-style): seek bar, ±10 s, previous / next, shuffle,
/// repeat, speed, volume, aspect ratio, sleep timer, full screen, queue,
/// lyrics and details. Keyboard: Space play/pause, ←/→ 10 s, ↑/↓ volume,
/// M mute, F full screen, N next, P previous, Esc leave full screen.
class MediaFullPlayer extends StatefulWidget {
  const MediaFullPlayer({super.key});

  @override
  State<MediaFullPlayer> createState() => _MediaFullPlayerState();
}

class _MediaFullPlayerState extends State<MediaFullPlayer> {
  final pb = MediaPlayback.instance;
  final _focus = FocusNode();
  bool _fullscreen = false;
  bool _controlsVisible = true;
  double? _drag; // seconds while dragging the seek bar
  int _tab = 0; // 0 up next, 1 lyrics, 2 details

  static const Color _accent = Color(0xFF7C4DFF);

  @override
  void initState() {
    super.initState();
    pb.setFullPlayerOpen(true);
  }

  @override
  void dispose() {
    pb.setFullPlayerOpen(false);
    if (_fullscreen) _exitFullscreen();
    _focus.dispose();
    super.dispose();
  }

  void _enterFullscreen() {
    setState(() => _fullscreen = true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if ((pb.controller?.value.aspectRatio ?? 1.7) > 1.1) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    if (mounted) setState(() => _fullscreen = false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space) {
      pb.toggle();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      pb.seekBy(10);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      pb.seekBy(-10);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      pb.setVolume(pb.volume + 0.1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      pb.setVolume(pb.volume - 0.1);
    } else if (k == LogicalKeyboardKey.keyM) {
      pb.toggleMute();
    } else if (k == LogicalKeyboardKey.keyN) {
      pb.next();
    } else if (k == LogicalKeyboardKey.keyP) {
      pb.previous();
    } else if (k == LogicalKeyboardKey.keyF && (pb.current?.isVideo ?? false)) {
      _fullscreen ? _exitFullscreen() : _enterFullscreen();
    } else if (k == LogicalKeyboardKey.escape && _fullscreen) {
      _exitFullscreen();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: AnimatedBuilder(
        animation: pb,
        builder: (context, _) {
          final item = pb.current;
          if (item == null) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text("Nothing is playing.")),
            );
          }
          if (_fullscreen && item.isVideo) return _fullscreenView();
          return LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 900;
            return Scaffold(
              backgroundColor: const Color(0xFF0E0B16),
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  tooltip: "Minimise (keeps playing)",
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text("Now playing", style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.bold)),
                centerTitle: true,
                actions: [
                  IconButton(
                    tooltip: "Stop and close",
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () async {
                      await pb.stop();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
              body: SafeArea(
                child: wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                            child: Column(children: [
                              _stage(item, maxHeight: c.maxHeight * 0.6),
                              const SizedBox(height: 16),
                              _titleBlock(item),
                              const SizedBox(height: 12),
                              _controls(item, wide: true),
                            ]),
                          ),
                        ),
                        Container(width: 1, color: Colors.white12),
                        SizedBox(width: 360, child: _sidePanel(item)),
                      ])
                    : Column(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: _stage(item, maxHeight: c.maxHeight * 0.38),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: Column(children: [_titleBlock(item), const SizedBox(height: 6), _controls(item, wide: false)]),
                        ),
                        Expanded(child: _sidePanel(item)),
                      ]),
              ),
            );
          });
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  Widget _video(VideoPlayerController c) {
    final size = c.value.size;
    return AspectRatio(
      aspectRatio: pb.videoAspect(),
      child: ClipRect(
        child: FittedBox(
          fit: pb.videoFit(),
          child: SizedBox(
            width: size.width > 0 ? size.width : 1600,
            height: size.height > 0 ? size.height : 900,
            child: VideoPlayer(c),
          ),
        ),
      ),
    );
  }

  Widget _stage(MediaItem item, {required double maxHeight}) {
    final c = pb.controller;
    Widget inner;
    if (pb.loading) {
      inner = const AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator(color: Colors.white)));
    } else if (pb.error != null) {
      inner = AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(pb.error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          ),
        ),
      );
    } else if (item.isVideo && c != null && c.value.isInitialized) {
      inner = GestureDetector(onTap: pb.toggle, onDoubleTap: _enterFullscreen, child: _video(c));
    } else {
      inner = _artwork(item, maxHeight);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(color: Colors.black, child: Center(child: inner))),
    );
  }

  Widget _artwork(MediaItem item, double maxHeight) {
    final thumb = MediaService.cachedLink(item.thumbnailPath) ?? item.legacyThumbUrl;
    final side = maxHeight.clamp(140.0, 360.0).toDouble();
    return Container(
      width: double.infinity,
      height: side,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF1A237E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Center(
        child: Container(
          width: side * 0.72,
          height: side * 0.72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white10,
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 8))],
            image: thumb == null ? null : DecorationImage(image: NetworkImage(thumb), fit: BoxFit.cover),
          ),
          child: thumb == null ? Icon(Icons.music_note_rounded, size: side * 0.3, color: Colors.white70) : null,
        ),
      ),
    );
  }

  Widget _titleBlock(MediaItem item) => Column(children: [
        Text(item.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.merriweather(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white)),
        if ((item.artist ?? '').isNotEmpty || (item.album ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text([item.artist, item.album].where((e) => (e ?? '').isNotEmpty).join(' · '),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
      ]);

  Widget _seekBar({bool compact = false}) {
    final c = pb.controller;
    final dur = (c != null && c.value.isInitialized) ? c.value.duration : Duration.zero;
    final pos = c?.value.position ?? Duration.zero;
    final maxS = dur.inMilliseconds / 1000.0;
    final value = (_drag ?? pos.inMilliseconds / 1000.0).clamp(0.0, maxS > 0 ? maxS : 1.0).toDouble();
    double buffered = 0;
    if (c != null && c.value.buffered.isNotEmpty) buffered = c.value.buffered.last.end.inMilliseconds / 1000.0;
    return Column(children: [
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: compact ? 2.5 : 3.5,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: compact ? 6 : 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          activeTrackColor: _accent,
          inactiveTrackColor: Colors.white24,
          secondaryActiveTrackColor: Colors.white38,
          thumbColor: Colors.white,
        ),
        child: Slider(
          value: value,
          max: maxS > 0 ? maxS : 1.0,
          secondaryTrackValue: maxS > 0 ? buffered.clamp(0.0, maxS).toDouble() : null,
          onChanged: maxS > 0 ? (v) => setState(() => _drag = v) : null,
          onChangeEnd: (v) {
            pb.seekTo(Duration(milliseconds: (v * 1000).round()));
            setState(() => _drag = null);
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(children: [
          Text(MediaService.formatDuration(Duration(milliseconds: (value * 1000).round())), style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
          const Spacer(),
          Text(MediaService.formatDuration(dur), style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
        ]),
      ),
    ]);
  }

  Widget _controls(MediaItem item, {required bool wide}) {
    final playing = pb.isPlaying;
    Widget btn(IconData i, String tip, VoidCallback? onTap, {double size = 26, Color color = Colors.white, bool active = false}) => IconButton(
          tooltip: tip,
          iconSize: size,
          onPressed: onTap,
          icon: Icon(i, color: active ? _accent : color),
        );
    final repeatIcon = pb.repeat == MediaRepeat.one ? Icons.repeat_one_rounded : Icons.repeat_rounded;
    return Column(children: [
      _seekBar(),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          btn(Icons.shuffle_rounded, pb.shuffle ? "Shuffle on" : "Shuffle off", pb.toggleShuffle, size: 22, active: pb.shuffle, color: Colors.white60),
          btn(Icons.skip_previous_rounded, "Previous (P)", pb.previous, size: 32),
          btn(Icons.replay_10_rounded, "Back 10 s (←)", () => pb.seekBy(-10)),
          const SizedBox(width: 6),
          Container(
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: IconButton(
              tooltip: playing ? "Pause (Space)" : "Play (Space)",
              iconSize: 38,
              onPressed: pb.controller == null ? null : pb.toggle,
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: const Color(0xFF0E0B16)),
            ),
          ),
          const SizedBox(width: 6),
          btn(Icons.forward_10_rounded, "Forward 10 s (→)", () => pb.seekBy(10)),
          btn(Icons.skip_next_rounded, "Next (N)", pb.next, size: 32),
          btn(repeatIcon, switch (pb.repeat) { MediaRepeat.off => "Repeat off", MediaRepeat.all => "Repeat all", MediaRepeat.one => "Repeat one" },
              pb.cycleRepeat,
              size: 22, active: pb.repeat != MediaRepeat.off, color: Colors.white60),
        ]),
      ),
      const SizedBox(height: 4),
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, runSpacing: 2, children: [
        // volume
        btn(pb.muted || pb.volume == 0 ? Icons.volume_off_rounded : (pb.volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
            pb.muted ? "Unmute (M)" : "Mute (M)", pb.toggleMute,
            size: 22, color: Colors.white70),
        if (wide)
          SizedBox(
            width: 120,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: Colors.white70,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(value: pb.muted ? 0 : pb.volume, onChanged: pb.setVolume),
            ),
          ),
        _speedMenu(),
        if (item.isVideo) _aspectMenu(),
        _sleepMenu(),
        if (item.isVideo)
          btn(pb.popupVideo ? Icons.picture_in_picture_alt_rounded : Icons.picture_in_picture_alt_outlined,
              pb.popupVideo ? "Pop-up video on (keeps showing when you leave)" : "Pop-up video off (audio only when you leave)",
              () => pb.setPopupVideo(!pb.popupVideo),
              size: 22, active: pb.popupVideo, color: Colors.white70),
        if (item.isVideo) btn(Icons.fullscreen_rounded, "Full screen (F)", _enterFullscreen, size: 24, color: Colors.white70),
      ]),
    ]);
  }

  Widget _chipMenu<T>({required String label, required IconData icon, required List<(T, String)> options, required T current, required ValueChanged<T> onSelected, required String tooltip}) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      initialValue: current,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final o in options)
          PopupMenuItem<T>(
            value: o.$1,
            child: Row(children: [
              SizedBox(width: 22, child: o.$1 == current ? const Icon(Icons.check_rounded, size: 18) : null),
              const SizedBox(width: 6),
              Text(o.$2),
            ]),
          ),
      ],
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _speedMenu() => _chipMenu<double>(
        tooltip: "Playback speed",
        label: "${pb.speed == pb.speed.roundToDouble() ? pb.speed.toStringAsFixed(0) : pb.speed}×",
        icon: Icons.speed_rounded,
        current: pb.speed,
        options: const [(0.25, '0.25×'), (0.5, '0.5×'), (0.75, '0.75×'), (1.0, 'Normal'), (1.25, '1.25×'), (1.5, '1.5×'), (1.75, '1.75×'), (2.0, '2×')],
        onSelected: pb.setSpeed,
      );

  Widget _aspectMenu() => _chipMenu<String>(
        tooltip: "Picture size / aspect ratio",
        label: switch (pb.aspect) { 'fit' => 'Fit', 'fill' => 'Fill', 'stretch' => 'Stretch', _ => pb.aspect },
        icon: Icons.aspect_ratio_rounded,
        current: pb.aspect,
        options: const [('fit', 'Best fit'), ('fill', 'Fill (crop)'), ('stretch', 'Stretch'), ('16:9', '16:9'), ('4:3', '4:3'), ('1:1', '1:1')],
        onSelected: pb.setAspect,
      );

  Widget _sleepMenu() {
    final left = pb.sleepAt?.difference(DateTime.now());
    return _chipMenu<int>(
      tooltip: "Sleep timer",
      label: left == null ? "Sleep" : "${left.inMinutes + 1} min",
      icon: Icons.bedtime_outlined,
      current: left == null ? 0 : -1,
      options: const [(0, 'Off'), (10, '10 minutes'), (15, '15 minutes'), (30, '30 minutes'), (45, '45 minutes'), (60, '1 hour')],
      onSelected: (m) => pb.setSleepTimer(m == 0 ? null : m),
    );
  }

  Widget _sidePanel(MediaItem item) {
    final tabs = ['Up next', 'Lyrics', 'Details'];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          for (int i = 0; i < tabs.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(tabs[i], style: TextStyle(color: _tab == i ? Colors.white : Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                selected: _tab == i,
                selectedColor: _accent,
                backgroundColor: Colors.white10,
                side: const BorderSide(color: Colors.white24),
                onSelected: (_) => setState(() => _tab = i),
              ),
            ),
        ]),
      ),
      Expanded(
        child: switch (_tab) {
          0 => ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              itemCount: pb.queue.length,
              itemBuilder: (_, i) {
                final m = pb.queue[i];
                final now = i == pb.currentIndex;
                return ListTile(
                  dense: true,
                  selected: now,
                  selectedTileColor: Colors.white10,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: Icon(now ? Icons.graphic_eq_rounded : (m.isVideo ? Icons.movie_outlined : Icons.music_note_outlined),
                      color: now ? _accent : Colors.white54),
                  title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: now ? Colors.white : Colors.white70, fontWeight: now ? FontWeight.bold : FontWeight.normal)),
                  subtitle: (m.artist ?? '').isEmpty
                      ? null
                      : Text(m.artist!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38)),
                  trailing: m.durationSeconds == null
                      ? null
                      : Text(MediaService.formatDuration(Duration(seconds: m.durationSeconds!)), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  onTap: () => pb.playAt(i),
                );
              },
            ),
          1 => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Text(
                (item.lyrics ?? '').trim().isEmpty ? "No lyrics were added for this item." : item.lyrics!,
                style: GoogleFonts.merriweather(color: Colors.white.withValues(alpha: 0.85), fontSize: 14.5, height: 1.7),
              ),
            ),
          _ => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
              _detail("Title", item.title),
              _detail("Artist / minister", item.artist),
              _detail("Album", item.album),
              _detail("Language", item.language),
              _detail("Type", item.isVideo ? "Video" : "Audio"),
              if (item.tags.isNotEmpty) _detail("Tags", item.tags.join(', ')),
              _detail("Played", "${item.playCount} times"),
              if ((item.description ?? '').isNotEmpty) _detail("About", item.description),
              const SizedBox(height: 12),
              const Text("Media plays inside the app only and can't be downloaded.",
                  style: TextStyle(color: Colors.white38, fontSize: 11.5, fontStyle: FontStyle.italic)),
            ]),
        },
      ),
    ]);
  }

  Widget _detail(String k, String? v) => (v ?? '').trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 2),
            Text(v!, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
          ]),
        );

  // ------------------------------------------------------------------
  Widget _fullscreenView() {
    final c = pb.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        onDoubleTap: _exitFullscreen,
        child: Stack(fit: StackFit.expand, children: [
          Center(child: c != null && c.value.isInitialized ? _video(c) : const CircularProgressIndicator(color: Colors.white)),
          if (_controlsVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 30, 8, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(pb.current?.title ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    _seekBar(compact: true),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(onPressed: pb.previous, icon: const Icon(Icons.skip_previous_rounded, color: Colors.white)),
                        IconButton(onPressed: () => pb.seekBy(-10), icon: const Icon(Icons.replay_10_rounded, color: Colors.white)),
                        IconButton(onPressed: pb.toggle, icon: Icon(pb.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 34)),
                        IconButton(onPressed: () => pb.seekBy(10), icon: const Icon(Icons.forward_10_rounded, color: Colors.white)),
                        IconButton(onPressed: pb.next, icon: const Icon(Icons.skip_next_rounded, color: Colors.white)),
                        const SizedBox(width: 8),
                        _speedMenu(),
                        _aspectMenu(),
                        IconButton(onPressed: _exitFullscreen, icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
