// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- ALL IMPORTS ACTIVELY USED ---
import 'cell_status_screen.dart';
import 'compilation_screen.dart';
import 'member_directory_screen.dart';
import 'entry_form_screen.dart';
import '../admin_tools/approval_cockpit.dart';
import 'admin/transfer_request_form.dart';
import 'admin/approval_inbox.dart';
import 'admin/milestone_upload.dart';
import 'admin/target_setter_screen.dart';
import 'admin/monthly_executive_report.dart';
import 'admin/universal_intervention_screen.dart';
import '../admin_tools/member_sync_tool.dart';
import '../admin_tools/task_manager_screen.dart';
import 'admin/unit_growth_tracker_screen.dart';

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
  List<String> _dynamicAdminActions = [];
  Map<String, String> _interventionLabels = {}; 
  bool _canEnterDataFromDB = false;
  String? _roleApprovalScope;
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
        primaryActions = List<String>.from(res['allowed_admin_actions'] ?? []);
        canEnter = res['can_enter_data'] ?? false;
        scope = res['approval_scope'];

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
      return ["Enter new offering data", "Open offering dashboard", _getInterventionLabel("Offering Status")];
    }
    if (_simulatedRole == 'loc_ia_mgr') {
      return ["Member Bio", "Service Attendance Status", "Cell Group Service", "Visitations and Counselling"];
    }

    List<String> buttons = [];
    if (_dynamicAdminActions.contains('View Member Profiles') || _dynamicAdminActions.contains('Member Bio')) buttons.add("Member Bio");
    for (var d in _dynamicDuties) {
      String label = d == 'Evangelism Part' ? 'Evangelism' : d;
      if (!label.toLowerCase().contains('growth')) buttons.add(label);
    }
    if (_dynamicAdminActions.contains('Strategic Analysis')) buttons.add("Strategic Analysis");
    if (_dynamicAdminActions.contains('Notification Center')) buttons.add("Notification Center");
    return buttons.toSet().toList();
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width; bool isDesktop = width > 900;
    final Color pPurple = const Color(0xFF4A148C);
    final allButtons = _getMainGridButtons();
    double hPadding = isDesktop ? width * 0.15 : 20;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFE),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF4A148C), size: 22), onPressed: () => Navigator.pop(context)),
        title: Text("Management reports", style: GoogleFonts.merriweather(color: pPurple, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator(color: Color(0xFF4A148C))) : Column(children: [
        if (selectedRole == 'admin') _buildAdminSwitcher(hPadding),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 10), 
          child: Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12), 
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: pPurple.withValues(alpha: 0.1), width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]), 
            child: Text(
              _secondaryRole != null && _secondaryRole!.isNotEmpty
                ? "Viewing as: ${_formatRoleToTitleCase(_simulatedRole)} + ${_formatRoleToTitleCase(_secondaryRole)}"
                : "Viewing as: ${_formatRoleToTitleCase(_simulatedRole)}", 
              textAlign: TextAlign.center, 
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: isDesktop ? 18 : 14, color: pPurple)
            )
          )
        ),
        if (_flaggedCount > 0) _buildCorrectionNotification(hPadding),
        const SizedBox(height: 10),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(hPadding, 0, hPadding, 40), 
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isDesktop ? 3 : 1, 
              mainAxisSpacing: 6,
              crossAxisSpacing: 15, 
              childAspectRatio: isDesktop ? 8.5 : 12.0 
            ), 
            itemCount: allButtons.length, 
            itemBuilder: (context, index) {
              String title = allButtons[index];
              bool isPrimary = ["Member Bio", "Strategic Analysis", "Notification Center"].contains(title);
              return Container(
                decoration: BoxDecoration(color: isPrimary ? pPurple : Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black.withValues(alpha: 0.08)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4))]), 
                child: InkWell(borderRadius: BorderRadius.circular(15), onTap: () => _handleSelection(title), child: Center(child: Text(title, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold, color: isPrimary ? Colors.white : Colors.black87))))
              );
            }
          )
        ),
      ]),
    );
  }

  void _handleSelection(String title) {
    if (title == "Enter new offering data") _handleExcelUpload("Offering Status");
    else if (title == "Open offering dashboard") _goToCorrectDashboard("Offering Status");
    else if (title == _getInterventionLabel("Offering Status")) {
       Navigator.push(context, MaterialPageRoute(builder: (c) => UniversalInterventionScreen(duty: "Offering Status", unitName: _getUnitNameByRole(), buttonTitle: title)));
    }
    else if (title == "Member Bio") _showMemberBioDialog();
    else if (title == "Strategic Analysis") _showStrategicAnalysisDialog();
    else if (title == "Notification Center") Navigator.push(context, MaterialPageRoute(builder: (c) => ApprovalInbox(userRole: _simulatedRole!)));
    else if (title == "Evangelism") _showEvangelismSubMenu();
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
          backgroundColor: Colors.white,
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
                        color: const Color(0xFF4A148C).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.edit_calendar_rounded, color: Color(0xFF4A148C), size: 22),
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
                              color: const Color(0xFF4A148C),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Editable within the last 5 days",
                            style: GoogleFonts.merriweather(fontSize: 11, color: Colors.grey.shade600),
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
                            color: diff == 0 
                                ? const Color(0xFF4A148C).withValues(alpha: 0.06) 
                                : const Color(0xFFFBFBFE),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: diff == 0 
                                  ? const Color(0xFF4A148C).withValues(alpha: 0.3) 
                                  : Colors.grey.shade200,
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
                                    color: diff == 0 ? const Color(0xFF4A148C) : Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    formattedDate,
                                    style: GoogleFonts.merriweather(
                                      fontSize: 12.5,
                                      fontWeight: diff == 0 ? FontWeight.bold : FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  badgeLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: badgeColor,
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
                        color: Colors.grey.shade700,
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

  void _showDutyActionDialog(String duty) async {
    if (_interventionLabels.isEmpty) {
      await _fetchDutyConfig();
    }

    bool canEdit = _canUserEnterData(duty);
    String interventionLabel = _getInterventionLabel(duty);

    if (!mounted) return;

    showGeneralDialog(context: context, pageBuilder: (context, anim1, anim2) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBFBFE),
        appBar: AppBar(
          backgroundColor: Colors.white, 
          elevation: 0.5, 
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)), 
          centerTitle: true, 
          title: Text(duty, style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold))
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(25), 
          child: Column(children: [
            const SizedBox(height: 5),
            if (canEdit) ...[
              _compactActionBtn(Icons.edit_note_rounded, "Enter new report", Colors.purple, () async { 
                Navigator.pop(context); 
                await _nav(duty, "entry", selectedDate: DateTime.now()); 
                if (mounted) _showDutyActionDialog(duty); 
              }),
              _compactActionBtn(Icons.history_rounded, "Edit previous report", Colors.orange[800]!, () async { 
                Navigator.pop(context); 
                final picked = await _pickNiceDate();
                if (picked != null) {
                  await _nav(duty, "edit", selectedDate: picked);
                }
                if (mounted) _showDutyActionDialog(duty); 
              }),
            ],
            _compactActionBtn(Icons.dashboard_customize_rounded, "Open dashboard", Colors.teal[700]!, () { 
              Navigator.pop(context); 
              _goToCorrectDashboard(duty); 
            }),
            _compactActionBtn(Icons.person_search_rounded, interventionLabel, Colors.blue[800]!, () { 
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(
                builder: (c) => UniversalInterventionScreen(
                  duty: duty, 
                  unitName: _getUnitNameByRole(), 
                  buttonTitle: interventionLabel
                )
              )); 
            }),
            if (!_simulatedRole!.contains('cell')) 
              _compactActionBtn(Icons.verified_user_rounded, "Approval cockpit", Colors.green[800]!, () { 
                Navigator.pop(context); 
                Navigator.push(context, MaterialPageRoute(
                  builder: (c) => ApprovalCockpit(
                    role: _simulatedRole!, 
                    unitName: _getUnitNameByRole(), 
                    selectedDuty: duty
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
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.15), width: 1.2), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4)]), 
    child: InkWell(onTap: t, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 15), child: Row(children: [Icon(i, color: c, size: 16), const SizedBox(width: 12), Expanded(child: Text(l, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold))), const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.black26)])))
  );

  void _handleExcelUpload(String duty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Offering excel upload module initialized..."))); }
  
  void _goToCorrectDashboard(String duty) { 
    if (_simulatedRole!.toLowerCase().contains('cell')) {
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
          role: _simulatedRole!, 
          userUnit: _getUnitNameByRole(), 
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
        userRole: _simulatedRole,
        initialMode: mode,
        selectedDate: dateToUse,
      )
    )); 
  }

  String _getUnitNameByRole() { 
    String r = _simulatedRole?.toLowerCase() ?? ""; 
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
      constraints: const BoxConstraints(minHeight: 32, maxHeight: 35),
      decoration: BoxDecoration(
        color: switcherBg,
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
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.admin_panel_settings_rounded, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text(
            "Admin Switcher",
            style: GoogleFonts.merriweather(
              fontSize: 11, // Reduced font size
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 14,
            width: 1,
            color: Colors.white.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _simulatedRole,
                isExpanded: true,
                isDense: true,
                dropdownColor: Colors.white,
                icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 20),
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
                          color: Colors.white,
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
                              color: const Color(0xFF4A148C),
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
                              color: const Color(0xFF4A148C),
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
        backgroundColor: const Color(0xFFFBFBFE),
        appBar: AppBar(
          backgroundColor: Colors.white, 
          elevation: 0.5, 
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)), 
          centerTitle: true, 
          title: Text("Member bio", style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold))
        ),
        body: Padding(padding: const EdgeInsets.all(25), child: Column(children: [
          const SizedBox(height: 5),
          _compactActionBtn(Icons.person_pin_rounded, "View member profiles", Colors.blue, () { 
            Navigator.pop(context); 
            Navigator.push(context, MaterialPageRoute(builder: (c) => MemberDirectoryScreen(
              userRole: _simulatedRole!, 
              userLoc: userLoc, 
              userSub: userSub, 
              userDept: userDept, 
              userTeam: userTeam, 
              userCell: userCell
            ))); 
          }),
          if (isIASec || r == 'admin') ...[
            _compactActionBtn(Icons.sync_lock_rounded, "Database master sync", Colors.red[900]!, () { 
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(builder: (c) => const MemberSyncTool())); 
            }),
            _compactActionBtn(Icons.upload_file_rounded, "Milestone bulk importer", Colors.indigo, () { 
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(builder: (c) => const MilestoneUploadScreen())); 
            }),
          ],
          if (isIASec || isOtherSec || r == 'admin') ...[
            _compactActionBtn(Icons.move_up_rounded, "Request member transfer", Colors.orange, () { 
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(builder: (c) => const TransferRequestForm())); 
            }),
          ],
        ]))
      );
    });
  }

  void _showStrategicAnalysisDialog() {
    showGeneralDialog(context: context, pageBuilder: (context, anim1, anim2) {
      String r = _simulatedRole?.toLowerCase() ?? "";
      bool canSetTargets = r == 'admin' || r.contains('internal_affairs');

      return Scaffold(
        backgroundColor: const Color(0xFFFBFBFE),
        appBar: AppBar(
          backgroundColor: Colors.white, 
          elevation: 0.5, 
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)), 
          centerTitle: true, 
          title: Text("Strategic analysis", style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold))
        ),
        body: Padding(padding: const EdgeInsets.all(25), child: Column(children: [
          const SizedBox(height: 5),
          if (canSetTargets)
            _compactActionBtn(Icons.track_changes_rounded, "Set unit targets", Colors.redAccent, () { 
              Navigator.pop(context); 
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
            Navigator.pop(context); 
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
            Navigator.pop(context); 
            Navigator.push(context, MaterialPageRoute(builder: (c) => const TaskManagerScreen())); 
          }),
          
          _compactActionBtn(Icons.assessment_rounded, "Monthly performance report", Colors.purple, () { 
            Navigator.pop(context); 
            Navigator.push(context, MaterialPageRoute(builder: (c) => const MonthlyExecutiveReport())); 
          }),
        ]))
      );
    });
  }

  void _showEvangelismSubMenu() {
    showGeneralDialog(context: context, pageBuilder: (context, anim1, anim2) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBFBFE),
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0.5, leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)), centerTitle: true, title: Text("Evangelism management", style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold))),
        body: Padding(padding: const EdgeInsets.all(25), child: Column(children: [
          _compactActionBtn(Icons.fact_check_rounded, "Evangelism participation", Colors.blue, () { 
            Navigator.pop(context); 
            _showDutyActionDialog("Evangelism"); 
          }),
          _compactActionBtn(Icons.folder_shared_outlined, "BB file (Students)", Colors.orange[800]!, () { 
            Navigator.pop(context); 
            if (_canUserEnterData("BB File")) {
              _nav("BB File", "entry", selectedDate: DateTime.now());
            } else {
              _goToCorrectDashboard("BB File");
            }
          }),
          _compactActionBtn(Icons.analytics_outlined, "Evangelism results", Colors.purple, () { 
            Navigator.pop(context); 
            _goToCorrectDashboard("Evangelism Results"); 
          }),
        ]))
      );
    });
  }

  Widget _buildCorrectionNotification(double hPad) => Container(
    margin: EdgeInsets.fromLTRB(hPad, 15, hPad, 0), 
    padding: const EdgeInsets.all(18), 
    decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.red.withValues(alpha: 0.3))), 
    child: Row(children: [
      const Icon(Icons.report_gmailerrorred_rounded, color: Colors.red, size: 30), 
      const SizedBox(width: 15), 
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Report flagged", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: Colors.red, fontSize: 13)), 
        const SizedBox(height: 2), 
        Text(_latestCorrectionNote, style: GoogleFonts.merriweather(fontSize: 14, color: Colors.black87))
      ]))
    ])
  );
}