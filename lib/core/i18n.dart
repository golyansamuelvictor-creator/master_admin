// System language (Settings › Language).
//
// Every screen keeps its English text in the code; the translations live in
// Supabase (`app_languages`, `app_translations`, `app_ui_strings`, see
// 10_round9.sql) and are downloaded once to the device, so switching is
// instant and works offline afterwards.
//
// How screens get translated without changing each screen: the files import
// material.dart `hide Text` and use the `Text` below, which looks its English
// text up in the chosen language when it is drawn. Labels given as plain
// strings (hints, tooltips, tabs) call `tr(...)`. Text with values inside it
// ("Version 10.3", "3 of 12 pending") is matched against templates such as
// "Version {0}". Names and other data typed by people are never translated:
// only the app's own wording is in the dictionary.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' as w;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The app's wording in the chosen language ([s] itself in English).
String tr(String s) => I18n.tr(s);

class I18n {
  I18n._();

  static const String english = 'en';

  /// Code of the language in use ('en', 'ko', 'lg' ...).
  static final ValueNotifier<String> language = ValueNotifier(english);
  static String get code => language.value;
  static bool isRtl = false;
  static String nativeName = 'English';

  static Map<String, String> _map = const {};
  // templates ("Version {0}") grouped by the text before / after the first / last value
  static final Map<String, List<_Tpl>> _byPrefix = {};
  static final Map<String, List<_Tpl>> _bySuffix = {};
  static List<int> _prefixLens = const [];
  static List<int> _suffixLens = const [];
  static final Map<String, String> _cache = {};

  static SupabaseClient get _db => Supabase.instance.client;

  static String tr(String s) {
    if (_map.isEmpty || s.isEmpty) return s;
    final exact = _map[s];
    if (exact != null) return exact;
    if (_prefixLens.isEmpty && _suffixLens.isEmpty) return s;
    final hit = _cache[s];
    if (hit != null) return hit;
    final out = _matchTemplate(s) ?? s;
    if (_cache.length > 6000) _cache.clear();
    _cache[s] = out;
    return out;
  }

  static String? _matchTemplate(String s) {
    for (final n in _prefixLens) {
      if (s.length < n) continue;
      final list = _byPrefix[s.substring(0, n)];
      if (list == null) continue;
      for (final t in list) {
        final r = t.apply(s);
        if (r != null) return r;
      }
    }
    for (final n in _suffixLens) {
      if (s.length < n) continue;
      final list = _bySuffix[s.substring(s.length - n)];
      if (list == null) continue;
      for (final t in list) {
        final r = t.apply(s);
        if (r != null) return r;
      }
    }
    return null;
  }

  static void _install(String code, Map<String, String> map, {bool rtl = false, String? native}) {
    _byPrefix.clear();
    _bySuffix.clear();
    _cache.clear();
    final clean = <String, String>{};
    map.forEach((k, v) {
      if (v.trim().isEmpty) return;
      if (k.contains('{0}')) {
        final t = _Tpl.tryParse(k, v);
        if (t == null) return;
        if (t.prefix.length >= 2) {
          _byPrefix.putIfAbsent(t.prefix, () => []).add(t);
        } else if (t.suffix.length >= 2) {
          _bySuffix.putIfAbsent(t.suffix, () => []).add(t);
        }
      } else {
        clean[k] = v;
      }
    });
    // longer (more specific) beginnings first
    _prefixLens = (_byPrefix.keys.map((k) => k.length).toSet().toList()..sort((a, b) => b.compareTo(a)));
    _suffixLens = (_bySuffix.keys.map((k) => k.length).toSet().toList()..sort((a, b) => b.compareTo(a)));
    _map = code == english ? const {} : clean;
    if (code == english) {
      _byPrefix.clear();
      _bySuffix.clear();
      _prefixLens = const [];
      _suffixLens = const [];
    }
    isRtl = rtl;
    nativeName = native ?? nativeName;
    language.value = code;
    rebuildAll();
  }

  /// Redraws every screen in the new language (keeps where you are).
  static void rebuildAll() {
    final root = w.WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void visit(w.Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    root.visitChildren(visit);
  }

  // ---------------------------------------------------------------------------
  // Device copy

  static String _packKey(String code) => 'lang_pack_$code';

  /// Reads the chosen language from the device (no network). Call before runApp.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('app_language') ?? english;
      if (code == english) return;
      final raw = prefs.getString(_packKey(code));
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _install(code, Map<String, String>.from(j['strings'] ?? {}), rtl: j['rtl'] == true, native: j['native']?.toString());
    } catch (e) {
      debugPrint('Language load skipped: $e');
    }
  }

  /// Languages whose pack is saved on this device.
  static Future<Set<String>> downloaded() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      english,
      for (final k in prefs.getKeys())
        if (k.startsWith('lang_pack_')) k.substring('lang_pack_'.length),
    };
  }

  static Future<void> removeDownload(String code) async {
    if (code == english) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_packKey(code));
    if (I18n.code == code) await use(english);
  }

  // ---------------------------------------------------------------------------
  // Supabase

  /// The languages people can choose (`app_languages`), with how much is translated.
  static Future<List<Map<String, dynamic>>> languages({bool includeHidden = false}) async {
    final res = await _db.rpc('language_overview', params: {'p_all': includeHidden});
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// More languages that can be added (`app_language_catalog`).
  static Future<List<Map<String, dynamic>>> catalog() async {
    final rows = await _db.from('app_language_catalog').select().order('name_en');
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Fills in the words still missing for [code] (translated by the
  /// `translate-pack` server function), a part at a time. [onProgress] gets
  /// (translated, total).
  static Future<void> completePack(String code, {void Function(int done, int total)? onProgress}) async {
    if (code == english) return;
    for (int round = 0; round < 60; round++) {
      final res = await _db.functions.invoke('translate-pack', body: {'lang': code});
      final d = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      if (d['error'] != null) throw Exception(d['error']);
      final total = (d['total'] ?? 0) as num;
      final remaining = (d['remaining'] ?? 0) as num;
      onProgress?.call((total - remaining).toInt(), total.toInt());
      if (remaining <= 0 || (d['translated'] ?? 0) == 0) break;
    }
  }

  /// Downloads the pack of [code] from Supabase to the device.
  static Future<Map<String, String>> _fetchPack(String code) async {
    final out = <String, String>{};
    for (int from = 0;; from += 1000) {
      final page = await _db.from('app_translations').select('key, value').eq('lang_code', code).order('key').range(from, from + 999);
      for (final r in page) {
        out[r['key'].toString()] = (r['value'] ?? '').toString();
      }
      if (page.length < 1000) break;
    }
    return out;
  }

  /// Downloads (or refreshes) [code] and switches the app to it.
  static Future<void> download(String code, {bool rtl = false, String? native}) async {
    final map = code == english ? <String, String>{} : await _fetchPack(code);
    final prefs = await SharedPreferences.getInstance();
    if (code != english) {
      await prefs.setString(_packKey(code), jsonEncode({'strings': map, 'rtl': rtl, 'native': native, 'at': DateTime.now().toIso8601String()}));
    }
  }

  /// Switches to [code] (downloading it first if it isn't on the device) and
  /// remembers it on this device and on the account.
  static Future<void> use(String code, {bool rtl = false, String? native}) async {
    final prefs = await SharedPreferences.getInstance();
    if (code != english && prefs.getString(_packKey(code)) == null) {
      await download(code, rtl: rtl, native: native);
    }
    Map<String, String> map = {};
    if (code != english) {
      final j = jsonDecode(prefs.getString(_packKey(code)) ?? '{}') as Map<String, dynamic>;
      map = Map<String, String>.from(j['strings'] ?? {});
      rtl = j['rtl'] == true || rtl;
      native ??= j['native']?.toString();
    }
    await prefs.setString('app_language', code);
    _install(code, map, rtl: rtl, native: code == english ? 'English' : native);
    final uid = _db.auth.currentUser?.id;
    if (uid != null) {
      try {
        await _db.from('user_settings').upsert({'user_id': uid, 'language': code}, onConflict: 'user_id');
      } catch (_) {}
    }
  }

  /// After signing in: follow the language saved on the account (chosen on
  /// another device), and refresh the device copy in the background.
  static Future<void> syncFromAccount() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await _db.from('user_settings').select('language').eq('user_id', uid).maybeSingle();
      final saved = (row?['language'] ?? '').toString();
      final langs = await languages();
      String target = code;
      if (saved.isNotEmpty && saved != code && langs.any((l) => l['code'] == saved)) target = saved;
      if (target == english) {
        if (code != english) await use(english);
        return;
      }
      final l = langs.firstWhere((l) => l['code'] == target, orElse: () => <String, dynamic>{});
      if (l.isEmpty) return;
      await download(target, rtl: l['is_rtl'] == true, native: l['native_name']?.toString());
      await use(target, rtl: l['is_rtl'] == true, native: l['native_name']?.toString());
    } catch (e) {
      debugPrint('Language sync skipped (run 10_round9.sql): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Editing (Manage Languages)

  static Future<List<Map<String, dynamic>>> strings(String code, {String search = '', bool missingOnly = false, int limit = 200}) async {
    final res = await _db.rpc('translation_rows', params: {'p_lang': code, 'p_search': search, 'p_missing': missingOnly, 'p_limit': limit});
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<void> saveString(String code, String key, String value) async {
    if (value.trim().isEmpty) {
      await _db.from('app_translations').delete().eq('lang_code', code).eq('key', key);
    } else {
      await _db.from('app_translations').upsert(
        {'lang_code': code, 'key': key, 'value': value, 'source': 'human', 'updated_by': _db.auth.currentUser?.id, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        onConflict: 'lang_code,key',
      );
    }
    if (I18n.code == code) {
      final m = Map<String, String>.from(_map);
      if (value.trim().isEmpty) {
        m.remove(key);
      } else {
        m[key] = value;
      }
      _install(code, m, rtl: isRtl, native: nativeName);
    }
  }
}

/// "Version {0}" ⇄ "Version 10.3"
class _Tpl {
  final String prefix;
  final String suffix;
  final RegExp re;
  final List<int> order; // placeholder number of each captured group
  final String target;
  _Tpl(this.prefix, this.suffix, this.re, this.order, this.target);

  static final RegExp _ph = RegExp(r'\{(\d+)\}');

  static _Tpl? tryParse(String key, String value) {
    final parts = key.split(_ph);
    final nums = _ph.allMatches(key).map((m) => int.parse(m.group(1)!)).toList();
    if (nums.isEmpty) return null;
    // every value must still be in the translation
    for (final n in nums) {
      if (!value.contains('{$n}')) return null;
    }
    final b = StringBuffer('^');
    for (int i = 0; i < parts.length; i++) {
      b.write(RegExp.escape(parts[i]));
      if (i < nums.length) b.write('(.*?)');
    }
    b.write(r'$');
    return _Tpl(parts.first, parts.last, RegExp(b.toString(), dotAll: true), nums, value);
  }

  String? apply(String s) {
    final m = re.firstMatch(s);
    if (m == null) return null;
    var out = target;
    for (int i = 0; i < order.length; i++) {
      final v = m.group(i + 1) ?? '';
      // a value that is itself app wording ("Pending") is translated too
      out = out.replaceAll('{${order[i]}}', I18n._map[v] ?? v);
    }
    return out;
  }
}

/// Drop-in for Flutter's [w.Text] that shows the app's wording in the chosen
/// language. Same constructor and fields, so `const Text("Save")` still works.
class Text extends w.StatelessWidget {
  final String? data;
  final w.InlineSpan? textSpan;
  final w.TextStyle? style;
  final w.StrutStyle? strutStyle;
  final w.TextAlign? textAlign;
  final w.TextDirection? textDirection;
  final w.Locale? locale;
  final bool? softWrap;
  final w.TextOverflow? overflow;
  final w.TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final w.TextWidthBasis? textWidthBasis;
  final w.TextHeightBehavior? textHeightBehavior;
  final w.Color? selectionColor;

  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    w.InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  @override
  w.Widget build(w.BuildContext context) {
    if (data == null) {
      return w.Text.rich(
        textSpan!,
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }
    return w.Text(
      I18n.tr(data!),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
