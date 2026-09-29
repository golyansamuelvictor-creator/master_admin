import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class MediaPlayerScreen extends StatefulWidget {
  final dynamic mediaItem;
  const MediaPlayerScreen({super.key, required this.mediaItem});

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    
    // In V9, we extract the ID differently or use the full URL
    final url = widget.mediaItem['media_url'] ?? "";
    
    _controller = YoutubePlayerController.fromVideoId(
      videoId: YoutubePlayerController.convertUrlToId(url) ?? "",
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          const Spacer(),
          // In V9, the player widget is simplified
          YoutubePlayer(
            controller: _controller,
            aspectRatio: 16 / 9,
          ),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(25, 35, 25, 50),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.mediaItem['title'] ?? "Unknown Title",
                              style: GoogleFonts.merriweather(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20)),
                          const SizedBox(height: 5),
                          Text(widget.mediaItem['artist'] ?? "Unknown Artist",
                              style: GoogleFonts.merriweather(
                                  fontSize: 15, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    const Icon(Icons.favorite_border,
                        color: Colors.grey, size: 28),
                  ],
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _utilBtn(Icons.share, "Share"),
                    _utilBtn(Icons.playlist_add, "Add to List"),
                    _utilBtn(Icons.download_for_offline, "Download"),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _utilBtn(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey[800], size: 24),
        const SizedBox(height: 8),
        Text(label,
            style: GoogleFonts.merriweather(
                fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }

  @override
  void dispose() {
    // Note: In some V9 configurations, close() is used instead of dispose()
    // but the controller handles most cleanup internally now.
    super.dispose();
  }
}