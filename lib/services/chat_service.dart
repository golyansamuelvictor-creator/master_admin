import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_refresh.dart';

/// One chat in the signed-in user's list (from my_chat_rooms()).
class ChatRoom {
  final String id;
  final String kind; // dm | group
  final String name;
  final String? description;
  final String? avatarUrl;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastSenderId;
  final int unread;
  final bool pinned;
  final bool muted;
  final bool archived;
  final String myRole; // owner | admin | member
  final int memberCount;
  final String? otherUserId;
  final DateTime? otherLastReadAt;
  final String? otherUsername;
  final DateTime? otherLastSeen; // null when their privacy hides it
  final bool otherOnlineVisible;
  final bool blocked;

  const ChatRoom({
    required this.id,
    required this.kind,
    required this.name,
    this.description,
    this.avatarUrl,
    this.lastMessage,
    this.lastMessageAt,
    this.lastSenderId,
    this.unread = 0,
    this.pinned = false,
    this.muted = false,
    this.archived = false,
    this.myRole = 'member',
    this.memberCount = 0,
    this.otherUserId,
    this.otherLastReadAt,
    this.otherUsername,
    this.otherLastSeen,
    this.otherOnlineVisible = false,
    this.blocked = false,
  });

  bool get isGroup => kind == 'group';
  bool get isAdmin => myRole == 'owner' || myRole == 'admin';

  factory ChatRoom.fromMap(Map m) => ChatRoom(
        id: m['room_id'].toString(),
        kind: (m['kind'] ?? 'group').toString(),
        name: (m['name'] ?? 'Chat').toString(),
        description: m['description']?.toString(),
        avatarUrl: m['avatar_url']?.toString(),
        lastMessage: m['last_message']?.toString(),
        lastMessageAt: DateTime.tryParse((m['last_message_at'] ?? '').toString())?.toLocal(),
        lastSenderId: m['last_sender_id']?.toString(),
        unread: (m['unread'] as num?)?.toInt() ?? 0,
        pinned: m['pinned'] == true,
        muted: m['muted'] == true,
        archived: m['archived'] == true,
        myRole: (m['my_role'] ?? 'member').toString(),
        memberCount: (m['member_count'] as num?)?.toInt() ?? 0,
        otherUserId: m['other_user_id']?.toString(),
        otherLastReadAt: DateTime.tryParse((m['other_last_read_at'] ?? '').toString())?.toLocal(),
        otherUsername: m['other_username']?.toString(),
        otherLastSeen: DateTime.tryParse((m['other_last_seen'] ?? '').toString())?.toLocal(),
        otherOnlineVisible: m['other_online_visible'] == true,
        blocked: m['blocked'] == true,
      );
}

class ChatMessage {
  final String id;
  final String roomId;
  final String? senderId;
  final String senderEmail;
  final String content;
  final String kind; // text | image | file | audio | video
  final String? attachmentPath;
  final String? attachmentName;
  final int? attachmentSize;
  final String? attachmentMime;
  final String? replyTo;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;

  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderEmail,
    required this.content,
    required this.kind,
    required this.createdAt,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentSize,
    this.attachmentMime,
    this.replyTo,
    this.editedAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;
  bool get hasAttachment => (attachmentPath ?? '').isNotEmpty;

  factory ChatMessage.fromMap(Map m) => ChatMessage(
        id: m['id'].toString(),
        roomId: (m['room_id'] ?? '').toString(),
        senderId: m['sender_id']?.toString(),
        senderEmail: (m['sender_email'] ?? '').toString(),
        content: (m['content'] ?? '').toString(),
        kind: (m['kind'] ?? 'text').toString(),
        attachmentPath: m['attachment_path']?.toString(),
        attachmentName: m['attachment_name']?.toString(),
        attachmentSize: (m['attachment_size'] as num?)?.toInt(),
        attachmentMime: m['attachment_mime']?.toString(),
        replyTo: m['reply_to']?.toString(),
        createdAt: (DateTime.tryParse((m['created_at'] ?? '').toString()) ?? DateTime.now()).toLocal(),
        editedAt: DateTime.tryParse((m['edited_at'] ?? '').toString())?.toLocal(),
        deletedAt: DateTime.tryParse((m['deleted_at'] ?? '').toString())?.toLocal(),
      );
}

class ChatPerson {
  final String id;
  final String name;
  final String? role;
  final String? location;
  final String? department;
  final String? avatarUrl;
  final String memberRole; // in a group: owner | admin | member
  final DateTime? lastReadAt;
  final String? username;
  final DateTime? lastSeen; // null when their privacy hides it
  final bool onlineVisible;
  final bool isContact;
  final String? nickname;

  const ChatPerson({
    required this.id,
    required this.name,
    this.role,
    this.location,
    this.department,
    this.avatarUrl,
    this.memberRole = 'member',
    this.lastReadAt,
    this.username,
    this.lastSeen,
    this.onlineVisible = false,
    this.isContact = false,
    this.nickname,
  });

  String get displayName => (nickname ?? '').trim().isNotEmpty ? nickname!.trim() : name;

  factory ChatPerson.fromRpc(Map m) => ChatPerson(
        id: (m['id'] ?? m['user_id']).toString(),
        name: (m['full_name'] ?? 'Unknown').toString(),
        role: m['role']?.toString(),
        location: m['location']?.toString(),
        department: m['department']?.toString(),
        avatarUrl: m['avatar_url']?.toString(),
        memberRole: (m['member_role'] ?? 'member').toString(),
        lastReadAt: DateTime.tryParse((m['last_read_at'] ?? '').toString())?.toLocal(),
        username: m['username']?.toString(),
        lastSeen: DateTime.tryParse((m['last_seen'] ?? '').toString())?.toLocal(),
        onlineVisible: m['online_visible'] == true,
        isContact: m['is_contact'] == true,
        nickname: m['nickname']?.toString(),
      );

  String get subtitle => [
        if ((role ?? '').isNotEmpty) role!.replaceAll('_', ' '),
        if ((location ?? '').isNotEmpty) location!,
        if ((department ?? '').isNotEmpty) department!,
      ].join(' · ');
}

/// Data access for My Home. Everything is checked again by the database
/// (06_round6.sql): only members of a chat can read or post in it.
class ChatService {
  ChatService._();

  static const String bucket = 'chat-files';
  static SupabaseClient get _db => Supabase.instance.client;
  static String? get myId => _db.auth.currentUser?.id;

  static Future<List<ChatRoom>> rooms() async {
    final res = await _db.rpc('my_chat_rooms');
    return (res as List).map((m) => ChatRoom.fromMap(m as Map)).toList();
  }

  static Future<List<ChatPerson>> contacts(String search) async {
    final res = await _db.rpc('chat_contacts', params: {'p_search': search.trim().isEmpty ? null : search.trim()});
    return (res as List).map((m) => ChatPerson.fromRpc(m as Map)).toList();
  }

  static Future<List<ChatPerson>> members(String roomId) async {
    // 08_round7.sql: photos / last seen as each person's privacy allows
    try {
      final r = await _db.rpc('chat_room_people', params: {'p_room': roomId});
      final list = (r as List).map((m) => ChatPerson.fromRpc(m as Map)).toList();
      const order = {'owner': 0, 'admin': 1, 'member': 2};
      list.sort((a, b) {
        final x = (order[a.memberRole] ?? 3).compareTo(order[b.memberRole] ?? 3);
        return x != 0 ? x : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return list;
    } catch (_) {}
    final res = await _db
        .from('chat_members')
        .select('user_id, role, last_read_at, profiles(full_name, role, location, department, avatar_url)')
        .eq('room_id', roomId);
    final list = (res as List).map((m) {
      final p = m['profiles'] is Map ? m['profiles'] as Map : const {};
      return ChatPerson(
        id: m['user_id'].toString(),
        name: (p['full_name'] ?? 'Unknown').toString(),
        role: p['role']?.toString(),
        location: p['location']?.toString(),
        department: p['department']?.toString(),
        avatarUrl: p['avatar_url']?.toString(),
        memberRole: (m['role'] ?? 'member').toString(),
        lastReadAt: DateTime.tryParse((m['last_read_at'] ?? '').toString())?.toLocal(),
      );
    }).toList();
    const order = {'owner': 0, 'admin': 1, 'member': 2};
    list.sort((a, b) {
      final r = (order[a.memberRole] ?? 3).compareTo(order[b.memberRole] ?? 3);
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  static Future<String> startDirect(String otherUserId) async =>
      (await _db.rpc('start_direct_chat', params: {'p_other': otherUserId})).toString();

  static Future<String> createGroup(String name, String description, List<String> memberIds) async =>
      (await _db.rpc('create_group_chat', params: {
        'p_name': name,
        'p_description': description,
        'p_members': memberIds,
      }))
          .toString();

  static Future<void> addMembers(String roomId, List<String> ids) =>
      _db.rpc('add_chat_members', params: {'p_room': roomId, 'p_members': ids});

  static Future<void> removeMember(String roomId, String userId) =>
      _db.from('chat_members').delete().eq('room_id', roomId).eq('user_id', userId);

  static Future<void> setMemberRole(String roomId, String userId, String role) =>
      _db.from('chat_members').update({'role': role}).eq('room_id', roomId).eq('user_id', userId);

  static Future<void> leave(String roomId) async {
    final me = myId;
    if (me == null) return;
    await removeMember(roomId, me);
  }

  static Future<void> updateGroup(String roomId, {String? name, String? description}) => _db.from('chat_rooms').update({
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', roomId);

  static Future<void> setMyFlag(String roomId, String flag, bool value) async {
    final me = myId;
    if (me == null) return;
    await _db.from('chat_members').update({flag: value}).eq('room_id', roomId).eq('user_id', me);
  }

  static Future<void> markRead(String roomId) => _db.rpc('mark_chat_read', params: {'p_room': roomId});

  static Future<List<ChatMessage>> messages(String roomId, {DateTime? before, int limit = 60}) async {
    var q = _db.from('chat_messages').select().eq('room_id', roomId);
    if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
    final res = await q.order('created_at', ascending: false).limit(limit);
    return (res as List).map((m) => ChatMessage.fromMap(m as Map)).toList();
  }

  static Future<ChatMessage> sendText(String roomId, String text, {String? replyTo}) async {
    final res = await _db
        .from('chat_messages')
        .insert({
          'room_id': roomId,
          'content': text,
          'kind': 'text',
          'sender_email': _db.auth.currentUser?.email ?? '',
          if (replyTo != null) 'reply_to': replyTo,
        })
        .select()
        .single();
    return ChatMessage.fromMap(res);
  }

  static String kindForMime(String mime) {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('audio/')) return 'audio';
    if (mime.startsWith('video/')) return 'video';
    return 'file';
  }

  static String mimeFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'webm': 'video/webm',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'zip': 'application/zip',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  static Future<ChatMessage> sendFile(String roomId, Uint8List bytes, String fileName,
      {String caption = '', String? replyTo, String? kind, String? mime}) async {
    mime ??= mimeFor(fileName);
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$roomId/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _db.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: false));
    final res = await _db
        .from('chat_messages')
        .insert({
          'room_id': roomId,
          'content': caption,
          'kind': kind ?? kindForMime(mime),
          'sender_email': _db.auth.currentUser?.email ?? '',
          'attachment_path': path,
          'attachment_name': fileName,
          'attachment_size': bytes.length,
          'attachment_mime': mime,
          if (replyTo != null) 'reply_to': replyTo,
        })
        .select()
        .single();
    return ChatMessage.fromMap(res);
  }

  static Future<void> edit(String messageId, String text) => _db
      .from('chat_messages')
      .update({'content': text, 'edited_at': DateTime.now().toUtc().toIso8601String()}).eq('id', messageId);

  static Future<void> deleteForEveryone(String messageId) => _db.from('chat_messages').update({
        'content': '',
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', messageId);

  // ------------------------------------------------------------------
  // Round 7: presence, contacts, privacy, blocks, polls, location
  // ------------------------------------------------------------------
  static Future<void> touch() async {
    try {
      await _db.rpc('chat_touch');
    } catch (_) {}
  }

  static Future<List<ChatPerson>> myContacts() async {
    final r = await _db.rpc('my_contacts');
    return (r as List).map((m) => ChatPerson.fromRpc({...(m as Map), 'is_contact': true})).toList();
  }

  static Future<void> saveContact(String id, {String? nickname}) async {
    final me = myId;
    if (me == null) return;
    await _db.from('chat_saved_contacts').upsert({'owner_id': me, 'contact_id': id, 'nickname': (nickname ?? '').trim().isEmpty ? null : nickname!.trim()});
  }

  static Future<void> removeContact(String id) => _db.from('chat_saved_contacts').delete().eq('owner_id', myId ?? '').eq('contact_id', id);

  static Future<void> block(String id) async {
    final me = myId;
    if (me == null) return;
    await _db.from('chat_blocks').upsert({'blocker_id': me, 'blocked_id': id});
  }

  static Future<void> unblock(String id) => _db.from('chat_blocks').delete().eq('blocker_id', myId ?? '').eq('blocked_id', id);

  static Future<List<ChatPerson>> blocked() async {
    final r = await _db.from('chat_blocks').select('blocked_id, profiles!chat_blocks_blocked_id_fkey(full_name, username)').eq('blocker_id', myId ?? '');
    return (r as List).map((m) {
      final p = m['profiles'] is Map ? m['profiles'] as Map : const {};
      return ChatPerson(id: m['blocked_id'].toString(), name: (p['full_name'] ?? 'Unknown').toString(), username: p['username']?.toString());
    }).toList();
  }

  static Future<Map<String, dynamic>> myProfile() async {
    final me = myId;
    if (me == null) return {};
    final r = await _db.from('profiles').select().eq('id', me).maybeSingle();
    final u = (r?['avatar_url'] ?? '').toString().trim();
    if (r != null) myAvatarUrl.value = u;
    return r == null ? {} : Map<String, dynamic>.from(r);
  }

  static Future<String?> setUsername(String u) async => (await _db.rpc('set_username', params: {'p_username': u}))?.toString();

  static Future<void> setBio(String bio) => updateMyProfile({'bio': bio});

  /// Uploads a new profile photo (public "avatars" bucket, own folder) and saves it on the profile.
  static Future<String> uploadAvatar(Uint8List bytes, String fileName) async {
    final me = myId!;
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';
    final path = '$me/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('avatars').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeFor(fileName), upsert: true));
    final url = _db.storage.from('avatars').getPublicUrl(path);
    await _db.from('profiles').update({'avatar_url': url}).eq('id', me);
    myAvatarUrl.value = url;
    return url;
  }

  static Future<Map<String, dynamic>> privacy() async {
    final me = myId;
    if (me == null) return {};
    try {
      final r = await _db.from('user_privacy').select().eq('user_id', me).maybeSingle();
      return r == null ? {} : Map<String, dynamic>.from(r);
    } catch (_) {
      return {};
    }
  }

  static Future<void> savePrivacy(Map<String, dynamic> values) async {
    final me = myId;
    if (me == null) return;
    await _db.from('user_privacy').upsert({...values, 'user_id': me, 'updated_at': DateTime.now().toUtc().toIso8601String()});
  }

  static Future<ChatMessage> sendLocation(String roomId, double lat, double lng, {String label = '', String? replyTo}) async {
    final res = await _db
        .from('chat_messages')
        .insert({
          'room_id': roomId,
          'content': '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}${label.trim().isEmpty ? '' : '|${label.trim()}'}',
          'kind': 'location',
          'sender_email': _db.auth.currentUser?.email ?? '',
          if (replyTo != null) 'reply_to': replyTo,
        })
        .select()
        .single();
    return ChatMessage.fromMap(res);
  }

  static Future<ChatMessage?> createPoll(String roomId, String question, List<String> options, {bool multiple = false, bool anonymous = false}) async {
    final id = await _db.rpc('create_chat_poll', params: {
      'p_room': roomId,
      'p_question': question,
      'p_options': options,
      'p_multiple': multiple,
      'p_anonymous': anonymous,
    });
    final row = await _db.from('chat_messages').select().eq('id', id.toString()).maybeSingle();
    return row == null ? null : ChatMessage.fromMap(row);
  }

  static Future<Map<String, dynamic>?> poll(String messageId) async {
    final r = await _db.from('chat_polls').select().eq('message_id', messageId).maybeSingle();
    return r == null ? null : Map<String, dynamic>.from(r);
  }

  static Future<List<Map<String, dynamic>>> pollResults(String messageId) async {
    final r = await _db.rpc('chat_poll_results', params: {'p_message': messageId});
    return List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  static Future<void> vote(String messageId, List<int> options) => _db.rpc('vote_chat_poll', params: {'p_message': messageId, 'p_options': options});

  static Future<void> closePoll(String messageId) => _db.from('chat_polls').update({'closed': true}).eq('message_id', messageId);

  // Private file links, cached for 50 minutes
  static final Map<String, (String, DateTime)> _links = {};

  static Future<String?> fileUrl(String path) async {
    final hit = _links[path];
    if (hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
    try {
      final url = await _db.storage.from(bucket).createSignedUrl(path, 3600);
      _links[path] = (url, DateTime.now().add(const Duration(minutes: 50)));
      return url;
    } catch (_) {
      return null;
    }
  }
}
