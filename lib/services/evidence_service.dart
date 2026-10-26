import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/image_fingerprint.dart';

/// Result of checking one photo before upload.
class EvidenceCheck {
  final bool blocked;
  final String sha;
  final ImageFingerprint? fingerprint;
  final String? reason; // shown to the user when blocked
  final bool flaggedForReview; // allowed, but reviewers are told it looks like an older photo

  const EvidenceCheck({
    required this.blocked,
    required this.sha,
    required this.fingerprint,
    this.reason,
    this.flaggedForReview = false,
  });
}

/// Evidence photos: duplicate check (fingerprint + AI review) and private links.
///
///  * distance 0–[blockDistance]: the same picture -> blocked
///  * up to [reviewDistance]: looks similar (crop, screenshot, edit) -> the
///    AI compares the two photos; blocked when it says they are the same
///  * above that: a different photo
class EvidenceService {
  EvidenceService._();

  static const int blockDistance = 8;
  static const int reviewDistance = 18;
  static const String bucket = 'report-evidence';
  static const String aiFunction = 'evidence-ai-check';

  static SupabaseClient get _db => Supabase.instance.client;

  static String _when(dynamic d) {
    final dt = DateTime.tryParse((d ?? '').toString());
    return dt == null ? 'an earlier date' : DateFormat('d MMM yyyy').format(dt);
  }

  static String _where(Map m) {
    final duty = (m['duty_name'] ?? 'another report').toString();
    final unit = (m['unit_name'] ?? '').toString();
    return "$duty on ${_when(m['report_date'])}${unit.isEmpty ? '' : ' ($unit)'}";
  }

  /// Checks [bytes] against every earlier evidence photo and against
  /// [batchHashes] (other photos chosen in the same upload).
  static Future<EvidenceCheck> check({
    required Uint8List bytes,
    required String dutyName,
    required String unitName,
    required DateTime reportDate,
    List<String> batchHashes = const [],
  }) async {
    final sha = sha256.convert(bytes).toString();
    final fp = await ImageFingerprint.compute(bytes);

    // Same upload: two near-identical photos
    if (fp != null) {
      for (final h in batchHashes) {
        if (ImageFingerprint.distance(fp.hash, h) <= blockDistance) {
          return EvidenceCheck(
            blocked: true,
            sha: sha,
            fingerprint: fp,
            reason: "It is the same picture as another photo you selected.",
          );
        }
      }
    }

    List<Map<String, dynamic>> matches = [];
    try {
      matches = await _similar(fp?.hash, sha);
      if (matches.isEmpty && fp != null) matches = await _similar(fp.mirrorHash, null); // flipped copy
    } catch (_) {
      // The check needs 06_round6.sql; without it, fall back to the exact-file check
      try {
        final exact = await _db.from('report_evidence').select('id, duty_name, unit_name, report_date').eq('file_hash', sha).limit(1);
        matches = List<Map<String, dynamic>>.from(exact).map((m) => {...m, 'evidence_id': m['id'], 'distance': 0, 'exact': true}).toList();
      } catch (_) {}
    }
    if (matches.isEmpty) return EvidenceCheck(blocked: false, sha: sha, fingerprint: fp);

    final best = matches.first;
    final int dist = (best['distance'] as num?)?.toInt() ?? 64;
    final bool exact = best['exact'] == true;

    if (exact || dist <= blockDistance) {
      await _flag(dutyName, unitName, reportDate, best, dist, exact, action: 'blocked');
      return EvidenceCheck(
        blocked: true,
        sha: sha,
        fingerprint: fp,
        reason: "This photo was already uploaded for ${_where(best)}.",
      );
    }

    // Looks similar: ask the AI to compare the two photos
    final ai = await _aiCompare(fp?.thumbnailPng, matches);
    if (ai != null && ai['duplicate'] == true && ((ai['confidence'] as num?)?.toDouble() ?? 0) >= 0.75) {
      final matchId = ai['matched_id']?.toString();
      final m = matches.firstWhere((x) => x['evidence_id']?.toString() == matchId, orElse: () => best);
      await _flag(dutyName, unitName, reportDate, m, (m['distance'] as num?)?.toInt() ?? dist, false,
          action: 'blocked', ai: ai);
      return EvidenceCheck(
        blocked: true,
        sha: sha,
        fingerprint: fp,
        reason: "It looks like a copy (cropped, edited or screenshotted) of a photo already uploaded for ${_where(m)}."
            "${(ai['reason'] ?? '').toString().isEmpty ? '' : ' ${ai['reason']}'}",
      );
    }
    if (ai == null) {
      // AI not set up or unreachable: let it through, but tell the reviewers
      await _flag(dutyName, unitName, reportDate, best, dist, false,
          action: 'allowed_flagged', ai: {'verdict': 'unavailable'});
      return EvidenceCheck(blocked: false, sha: sha, fingerprint: fp, flaggedForReview: true);
    }
    return EvidenceCheck(blocked: false, sha: sha, fingerprint: fp);
  }

  static Future<List<Map<String, dynamic>>> _similar(String? phash, String? sha) async {
    final res = await _db.rpc('find_similar_evidence', params: {
      'p_phash': phash,
      'p_sha': sha,
      'p_max_distance': reviewDistance,
      'p_limit': 3,
    });
    return List<Map<String, dynamic>>.from((res as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  static Future<Map<String, dynamic>?> _aiCompare(Uint8List? thumbPng, List<Map<String, dynamic>> candidates) async {
    if (thumbPng == null) return null;
    try {
      final res = await _db.functions.invoke(aiFunction, body: {
        'image_base64': base64Encode(thumbPng),
        'media_type': 'image/png',
        'candidate_ids': candidates.map((c) => c['evidence_id'].toString()).toList(),
      });
      final data = res.data;
      if (data is Map && data.containsKey('duplicate')) return Map<String, dynamic>.from(data);
      if (data is String) {
        final m = jsonDecode(data);
        if (m is Map && m.containsKey('duplicate')) return Map<String, dynamic>.from(m);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _flag(String duty, String unit, DateTime date, Map match, int dist, bool exact,
      {required String action, Map? ai}) async {
    try {
      await _db.from('evidence_flags').insert({
        'duty_name': duty,
        'unit_name': unit,
        'report_date': DateFormat('yyyy-MM-dd').format(date),
        'matched_evidence_id': match['evidence_id'],
        'matched_report_date': match['report_date'],
        'matched_unit_name': match['unit_name'],
        'distance': dist,
        'exact': exact,
        'ai_verdict': ai == null ? null : (ai['verdict'] ?? (ai['duplicate'] == true ? 'duplicate' : 'different')),
        'ai_confidence': ai?['confidence'],
        'ai_reason': ai?['reason'],
        'action': action,
      });
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Private links (the bucket is private; links last one hour)
  // ------------------------------------------------------------------

  /// Signed links for evidence rows: {row id: (thumb, full)}.
  static Future<Map<String, ({String? thumb, String? full})>> signedUrls(List<dynamic> rows) async {
    final paths = <String>{};
    for (final r in rows) {
      if (r is! Map) continue;
      final sp = (r['storage_path'] ?? '').toString();
      final tp = (r['thumb_path'] ?? '').toString();
      if (sp.isNotEmpty) paths.add(sp);
      if (tp.isNotEmpty) paths.add(tp);
    }
    final signed = <String, String>{};
    if (paths.isNotEmpty) {
      try {
        // ignore: deprecated_member_use
        final res = await _db.storage.from(bucket).createSignedUrls(paths.toList(), 3600);
        for (final s in res) {
          signed[s.path] = s.signedUrl;
        }
      } catch (_) {}
    }
    final out = <String, ({String? thumb, String? full})>{};
    for (final r in rows) {
      if (r is! Map) continue;
      final id = (r['id'] ?? '').toString();
      final sp = (r['storage_path'] ?? '').toString();
      final tp = (r['thumb_path'] ?? '').toString();
      final legacy = (r['image_url'] ?? '').toString();
      final full = signed[sp] ?? (legacy.startsWith('http') ? legacy : null);
      out[id] = (thumb: signed[tp] ?? full, full: full);
    }
    return out;
  }
}
