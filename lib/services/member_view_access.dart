import 'package:material_ui/material_ui.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/friendly_error.dart';
import '../core/i18n.dart';

/// Member details for leaders below region level (39_round35.sql):
/// they ask their immediate leader, who approves for one day; only the
/// members of their own units are ever listed.
class MemberViewAccess {
  MemberViewAccess._();
  static final _db = Supabase.instance.client;
  static Map<String, dynamic>? _status;
  static DateTime? _at;

  static Future<Map<String, dynamic>> status({bool fresh = false}) async {
    if (!fresh && _status != null && _at != null && DateTime.now().difference(_at!) < const Duration(minutes: 1)) return _status!;
    try {
      _status = Map<String, dynamic>.from(await _db.rpc('member_view_status') as Map);
    } catch (_) {
      _status = const {'needed': false}; // before 39_round35.sql: as before
    }
    _at = DateTime.now();
    return _status!;
  }

  /// True when member details may be opened now; otherwise explains and
  /// offers to ask the immediate leader.
  static Future<bool> ensure(BuildContext context) async {
    final s = await status(fresh: true);
    if (s['needed'] != true || s['granted'] == true) return true;
    if (!context.mounted) return false;
    if (s['pending'] == true) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.hourglass_top_rounded, color: Color(0xFF4A148C)),
          title: const Text("Waiting for your leader"),
          content: const Text("You asked to view member details. Your leader has been told; you can open them as soon as they approve."),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
        ),
      );
      return false;
    }
    final reason = TextEditingController();
    final ask = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_person_rounded, color: Color(0xFF4A148C)),
        title: const Text("Permission needed"),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("Member details need your immediate leader's permission. Once approved you can view the members of your own unit(s) for one day, and the leaders above you are told."),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 2,
              decoration: InputDecoration(labelText: tr("Reason (optional)"), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.send_rounded, size: 18), label: const Text("Ask my leader")),
        ],
      ),
    );
    if (ask != true || !context.mounted) return false;
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('request_member_view', params: {'p_reason': reason.text.trim()}) as Map);
      _status = null;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text.rich(TextSpan(text: "${tr('Request sent to')} ${r['approvers'] ?? tr('your leader')}.")),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text.rich(TextSpan(text: "${tr("Couldn't send the request")}${friendlyTail(e)}"))));
      }
    }
    return false;
  }

  /// The requests waiting for this leader.
  static Future<List<Map<String, dynamic>>> waiting() async {
    try {
      final r = await _db.rpc('member_view_requests_for_me');
      return List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {
      return const [];
    }
  }

  static Future<void> showRequests(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Requests());
}

class _Requests extends StatefulWidget {
  const _Requests();
  @override
  State<_Requests> createState() => _RequestsState();
}

class _RequestsState extends State<_Requests> {
  List<Map<String, dynamic>>? _rows;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await MemberViewAccess.waiting();
    if (mounted) setState(() => _rows = r);
  }

  Future<void> _decide(Map<String, dynamic> r, bool ok) async {
    final id = r['id'].toString();
    setState(() => _busy.add(id));
    try {
      await Supabase.instance.client.rpc('decide_member_view', params: {'p_id': id, 'p_approve': ok});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text.rich(TextSpan(text: ok ? "${r['name']} ${tr('may view member details for one day.')}" : tr("Request declined."))),
      ));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text.rich(TextSpan(text: "${tr("Couldn't answer")}${friendlyTail(e)}"))));
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return AlertDialog(
      title: Text("Member details requests", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: rows == null
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : rows.isEmpty
                ? const Padding(padding: EdgeInsets.all(20), child: Text("No requests waiting.", textAlign: TextAlign.center))
                : ListView(shrinkWrap: true, children: [
                    for (final r in rows)
                      Card(
                        elevation: 0,
                        color: AppPalette.bg(const Color(0xFFF7F3FC)),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text.rich(TextSpan(text: "${r['name'] ?? ''}"), style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text.rich(TextSpan(text: [(r['role'] ?? '').toString().replaceAll('_', ' '), r['units'] ?? ''].where((x) => x.toString().isNotEmpty).join(' · ')),
                                style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
                            if ((r['reason'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text.rich(TextSpan(text: "“${r['reason']}”"))),
                            Text.rich(TextSpan(text: DateFormat('d MMM HH:mm').format(DateTime.tryParse(r['created_at'].toString())?.toLocal() ?? DateTime.now())),
                                style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
                            const SizedBox(height: 6),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              TextButton(onPressed: _busy.contains(r['id'].toString()) ? null : () => _decide(r, false), child: const Text("Decline")),
                              const SizedBox(width: 6),
                              FilledButton(onPressed: _busy.contains(r['id'].toString()) ? null : () => _decide(r, true), child: const Text("Allow for one day")),
                            ]),
                          ]),
                        ),
                      ),
                  ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
    );
  }
}
