import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';

const Color _kBlue = Color(0xFF1565C0);

/// Settings › Language: choose the system language, download more languages,
/// and (Manage Languages) add languages and correct translations.
class LanguagePanel extends StatefulWidget {
  final bool canManage;
  const LanguagePanel({super.key, this.canManage = false});
  @override
  State<LanguagePanel> createState() => _LanguagePanelState();
}

class _LanguagePanelState extends State<LanguagePanel> {
  List<Map<String, dynamic>> _langs = [];
  Set<String> _onDevice = {I18n.english};
  bool _loading = true;
  String? _error;
  String? _busy; // code being downloaded
  int _done = 0, _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await I18n.languages(includeHidden: widget.canManage);
      final d = await I18n.downloaded();
      if (mounted) {
        setState(() {
          _langs = l;
          _onDevice = d;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Languages aren't set up yet (run 10_round9.sql). English stays on.";
        });
      }
    }
  }

  void _snack(String m, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null, behavior: SnackBarBehavior.floating));

  int _pct(Map l) {
    final t = (l['total'] ?? 0) as num, d = (l['translated'] ?? 0) as num;
    return t == 0 ? 0 : (d * 100 / t).floor();
  }

  /// Fills in missing words (server), saves the language on this device and switches to it.
  Future<void> _download(Map<String, dynamic> l, {bool switchTo = true}) async {
    final code = l['code'].toString();
    setState(() {
      _busy = code;
      _done = (l['translated'] ?? 0) as int;
      _total = (l['total'] ?? 0) as int;
    });
    String? problem;
    try {
      if (_pct(l) < 100) {
        await I18n.completePack(code, onProgress: (d, t) {
          if (mounted) {
            setState(() {
              _done = d;
              _total = t;
            });
          }
        });
      }
    } catch (e) {
      problem = e.toString().replaceFirst('Exception: ', '');
    }
    try {
      await I18n.download(code, rtl: l['is_rtl'] == true, native: l['native_name']?.toString());
      if (switchTo) await I18n.use(code, rtl: l['is_rtl'] == true, native: l['native_name']?.toString());
      if (problem != null) {
        _snack("Some words are still in English: the translator couldn't finish ($problem). Download again later to complete it.", error: true);
      } else {
        _snack(switchTo ? "${l['native_name']} is on" : "${l['native_name']} is saved on this device");
      }
    } catch (e) {
      _snack("Couldn't download ${l['name_en']}: $e", error: true);
    }
    if (mounted) setState(() => _busy = null);
    _load();
  }

  Future<void> _choose(Map<String, dynamic> l) async {
    final code = l['code'].toString();
    if (code == I18n.code || _busy != null) return;
    if (code == I18n.english || _onDevice.contains(code)) {
      await I18n.use(code, rtl: l['is_rtl'] == true, native: l['native_name']?.toString());
      if (mounted) setState(() {});
      return;
    }
    final pct = _pct(l);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Download ${l['name_en']}?"),
        content: Text(pct >= 100
            ? "The language is saved on this device, so it opens instantly next time."
            : pct == 0
                ? "This language hasn't been downloaded by anyone yet. It is prepared now (a few minutes), then saved on this device. You can keep the screen open while it works."
                : "$pct% is ready. The rest is prepared now (a few minutes), then the language is saved on this device."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download_rounded),
            label: const Text("Download"),
          ),
        ],
      ),
    );
    if (ok == true) await _download(l);
  }

  Future<void> _remove(Map<String, dynamic> l) async {
    await I18n.removeDownload(l['code'].toString());
    _snack("${l['name_en']} removed from this device");
    _load();
  }

  Future<void> _setEnabled(Map<String, dynamic> l, bool on) async {
    try {
      await Supabase.instance.client.from('app_languages').update({'enabled': on}).eq('code', l['code']);
      _load();
    } catch (e) {
      _snack("Couldn't change it: $e", error: true);
    }
  }

  Future<void> _addLanguage() async {
    final added = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddLanguageSheet(existing: _langs.map((l) => l['code'].toString()).toSet()),
    );
    if (added == null) return;
    await _load();
    final l = _langs.firstWhere((x) => x['code'] == added['code'], orElse: () => added);
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("${added['name_en']} added"),
        content: const Text("Prepare and download it now? Everyone can then choose it in Settings › Language."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Later")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Download now")),
        ],
      ),
    );
    if (go == true) await _download(l, switchTo: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          RadioGroup<String>(
            groupValue: I18n.english,
            onChanged: (_) {},
            child: const RadioListTile<String>(value: I18n.english, title: Text("English", style: TextStyle(fontWeight: FontWeight.bold))),
          ),
          Text(_error!, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text("Choose the language of all screens. A language is downloaded once and then works offline on this device.",
            style: TextStyle(fontSize: 12.5, color: AppPalette.fg(Colors.grey.shade700))),
      ),
      if (_busy != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Preparing ${_langs.firstWhere((l) => l['code'] == _busy, orElse: () => {'name_en': _busy})['name_en']}… $_done of $_total",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total, minHeight: 6, borderRadius: BorderRadius.circular(4)),
          ]),
        ),
      RadioGroup<String>(
        groupValue: I18n.code,
        onChanged: (v) {
          final l = _langs.firstWhere((x) => x['code'] == v, orElse: () => <String, dynamic>{});
          if (l.isNotEmpty) _choose(l);
        },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final l in _langs) _tile(l),
        ]),
      ),
      const Divider(height: 20),
      if (widget.canManage) ...[
        ListTile(
          leading: Icon(Icons.add_circle_outline_rounded, color: AppPalette.fg(_kBlue)),
          title: const Text("Add a language", style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text("From the list of world languages, or any other language"),
          onTap: _busy == null ? _addLanguage : null,
        ),
        ListTile(
          leading: Icon(Icons.edit_note_rounded, color: AppPalette.fg(_kBlue)),
          title: const Text("Correct translations", style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text("Fix any word the translator got wrong"),
          onTap: () => _pickForEditing(),
        ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Text("Names typed by people (members, units such as 장년회, 부녀회 …) are shown as they are saved.",
            style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
      ),
    ]);
  }

  Widget _tile(Map<String, dynamic> l) {
    final code = l['code'].toString();
    final pct = _pct(l);
    final onDevice = _onDevice.contains(code);
    final hidden = l['enabled'] == false;
    final status = code == I18n.english
        ? "Built in"
        : [
            if (pct >= 100) "Ready" else if (pct == 0) "Not prepared yet" else "$pct% ready",
            if (onDevice) "on this device",
            if (hidden) "hidden from users",
          ].join(" · ");
    return RadioListTile<String>(
      value: code,
      title: Row(children: [
        Flexible(child: Text(l['native_name']?.toString() ?? code, style: const TextStyle(fontWeight: FontWeight.bold))),
        if (onDevice && code != I18n.english)
          Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.download_done_rounded, size: 16, color: AppPalette.fg(Colors.green.shade700))),
      ]),
      subtitle: Text("${l['name_en']} · $status", style: const TextStyle(fontSize: 12)),
      secondary: code == I18n.english
          ? null
          : PopupMenuButton<String>(
              tooltip: tr("More"),
              onSelected: (v) {
                switch (v) {
                  case 'update':
                    _download(l, switchTo: I18n.code == code);
                  case 'remove':
                    _remove(l);
                  case 'edit':
                    _openEditor(l);
                  case 'hide':
                    _setEnabled(l, false);
                  case 'show':
                    _setEnabled(l, true);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'update', child: Text(onDevice ? "Update" : "Download")),
                if (onDevice) const PopupMenuItem(value: 'remove', child: Text("Remove from this device")),
                if (widget.canManage) ...[
                  const PopupMenuItem(value: 'edit', child: Text("Correct translations")),
                  PopupMenuItem(value: hidden ? 'show' : 'hide', child: Text(hidden ? "Show to users" : "Hide from users")),
                ],
              ],
            ),
    );
  }

  void _openEditor(Map<String, dynamic> l) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TranslationEditorScreen(code: l['code'].toString(), name: l['name_en'].toString()))).then((_) => _load());
  }

  Future<void> _pickForEditing() async {
    final choices = _langs.where((l) => l['code'] != I18n.english).toList();
    final l = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Which language?"),
        children: [
          for (final l in choices)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, l), child: Text("${l['native_name']} (${l['name_en']})")),
        ],
      ),
    );
    if (l != null) _openEditor(l);
  }
}

/// Pick from `app_language_catalog`, or type any other language.
class _AddLanguageSheet extends StatefulWidget {
  final Set<String> existing;
  const _AddLanguageSheet({required this.existing});
  @override
  State<_AddLanguageSheet> createState() => _AddLanguageSheetState();
}

class _AddLanguageSheetState extends State<_AddLanguageSheet> {
  List<Map<String, dynamic>> _all = [];
  String _q = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    I18n.catalog().then((c) {
      if (mounted) {
        setState(() {
          _all = c.where((l) => !widget.existing.contains(l['code'])).toList();
          _loading = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _add(Map<String, dynamic> l) async {
    setState(() => _saving = true);
    try {
      final row = {
        'code': l['code'],
        'name_en': l['name_en'],
        'native_name': l['native_name'],
        'is_rtl': l['is_rtl'] == true,
        'sort_order': 50,
        'added_by': Supabase.instance.client.auth.currentUser?.id,
      };
      await Supabase.instance.client.from('app_languages').upsert(row, onConflict: 'code');
      if (mounted) Navigator.pop(context, row);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't add it: $e")));
      }
    }
  }

  Future<void> _other() async {
    final code = TextEditingController(), en = TextEditingController(), nat = TextEditingController();
    bool rtl = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text("Other language"),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: en, decoration: InputDecoration(labelText: tr("Name in English"), hintText: tr("e.g. Rukonzo"))),
            TextField(controller: nat, decoration: InputDecoration(labelText: tr("Name in the language itself"), hintText: tr("e.g. Olukonzo"))),
            TextField(controller: code, decoration: InputDecoration(labelText: tr("Short code"), hintText: tr("e.g. koo (ISO 639 code if you know it)"))),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: rtl,
              onChanged: (v) => set(() => rtl = v),
              title: const Text("Written right to left"),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Add")),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final c = code.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '');
    final name = en.text.trim();
    if (c.isEmpty || name.isEmpty) return;
    await _add({'code': c, 'name_en': name, 'native_name': nat.text.trim().isEmpty ? name : nat.text.trim(), 'is_rtl': rtl});
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = _all
        .where((l) => q.isEmpty || '${l['name_en']} ${l['native_name']} ${l['region'] ?? ''} ${l['code']}'.toLowerCase().contains(q))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text("Add a language", style: GoogleFonts.merriweather(fontSize: 17, fontWeight: FontWeight.w900)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr("Search languages"), isDense: true, border: const OutlineInputBorder()),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          if (_saving) const LinearProgressIndicator(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(children: [
                    for (final l in list)
                      ListTile(
                        title: Text("${l['native_name']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${l['name_en']}${(l['region'] ?? '').toString().isEmpty ? '' : ' · ${l['region']}'}"),
                        trailing: const Icon(Icons.add_rounded),
                        onTap: _saving ? null : () => _add(l),
                      ),
                    ListTile(
                      leading: const Icon(Icons.edit_rounded),
                      title: const Text("Another language…", style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text("Type its name if it isn't in the list"),
                      onTap: _saving ? null : _other,
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// Manage Languages: correct what the translator wrote.
class TranslationEditorScreen extends StatefulWidget {
  final String code;
  final String name;
  const TranslationEditorScreen({super.key, required this.code, required this.name});
  @override
  State<TranslationEditorScreen> createState() => _TranslationEditorScreenState();
}

class _TranslationEditorScreenState extends State<TranslationEditorScreen> {
  List<Map<String, dynamic>> _rows = [];
  final Map<String, TextEditingController> _ctl = {};
  final Set<String> _saved = {};
  String _search = '';
  bool _missing = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await I18n.strings(widget.code, search: _search, missingOnly: _missing, limit: 300);
      if (mounted) {
        setState(() {
          _rows = r;
          _loading = false;
          for (final row in r) {
            final k = row['key'].toString();
            _ctl.putIfAbsent(k, () => TextEditingController()).text = (row['value'] ?? '').toString();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(String key) async {
    try {
      await I18n.saveString(widget.code, key, _ctl[key]!.text);
      if (mounted) setState(() => _saved.add(key));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.name} translations")),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr("Search English or translation"), isDense: true, border: const OutlineInputBorder()),
                onSubmitted: (v) {
                  _search = v.trim();
                  _load();
                },
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text("Missing only"),
              selected: _missing,
              onSelected: (v) {
                _missing = v;
                _load();
              },
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text("Press Enter to save a line. Empty = shown in English. Lines you correct are never replaced by the translator.",
              style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const Center(child: Text("Nothing found"))
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        final k = r['key'].toString();
                        final human = r['source'] == 'human' || _saved.contains(k);
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            // the English text itself is shown untranslated
                            SelectableText(k, style: TextStyle(fontSize: 12.5, color: AppPalette.fg(Colors.grey.shade800))),
                            Row(children: [
                              Expanded(
                                child: TextField(
                                  controller: _ctl[k],
                                  minLines: 1,
                                  maxLines: 4,
                                  decoration: const InputDecoration(isDense: true),
                                  onSubmitted: (_) => _save(k),
                                ),
                              ),
                              IconButton(
                                tooltip: tr("Save"),
                                icon: Icon(human ? Icons.verified_rounded : Icons.check_rounded,
                                    color: AppPalette.fg(human ? Colors.green.shade700 : Colors.grey.shade600)),
                                onPressed: () => _save(k),
                              ),
                            ]),
                          ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

/// Small language button for the sign-in screen (languages already prepared).
class LanguageQuickButton extends StatelessWidget {
  const LanguageQuickButton({super.key});

  Future<void> _pick(BuildContext context) async {
    List<Map<String, dynamic>> langs = [];
    try {
      langs = (await I18n.languages()).where((l) => l['code'] == I18n.english || ((l['translated'] ?? 0) as num) > 0).toList();
    } catch (_) {}
    if (!context.mounted || langs.length < 2) return;
    final l = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Language"),
        children: [
          for (final l in langs)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, l),
              child: Row(children: [
                Expanded(child: Text("${l['native_name']}", style: TextStyle(fontWeight: l['code'] == I18n.code ? FontWeight.w900 : FontWeight.normal))),
                if (l['code'] == I18n.code) const Icon(Icons.check_rounded, size: 18),
              ]),
            ),
        ],
      ),
    );
    if (l == null) return;
    try {
      await I18n.use(l['code'].toString(), rtl: l['is_rtl'] == true, native: l['native_name']?.toString());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextButton.icon(
        onPressed: () => _pick(context),
        icon: Icon(Icons.translate_rounded, size: 18, color: AppPalette.fg(const Color(0xFF4A148C))),
        // the language's own name, never translated
        label: Text.rich(TextSpan(text: I18n.nativeName), style: TextStyle(color: AppPalette.fg(const Color(0xFF4A148C)), fontWeight: FontWeight.bold)),
      ),
    );
  }
}
