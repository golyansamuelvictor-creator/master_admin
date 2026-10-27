import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';

/// Member Bio › Account approvals.
///
/// Roles with the "Approve Accounts" admin action (app_roles) approve or
/// reject new accounts in their own area: church-wide roles anyone, a
/// Location Sec their location, a sub-location role their sub-location.
/// The database checks the same rule (accounts_to_approve / decide_account
/// in 09_round8.sql) and tells the person by notification.
class AccountApprovalsScreen extends StatefulWidget {
  const AccountApprovalsScreen({super.key});
  @override
  State<AccountApprovalsScreen> createState() => _AccountApprovalsScreenState();
}

class _AccountApprovalsScreenState extends State<AccountApprovalsScreen> {
  final _db = Supabase.instance.client;
  static const Color _purple = Color(0xFF4A148C);
  String _status = 'pending';
  String _search = '';
  bool _loading = true;
  String? _error;
  String? _scope;
  List<Map<String, dynamic>> _rows = [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _db.rpc('account_approval_scope'),
        _db.rpc('accounts_to_approve', params: {'p_status': _status}),
      ]);
      if (!mounted) return;
      setState(() {
        _scope = results[0]?.toString();
        _rows = List<Map<String, dynamic>>.from((results[1] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        _loading = false;
      });
    } catch (e) {
      debugPrint("Account approvals: $e");
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load accounts. Ask the admin to run 09_round8.sql.";
        });
      }
    }
  }

  void _snack(String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, backgroundColor: error ? Colors.red.shade700 : null));

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    String? reason;
    if (!approve) {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Reject ${r['full_name'] ?? 'this account'}?"),
          content: SizedBox(
            width: 380,
            child: TextField(
              controller: c,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(labelText: tr("Reason (shown to the person)"), border: OutlineInputBorder()),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
              onPressed: () {
                if (c.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text("Reject"),
            ),
          ],
        ),
      );
      if (ok != true) return;
      reason = c.text.trim();
    }
    final id = r['id'].toString();
    setState(() => _busy.add(id));
    try {
      await _db.rpc('decide_account', params: {'p_user': id, 'p_approve': approve, 'p_reason': reason});
      _snack(approve ? "${r['full_name'] ?? 'Account'} approved" : "${r['full_name'] ?? 'Account'} rejected");
      setState(() => _rows.removeWhere((x) => x['id'].toString() == id));
    } catch (e) {
      _snack(e is PostgrestException ? e.message : "Couldn't save the decision", error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  String _v(Map r, String k) {
    final s = (r[k] ?? '').toString().trim();
    return s.toLowerCase() == 'n/a' ? '' : s;
  }

  Widget _card(Map<String, dynamic> r) {
    final id = r['id'].toString();
    final name = _v(r, 'full_name').isEmpty ? _v(r, 'email') : _v(r, 'full_name');
    final unit = [_v(r, 'location'), _v(r, 'sub_location'), _v(r, 'department'), _v(r, 'team'), _v(r, 'cell_group')].where((x) => x.isNotEmpty).join(' › ');
    final created = DateTime.tryParse((r['created_at'] ?? '').toString())?.toLocal();
    Widget line(IconData i, String t) => t.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(i, size: 15, color: AppPalette.fg(Colors.grey.shade600)),
              const SizedBox(width: 6),
              Expanded(child: Text(t, style: TextStyle(fontSize: 12.5, color: AppPalette.fg(Colors.grey.shade800)))),
            ]),
          );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: AppPalette.bg(_purple.withValues(alpha: 0.1)),
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(color: AppPalette.fg(_purple), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: GoogleFonts.merriweather(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(
                  [if (_v(r, 'username').isNotEmpty) "@${_v(r, 'username')}", if (_v(r, 'role_name').isNotEmpty) _v(r, 'role_name') else _v(r, 'role')]
                      .where((x) => x.isNotEmpty)
                      .join(' · '),
                  style: TextStyle(fontSize: 12, color: AppPalette.fg(_purple), fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            if (created != null) Text(DateFormat('d MMM').format(created), style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade600))),
          ]),
          const SizedBox(height: 6),
          line(Icons.badge_outlined, _v(r, 'scj_id').isEmpty ? '' : "SCJ ID: ${_v(r, 'scj_id')}"),
          line(Icons.alternate_email, _v(r, 'email')),
          line(Icons.phone_outlined, _v(r, 'phone')),
          line(Icons.account_tree_outlined, unit),
          line(Icons.person_outline, [_v(r, 'account_type'), _v(r, 'unit_category')].where((x) => x.isNotEmpty).join(' · ')),
          if (_status == 'rejected') line(Icons.info_outline, _v(r, 'rejection_reason').isEmpty ? '' : "Reason: ${_v(r, 'rejection_reason')}"),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (_busy.contains(id))
              const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
            else ...[
              if (_status != 'rejected')
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                  onPressed: () => _decide(r, false),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text("Reject"),
                ),
              const SizedBox(width: 8),
              if (_status != 'approved')
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                  onPressed: () => _decide(r, true),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text("Approve"),
                ),
            ],
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final rows = q.isEmpty
        ? _rows
        : _rows.where((r) => ['full_name', 'email', 'scj_id', 'username', 'phone'].any((k) => (r[k] ?? '').toString().toLowerCase().contains(q))).toList();
    final scopeText = switch (_scope) {
      'church' => "You can approve accounts across the whole church.",
      'location' => "You can approve accounts in your location.",
      'sub_location' => "You can approve accounts in your sub-location.",
      _ => "Your role cannot approve accounts. An admin can give it the \"Approve Accounts\" permission.",
    };
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        title: Text("Account approvals", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [IconButton(tooltip: tr("Refresh"), onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 40), children: [
              Text(scopeText, style: TextStyle(fontSize: 12.5, color: AppPalette.fg(Colors.grey.shade700))),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'pending', icon: Icon(Icons.hourglass_top_rounded, size: 18), label: Text("Pending")),
                  ButtonSegment(value: 'rejected', icon: Icon(Icons.block_rounded, size: 18), label: Text("Rejected")),
                  ButtonSegment(value: 'approved', icon: Icon(Icons.verified_rounded, size: 18), label: Text("Approved")),
                ],
                selected: {_status},
                onSelectionChanged: (s) {
                  setState(() => _status = s.first);
                  _load();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: tr("Search by name, email, SCJ ID or phone"),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: AppPalette.bg(Colors.white),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.red.shade800))))
              else if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text(
                    _status == 'pending' ? "No accounts waiting for approval." : "Nothing here.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppPalette.fg(Colors.grey.shade600)),
                  ),
                )
              else ...[
                Text("${rows.length} account${rows.length == 1 ? '' : 's'}", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final r in rows) _card(r),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
