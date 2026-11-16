import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';

/// Version history of a Doc, Slides or Sheet (26_round25.sql keeps a copy at
/// most every 10 minutes while it is edited). [onRestore] gets the chosen
/// copy's content and puts it back; the current state is kept as a copy
/// first, so a restore can itself be undone.
Future<void> showOfficeHistory(
  BuildContext context, {
  required String kind, // doc | slides | sheet
  required String fileId,
  required String title,
  required Object? Function() currentContent, // null = not open: nothing to keep
  required Future<void> Function(Map<String, dynamic> version) onRestore,
}) async {
  final db = Supabase.instance.client;
  List<Map<String, dynamic>> rows = [];
  String? error;
  try {
    rows = List<Map<String, dynamic>>.from(
      await db.from('office_versions').select('id, title, saved_at, content').eq('file_id', fileId).order('saved_at', ascending: false).limit(50),
    );
  } catch (e) {
    error = "Version history isn't available right now.";
  }
  if (!context.mounted) return;
  final fmt = DateFormat('EEE d MMM yyyy, HH:mm');
  await showDialog(
    context: context,
    builder: (dctx) => AlertDialog(
      title: Text.rich(TextSpan(text: "${tr('Version history')} · $title"), maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 460,
        height: 420,
        child: error != null
            ? Center(child: Text(error))
            : rows.isEmpty
                ? const Center(child: Text("No earlier versions yet. A copy is kept every 10 minutes while you work.", textAlign: TextAlign.center))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final at = DateTime.tryParse((r['saved_at'] ?? '').toString())?.toLocal();
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppPalette.bg(const Color(0xFFEDE7F6)),
                          child: Icon(Icons.history_rounded, size: 18, color: AppPalette.fg(const Color(0xFF4A148C))),
                        ),
                        title: Text.rich(TextSpan(text: at == null ? '' : fmt.format(at)), style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        subtitle: Text.rich(TextSpan(text: (r['title'] ?? '').toString()), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: dctx,
                              builder: (c) => AlertDialog(
                                title: const Text("Restore this version?"),
                                content: const Text("The file goes back to this version. What it looks like now is kept in the history, so you can come back to it."),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
                                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text("Restore")),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            try {
                              final now = currentContent();
                              if (now != null) {
                                await db.from('office_versions').insert({'kind': kind, 'file_id': fileId, 'title': title, 'content': now});
                              }
                              await onRestore(r);
                              if (dctx.mounted) Navigator.pop(dctx);
                            } catch (e) {
                              if (dctx.mounted) {
                                ScaffoldMessenger.of(dctx).showSnackBar(SnackBar(content: Text("Couldn't restore: $e")));
                              }
                            }
                          },
                          child: const Text("Restore"),
                        ),
                      );
                    },
                  ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: const Text("Close"))],
    ),
  );
}
