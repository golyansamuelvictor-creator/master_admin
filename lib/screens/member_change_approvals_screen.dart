// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';

/// Member Bio › Member profile › Approve member profile changes.
///
/// Changes proposed by cell leaders (member_change_submit), with the old and
/// new value of every field. Leaders above the cell, Internal Affairs and the
/// admin approve (the member list is updated) or reject with a note. The
/// requester sees the status of their own proposals here too.
class MemberChangeApprovalsScreen extends StatefulWidget {
  const MemberChangeApprovalsScreen({super.key});
  @override
  State<MemberChangeApprovalsScreen> createState() => _MemberChangeApprovalsScreenState();
}

class _MemberChangeApprovalsScreenState extends State<MemberChangeApprovalsScreen> {
  static const Color _purple = Color(0xFF4A148C);
  static const _tabs = [('pending', "Pending", Icons.pending_actions_rounded), ('approved', "Approved", Icons.verified_rounded), ('rejected', "Rejected", Icons.block_rounded)];
  final _db = Supabase.instance.client;
  final Map<String, List<Map<String, dynamic>>> _rows = {};
  final Set<String> _busy = {};
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([for (final t in _tabs) _db.rpc('member_change_list', params: {'p_status': t.$1})]);
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < _tabs.length; i++) {
          _rows[_tabs[i].$1] = List<Map<String, dynamic>>.from((r[i] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't load the changes (run 15_round14.sql): ${e is PostgrestException ? e.message : e}");
    }
  }

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    String? note;
    if (!approve) {
      final c = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Reason for rejecting"),
          content: TextField(controller: c, autofocus: true, maxLines: 3, decoration: InputDecoration(hintText: tr("e.g. the phone number is wrong"), border: const OutlineInputBorder())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text("Reject")),
          ],
        ),
      );
      if (note == null) return;
    }
    setState(() => _busy.add(r['id'].toString()));
    try {
      await _db.rpc('member_change_decide', params: {'p_id': r['id'], 'p_approve': approve, 'p_note': note});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approve ? "Approved: ${r['member_name']}'s profile is updated." : "Rejected. The cell leader is told why."),
          backgroundColor: approve ? const Color(0xFF2E7D32) : null,
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: ${e is PostgrestException ? e.message : e}"), backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _busy.remove(r['id'].toString()));
    }
  }

  String _fmt(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? '—' : s;
  }

  Widget _card(Map<String, dynamic> r) {
    final changes = Map<String, dynamic>.from((r['changes'] as Map?) ?? const {});
    final old = Map<String, dynamic>.from((r['old_values'] as Map?) ?? const {});
    final labels = Map<String, dynamic>.from((r['labels'] as Map?) ?? const {});
    final when = DateTime.tryParse((r['created_at'] ?? '').toString())?.toLocal();
    final reviewed = DateTime.tryParse((r['reviewed_at'] ?? '').toString())?.toLocal();
    final status = (r['status'] ?? '').toString();
    final color = status == 'approved' ? const Color(0xFF2E7D32) : (status == 'rejected' ? Colors.red.shade700 : const Color(0xFFEF6C00));
    final busy = _busy.contains(r['id'].toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line(color.withValues(alpha: 0.25))),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppPalette.bg(_purple.withValues(alpha: 0.1)),
              child: Text(_fmt(r['member_name']).substring(0, 1).toUpperCase(), style: TextStyle(color: AppPalette.fg(_purple), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_fmt(r['member_name']), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14)),
                Text([r['unit'], if ((r['scj_id'] ?? '').toString().isNotEmpty) "SCJ ${r['scj_id']}"].where((x) => (x ?? '').toString().isNotEmpty).join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: AppPalette.bg(color.withValues(alpha: 0.12)), borderRadius: BorderRadius.circular(10)),
              child: Text(status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(color))),
            ),
          ]),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Table(
            columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.4), 2: FixedColumnWidth(22), 3: FlexColumnWidth(1.4)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (final e in changes.entries)
                TableRow(children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text((labels[e.key] ?? e.key).toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  Text(_fmt(old[e.key]), style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade600), decoration: TextDecoration.lineThrough)),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: AppPalette.fg(Colors.grey)),
                  Text(_fmt(e.value), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(const Color(0xFF0D47A1)))),
                ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
          child: Text(
            [
              "Proposed by ${_fmt(r['requested_by_name'])}${when == null ? '' : ' · ${DateFormat('d MMM yyyy, HH:mm').format(when)}'}",
              if (status != 'pending') "${status == 'approved' ? 'Approved' : 'Rejected'} by ${_fmt(r['reviewed_by_name'])}${reviewed == null ? '' : ' · ${DateFormat('d MMM yyyy').format(reviewed)}'}",
              if ((r['review_note'] ?? '').toString().isNotEmpty) "Note: ${r['review_note']}",
            ].join('\n'),
            style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700)),
          ),
        ),
        if (r['can_decide'] == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => _decide(r, false),
                icon: Icon(Icons.close_rounded, size: 18, color: AppPalette.fg(Colors.red.shade700)),
                label: Text("Reject", style: TextStyle(color: AppPalette.fg(Colors.red.shade700))),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: busy ? null : () => _decide(r, true),
                icon: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded, size: 18),
                label: const Text("Approve"),
                style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(const Color(0xFF2E7D32)), foregroundColor: AppPalette.fg(Colors.white)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _list(String status) {
    final all = _rows[status];
    if (all == null) return const Center(child: CircularProgressIndicator());
    final q = _q.trim().toLowerCase();
    final rows = q.isEmpty ? all : all.where((r) => '${r['member_name']} ${r['unit']} ${r['scj_id']} ${r['requested_by_name']}'.toLowerCase().contains(q)).toList();
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(status == 'pending' ? "No profile changes are waiting for you." : "Nothing here yet.", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey.shade600))),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 40), children: [for (final r in rows) _card(r)]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFF3F5FA)),
        appBar: AppBar(
          centerTitle: true,
          title: Text("Member profile changes", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_purple))),
          actions: [IconButton(tooltip: tr("Refresh"), onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
          bottom: TabBar(
            tabs: [for (final t in _tabs) Tab(icon: Icon(t.$3, size: 18), text: "${t.$2}${_rows[t.$1] == null ? '' : ' (${_rows[t.$1]!.length})'}")],
          ),
        ),
        body: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: TextField(
                        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr("Search member, unit or cell leader"), isDense: true, border: const OutlineInputBorder()),
                        onChanged: (v) => setState(() => _q = v),
                      ),
                    ),
                  ),
                ),
                Expanded(child: TabBarView(children: [for (final t in _tabs) _list(t.$1)])),
              ]),
      ),
    );
  }
}
