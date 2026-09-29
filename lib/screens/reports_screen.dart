// ignore_for_file: curly_braces_in_flow_control_structures
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
        setState(() { 
          selectedRole = data['role']; 
          _simulatedRole = data['role']; 
          _secondaryRole = data['secondary_role']; 
          userLoc = data['location'] ?? ""; 
          userSub = data['sub_location'] ?? ""; 
          userDept = data['department'] ?? ""; 
          userTeam = data['team'] ?? ""; 
          userCell = data['cell_group'] ?? ""; 
        });
        await _fetchRolePermissions(_simulatedRole!); 
        await _fetchDutyConfig(); 
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
    } catch (e) { debugPrint("User Error: $e"); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  // Dynamically fetches labels directly from Supabase 'app_duty_config'
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

  // Dynamic label resolver with case-insensitive matching & smart fallback
  String _getInterventionLabel(String duty) {
    String cleanDuty = duty.trim();

    // 1. Direct match
    if (_interventionLabels.containsKey(cleanDuty)) {
      return _interventionLabels[cleanDuty]!;
    }

    // 2. Evangelism / Evangelism Part cross-match
    if (cleanDuty == "Evangelism Part" && _interventionLabels.containsKey("Evangelism")) {
      return _interventionLabels["Evangelism"]!;
    }
    if (cleanDuty == "Evangelism" && _interventionLabels.containsKey("Evangelism Part")) {
      return _interventionLabels["Evangelism Part"]!;
    }

    // 3. Case-insensitive search across dynamically loaded database keys
    for (var entry in _interventionLabels.entries) {
      if (entry.key.toLowerCase() == cleanDuty.toLowerCase()) {
        return entry.value;
      }
    }

    // 4. Dynamic fallback without hardcoding
    return "$cleanDuty absentees";
  }

  Future<void> _fetchRolePermissions(String roleKey) async {
    try {
      final res = await _supabase.from('app_roles').select().eq('role_key', roleKey).maybeSingle();
      
      List<String> primaryDuties = [];
      List<String> primaryActions = [];
      
      if (res != null) {
        primaryDuties = List<String>.from(res['allowed_duties'] ?? []);
        primaryActions = List<String>.from(res['allowed_admin_actions'] ?? []);
      }

      if (_secondaryRole != null && _secondaryRole!.isNotEmpty) {
        final secRes = await _supabase.from('app_roles').select().eq('role_key', _secondaryRole!).maybeSingle();
        if (secRes != null) {
          final secDuties = List<String>.from(secRes['allowed_duties'] ?? []);
          final secActions = List<String>.from(secRes['allowed_admin_actions'] ?? []);
          primaryDuties.addAll(secDuties);
          primaryActions.addAll(secActions);
        }
      }
      if (roleKey == 'internal_affairs_dept_sec') {
        primaryActions.addAll([
          'Member Bio',
          'Notification Center',
          'Strategic Analysis',
          'Request member transfer',
          'Milestone bulk importer',
          'Database master sync',
          'View Member Profiles'
        ]);
      }

      if (mounted) {
        setState(() {
          _dynamicDuties = primaryDuties.toSet().toList();
          _dynamicAdminActions = primaryActions.toSet().toList();
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

  bool _canUserEnterData(String duty) {
    String r = _simulatedRole?.toLowerCase() ?? ""; 
    String sec = _secondaryRole?.toLowerCase() ?? "";

    if (r == 'admin') return true;

    bool hasTeamSec = r.contains('team_sec') || sec.contains('team_sec');

    if (r.contains('cell_leader')) {
      List<String> cellDuties = ['Service Attendance Status', 'Cell Group Service', 'Evangelism', 'Morning Light', 'All Saints Education', 'Visitations and Counselling'];
      return cellDuties.contains(duty);
    }

    if (r.contains('team_leader') || r.contains('assistant_team') || hasTeamSec) {
      return (duty == 'Workers Education' || duty == 'Workers Daily Participation');
    }

    if (r.contains('sec') || r.contains('secretary') || r.contains('manager')) {
      if (!hasTeamSec) return false;
    }

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

  List<String> _getAllowedTargetDuties(String role) {
    String r = role.toLowerCase();
    if (r == 'admin' || r == 'internal_affairs_dept_leader') {
      return [
        'Service Attendance Status', 'Cell Group Service', 'Offering Status',
        'Evangelism', 'Morning Light', 'All Saints Education',
        'Visitations and Counselling', 'Workers Education', 'Workers Daily Participation'
      ];
    }
    if (r == 'edu_dept_sec' || r == 'edu_dept_leader') {
      return ['Workers Education', 'All Saints Education'];
    }
    if (r == 'ia_maintenance_mgr') {
      return ['Service Attendance Status', 'Visitations and Counselling'];
    }
    if (r == 'ia_mgr_1' || r == 'ia_mgr_2') {
      return ['Cell Group Service', 'Workers Daily Participation'];
    }
    if (r == 'evang_dept_sec' || r == 'evang_dept_leader') {
      return ['Evangelism'];
    }
    if (r == 'fin_dept_sec' || r == 'fin_dept_leader') {
      return ['Offering Status'];
    }
    return [];
  }

  bool _canSetTargets(String role) {
    return _getAllowedTargetDuties(role).isNotEmpty;
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
            Navigator.push(context, MaterialPageRoute(builder: (c) => MemberDirectoryScreen(userRole: _simulatedRole!, userLoc: userLoc, userSub: userSub, userDept: userDept, userTeam: userTeam, userCell: userCell))); 
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
      bool canSetTargets = _canSetTargets(r);

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
                  allowedDuties: _getAllowedTargetDuties(_simulatedRole!),
                  userRole: _simulatedRole!,
                  userLoc: userLoc,
                  userSub: userSub,
                  userDept: userDept,
                )
              )); 
            }),
            
          _compactActionBtn(Icons.trending_up_rounded, "Track growth", Colors.blue, () { 
            Navigator.pop(context); 
            _showGrowthTrackDialog();
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

  void _showGrowthTrackDialog() { 
    Navigator.push(
      context, 
      MaterialPageRoute(
        builder: (c) => UnitGrowthTrackerScreen(
          userRole: _simulatedRole ?? widget.userRole, 
          userLoc: userLoc, 
          userSub: userSub, 
          userDept: userDept, 
          userTeam: userTeam, 
          userCell: userCell,
        ),
      ),
    );
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
            if (_simulatedRole!.contains('leader')) _nav("BB File", "entry"); 
            else _goToCorrectDashboard("BB File");
          }),
          _compactActionBtn(Icons.analytics_outlined, "Evangelism results", Colors.purple, () { 
            Navigator.pop(context); 
            _goToCorrectDashboard("Evangelism Results"); 
          }),
        ]))
      );
    });
  }

  // --- UPDATED DIALOG: Awaits config if needed & uses dynamic labels ---
  void _showDutyActionDialog(String duty) async {
    // If labels haven't finished loading yet, await them so it never falls back
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
              _compactActionBtn(Icons.edit_note_rounded, "Enter new report", Colors.purple, () { 
                Navigator.pop(context); 
                _nav(duty, "entry"); 
              }),
              _compactActionBtn(Icons.history_rounded, "Edit previous report", Colors.orange[800]!, () { 
                Navigator.pop(context); 
                _nav(duty, "edit"); 
              }),
            ],
            _compactActionBtn(Icons.dashboard_customize_rounded, "Open dashboard", Colors.teal[700]!, () { 
              Navigator.pop(context); 
              _goToCorrectDashboard(duty); 
            }),
            // Custom dynamic label fetched from Supabase app_duty_config
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
      Navigator.push(context, MaterialPageRoute(builder: (c) => CellStatusScreen(sheetName: duty, cellName: userCell, location: userLoc, subLocation: userSub, dept: userDept, team: userTeam, initialMode: "dashboard"))); 
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (c) => CompilationEngine(role: _simulatedRole!, userUnit: _getUnitNameByRole(), selectedDuty: duty, loc: userLoc, sub: userSub, dept: userDept, team: userTeam))); 
    }
  }

  void _nav(String duty, String mode) async { 
    bool? wasSaved; 
    if (_simulatedRole!.contains('cell')) {
      wasSaved = await Navigator.push(context, MaterialPageRoute(builder: (c) => CellStatusScreen(sheetName: duty, cellName: userCell, location: userLoc, subLocation: userSub, dept: userDept, team: userTeam, initialMode: mode))); 
    } else {
      wasSaved = await Navigator.push(context, MaterialPageRoute(builder: (c) => EntryFormScreen(sheetName: duty, cellName: userCell, location: userLoc, subLocation: userSub, dept: userDept, team: userTeam))); 
    }
    if (wasSaved == true && mounted) _goToCorrectDashboard(duty); 
  }

  String _getUnitNameByRole() { 
    String r = _simulatedRole?.toLowerCase() ?? ""; 
    if (r.startsWith('church_') || r.startsWith('korean_worker_')) return "Church Executive";
    if (userLoc.trim().toLowerCase() == 'church') return userDept.isNotEmpty ? userDept : "24 Departments";
    if (r.contains('cell')) return userCell; 
    if (r.contains('team')) return userTeam; 
    if (r.contains('dept')) return userDept; 
    if (r.contains('sub_loc')) return userSub; 
    if (r.contains('loc') || r.contains('group')) return userLoc; 
    return "Church Admin"; 
  }

  Widget _buildAdminSwitcher(double hPad) => Container(
    margin: EdgeInsets.fromLTRB(hPad, 0, hPad, 15), 
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5), 
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(15)), 
    child: Row(children: [
      const Icon(Icons.admin_panel_settings, size: 18), 
      const SizedBox(width: 10), 
      Text("Admin Switcher", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.w900)), 
      const Spacer(), 
      DropdownButton<String>(
        value: _simulatedRole, 
        underline: const SizedBox(), 
        items: {
          'admin', 'loc_leader', 'loc_gen_sec', 'loc_sec', 'loc_treasurer', 'loc_ia_mgr', 'loc_edu_mgr', 'loc_evangelism_mgr',
          'sub_loc_leader', 'sub_loc_sec', 
          'dept_leader', 'dept_gen_sec', 'dept_sec', 
          'team_leader', 'team_sec', 'cell_leader',
          'internal_affairs_dept_leader', 'internal_affairs_dept_gen_sec', 'internal_affairs_dept_sec', 'ia_maintenance_mgr', 'ia_mgr_1', 'ia_mgr_2',
          'edu_dept_leader', 'edu_dept_gen_sec', 'edu_dept_sec',
          'fin_dept_leader', 'fin_dept_gen_sec', 'fin_dept_sec',
          'evang_dept_leader', 'evang_dept_gen_sec', 'evang_dept_sec',
          'admin_dept_leader', 'admin_dept_sec',
          'church_head_instructor', 'church_secretary', 'korean_worker_1', 'korean_worker_2',
        }.map((r) => DropdownMenuItem(
          value: r, 
          child: Text(_formatRoleToTitleCase(r), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))
        )).toList(), 
        onChanged: (v) { 
          setState(() { 
            _simulatedRole = v; 
            _isLoading = true; 
          }); 
          _fetchRolePermissions(v!); 
          setState(() => _isLoading = false); 
        }
      )
    ])
  );

  String _formatRoleToTitleCase(String? role) { 
    if (role == null || role.isEmpty) return ""; 
    return role.replaceAll('_', ' ').split(' ').map((word) => word.isEmpty ? "" : word[0].toUpperCase() + word.substring(1).toLowerCase()).join(' '); 
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