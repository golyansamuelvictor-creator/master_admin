import 'package:supabase_flutter/supabase_flutter.dart';

/// Which church-wide group a church worker leads, if any:
/// 장년회 (Men), 부녀회 (Women), 청년회 (Young Adults), 새신자 (New Saints),
/// 신학부 (Theology) or MOU.
///
/// Group leaders are registered under Internal Affairs (their profile
/// department is saved as 내무부), so screens that looked at the department
/// text treated them as Internal Affairs: they got the Church / Department
/// toggle and the Internal Affairs member list instead of their own group.
/// The group is read from the role (Grouping / role key) and from the
/// sub-department chosen at registration (profiles.sub_dept_id).
class GroupScope {
  GroupScope._();

  static String? _cachedFor;
  static List<String> _cachedNames = const [];

  /// Names (Korean / English / code) of the signed-in user's official
  /// department and sub-department.
  static Future<List<String>> myDeptNames() async {
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    if (uid == null) return const [];
    if (_cachedFor == uid) return _cachedNames;
    try {
      final p = await db.from('profiles').select('sub_dept_id').eq('id', uid).maybeSingle();
      final ids = [p?['sub_dept_id']].where((e) => e != null).map((e) => e.toString()).toList();
      final names = <String>[];
      if (ids.isNotEmpty) {
        final rows = await db.from('official_departments').select('name, name_ko, name_en, code').inFilter('id', ids);
        for (final r in rows) {
          for (final k in ['name', 'name_ko', 'name_en', 'code']) {
            final v = (r[k] ?? '').toString().trim();
            if (v.isNotEmpty) names.add(v);
          }
        }
      }
      _cachedFor = uid;
      _cachedNames = names;
      return names;
    } catch (_) {
      return const [];
    }
  }

  /// The group for this role, or null when the user isn't a group leader.
  static String? detect({required String grouping, required String role, List<String> subDeptNames = const []}) {
    final r = role.toLowerCase();
    if (grouping == '24-Dept MG' || r.startsWith('mg_group')) return '장년회';
    if (grouping == '24-Dept WG' || r.startsWith('wg_group')) return '부녀회';
    if (grouping == '24-Dept YAG' || r.startsWith('yag_group')) return '청년회';
    if (grouping == '24-Dept New Saints' || r.startsWith('new_saints')) return '새신자';
    if (grouping.startsWith('24-Dept 18') || r.startsWith('theology_dept')) return '신학부';
    if (grouping == '24-Dept MOU' || r.startsWith('mou_dept')) return 'MOU';
    // Location roles never lead a church-wide group.
    if (r.contains('cell') || r.contains('team') || r.startsWith('dept_') || r.startsWith('sub_loc') || r.startsWith('loc_')) return null;
    for (final raw in subDeptNames) {
      final n = raw.toLowerCase();
      if (n.contains('부녀') || n.contains('women')) return '부녀회';
      if (n.contains('장년') || RegExp(r"\bmen\b|men's").hasMatch(n)) return '장년회';
      if (n.contains('청년') || n.contains('young adult') || n == 'yag') return '청년회';
      if (n.contains('새신자') || n.contains('new saint')) return '새신자';
      if (n.contains('신학') || n.contains('theolog')) return '신학부';
      if (n.startsWith('mou')) return 'MOU';
    }
    return null;
  }

  /// Members of [group] across the whole church (the same rules the entry
  /// form and member directory used for each group).
  static PostgrestFilterBuilder<T> filter<T>(PostgrestFilterBuilder<T> q, String group) {
    PostgrestFilterBuilder<T> noChurchWorkers(PostgrestFilterBuilder<T> x) =>
        x.neq('location', 'Church Workers').neq('location', 'Church Main').neq('location', 'Church');
    switch (group) {
      case '새신자':
        return noChurchWorkers(q.or('department.eq.새신자,department.ilike.%new saints%').neq('location', 'Mou'));
      case '신학부':
        return noChurchWorkers(q.or('department.eq.신학부,department.ilike.%theology%').neq('location', 'Mou').neq('location', 'New Saints'));
      case 'MOU':
        return noChurchWorkers(q.ilike('department', 'mou'));
      default:
        return noChurchWorkers(q.eq('department', group).neq('location', 'Mou').neq('location', 'New Saints'));
    }
  }

  static String label(String group) => switch (group) {
        '장년회' => "Men's Group (장년회)",
        '부녀회' => "Women's Group (부녀회)",
        '청년회' => 'Young Adults Group (청년회)',
        '새신자' => 'New Saints (새신자)',
        '신학부' => 'Theology (신학부)',
        _ => group,
      };
}
