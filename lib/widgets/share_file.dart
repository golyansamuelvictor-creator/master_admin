import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';
import '../services/chat_service.dart';

const Color _kPurple = Color(0xFF4A148C);

/// Share a file made in the app (a document or presentation as PDF, a
/// spreadsheet as Excel): send it to chats in My Home, or to other apps.
/// [build] makes the file only when a way to share is picked.
Future<void> shareAppFile(
  BuildContext context, {
  required String fileName,
  required Future<Uint8List> Function() build,
  String mime = 'application/pdf',
  String? caption,
}) async {
  final how = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppPalette.bg(Colors.white),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Text("Share \"$fileName\"", textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: AppPalette.fg(_kPurple))),
          const SizedBox(height: 12),
          _option(ctx, 'chat', Icons.forum_rounded, const Color(0xFF24A1DE), "Send in My Home", "Pick the chats or groups to send it to"),
          _option(ctx, 'apps', Icons.ios_share_rounded, const Color(0xFF2E7D32), "Share to other apps", "WhatsApp, email, Drive …"),
        ]),
      ),
    ),
  );
  if (how == null || !context.mounted) return;
  if (how == 'apps') {
    try {
      final bytes = await build();
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, name: fileName, mimeType: mime)],
        fileNameOverrides: [fileName],
        text: caption,
        title: fileName,
      ));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't share: $e")));
    }
    return;
  }
  // My Home: choose the chats
  final rooms = await ChatService.rooms().catchError((_) => <ChatRoom>[]);
  if (!context.mounted) return;
  final picked = await showDialog<Set<String>>(context: context, builder: (_) => _ChatPicker(rooms: rooms.where((r) => !r.archived && !r.blocked).toList()));
  if (picked == null || picked.isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text("Sending …"), duration: Duration(seconds: 2)));
  try {
    final bytes = await build();
    for (final id in picked) {
      await ChatService.sendFile(id, bytes, fileName, caption: caption ?? '', mime: mime);
    }
    messenger.showSnackBar(SnackBar(content: Text("Sent to ${picked.length} chat${picked.length == 1 ? '' : 's'}"), backgroundColor: Colors.green.shade700));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't send: $e")));
  }
}

Widget _option(BuildContext ctx, String v, IconData i, Color c, String title, String sub) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppPalette.bg(c.withValues(alpha: 0.07)),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: CircleAvatar(backgroundColor: c, child: Icon(i, color: Colors.white, size: 20)),
          title: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)),
          subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.pop(ctx, v),
        ),
      ),
    );

class _ChatPicker extends StatefulWidget {
  final List<ChatRoom> rooms;
  const _ChatPicker({required this.rooms});
  @override
  State<_ChatPicker> createState() => _ChatPickerState();
}

class _ChatPickerState extends State<_ChatPicker> {
  final Set<String> _sel = {};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = widget.rooms.where((r) => q.isEmpty || r.name.toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: const Text("Send to", textAlign: TextAlign.center),
      content: SizedBox(
        width: 380,
        height: 440,
        child: Column(children: [
          TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: tr("Search chats"), isDense: true, border: const OutlineInputBorder()),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text("No chats yet. Start one in My Home.", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey))))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final r = list[i];
                      return CheckboxListTile(
                        dense: true,
                        value: _sel.contains(r.id),
                        secondary: CircleAvatar(
                          radius: 16,
                          backgroundImage: (r.avatarUrl ?? '').isEmpty ? null : NetworkImage(r.avatarUrl!),
                          child: (r.avatarUrl ?? '').isEmpty ? Icon(r.kind == 'group' ? Icons.groups_rounded : Icons.person_rounded, size: 18) : null,
                        ),
                        title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(r.kind == 'group' ? "Group · ${r.memberCount} members" : "Chat", style: const TextStyle(fontSize: 11)),
                        onChanged: (v) => setState(() => v == true ? _sel.add(r.id) : _sel.remove(r.id)),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        FilledButton.icon(
          onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, _sel),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: Text("Send${_sel.isEmpty ? '' : ' (${_sel.length})'}"),
        ),
      ],
    );
  }
}
