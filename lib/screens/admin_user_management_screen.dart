// ignore_for_file: use_build_context_synchronously
import 'package:material_ui/material_ui.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';
import 'package:master_admin/core/app_sizes.dart';
import 'package:master_admin/widgets/compact_card.dart';
import 'package:master_admin/widgets/secondary_unit_picker.dart';

/// Member Bio › User management.
///
/// One screen for what used to be "Account approvals" and "User
/// Administration" (Approve new users / Change roles / Remove user):
/// - Pending, Approved, Rejected and All accounts, searchable, and filtered by
///   role, location, sub-location and department;
/// - Approve / Reject (anyone with "Approve Accounts", inside their own area:
///   church-wide roles everyone, a Location Sec their location, a
///   sub-location role their sub-location; the person is notified);
/// - Change role and Remove user (admins).
/// The list and the filters come from the database already limited to your
/// area (user_admin_list / user_admin_facets in 11_round10.sql).
class AdminUserManagementScreen extends StatefulWidget {
  final String initialStatus;
  const AdminUserManagementScreen({super.key, this.initialStatus = 'pending'});

  @override
  State<AdminUserManagementScreen> createState() => _AdminUserManagementScreenState();
}

class _AdminUserManagementScreenState extends State<AdminUserManagementScreen> {
  final _db = Supabase.instance.client;
  static const int _page = 100;

  late String _status = widget.initialStatus;
  String _search = '';
  String? _role, _location, _subLocation, _department;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _scope;
  bool _isAdmin = false;
  /// 'admin' | 'location' (Location Secretary) | null: who may change roles
  String? _roleRights;
  int _total = 0;
  List<Map<String, dynamic>> _rows = [];
  Map<String, List<Map<String, dynamic>>> _facets = {};
  List<Map<String, dynamic>> _appRoles = [];
  // Department / group choices for the role dialog (official_departments)
  Map<String, String?> _deptOptions = {"All / General": null};
  final Set<String> _busy = {};
  int _req = 0;

  final Color pPurple = const Color(0xFF4A148C);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // registrations left unfinished for more than 24 hours are deleted
    _db.rpc('purge_stale_registrations').catchError((_) => 0);
    try {
      final r = await Future.wait<dynamic>([
        _db.rpc('account_approval_scope'),
        _db.rpc('is_admin'),
        _db.from('app_roles').select(),
        _db.from('official_departments').select('id, name, name_en, name_ko, parent_id').order('name'),
      ]);
      _scope = r[0]?.toString();
      _isAdmin = r[1] == true;
      try {
        _roleRights = (await _db.rpc('role_change_rights'))?.toString();
      } catch (_) {
        _roleRights = _isAdmin ? 'admin' : null; // before 18_round17.sql
      }
      _appRoles = List<Map<String, dynamic>>.from(r[2] as List);
      final depts = List<Map<String, dynamic>>.from(r[3] as List);
      String label(Map d) {
        final ko = (d['name_ko'] ?? d['name'] ?? '').toString();
        final en = (d['name_en'] ?? '').toString();
        return en.isEmpty || en == ko ? ko : (ko.isEmpty ? en : "$ko ($en)");
      }
      final opts = <String, String?>{"All / General": null};
      for (final d in depts.where((d) => d['parent_id'] == null)) {
        opts[label(d)] = d['id'].toString();
        for (final c in depts.where((c) => c['parent_id']?.toString() == d['id'].toString())) {
          opts["   ${label(c)}"] = c['id'].toString();
        }
      }
      _deptOptions = opts;
    } catch (e) {
      debugPrint("User management init: $e");
    }
    await _load();
  }

  Future<void> _load({bool more = false}) async {
    final req = ++_req;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final params = {
        'p_status': _status,
        'p_search': _search.trim(),
        'p_role': _role,
        'p_location': _location,
        'p_sub_location': _subLocation,
        'p_department': _department,
        'p_limit': _page,
        'p_offset': more ? _rows.length : 0,
      };
      final res = await Future.wait<dynamic>([
        _db.rpc('user_admin_list', params: params),
        if (!more) _db.rpc('user_admin_facets', params: {'p_status': _status}),
      ]);
      if (!mounted || req != _req) return;
      final rows = List<Map<String, dynamic>>.from((res[0] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      setState(() {
        _rows = more ? [..._rows, ...rows] : rows;
        _total = rows.isEmpty ? (more ? _total : 0) : ((rows.first['total'] ?? rows.length) as num).toInt();
        if (!more) {
          final f = <String, List<Map<String, dynamic>>>{};
          for (final x in (res[1] as List)) {
            final m = Map<String, dynamic>.from(x as Map);
            f.putIfAbsent(m['kind'].toString(), () => []).add(m);
          }
          _facets = f;
        }
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint("User management: $e");
      if (mounted && req == _req) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = "Couldn't load accounts. Check your internet connection and refresh.";
        });
      }
    }
  }

  void _snack(String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, backgroundColor: error ? Colors.red.shade700 : null));

  String _v(Map r, String k) {
    final s = (r[k] ?? '').toString().trim();
    return s.toLowerCase() == 'n/a' ? '' : s;
  }

  String _name(Map r) => _v(r, 'full_name').isEmpty ? _v(r, 'email') : _v(r, 'full_name');

  // ==========================================
  // 1. APPROVE / REJECT (decide_account: area rule + notification)
  // ==========================================
  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    String? reason;
    if (!approve) {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Reject ${_name(r)}?"),
          content: SizedBox(
            width: 380,
            child: TextField(
              controller: c,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(labelText: tr("Reason (shown to the person)"), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
              onPressed: () {
                if (c.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text("Reject"),
            ),
          ],
        ),
      );
      if (ok != true) return;
      reason = c.text.trim();
    }
    final id = r['id'].toString();
    setState(() => _busy.add(id));
    try {
      await _db.rpc('decide_account', params: {'p_user': id, 'p_approve': approve, 'p_reason': reason});
      _snack(approve ? "${_name(r)} approved" : "${_name(r)} rejected");
      setState(() {
        if (_status == 'all') {
          r['approval_status'] = approve ? 'approved' : 'rejected';
        } else {
          _rows.removeWhere((x) => x['id'].toString() == id);
          _total = _total > 0 ? _total - 1 : 0;
        }
      });
    } catch (e) {
      _snack(e is PostgrestException ? e.message : "Couldn't save the decision", error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  // ==========================================
  // 2. CHANGE ROLE (MATCHING YOUR APP_ROLES TABLE)
  // ==========================================
  // ==========================================
  // 2. CHANGE ROLE (change_user_role, 18_round17.sql)
  // ==========================================
  static const _levels = <String, String>{
    'all': 'All levels',
    'cell': 'Cell group',
    'team': 'Team',
    'department': 'Department',
    'sub_location': 'Sub-location',
    'location': 'Location',
    'church': 'Church / 24 departments',
  };

  /// Church / 24-department roles (and admin) — never offered to Location
  /// Secretaries, and not mixed into a location worker's list.
  bool _isChurchRole(Map r) {
    final key = (r['role_key'] ?? '').toString();
    final scope = (r['approval_scope'] ?? '').toString().toLowerCase();
    final grouping = (r['Grouping'] ?? '').toString();
    return key.toLowerCase() == 'admin' || key == 'Master' || key.startsWith('church_') || key.startsWith('korean') ||
        scope == 'church' || scope == 'church_department' || grouping.startsWith('24-Dept') || grouping.startsWith('Church') ||
        r['official_dept_id'] != null;
  }

  String _levelOf(Map r) {
    final scope = (r['approval_scope'] ?? '').toString().toLowerCase();
    final key = (r['role_key'] ?? '').toString().toLowerCase();
    final grouping = (r['Grouping'] ?? '').toString().toLowerCase();
    if (_isChurchRole(r)) return 'church';
    if (scope == 'cell' || grouping.startsWith('cell') || key.contains('cell')) return 'cell';
    if (scope == 'team' || grouping.startsWith('team') || key.contains('team')) return 'team';
    if (scope == 'department' || grouping.startsWith('dept') || key.startsWith('dept')) return 'department';
    if (scope == 'sub_location' || grouping.startsWith('sub') || key.startsWith('sub_loc')) return 'sub_location';
    if (scope == 'location' || grouping.startsWith('location') || key.startsWith('loc_')) return 'location';
    return 'cell';
  }

  bool _userIsChurchWorker(Map user) {
    final loc = _v(user, 'location').toLowerCase();
    return _v(user, 'unit_category').toLowerCase().contains('church') || loc == 'church' || loc == 'church workers' || loc == 'church main';
  }

  /// Depth of a role's own unit (for a secondary role in another department):
  /// 0 = none (location-wide roles), 1 department, 2 team, 3 cell group.
  int _unitDepth(String? key) {
    if (key == null) return 0;
    final r = _appRoles.firstWhere((x) => x['role_key'] == key, orElse: () => const {});
    final k = key.toLowerCase();
    final sc = (r['approval_scope'] ?? '').toString().toLowerCase();
    if (sc.startsWith('location') || sc == 'sub_location' || sc.startsWith('church') || k.startsWith('loc_') || k.startsWith('sub_loc')) return 0;
    if (k.contains('cell') || sc == 'cell_group') return 3;
    if (k.contains('team') || sc == 'team') return 2;
    if (k.contains('dept') || sc == 'department') return 1;
    return 0;
  }

  Future<void> _openChangeRoleDialog(Map<String, dynamic> user) async {
    // the secondary role's own unit (if any)
    String? secDept, secTeam, secCell;
    try {
      final p = await _db.from('profiles').select('secondary_department, secondary_team, secondary_cell_group').eq('id', user['id']).maybeSingle();
      secDept = (p?['secondary_department'] ?? '').toString().isEmpty ? null : p!['secondary_department'].toString();
      secTeam = (p?['secondary_team'] ?? '').toString().isEmpty ? null : p!['secondary_team'].toString();
      secCell = (p?['secondary_cell_group'] ?? '').toString().isEmpty ? null : p!['secondary_cell_group'].toString();
    } catch (_) {}
    if (!mounted) return;
    final onlyLocation = _roleRights != 'admin';
    // the user's own kind of roles first: location workers see location
    // roles, church workers church / 24-department roles
    // account category: Saint / Location Worker / Church Worker
    final uc = _v(user, 'unit_category');
    final String category0 = _userIsChurchWorker(user)
        ? 'Church Worker'
        : (uc == 'Saint' || _v(user, 'account_type') == 'Saint' ? 'Saint' : 'Location Worker');
    String category = onlyLocation && category0 == 'Church Worker' ? 'Location Worker' : category0;
    String? newLocation; // leaving "Church Worker": the person's location
    String kind = category == 'Church Worker' ? 'church' : 'location';
    String level = 'all';
    String? deptId; // church roles: one of the 24 departments
    String? roleKey = user['role']?.toString();
    String? secondKey = (user['secondary_role'] ?? '').toString().isEmpty ? null : user['secondary_role'].toString();
    String search = '';
    bool saving = false;

    String name(Map r) {
      final ko = (r['display_name_ko'] ?? '').toString();
      final n = (r['display_name'] ?? r['role_key']).toString();
      return ko.isEmpty || ko == n ? n : "$n ($ko)";
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        bool isSaintRole(Map r) => (r['category'] ?? '').toString() == 'Saint';
        bool inKind(Map r) => kind == 'church'
            ? _isChurchRole(r) && (r['role_key'] != 'admin' || !onlyLocation)
            : !_isChurchRole(r) && (category == 'Saint' ? isSaintRole(r) : !isSaintRole(r));
        final roles = _appRoles.where((r) {
          if (r['role_key'] == null) return false;
          if (onlyLocation && _isChurchRole(r)) return false;
          if (!inKind(r)) return false;
          if (level != 'all' && _levelOf(r) != level) return false;
          if (kind == 'church' && deptId != null && r['official_dept_id']?.toString() != deptId) return false;
          if (search.isNotEmpty && !"${name(r)} ${r['role_key']}".toLowerCase().contains(search.toLowerCase())) return false;
          return true;
        }).toList()
          ..sort((a, b) => name(a).compareTo(name(b)));
        // the secondary role follows the same kind (Location / Church) as the
        // main list; it may sit at another level (e.g. a Theology worker who
        // is also a cell leader)
        final seconds = _appRoles.where((r) => r['role_key'] != null && r['role_key'] != roleKey && (!onlyLocation || !_isChurchRole(r)) && (inKind(r) || r['role_key'] == secondKey)).toList()
          ..sort((a, b) => name(a).compareTo(name(b)));
        final current = _appRoles.firstWhere((r) => r['role_key'] == roleKey, orElse: () => <String, dynamic>{});
        Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)));
        InputDecoration deco([String? hint]) => InputDecoration(border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))), isDense: true, hintText: hint, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10));
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Category & role: ${_name(user)}", maxLines: 2, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(pPurple))),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text("Now: ${current.isEmpty ? (roleKey ?? '-') : name(current)}${_v(user, 'location').isEmpty ? '' : ' · ${_v(user, 'location')}'}",
                    style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.blueGrey.shade700))),
                if (onlyLocation)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text("As Location Secretary you can give only the roles of the location levels, to people of your location.",
                        style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.orange.shade900))),
                  ),
                label("Account category"),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: 'Saint', label: Text("Saint")),
                    const ButtonSegment(value: 'Location Worker', label: Text("Location Worker")),
                    if (!onlyLocation) const ButtonSegment(value: 'Church Worker', label: Text("Church Worker")),
                  ],
                  selected: {category},
                  onSelectionChanged: (v) => set(() {
                    category = v.first;
                    kind = category == 'Church Worker' ? 'church' : 'location';
                    level = 'all';
                    deptId = null;
                    // the old role belongs to the old category: choose again
                    if (category != category0) roleKey = null;
                    if (category == category0) roleKey = user['role']?.toString();
                  }),
                ),
                if (category != category0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      category == 'Church Worker'
                          ? "The account moves to Church (24 departments); choose the new role below."
                          : "The account becomes a $category; choose the new role below.",
                      style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.orange.shade900)),
                    ),
                  ),
                if (category0 == 'Church Worker' && category != 'Church Worker') ...[
                  label("Location"),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: newLocation,
                    decoration: deco("Choose the location"),
                    items: [
                      for (final o in _facets['location'] ?? const <Map<String, dynamic>>[])
                        if ((o['value'] ?? '').toString().isNotEmpty && (o['value'] ?? '').toString().toLowerCase() != 'church')
                          DropdownMenuItem(value: o['value'].toString(), child: Text((o['label'] ?? o['value']).toString(), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => set(() => newLocation = v),
                  ),
                ],
                if (kind == 'church') ...[
                  label("Department"),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: deptId ?? '',
                    decoration: deco(),
                    items: [
                      for (final e in _deptOptions.entries)
                        DropdownMenuItem(value: e.value ?? '', child: Text(e.key.trim(), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => set(() => deptId = (v ?? '').isEmpty ? null : v),
                  ),
                ] else ...[
                  label("Level"),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: level,
                    decoration: deco(),
                    items: [
                      for (final e in _levels.entries)
                        if (e.key != 'church') DropdownMenuItem(value: e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => set(() => level = v ?? 'all'),
                  ),
                ],
                label("Role (${roles.length})"),
                TextField(onChanged: (v) => set(() => search = v), decoration: deco("Find a role").copyWith(prefixIcon: const Icon(Icons.search, size: 18))),
                const SizedBox(height: 6),
                Container(
                  height: 220,
                  decoration: BoxDecoration(border: Border.all(color: AppPalette.line(Colors.grey.shade300)), borderRadius: BorderRadius.circular(8)),
                  child: roles.isEmpty
                      ? const Center(child: Text("No roles match."))
                      : ListView.builder(
                          itemCount: roles.length,
                          itemBuilder: (_, i) {
                            final r = roles[i];
                            final sel = r['role_key'] == roleKey;
                            return ListTile(
                              dense: true,
                              selected: sel,
                              selectedTileColor: pPurple.withValues(alpha: 0.08),
                              leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: AppPalette.fg(pPurple)),
                              title: Text(name(r), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                              subtitle: Text("${r['role_key']} · ${_levels[_levelOf(r)]}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5)),
                              onTap: () => set(() => roleKey = r['role_key'].toString()),
                            );
                          },
                        ),
                ),
                label("Secondary role (optional)"),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: seconds.any((r) => r['role_key'] == secondKey) ? secondKey : '',
                  decoration: deco(),
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text("None")),
                    for (final r in seconds)
                      DropdownMenuItem<String>(value: r['role_key'].toString(), child: Text(name(r), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => set(() {
                    secondKey = (v == null || v.isEmpty) ? null : v;
                    secDept = secTeam = secCell = null;
                  }),
                ),
                if (secondKey != null && _unitDepth(secondKey) > 0 && _v(user, 'location').isNotEmpty) ...[
                  label("Unit of the secondary role (empty = same as the main role)"),
                  SecondaryUnitPicker(
                    key: ValueKey('sec|$secondKey'),
                    location: _v(user, 'location'),
                    subLocation: _v(user, 'sub_location'),
                    depth: _unitDepth(secondKey),
                    department: secDept,
                    team: secTeam,
                    cell: secCell,
                    onChanged: (d, t, c) {
                      secDept = d;
                      secTeam = t;
                      secCell = c;
                    },
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(pPurple), foregroundColor: Colors.white),
              onPressed: roleKey == null || saving || (category0 == 'Church Worker' && category != 'Church Worker' && newLocation == null)
                  ? null
                  : () async {
                      set(() => saving = true);
                      try {
                        // administrators: applied at once; Location
                        // Secretaries: sent to the Location Leader to approve
                        final res = await _db.rpc('request_role_change', params: {
                          'p_user': user['id'],
                          'p_role': roleKey,
                          'p_secondary': secondKey,
                          'p_sec_department': secDept,
                          'p_sec_team': secTeam,
                          'p_sec_cell': secCell,
                          'p_category': category != category0 ? category : null,
                          'p_location': newLocation,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        _load();
                        _snack(res == 'requested'
                            ? "Sent for approval. The Location Leader approves it; then the role changes automatically."
                            : "Role changed. The person and their leaders were notified.");
                      } catch (e) {
                        set(() => saving = false);
                        _snack("Couldn't change the role: ${e is PostgrestException ? e.message : e}", error: true);
                      }
                    },
              child: Text(category != category0 ? "Save category & role" : "Save role"),
            ),
          ],
        );
      }),
    );
  }

  // ==========================================
  // 3. REMOVE USER ACTION
  // ==========================================
  Future<void> _removeUser(Map<String, dynamic> user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Remove User: ${_name(user)}", style: TextStyle(color: AppPalette.fg(Colors.red))),
        content: const Text("This deletes the user's profile and sign-in, so they can no longer open the system. "
            "If records they entered must keep their name, the account is blocked instead. This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(Colors.red)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Delete User", style: TextStyle(color: AppPalette.fg(Colors.white))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // A plain delete of the profiles row was refused by the database
        // (no permission) and left the sign-in behind; the server does it now.
        final res = await _db.rpc('admin_delete_user', params: {'p_user': user['id']});
        _load();
        _snack(res == 'blocked'
            ? "${_name(user)} is linked to saved records, so the account was blocked and hidden instead of deleted."
            : "${_name(user)} was deleted.");
      } catch (e) {
        _snack("Couldn't remove: ${e is PostgrestException ? e.message : e}", error: true);
      }
    }
  }

  /// Deletes every registration that was started but never finished.
  Future<void> _purgeIncomplete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove unfinished registrations"),
        content: const Text("Deletes accounts that were started more than 24 hours ago but never completed (no name, SCJ ID, role or unit) and were never approved. This also happens by itself every hour."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await _db.rpc('admin_purge_incomplete', params: {'p_days': 1});
      _load();
      _snack("$n unfinished registration(s) removed.");
    } catch (e) {
      _snack("Couldn't remove: ${e is PostgrestException ? e.message : e}", error: true);
    }
  }

  // ==========================================
  // DETAILS
  // ==========================================
  void _details(Map<String, dynamic> r) {
    final unit = [_v(r, 'location'), _v(r, 'sub_location'), _v(r, 'department'), _v(r, 'team'), _v(r, 'cell_group')].where((x) => x.isNotEmpty).join(' › ');
    final created = DateTime.tryParse((r['created_at'] ?? '').toString())?.toLocal();
    Widget line(IconData i, String label, String t) => t.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(i, size: 17, color: AppPalette.fg(Colors.grey.shade600)),
              const SizedBox(width: 8),
              SizedBox(width: 96, child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(child: SelectableText(t, style: const TextStyle(fontSize: 12.5))),
            ]),
          );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name(r), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(pPurple))),
            const SizedBox(height: 8),
            line(Icons.alternate_email, "User name", _v(r, 'username').isEmpty ? '' : "@${_v(r, 'username')}"),
            line(Icons.badge_outlined, "SCJ ID", _v(r, 'scj_id')),
            line(Icons.mail_outline, "Email", _v(r, 'email')),
            line(Icons.phone_outlined, "Phone", _v(r, 'phone')),
            line(Icons.work_outline, "Role", [_v(r, 'role_name').isEmpty ? _v(r, 'role') : _v(r, 'role_name'), _v(r, 'secondary_role')].where((x) => x.isNotEmpty).join(' + ')),
            line(Icons.account_tree_outlined, "Unit", unit),
            line(Icons.person_outline, "Account", [_v(r, 'account_type'), _v(r, 'unit_category')].where((x) => x.isNotEmpty).join(' · ')),
            line(Icons.flag_outlined, "Status", _v(r, 'approval_status')),
            line(Icons.info_outline, "Reason", _v(r, 'rejection_reason')),
            line(Icons.event_outlined, "Registered", created == null ? '' : DateFormat('d MMM yyyy, HH:mm').format(created)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: _actions(r, ctx: ctx, full: true)),
          ]),
        ),
      ),
    );
  }

  List<Widget> _actions(Map<String, dynamic> r, {BuildContext? ctx, bool full = false}) {
    final st = _v(r, 'approval_status');
    void close() {
      if (ctx != null) Navigator.pop(ctx);
    }
    return [
      // an unfinished registration has nothing to approve yet
      if (st != 'approved' && st != 'incomplete')
        full
            ? ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                onPressed: () {
                  close();
                  _decide(r, true);
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text("Approve"))
            : IconButton(tooltip: tr("Approve"), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30), icon: Icon(Icons.check_circle_rounded, size: 22, color: AppPalette.fg(Colors.green.shade700)), onPressed: () => _decide(r, true)),
      if (st != 'rejected')
        full
            ? OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                onPressed: () {
                  close();
                  _decide(r, false);
                },
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text("Reject"))
            : IconButton(tooltip: tr("Reject"), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30), icon: Icon(Icons.cancel_rounded, size: 22, color: AppPalette.fg(Colors.red.shade700)), onPressed: () => _decide(r, false)),
      // Location Secretaries change roles too (own location, location roles)
      if (_roleRights != null && full)
        OutlinedButton.icon(
            onPressed: () {
              close();
              _openChangeRoleDialog(r);
            },
            icon: const Icon(Icons.manage_accounts_rounded, size: 18),
            label: const Text("Category & role")),
      if (_isAdmin && full) ...[
        OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: () {
              close();
              _removeUser(r);
            },
            icon: const Icon(Icons.person_remove_rounded, size: 18),
            label: const Text("Remove user")),
      ],
    ];
  }

  // ==========================================
  // SCREEN
  // ==========================================
  Widget _filter(String kind, String label, String? value, void Function(String?) set) {
    final opts = _facets[kind] ?? const [];
    final current = opts.firstWhere((o) => o['value'] == value, orElse: () => <String, dynamic>{});
    final text = value == null ? label : (current['label'] ?? value).toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: PopupMenuButton<String>(
        tooltip: tr(label),
        enabled: opts.isNotEmpty,
        onSelected: (v) {
          set(v == '\u0000' ? null : v);
          _load();
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: '\u0000', child: Text("All", style: const TextStyle(fontWeight: FontWeight.bold))),
          for (final o in opts) PopupMenuItem(value: o['value'].toString(), child: Text("${o['label']}  (${o['n']})")),
        ],
        child: Chip(
          avatar: Icon(value == null ? Icons.filter_list_rounded : Icons.check_rounded, size: 16),
          label: Text(text, overflow: TextOverflow.ellipsis),
          backgroundColor: AppPalette.bg(value == null ? Colors.white : const Color(0xFFEDE3F8)),
          side: BorderSide(color: AppPalette.line(value == null ? Colors.black12 : pPurple)),
        ),
      ),
    );
  }

  /// Role: several at once (sent as role keys joined by "|").
  Widget _roleFilter() {
    final opts = _facets['role'] ?? const [];
    final chosen = (_role ?? '').split('|').where((x) => x.isNotEmpty).toSet();
    String labelOf(String v) => (opts.firstWhere((o) => o['value'] == v, orElse: () => {'label': v})['label'] ?? v).toString();
    final text = chosen.isEmpty ? tr("Role") : (chosen.length == 1 ? labelOf(chosen.first) : "${chosen.length} ${tr('roles')}");
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        avatar: Icon(chosen.isEmpty ? Icons.filter_list_rounded : Icons.check_rounded, size: 16),
        label: Text.rich(TextSpan(text: text), overflow: TextOverflow.ellipsis),
        backgroundColor: AppPalette.bg(chosen.isEmpty ? Colors.white : const Color(0xFFEDE3F8)),
        side: BorderSide(color: AppPalette.line(chosen.isEmpty ? Colors.black12 : pPurple)),
        onPressed: opts.isEmpty
            ? null
            : () async {
                final picked = Set<String>.of(chosen);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => StatefulBuilder(
                    builder: (ctx, set) => AlertDialog(
                      title: const Text("Filter by role"),
                      content: SizedBox(
                        width: 380,
                        height: 440,
                        child: Column(children: [
                          Row(children: [
                            TextButton(onPressed: () => set(() => picked.addAll(opts.map((o) => o['value'].toString()))), child: const Text("Select all")),
                            TextButton(onPressed: () => set(picked.clear), child: const Text("Clear")),
                          ]),
                          Expanded(
                            child: ListView(children: [
                              for (final o in opts)
                                CheckboxListTile(
                                  dense: true,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  value: picked.contains(o['value'].toString()),
                                  title: Text.rich(TextSpan(text: "${o['label']}  (${o['n']})")),
                                  onChanged: (v) => set(() => v == true ? picked.add(o['value'].toString()) : picked.remove(o['value'].toString())),
                                ),
                            ]),
                          ),
                        ]),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Apply")),
                      ],
                    ),
                  ),
                );
                if (ok != true || !mounted) return;
                setState(() => _role = picked.isEmpty ? null : picked.join('|'));
                _load();
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scopeText = switch (_scope) {
      'church' => "Accounts across the whole church.",
      'location' => "Accounts in your location.",
      'sub_location' => "Accounts in your sub-location.",
      _ => "Your role cannot manage accounts. An admin can give it the \"Approve Accounts\" permission.",
    };
    final anyFilter = _role != null || _location != null || _subLocation != null || _department != null;
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        centerTitle: true,
        title: Text("User management", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [IconButton(tooltip: tr("Refresh"), onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSizes.gutter, 10, AppSizes.gutter, 0),
          child: Column(children: [
            Text(scopeText, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
            const SizedBox(height: 8),
            Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'pending', icon: Icon(Icons.hourglass_top_rounded, size: 18), label: Text("Pending")),
                    ButtonSegment(value: 'incomplete', icon: Icon(Icons.pending_outlined, size: 18), label: Text("Unfinished")),
                    ButtonSegment(value: 'approved', icon: Icon(Icons.verified_rounded, size: 18), label: Text("Approved")),
                    ButtonSegment(value: 'rejected', icon: Icon(Icons.block_rounded, size: 18), label: Text("Rejected")),
                    ButtonSegment(value: 'all', icon: Icon(Icons.groups_rounded, size: 18), label: Text("All")),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) {
                    setState(() => _status = s.first);
                    _load();
                  },
                ),
              ),
            ),
            if (_status == 'incomplete')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(children: [
                  Text("Registrations that were started but never completed. They are not sent for approval.",
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
                  if (_isAdmin)
                    TextButton.icon(
                      onPressed: _purgeIncomplete,
                      icon: Icon(Icons.delete_sweep_rounded, color: AppPalette.fg(Colors.red.shade700)),
                      label: Text("Remove unfinished registrations", style: TextStyle(color: AppPalette.fg(Colors.red.shade700))),
                    ),
                ]),
              ),
            const SizedBox(height: 8),
            TextField(
              onChanged: (v) => _search = v,
              onSubmitted: (_) => _load(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: tr("Search name, email, SCJ ID or phone, then press Enter"),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: AppPalette.bg(Colors.white),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 6),
            // Filters in the middle; they scroll sideways when they don't fit
            Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _roleFilter(),
                  _filter('location', "Location", _location, (v) => _location = v),
                  _filter('sub_location', "Sub-location", _subLocation, (v) => _subLocation = v),
                  _filter('department', "Department", _department, (v) => _department = v),
                  if (anyFilter)
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _role = _location = _subLocation = _department = null);
                        _load();
                      },
                      icon: const Icon(Icons.clear_all_rounded, size: 18),
                      label: const Text("Clear"),
                    ),
                ]),
              ),
            ),
            if (!_loading && _error == null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Text("$_total account${_total == 1 ? '' : 's'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.red.shade800)))))
                  : _rows.isEmpty
                      ? Center(
                          child: Text(_status == 'pending' ? "No accounts waiting for approval." : "No accounts found.",
                              style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey))))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: CardGrid(
                            padding: const EdgeInsets.fromLTRB(AppSizes.gutter, 0, AppSizes.gutter, 24),
                            extent: AppSizes.listCard,
                            itemCount: _rows.length + (_rows.length < _total ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i >= _rows.length) {
                                return Center(
                                  child: _loadingMore
                                      ? const CircularProgressIndicator()
                                      : TextButton.icon(onPressed: () => _load(more: true), icon: const Icon(Icons.expand_more_rounded), label: Text("Show more (${_total - _rows.length})")),
                                );
                              }
                              final r = _rows[i];
                              final id = r['id'].toString();
                              final name = _name(r);
                              final st = _v(r, 'approval_status');
                              final unit = [_v(r, 'location'), _v(r, 'sub_location'), _v(r, 'department'), _v(r, 'team'), _v(r, 'cell_group')]
                                  .where((x) => x.isNotEmpty)
                                  .join(' › ');
                              final statusColor = st == 'approved' ? Colors.green.shade700 : (st == 'rejected' ? Colors.red.shade700 : Colors.orange.shade800);
                              return CompactCard(
                                leading: CircleAvatar(
                                  radius: 17,
                                  backgroundColor: AppPalette.bg(statusColor.withValues(alpha: 0.12)),
                                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(color: AppPalette.fg(statusColor), fontWeight: FontWeight.bold)),
                                ),
                                title: name,
                                subtitle: [
                                  _v(r, 'role_name').isEmpty ? _v(r, 'role') : _v(r, 'role_name'),
                                  unit,
                                  if (_status == 'all') st,
                                ].where((x) => x.isNotEmpty).join(' · '),
                                onTap: () => _details(r),
                                trailing: _busy.contains(id)
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Row(mainAxisSize: MainAxisSize.min, children: [
                                        if (st == 'pending') ..._actions(r),
                                        Icon(Icons.chevron_right_rounded, color: AppPalette.fg(Colors.grey)),
                                      ]),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
