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
  /// Shown inside the app (the sign-in check): Agree / Decline call this
  /// instead of closing the page (version, or null = declined).
  final void Function(int? version)? onDecision;
  /// A line above the terms (e.g. "The terms were updated …").
  final String? notice;
  const TermsScreen({super.key, this.readOnly = false, this.onDecision, this.notice});
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
      canPop: widget.onDecision == null,
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
                        TextButton(onPressed: () => widget.onDecision != null ? widget.onDecision!(null) : Navigator.pop(context), child: Text(widget.onDecision != null ? "Sign out" : "Back")),
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
                              if (widget.notice != null)
                                Container(
                                  margin: const EdgeInsets.only(top: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppPalette.bg(const Color(0xFFFFF8E1)),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppPalette.line(const Color(0xFFFFCC80))),
                                  ),
                                  child: Row(children: [
                                    Icon(Icons.info_outline_rounded, color: AppPalette.fg(Colors.orange.shade900)),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(widget.notice!, style: GoogleFonts.merriweather(fontSize: 12.5, color: AppPalette.fg(Colors.orange.shade900)))),
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
                                      onPressed: () => widget.onDecision != null ? widget.onDecision!(null) : Navigator.pop(context),
                                      child: Text(widget.onDecision != null ? "Decline & sign out" : "Decline"),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(minimumSize: const Size(0, 46), backgroundColor: AppPalette.solid(_kPurple)),
                                      onPressed: _read && _ticked
                                          ? () {
                                              final v = (t?['version'] as num?)?.toInt() ?? 1;
                                              widget.onDecision != null ? widget.onDecision!(v) : Navigator.pop(context, v);
                                            }
                                          : null,
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

/// After sign-in: everyone must have accepted the current terms. Accounts
/// made before the terms existed, and everyone after the terms are updated
/// (a new version in app_terms), see them once; "I agree" records it,
/// declining signs out.
class TermsGate extends StatefulWidget {
  final Widget child;
  final int? acceptedVersion; // profiles.terms_version
  const TermsGate({super.key, required this.child, this.acceptedVersion});
  @override
  State<TermsGate> createState() => _TermsGateState();
}

class _TermsGateState extends State<TermsGate> {
  static int? _current; // the active version (once per app run)
  static final Set<String> _okUsers = {};
  bool? _needed;
  bool _saving = false;

  String get _uid => Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (_okUsers.contains(_uid)) {
      setState(() => _needed = false);
      return;
    }
    try {
      await Terms.recordPending(); // accepted while creating the account
      if (_current == null) {
        final r = await Supabase.instance.client.from('app_terms').select('version').eq('is_active', true).order('version', ascending: false).limit(1).maybeSingle();
        _current = (r?['version'] as num?)?.toInt() ?? 0;
      }
      var mine = widget.acceptedVersion ?? 0;
      if (mine < _current!) {
        final p = await Supabase.instance.client.from('profiles').select('terms_version').eq('id', _uid).maybeSingle();
        mine = (p?['terms_version'] as num?)?.toInt() ?? 0;
      }
      final need = _current! > 0 && mine < _current!;
      if (!need) _okUsers.add(_uid);
      if (mounted) setState(() => _needed = need);
    } catch (_) {
      // offline or before the terms table: don't lock people out
      if (mounted) setState(() => _needed = false);
    }
  }

  Future<void> _decide(int? v) async {
    if (v == null) {
      await Supabase.instance.client.auth.signOut();
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('accept_terms', params: {'p_version': v});
      _okUsers.add(_uid);
      if (mounted) setState(() => _needed = false);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save your answer. Check your connection and try again.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_needed == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_needed == false) return widget.child;
    return Stack(children: [
      TermsScreen(
        onDecision: _decide,
        notice: (widget.acceptedVersion ?? 0) > 0
            ? "The Terms and Data Policy were updated. Please read them and agree to continue."
            : "Please read the Terms and Data Policy and agree to continue using Master Admin.",
      ),
      if (_saving) const ColoredBox(color: Color(0x33000000), child: Center(child: CircularProgressIndicator())),
    ]);
  }
}
