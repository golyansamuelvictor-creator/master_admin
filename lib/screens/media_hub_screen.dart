import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'media_player_screen.dart';
import 'package:master_admin/core/app_palette.dart';

class MediaHubScreen extends StatefulWidget {
  final String title;
  final String userEmail;
  final String userRole;

  const MediaHubScreen({
    super.key,
    required this.title,
    required this.userEmail,
    required this.userRole,
  });

  @override
  State<MediaHubScreen> createState() => _MediaHubScreenState();
}

class _MediaHubScreenState extends State<MediaHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0,
        title: Text("Media Hub",
            style: GoogleFonts.merriweather(
                fontWeight: FontWeight.w900, // FIXED: black changed to w900
                fontSize: 18,
                color: AppPalette.fg(const Color(0xFF0D47A1)))),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF0D47A1),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF0D47A1),
          indicatorWeight: 3,
          labelStyle: GoogleFonts.merriweather(
              fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [Tab(text: "Music"), Tab(text: "Videos")],
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMediaList("Music"),
                _buildMediaList("Video"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), // FIXED: withValues
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: GoogleFonts.merriweather(fontSize: 14),
        decoration: InputDecoration(
          hintText: "Search title or artist...",
          hintStyle: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey), fontSize: 13),
          prefixIcon: Icon(Icons.search, color: AppPalette.fg(Color(0xFF0D47A1))),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = "");
                  })
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildMediaList(String category) {
    return FutureBuilder(
      future: _searchQuery.isEmpty
          ? _supabase
              .from('media_library')
              .select()
              .eq('category', category)
              .order('created_at')
          : _supabase
              .from('media_library')
              .select()
              .eq('category', category)
              .ilike('title', '%$_searchQuery%'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } // FIXED: Added braces {}

        if (!snapshot.hasData || (snapshot.data as List).isEmpty) {
          return Center(
              child: Text("No items found",
                  style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey))));
        }

        final data = snapshot.data as List<dynamic>;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: data.length,
          itemBuilder: (context, index) => _buildMediaCard(data[index]),
        );
      },
    );
  }

  Widget _buildMediaCard(dynamic item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03), // FIXED: withValues
              blurRadius: 10,
              offset: const Offset(0, 5))
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (c) => MediaPlayerScreen(mediaItem: item))),
        child: Row(
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(20)),
              child: CachedNetworkImage(
                imageUrl: item['thumbnail_url'] ?? "",
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                placeholder: (c, u) => Container(color: AppPalette.bg(Colors.grey[200])),
                errorWidget: (c, u, e) => Container(
                    color: AppPalette.bg(Colors.grey[300]),
                    child: const Icon(Icons.music_note)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['title'],
                        style: GoogleFonts.merriweather(
                            fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(item['artist'] ?? "Unknown",
                        style: GoogleFonts.merriweather(
                            fontSize: 12, color: AppPalette.fg(Colors.grey[600]))),
                  ],
                ),
              ),
            ),
            Padding(
                padding: EdgeInsets.only(right: 15),
                child: Icon(Icons.play_circle_fill,
                    color: AppPalette.fg(Color(0xFF0D47A1)), size: 30)),
          ],
        ),
      ),
    );
  }
}
