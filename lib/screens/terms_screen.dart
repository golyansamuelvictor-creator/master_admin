import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';

const Color _kPurple = Color(0xFF4A148C);
const _pendingKey = 'terms_pending_version';

/// Terms and Conditions (Data Policy): read and accepted before an account is
/// created. The text lives in Supabase (app_terms, 22_round21.sql).
class Terms {
  Terms._();
  static int? _acceptedThisSession;

  /// Shows the terms unless they were accepted in this session. True = agreed.
  static Future<bool> ensureAccepted(BuildContext context) async {
    if (_acceptedThisSession != null) return true;
    final v = await Navigator.push<int>(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const TermsScreen()));
    if (v == null) return false;
    _acceptedThisSession = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_pendingKey, v);
    } catch (_) {}
    return true;
  }

  /// After sign-in: records the acceptance on the new account's profile.
  static Future<void> recordPending() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getInt(_pendingKey);
      if (v == null) return;
      await Supabase.instance.client.rpc('accept_terms', params: {'p_version': v});
      await p.remove(_pendingKey);
    } catch (_) {}
  }
}

class TermsScreen extends StatefulWidget {
  /// [readOnly]: only to read them again (no Agree / Decline).
  final bool readOnly;
  const TermsScreen({super.key, this.readOnly = false});
  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  final _scroll = ScrollController();
  Map<String, dynamic>? _terms;
  bool _loading = true, _read = false, _ticked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_checkEnd);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _checkEnd() {
    if (!_read && _scroll.hasClients && _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40) {
      setState(() => _read = true);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Supabase.instance.client.from('app_terms').select().eq('is_active', true).order('version', ascending: false).limit(1).maybeSingle();
      if (!mounted) return;
      setState(() {
        _terms = r;
        _loading = false;
        if (r == null) _error = "The terms could not be found. Please try again later.";
      });
      // short text: nothing to scroll
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients && _scroll.position.maxScrollExtent <= 0) setState(() => _read = true);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load the terms. Check your connection and try again.";
      });
    }
  }

  /// "## " headings, "- " points, "# " title; other lines are paragraphs.
  List<Widget> _render(String body) {
    final out = <Widget>[];
    for (final raw in body.split('\n')) {
      final l = raw.trimRight();
      if (l.trim().isEmpty) {
        out.add(const SizedBox(height: 6));
      } else if (l.startsWith('# ')) {
        continue; // the title is in the header
      } else if (l.startsWith('## ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(l.substring(3), style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
        ));
      } else if (l.startsWith('- ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 7, right: 9), child: Container(width: 5, height: 5, decoration: BoxDecoration(color: AppPalette.solid(_kPurple), shape: BoxShape.circle))),
            Expanded(child: Text(l.substring(2), style: GoogleFonts.merriweather(fontSize: 13, height: 1.55))),
          ]),
        ));
      } else {
        out.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l, style: GoogleFonts.merriweather(fontSize: 13, height: 1.55))));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = _terms;
    final date = DateTime.tryParse((t?['effective_date'] ?? '').toString());
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
        appBar: AppBar(
          centerTitle: true,
          toolbarHeight: 50,
          automaticallyImplyLeading: widget.readOnly,
          title: Text("Terms & Data Policy", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(_kPurple))),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text("Try again")),
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Back")),
                      ]),
                    ),
                  )
                : Column(children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 820),
                          child: Scrollbar(
                            controller: _scroll,
                            thumbVisibility: true,
                            child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(18, 16, 18, 30), children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [AppPalette.solid(_kPurple), AppPalette.solid(const Color(0xFF7B4FC0))]),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.privacy_tip_rounded, color: Colors.white, size: 30),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text((t?['title'] ?? 'Terms and Conditions').toString(), style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                                      const SizedBox(height: 3),
                                      Text("Version ${t?['version']}${date == null ? '' : ' · effective ${DateFormat('d MMMM yyyy').format(date)}'}",
                                          style: GoogleFonts.merriweather(fontSize: 11.5, color: Colors.white70)),
                                    ]),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 10),
                              ..._render((t?['body'] ?? '').toString()),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    if (!widget.readOnly)
                      Container(
                        decoration: BoxDecoration(
                          color: AppPalette.bg(Colors.white),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, -3))],
                        ),
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                        child: SafeArea(
                          top: false,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 820),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                if (!_read)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text("Scroll to the end to read everything first.", style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.orange.shade800))),
                                  ),
                                CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  value: _ticked,
                                  onChanged: _read ? (v) => setState(() => _ticked = v == true) : null,
                                  title: Text("I have read and understood the Terms and Conditions and the Data Policy.", style: GoogleFonts.merriweather(fontSize: 12.5)),
                                ),
                                Row(children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text("Decline"),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(minimumSize: const Size(0, 46), backgroundColor: AppPalette.solid(_kPurple)),
                                      onPressed: _read && _ticked ? () => Navigator.pop(context, (t?['version'] as num?)?.toInt() ?? 1) : null,
                                      child: const Text("I agree"),
                                    ),
                                  ),
                                ]),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ]),
      ),
    );
  }
}
