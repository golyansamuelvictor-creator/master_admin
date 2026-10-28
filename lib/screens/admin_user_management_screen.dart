// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';
import 'package:master_admin/core/app_sizes.dart';
import 'package:master_admin/widgets/compact_card.dart';

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
    try {
      final r = await Future.wait<dynamic>([
        _db.rpc('account_approval_scope'),
        _db.rpc('is_admin'),
        _db.from('app_roles').select(),
        _db.from('official_departments').select('id, name, name_en, name_ko, parent_id').order('name'),
      ]);
      _scope = r[0]?.toString();
      _isAdmin = r[1] == true;
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
          _error = "Couldn't load accounts. Ask the admin to run 11_round10.sql.";
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
              decoration: InputDecoration(labelText: tr("Reason (shown to the person)"), border: const OutlineInputBorder()),
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
  void _openChangeRoleDialog(Map<String, dynamic> user) {
    String selectedWorkerType = "location"; // "location" or "church"
    String selectedDeptLabel = "All / General";
    String selectedUnitLevel = "All Levels";
    // profiles.role stores the role_key (e.g. cell_leader); the dropdown shows display names.
    String? selectedRoleKey = user['role']?.toString();
    final currentRole = _appRoles.firstWhere((r) => r['role_key'] == selectedRoleKey, orElse: () => <String, dynamic>{});
    String? selectedRoleName = (currentRole['display_name'] ?? selectedRoleKey)?.toString();
    // Optional second role (its duties are added to the primary role's)
    String? selectedSecondaryKey = (user['secondary_role'] ?? '').toString().isEmpty ? null : user['secondary_role'].toString();
    if (selectedSecondaryKey != null && !_appRoles.any((r) => r['role_key'] == selectedSecondaryKey)) selectedSecondaryKey = null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) {
          final targetDeptUUID = _deptOptions[selectedDeptLabel];

          // Filter app_roles based on approval_scope, official_dept_id, and level
          final filteredRoles = _appRoles.where((r) {
            final scope = (r['approval_scope'] ?? '').toString().toLowerCase();
            final deptId = r['official_dept_id']?.toString();
            final level = r['approval_level']?.toString();
            final grouping = (r['Grouping'] ?? '').toString();

            // 1. Worker Scope filter (Location vs Church)
            bool scopeMatch = true;
            if (selectedWorkerType == "location") {
              scopeMatch = scope == 'team' || scope == 'sub_location' || scope == 'location' || grouping.startsWith('Location') || grouping.startsWith('Cell') || grouping.startsWith('Team');
            } else {
              scopeMatch = scope == 'church' || scope == 'church_department' || grouping.startsWith('Church') || grouping.startsWith('24-Dept');
            }

            // 2. Department UUID filter
            bool deptMatch = true;
            if (targetDeptUUID != null) {
              deptMatch = deptId == targetDeptUUID || grouping.contains(selectedDeptLabel.split(' ').first);
            }

            // 3. Level filter
            bool levelMatch = true;
            if (selectedUnitLevel == "Cell") {
              levelMatch = grouping.toLowerCase().contains("cell");
            } else if (selectedUnitLevel == "Team (Level 1)") {
              levelMatch = level == "1";
            } else if (selectedUnitLevel == "Dept (Level 2)") {
              levelMatch = level == "2";
            } else if (selectedUnitLevel == "Sub-Location (Level 3)") {
              levelMatch = level == "3";
            } else if (selectedUnitLevel == "Location (Level 4)") {
              levelMatch = level == "4";
            } else if (selectedUnitLevel == "Church / 24-Dept (Level 5)") {
              levelMatch = level == "5";
            }

            return scopeMatch && deptMatch && levelMatch;
          }).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text("Change Role: ${user['full_name'] ?? 'Member'}",
                style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(pPurple))),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Worker Category
                  const Text("1. Worker Category Scope:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedWorkerType,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
                    items: const [
                      DropdownMenuItem(value: "location", child: Text("Location Workers (지회/지부/팀/구역)")),
                      DropdownMenuItem(value: "church", child: Text("Church & 24 Departments (교회/총회/24부서)")),
                    ],
                    onChanged: (v) => setDState(() {
                      selectedWorkerType = v!;
                      selectedRoleName = null;
                    }),
                  ),
                  const SizedBox(height: 12),

                  // 2. Department
                  const Text("2. Department / Group:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedDeptLabel,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
                    isExpanded: true,
                    items: _deptOptions.keys.map((k) => DropdownMenuItem(value: k, child: Text(k, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setDState(() {
                      selectedDeptLabel = v!;
                      selectedRoleName = null;
                    }),
                  ),
                  const SizedBox(height: 12),

                  // 3. Unit Level
                  const Text("3. Unit Level:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedUnitLevel,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
                    items: const [
                      DropdownMenuItem(value: "All Levels", child: Text("All Levels")),
                      DropdownMenuItem(value: "Cell", child: Text("Cell Group (구역)")),
                      DropdownMenuItem(value: "Team (Level 1)", child: Text("Team (Level 1 - 팀)")),
                      DropdownMenuItem(value: "Dept (Level 2)", child: Text("Department (Level 2 - 부서)")),
                      DropdownMenuItem(value: "Sub-Location (Level 3)", child: Text("Sub-Location (Level 3 - 부지역)")),
                      DropdownMenuItem(value: "Location (Level 4)", child: Text("Location (Level 4 - 지역)")),
                      DropdownMenuItem(value: "Church / 24-Dept (Level 5)", child: Text("Church / General (Level 5 - 총회/교회)")),
                    ],
                    onChanged: (v) => setDState(() {
                      selectedUnitLevel = v!;
                      selectedRoleName = null;
                    }),
                  ),
                  const SizedBox(height: 12),

                  // 4. DYNAMIC ROLE DROPDOWN FROM APP_ROLES
                  const Text("4. Designated Role (display_name):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: filteredRoles.any((r) => r['display_name'] == selectedRoleName) ? selectedRoleName : null,
                    hint: Text(filteredRoles.isEmpty ? "No roles match criteria" : "Select Role"),
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
                    items: filteredRoles.map((r) {
                      final ko = r['display_name_ko'] != null ? " (${r['display_name_ko']})" : "";
                      return DropdownMenuItem<String>(
                        value: r['display_name'].toString(),
                        child: Text("${r['display_name']}$ko", overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (v) {
                      final match = filteredRoles.firstWhere((r) => r['display_name'] == v, orElse: () => {});
                      setDState(() {
                        selectedRoleName = v;
                        selectedRoleKey = match['role_key']?.toString();
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  // 5. OPTIONAL SECONDARY ROLE
                  const Text("5. Secondary Role (optional):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSecondaryKey ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
                    items: [
                      const DropdownMenuItem<String>(value: '', child: Text("None")),
                      ...(_appRoles.where((r) => r['role_key'] != null).toList()
                            ..sort((a, b) => (a['display_name'] ?? '').toString().compareTo((b['display_name'] ?? '').toString())))
                          .map((r) => DropdownMenuItem<String>(
                                value: r['role_key'].toString(),
                                child: Text((r['display_name'] ?? r['role_key']).toString(), overflow: TextOverflow.ellipsis),
                              )),
                    ],
                    onChanged: (v) => setDState(() => selectedSecondaryKey = (v == null || v.isEmpty) ? null : v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(pPurple)),
                onPressed: (selectedRoleName == null || selectedRoleKey == null) ? null : () async {
                  // Saves the role_key, which the rest of the app looks roles up by
                  // (it used to save the display name, e.g. "Cell Leader", so the new
                  // role matched nothing). app_role_id isn't a profiles column, and
                  // forcing department to 내무부 moved users out of their own reports.
                  await _db.from('profiles').update({
                    'role': selectedRoleKey,
                    'secondary_role': selectedSecondaryKey == selectedRoleKey ? null : selectedSecondaryKey,
                  }).eq('id', user['id']);

                  Navigator.pop(ctx);
                  _load();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Role updated to '$selectedRoleName'"), backgroundColor: Colors.green),
                  );
                },
                child: Text("Save Role", style: TextStyle(color: AppPalette.fg(Colors.white))),
              ),
            ],
          );
        },
      ),
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
        content: const Text("Are you sure you want to remove this user from the profiles table? This cannot be undone."),
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
        await _db.from('profiles').delete().eq('id', user['id']);
        _load();
        _snack("User removed successfully.");
      } catch (e) {
        _snack("Couldn't remove: $e", error: true);
      }
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
              SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
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
      if (st != 'approved')
        full
            ? ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                onPressed: () {
                  close();
                  _decide(r, true);
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text("Approve"))
            : IconButton(tooltip: tr("Approve"), icon: Icon(Icons.check_circle_rounded, color: AppPalette.fg(Colors.green.shade700)), onPressed: () => _decide(r, true)),
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
            : IconButton(tooltip: tr("Reject"), icon: Icon(Icons.cancel_rounded, color: AppPalette.fg(Colors.red.shade700)), onPressed: () => _decide(r, false)),
      if (_isAdmin && full) ...[
        OutlinedButton.icon(
            onPressed: () {
              close();
              _openChangeRoleDialog(r);
            },
            icon: const Icon(Icons.manage_accounts_rounded, size: 18),
            label: const Text("Change role")),
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
                  _filter('role', "Role", _role, (v) => _role = v),
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
