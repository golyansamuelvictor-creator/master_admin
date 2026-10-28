// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';
import '../../core/app_sizes.dart';
import '../../core/i18n.dart';

/// Transfer approvals: the requests waiting for you at your step.
/// The destination department assigns the team and cell; then the team
/// leader, cell leader, sub-location, location and Internal Affairs approve,
/// and the last step (Administration Department) moves the member.
class ApprovalInbox extends StatefulWidget {
  final String userRole;
  const ApprovalInbox({super.key, required this.userRole});
  @override
  State<ApprovalInbox> createState() => _ApprovalInboxState();
}

class _ApprovalInboxState extends State<ApprovalInbox> {
  final _db = Supabase.instance.client;
  static const Color _purple = Color(0xFF4A148C);
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  final Map<String, String> _urls = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = List<Map<String, dynamic>>.from(await _db.rpc('transfer_inbox') as List);
      // photos are private: short-lived links
      final paths = {for (final x in r) ...List<String>.from(x['photo_paths'] ?? const [])}.where((p) => !_urls.containsKey(p)).toList();
      if (paths.isNotEmpty) {
        try {
          // ignore: deprecated_member_use
          final signed = await _db.storage.from('transfer-photos').createSignedUrls(paths, 3600);
          for (final s in signed) {
            _urls[s.path] = s.signedUrl;
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _rows = r;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load the requests (run 13_round12.sql): ${e is PostgrestException ? e.message : e}";
        });
      }
    }
  }

  String _unit(dynamic u) {
    if (u is! Map) return '';
    return [u['group'], u['location'], u['sub_location'], u['department'], u['team'], u['cell_group']]
        .where((x) => (x ?? '').toString().isNotEmpty && x.toString().toUpperCase() != 'N/A')
        .join(' › ');
  }

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    String? team, cell;
    final note = TextEditingController();
    final assigns = r['assigns_team_cell'] == true && approve;
    List<Map<String, dynamic>> units = [];
    if (assigns) {
      final to = Map<String, dynamic>.from(r['to_unit'] ?? {});
      try {
        units = List<Map<String, dynamic>>.from(await _db.rpc('transfer_dest_units', params: {'p_location': to['location'], 'p_sub': to['sub_location'], 'p_dept': to['department']}) as List);
      } catch (_) {}
    }
    final teams = {for (final u in units) (u['team'] ?? '').toString()}.where((t) => t.isNotEmpty).toList()..sort();
    final teamCtl = TextEditingController(), cellCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final cells = {for (final u in units.where((u) => u['team'] == team)) (u['cell_group'] ?? '').toString()}.where((c) => c.isNotEmpty).toList()..sort();
          return AlertDialog(
            title: Text(approve ? (r['is_final'] == true ? "Confirm the transfer of ${r['member_name']}" : "Approve ${r['member_name']}") : "Reject ${r['member_name']}"),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (assigns) ...[
                  const Text("Assign the team and cell in your department:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (teams.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: team,
                      decoration: InputDecoration(labelText: tr("Team"), border: const OutlineInputBorder(), isDense: true),
                      items: [for (final t in teams) DropdownMenuItem(value: t, child: Text(t))],
                      onChanged: (v) => set(() {
                        team = v;
                        cell = null;
                      }),
                    )
                  else
                    TextField(controller: teamCtl, decoration: InputDecoration(labelText: tr("Team"), border: const OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  if (cells.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: ValueKey(team),
                      initialValue: cell,
                      decoration: InputDecoration(labelText: tr("Cell"), border: const OutlineInputBorder(), isDense: true),
                      items: [for (final c in cells) DropdownMenuItem(value: c, child: Text(c))],
                      onChanged: (v) => set(() => cell = v),
                    )
                  else
                    TextField(controller: cellCtl, decoration: InputDecoration(labelText: tr("Cell"), border: const OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 10),
                ],
                if (approve && r['is_final'] == true)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text("Confirming moves the member to the new unit in the member list.", textAlign: TextAlign.center),
                  ),
                TextField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: tr(approve ? "Note (optional)" : "Reason for rejecting"), border: const OutlineInputBorder())),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(approve ? (r['is_final'] == true ? "Confirm" : "Approve") : "Reject")),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    team ??= teamCtl.text.trim().isEmpty ? null : teamCtl.text.trim();
    cell ??= cellCtl.text.trim().isEmpty ? null : cellCtl.text.trim();
    try {
      final res = await _db.rpc('transfer_decide', params: {'p_request': r['id'], 'p_approve': approve, 'p_note': note.text.trim(), 'p_team': team, 'p_cell': cell});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res == 'completed' ? "Transfer done: ${r['member_name']} has been moved." : (res == 'rejected' ? "Rejected." : "Approved. Now with: $res")),
      ));
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't record it: ${e is PostgrestException ? e.message : e}"), backgroundColor: Colors.red.shade700));
    }
  }

  void _showPhoto(String url) => showDialog(
        context: context,
        builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain))),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        centerTitle: true,
        title: Text("Transfer approvals", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(_purple))),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : _rows.isEmpty
                  ? Center(child: Text("No transfer requests are waiting for you.", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey))))
                  : ListView.builder(
                      padding: AppSizes.page,
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        final photos = List<String>.from(r['photo_paths'] ?? const []);
                        final history = List<Map<String, dynamic>>.from(r['history'] ?? const []);
                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Row(children: [
                                Expanded(child: Text("${r['member_name'] ?? ''}", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: AppPalette.bg(_purple.withValues(alpha: 0.08)), borderRadius: BorderRadius.circular(8)),
                                  child: Text("Step ${r['step_no']}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(_purple))),
                                ),
                              ]),
                              Text("${r['step_label']}", style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
                              const SizedBox(height: 8),
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const SizedBox(width: 50, child: Text("From", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                Expanded(child: Text(_unit(r['from_unit']), style: const TextStyle(fontSize: 12))),
                              ]),
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const SizedBox(width: 50, child: Text("To", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                Expanded(child: Text(_unit(r['to_unit']), style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.green.shade800), fontWeight: FontWeight.bold))),
                              ]),
                              if ((r['reason'] ?? '').toString().isNotEmpty)
                                Padding(padding: const EdgeInsets.only(top: 6), child: Text("Reason: ${r['reason']}", style: const TextStyle(fontSize: 12))),
                              Text("Requested by ${r['requester_name'] ?? '—'} · ${DateFormat('d MMM yyyy').format(DateTime.parse(r['created_at'].toString()).toLocal())}",
                                  style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
                              if (photos.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(spacing: 6, runSpacing: 6, children: [
                                  for (final p in photos)
                                    if (_urls[p] != null)
                                      InkWell(
                                        onTap: () => _showPhoto(_urls[p]!),
                                        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(_urls[p]!, width: 80, height: 80, fit: BoxFit.cover)),
                                      ),
                                ]),
                              ],
                              if (history.isNotEmpty) ...[
                                const Divider(height: 18),
                                for (final h in history)
                                  Text("✓ ${h['step']}: ${h['by'] ?? h['role']}${(h['note'] ?? '').toString().isEmpty ? '' : ' — ${h['note']}'}",
                                      style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.blueGrey.shade700))),
                              ],
                              const SizedBox(height: 10),
                              Wrap(alignment: WrapAlignment.center, spacing: 10, children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(foregroundColor: AppPalette.fg(Colors.red.shade700)),
                                  onPressed: () => _decide(r, false),
                                  icon: const Icon(Icons.close_rounded),
                                  label: const Text("Reject"),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(Colors.green.shade700), foregroundColor: Colors.white),
                                  onPressed: () => _decide(r, true),
                                  icon: const Icon(Icons.check_rounded),
                                  label: Text(r['assigns_team_cell'] == true ? "Assign team & cell" : (r['is_final'] == true ? "Confirm transfer" : "Approve")),
                                ),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),
    );
  }
}
