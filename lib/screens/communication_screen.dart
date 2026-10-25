// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';

class CommunicationScreen extends StatefulWidget {
  final String userEmail;
  final String userRole;

  const CommunicationScreen({super.key, required this.userEmail, required this.userRole});

  @override
  State<CommunicationScreen> createState() => _CommunicationScreenState();
}

class _CommunicationScreenState extends State<CommunicationScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  // --- PREMIUM PALETTE ---
  static const Color tgBlue = Color(0xFF24A1DE);
  static const Color tgBackground = Color(0xFFF1F5F9);
  static const Color pPurple = Color(0xFF4A148C);
  static const Color lightPurple = Color(0xFFF3E5F5);

  String selectedFolder = "All Chats";
  Map<String, dynamic>? selectedChat; 
  bool isAudioMode = true; // RESTORED: Toggle for Audio/Video input
  final TextEditingController _msgController = TextEditingController();

  IconData _getIcon(String name) {
    switch (name) {
      case 'person_rounded': return Icons.person_rounded;
      case 'groups_rounded': return Icons.groups_rounded;
      case 'campaign_rounded': return Icons.campaign_rounded;
      default: return Icons.chat_bubble_rounded;
    }
  }

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  // --- ACTIONS ---
  Future<void> _sendMessage() async {
    if (_msgController.text.trim().isEmpty || selectedChat == null) return;
    await supabase.from('chat_messages').insert({
      'room_id': selectedChat!['id'],
      'sender_email': widget.userEmail,
      'content': _msgController.text.trim(),
    });
    _msgController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      bool isDesktop = constraints.maxWidth > 1100;
      bool isMobile = constraints.maxWidth < 700;
      bool isChatSelected = selectedChat != null;

      return Scaffold(
        backgroundColor: AppPalette.bg(tgBackground),
        body: Row(
          children: [
            if (!isMobile) _buildOutstandingSidebar(),
            if (!isMobile || (isMobile && !isChatSelected))
              SizedBox(
                width: isMobile ? constraints.maxWidth : 400,
                child: Column(
                  children: [
                    _buildHubHeader(),
                    _buildStoriesBar(),
                    _buildSearchBar(),
                    Expanded(child: _buildChatList()),
                  ],
                ),
              ),
            if (!isMobile || (isMobile && isChatSelected))
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: isChatSelected ? _buildChatArea(isMobile) : _buildEmptyState(),
                    ),
                    if (isDesktop && isChatSelected)
                      Expanded(flex: 2, child: _buildRightBentoProfile()),
                  ],
                ),
              ),
          ],
        ),
      );
    });
  }

  // --- 1. SIDEBAR ---
  Widget _buildOutstandingSidebar() {
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 20),
      color: AppPalette.bg(const Color(0xFF1D2733)),
      child: FutureBuilder(
        future: supabase.from('chat_folders').select().order('sort_order'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final folders = snapshot.data!;
          return Column(
            children: [
              IconButton(icon: Icon(Icons.arrow_back_ios_new, color: AppPalette.fg(Colors.white54), size: 20), onPressed: () => Navigator.pop(context)),
              const SizedBox(height: 30),
              ...folders.map((f) => _sidebarCard(_getIcon(f['icon_name']), f['name'], f['name'])),
              const Spacer(),
              _sidebarCard(Icons.settings_suggest_rounded, "Settings", "Settings", isSettings: true),
            ],
          );
        },
      ),
    );
  }

  Widget _sidebarCard(IconData icon, String label, String folderName, {bool isSettings = false}) {
    bool isSel = selectedFolder == folderName;
    return GestureDetector(
      onTap: () => isSettings ? _showSettingsModal() : setState(() => selectedFolder = folderName),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        height: 65, width: 65,
        decoration: BoxDecoration(
          color: AppPalette.bg(isSel ? pPurple : Colors.white.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(18),
          boxShadow: isSel ? [BoxShadow(color: pPurple.withValues(alpha: 0.3), blurRadius: 10)] : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppPalette.fg(isSel ? Colors.white : Colors.white60), size: 26),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: AppPalette.fg(isSel ? Colors.white : Colors.white54), fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // --- 2. STORIES (RESTORED INDEX 0 ADD BUTTON) ---
  Widget _buildStoriesBar() {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: FutureBuilder(
        future: supabase.from('chat_stories').select(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final stories = snapshot.data!;
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 20),
            itemCount: stories.length + 1, // +1 for the "Add Story" button
            itemBuilder: (context, index) {
              bool isAddButton = index == 0;
              final story = isAddButton ? null : stories[index - 1];

              return Padding(
                padding: const EdgeInsets.only(right: 15),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppPalette.line(isAddButton ? Colors.grey : Colors.greenAccent), width: 2.5),
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: AppPalette.bg(Colors.white),
                        child: Icon(isAddButton ? Icons.add : Icons.person, color: AppPalette.fg(Colors.grey)),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(isAddButton ? "My Story" : story!['label'], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // --- 3. CHAT LIST ---
  Widget _buildChatList() {
    return StreamBuilder(
      stream: supabase.from('chat_rooms').stream(primaryKey: ['id']).order('created_at'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final rooms = snapshot.data!.where((r) => selectedFolder == "All Chats" || r['folder_name'] == selectedFolder).toList();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          itemCount: rooms.length,
          itemBuilder: (context, index) {
            bool isSel = selectedChat?['id'] == rooms[index]['id'];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppPalette.bg(isSel ? pPurple : Colors.white),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4))],
              ),
              child: ListTile(
                onTap: () => setState(() => selectedChat = rooms[index]),
                leading: CircleAvatar(backgroundColor: AppPalette.bg(isSel ? Colors.white24 : tgBlue.withValues(alpha: 0.1)), 
                  child: Icon(Icons.groups_rounded, color: AppPalette.fg(isSel ? Colors.white : tgBlue))),
                title: Text(rooms[index]['name'], style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppPalette.fg(isSel ? Colors.white : Colors.black87), fontSize: 14)),
                subtitle: Text(rooms[index]['last_message'] ?? "No messages", style: TextStyle(color: AppPalette.fg(isSel ? Colors.white70 : Colors.grey), fontSize: 11)),
                trailing: Text("12:45", style: TextStyle(color: AppPalette.fg(Colors.grey), fontSize: 10)),
              ),
            );
          },
        );
      },
    );
  }

  // --- 4. CHAT AREA (RESTORED HEADER ICONS) ---
  Widget _buildChatArea(bool isMobile) {
    return Container(
      color: AppPalette.bg(const Color(0xFFE7EBF0)),
      child: Column(
        children: [
          _buildChatHeader(isMobile),
          Expanded(
            child: StreamBuilder(
              stream: supabase.from('chat_messages').stream(primaryKey: ['id']).eq('room_id', selectedChat!['id']).order('created_at', ascending: true),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final msgs = snapshot.data!;
                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) => _bubble(msgs[i]['content'], msgs[i]['sender_email'] == widget.userEmail),
                );
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildChatHeader(bool isMobile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 45, 15, 15),
      color: AppPalette.bg(Colors.white),
      child: Row(
        children: [
          if (isMobile) IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => selectedChat = null)),
          CircleAvatar(backgroundColor: AppPalette.bg(tgBlue), child: Icon(Icons.person, color: AppPalette.fg(Colors.white))),
          const SizedBox(width: 15),
          Text(selectedChat!['name'], style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16)),
          const Spacer(),
          Icon(Icons.videocam_outlined, color: AppPalette.fg(Colors.grey)), // RESTORED
          const SizedBox(width: 15),
          Icon(Icons.search, color: AppPalette.fg(Colors.grey)), // RESTORED
        ],
      ),
    );
  }

  Widget _bubble(String m, bool me) => Align(
    alignment: me ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.bg(me ? const Color(0xFFEFFDDE) : Colors.white), 
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2)],
      ),
      child: Text(m, style: GoogleFonts.merriweather(fontSize: 14)),
    ),
  );

  // --- 5. INPUT AREA (RESTORED MIC/VIDEO TOGGLE) ---
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(15),
      color: AppPalette.bg(Colors.white),
      child: Row(
        children: [
          Icon(Icons.sentiment_satisfied_alt_rounded, color: AppPalette.fg(Colors.grey)),
          const SizedBox(width: 15),
          Expanded(child: TextField(controller: _msgController, onSubmitted: (_) => _sendMessage(), decoration: InputDecoration(hintText: "Message", border: InputBorder.none, hintStyle: GoogleFonts.merriweather(fontSize: 14)))),
          Icon(Icons.attach_file_rounded, color: AppPalette.fg(Colors.grey)), // RESTORED
          const SizedBox(width: 15),
          GestureDetector( // RESTORED: Audio/Video Mode circle toggle
            onTap: () {
              if (_msgController.text.isNotEmpty) _sendMessage();
              else setState(() => isAudioMode = !isAudioMode);
            },
            child: CircleAvatar(
              backgroundColor: AppPalette.bg(tgBlue),
              child: Icon(_msgController.text.isNotEmpty ? Icons.send_rounded : (isAudioMode ? Icons.mic : Icons.videocam), color: AppPalette.fg(Colors.white), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // --- 6. RIGHT PROFILE (RESTORED SHARED MEDIA) ---
  Widget _buildRightBentoProfile() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: AppPalette.bg(Colors.white), border: Border(left: BorderSide(color: AppPalette.line(Colors.black12)))),
      child: Column(
        children: [
          CircleAvatar(radius: 60, backgroundColor: AppPalette.bg(lightPurple), child: Icon(Icons.person, size: 60, color: AppPalette.fg(Colors.grey))),
          const SizedBox(height: 20),
          Text(selectedChat!['name'], style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 20)),
          Text(selectedChat!['description'] ?? widget.userEmail, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey))),
          const Divider(height: 50),
          _bentoItem("Privacy & Security", [
            _pItem(Icons.visibility_off, "Last Seen", "My Contacts"),
            _pItem(Icons.lock, "Passcode Lock", "Off"),
          ]),
          const SizedBox(height: 20),
          _bentoItem("Shared Media", [ // RESTORED: Colored Shared Media Boxes
             Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
               _mBox(Colors.blue), _mBox(Colors.orange), _mBox(Colors.green)
            ])
          ]),
        ],
      ),
    );
  }

  Widget _mBox(Color c) => Container(width: 60, height: 60, decoration: BoxDecoration(color: AppPalette.bg(c.withValues(alpha: 0.2)), borderRadius: const BorderRadius.all(Radius.circular(10))));

  Widget _bentoItem(String t, List<Widget> c) => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFFBFBFE)), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppPalette.line(Colors.black.withValues(alpha: 0.05)))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppPalette.fg(Colors.blueGrey))), const SizedBox(height: 10), ...c]));
  Widget _pItem(IconData i, String t, String v) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Icon(i, size: 14, color: AppPalette.fg(tgBlue)), const SizedBox(width: 10), Expanded(child: Text(t, style: const TextStyle(fontSize: 12))), Text(v, style: TextStyle(color: AppPalette.fg(tgBlue), fontWeight: FontWeight.bold, fontSize: 11))]));

  Widget _buildHubHeader() => Container(padding: const EdgeInsets.fromLTRB(25, 40, 20, 10), child: Row(children: [Text(selectedFolder, style: GoogleFonts.merriweather(fontSize: 22, fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.black87))), const Spacer(), Icon(Icons.edit_note_rounded, color: AppPalette.fg(pPurple), size: 28)]));
  Widget _buildSearchBar() => Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: TextField(decoration: InputDecoration(hintText: "Search as ${widget.userRole}...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: AppPalette.bg(Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), contentPadding: EdgeInsets.zero)));
  void _showSettingsModal() {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), builder: (c) => Container(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [Text("Communication Settings", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 18)), const Divider(height: 40), ListTile(leading: const Icon(Icons.palette), title: const Text("Chat Themes")), ListTile(leading: const Icon(Icons.language), title: const Text("Translation"))])));
  }
  Widget _buildEmptyState() => Center(child: Text("Select a unit conversation", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey), fontSize: 16)));
}