import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:video_player/video_player.dart';

import '../screens/media_full_player.dart';
import '../services/media_playback.dart';
import '../services/media_service.dart';

/// Shown above every screen while something plays and the full player is
/// closed: a slim bar for audio, or a small draggable pop-up window for video.
class MediaMiniPlayer extends StatefulWidget {
  const MediaMiniPlayer({super.key});

  @override
  State<MediaMiniPlayer> createState() => _MediaMiniPlayerState();
}

class _MediaMiniPlayerState extends State<MediaMiniPlayer> {
  final pb = MediaPlayback.instance;
  Offset? _popupPos; // top-left of the floating video window

  void _openFull() {
    appNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const MediaFullPlayer()));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pb,
      builder: (context, _) {
        if (!pb.showMini) return const SizedBox.shrink();
        final item = pb.current!;
        final c = pb.controller;
        return LayoutBuilder(builder: (context, box) {
          final pad = MediaQuery.of(context).padding;
          final videoPopup = item.isVideo && pb.popupVideo && c != null && c.value.isInitialized;
          if (videoPopup) return Stack(children: [_popup(box, pad, c)]);
          final wide = box.maxWidth >= 700;
          return Stack(children: [
            Positioned(
              left: wide ? null : 10,
              right: wide ? 16 : 10,
              bottom: 10 + pad.bottom,
              width: wide ? 420 : null,
              child: _bar(item, c),
            ),
          ]);
        });
      },
    );
  }

  Widget _progress(VideoPlayerController? c) {
    if (c == null || !c.value.isInitialized || c.value.duration == Duration.zero) {
      return const LinearProgressIndicator(minHeight: 2.5);
    }
    final v = c.value.position.inMilliseconds / c.value.duration.inMilliseconds;
    return LinearProgressIndicator(
      value: v.clamp(0.0, 1.0).toDouble(),
      minHeight: 2.5,
      backgroundColor: Colors.white24,
      valueColor: const AlwaysStoppedAnimation(Color(0xFFB388FF)),
    );
  }

  Widget _bar(MediaItem item, VideoPlayerController? c) {
    final thumb = MediaService.cachedLink(item.thumbnailPath) ?? item.legacyThumbUrl;
    return Material(
      color: const Color(0xFF1E1530),
      elevation: 10,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openFull,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _progress(c),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 42,
                  height: 42,
                  color: const Color(0xFF4A148C),
                  child: thumb == null
                      ? Icon(item.isVideo ? Icons.movie_rounded : Icons.music_note_rounded, color: Colors.white70)
                      : Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded, color: Colors.white70)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(item.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(
                    pb.error ?? (pb.loading ? 'Loading…' : (item.artist ?? (item.isVideo ? 'Video (audio only)' : ''))),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: pb.error != null ? Colors.red.shade200 : Colors.white60, fontSize: 11.5),
                  ),
                ]),
              ),
              IconButton(onPressed: pb.previous, icon: const Icon(Icons.skip_previous_rounded, color: Colors.white)),
              IconButton(
                onPressed: pb.controller == null ? null : pb.toggle,
                icon: Icon(pb.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: Colors.white, size: 34),
              ),
              IconButton(onPressed: pb.next, icon: const Icon(Icons.skip_next_rounded, color: Colors.white)),
              IconButton(onPressed: pb.stop, icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _popup(BoxConstraints box, EdgeInsets pad, VideoPlayerController c) {
    final w = (box.maxWidth * (box.maxWidth < 600 ? 0.62 : 0.28)).clamp(200.0, 380.0).toDouble();
    final aspect = c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9;
    final h = w / aspect + 40;
    final maxX = (box.maxWidth - w - 8).clamp(8.0, double.infinity).toDouble();
    final maxY = (box.maxHeight - h - 8 - pad.bottom).clamp(8.0 + pad.top, double.infinity).toDouble();
    final pos = _popupPos ?? Offset(maxX - 8, maxY - 8);
    final x = pos.dx.clamp(8.0, maxX).toDouble();
    final y = pos.dy.clamp(8.0 + pad.top, maxY).toDouble();
    return Positioned(
      left: x,
      top: y,
      width: w,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _popupPos = Offset(x + d.delta.dx, y + d.delta.dy)),
        child: Material(
          color: Colors.black,
          elevation: 14,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: _openFull,
              child: AspectRatio(aspectRatio: aspect, child: VideoPlayer(c)),
            ),
            _progress(c),
            SizedBox(
              height: 36,
              child: Row(children: [
                const SizedBox(width: 6),
                const Icon(Icons.drag_indicator_rounded, color: Colors.white38, size: 18),
                Expanded(
                  child: Text(pb.current?.title ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: pb.toggle,
                  icon: Icon(pb.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 20),
                ),
                IconButton(padding: EdgeInsets.zero, onPressed: _openFull, icon: const Icon(Icons.open_in_full_rounded, color: Colors.white, size: 18)),
                IconButton(padding: EdgeInsets.zero, onPressed: pb.stop, icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
