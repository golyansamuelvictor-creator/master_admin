// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';

class AdminUserManagementScreen extends StatefulWidget {
  const AdminUserManagementScreen({super.key});

  @override
  State<AdminUserManagementScreen> createState() => _AdminUserManagementScreenState();
}

class _AdminUserManagementScreenState extends State<AdminUserManagementScreen> {
  final _supabase = Supabase.instance.client;

  String _currentView = 'menu'; // 'menu', 'approve', 'roles', 'remove'
  bool _isLoading = false;
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _appRoles = [];
  String _searchQuery = '';

  final Color pPurple = const Color(0xFF4A148C);
  final Color pGold = const Color(0xFFB78103);

  // Exact Official Department UUIDs from your app_roles table
  final Map<String, String?> _deptUUIDMap = {
    "All / General": null,
    "내무부 (Internal Affairs)": "1ab8ccda-1551-4cdc-8e6c-6d8c50a7ebe2",
    "장년회 (MG)": "03100bbc-6897-4538-8533-c9f36fe74f41",
    "부녀회 (WG)": "fd7bc250-72b6-449b-b0eb-348483261c17",
    "청년회 (YAG)": "5c8a3f12-7e44-4829-9b93-8a123456789a",
    "새신자 (New Saints)": "ccf31d7c-119d-4cba-82e0-b47540489d64",
    "MOU": "65d7451d-83d8-459d-81b8-b73fea7636cb",
  };

  @override
  void initState() {
    super.initState();
    _loadAppRoles();
  }

  Future<void> _loadAppRoles() async {
    try {
      final res = await _supabase.from('app_roles').select();
      setState(() => _appRoles = List<Map<String, dynamic>>.from(res));
    } catch (e) {
      debugPrint("Error loading roles: $e");
    }
  }

  Future<void> _loadProfiles({bool pendingOnly = false}) async {
    setState(() => _isLoading = true);
    try {
      var query = _supabase.from('profiles').select();
      if (pendingOnly) {
        query = query.or('is_approved.is.false,approval_status.eq.pending');
      }
      final res = await query.order('created_at', ascending: false);
      setState(() {
        _profiles = List<Map<String, dynamic>>.from(res);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading profiles: $e");
      setState(() => _isLoading = false);
    }
  }

  // ==========================================
  // 1. APPROVE ACCOUNT ACTION
  // ==========================================
  Future<void> _approveUser(Map<String, dynamic> user) async {
    try {
      await _supabase.from('profiles').update({
        'is_approved': true,
        'approval_status': 'approved',
      }).eq('id', user['id']);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Approved account for ${user['full_name'] ?? user['email']}."),
          backgroundColor: Colors.green.shade800,
        ),
      );
      _loadProfiles(pendingOnly: true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Approval error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rejectUser(Map<String, dynamic> user) async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reject Registration"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Reason for rejecting ${user['full_name'] ?? user['email']}:"),
            const SizedBox(height: 10),
            TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: "Reason", border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(Colors.red)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Reject", style: TextStyle(color: AppPalette.fg(Colors.white))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _supabase.from('profiles').update({
        'is_approved': false,
        'approval_status': 'rejected',
        'rejection_reason': reasonCtrl.text.trim(),
      }).eq('id', user['id']);
      _loadProfiles(pendingOnly: true);
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
          final targetDeptUUID = _deptUUIDMap[selectedDeptLabel];

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
                    items: _deptUUIDMap.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
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
                  await _supabase.from('profiles').update({
                    'role': selectedRoleKey,
                    'secondary_role': selectedSecondaryKey == selectedRoleKey ? null : selectedSecondaryKey,
                  }).eq('id', user['id']);

                  Navigator.pop(ctx);
                  _loadProfiles(pendingOnly: false);
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
        title: Text("Remove User: ${user['full_name'] ?? user['email']}", style: TextStyle(color: AppPalette.fg(Colors.red))),
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
      await _supabase.from('profiles').delete().eq('id', user['id']);
      _loadProfiles(pendingOnly: false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User removed successfully.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppPalette.bg(pPurple),
        title: Text("User Administration", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontSize: 16)),
        leading: _currentView != 'menu'
            ? IconButton(icon: Icon(Icons.arrow_back, color: AppPalette.fg(Colors.white)), onPressed: () => setState(() => _currentView = 'menu'))
            : null,
      ),
      body: _buildCurrentView(),
    );
  }

  Widget _buildCurrentView() {
    switch (_currentView) {
      case 'approve': return _buildListView(isApprovalView: true);
      case 'roles': return _buildListView(isRoleChangeView: true);
      case 'remove': return _buildListView(isRemoveView: true);
      case 'menu':
      default: return _buildSelectionMenu();
    }
  }

  Widget _buildSelectionMenu() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 550),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Profiles Management",
                textAlign: TextAlign.center,
                style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple))),
            const SizedBox(height: 6),
            Text("Select an administrative operation",
                textAlign: TextAlign.center,
                style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey))),
            const SizedBox(height: 28),

            _menuCard(
              icon: Icons.how_to_reg_rounded,
              color: Colors.green.shade700,
              title: "Approve New Users",
              subtitle: "Load pending accounts and grant verified approval.",
              onTap: () {
                setState(() => _currentView = 'approve');
                _loadProfiles(pendingOnly: true);
              },
            ),
            const SizedBox(height: 14),

            _menuCard(
              icon: Icons.manage_accounts_rounded,
              color: Colors.blue.shade800,
              title: "Change Roles",
              subtitle: "Filter roles dynamically by unit category and department.",
              onTap: () {
                setState(() => _currentView = 'roles');
                _loadProfiles(pendingOnly: false);
              },
            ),
            const SizedBox(height: 14),

            _menuCard(
              icon: Icons.person_remove_rounded,
              color: Colors.red.shade700,
              title: "Remove User",
              subtitle: "Review members under units and delete accounts.",
              onTap: () {
                setState(() => _currentView = 'remove');
                _loadProfiles(pendingOnly: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuCard({required IconData icon, required Color color, required String title, required String subtitle, required VoidCallback onTap}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppPalette.bg(color.withValues(alpha: 0.12)), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: AppPalette.fg(color), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppPalette.fg(Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListView({bool isApprovalView = false, bool isRoleChangeView = false, bool isRemoveView = false}) {
    final filtered = _profiles.where((p) {
      final name = (p['full_name'] ?? '').toString().toLowerCase();
      final email = (p['email'] ?? '').toString().toLowerCase();
      final scj = (p['scj_id'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || email.contains(q) || scj.contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: TextField(
            decoration: InputDecoration(
              hintText: "Search Name, Email, or SCJ ID...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(child: Text(isApprovalView ? "No accounts pending approval." : "No profiles found.", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey))))
                  : ListView.builder(
                      itemCount: filtered.length,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      itemBuilder: (ctx, i) {
                        final u = filtered[i];
                        final bool approved = u['is_approved'] == true;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            title: Text(u['full_name'] ?? u['email'] ?? "Member", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text(
                              "SCJ ID: ${u['scj_id'] ?? 'N/A'} • Role: ${u['role'] ?? 'Saint'}\nDept: ${u['department'] ?? '내무부'} • Status: ${u['approval_status'] ?? (approved ? 'approved' : 'pending')}",
                              style: GoogleFonts.merriweather(fontSize: 11, height: 1.4),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isApprovalView) ...[
                                  IconButton(icon: Icon(Icons.check_circle_rounded, color: AppPalette.fg(Colors.green)), tooltip: "Approve", onPressed: () => _approveUser(u)),
                                  IconButton(icon: Icon(Icons.cancel_rounded, color: AppPalette.fg(Colors.red)), tooltip: "Reject", onPressed: () => _rejectUser(u)),
                                ],
                                if (isRoleChangeView)
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.edit, size: 14),
                                    label: const Text("Role"),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(pPurple), foregroundColor: AppPalette.fg(Colors.white)),
                                    onPressed: () => _openChangeRoleDialog(u),
                                  ),
                                if (isRemoveView)
                                  IconButton(icon: Icon(Icons.delete_forever_rounded, color: AppPalette.fg(Colors.red)), tooltip: "Delete", onPressed: () => _removeUser(u)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}