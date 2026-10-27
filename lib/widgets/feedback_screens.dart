import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../services/device_sessions.dart';

const Color _kPurple = Color(0xFF4A148C);

const Map<String, (String, IconData, String)> kFeedbackKinds = {
  'feedback': ('Send feedback', Icons.rate_review_outlined, "What do you like, and what should be better?"),
  'bug': ('Report a bug', Icons.bug_report_outlined, "What went wrong? Which screen, and what did you tap?"),
  'feature': ('Suggest a feature', Icons.lightbulb_outline, "What would help you in your work?"),
};

const Map<String, (String, Color)> kFeedbackStatus = {
  'new': ('New', Colors.blueGrey),
  'seen': ('Seen', Colors.blue),
  'in_progress': ('In progress', Colors.orange),
  'done': ('Done', Colors.green),
  'declined': ('Not planned', Colors.red),
};

/// Settings › Feedback: a short form that saves to `app_feedback`.
class FeedbackForm extends StatefulWidget {
  final String kind;
  const FeedbackForm({super.key, required this.kind});
  @override
  State<FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends State<FeedbackForm> {
  final _db = Supabase.instance.client;
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _screen = TextEditingController();
  int _rating = 0;
  bool _sending = false;

  Future<void> _send() async {
    if (_message.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please write a little more.")));
      return;
    }
    setState(() => _sending = true);
    try {
      final me = _db.auth.currentUser;
      final p = await _db.from('profiles').select('full_name, role').eq('id', me?.id ?? '').maybeSingle();
      await _db.from('app_feedback').insert({
        'user_id': me?.id,
        'user_name': p?['full_name'],
        'user_role': p?['role'],
        'kind': widget.kind,
        'subject': _subject.text.trim().isEmpty ? null : _subject.text.trim(),
        'message': _message.text.trim(),
        'screen': _screen.text.trim().isEmpty ? null : _screen.text.trim(),
        'device': "${kIsWeb ? 'Web' : defaultTargetPlatform.name} · app ${DeviceSessions.appVersion}",
        if (_rating > 0) 'rating': _rating,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Thank you! It was sent to the administration.")));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't send: ${e is PostgrestException ? e.message : e}")));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = kFeedbackKinds[widget.kind] ?? kFeedbackKinds['feedback']!;
    InputDecoration deco(String l, {String? h}) => InputDecoration(labelText: l, hintText: h, border: const OutlineInputBorder(), isDense: true, alignLabelWithHint: true);
    return Scaffold(
      appBar: AppBar(title: Text(k.$1, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 17))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(18), children: [
            Row(children: [
              Icon(k.$2, color: AppPalette.fg(_kPurple), size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(k.$3, style: TextStyle(color: AppPalette.fg(Colors.grey.shade800)))),
            ]),
            const SizedBox(height: 16),
            if (widget.kind == 'feedback') ...[
              const Text("How is the app for you?", style: TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                for (int i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => setState(() => _rating = _rating == i ? 0 : i),
                    icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= _rating ? const Color(0xFFF59E0B) : Colors.grey, size: 32),
                  ),
              ]),
              const SizedBox(height: 8),
            ],
            TextField(controller: _subject, decoration: deco("Title (optional)")),
            const SizedBox(height: 12),
            TextField(controller: _message, minLines: 5, maxLines: 12, decoration: deco(widget.kind == 'bug' ? "What happened?" : "Your message")),
            const SizedBox(height: 12),
            if (widget.kind == 'bug') TextField(controller: _screen, decoration: deco("Screen or feature", h: "e.g. Compilation › Ranking")),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_kPurple), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _sending ? null : _send,
              icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
              label: const Text("Send"),
            ),
          ]),
        ),
      ),
    );
  }
}

/// My feedback (everyone) or the Feedback inbox (admins / "Manage Feedback").
class FeedbackListScreen extends StatefulWidget {
  final bool inbox;
  const FeedbackListScreen({super.key, this.inbox = false});
  @override
  State<FeedbackListScreen> createState() => _FeedbackListScreenState();
}

class _FeedbackListScreenState extends State<FeedbackListScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var q = _db.from('app_feedback').select();
      if (!widget.inbox) q = q.eq('user_id', _db.auth.currentUser?.id ?? '');
      final r = await q.order('created_at', ascending: false).limit(300);
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(r);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _answer(Map<String, dynamic> f) async {
    String status = (f['status'] ?? 'new').toString();
    final reply = TextEditingController(text: (f['admin_reply'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text("Answer"),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: InputDecoration(labelText: tr("Status"), border: OutlineInputBorder(), isDense: true),
                items: [for (final e in kFeedbackStatus.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1))],
                onChanged: (v) => setD(() => status = v ?? status),
              ),
              const SizedBox(height: 12),
              TextField(controller: reply, maxLines: 4, decoration: InputDecoration(labelText: tr("Reply to the sender (optional)"), border: OutlineInputBorder())),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
          ],
        );
      }),
    );
    if (ok != true) return;
    try {
      await _db.from('app_feedback').update({'status': status, 'admin_reply': reply.text.trim().isEmpty ? null : reply.text.trim()}).eq('id', f['id']);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filter == 'all' ? _rows : _rows.where((r) => r['kind'] == _filter).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.inbox ? "Feedback inbox" : "My feedback", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(14), children: [
                  Wrap(spacing: 8, children: [
                    for (final f in ['all', 'feedback', 'bug', 'feature'])
                      ChoiceChip(
                        label: Text(f == 'all' ? "All (${_rows.length})" : "${kFeedbackKinds[f]!.$1} (${_rows.where((r) => r['kind'] == f).length})"),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  if (rows.isEmpty)
                    const Padding(padding: EdgeInsets.all(30), child: Center(child: Text("Nothing here yet.")))
                  else
                    for (final f in rows) _tile(f),
                ]),
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> f) {
    final k = kFeedbackKinds[f['kind']] ?? kFeedbackKinds['feedback']!;
    final st = kFeedbackStatus[f['status']] ?? kFeedbackStatus['new']!;
    final when = DateTime.tryParse((f['created_at'] ?? '').toString())?.toLocal();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.inbox ? () => _answer(f) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(k.$2, size: 20, color: AppPalette.fg(_kPurple)),
              const SizedBox(width: 8),
              Expanded(child: Text((f['subject'] ?? k.$1).toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppPalette.bg(st.$2.withValues(alpha: 0.12)), borderRadius: BorderRadius.circular(20)),
                child: Text(st.$1, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(st.$2))),
              ),
            ]),
            const SizedBox(height: 6),
            Text((f['message'] ?? '').toString()),
            if ((f['rating'] ?? 0) is int && (f['rating'] ?? 0) > 0) Text("★" * (f['rating'] as int), style: const TextStyle(color: Color(0xFFF59E0B))),
            if ((f['admin_reply'] ?? '').toString().isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppPalette.bg(Colors.green.shade50), borderRadius: BorderRadius.circular(8)),
                child: Text("Reply: ${f['admin_reply']}", style: TextStyle(color: AppPalette.fg(Colors.green.shade900))),
              ),
            const SizedBox(height: 6),
            Text(
              [
                if (widget.inbox) "${f['user_name'] ?? 'Someone'}${(f['user_role'] ?? '').toString().isEmpty ? '' : ' (${f['user_role']})'}",
                if ((f['screen'] ?? '').toString().isNotEmpty) "Screen: ${f['screen']}",
                if (when != null) DateFormat('d MMM yyyy, HH:mm').format(when),
              ].join(' · '),
              style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700)),
            ),
          ]),
        ),
      ),
    );
  }
}
