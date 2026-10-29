// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- ALL IMPORTS ACTIVELY USED ---
import 'cell_status_screen.dart';
import 'compilation_screen.dart';
import 'member_directory_screen.dart';
import 'entry_form_screen.dart';
import '../admin_tools/approval_cockpit.dart';
import 'admin/transfer_request_form.dart';
import 'notification_center_screen.dart';
import 'service_photos_screen.dart';
import 'admin_user_management_screen.dart';
import 'admin/milestone_upload.dart';
import 'admin/target_setter_screen.dart';
import 'admin/monthly_executive_report.dart';
import 'admin/universal_intervention_screen.dart';
import '../admin_tools/member_sync_tool.dart';
import '../admin_tools/task_manager_screen.dart';
import 'admin/unit_growth_tracker_screen.dart';
import 'package:master_admin/core/app_palette.dart';
import '../core/group_scope.dart';
import 'member_change_approvals_screen.dart';
import 'duty_panel_screen.dart';
import 'evangelism/bb_workspace_screen.dart';
import 'evangelism/evangelism_results_screen.dart';
import '../core/app_sizes.dart';

class ReportsScreen extends StatefulWidget {
  final String userEmail, userRole;
  const ReportsScreen({super.key, required this.userEmail, required this.userRole});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _supabase = Supabase.instance.client;
  
  String? selectedRole; 
  String? _simulatedRole; 
  String? _secondaryRole; 
  bool _isLoading = true;
  bool _hasRedirected = false; 
  String userLoc = ""; String userSub = ""; String userDept = ""; String userTeam = ""; String userCell = "";
  int _flaggedCount = 0;
  String _latestCorrectionNote = "";

  List<String> _dynamicDuties = [];
  List<String> _primaryRoleDuties = [];
  List<String> _dynamicAdminActions = [];
  Map<String, String> _interventionLabels = {}; 
  // Who enters each duty, when a duty has its own rule (duty_entry_rules in
  // 12_round11.sql), e.g. Offering: the department treasurer; BB File: the
  // location evangelism secretary. Everyone else with the duty only views it.
  Map<String, List<String>> _entryRules = {};
  // Duties with a policies / goals panel (duty_managers): Service Attendance
  // here; Evangelism has its own button in the Evangelism menu
  Set<String> _policyDuties = {};
  bool _canEnterDataFromDB = false;
  String? _roleApprovalScope;
  String _roleGrouping = '';
  List<Map<String, dynamic>> _availableRoles = [];

  @override
  void initState() { 
    super.initState(); 
    _fetchDutyConfig(); 
    _identifyUser(); 
  }

  Future<void> _identifyUser() async {
    try {
      final data = await _supabase.from('profiles').select().eq('email', widget.userEmail).maybeSingle();
      if (data != null && mounted) {
        selectedRole = data['role']; 
        _simulatedRole = data['role']; 
        _secondaryRole = data['secondary_role']; 
        userLoc = data['location'] ?? ""; 
        userSub = data['sub_location'] ?? ""; 
        userDept = data['department'] ?? ""; 
        userTeam = data['team'] ?? ""; 
        userCell = data['cell_group'] ?? ""; 

        // Extract scj_id from profiles
        final String userScjId = (data['scj_id'] ?? data['scj_number'] ?? "").toString().trim();

        // Cross-check members table using scj_id if unit information is missing from profiles
        if ((userLoc.isEmpty || userCell.isEmpty) && userScjId.isNotEmpty) {
          final memberData = await _supabase
              .from('members')
              .select('location, sub_location, department, team, cell_group')
              .eq('scj_id', userScjId)
              .maybeSingle();

          if (memberData != null) {
            if (userLoc.isEmpty) userLoc = memberData['location'] ?? "";
            if (userSub.isEmpty) userSub = memberData['sub_location'] ?? "";
            if (userDept.isEmpty) userDept = memberData['department'] ?? "";
            if (userTeam.isEmpty) userTeam = memberData['team'] ?? "";
            if (userCell.isEmpty) userCell = memberData['cell_group'] ?? "";
          }
        }

        setState(() {});
        await _fetchRolePermissions(_simulatedRole!); 
        await _fetchDutyConfig(); 
        await _fetchAvailableRoles();
        _checkForFlaggedReports();

        if (!_hasRedirected) {
          _hasRedirected = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_simulatedRole == 'loc_evangelism_mgr' || _simulatedRole == 'evang_dept_leader') {
              _showEvangelismSubMenu();
            } else if (_simulatedRole == 'loc_edu_mgr' || _simulatedRole == 'edu_dept_leader') {
              _showDutyActionDialog("All Saints Education");
            } else if (selectedRole != 'admin') {
              // Only one duty: skip the one-button grid and open that duty
              // (the Notification Center added for every reporter doesn't count)
              final buttons = _getMainGridButtons()
                  .where((b) => b != "Notification Center" || _dynamicAdminActions.contains('Notification Center'))
                  .toList();
              const nonDuty = ["Member Bio", "Strategic Analysis", "Notification Center"];
              if (buttons.length == 1 && !nonDuty.contains(buttons.first)) {
                final only = buttons.first;
                if (only == "Evangelism") {
                  _showEvangelismSubMenu();
                } else {
                  _showDutyActionDialog(only, exitOnClose: true);
                }
              }
            }
          });
        }
      }
    } catch (e) { 
      debugPrint("User Error: $e"); 
    } finally { 
      if (mounted) setState(() => _isLoading = false); 
    }
  }

  Future<void> _fetchAvailableRoles() async {
    try {
      final res = await _supabase
          .from('app_roles')
          .select('role_key, display_name, "Grouping", display_name_ko, approval_scope')
          .order('display_name');
      if (mounted && res.isNotEmpty) {
        setState(() {
          _availableRoles = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (e) {
      debugPrint("Available roles fetch error: $e");
    }
  }

  Future<void> _fetchDutyConfig() async {
    try {
      final pm = await _supabase.from('duty_managers').select('duty_name');
      _policyDuties = {for (final r in pm) r['duty_name'].toString()};
      final rules = await _supabase.from('duty_entry_rules').select('duty_name, entry_roles');
      _entryRules = {
        for (final r in rules)
          r['duty_name'].toString(): List<String>.from((r['entry_roles'] ?? const []) as List).map((e) => e.toLowerCase()).toList(),
      };
    } catch (e) {
      debugPrint("Entry rules not loaded (run 12_round11.sql): $e");
    }
    try {
      final res = await _supabase.from('app_duty_config').select('duty_name, intervention_label');
      if (mounted && res.isNotEmpty) {
        setState(() {
          _interventionLabels = {
            for (var item in res)
              if (item['duty_name'] != null && item['intervention_label'] != null)
                item['duty_name'].toString().trim(): item['intervention_label'].toString().trim()
          };
        });
      }
    } catch (e) { 
      debugPrint("Labels Load Error: $e"); 
    }
  }

  String _getInterventionLabel(String duty) {
    String cleanDuty = duty.trim();
    if (_interventionLabels.containsKey(cleanDuty)) return _interventionLabels[cleanDuty]!;
    if (cleanDuty == "Evangelism Part" && _interventionLabels.containsKey("Evangelism")) {
      return _interventionLabels["Evangelism"]!;
    }
    if (cleanDuty == "Evangelism" && _interventionLabels.containsKey("Evangelism Part")) {
      return _interventionLabels["Evangelism Part"]!;
    }
    for (var entry in _interventionLabels.entries) {
      if (entry.key.toLowerCase() == cleanDuty.toLowerCase()) return entry.value;
    }
    return "$cleanDuty absentees";
  }

  Future<void> _fetchRolePermissions(String roleKey) async {
    try {
      final res = await _supabase.from('app_roles').select().eq('role_key', roleKey).maybeSingle();
      
      List<String> primaryDuties = [];
      List<String> primaryActions = [];
      bool canEnter = false;
      String? scope;
      
      if (res != null) {
        primaryDuties = List<String>.from(res['allowed_duties'] ?? []);
        _primaryRoleDuties = List<String>.from(primaryDuties);
        primaryActions = List<String>.from(res['allowed_admin_actions'] ?? []);
        canEnter = res['can_enter_data'] ?? false;
        scope = res['approval_scope'];
        _roleGrouping = (res['Grouping'] ?? '').toString();

        // MG, WG, YAG, MOU and New Saints belong to Internal Affairs: they
        // only report on their group's members across the church, so the
        // department workers' reports (entered by the other 24 departments
        // for their own workers) are neither entered nor shown for them.
        final grp = GroupScope.detect(grouping: _roleGrouping, role: roleKey);
        if (grp != null && grp != '신학부') {
          primaryDuties.removeWhere((d) => const ['Workers Education', 'Workers Daily Participation'].contains(d));
          _primaryRoleDuties = List<String>.from(primaryDuties);
        }

        // If simulated by admin, sync the department context to match the role being simulated
        if (selectedRole == 'admin') {
          if (res['display_name_ko'] != null && res['display_name_ko'].toString().isNotEmpty) {
            userDept = res['display_name_ko'];
          } else if (res['Grouping'] != null && res['Grouping'].toString().isNotEmpty) {
            userDept = res['Grouping'];
          }
        } else if (userDept.isEmpty && res['display_name_ko'] != null) {
          userDept = res['display_name_ko'];
        }
      }

      if (_secondaryRole != null && _secondaryRole!.isNotEmpty) {
        final secRes = await _supabase.from('app_roles').select().eq('role_key', _secondaryRole!).maybeSingle();
        if (secRes != null) {
          final secDuties = List<String>.from(secRes['allowed_duties'] ?? []);
          final secActions = List<String>.from(secRes['allowed_admin_actions'] ?? []);
          primaryDuties.addAll(secDuties);
          primaryActions.addAll(secActions);
          if (secRes['can_enter_data'] == true) canEnter = true;
          if (scope == null && secRes['approval_scope'] != null) {
            scope = secRes['approval_scope'];
          }
        }
      }

      if (mounted) {
        setState(() {
          _dynamicDuties = primaryDuties.toSet().toList();
          _dynamicAdminActions = primaryActions.toSet().toList();
          _canEnterDataFromDB = canEnter;
          _roleApprovalScope = scope;
        });
      }
    } catch (e) { debugPrint("Permission Error: $e"); }
  }

  Future<void> _checkForFlaggedReports() async {
    if (_simulatedRole == null || !_simulatedRole!.contains('cell') || userCell.isEmpty) return;
    try {
      final res = await _supabase.from('logs_service_attendance_status').select('correction_note').eq('unit_name', userCell).eq('flagged_for_correction', true).limit(1);
      if (res.isNotEmpty && mounted) setState(() { _flaggedCount = res.length; _latestCorrectionNote = res[0]['correction_note'] ?? "Check your reports."; });
    } catch (e) { debugPrint("Flag Check Error: $e"); }
  }

  // --- DUAL-MODE & BOUNDARY PERMISSION MATRIX ---
  bool _canUserEnterData(String duty) {
    String r = _simulatedRole?.toLowerCase() ?? ""; 
    String sec = _secondaryRole?.toLowerCase() ?? "";

    // 1. Admin can enter all reports
    if (r == 'admin') return true;

    // 1b. Duties with their own rule: only the listed roles enter them
    final cleanName = duty == 'Evangelism' ? 'Evangelism Part' : duty;
    final rule = _entryRules[duty] ?? _entryRules[cleanName] ?? (duty == 'Offering' ? _entryRules['Offering Status'] : null);
    if (rule != null) return rule.contains(r) || (sec.isNotEmpty && rule.contains(sec));

    // 2. Strict DB gate: If can_enter_data is FALSE in app_roles, this department
    // has NO dual modes (they are strictly view-only across all duties)
    if (!_canEnterDataFromDB) return false;

    // 3. Must be actively listed in this role's allowed_duties in app_roles
    String cleanDuty = duty == 'Evangelism' ? 'Evangelism Part' : duty;
    bool isAllowedInDB = _dynamicDuties.contains(duty) || _dynamicDuties.contains(cleanDuty);
    if (!isAllowedInDB) return false;

    // Church / Location congregation reports
    const churchLocationReports = [
      'Service Attendance Status',
      'Cell Group Service',
      'Offering Status',
      'Offering',
      'Visitations and Counselling',
      'Morning Light',
      'All Saints Education',
      'Evangelism',
      'Evangelism Part',
      'BB File',
      'Evangelism Results',
    ];

    // Department workers reports
    const departmentReports = [
      'Workers Education',
      'Workers Daily Participation',
    ];

    // 4. Leaders, Overseers, and General Secretaries cannot enter data
    if (r.startsWith('sub_loc_') || 
        r.startsWith('dept_leader') || 
        r == 'loc_leader' || 
        r == 'loc_gen_sec' || 
        r.contains('church_head') ||
        r.contains('church_secretary') ||
        (r.endsWith('_leader') && !r.contains('cell') && !r.contains('team'))) {
      return false;
    }

    // 5. Cell Leaders can ONLY enter cell / church reports
    if (r.contains('cell_leader') || sec.contains('cell_leader')) {
      return churchLocationReports.contains(duty);
    }

    // 6. Team Leaders can ONLY enter workers duties for their team
    if (r.contains('team_leader') || r.contains('assistant_team') || r.contains('team_sec') || sec.contains('team_sec')) {
      return departmentReports.contains(duty);
    }

    // 7. Department Secretaries (Internal Affairs, Construction, Praise, MOU, New Saints, etc.)
    bool isDepartmentScope = _roleApprovalScope == 'church_department' || 
                             _roleApprovalScope == 'department' ||
                             r.contains('dept_') || 
                             r.contains('_dept') ||
                             r.contains('group_sec');

    // 7a. Secretaries of the 24 church departments (welfare_dept_sec,
    //     fin_dept_sec, mg_group_sec …) enter every duty of their role for
    //     their own department at church level (the entry form lists only
    //     that department's members, never a location's).
    final bool churchDeptSecretary = _roleGrouping.startsWith('24-Dept') &&
        (r.endsWith('_sec') || r.endsWith('_mgr')) && !r.endsWith('_gen_sec');
    if (churchDeptSecretary) return true;

    if (isDepartmentScope) {
      if (churchLocationReports.contains(duty)) {
        return false; // Church reports for locations are view-only
      }
      return departmentReports.contains(duty); // Enters only respective department reports
    }

    // 8. Specific Location Managers
    if (r == 'loc_treasurer') return duty == 'Offering Status' || duty == 'Offering';
    if (r == 'loc_evangelism_mgr') return duty == 'Evangelism' || duty == 'Evangelism Part' || duty == 'BB File';
    if (r == 'loc_edu_mgr') return duty == 'Workers Education' || duty == 'All Saints Education';
    if (r == 'loc_ia_mgr') return false; 

    return false;
  }

  List<String> _getMainGridButtons() {
    if (_simulatedRole == 'loc_treasurer') {
      return [if (_canUserEnterData("Offering Status")) "Enter new offering data", "Open offering dashboard", _getInterventionLabel("Offering Status")];
    }
    if (_simulatedRole == 'loc_ia_mgr') {
      return ["Member Bio", "Service Attendance Status", "Cell Group Service", "Visitations and Counselling"];
    }

    List<String> buttons = [];
    if (_dynamicAdminActions.contains('View Member Profiles') || _dynamicAdminActions.contains('Member Bio')) buttons.add("Member Bio");
    // BB File opens from the Evangelism menu; with an Evangelism duty it
    // isn't repeated on the main grid.
    final hasEvangelism = _dynamicDuties.contains('Evangelism') || _dynamicDuties.contains('Evangelism Part');
    for (var d in _dynamicDuties) {
      String label = d == 'Evangelism Part' ? 'Evangelism' : d;
      if (hasEvangelism && label == 'BB File') continue;
      if (!label.toLowerCase().contains('growth')) buttons.add(label);
    }
    if (_dynamicAdminActions.contains('Strategic Analysis')) buttons.add("Strategic Analysis");
    // Everyone who saves reports can follow their status (Pending / Approved / Rejected)
    if (_dynamicAdminActions.contains('Notification Center') || _dynamicDuties.isNotEmpty || _dynamicAdminActions.contains('Request Member Transfer')) {
      buttons.add("Notification Center");
    }
    return buttons.toSet().toList();
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width; bool isDesktop = width > 900;
    final Color pPurple = const Color(0xFF4A148C);
    final allButtons = _getMainGridButtons();
    // Full width with a small edge (was 15% empty on each side on desktop)
    double hPadding = isDesktop ? 18 : AppSizes.gutter;

    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.transparent), elevation: 0, centerTitle: true,
        leading: IconButton(icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppPalette.fg(Color(0xFF4A148C)), size: 22), onPressed: () => Navigator.pop(context)),
        title: Text("Management reports", style: GoogleFonts.merriweather(color: AppPalette.fg(pPurple), fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator(color: Color(0xFF4A148C))) : Column(children: [
        if (selectedRole == 'admin') _buildAdminSwitcher(hPadding),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 10), 
          child: Container(
            width: double.infinity, height: isDesktop ? 40 : 34, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 10), 
            decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppPalette.line(pPurple.withValues(alpha: 0.1)), width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]), 
            child: Text(
              _secondaryRole != null && _secondaryRole!.isNotEmpty
                ? "Viewing as: ${_formatRoleToTitleCase(_simulatedRole)} + ${_formatRoleToTitleCase(_secondaryRole)}"
                : "Viewing as: ${_formatRoleToTitleCase(_simulatedRole)}", 
              textAlign: TextAlign.center, 
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: isDesktop ? 16 : 13, color: AppPalette.fg(pPurple))
            )
          )
        ),
        if (_flaggedCount > 0) _buildCorrectionNotification(hPadding),
        const SizedBox(height: 10),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(hPadding, 0, hPadding, 40), 
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: AppSizes.columns(width),
              mainAxisSpacing: 8,
              crossAxisSpacing: 12,
              mainAxisExtent: AppSizes.card, // the standard card height
            ), 
            itemCount: allButtons.length, 
            itemBuilder: (context, index) {
              String title = allButtons[index];
              bool isPrimary = ["Member Bio", "Strategic Analysis", "Notification Center"].contains(title);
              return Container(
                // elevated (raised) duty cards
                decoration: BoxDecoration(color: AppPalette.bg(isPrimary ? pPurple : Colors.white), borderRadius: BorderRadius.circular(15), border: Border.all(color: AppPalette.line(Colors.black.withValues(alpha: 0.06))), boxShadow: [BoxShadow(color: pPurple.withValues(alpha: isPrimary ? 0.30 : 0.14), blurRadius: 12, offset: const Offset(0, 5)), BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))]), 
                child: InkWell(borderRadius: BorderRadius.circular(15), onTap: () => _handleSelection(title), child: Center(child: Text(title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.fg(isPrimary ? Colors.white : Colors.black87)))))
              );
            }
          )
        ),
      ]),
    );
  }

  void _handleSelection(String title) {
    if (title == "Enter new offering data") _showDutyActionDialog("Offering Status");
    else if (title == "Open offering dashboard") _goToCorrectDashboard("Offering Status");
    else if (title == _getInterventionLabel("Offering Status")) {
       _openAbsentees("Offering Status", title, _simulatedRole);
    }
    else if (title == "Member Bio") _showMemberBioDialog();
    else if (title == "Strategic Analysis") _showStrategicAnalysisDialog();
    else if (title == "Notification Center") Navigator.push(context, MaterialPageRoute(builder: (c) => NotificationCenterScreen(
          userRole: _simulatedRole,
          // The transfer approvals inbox stays with the roles that had it
          canReviewTransfers: _dynamicAdminActions.contains('Notification Center'),
        )));
    else if (title == "Evangelism") _showEvangelismSubMenu();
    // BB File opens the BB File / Attendance sheets directly (no dashboard or policies there)
    else if (title == "BB File") _openBbFile();
    else if (title == "Evangelism Results" || title == "BB Results") _openEvangelismResults();
    else _showDutyActionDialog(title);
  }

  Future<DateTime?> _pickNiceDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final List<DateTime> allowedDays = List.generate(6, (index) => today.subtract(Duration(days: index)));

    DateTime? chosenDate = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          elevation: 10,
          backgroundColor: AppPalette.bg(Colors.white),
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppPalette.bg(const Color(0xFF4A148C).withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.edit_calendar_rounded, color: AppPalette.fg(Color(0xFF4A148C)), size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Select Report Date",
                            style: GoogleFonts.merriweather(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppPalette.fg(const Color(0xFF4A148C)),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Editable within the last 5 days",
                            style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 10),

                Column(
                  children: allowedDays.map((date) {
                    final int diff = today.difference(date).inDays;
                    String badgeLabel = "";
                    Color badgeColor = Colors.grey.shade600;
                    if (diff == 0) {
                      badgeLabel = "Today";
                      badgeColor = Colors.green[700]!;
                    } else if (diff == 1) {
                      badgeLabel = "Yesterday";
                      badgeColor = Colors.orange[800]!;
                    } else {
                      badgeLabel = "$diff days ago";
                    }

                    const List<String> weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
                    const List<String> months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

                    final String weekdayName = weekdays[date.weekday - 1];
                    final String monthName = months[date.month - 1];
                    final String formattedDate = "$weekdayName, $monthName ${date.day}, ${date.year}";

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        onTap: () => Navigator.pop(ctx, date),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppPalette.bg(diff == 0 
                                ? const Color(0xFF4A148C).withValues(alpha: 0.06) 
                                : const Color(0xFFFBFBFE)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppPalette.line(diff == 0 
                                  ? const Color(0xFF4A148C).withValues(alpha: 0.3) 
                                  : Colors.grey.shade200),
                              width: 1.1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    diff == 0 ? Icons.today_rounded : Icons.history_rounded,
                                    size: 16,
                                    color: AppPalette.fg(diff == 0 ? const Color(0xFF4A148C) : Colors.grey.shade700),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    formattedDate,
                                    style: GoogleFonts.merriweather(
                                      fontSize: 12.5,
                                      fontWeight: diff == 0 ? FontWeight.bold : FontWeight.w600,
                                      color: AppPalette.fg(Colors.black87),
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppPalette.bg(badgeColor.withValues(alpha: 0.1)),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  badgeLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppPalette.fg(badgeColor),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      "Cancel",
                      style: GoogleFonts.merriweather(
                        fontWeight: FontWeight.bold,
                        color: AppPalette.fg(Colors.grey.shade700),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return chosenDate;
  }

  /// The role that grants [duty]: the primary role, or the secondary role
  /// when only that one lists it (e.g. a cell leader who is also team secretary).
  String _roleForDuty(String duty) {
    final primary = _simulatedRole ?? '';
    final sec = _secondaryRole ?? '';
    if (sec.isEmpty || selectedRole == 'admin') return primary;
    final names = {duty, if (duty == 'Evangelism') 'Evangelism Part', if (duty == 'Evangelism Part') 'Evangelism'};
    if (_primaryRoleDuties.any(names.contains)) return primary;
    return sec;
  }

  void _showDutyActionDialog(String duty, {bool exitOnClose = false}) async {
    if (_interventionLabels.isEmpty) {
      await _fetchDutyConfig();
    }

    bool canEdit = _canUserEnterData(duty);
    String interventionLabel = _getInterventionLabel(duty);

    if (!mounted) return;

    showGeneralDialog(context: context, pageBuilder: (context, anim1, anim2) {
      return Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(Colors.white), 
          elevation: 0.5, 
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () {
            Navigator.pop(context);
            // Opened automatically for a single-duty user: close goes back home
            if (exitOnClose && mounted) Navigator.of(this.context).maybePop();
          }), 
          centerTitle: true, 
          title: Text(duty, style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold))
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(25), 
          child: Column(children: [
            const SizedBox(height: 5),
            if (canEdit) ...[
              _compactActionBtn(Icons.edit_note_rounded, "Enter new report", Colors.purple, () async { 
                // opens on top of this menu, so Back returns here
                await _nav(duty, "entry", selectedDate: DateTime.now()); 
              }),
              _compactActionBtn(Icons.history_rounded, "Edit previous report", Colors.orange[800]!, () async { 
                final picked = await _pickNiceDate();
                if (picked != null) {
                  await _nav(duty, "edit", selectedDate: picked);
                }
              }),
            ],
            _compactActionBtn(Icons.dashboard_customize_rounded, "Open dashboard", Colors.teal[700]!, () { 
              _goToCorrectDashboard(duty); 
            }),
            // Location Secretary: the general picture taken right after the service
            if (duty == 'Service Attendance Status' &&
                (_simulatedRole == 'admin' || _dynamicAdminActions.contains('Upload Service Photos')))
              _compactActionBtn(Icons.photo_camera_back_rounded, "Final service picture", Colors.indigo[700]!, () {
                Navigator.push(context, MaterialPageRoute(builder: (c) => const ServicePhotosScreen()));
              }),
            if (_policyDuties.contains(duty) && dutyFamily(duty) == duty && duty != 'Evangelism')
              _compactActionBtn(Icons.gavel_rounded, "Policies, standards & goals", Colors.teal[800]!, () {
                DutyPanelScreen.open(context, duty, role: selectedRole == 'admin' ? _simulatedRole : null);
              }),
            _compactActionBtn(Icons.person_search_rounded, interventionLabel, Colors.blue[800]!, () { 
              _openAbsentees(duty, interventionLabel, _roleForDuty(duty));
            }),
            if (!_roleForDuty(duty).contains('cell')) 
              _compactActionBtn(Icons.verified_user_rounded, "Approval cockpit", Colors.green[800]!, () async { 
                final dual = await _dualFor(duty, _roleForDuty(duty));
                if (!mounted) return;
                Navigator.push(context, MaterialPageRoute(
                  builder: (c) => ApprovalCockpit(
                    role: _roleForDuty(duty), 
                    unitName: _getUnitNameByRole(_roleForDuty(duty)), 
                    selectedDuty: duty,
                    dualTitle: dual?.title,
                    dualLabels: dual?.labels ?? const ("Church-wide", "Department only"),
                  )
                )); 
              }),
          ])
        )
      );
    });
  }

  Widget _compactActionBtn(IconData i, String l, Color c, VoidCallback t) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    height: 38,
    decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppPalette.line(c.withValues(alpha: 0.15)), width: 1.2), boxShadow: [BoxShadow(color: c.withValues(alpha: 0.16), blurRadius: 10, offset: const Offset(0, 4)), BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1))]), 
    child: InkWell(onTap: t, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 15), child: Row(children: [Icon(i, color: AppPalette.fg(c), size: 17), const SizedBox(width: 12), Expanded(child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold))), Icon(Icons.chevron_right_rounded, size: 16, color: AppPalette.fg(Colors.black26))])))
  );

  // (Offering is entered in the Offering entry form; the old Excel-upload placeholder opened nothing.)
  
  void _goToCorrectDashboard(String duty) { 
    final String role = _roleForDuty(duty);
    if (role.toLowerCase().contains('cell')) {
      Navigator.push(context, MaterialPageRoute(
        builder: (c) => CellStatusScreen(
          sheetName: duty, 
          cellName: userCell, 
          location: userLoc, 
          subLocation: userSub, 
          dept: userDept, 
          team: userTeam, 
          initialMode: "dashboard"
        )
      )); 
    } else {
      Navigator.push(context, MaterialPageRoute(
        builder: (c) => CompilationEngine(
          role: role, 
          userUnit: _getUnitNameByRole(role), 
          selectedDuty: duty, 
          loc: userLoc, 
          sub: userSub, 
          dept: userDept, 
          team: userTeam
        )
      )); 
    }
  }

  Future<void> _nav(String duty, String mode, {DateTime? selectedDate}) async { 
    DateTime dateToUse = selectedDate ?? DateTime.now();

    await Navigator.push(context, MaterialPageRoute(
      builder: (c) => EntryFormScreen(
        sheetName: duty, 
        cellName: userCell, 
        location: userLoc, 
        subLocation: userSub, 
        dept: userDept, 
        team: userTeam,
        userRole: _roleForDuty(duty),
        initialMode: mode,
        selectedDate: dateToUse,
      )
    )); 
  }

  /// The absentee list of exactly the leader's unit. Only the unit name was
  /// passed before, and it was matched against every level of the church, so
  /// all cells / teams sharing that name (and placeholders such as
  /// "Church Admin") gave the same, wrong list for everyone.
  Future<void> _openAbsentees(String duty, String title, String? role) async {
    final r = (role ?? _simulatedRole ?? '').toLowerCase();
    String? group;
    Map<String, String> scope;
    final loc = {'location': userLoc};
    final sub = {...loc, 'sub_location': userSub};
    final dept = {...sub, 'department': userDept};
    final team = {...dept, 'team': userTeam};
    final byKey = GroupScope.detect(grouping: '', role: r);
    if (r == 'admin' || r.startsWith('church_') || r.startsWith('korean_worker_')) {
      scope = {};
    } else if (byKey != null) {
      group = byKey;
      scope = {};
    } else if (r.contains('cell')) {
      scope = {...team, 'cell_group': userCell};
    } else if (r.contains('team')) {
      scope = team;
    } else if (r.startsWith('dept_')) {
      scope = dept;
    } else if (r.startsWith('sub_loc_')) {
      scope = sub;
    } else if (r.startsWith('loc_')) {
      scope = loc;
    } else {
      // Church-wide groups (장년회, 부녀회, 청년회, 새신자, 신학부 ...)
      try {
        final meta = await _supabase.from('app_roles').select('"Grouping"').eq('role_key', role ?? '').maybeSingle();
        group = GroupScope.detect(
          grouping: (meta?['Grouping'] ?? '').toString(),
          role: r,
          subDeptNames: await GroupScope.myDeptNames(),
        );
      } catch (_) {}
      scope = group != null
          ? {}
          : (r.contains('group') || r.contains('_dept') || _roleApprovalScope == 'church_department') && userDept.isNotEmpty
              ? {'department': userDept}
              : {};
    }
    // Dual-mode roles (Internal Affairs, Evangelism, Education, Administration,
    // Theology) get the Church-wide / Department only toggle here too.
    final dual = await _dualFor(duty, role);
    Map<String, String>? deptScope;
    if (dual != null) {
      if (DualMode.isTheology(r, dual.grouping)) {
        group = '신학부'; // across the locations
        scope = {};
      } else {
        group = null;
        scope = {}; // whole church
      }
      deptScope = {
        '@church_level': '1',
        if (dual.officialDeptId != null) 'official_dept_id': dual.officialDeptId! else if (userDept.isNotEmpty) 'department': userDept,
      };
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (c) => UniversalInterventionScreen(
        duty: duty,
        unitName: group != null ? GroupScope.label(group) : _getUnitNameByRole(role),
        buttonTitle: title,
        scope: scope,
        group: group,
        dualTitle: dual?.title,
        dualLabels: dual?.labels ?? const ("Church-wide", "Department only"),
        deptScope: deptScope,
      ),
    ));
  }

  /// The dashboard's Church / Department toggle for this role and duty
  /// (DualMode), with the role's grouping and official department.
  Future<({String title, (String, String) labels, String grouping, String? officialDeptId})?> _dualFor(String duty, String? role) async {
    final rk = (role ?? _simulatedRole ?? '').trim();
    if (rk.isEmpty) return null;
    String grouping = _roleGrouping;
    String? deptId;
    try {
      final meta = await _supabase.from('app_roles').select('"Grouping", official_dept_id').eq('role_key', rk).maybeSingle();
      grouping = (meta?['Grouping'] ?? grouping).toString();
      deptId = meta?['official_dept_id']?.toString();
    } catch (_) {}
    final t = DualMode.title(role: rk, grouping: grouping, dept: userDept, duty: duty);
    if (t == null) return null;
    return (title: t, labels: DualMode.labels(rk, grouping), grouping: grouping, officialDeptId: deptId);
  }

  String _getUnitNameByRole([String? role]) { 
    String r = (role ?? _simulatedRole)?.toLowerCase() ?? ""; 
    if (r.startsWith('church_') || r.startsWith('korean_worker_')) return "Church Executive";
    if (r.contains('cell')) return userCell.isNotEmpty ? userCell : "Cell Group"; 
    if (r.contains('team')) return userTeam.isNotEmpty ? userTeam : "Team"; 
    if (r.startsWith('dept_')) return userDept.isNotEmpty ? userDept : "Department"; 
    if (r.startsWith('sub_loc_')) return userSub.isNotEmpty ? userSub : "Sub-Location"; 
    if (r.startsWith('loc_')) return userLoc.isNotEmpty ? userLoc : "Location"; 
    if (r.contains('group') || r.contains('_dept') || _roleApprovalScope == 'church_department') {
      return userDept.isNotEmpty ? userDept : "Church Department";
    }
    return "Church Admin"; 
  }

  // --- SLIM, COMPACT ADMIN SWITCHER (REDUCED HEIGHT & SMALLER FONT) ---
  Widget _buildAdminSwitcher(double hPad) {
    const Color switcherBg = Color(0xFF7E57C2); 

    return Container(
      margin: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      // same height as the "Viewing as" card below it
      height: MediaQuery.of(context).size.width > 900 ? 40 : 34,
      decoration: BoxDecoration(
        color: AppPalette.bg(switcherBg),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: switcherBg.withValues(alpha: 0.25),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppPalette.bg(Colors.white.withValues(alpha: 0.2)),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.admin_panel_settings_rounded, size: 14, color: AppPalette.fg(Colors.white)),
          ),
          const SizedBox(width: 8),
          Text(
            "Admin Switcher",
            style: GoogleFonts.merriweather(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: AppPalette.fg(Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 14,
            width: 1,
            color: AppPalette.bg(Colors.white.withValues(alpha: 0.35)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _simulatedRole,
                isExpanded: true,
                isDense: true,
                dropdownColor: AppPalette.bg(Colors.white),
                icon: Icon(Icons.arrow_drop_down_rounded, color: AppPalette.fg(Colors.white), size: 20),
                selectedItemBuilder: (BuildContext context) {
                  final roles = _availableRoles.isNotEmpty
                      ? _availableRoles
                      : [{'role_key': _simulatedRole, 'display_name': _formatRoleToTitleCase(_simulatedRole)}];
                  return roles.map((r) {
                    final String name = r['display_name'] ?? _formatRoleToTitleCase(r['role_key']);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.merriweather(
                          fontSize: 11, // Reduced font size for compact display
                          fontWeight: FontWeight.bold,
                          color: AppPalette.fg(Colors.white),
                        ),
                      ),
                    );
                  }).toList();
                },
                items: _availableRoles.isNotEmpty
                    ? _availableRoles.map((r) {
                        final String name = r['display_name'] ?? _formatRoleToTitleCase(r['role_key']);
                        return DropdownMenuItem<String>(
                          value: r['role_key'],
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.merriweather(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.fg(const Color(0xFF4A148C)),
                            ),
                          ),
                        );
                      }).toList()
                    : [
                        DropdownMenuItem(
                          value: _simulatedRole,
                          child: Text(
                            _formatRoleToTitleCase(_simulatedRole),
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.merriweather(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.fg(const Color(0xFF4A148C)),
                            ),
                          ),
                        )
                      ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _simulatedRole = v;
                    _isLoading = true;
                  });
                  _fetchRolePermissions(v);
                  setState(() => _isLoading = false);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRoleToTitleCase(String? role) { 
    if (role == null || role.isEmpty) return ""; 
    return role.replaceAll('_', ' ').split(' ').map((word) => word.isEmpty ? "" : word[0].toUpperCase() + word.substring(1).toLowerCase()).join(' '); 
  }

  void _showMemberBioDialog() {
    showGeneralDialog(context: context, pageBuilder: (context, anim1, anim2) {
      String r = _simulatedRole?.toLowerCase() ?? "";
      bool isIASec = r == 'internal_affairs_dept_sec';
      bool isOtherSec = (r.contains('sec') || r.contains('secretary')) && 
                         r != 'internal_affairs_dept_gen_sec' && 
                         r != 'internal_affairs_dept_sec';

      return Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(Colors.white), 
          elevation: 0.5, 
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)), 
          centerTitle: true, 
          title: Text("Member bio", style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold))
        ),
        body: Padding(padding: const EdgeInsets.all(25), child: Column(children: [
          const SizedBox(height: 5),
          // Member profile: the directory, and the approval of the profile
          // changes proposed by cell leaders
          _compactActionBtn(Icons.person_pin_rounded, "Member profile", Colors.blue, () => _showMemberProfileMenu(context)),
          if (isIASec || r == 'admin') ...[
            _compactActionBtn(Icons.sync_lock_rounded, "Database master sync", Colors.red[900]!, () { 
              Navigator.push(context, MaterialPageRoute(builder: (c) => const MemberSyncTool())); 
            }),
            _compactActionBtn(Icons.upload_file_rounded, "Milestone bulk importer", Colors.indigo, () { 
              Navigator.push(context, MaterialPageRoute(builder: (c) => const MilestoneUploadScreen())); 
            }),
          ],
          if (isIASec || isOtherSec || r == 'admin') ...[
            _compactActionBtn(Icons.move_up_rounded, "Request member transfer", Colors.orange, () { 
              Navigator.push(context, MaterialPageRoute(builder: (c) => const TransferRequestForm())); 
            }),
          ],
          // One screen for approvals, roles and removal: roles with the
          // "Approve Accounts" permission (app_roles), inside their own area
          if (r == 'admin' || _dynamicAdminActions.contains('Approve Accounts'))
            _compactActionBtn(Icons.manage_accounts_rounded, "User management", Colors.green[800]!, () {
              Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminUserManagementScreen()));
            }),
        ]))
      );
    });
  }

  void _showMemberProfileMenu(BuildContext ctx) {
    showGeneralDialog(context: ctx, pageBuilder: (context, anim1, anim2) {
      return Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(Colors.white),
          elevation: 0.5,
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          centerTitle: true,
          title: Text("Member profile", style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        body: Padding(padding: const EdgeInsets.all(25), child: Column(children: [
          const SizedBox(height: 5),
          _compactActionBtn(Icons.person_search_rounded, "View member profile", Colors.blue, () {
            Navigator.push(context, MaterialPageRoute(builder: (c) => MemberDirectoryScreen(
              userRole: _simulatedRole!,
              userLoc: userLoc,
              userSub: userSub,
              userDept: userDept,
              userTeam: userTeam,
              userCell: userCell
            )));
          }),
          _compactActionBtn(Icons.fact_check_rounded, "Approve member profile changes", Colors.green[800]!, () {
            Navigator.push(context, MaterialPageRoute(builder: (c) => const MemberChangeApprovalsScreen()));
          }),
        ])),
      );
    });
  }

  void _showStrategicAnalysisDialog() {
    showGeneralDialog(context: context, pageBuilder: (context, anim1, anim2) {
      String r = _simulatedRole?.toLowerCase() ?? "";
      bool canSetTargets = r == 'admin' || r.contains('internal_affairs');

      return Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(Colors.white), 
          elevation: 0.5, 
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)), 
          centerTitle: true, 
          title: Text("Strategic analysis", style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold))
        ),
        body: Padding(padding: const EdgeInsets.all(25), child: Column(children: [
          const SizedBox(height: 5),
          if (canSetTargets)
            _compactActionBtn(Icons.track_changes_rounded, "Set unit targets", Colors.redAccent, () { 
              Navigator.push(context, MaterialPageRoute(
                builder: (c) => TargetSetterScreen(
                  allowedDuties: _dynamicDuties,
                  userRole: _simulatedRole!,
                  userLoc: userLoc,
                  userSub: userSub,
                  userDept: userDept,
                )
              )); 
            }),
            
          _compactActionBtn(Icons.trending_up_rounded, "Track growth", Colors.blue, () { 
            Navigator.push(context, MaterialPageRoute(builder: (c) => UnitGrowthTrackerScreen(
              userRole: _simulatedRole ?? widget.userRole, 
              userLoc: userLoc, 
              userSub: userSub, 
              userDept: userDept, 
              userTeam: userTeam, 
              userCell: userCell,
            )));
          }),
          
          _compactActionBtn(Icons.assignment_turned_in_rounded, "Accountability tasks", Colors.teal[800]!, () { 
            Navigator.push(context, MaterialPageRoute(builder: (c) => const TaskManagerScreen())); 
          }),
          
          _compactActionBtn(Icons.assessment_rounded, "Monthly performance report", Colors.purple, () { 
            Navigator.push(context, MaterialPageRoute(builder: (c) => const MonthlyExecutiveReport())); 
          }),
        ]))
      );
    });
  }

  /// BB File: location evangelism secretaries enter, everyone else sees the
  /// sheets compiled for their own unit.
  void _openBbFile() {
    final canEdit = _canUserEnterData("BB File");
    Navigator.push(context, MaterialPageRoute(builder: (c) => BbWorkspaceScreen(
      canEdit: canEdit,
      userRole: _simulatedRole ?? '',
    )));
  }

  /// Evangelism Results: the Summary sheet's tables with a filter side bar.
  void _openEvangelismResults() {
    Navigator.push(context, MaterialPageRoute(builder: (c) => EvangelismResultsScreen(
      onOpenClassic: () => _goToCorrectDashboard("Evangelism Results"),
    )));
  }

  void _showEvangelismSubMenu() {
    showGeneralDialog(context: context, pageBuilder: (context, anim1, anim2) {
      return Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        appBar: AppBar(backgroundColor: AppPalette.bg(Colors.white), elevation: 0.5, leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)), centerTitle: true, title: Text("Evangelism management", style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold))),
        body: Padding(padding: const EdgeInsets.all(25), child: Column(children: [
          _compactActionBtn(Icons.fact_check_rounded, "Evangelism participation", Colors.blue, () { 
            _showDutyActionDialog("Evangelism"); 
          }),
          _compactActionBtn(Icons.folder_shared_outlined, "BB File", Colors.orange[800]!, _openBbFile),
          _compactActionBtn(Icons.gavel_rounded, "Evangelism policies, standards & goals", Colors.teal[800]!, () {
            DutyPanelScreen.open(context, "Evangelism", role: selectedRole == 'admin' ? _simulatedRole : null);
          }),
          _compactActionBtn(Icons.analytics_outlined, "Evangelism results", Colors.purple, _openEvangelismResults),
        ]))
      );
    });
  }

  Widget _buildCorrectionNotification(double hPad) => Container(
    margin: EdgeInsets.fromLTRB(hPad, 15, hPad, 0), 
    padding: const EdgeInsets.all(18), 
    decoration: BoxDecoration(color: AppPalette.bg(Colors.red[50]), borderRadius: BorderRadius.circular(15), border: Border.all(color: AppPalette.line(Colors.red.withValues(alpha: 0.3)))), 
    child: Row(children: [
      Icon(Icons.report_gmailerrorred_rounded, color: AppPalette.fg(Colors.red), size: 30), 
      const SizedBox(width: 15), 
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Report flagged", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.red), fontSize: 13)), 
        const SizedBox(height: 2), 
        Text(_latestCorrectionNote, style: GoogleFonts.merriweather(fontSize: 14, color: AppPalette.fg(Colors.black87)))
      ]))
    ])
  );
}