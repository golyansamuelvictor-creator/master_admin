import 'package:material_ui/material_ui.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/friendly_error.dart';
import '../core/i18n.dart';

const Color _kPurple = Color(0xFF4A148C);
const Color _kBlue = Color(0xFF1E3A8A);
const Color _kRed = Color(0xFFB91C1C);

/// Opens the member's faith & performance as a sheet (e.g. from a transfer
/// request, so the receiving unit can review the person first).
Future<void> showMemberPerformance(BuildContext context, {required String memberId, required String name}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text.rich(TextSpan(text: name), style: GoogleFonts.merriweather(fontSize: 17, fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
            const SizedBox(height: 8),
            MemberPerformanceView(memberId: memberId),
          ]),
        ),
      ),
    ),
  );
}

/// Member profile › Faith & performance: every duty for a period — how many
/// times the member took part or missed, their answers, the reasons given
/// when they missed, and an AI summary.
class MemberPerformanceView extends StatefulWidget {
  final String memberId;
  const MemberPerformanceView({super.key, required this.memberId});
  @override
  State<MemberPerformanceView> createState() => _MemberPerformanceViewState();
}

class _MemberPerformanceViewState extends State<MemberPerformanceView> {
  static const _periods = {7: 'Last week', 30: 'Last month', 90: 'Last 3 months', 182: 'Last 6 months', 365: 'Last year'};
  int _days = 30;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _duties = [];
  Map<String, dynamic>? _ai;
  bool _aiBusy = false;
  String? _aiError;

  DateTime get _from => DateTime.now().subtract(Duration(days: _days));
  String _d(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _ai = null;
      _aiError = null;
    });
    try {
      final r = await Supabase.instance.client.rpc('member_performance', params: {'p_member': widget.memberId, 'p_from': _d(_from), 'p_to': _d(DateTime.now())});
      final list = ((r as Map)['duties'] as List?) ?? const [];
      if (mounted) setState(() => _duties = [for (final x in list) Map<String, dynamic>.from(x as Map)]);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't load the performance${friendlyTail(e)}");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _summarise() async {
    setState(() {
      _aiBusy = true;
      _aiError = null;
    });
    try {
      final res = await Supabase.instance.client.functions.invoke('member-performance-ai', body: {'member_id': widget.memberId, 'from': _d(_from), 'to': _d(DateTime.now())});
      final data = res.data;
      if (data is Map && data['error'] != null) throw data['error'].toString();
      if (mounted) setState(() => _ai = Map<String, dynamic>.from(data as Map));
    } catch (e) {
      if (mounted) setState(() => _aiError = "The AI summary isn't available right now${friendlyTail(e)}");
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final e in _periods.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(e.value),
                selected: _days == e.key,
                selectedColor: AppPalette.bg(_kPurple.withValues(alpha: 0.15)),
                onSelected: (_) {
                  setState(() => _days = e.key);
                  _load();
                },
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      if (_loading)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (_error != null)
        Padding(padding: const EdgeInsets.all(12), child: Text.rich(TextSpan(text: _error), style: TextStyle(color: AppPalette.fg(_kRed))))
      else if (_duties.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text("No reports for this member in this period.", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey.shade600))),
        )
      else ...[
        _overall(),
        const SizedBox(height: 10),
        for (final d in _duties) _dutyCard(d),
        const SizedBox(height: 6),
        _aiBox(),
      ],
    ]);
  }

  Widget _overall() {
    final done = _duties.fold<int>(0, (a, d) => a + ((d['done'] as num?)?.toInt() ?? 0));
    final missed = _duties.fold<int>(0, (a, d) => a + ((d['missed'] as num?)?.toInt() ?? 0));
    final total = done + missed;
    final rate = total == 0 ? 0 : (done * 100 / total).round();
    final tone = rate >= 80 ? _kPurple : (rate >= 50 ? _kBlue : _kRed);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppPalette.solid(tone), AppPalette.solid(Color.lerp(tone, Colors.black, 0.25)!)]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppPalette.cardShadow,
      ),
      child: Row(children: [
        Text.rich(TextSpan(text: "$rate%"), style: GoogleFonts.merriweather(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Overall participation", style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.bold)),
            Text.rich(TextSpan(text: "$done ${tr('times took part')} · $missed ${tr('missed')} · ${_periods[_days] != null ? tr(_periods[_days]!) : ''}"),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _dutyCard(Map<String, dynamic> d) {
    final done = (d['done'] as num?)?.toInt() ?? 0;
    final missed = (d['missed'] as num?)?.toInt() ?? 0;
    final total = done + missed;
    final answers = Map<String, dynamic>.from((d['answers'] ?? {}) as Map);
    final reasons = [for (final x in (d['reasons'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text.rich(TextSpan(text: tr(d['duty'].toString())), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13.5)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  minHeight: 10,
                  color: _kPurple,
                  backgroundColor: AppPalette.bg(_kRed.withValues(alpha: 0.25)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text.rich(TextSpan(text: "$done ✓  ·  $missed ✗"), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (answers.isNotEmpty)
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in answers.entries)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text.rich(TextSpan(text: "${e.key}: ${e.value}"), style: const TextStyle(fontSize: 11.5)),
                ),
            ]),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text("Reasons given when missed", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(_kRed))),
            const SizedBox(height: 4),
            for (final r in reasons)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 82, child: Text.rich(TextSpan(text: (r['date'] ?? '').toString()), style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700)))),
                  Expanded(
                    child: Text.rich(
                      TextSpan(text: (r['reason'] ?? '').toString().trim().isEmpty ? "${r['answer'] ?? ''} · ${tr('no reason written')}" : r['reason'].toString()),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ]),
              ),
          ],
        ],
      ),
    );
  }

  Widget _aiBox() {
    if (_ai == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OutlinedButton.icon(
          onPressed: _aiBusy ? null : _summarise,
          icon: _aiBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded),
          label: Text(_aiBusy ? "Summarising…" : "AI summary"),
        ),
        if (_aiError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text.rich(TextSpan(text: _aiError), style: TextStyle(fontSize: 12, color: AppPalette.fg(_kRed)))),
      ]);
    }
    List<Widget> list(String title, String key, IconData icon, Color c) {
      final items = [for (final x in (_ai![key] as List? ?? const [])) x.toString()];
      if (items.isEmpty) return const [];
      return [
        const SizedBox(height: 8),
        Row(children: [Icon(icon, size: 16, color: AppPalette.fg(c)), const SizedBox(width: 6), Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppPalette.fg(c)))]),
        for (final i in items) Padding(padding: const EdgeInsets.only(left: 22, top: 3), child: Text.rich(TextSpan(text: "• $i"), style: const TextStyle(fontSize: 12.5, height: 1.4))),
      ];
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.bg(const Color(0xFFF5F3FF)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(_kPurple.withValues(alpha: 0.2))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, color: AppPalette.fg(_kPurple), size: 18),
          const SizedBox(width: 6),
          Text("AI summary", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
        ]),
        const SizedBox(height: 6),
        Text.rich(TextSpan(text: (_ai!['summary'] ?? '').toString()), style: const TextStyle(fontSize: 13, height: 1.5)),
        ...list("Strengths", 'strengths', Icons.thumb_up_alt_outlined, _kPurple),
        ...list("Concerns", 'concerns', Icons.warning_amber_rounded, _kRed),
        ...list("Suggested care", 'suggestions', Icons.volunteer_activism_outlined, _kBlue),
        const SizedBox(height: 6),
        Text("Written by AI from the reports above; check before acting on it.", style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.grey.shade600))),
      ]),
    );
  }
}
