import 'package:supabase_flutter/supabase_flutter.dart';

/// Who may add calendar events, intentions and quotes.
///
/// Not fixed in code: each permission is an "admin action" on the user's role
/// (or secondary role) in app_roles.allowed_admin_actions — see
/// 05_notices.sql. The database enforces the same rules.
class NoticePermissions {
  static const String churchEvents = 'Manage Church Events';
  static const String locationEvents = 'Manage Location Events';
  static const String churchIntentions = 'Manage Church Intentions';
  static const String locationIntentions = 'Manage Location Intentions';
  static const String departmentIntentions = 'Manage Department Intentions';
  static const String quotes = 'Manage Quotes';
  static const String churchSurveys = 'Manage Church Surveys';
  static const String locationSurveys = 'Manage Location Surveys';

  final Set<String> actions;
  final bool isAdmin;
  final String location;
  final String subLocation;
  final String department;

  const NoticePermissions({
    required this.actions,
    required this.isAdmin,
    required this.location,
    required this.subLocation,
    required this.department,
  });

  static const NoticePermissions none =
      NoticePermissions(actions: {}, isAdmin: false, location: '', subLocation: '', department: '');

  bool can(String action) => isAdmin || actions.contains(action);

  bool get canAddEvents => can(churchEvents) || can(locationEvents);
  bool get canAddIntentions => can(churchIntentions) || can(locationIntentions) || can(departmentIntentions);
  bool get canAddQuotes => can(quotes);
  bool get canAddSurveys => can(churchSurveys) || can(locationSurveys);

  static Future<NoticePermissions> load() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return none;
    try {
      final p = await client
          .from('profiles')
          .select('role, secondary_role, location, sub_location, department, is_approved, approval_status')
          .eq('id', user.id)
          .maybeSingle();
      if (p == null) return none;
      final approved = p['is_approved'] == true || p['approval_status'] == 'approved';
      final role = (p['role'] ?? '').toString();
      final sec = (p['secondary_role'] ?? '').toString();
      final isAdmin = approved && (role.toLowerCase() == 'admin' || role == 'Master');

      final Set<String> actions = {};
      final keys = [role, sec].where((k) => k.isNotEmpty).toList();
      if (approved && keys.isNotEmpty) {
        final roles = await client.from('app_roles').select('allowed_admin_actions').inFilter('role_key', keys);
        for (final r in roles) {
          for (final a in (r['allowed_admin_actions'] as List? ?? const [])) {
            actions.add(a.toString());
          }
        }
      }
      return NoticePermissions(
        actions: actions,
        isAdmin: isAdmin,
        location: (p['location'] ?? '').toString(),
        subLocation: (p['sub_location'] ?? '').toString(),
        department: (p['department'] ?? '').toString(),
      );
    } catch (_) {
      return none;
    }
  }

  /// Scope columns for a new item at [level] ('church' | 'location' | 'department'),
  /// taken from the author's own unit.
  Map<String, dynamic> scopeFor(String level) => {
        'scope_level': level,
        'scope_location': level == 'church' ? null : location,
        'scope_sub_location': level == 'department' ? subLocation : null,
        'scope_department': level == 'department' ? department : null,
      };

  /// Human description of who will see an item at [level].
  String audienceFor(String level) {
    if (level == 'location') return "Shown to members of $location";
    if (level == 'department') return "Shown to members of $department ($subLocation, $location)";
    return "Shown to everyone in the church";
  }
}
