import 'package:material_ui/material_ui.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/friendly_error.dart';
import '../core/i18n.dart';

const Color _kPurple = Color(0xFF4A148C);

/// Role changes waiting for me (Location Leader / Location General
/// Secretary / administrator). Shows nothing when there are none.
class RoleChangeInboxTile extends StatefulWidget {
  const RoleChangeInboxTile({super.key});
  @override
  State<RoleChangeInboxTile> createState() => _RoleChangeInboxTileState();
}

class _RoleChangeInboxTileState extends State<RoleChangeInboxTile> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client.rpc('role_change_inbox');
      if (mounted) setState(() => _items = List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map))));
    } catch (_) {
      // not set up yet / no rights: nothing to show
    }
  }

  Future<void> _open() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _InboxSheet(items: _items),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Card(
      color: AppPalette.bg(const Color(0xFFF3E8FF)),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: _kPurple, child: Icon(Icons.manage_accounts_rounded, color: Colors.white, size: 20)),
        title: Text.rich(TextSpan(text: "${_items.length} ${tr(_items.length == 1 ? 'role change to approve' : 'role changes to approve')}"),
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
        subtitle: const Text("Asked by your Location Secretary. Tap to review."),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _open,
      ),
    );
  }
}

class _InboxSheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  const _InboxSheet({required this.items});
  @override
  State<_InboxSheet> createState() => _InboxSheetState();
}

class _InboxSheetState extends State<_InboxSheet> {
  late final List<Map<String, dynamic>> _items = [...widget.items];
  final Set<String> _busy = {};

  Future<void> _decide(Map<String, dynamic> q, bool approve) async {
    String? note;
    if (!approve) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Not approve"),
          content: TextField(controller: ctrl, maxLines: 3, decoration: InputDecoration(labelText: tr("Reason (optional)"), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text("Not approve")),
          ],
        ),
      );
      if (ok != true) return;
      note = ctrl.text.trim();
    }
    final id = q['id'].toString();
    setState(() => _busy.add(id));
    try {
      await Supabase.instance.client.rpc('decide_role_change', params: {'p_id': id, 'p_approve': approve, 'p_note': note});
      if (!mounted) return;
      setState(() => _items.removeWhere((e) => e['id'].toString() == id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? "Approved: the role was changed." : "Not approved. The secretary was told.")));
      if (_items.isEmpty) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text.rich(TextSpan(text: "${tr("Couldn't save")}${friendlyTail(e)}"))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), children: [
          Text("Role changes to approve", style: GoogleFonts.merriweather(fontSize: 17, fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
          const SizedBox(height: 4),
          Text("Approve to change the role at once, or not approve with a reason.", style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
          const SizedBox(height: 10),
          for (final q in _items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(text: (q['summary'] ?? '').toString()), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(text: "${tr('Asked')} ${(q['created_at'] ?? '').toString().split('T').first}"),
                    style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade600)),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: _busy.contains(q['id'].toString()) ? null : () => _decide(q, false),
                      child: Text("Not approve", style: TextStyle(color: AppPalette.fg(Colors.red.shade700))),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _kPurple),
                      onPressed: _busy.contains(q['id'].toString()) ? null : () => _decide(q, true),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text("Approve"),
                    ),
                  ]),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
