// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../services/chat_service.dart';
import '../services/app_sounds.dart';
import '../services/call_service.dart';
import '../widgets/app_menus.dart';
import 'package:master_admin/core/app_palette.dart';

part 'my_home_extras.dart';

/// My Home: private chats and groups (WhatsApp / Telegram style).
///
/// Layout follows the screen width:
///   phone   -> chat list, tap a chat to open it full screen
///   tablet  -> list + conversation side by side
///   desktop -> list + conversation + chat info panel
class CommunicationScreen extends StatefulWidget {
  final String userEmail;
  final String userRole;
  /// Chat to open first (e.g. after joining with an invite link)
  final String? openRoomId;

  const CommunicationScreen({super.key, required this.userEmail, required this.userRole, this.openRoomId});

  @override
  State<CommunicationScreen> createState() => _CommunicationScreenState();
}

const Color _kPurple = Color(0xFF4A148C);
const Color _kBlue = Color(0xFF24A1DE);
const Color _kBg = Color(0xFFF1F5F9);
const Color _kChatBg = Color(0xFFE7EBF0);
const Color _kMine = Color(0xFFEFE3FF);

String _chatTime(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return DateFormat('HH:mm').format(t);
  if (today.difference(day).inDays == 1) return 'Yesterday';
  if (today.difference(day).inDays < 7) return DateFormat('EEE').format(t);
  return DateFormat('d/M/yy').format(t);
}

String _fileSize(int? b) {
  if (b == null) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

Color _colorFor(String seed) {
  const palette = [
    Color(0xFF6A1B9A),
    Color(0xFF1565C0),
    Color(0xFF00897B),
    Color(0xFFEF6C00),
    Color(0xFFAD1457),
    Color(0xFF2E7D32),
    Color(0xFF4527A0),
    Color(0xFF00838F),
  ];
  int h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  final bool group;
  const _Avatar({required this.name, this.url, this.size = 44, this.group = false});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
    final c = _colorFor(name);
    if ((url ?? '').isNotEmpty) {
      return CircleAvatar(radius: size / 2, backgroundColor: AppPalette.bg(c), backgroundImage: NetworkImage(url!));
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppPalette.bg(c),
      child: group
          ? Icon(Icons.groups_rounded, color: AppPalette.fg(Colors.white), size: size * 0.5)
          : Text(initials, style: TextStyle(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold, fontSize: size * 0.36)),
    );
  }
}

class _CommunicationScreenState extends State<CommunicationScreen> {
  final _db = Supabase.instance.client;

  List<ChatRoom> _rooms = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // all | unread | dm | group | archived
  String _search = '';
  String? _openRoomId;
  bool _showInfo = true;
  String _myName = '';

  RealtimeChannel? _listChannel;
  Timer? _refreshDebounce;
  RealtimeChannel? _presence;
  Timer? _touchTimer;
  String? _myAvatar;
  String? _myUsername;

  ChatRoom? get _openRoom {
    for (final r in _rooms) {
      if (r.id == _openRoomId) return r;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _openRoomId = widget.openRoomId;
    _loadRooms();
    _loadMyName();
    _loadPrivacy();
    _initPresence();
    // "last seen": refreshed every minute while My Home is open
    ChatService.touch();
    _touchTimer = Timer.periodic(const Duration(minutes: 1), (_) => ChatService.touch());
    // Any new message or read update in my chats refreshes the list (the database only sends my chats)
    _listChannel = _db
        .channel('chat-list-${ChatService.myId}')
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'chat_messages',
            callback: (p) {
              // message sound (Settings › Notifications & Sounds) for others' messages
              final from = (p.newRecord['sender_id'] ?? '').toString();
              if (from.isNotEmpty && from != ChatService.myId) AppSounds.message();
              _scheduleRefresh();
            })
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'chat_members', callback: (_) => _scheduleRefresh())
        .subscribe();
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _touchTimer?.cancel();
    ChatService.touch();
    final ch = _listChannel;
    if (ch != null) _db.removeChannel(ch);
    final pr = _presence;
    if (pr != null) _db.removeChannel(pr);
    _onlineNow.value = <String>{};
    super.dispose();
  }

  /// Paste an invite link (or its code) to join a group.
  Future<void> _joinWithLink() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Join with a link"),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: tr("Paste the invite link or code"), border: const OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text("Continue")),
        ],
      ),
    );
    final code = CallService.codeFrom(text ?? '');
    if (code == null || !mounted) {
      if (text != null && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That isn't an invite link.")));
      return;
    }
    await CallService.joinWithCode(context, code);
    _loadRooms();
  }

  /// Who is online: everyone with My Home open joins this channel.
  void _initPresence() {
    final me = ChatService.myId;
    if (me == null) return;
    final ch = _db.channel('online-users');
    ch.onPresenceSync((_) {
      final ids = <String>{};
      for (final s in ch.presenceState()) {
        for (final p in s.presences) {
          final uid = p.payload['user_id']?.toString();
          if (uid != null && p.payload['hidden'] != true) ids.add(uid);
        }
      }
      _onlineNow.value = ids;
    }).subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) await _track();
    });
    _presence = ch;
  }

  Future<void> _track() async {
    final me = ChatService.myId;
    final ch = _presence;
    if (me == null || ch == null) return;
    try {
      await ch.track({'user_id': me, 'hidden': _ChatPrefs.lastSeenRule == 'nobody'});
    } catch (_) {}
  }

  Future<void> _loadPrivacy() async {
    final p = await ChatService.privacy();
    _ChatPrefs.apply(p);
    _track();
    if (mounted) setState(() {});
  }

  Future<void> _startWith(ChatPerson p) async {
    try {
      final id = await ChatService.startDirect(p.id);
      await _loadRooms(silent: true);
      _open(id);
    } catch (e) {
      _snack("Couldn't start the chat: ${e is PostgrestException ? e.message : e}");
    }
  }

  Future<void> _openContacts() async {
    final p = await Navigator.push<ChatPerson>(context, MaterialPageRoute(builder: (_) => const _ContactsScreen()));
    if (p != null) await _startWith(p);
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const _ChatSettingsScreen()));
    await _loadMyName();
    await _loadPrivacy();
    _loadRooms(silent: true);
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 400), () => _loadRooms(silent: true));
  }

  Future<void> _loadMyName() async {
    try {
      final p = await ChatService.myProfile();
      String? photo = (p['avatar_url'] ?? '').toString();
      if (photo.isEmpty) {
        try {
          photo = (await _db.rpc('profile_photo', params: {'p_id': ChatService.myId}))?.toString();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _myName = (p['full_name'] ?? widget.userEmail).toString();
          _myUsername = (p['username'] ?? '').toString().isEmpty ? null : p['username'].toString();
          _myAvatar = (photo ?? '').isEmpty ? null : photo;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadRooms({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final rooms = await ChatService.rooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint("Chat rooms error: $e");
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load your chats. If this keeps happening, ask the admin to run 06_round6.sql.";
      });
    }
  }

  List<ChatRoom> get _visibleRooms {
    final q = _search.trim().toLowerCase();
    return _rooms.where((r) {
      if (_filter == 'archived') {
        if (!r.archived) return false;
      } else {
        if (r.archived) return false;
        if (_filter == 'unread' && r.unread == 0) return false;
        if (_filter == 'dm' && r.isGroup) return false;
        if (_filter == 'group' && !r.isGroup) return false;
      }
      if (q.isEmpty) return true;
      return r.name.toLowerCase().contains(q) || (r.lastMessage ?? '').toLowerCase().contains(q);
    }).toList();
  }

  void _open(String roomId) {
    setState(() => _openRoomId = roomId);
  }

  Future<void> _newChat() async {
    final picked = await showDialog<List<ChatPerson>>(
      context: context,
      builder: (_) => const _PeoplePicker(title: "New chat", multi: false),
    );
    if (picked == null || picked.isEmpty) return;
    await _startWith(picked.first);
  }

  Future<void> _newGroup() async {
    final result = await showDialog<(String, String, List<ChatPerson>)>(
      context: context,
      builder: (_) => const _NewGroupDialog(),
    );
    if (result == null) return;
    try {
      final id = await ChatService.createGroup(result.$1, result.$2, result.$3.map((p) => p.id).toList());
      await _loadRooms(silent: true);
      _open(id);
    } catch (e) {
      _snack("Couldn't create the group: ${e is PostgrestException ? e.message : e}");
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _roomMenu(ChatRoom r, Offset? at) async {
    final items = <(String, IconData, String)>[
      ('pin', r.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded, r.pinned ? 'Unpin' : 'Pin to top'),
      ('mute', r.muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, r.muted ? 'Unmute' : 'Mute'),
      ('archive', Icons.archive_outlined, r.archived ? 'Unarchive' : 'Archive'),
      if (r.unread > 0) ('read', Icons.mark_chat_read_outlined, 'Mark as read'),
      if (!r.isGroup && r.otherUserId != null) ('contact', Icons.person_add_alt_1_outlined, 'Add to contacts'),
      if (!r.isGroup && r.otherUserId != null) ('block', Icons.block, r.blocked ? 'Unblock' : 'Block'),
      if (r.isGroup) ('leave', Icons.logout_rounded, 'Leave group'),
    ];
    String? choice;
    if (at != null) {
      choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
        items: [for (final i in items) PopupMenuItem(value: i.$1, child: Row(children: [Icon(i.$2, size: 18), const SizedBox(width: 10), Text(i.$3)]))],
      );
    } else {
      choice = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final i in items) ListTile(leading: Icon(i.$2), title: Text(i.$3), onTap: () => Navigator.pop(ctx, i.$1)),
          ]),
        ),
      );
    }
    if (choice == null) return;
    try {
      switch (choice) {
        case 'pin':
          await ChatService.setMyFlag(r.id, 'pinned', !r.pinned);
        case 'mute':
          await ChatService.setMyFlag(r.id, 'muted', !r.muted);
        case 'archive':
          await ChatService.setMyFlag(r.id, 'archived', !r.archived);
          if (_openRoomId == r.id && !r.archived) setState(() => _openRoomId = null);
        case 'read':
          await ChatService.markRead(r.id);
        case 'contact':
          await ChatService.saveContact(r.otherUserId!);
          _snack("${r.name} added to your contacts.");
        case 'block':
          if (r.blocked) {
            await ChatService.unblock(r.otherUserId!);
          } else if (await _confirm("Block ${r.name}?", "They won't be able to message you or see your last seen and photo.")) {
            await ChatService.block(r.otherUserId!);
          }
        case 'leave':
          final ok = await _confirm("Leave \"${r.name}\"?", "You will stop receiving its messages.");
          if (ok) {
            await ChatService.leave(r.id);
            if (_openRoomId == r.id) setState(() => _openRoomId = null);
          }
      }
      await _loadRooms(silent: true);
    } catch (e) {
      _snack("Couldn't update the chat.");
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16)),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Yes", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final phone = w < 760;
      final desktop = w >= 1250;
      final room = _openRoom;

      final list = _buildListPane(phone: phone);
      final conversation = room == null
          ? _emptyState()
          : _ConversationView(
              key: ValueKey(room.id),
              room: room,
              myName: _myName,
              showBack: phone,
              infoOpen: desktop && _showInfo,
              onBack: () => setState(() => _openRoomId = null),
              onToggleInfo: () {
                if (desktop) {
                  setState(() => _showInfo = !_showInfo);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text("Chat info")),
                        body: _ChatInfoPanel(room: room, onChanged: () => _loadRooms(silent: true), onLeft: () {
                          Navigator.pop(context);
                          setState(() => _openRoomId = null);
                          _loadRooms(silent: true);
                        }),
                      ),
                    ),
                  );
                }
              },
              onActivity: () => _scheduleRefresh(),
            );

      Widget body;
      if (phone) {
        body = room == null ? list : conversation;
      } else {
        body = Row(children: [
          SizedBox(width: w < 1000 ? 320 : 370, child: list),
          const VerticalDivider(width: 1),
          Expanded(child: conversation),
          if (desktop && _showInfo && room != null) ...[
            const VerticalDivider(width: 1),
            SizedBox(
              width: 320,
              child: _ChatInfoPanel(
                key: ValueKey('info-${room.id}'),
                room: room,
                onChanged: () => _loadRooms(silent: true),
                onLeft: () {
                  setState(() => _openRoomId = null);
                  _loadRooms(silent: true);
                },
              ),
            ),
          ],
        ]);
      }

      return PopScope(
        canPop: !(phone && room != null),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && phone && room != null) setState(() => _openRoomId = null);
        },
        child: Scaffold(backgroundColor: AppPalette.bg(_kBg), body: SafeArea(child: body)),
      );
    });
  }

  Widget _emptyState() => Container(
        color: AppPalette.bg(_kChatBg),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.forum_rounded, size: 64, color: AppPalette.fg(_kPurple.withValues(alpha: 0.35))),
              const SizedBox(height: 12),
              Text("Select a chat to start messaging",
                  textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 15, color: AppPalette.fg(Colors.blueGrey[700]))),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                OutlinedButton.icon(onPressed: _newChat, icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text("New chat")),
                OutlinedButton.icon(onPressed: _newGroup, icon: const Icon(Icons.group_add_rounded, size: 18), label: const Text("New group")),
              ]),
            ]),
          ),
        ),
      );

  Widget _buildListPane({required bool phone}) {
    final rooms = _visibleRooms;
    final unreadTotal = _rooms.where((r) => !r.archived && !r.muted).fold<int>(0, (a, r) => a + r.unread);
    Widget filterChip(String key, String label) {
      final sel = _filter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(sel ? Colors.white : _kPurple))),
          selected: sel,
          selectedColor: AppPalette.bg(_kPurple),
          backgroundColor: AppPalette.bg(Colors.white),
          side: BorderSide(color: AppPalette.line(_kPurple.withValues(alpha: 0.25))),
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() => _filter = key),
        ),
      );
    }

    return Container(
      color: AppPalette.bg(_kBg),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18), onPressed: () => Navigator.maybePop(context)),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: _openSettings,
              child: Tooltip(message: "My profile and settings", child: _Avatar(name: _myName.isEmpty ? '?' : _myName, url: _myAvatar, size: 36)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: _openSettings,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text("My Home",
                      style: GoogleFonts.merriweather(fontSize: 19, fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.black87)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (_myName.isNotEmpty)
                    Text(_myUsername == null ? _myName : "$_myName · @$_myUsername",
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
                ]),
              ),
            ),
            if (unreadTotal > 0)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppPalette.bg(_kBlue), borderRadius: BorderRadius.circular(10)),
                child: Text('$unreadTotal', style: TextStyle(color: AppPalette.fg(Colors.white), fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            IconButton(tooltip: tr("Contacts"), icon: Icon(Icons.contacts_outlined, color: AppPalette.fg(_kPurple)), onPressed: _openContacts),
            PopupMenuButton<String>(
              tooltip: tr("New"),
              icon: Icon(Icons.edit_square, color: AppPalette.fg(_kPurple)),
              onSelected: (v) {
                if (v == 'chat') _newChat();
                if (v == 'group') _newGroup();
                if (v == 'contacts') _openContacts();
                if (v == 'settings') _openSettings();
                if (v == 'refresh') _loadRooms();
                if (v == 'join') _joinWithLink();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'chat', child: Row(children: [Icon(Icons.person_add_alt_1_rounded, size: 18), SizedBox(width: 10), Text("New chat")])),
                PopupMenuItem(value: 'group', child: Row(children: [Icon(Icons.group_add_rounded, size: 18), SizedBox(width: 10), Text("New group")])),
                PopupMenuItem(value: 'join', child: Row(children: [Icon(Icons.link_rounded, size: 18), SizedBox(width: 10), Text("Join with a link")])),
                PopupMenuItem(value: 'contacts', child: Row(children: [Icon(Icons.contacts_outlined, size: 18), SizedBox(width: 10), Text("Contacts")])),
                PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 10), Text("Privacy & settings")])),
                PopupMenuItem(value: 'refresh', child: Row(children: [Icon(Icons.refresh_rounded, size: 18), SizedBox(width: 10), Text("Refresh")])),
              ],
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: tr("Search chats"),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AppPalette.bg(Colors.white),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            filterChip('all', 'All'),
            filterChip('unread', 'Unread'),
            filterChip('dm', 'Personal'),
            filterChip('group', 'Groups'),
            filterChip('archived', 'Archived'),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.red.shade800))),
                          const SizedBox(height: 10),
                          OutlinedButton(onPressed: _loadRooms, child: const Text("Retry")),
                        ]),
                      ),
                    )
                  : rooms.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.chat_bubble_outline_rounded, size: 44, color: AppPalette.fg(Colors.grey.shade400)),
                              const SizedBox(height: 8),
                              Text(_rooms.isEmpty ? "No chats yet. Start one with the pencil button." : "No chats here.",
                                  textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey.shade600))),
                            ]),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _loadRooms(silent: true),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                            itemCount: rooms.length,
                            itemBuilder: (_, i) => _roomTile(rooms[i]),
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _roomTile(ChatRoom r) {
    final sel = r.id == _openRoomId;
    final mineLast = r.lastSenderId != null && r.lastSenderId == ChatService.myId;
    return GestureDetector(
      onSecondaryTapDown: (d) => _roomMenu(r, d.globalPosition),
      child: Material(
        color: AppPalette.bg(sel ? _kPurple.withValues(alpha: 0.10) : Colors.transparent),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _open(r.id),
          onLongPress: () => _roomMenu(r, null),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              _PresenceAvatar(
                name: r.name,
                url: r.avatarUrl,
                group: r.isGroup && (r.avatarUrl ?? '').isEmpty,
                userId: r.isGroup ? null : r.otherUserId,
                visible: r.otherOnlineVisible,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 14, color: AppPalette.fg(Colors.black87))),
                    ),
                    const SizedBox(width: 6),
                    Text(_chatTime(r.lastMessageAt),
                        style: TextStyle(fontSize: 11, color: AppPalette.fg(r.unread > 0 ? _kBlue : Colors.grey.shade600), fontWeight: r.unread > 0 ? FontWeight.bold : null)),
                  ]),
                  const SizedBox(height: 3),
                  Row(children: [
                    Expanded(
                      child: Text(
                        (r.lastMessage ?? '').isEmpty
                            ? (r.isGroup ? "${r.memberCount} members" : "Say hello 👋")
                            : "${mineLast ? 'You: ' : ''}${r.lastMessage}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: AppPalette.fg(Colors.grey.shade700)),
                      ),
                    ),
                    if (r.muted) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.notifications_off_rounded, size: 14, color: AppPalette.fg(Colors.grey.shade500))),
                    if (r.pinned) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.push_pin_rounded, size: 14, color: AppPalette.fg(Colors.grey.shade500))),
                    if (r.unread > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: AppPalette.bg(r.muted ? Colors.grey : _kBlue), borderRadius: BorderRadius.circular(10)),
                        child: Text(r.unread > 99 ? '99+' : '${r.unread}',
                            style: TextStyle(color: AppPalette.fg(Colors.white), fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// CONVERSATION
// =====================================================================
class _ConversationView extends StatefulWidget {
  final ChatRoom room;
  final String myName;
  final bool showBack;
  final bool infoOpen;
  final VoidCallback onBack;
  final VoidCallback onToggleInfo;
  final VoidCallback onActivity;

  const _ConversationView({
    super.key,
    required this.room,
    required this.myName,
    required this.showBack,
    required this.infoOpen,
    required this.onBack,
    required this.onToggleInfo,
    required this.onActivity,
  });

  @override
  State<_ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<_ConversationView> {
  final _db = Supabase.instance.client;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  List<ChatMessage> _messages = []; // newest first
  Map<String, ChatPerson> _people = {};
  bool _loading = true;
  bool _loadingOlder = false;
  bool _noMore = false;
  bool _sending = false;
  ChatMessage? _replyTo;
  ChatMessage? _editing;
  String _searchText = '';
  bool _searching = false;
  final Map<String, (String, DateTime)> _typing = {}; // user id -> (name, until)
  Timer? _typingTicker;
  DateTime _lastTypingSent = DateTime(2000);
  RealtimeChannel? _channel;
  bool _recordingVoice = false;
  final Map<String, int> _pollTicks = {};

  void _rebuild() {
    if (mounted) setState(() {});
  }

  String get _me => ChatService.myId ?? '';

  @override
  void initState() {
    super.initState();
    _onlineNow.addListener(_rebuild);
    _ChatPrefs.changed.addListener(_rebuild);
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _loadOlder();
    });
    _channel = _db
        .channel('chat-room-${widget.room.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: widget.room.id),
          callback: (p) => _onRemote(ChatMessage.fromMap(p.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: widget.room.id),
          callback: (p) => _onRemote(ChatMessage.fromMap(p.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_members',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: widget.room.id),
          callback: (_) => _loadPeople(),
        )
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final uid = (payload['user_id'] ?? '').toString();
            if (uid.isEmpty || uid == _me) return;
            setState(() => _typing[uid] = ((payload['name'] ?? 'Someone').toString(), DateTime.now().add(const Duration(seconds: 4))));
          },
        )
        .subscribe();
    _typingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_typing.isEmpty || !mounted) return;
      final now = DateTime.now();
      final before = _typing.length;
      _typing.removeWhere((_, v) => v.$2.isBefore(now));
      if (_typing.length != before) setState(() {});
    });
  }

  @override
  void dispose() {
    _onlineNow.removeListener(_rebuild);
    _ChatPrefs.changed.removeListener(_rebuild);
    _typingTicker?.cancel();
    final ch = _channel;
    if (ch != null) _db.removeChannel(ch);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final msgs = await ChatService.messages(widget.room.id);
      await _loadPeople();
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
        _noMore = msgs.length < 60;
      });
      _markRead();
    } catch (e) {
      debugPrint("Messages error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPeople() async {
    try {
      final people = await ChatService.members(widget.room.id);
      if (mounted) setState(() => _people = {for (final p in people) p.id: p});
    } catch (_) {}
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || _noMore || _messages.isEmpty) return;
    _loadingOlder = true;
    try {
      final older = await ChatService.messages(widget.room.id, before: _messages.last.createdAt);
      if (!mounted) return;
      setState(() {
        _messages.addAll(older.where((m) => !_messages.any((x) => x.id == m.id)));
        _noMore = older.length < 60;
      });
    } catch (_) {}
    _loadingOlder = false;
  }

  void _markRead() {
    ChatService.markRead(widget.room.id).then((_) => widget.onActivity()).catchError((_) {});
  }

  void _onRemote(ChatMessage m) {
    if (!mounted) return;
    setState(() {
      final i = _messages.indexWhere((x) => x.id == m.id);
      if (i >= 0) {
        if (m.kind == 'poll') _pollTicks[m.id] = (_pollTicks[m.id] ?? 0) + 1;
        _messages[i] = m;
      } else {
        _messages.insert(0, m);
        _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      if (m.senderId != null) _typing.remove(m.senderId);
    });
    if (m.senderId != _me) _markRead();
  }

  bool _isMine(ChatMessage m) => m.senderId == _me || (m.senderId == null && m.senderEmail == _db.auth.currentUser?.email);

  void _sendTyping() {
    if (!_ChatPrefs.typing) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inMilliseconds < 2500) return;
    _lastTypingSent = now;
    _channel?.sendBroadcastMessage(event: 'typing', payload: {'user_id': _me, 'name': widget.myName});
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (_editing != null) {
        await ChatService.edit(_editing!.id, text);
        final idx = _messages.indexWhere((x) => x.id == _editing!.id);
        if (idx >= 0) {
          final old = _messages[idx];
          _messages[idx] = ChatMessage(
            id: old.id,
            roomId: old.roomId,
            senderId: old.senderId,
            senderEmail: old.senderEmail,
            content: text,
            kind: old.kind,
            createdAt: old.createdAt,
            attachmentPath: old.attachmentPath,
            attachmentName: old.attachmentName,
            attachmentSize: old.attachmentSize,
            attachmentMime: old.attachmentMime,
            replyTo: old.replyTo,
            editedAt: DateTime.now(),
          );
        }
        _editing = null;
      } else {
        final m = await ChatService.sendText(widget.room.id, text, replyTo: _replyTo?.id);
        _onRemote(m);
        _replyTo = null;
      }
      _input.clear();
      widget.onActivity();
    } catch (e) {
      _snack("Message not sent. Check your connection.");
    } finally {
      if (mounted) setState(() => _sending = false);
      _focus.requestFocus();
    }
  }

  Future<void> _attach({required bool images}) async {
    final res = await FilePicker.platform.pickFiles(
      type: images ? FileType.image : FileType.any,
      allowMultiple: true,
      withData: true,
    );
    if (res == null) return;
    setState(() => _sending = true);
    int failed = 0;
    for (final f in res.files) {
      if (f.bytes == null) continue;
      if (f.bytes!.length > 25 * 1024 * 1024) {
        failed++;
        continue;
      }
      try {
        final m = await ChatService.sendFile(widget.room.id, f.bytes!, f.name, replyTo: _replyTo?.id);
        _onRemote(m);
      } catch (e) {
        debugPrint("Attachment error: $e");
        failed++;
      }
    }
    if (mounted) {
      setState(() {
        _sending = false;
        _replyTo = null;
      });
    }
    widget.onActivity();
    if (failed > 0) _snack("$failed file(s) couldn't be sent (files must be under 25 MB).");
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _sendVoice(Uint8List bytes, String mime, String name, int seconds) async {
    setState(() {
      _recordingVoice = false;
      _sending = true;
    });
    try {
      final m = await ChatService.sendFile(widget.room.id, bytes, name, kind: 'voice', mime: mime, replyTo: _replyTo?.id);
      _onRemote(m);
      _replyTo = null;
      widget.onActivity();
    } catch (e) {
      debugPrint("Voice send error: $e");
      _snack("The voice message couldn't be sent.");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendVideoNote() async {
    final r = await _recordVideoNote(context);
    if (r == null) return;
    if (r.$1.length > 25 * 1024 * 1024) {
      _snack("That video is too large (25 MB at most).");
      return;
    }
    setState(() => _sending = true);
    try {
      final m = await ChatService.sendFile(widget.room.id, r.$1, r.$3, kind: 'video_note', mime: r.$2, replyTo: _replyTo?.id);
      _onRemote(m);
      _replyTo = null;
      widget.onActivity();
    } catch (e) {
      debugPrint("Video note send error: $e");
      _snack("The video message couldn't be sent.");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendLocation() async {
    // Settings › Privacy & Security › Location sharing
    await AppSounds.load();
    if (AppSounds.prefs.value['location_sharing'] == false) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location sharing is off. Turn it on in Settings › Privacy & Security.")));
      }
      return;
    }
    if (!mounted) return;
    final loc = await _pickLocation(context);
    if (loc == null) return;
    try {
      final m = await ChatService.sendLocation(widget.room.id, loc.$1, loc.$2, label: loc.$3, replyTo: _replyTo?.id);
      _onRemote(m);
      _replyTo = null;
      widget.onActivity();
    } catch (_) {
      _snack("The location couldn't be sent.");
    }
  }

  Future<void> _newPoll() async {
    final d = await showDialog<_PollDraft>(context: context, builder: (_) => const _PollCreator());
    if (d == null) return;
    try {
      final m = await ChatService.createPoll(widget.room.id, d.question, d.options, multiple: d.multiple, anonymous: d.anonymous);
      if (m != null) _onRemote(m);
      widget.onActivity();
    } catch (e) {
      _snack(e is PostgrestException ? e.message : "The poll couldn't be created. Ask the admin to run 08_round7.sql.");
    }
  }

  Future<void> _messageActions(ChatMessage m, Offset? at) async {
    if (m.isDeleted) return;
    final mine = _isMine(m);
    final items = <(String, IconData, String)>[
      ('reply', Icons.reply_rounded, 'Reply'),
      if (m.content.isNotEmpty) ('copy', Icons.copy_rounded, 'Copy text'),
      if (mine && m.kind == 'text') ('edit', Icons.edit_rounded, 'Edit'),
      if (mine) ('delete', Icons.delete_outline_rounded, 'Delete for everyone'),
    ];
    String? choice;
    if (at != null) {
      choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
        items: [for (final i in items) PopupMenuItem(value: i.$1, child: Row(children: [Icon(i.$2, size: 18), const SizedBox(width: 10), Text(i.$3)]))],
      );
    } else {
      choice = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final i in items) ListTile(leading: Icon(i.$2), title: Text(i.$3), onTap: () => Navigator.pop(ctx, i.$1)),
          ]),
        ),
      );
    }
    switch (choice) {
      case 'reply':
        setState(() {
          _replyTo = m;
          _editing = null;
        });
        _focus.requestFocus();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.content));
        _snack("Copied");
      case 'edit':
        setState(() {
          _editing = m;
          _replyTo = null;
          _input.text = m.content;
        });
        _focus.requestFocus();
      case 'delete':
        try {
          await ChatService.deleteForEveryone(m.id);
          _onRemote(ChatMessage(
            id: m.id,
            roomId: m.roomId,
            senderId: m.senderId,
            senderEmail: m.senderEmail,
            content: '',
            kind: m.kind,
            createdAt: m.createdAt,
            deletedAt: DateTime.now(),
          ));
          widget.onActivity();
        } catch (_) {
          _snack("Couldn't delete the message.");
        }
    }
  }

  String _nameOf(String? uid, String email) => _people[uid]?.name ?? (email.isEmpty ? 'Unknown' : email);

  @override
  Widget build(BuildContext context) {
    final r = widget.room;
    final typingNames = _typing.values.map((v) => v.$1).toList();
    final other = r.otherUserId == null ? null : _people[r.otherUserId];
    final subtitle = typingNames.isNotEmpty
        ? (typingNames.length == 1 ? "${typingNames.first} is typing…" : "${typingNames.length} people are typing…")
        : r.isGroup
            ? "${_people.isEmpty ? r.memberCount : _people.length} members${_people.isEmpty ? '' : ', ${_people.values.where((p) => p.id != _me && _isOnline(p.id, p.onlineVisible)).length} online'}"
            : r.blocked
                ? 'blocked'
                : _lastSeenText(
                    online: _isOnline(r.otherUserId, other?.onlineVisible ?? r.otherOnlineVisible),
                    visible: other?.onlineVisible ?? r.otherOnlineVisible,
                    lastSeen: other?.lastSeen ?? r.otherLastSeen,
                  );
    final online = subtitle == 'online';

    final q = _searchText.trim().toLowerCase();
    final shown = q.isEmpty
        ? _messages
        : _messages.where((m) => m.content.toLowerCase().contains(q) || (m.attachmentName ?? '').toLowerCase().contains(q)).toList();

    return Container(
      decoration: _ChatPrefs.background,
      child: Column(children: [
        // Header
        Material(
          color: AppPalette.bg(Colors.white),
          elevation: 0.5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
            child: Row(children: [
              if (widget.showBack) IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
              const SizedBox(width: 4),
              InkWell(
                onTap: widget.onToggleInfo,
                child: _PresenceAvatar(
                    name: r.name, url: r.avatarUrl, size: 40, group: r.isGroup && (r.avatarUrl ?? '').isEmpty, userId: r.isGroup ? null : r.otherUserId, visible: r.otherOnlineVisible),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _searching
                    ? TextField(
                        autofocus: true,
                        onChanged: (v) => setState(() => _searchText = v),
                        decoration: InputDecoration(hintText: tr("Search in this chat"), border: InputBorder.none, isDense: true),
                      )
                    : InkWell(
                        onTap: widget.onToggleInfo,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: AppPalette.fg(Colors.black87))),
                          if (subtitle.isNotEmpty)
                            Text(subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: AppPalette.fg(typingNames.isNotEmpty ? _kBlue : (online ? const Color(0xFF16A34A) : Colors.grey.shade600)))),
                        ]),
                      ),
              ),
              if (!r.blocked) ...[
                IconButton(
                  tooltip: tr(r.isGroup ? "Voice chat" : "Voice call"),
                  icon: Icon(Icons.call_rounded, color: AppPalette.fg(_kPurple)),
                  onPressed: () => CallService.call(context, r.id, video: false, roomName: r.name),
                ),
                IconButton(
                  tooltip: tr(r.isGroup ? "Video chat" : "Video call"),
                  icon: Icon(Icons.videocam_rounded, color: AppPalette.fg(_kPurple)),
                  onPressed: () => CallService.call(context, r.id, video: true, roomName: r.name),
                ),
              ],
              IconButton(
                tooltip: _searching ? "Close search" : "Search",
                icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded, color: AppPalette.fg(Colors.grey.shade700)),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _searchText = '';
                }),
              ),
              IconButton(
                tooltip: tr("Chat info"),
                icon: Icon(widget.infoOpen ? Icons.info_rounded : Icons.info_outline_rounded, color: AppPalette.fg(Colors.grey.shade700)),
                onPressed: widget.onToggleInfo,
              ),
            ]),
          ),
        ),
        // Messages
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : shown.isEmpty
                  ? Center(
                      child: Text(q.isEmpty ? "No messages yet. Say hello 👋" : "No messages match.",
                          style: TextStyle(color: AppPalette.fg(Colors.grey.shade600))),
                    )
                  : LayoutBuilder(builder: (context, c) {
                      final maxBubble = c.maxWidth * (c.maxWidth < 600 ? 0.82 : 0.62);
                      return ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final m = shown[i];
                          final older = i + 1 < shown.length ? shown[i + 1] : null;
                          final newDay = older == null ||
                              DateTime(older.createdAt.year, older.createdAt.month, older.createdAt.day) !=
                                  DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
                          final sameSenderAsOlder = older != null && !newDay && older.senderId == m.senderId;
                          return Column(children: [
                            if (newDay) _daySeparator(m.createdAt),
                            _bubble(m, maxBubble, showName: r.isGroup && !_isMine(m) && !sameSenderAsOlder),
                          ]);
                        },
                      );
                    }),
        ),
        _composer(),
      ]),
    );
  }

  Widget _daySeparator(DateTime t) {
    final now = DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final label = d == today
        ? 'Today'
        : today.difference(d).inDays == 1
            ? 'Yesterday'
            : DateFormat('EEEE, d MMMM yyyy').format(t);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: AppPalette.bg(Colors.white.withValues(alpha: 0.85)), borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700), fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m, double maxWidth, {required bool showName}) {
    // "… joined with an invite link": a small line in the middle
    if (m.kind == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: AppPalette.bg(Colors.black.withValues(alpha: 0.07)), borderRadius: BorderRadius.circular(12)),
          child: Text(m.content, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade800))),
        ),
      );
    }
    final mine = _isMine(m);
    final replied = m.replyTo == null ? null : _messages.where((x) => x.id == m.replyTo).firstOrNull;
    final read = mine &&
        !widget.room.isGroup &&
        widget.room.otherUserId != null &&
        (_people[widget.room.otherUserId]?.lastReadAt ?? widget.room.otherLastReadAt)?.isBefore(m.createdAt) == false;

    final body = m.isDeleted
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.block_rounded, size: 14, color: AppPalette.fg(Colors.grey.shade600)),
            const SizedBox(width: 6),
            Text("This message was deleted", style: TextStyle(fontStyle: FontStyle.italic, color: AppPalette.fg(Colors.grey.shade600), fontSize: 13)),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (showName)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(_nameOf(m.senderId, m.senderEmail),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(_colorFor(_nameOf(m.senderId, m.senderEmail))))),
              ),
            if (replied != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                decoration: BoxDecoration(
                  color: AppPalette.bg(Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(left: BorderSide(color: AppPalette.line(_kPurple), width: 3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_isMine(replied) ? 'You' : _nameOf(replied.senderId, replied.senderEmail),
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(_kPurple))),
                  Text(
                    replied.isDeleted ? 'Deleted message' : (replied.content.isNotEmpty ? replied.content : (replied.attachmentName ?? 'Attachment')),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700)),
                  ),
                ]),
              ),
            if (m.hasAttachment) _attachment(m, maxWidth),
            if (m.kind == 'poll') _PollCard(key: ValueKey('poll-${m.id}'), message: m, tick: _pollTicks[m.id] ?? 0),
            if (m.kind == 'location') _LocationCard(content: m.content),
            if (m.kind == 'call')
              _CallLine(
                text: m.content,
                onCall: () => CallService.call(context, widget.room.id,
                    video: m.content.contains('🎥'), roomName: widget.room.name),
              ),
            if (m.content.isNotEmpty && m.kind != 'poll' && m.kind != 'location' && m.kind != 'call')
              Padding(
                padding: EdgeInsets.only(top: m.hasAttachment ? 6 : 0),
                child: SelectableText(m.content, style: GoogleFonts.merriweather(fontSize: _ChatPrefs.textSize, height: 1.35, color: AppPalette.fg(Colors.black87))),
              ),
          ]);

    final groupOther = widget.room.isGroup && !mine;
    final bubble = GestureDetector(
        onLongPress: () => _messageActions(m, null),
        onSecondaryTapDown: (d) => _messageActions(m, d.globalPosition),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          margin: EdgeInsets.only(bottom: 4, top: showName ? 6 : 0),
          padding: const EdgeInsets.fromLTRB(11, 8, 11, 6),
          decoration: BoxDecoration(
            color: AppPalette.bg(mine ? _kMine : Colors.white),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 4),
              bottomRight: Radius.circular(mine ? 4 : 14),
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            body,
            const SizedBox(height: 3),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (m.editedAt != null && !m.isDeleted) Text("edited  ", style: TextStyle(fontSize: 10, color: AppPalette.fg(Colors.grey.shade600))),
              Text(DateFormat('HH:mm').format(m.createdAt), style: TextStyle(fontSize: 10, color: AppPalette.fg(Colors.grey.shade600))),
              if (mine && !m.isDeleted) ...[
                const SizedBox(width: 3),
                Icon(read ? Icons.done_all_rounded : Icons.done_rounded, size: 14, color: AppPalette.fg(read ? _kBlue : Colors.grey.shade600)),
              ],
            ]),
          ]),
        ),
      );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: !groupOther
          ? bubble
          : Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: EdgeInsets.only(top: showName ? 6 : 0, right: 6),
                child: showName
                    ? _PresenceAvatar(
                        name: _nameOf(m.senderId, m.senderEmail),
                        url: _people[m.senderId]?.avatarUrl,
                        size: 30,
                        userId: m.senderId,
                        visible: _people[m.senderId]?.onlineVisible ?? false,
                      )
                    : const SizedBox(width: 30),
              ),
              Flexible(child: bubble),
            ]),
    );
  }

  Widget _attachment(ChatMessage m, double maxWidth) {
    if (m.kind == 'voice') return _VoicePlayer(path: m.attachmentPath!, mine: _isMine(m));
    if (m.kind == 'video_note') return _VideoNotePlayer(path: m.attachmentPath!);
    if (m.kind == 'audio') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(m.attachmentName ?? 'Audio', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        _VoicePlayer(path: m.attachmentPath!, mine: _isMine(m)),
      ]);
    }
    if (m.kind == 'image') {
      return FutureBuilder<String?>(
        future: ChatService.fileUrl(m.attachmentPath!),
        builder: (context, snap) {
          final url = snap.data;
          final side = maxWidth.clamp(120.0, 280.0).toDouble();
          if (url == null) {
            return Container(
              width: side,
              height: side * 0.75,
              decoration: BoxDecoration(color: AppPalette.bg(Colors.grey.shade200), borderRadius: BorderRadius.circular(10)),
              child: Center(
                child: snap.connectionState == ConnectionState.waiting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.broken_image_outlined, color: AppPalette.fg(Colors.grey.shade500)),
              ),
            );
          }
          return GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (ctx) => Dialog(
                backgroundColor: AppPalette.bg(Colors.black),
                insetPadding: const EdgeInsets.all(10),
                child: Stack(children: [
                  InteractiveViewer(child: Center(child: Image.network(url, fit: BoxFit.contain))),
                  Positioned(right: 4, top: 4, child: IconButton(icon: Icon(Icons.close, color: AppPalette.fg(Colors.white)), onPressed: () => Navigator.pop(ctx))),
                ]),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: side, maxHeight: 320),
                child: Image.network(url, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => SizedBox(width: side, height: 120, child: const Icon(Icons.broken_image_outlined))),
              ),
            ),
          );
        },
      );
    }
    final icon = switch (m.kind) {
      'audio' => Icons.audiotrack_rounded,
      'video' => Icons.movie_rounded,
      _ => (m.attachmentName ?? '').toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final url = await ChatService.fileUrl(m.attachmentPath!);
        if (url == null) {
          _snack("This file can't be opened.");
          return;
        }
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppPalette.bg(Colors.black.withValues(alpha: 0.04)), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 18, backgroundColor: AppPalette.bg(_kPurple), child: Icon(icon, color: AppPalette.fg(Colors.white), size: 18)),
          const SizedBox(width: 10),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(m.attachmentName ?? 'File',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(_fileSize(m.attachmentSize), style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _composer() {
    final bar = _editing != null
        ? ("Editing message", _editing!.content, Icons.edit_rounded)
        : _replyTo != null
            ? ("Replying to ${_isMine(_replyTo!) ? 'yourself' : _nameOf(_replyTo!.senderId, _replyTo!.senderEmail)}",
                _replyTo!.content.isNotEmpty ? _replyTo!.content : (_replyTo!.attachmentName ?? 'Attachment'),
                Icons.reply_rounded)
            : null;

    if (widget.room.blocked) {
      return Material(
        color: AppPalette.bg(Colors.white),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text("You can't send messages in this chat (blocked).", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey.shade700))),
          ),
        ),
      );
    }
    if (_recordingVoice) {
      return Material(
        color: AppPalette.bg(Colors.white),
        child: SafeArea(top: false, child: _VoiceRecorderBar(onDone: _sendVoice, onCancel: () => setState(() => _recordingVoice = false))),
      );
    }
    final empty = _input.text.trim().isEmpty && _editing == null;

    return Material(
      color: AppPalette.bg(Colors.white),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (bar != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              color: AppPalette.bg(_kPurple.withValues(alpha: 0.05)),
              child: Row(children: [
                Icon(bar.$3, size: 18, color: AppPalette.fg(_kPurple)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(bar.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(_kPurple))),
                    Text(bar.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
                  ]),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() {
                    if (_editing != null) _input.clear();
                    _editing = null;
                    _replyTo = null;
                  }),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(
                tooltip: tr("Emoji"),
                icon: Icon(Icons.emoji_emotions_outlined, color: AppPalette.fg(Colors.grey.shade600)),
                onPressed: _pickEmoji,
              ),
              if (_editing == null)
                PopupMenuButton<String>(
                  tooltip: tr("Attach"),
                  icon: Icon(Icons.attach_file_rounded, color: AppPalette.fg(Colors.grey.shade600)),
                  onSelected: (v) {
                    if (v == 'photo' || v == 'file') _attach(images: v == 'photo');
                    if (v == 'location') _sendLocation();
                    if (v == 'poll') _newPoll();
                    if (v == 'video_note') _sendVideoNote();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'photo', child: Row(children: [Icon(Icons.photo_rounded, size: 18, color: Color(0xFF2563EB)), SizedBox(width: 10), Text("Photo")])),
                    PopupMenuItem(value: 'file', child: Row(children: [Icon(Icons.insert_drive_file_rounded, size: 18, color: Color(0xFF7C3AED)), SizedBox(width: 10), Text("Document or file")])),
                    PopupMenuItem(value: 'location', child: Row(children: [Icon(Icons.location_on_rounded, size: 18, color: Color(0xFF16A34A)), SizedBox(width: 10), Text("Location")])),
                    PopupMenuItem(value: 'poll', child: Row(children: [Icon(Icons.poll_rounded, size: 18, color: Color(0xFFF59E0B)), SizedBox(width: 10), Text("Poll")])),
                    PopupMenuItem(value: 'video_note', child: Row(children: [Icon(Icons.videocam_rounded, size: 18, color: Color(0xFFE11D48)), SizedBox(width: 10), Text("Video message")])),
                  ],
                ),
              Expanded(
                child: Focus(
                  onKeyEvent: (node, e) {
                    final wide = MediaQuery.of(context).size.width >= 760;
                    if (wide && _ChatPrefs.enterToSend && e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
                      _send();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) {
                      _sendTyping();
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: tr("Message"),
                      filled: true,
                      fillColor: AppPalette.bg(_kBg),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (empty && !_sending) ...[
                IconButton(
                  tooltip: tr("Video message"),
                  icon: Icon(Icons.videocam_outlined, color: AppPalette.fg(Colors.grey.shade600)),
                  onPressed: _sendVideoNote,
                ),
                CircleAvatar(
                  backgroundColor: AppPalette.bg(_kPurple),
                  child: IconButton(
                    tooltip: tr("Record a voice message"),
                    icon: const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
                    onPressed: () => setState(() => _recordingVoice = true),
                  ),
                ),
              ] else
              CircleAvatar(
                backgroundColor: AppPalette.bg(_input.text.trim().isEmpty ? Colors.grey.shade400 : _kPurple),
                child: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : IconButton(
                        tooltip: _editing != null ? "Save" : "Send",
                        icon: Icon(_editing != null ? Icons.check_rounded : Icons.send_rounded, color: AppPalette.fg(Colors.white), size: 20),
                        onPressed: _input.text.trim().isEmpty ? null : _send,
                      ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _pickEmoji() async {
    final e = await _showEmojiPicker(context);
    if (e == null || !mounted) return;
    final sel = _input.selection;
    final text = _input.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _input.value = TextEditingValue(
      text: text.replaceRange(start, end, e),
      selection: TextSelection.collapsed(offset: start + e.length),
    );
    setState(() {});
    _focus.requestFocus();
  }
}

// =====================================================================
// CHAT INFO (members, group settings, shared media)
// =====================================================================
/// Group admins: make, copy and turn off invite links; answer join requests.
class _InviteLinksDialog extends StatefulWidget {
  final ChatRoom room;
  final VoidCallback onChanged;
  const _InviteLinksDialog({required this.room, required this.onChanged});
  @override
  State<_InviteLinksDialog> createState() => _InviteLinksDialogState();
}

class _InviteLinksDialogState extends State<_InviteLinksDialog> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _links = [];
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  int _days = 7;
  int _maxUses = 0;
  bool _approval = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await _db.from('chat_invites').select().eq('room_id', widget.room.id).eq('revoked', false).order('created_at', ascending: false);
      final r = await _db.rpc('chat_join_requests_list', params: {'p_room': widget.room.id});
      if (mounted) {
        setState(() {
          _links = List<Map<String, dynamic>>.from(l);
          _requests = List<Map<String, dynamic>>.from(r as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _create() async {
    try {
      final code = await _db.rpc('create_chat_invite', params: {
        'p_room': widget.room.id,
        'p_days': _days,
        'p_max_uses': _maxUses == 0 ? null : _maxUses,
        'p_needs_approval': _approval,
      });
      await Clipboard.setData(ClipboardData(text: CallService.inviteLink(code.toString())));
      _snack("Link made and copied. Paste it in WhatsApp, SMS or email.");
      _load();
    } catch (e) {
      _snack("Couldn't make a link: ${e is PostgrestException ? e.message : e}");
    }
  }

  Future<void> _revoke(String code) async {
    await _db.from('chat_invites').update({'revoked': true}).eq('code', code);
    _load();
  }

  Future<void> _answer(String user, bool ok) async {
    await _db.rpc('answer_join_request', params: {'p_room': widget.room.id, 'p_user': user, 'p_accept': ok});
    widget.onChanged();
    _load();
  }

  String _limits(Map l) {
    final parts = <String>[];
    final exp = DateTime.tryParse((l['expires_at'] ?? '').toString());
    parts.add(exp == null ? "Never expires" : "Until ${DateFormat('d MMM, HH:mm').format(exp.toLocal())}");
    parts.add(l['max_uses'] == null ? "${l['uses']} joined" : "${l['uses']} of ${l['max_uses']} used");
    if (l['needs_approval'] == true) parts.add("admin approves");
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Invite to ${widget.room.name}"),
      content: SizedBox(
        width: 460,
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  const Text("Anyone with an approved account who opens the link can join this group."),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.center, children: [
                    DropdownButton<int>(
                      value: _days,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text("1 day")),
                        DropdownMenuItem(value: 7, child: Text("7 days")),
                        DropdownMenuItem(value: 30, child: Text("30 days")),
                        DropdownMenuItem(value: 0, child: Text("Never expires")),
                      ],
                      onChanged: (v) => setState(() => _days = v ?? 7),
                    ),
                    DropdownButton<int>(
                      value: _maxUses,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text("No limit")),
                        DropdownMenuItem(value: 1, child: Text("1 person")),
                        DropdownMenuItem(value: 10, child: Text("10 people")),
                        DropdownMenuItem(value: 50, child: Text("50 people")),
                        DropdownMenuItem(value: 100, child: Text("100 people")),
                      ],
                      onChanged: (v) => setState(() => _maxUses = v ?? 0),
                    ),
                    FilterChip(label: const Text("Admin approves"), selected: _approval, onSelected: (v) => setState(() => _approval = v)),
                  ]),
                  const SizedBox(height: 8),
                  Center(child: ElevatedButton.icon(onPressed: _create, icon: const Icon(Icons.add_link_rounded), label: const Text("Make a new link"))),
                  if (_links.isNotEmpty) ...[
                    const Divider(height: 24),
                    const Text("Active links", style: TextStyle(fontWeight: FontWeight.bold)),
                    for (final l in _links)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.link_rounded),
                        title: SelectableText(CallService.inviteLink(l['code'].toString()), maxLines: 1, style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text(_limits(l)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: tr("Copy"),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: CallService.inviteLink(l['code'].toString())));
                              _snack("Link copied");
                            },
                          ),
                          IconButton(tooltip: tr("Turn off"), icon: Icon(Icons.link_off_rounded, size: 18, color: AppPalette.fg(Colors.red.shade700)), onPressed: () => _revoke(l['code'].toString())),
                        ]),
                      ),
                  ],
                  if (_requests.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text("Asking to join (${_requests.length})", style: const TextStyle(fontWeight: FontWeight.bold)),
                    for (final q in _requests)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text((q['full_name'] ?? 'Someone').toString()),
                        subtitle: Text([q['location'], q['department']].where((x) => (x ?? '').toString().isNotEmpty).join(' · ')),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: tr("Accept"), icon: Icon(Icons.check_circle_rounded, color: AppPalette.fg(Colors.green.shade700)), onPressed: () => _answer(q['user_id'].toString(), true)),
                          IconButton(tooltip: tr("Decline"), icon: Icon(Icons.cancel_rounded, color: AppPalette.fg(Colors.red.shade700)), onPressed: () => _answer(q['user_id'].toString(), false)),
                        ]),
                      ),
                  ],
                ]),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
    );
  }
}

/// A call in the chat history: "📞 Voice call · 3:12", "Missed video call" …
class _CallLine extends StatelessWidget {
  final String text;
  final VoidCallback onCall;
  const _CallLine({required this.text, required this.onCall});
  @override
  Widget build(BuildContext context) {
    final missed = text.contains('Missed') || text.contains('declined');
    final video = text.contains('🎥');
    final label = text.replaceAll('📞 ', '').replaceAll('🎥 ', '');
    return InkWell(
      onTap: onCall,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppPalette.bg((missed ? Colors.red : const Color(0xFF16A34A)).withValues(alpha: 0.12)),
            child: Icon(video ? Icons.videocam_rounded : (missed ? Icons.call_missed_rounded : Icons.call_rounded),
                size: 17, color: AppPalette.fg(missed ? Colors.red.shade700 : const Color(0xFF16A34A))),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.fg(missed ? Colors.red.shade700 : Colors.black87))),
              Text(text.contains('started') ? "Tap to join" : "Tap to call back", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ChatInfoPanel extends StatefulWidget {
  final ChatRoom room;
  final VoidCallback onChanged;
  final VoidCallback onLeft;
  const _ChatInfoPanel({super.key, required this.room, required this.onChanged, required this.onLeft});

  @override
  State<_ChatInfoPanel> createState() => _ChatInfoPanelState();
}

class _ChatInfoPanelState extends State<_ChatInfoPanel> {
  List<ChatPerson> _members = [];
  List<ChatMessage> _media = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await ChatService.members(widget.room.id);
      final media = await Supabase.instance.client
          .from('chat_messages')
          .select()
          .eq('room_id', widget.room.id)
          .eq('kind', 'image')
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(12);
      if (!mounted) return;
      setState(() {
        _members = m;
        _media = (media as List).map((x) => ChatMessage.fromMap(x as Map)).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _editGroup() async {
    final nameC = TextEditingController(text: widget.room.name);
    final descC = TextEditingController(text: widget.room.description ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit group"),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameC, decoration: InputDecoration(labelText: tr("Group name"), border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: descC, maxLines: 3, decoration: InputDecoration(labelText: tr("Description"), border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
        ],
      ),
    );
    if (ok != true || nameC.text.trim().isEmpty) return;
    try {
      await ChatService.updateGroup(widget.room.id, name: nameC.text.trim(), description: descC.text.trim());
      widget.onChanged();
    } catch (_) {
      _snack("Only group admins can edit the group.");
    }
  }

  Future<void> _addPeople() async {
    final picked = await showDialog<List<ChatPerson>>(
      context: context,
      builder: (_) => _PeoplePicker(title: "Add people", multi: true, exclude: _members.map((m) => m.id).toSet()),
    );
    if (picked == null || picked.isEmpty) return;
    try {
      await ChatService.addMembers(widget.room.id, picked.map((p) => p.id).toList());
      await _load();
      widget.onChanged();
    } catch (_) {
      _snack("Only group admins can add people.");
    }
  }

  Future<void> _memberMenu(ChatPerson p) async {
    if (!widget.room.isAdmin || p.id == ChatService.myId || p.memberRole == 'owner') return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold))),
          if (p.memberRole == 'member')
            ListTile(leading: const Icon(Icons.admin_panel_settings_outlined), title: const Text("Make group admin"), onTap: () => Navigator.pop(ctx, 'admin')),
          if (p.memberRole == 'admin')
            ListTile(leading: const Icon(Icons.person_outline), title: const Text("Remove as admin"), onTap: () => Navigator.pop(ctx, 'member')),
          ListTile(
            leading: Icon(Icons.person_remove_outlined, color: AppPalette.fg(Colors.red.shade700)),
            title: Text("Remove from group", style: TextStyle(color: AppPalette.fg(Colors.red.shade700))),
            onTap: () => Navigator.pop(ctx, 'remove'),
          ),
        ]),
      ),
    );
    try {
      if (choice == 'admin' || choice == 'member') await ChatService.setMemberRole(widget.room.id, p.id, choice!);
      if (choice == 'remove') await ChatService.removeMember(widget.room.id, p.id);
      if (choice != null) {
        await _load();
        widget.onChanged();
      }
    } catch (_) {
      _snack("Couldn't change this member.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.room;
    return Container(
      color: AppPalette.bg(Colors.white),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Center(child: _Avatar(name: r.name, url: r.avatarUrl, size: 88, group: r.isGroup && (r.avatarUrl ?? '').isEmpty)),
              const SizedBox(height: 10),
              Text(r.name, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18)),
              if ((r.description ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(r.description!, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey.shade700), fontSize: 12.5)),
                ),
              if (!r.isGroup && r.otherUserId != null)
                Builder(builder: (_) {
                  final other = _members.where((m) => m.id == r.otherUserId).firstOrNull;
                  final seen = _lastSeenText(
                    online: _isOnline(r.otherUserId, other?.onlineVisible ?? r.otherOnlineVisible),
                    visible: other?.onlineVisible ?? r.otherOnlineVisible,
                    lastSeen: other?.lastSeen ?? r.otherLastSeen,
                  );
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(children: [
                      if ((other?.username ?? r.otherUsername ?? '').isNotEmpty)
                        Text("@${other?.username ?? r.otherUsername}", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(_kBlue), fontSize: 13)),
                      Text(seen, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(seen == 'online' ? const Color(0xFF16A34A) : Colors.grey.shade600), fontSize: 12)),
                      if (other != null && other.subtitle.isNotEmpty)
                        Text(other.subtitle, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey.shade700), fontSize: 12.5)),
                    ]),
                  );
                }),
              const SizedBox(height: 14),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                if (r.isGroup && r.isAdmin)
                  OutlinedButton.icon(onPressed: _editGroup, icon: const Icon(Icons.edit_rounded, size: 16), label: const Text("Edit")),
                if (r.isGroup && r.isAdmin)
                  OutlinedButton.icon(onPressed: _addPeople, icon: const Icon(Icons.person_add_alt_1_rounded, size: 16), label: const Text("Add")),
                if (r.isGroup && r.isAdmin)
                  OutlinedButton.icon(
                    onPressed: () => showDialog(context: context, builder: (_) => _InviteLinksDialog(room: r, onChanged: () async {
                      await _load();
                      widget.onChanged();
                    })),
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: const Text("Invite link"),
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ChatService.setMyFlag(r.id, 'muted', !r.muted);
                    widget.onChanged();
                  },
                  icon: Icon(r.muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, size: 16),
                  label: Text(r.muted ? "Unmute" : "Mute"),
                ),
                if (!r.isGroup && r.otherUserId != null) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ChatService.saveContact(r.otherUserId!);
                      _snack("Added to your contacts.");
                    },
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
                    label: const Text("Add contact"),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppPalette.fg(Colors.red.shade700)),
                    onPressed: () async {
                      if (r.blocked) {
                        await ChatService.unblock(r.otherUserId!);
                      } else {
                        await ChatService.block(r.otherUserId!);
                      }
                      widget.onChanged();
                    },
                    icon: const Icon(Icons.block, size: 16),
                    label: Text(r.blocked ? "Unblock" : "Block"),
                  ),
                ],
              ]),
              if (_media.isNotEmpty) ...[
                const Divider(height: 30),
                Text("Shared photos", style: TextStyle(fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[700]), fontSize: 12.5)),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  children: [
                    for (final m in _media)
                      FutureBuilder<String?>(
                        future: ChatService.fileUrl(m.attachmentPath ?? ''),
                        builder: (_, s) => ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: s.data == null
                              ? Container(color: AppPalette.bg(Colors.grey.shade200))
                              : Image.network(s.data!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: AppPalette.bg(Colors.grey.shade200))),
                        ),
                      ),
                  ],
                ),
              ],
              const Divider(height: 30),
              Text(r.isGroup ? "${_members.length} members" : "People", style: TextStyle(fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[700]), fontSize: 12.5)),
              const SizedBox(height: 4),
              for (final p in _members)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: _PresenceAvatar(name: p.name, url: p.avatarUrl, size: 36, userId: p.id, visible: p.onlineVisible),
                  title: Text(p.id == ChatService.myId ? "${p.name} (you)" : p.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: p.subtitle.isEmpty ? null : Text(p.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: r.isGroup && p.memberRole != 'member'
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppPalette.bg(_kPurple.withValues(alpha: 0.1)), borderRadius: BorderRadius.circular(6)),
                          child: Text(p.memberRole == 'owner' ? 'Owner' : 'Admin',
                              style: TextStyle(fontSize: 10.5, color: AppPalette.fg(_kPurple), fontWeight: FontWeight.bold)),
                        )
                      : null,
                  onTap: () => _memberMenu(p),
                ),
              if (r.isGroup) ...[
                const Divider(height: 24),
                TextButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text("Leave \"${r.name}\"?"),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Leave", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await ChatService.leave(r.id);
                      widget.onLeft();
                    }
                  },
                  icon: Icon(Icons.logout_rounded, color: AppPalette.fg(Colors.red.shade700)),
                  label: Text("Leave group", style: TextStyle(color: AppPalette.fg(Colors.red.shade700))),
                ),
              ],
            ]),
    );
  }
}

// =====================================================================
// PEOPLE PICKER + NEW GROUP
// =====================================================================
class _PeoplePicker extends StatefulWidget {
  final String title;
  final bool multi;
  final Set<String> exclude;
  const _PeoplePicker({required this.title, required this.multi, this.exclude = const {}});

  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  List<ChatPerson> _results = [];
  final Map<String, ChatPerson> _picked = {};
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final r = await ChatService.contacts(q);
      if (mounted) {
        setState(() {
          _results = r.where((p) => !widget.exclude.contains(p.id)).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: size.width < 500 ? 12 : 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: size.height * 0.85),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              Expanded(child: Text(widget.title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            TextField(
              autofocus: true,
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () => _search(v));
              },
              decoration: InputDecoration(
                hintText: tr("Search by name, location or department"),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (widget.multi && _picked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 36,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final p in _picked.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InputChip(label: Text(p.name), onDeleted: () => setState(() => _picked.remove(p.id))),
                      ),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(child: Text("Nobody found.", style: TextStyle(color: AppPalette.fg(Colors.grey.shade600))))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final p = _results[i];
                            final sel = _picked.containsKey(p.id);
                            return ListTile(
                              leading: _Avatar(name: p.name, url: p.avatarUrl, size: 38),
                              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: p.subtitle.isEmpty ? null : Text(p.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: widget.multi ? Checkbox(value: sel, onChanged: (_) => _toggle(p)) : null,
                              onTap: () => widget.multi ? _toggle(p) : Navigator.pop(context, [p]),
                            );
                          },
                        ),
            ),
            if (widget.multi)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_kPurple), foregroundColor: AppPalette.fg(Colors.white)),
                    onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked.values.toList()),
                    child: Text("Add ${_picked.length}"),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  void _toggle(ChatPerson p) => setState(() => _picked.containsKey(p.id) ? _picked.remove(p.id) : _picked[p.id] = p);
}

class _NewGroupDialog extends StatefulWidget {
  const _NewGroupDialog();

  @override
  State<_NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends State<_NewGroupDialog> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  List<ChatPerson> _people = [];

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text("New group", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: tr("Group name"), border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(controller: _desc, maxLines: 2, decoration: InputDecoration(labelText: tr("Description (optional)"), border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text("${_people.length} people added", style: const TextStyle(fontWeight: FontWeight.bold))),
              TextButton.icon(
                onPressed: () async {
                  final picked = await showDialog<List<ChatPerson>>(
                    context: context,
                    builder: (_) => _PeoplePicker(title: "Add people", multi: true, exclude: _people.map((p) => p.id).toSet()),
                  );
                  if (picked != null) setState(() => _people = [..._people, ...picked]);
                },
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text("Add people"),
              ),
            ]),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in _people) InputChip(label: Text(p.name), onDeleted: () => setState(() => _people.remove(p))),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_kPurple), foregroundColor: AppPalette.fg(Colors.white)),
          onPressed: _name.text.trim().isEmpty ? null : () => Navigator.pop(context, (_name.text.trim(), _desc.text.trim(), _people)),
          child: const Text("Create"),
        ),
      ],
    );
  }
}
