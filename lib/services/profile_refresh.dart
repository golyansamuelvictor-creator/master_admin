import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AuthWrapper listens to this and reloads the signed-in user's profile.
/// Call [requestProfileRefresh] after anything that changes approval state
/// (approval confirmed, SCJ verification finished, etc.).
final ValueNotifier<int> profileRefreshNotifier = ValueNotifier<int>(0);

void requestProfileRefresh() => profileRefreshNotifier.value++;

/// The signed-in user's profile photo, shared by every screen that shows it
/// (Home, the side menu, Settings, My Home). Set it after an upload and all
/// of them change at once.
final ValueNotifier<String> myAvatarUrl = ValueNotifier<String>('');

/// Reads the photo from `profiles.avatar_url` once and shares it.
Future<void> loadMyAvatar() async {
  final db = Supabase.instance.client;
  final me = db.auth.currentUser?.id;
  if (me == null) return;
  try {
    final r = await db.from('profiles').select('avatar_url').eq('id', me).maybeSingle();
    final u = (r?['avatar_url'] ?? '').toString().trim();
    myAvatarUrl.value = u; // empty after switching to an account without a photo
  } catch (_) {}
}

/// Updates the signed-in user's profile. A column the database doesn't have
/// yet (e.g. `bio` before 14_round13.sql) is left out and the rest is saved.
Future<void> updateMyProfile(Map<String, dynamic> data, {String? email}) async {
  final db = Supabase.instance.client;
  final me = db.auth.currentUser?.id;
  final row = Map<String, dynamic>.from(data);
  for (int i = 0; i < 6 && row.isNotEmpty; i++) {
    try {
      if (me != null) {
        await db.from('profiles').update(row).eq('id', me);
      } else if (email != null) {
        await db.from('profiles').update(row).ilike('email', email.trim());
      }
      final u = (row['avatar_url'] ?? '').toString();
      if (u.isNotEmpty) myAvatarUrl.value = u;
      return;
    } on PostgrestException catch (e) {
      final m = RegExp(r"the '([^']+)' column").firstMatch(e.message);
      if (e.code == 'PGRST204' && m != null && row.containsKey(m.group(1))) {
        row.remove(m.group(1));
        continue;
      }
      rethrow;
    }
  }
}
