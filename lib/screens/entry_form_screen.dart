// ignore_for_file: curly_braces_in_flow_control_structures, avoid_print
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:master_admin/entry_modules/evidence_gallery_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

// --- ALL MODULES IMPORTED ---
import '../entry_modules/service_attendance_entry.dart';
import '../entry_modules/cell_service_entry.dart';
import '../entry_modules/evangelism_entry.dart';
import '../entry_modules/morning_light_entry.dart';
import '../entry_modules/all_saints_education_entry.dart';
import '../entry_modules/visitations_entry.dart';
import '../entry_modules/workers_education_entry.dart';
import '../entry_modules/daily_participation_entry.dart';
import '../entry_modules/bb_file_entry.dart';
import '../core/compilation_rules.dart';
import 'package:master_admin/core/app_palette.dart';

class EntryFormScreen extends StatefulWidget {
  final String sheetName, cellName, location, subLocation, dept, team;
  final DateTime? selectedDate;
  final String? initialMode;
  final String? userRole;

  const EntryFormScreen({
    super.key,
    required this.sheetName,
    required this.cellName,
    required this.location,
    required this.subLocation,
    required this.dept,
    required this.team,
    this.selectedDate,
    this.initialMode,
    this.userRole,
  });

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final supabase = Supabase.instance.client;
  late DateTime selectedDate;
  List<dynamic> members = [];
  Map<String, Map<String, dynamic>> reportData = {};
  Map<String, List<String>> dynamicOptions = {};
  bool isLoading = true;
  int groupEvidenceCount = 0;
  final Color pPurple = const Color(0xFF4A148C);

  // --- DAY SELECTOR STATE ---
  String _selectedDay = 'Wednesday';

  // --- EXCEL PRO STATE ---
  String _saveStatus = "Save";
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  // --- ROLE METADATA & DUAL MODE ---
  Map<String, dynamic>? _roleMetadata;
  bool _dualModeIsChurch = false;

  bool get _isBB => widget.sheetName == "BB File";
  bool get _isMorningLight => widget.sheetName == 'Morning Light';
  bool get _isWorkersEducation => widget.sheetName == 'Workers Education';
  bool get _isWorkersParticipation => widget.sheetName == 'Workers Daily Participation';
  bool get _isEvangelism => widget.sheetName == 'Evangelism' || widget.sheetName == 'Evangelism Part';

  bool get _hasDayToggle =>
      widget.sheetName == 'Service Attendance Status' ||
      widget.sheetName == 'All Saints Education' ||
      _isMorningLight ||
      _isWorkersEducation ||
      _isWorkersParticipation ||
      _isEvangelism;

  @override
  void initState() {
    super.initState();
    selectedDate = widget.selectedDate ?? DateTime.now();
    _dualModeIsChurch = widget.initialMode?.toLowerCase() == 'church';

    _determineDefaultDay(selectedDate);
    _initRoleAndData();
  }

  void _determineDefaultDay(DateTime dt) {
    if (_isMorningLight) {
      if (dt.weekday == DateTime.tuesday) _selectedDay = 'Tue';
      else if (dt.weekday == DateTime.thursday) _selectedDay = 'Thu';
      else if (dt.weekday == DateTime.friday) _selectedDay = 'Fri';
      else _selectedDay = 'Mon';
    } else if (_isWorkersEducation || _isEvangelism) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      _selectedDay = weekdays[dt.weekday - 1];
    } else if (_isWorkersParticipation) {
      if (dt.weekday == DateTime.tuesday) _selectedDay = 'Tue';
      else if (dt.weekday == DateTime.thursday) _selectedDay = 'Thu';
      else if (dt.weekday == DateTime.friday) _selectedDay = 'Fri';
      else if (dt.weekday == DateTime.saturday) _selectedDay = 'Sat';
      else _selectedDay = 'Mon';
    } else {
      if (dt.weekday == DateTime.monday ||
          dt.weekday == DateTime.tuesday ||
          dt.weekday == DateTime.wednesday) {
        _selectedDay = 'Wednesday';
      } else {
        _selectedDay = 'Sunday';
      }
    }
  }

  Future<void> _initRoleAndData() async {
    if (widget.userRole != null && widget.userRole!.isNotEmpty) {
      try {
        final res = await supabase
            .from('app_roles')
            .select('role_key, approval_scope, display_name_ko, "Grouping", official_dept_id')
            .eq('role_key', widget.userRole!)
            .maybeSingle();
        _roleMetadata = res;
      } catch (e) {
        debugPrint("Error fetching role metadata: $e");
      }
    }
    await _loadInitialData();
  }

  bool get _isInternalAffairs {
    final grouping = (_roleMetadata?['Grouping'] ?? '').toString();
    final role = (widget.userRole ?? '').toLowerCase();
    final d = widget.dept.trim().toLowerCase();
    return role.contains('internal_affairs') ||
        role.startsWith('ia_') ||
        d.contains('내무') ||
        grouping.startsWith('24-Dept 3');
  }

  bool get _isEvangelismDept {
    final r = (widget.userRole ?? '').toLowerCase();
    final d = widget.dept.trim().toLowerCase();
    final grouping = (_roleMetadata?['Grouping'] ?? '').toString();
    return (r.contains('evang_dept') || d.contains('전도') || grouping.startsWith('24-Dept 5')) &&
           !r.contains('loc_evang');
  }

  bool get _isEducationDept {
    final r = (widget.userRole ?? '').toLowerCase();
    final d = widget.dept.trim().toLowerCase();
    final grouping = (_roleMetadata?['Grouping'] ?? '').toString();
    return (r.contains('edu_dept') || d.contains('교육') || grouping.startsWith('24-Dept 4')) &&
           !r.contains('loc_edu');
  }

  bool get _isAdministrationDept {
    final r = (widget.userRole ?? '').toLowerCase();
    final d = widget.dept.trim().toLowerCase();
    final grouping = (_roleMetadata?['Grouping'] ?? '').toString();
    return (r.contains('admin_dept') || d.contains('행정서무') || 
            grouping.startsWith('24-Dept 11') || grouping.startsWith('24-Dept 12') || grouping.startsWith('24-Dept 13')) &&
           r != 'admin';
  }

  bool get _hasDualModeForCurrentDuty {
    final d = widget.sheetName.trim();
    if (_isInternalAffairs) return true;

    if (_isEvangelismDept && (d == 'Evangelism' || d == 'Evangelism Part' || d == 'BB File')) {
      return true;
    }
    if (_isEducationDept && (d == 'All Saints Education' || d == 'Workers Education')) {
      return true;
    }
    if (_isAdministrationDept && d == 'Service Attendance Status') {
      return true;
    }
    return false;
  }

  int get _pendingCount {
    if (members.isEmpty) return 0;
    int filled = reportData.values.where((v) => v.isNotEmpty && v.values.any((val) => val != null && val != "")).length;
    return members.length - filled;
  }

  bool get _isServiceSheet => widget.sheetName == 'Service Attendance Status';

  /// Pending count that follows the stage being filled. For Service
  /// Attendance: pre-attendance -> real-time -> make-up, and make-up only
  /// counts members who were ABSENT in real time (those who attended don't
  /// need a make-up). Other duties: members with nothing entered yet.
  ({String label, int count, String detail}) get _pendingInfo {
    if (members.isEmpty || !_isServiceSheet) {
      return (label: "Pending entries", count: _pendingCount, detail: "");
    }
    String v(String id, String key) => (reportData[id]?[key] ?? '').toString().trim();
    final ids = members.map((m) => m['id'].toString()).toList();
    final int prePending = ids.where((id) => v(id, 'attendance_pre').isEmpty).length;
    final int rtPending = ids.where((id) => v(id, 'attendance_realtime').isEmpty).length;
    final absent = ids.where((id) {
      final s = v(id, 'attendance_realtime');
      return s.isNotEmpty && CompStatus.isNegative(s);
    }).toList();
    final int muPending = absent.where((id) => v(id, 'attendance_makeup').isEmpty).length;
    final bool rtStarted = rtPending < ids.length;
    final bool muStarted = ids.any((id) => v(id, 'attendance_makeup').isNotEmpty);
    final String detail =
        "Pre-attendance: $prePending pending  ·  Real-time: $rtPending pending  ·  Make-up: $muPending of ${absent.length} absentees pending";

    if (muStarted || (rtStarted && rtPending == 0)) {
      return (label: "Pending make-up", count: muPending, detail: detail);
    }
    if (rtStarted) return (label: "Pending real-time", count: rtPending, detail: detail);
    return (label: "Pending pre-attendance", count: prePending, detail: detail);
  }

  void _recordHistory() {
    _undoStack.add(jsonEncode(reportData));
    if (_undoStack.length > 40) _undoStack.removeAt(0);
    _redoStack.clear();
    setState(() {});
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(jsonEncode(reportData));
      reportData = Map<String, Map<String, dynamic>>.from(jsonDecode(_undoStack.removeLast()));
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(jsonEncode(reportData));
      reportData = Map<String, Map<String, dynamic>>.from(jsonDecode(_redoStack.removeLast()));
    });
  }

  void _clearGrid() {
    _recordHistory();
    setState(() {
      reportData = {for (var m in members) m['id'].toString(): {}};
    });
  }

  String _getTargetTable() {
    String sn = widget.sheetName;
    if (sn == 'Service Attendance Status') return 'logs_service_attendance_status';
    if (sn == 'All Saints Education') return 'logs_all_saints_education';
    if (sn == 'Cell Group Service') return 'logs_cell_service';
    if (sn == 'Offering Status') return 'logs_offering';
    if (sn == 'Evangelism' || sn == 'Evangelism Part') return 'logs_evangelism';
    if (sn == 'Morning Light') return 'logs_morning_light';
    if (sn == 'Visitations and Counselling') return 'logs_visitations';
    if (sn == 'Workers Education') return 'logs_workers_education';
    if (sn == 'Workers Daily Participation') return 'logs_workers_participation';
    if (sn == 'BB File') return 'bb_students';
    return 'member_logs';
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      // 0. SPECIAL CASE: BB FILE (Master student table)
      if (_isBB) {
        var bbQuery = supabase.from('bb_students').select();
        if (widget.cellName.isNotEmpty && widget.cellName != 'N/A') {
          bbQuery = bbQuery.eq('cell_name', widget.cellName);
        }
        final res = await bbQuery.order('student_name');

        final optionsRes = await supabase
            .from('entry_field_options')
            .select()
            .eq('sheet_name', 'BB File')
            .eq('is_active', true);

        Map<String, List<String>> tempOpts = {};
        for (var opt in optionsRes) {
          tempOpts.putIfAbsent(opt['field_key'].toString().trim(), () => []).add(opt['option_label'].toString());
        }

        if (mounted) {
          setState(() {
            members = res;
            dynamicOptions = tempOpts;
            reportData = {
              for (var s in res) s['id'].toString(): Map<String, dynamic>.from(s)
            };
            isLoading = false;
          });
        }
        return;
      }
      // Load existing photos count for this sheet + date
        final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
        final unitName = widget.cellName.isNotEmpty && widget.cellName != "N/A"
        ? widget.cellName
        : (widget.team.isNotEmpty && widget.team != "N/A"
        ? widget.team
        : (widget.dept.isNotEmpty && widget.dept != "N/A" ? widget.dept : widget.location));

        try {
        final photoRes = await supabase
        .from('report_evidence')
        .select('id')
        .eq('sheet_name', widget.sheetName)
        .eq('unit_name', unitName)
        .eq('report_date', dateStr);

        if (mounted) setState(() => groupEvidenceCount = (photoRes as List).length);
        } catch (e) {
        debugPrint("Evidence count error: $e");
        }

      // 1. STANDARD MEMBERS QUERY (Optimized select!)
      var query = supabase.from('members').select('id, english_name, duty, location, sub_location, department, team, cell_group');

      final grouping = (_roleMetadata?['Grouping'] ?? '').toString();
      final role = (widget.userRole ?? '').toLowerCase();
      final locLower = widget.location.trim().toLowerCase();
      final bool isWorkersSheet = widget.sheetName.contains('Workers');

      final bool isCellWorker = role.contains('cell');
      final bool isTeamWorker = role.contains('team') && !isCellWorker;
      final bool isDeptWorker = (role.startsWith('dept_') || role.contains('_dept_')) && !isCellWorker && !isTeamWorker;
      final bool isSubLocWorker = (role.startsWith('sub_loc_') || role.contains('_sub_loc_')) && !isCellWorker && !isTeamWorker && !isDeptWorker;
      final bool isLocOnlyWorker = role.startsWith('loc_') && !isSubLocWorker && !isDeptWorker && !isTeamWorker && !isCellWorker;

      final bool isLocRole = isCellWorker || isTeamWorker || isDeptWorker || isSubLocWorker || isLocOnlyWorker;

      final bool hasLocationUnits = (locLower != 'church' && locLower != 'church workers' && locLower != 'church main') &&
          ((widget.location.isNotEmpty && widget.location != 'N/A') ||
           (widget.subLocation.isNotEmpty && widget.subLocation != 'N/A') ||
           (widget.team.isNotEmpty && widget.team != 'N/A') ||
           (widget.cellName.isNotEmpty && widget.cellName != 'N/A'));

      final bool isLocWorker = isLocRole || hasLocationUnits;

      if (isLocWorker) {
        if (isWorkersSheet) {
          if (isTeamWorker || (widget.team.isNotEmpty && widget.team != 'N/A')) {
            query = query.eq('team', widget.team);
            if (widget.dept.isNotEmpty && widget.dept != 'N/A') query = query.eq('department', widget.dept);
            if (widget.subLocation.isNotEmpty && widget.subLocation != 'N/A') query = query.eq('sub_location', widget.subLocation);
            if (widget.location.isNotEmpty && widget.location != 'N/A' && locLower != 'church') query = query.eq('location', widget.location);
          } else if (isDeptWorker || (widget.dept.isNotEmpty && widget.dept != 'N/A')) {
            query = query.eq('department', widget.dept);
            if (widget.subLocation.isNotEmpty && widget.subLocation != 'N/A') query = query.eq('sub_location', widget.subLocation);
            if (widget.location.isNotEmpty && widget.location != 'N/A' && locLower != 'church') query = query.eq('location', widget.location);
          } else if (isSubLocWorker || (widget.subLocation.isNotEmpty && widget.subLocation != 'N/A')) {
            query = query.eq('sub_location', widget.subLocation);
            if (widget.location.isNotEmpty && widget.location != 'N/A' && locLower != 'church') query = query.eq('location', widget.location);
          } else {
            if (widget.location.isNotEmpty && widget.location != 'N/A' && locLower != 'church') {
              query = query.eq('location', widget.location);
            }
          }
          query = query.neq('duty', '구역원').not('duty', 'is', null).neq('duty', '');
        } else {
          if (isCellWorker || (widget.cellName.isNotEmpty && widget.cellName != 'N/A')) {
            query = query.eq('cell_group', widget.cellName);
            if (widget.team.isNotEmpty && widget.team != 'N/A') query = query.eq('team', widget.team);
            if (widget.dept.isNotEmpty && widget.dept != 'N/A') query = query.eq('department', widget.dept);
            if (widget.subLocation.isNotEmpty && widget.subLocation != 'N/A') query = query.eq('sub_location', widget.subLocation);
            if (widget.location.isNotEmpty && widget.location != 'N/A' && locLower != 'church') {
              query = query.eq('location', widget.location);
            }
          } else if (isTeamWorker || (widget.team.isNotEmpty && widget.team != 'N/A')) {
            query = query.eq('team', widget.team);
            if (widget.dept.isNotEmpty && widget.dept != 'N/A') query = query.eq('department', widget.dept);
            if (widget.subLocation.isNotEmpty && widget.subLocation != 'N/A') query = query.eq('sub_location', widget.subLocation);
            if (widget.location.isNotEmpty && widget.location != 'N/A' && locLower != 'church') {
              query = query.eq('location', widget.location);
            }
          } else {
            if (widget.dept.isNotEmpty && widget.dept != 'N/A') query = query.eq('department', widget.dept);
            if (widget.subLocation.isNotEmpty && widget.subLocation != 'N/A') query = query.eq('sub_location', widget.subLocation);
            if (widget.location.isNotEmpty && widget.location != 'N/A' && locLower != 'church') {
              query = query.eq('location', widget.location);
            }
          }
        }
      } else {
        void excludeChurchWorkers() {
          query = query
              .neq('location', 'Church Workers')
              .neq('location', 'Church Main')
              .neq('location', 'Church');
        }

        if (grouping == '24-Dept MG' || role.startsWith('mg_group')) {
          query = query.eq('department', '장년회').neq('location', 'Mou').neq('location', 'New Saints');
          excludeChurchWorkers();
        } else if (grouping == '24-Dept WG' || role.startsWith('wg_group')) {
          query = query.eq('department', '부녀회').neq('location', 'Mou').neq('location', 'New Saints');
          excludeChurchWorkers();
        } else if (grouping == '24-Dept YAG' || role.startsWith('yag_group')) {
          query = query.eq('department', '청년회').neq('location', 'Mou').neq('location', 'New Saints');
          excludeChurchWorkers();
        } else if (grouping == '24-Dept New Saints' || role.startsWith('new_saints_dept')) {
          query = query.or('department.eq.새신자,department.ilike.%new saints%').neq('location', 'Mou');
          excludeChurchWorkers();
        } else if (grouping.startsWith('24-Dept 18') || role.startsWith('theology_dept')) {
          query = query.or('department.eq.신학부,department.ilike.%theology%').neq('location', 'Mou').neq('location', 'New Saints');
          excludeChurchWorkers();
        } else if (grouping == '24-Dept MOU' || role.startsWith('mou_dept')) {
          query = query.eq('department', 'Mou').neq('location', 'Mou').neq('location', 'New Saints');
          excludeChurchWorkers();
        } else if (_hasDualModeForCurrentDuty && _dualModeIsChurch) {
          // Church-wide
        } else {
          final officialDeptId = _roleMetadata?['official_dept_id'];
          if (officialDeptId != null) {
            query = query.eq('official_dept_id', officialDeptId);
          } else if (_isInternalAffairs) {
            query = query.or('department.eq.내무부,department.ilike.%internal affairs%');
          } else if (_isEvangelismDept) {
            query = query.or('department.eq.전도부,department.ilike.%evangelism%');
          } else if (_isEducationDept) {
            query = query.or('department.eq.교육부,department.ilike.%education%');
          } else if (_isAdministrationDept) {
            query = query.or('department.eq.행정서무부,department.ilike.%admin%');
          } else if (widget.dept.isNotEmpty && widget.dept != 'N/A' && widget.dept != 'Church') {
            query = query.eq('department', widget.dept);
          } else {
            String deptKeyword = (_roleMetadata?['display_name_ko'] ?? '')
                .toString()
                .replaceAll(RegExp(r'(서무|부장|총무|과장)$'), '')
                .trim();
            if (deptKeyword.isNotEmpty) {
              query = query.eq('department', deptKeyword);
            }
          }
        }

        if (isWorkersSheet) {
          query = query.neq('duty', '구역원').not('duty', 'is', null).neq('duty', '');
        }
      }

      final res = await query.order('english_name');
      final memberIds = res.map((m) => m['id'].toString()).toList();

      List<dynamic> logs = [];
      if (memberIds.isNotEmpty) {
        var logsQuery = supabase
            .from(_getTargetTable())
            .select()
            .eq('report_date', DateFormat('yyyy-MM-dd').format(selectedDate));

        if (widget.sheetName == 'Service Attendance Status') {
          logsQuery = logsQuery.eq('service_day', _selectedDay);
        } else if (widget.sheetName == 'All Saints Education') {
          logsQuery = logsQuery.eq('education_day', _selectedDay);
        } else if (_isMorningLight) {
          logsQuery = logsQuery.eq('ml_day', _selectedDay);
        } else if (_isWorkersEducation) {
          logsQuery = logsQuery.eq('edu_day', _selectedDay);
        } else if (_isWorkersParticipation) {
          logsQuery = logsQuery.eq('part_day', _selectedDay);
        } else if (_isEvangelism) {
          logsQuery = logsQuery.eq('evang_day', _selectedDay);
        }

        if (memberIds.length <= 500) {
          logsQuery = logsQuery.filter('member_id', 'in', memberIds);
        }
        logs = await logsQuery;
      }

      String dbLookupName = widget.sheetName.trim() == "Evangelism Part" ? "Evangelism" : widget.sheetName.trim();
      final optionsRes = await supabase
          .from('entry_field_options')
          .select()
          .eq('sheet_name', dbLookupName)
          .eq('is_active', true);

      Map<String, List<String>> tempOpts = {};
      for (var opt in optionsRes) {
        tempOpts.putIfAbsent(opt['field_key'].toString().trim(), () => []).add(opt['option_label'].toString());
      }

      if (mounted) {
        setState(() {
          members = res;
          dynamicOptions = tempOpts;
          reportData = {for (var m in members) m['id'].toString(): {}};
          for (var log in logs) {
            String mid = log['member_id'].toString();
            if (reportData.containsKey(mid)) {
              reportData[mid] = Map<String, dynamic>.from(log);
            }
          }
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Entry Initial Load Error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _save() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Error: You are not logged in. Please sign in first."),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _saveStatus = "Saving...");

    // 1. SAVE PATH A: BB FILE
    if (_isBB) {
      List<Map<String, dynamic>> studentRows = [];
      reportData.forEach((id, data) {
        if (data.isNotEmpty) {
          final row = Map<String, dynamic>.from(data);
          row['id'] = id;
          row['owner_email'] = currentUser.email;
          row['last_updated'] = DateTime.now().toIso8601String();
          studentRows.add(row);
        }
      });

      if (studentRows.isEmpty) {
        setState(() => _saveStatus = "Save");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.orange, content: Text("No entries to save!")),
        );
        return;
      }

      try {
        await supabase.from('bb_students').upsert(studentRows, onConflict: 'id');
        if (mounted) {
          setState(() => _saveStatus = "Saved");
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            setState(() => _saveStatus = "Save");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(backgroundColor: Colors.green[800], content: const Text("BB Students saved successfully!")),
            );
          }
        }
      } catch (e) {
        debugPrint("BB Save Error: $e");
        if (mounted) {
          setState(() => _saveStatus = "Save");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red[800], content: Text("Save failed: $e")),
          );
        }
      }
      return;
    }

    // 2. SAVE PATH B: STANDARD LOG TABLES
    List<Map<String, dynamic>> logRows = [];
    String dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);

    String unitName = widget.cellName.isNotEmpty && widget.cellName != "N/A"
        ? widget.cellName
        : (widget.team.isNotEmpty && widget.team != "N/A"
            ? widget.team
            : (widget.dept.isNotEmpty && widget.dept != "N/A" ? widget.dept : widget.location));

    final Map<String, dynamic> memberLookup = {
      for (var m in members) m['id'].toString(): m
    };

    final bool isServiceAttendance = widget.sheetName == 'Service Attendance Status';
    final bool isAllSaintsEdu = widget.sheetName == 'All Saints Education';
    final bool isCellService = widget.sheetName == 'Cell Group Service';
    final bool isVisitations = widget.sheetName == 'Visitations and Counselling';

    reportData.forEach((mid, data) {
      if (data.isNotEmpty) {
        final member = memberLookup[mid];

        Map<String, dynamic> row = {
          'member_id': mid,
          'leader_id': currentUser.id,
          'report_date': dateStr,
          'unit_name': unitName,
          // Saving again sends the report back through approval from the start
          // (keeping the old level made an edited report look "final" and
          // drop out of compilations).
          'verification_status': 'pending',
          'approval_level': 0,

          'location': member?['location'] ?? (widget.location != 'N/A' ? widget.location : null),
          'sub_location': member?['sub_location'] ?? (widget.subLocation != 'N/A' ? widget.subLocation : null),
          'department': member?['department'] ?? (widget.dept != 'N/A' ? widget.dept : null),
          'team': member?['team'] ?? (widget.team != 'N/A' ? widget.team : null),
          'cell_group': member?['cell_group'] ?? (widget.cellName != 'N/A' ? widget.cellName : null),
        };

        if (isServiceAttendance) {
          row['reg_status'] = member?['reg_status'];
          row['geo_category'] = member?['geo_category'];
          row['service_day'] = _selectedDay;
        } else if (isAllSaintsEdu) {
          row['education_day'] = _selectedDay;
        } else if (isCellService) {
          row['owner_email'] = currentUser.email;
        } else if (_isMorningLight) {
          row['ml_day'] = _selectedDay;
          row['owner_email'] = currentUser.email;
          row['status_detail'] = data['status_detail'];
        } else if (_isWorkersEducation) {
          row['edu_day'] = _selectedDay;
          row['status_detail'] = data['status_detail'];
        } else if (_isEvangelism) {
          row['evang_day'] = _selectedDay;
          row['owner_email'] = currentUser.email;
          row['status_detail'] = data['status_detail'];
          if (data.containsKey('weekly_schedule')) {
            row['weekly_schedule'] = data['weekly_schedule'];
          }
        } else if (isVisitations) {
          row['owner_email'] = currentUser.email;
          if (data.containsKey('result')) row['result'] = data['result'];
          if (data.containsKey('situation_notes')) row['situation_notes'] = data['situation_notes'];
        } else if (_isWorkersParticipation) {
          row['part_day'] = _selectedDay;
          row['status_detail'] = data['status_detail'];
        }

        row.addAll(data);
        logRows.add(row);
      }
    });

    if (logRows.isEmpty) {
      setState(() => _saveStatus = "Save");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text("No entries to save! Please fill in data before saving."),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      debugPrint("Saving ${logRows.length} rows to ${_getTargetTable()}");
      if (isServiceAttendance) {
        await supabase.from(_getTargetTable()).upsert(
          logRows,
          onConflict: 'member_id,report_date,service_day',
        );
      } else if (isAllSaintsEdu) {
        await supabase.from(_getTargetTable()).upsert(
          logRows,
          onConflict: 'member_id,report_date,education_day',
        );
      } else if (isCellService) {
        await supabase.from(_getTargetTable()).upsert(
          logRows,
          onConflict: 'member_id,report_date',
        );
      } else if (_isMorningLight) {
        await supabase.from(_getTargetTable()).upsert(
          logRows,
          onConflict: 'member_id,report_date,ml_day',
        );
      } else if (_isWorkersEducation) {
        await supabase.from(_getTargetTable()).upsert(
          logRows,
          onConflict: 'member_id,report_date,edu_day',
        );
      } else if (_isWorkersParticipation) {
        await supabase.from(_getTargetTable()).upsert(
          logRows,
          onConflict: 'member_id,report_date,part_day',
        );
      } else if (_isEvangelism) {
        await supabase.from(_getTargetTable()).upsert(
          logRows,
          onConflict: 'member_id,report_date,evang_day',
        );
      } else if (isVisitations) {
        await supabase.from(_getTargetTable()).upsert(
          logRows,
          onConflict: 'member_id,report_date',
        );
      } else if (widget.sheetName == 'Offering Status') {
        // Needs the unique key from 02_schema_fixes.sql; without it every save added new rows
        await supabase.from(_getTargetTable()).upsert(
          logRows,
          onConflict: 'member_id,report_date',
        );
      } else {
        await supabase.from(_getTargetTable()).upsert(logRows);
      }

      if (mounted) {
        setState(() => _saveStatus = "Saved");
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          setState(() => _saveStatus = "Save");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green[800],
              content: Text(
                _hasDayToggle
                    ? "Report for $_selectedDay ($dateStr) saved successfully!"
                    : "Report for $dateStr saved successfully!",
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Entry Save Error: $e");
      if (mounted) {
        setState(() => _saveStatus = "Save");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red[800],
            content: Text("Save failed: $e"),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _pickAnotherDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final minDate = today.subtract(const Duration(days: 5));

    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: minDate,
      lastDate: today,
      helpText: "SELECT REPORT DATE (MAX 5 DAYS AGO)",
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(
          colorScheme: ColorScheme.light(primary: pPurple),
        ),
        child: child!,
      ),
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
        _determineDefaultDay(picked);
      });
      _loadInitialData();
    }
  }

  Widget _buildDayToggle() {
    if (_isWorkersEducation || _isEvangelism) {
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.grey.shade100),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.line(Colors.grey.shade300)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: days.map((d) => _dayOption(d, d)).toList(),
          ),
        ),
      );
    }

    if (_isWorkersParticipation) {
      return Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.grey.shade100),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.line(Colors.grey.shade300)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dayOption('Mon', 'Mon'),
            _dayOption('Tue', 'Tue'),
            _dayOption('Thu', 'Thu'),
            _dayOption('Fri', 'Fri'),
            _dayOption('Sat', 'Sat'),
          ],
        ),
      );
    }

    if (_isMorningLight) {
      return Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.grey.shade100),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.line(Colors.grey.shade300)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dayOption('Mon', 'Mon'),
            _dayOption('Tue', 'Tue'),
            _dayOption('Thu', 'Thu'),
            _dayOption('Fri', 'Fri'),
          ],
        ),
      );
    }

    final String labelSuffix = widget.sheetName == 'All Saints Education' ? 'Edu' : 'Service';
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.grey.shade100),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.line(Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dayOption('Wednesday', 'Wed $labelSuffix'),
          _dayOption('Sunday', 'Sun $labelSuffix'),
        ],
      ),
    );
  }

  Widget _dayOption(String key, String label) {
    final isSelected = _selectedDay == key;
    return InkWell(
      onTap: () {
        if (_selectedDay != key) {
          setState(() => _selectedDay = key);
          _loadInitialData();
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppPalette.bg(isSelected ? pPurple : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: GoogleFonts.merriweather(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppPalette.fg(isSelected ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedModule() {
    String sn = widget.sheetName;
    final void Function() onDataChanged = _recordHistory;

    if (sn == 'Service Attendance Status') {
      return ServiceAttendanceEntry(
        members: members,
        reportData: reportData,
        pPurple: pPurple,
        optionsPre: dynamicOptions['attendance_pre'] ?? [],
        optionsActual: dynamicOptions['attendance_realtime'] ?? [],
        optionsMakeup: dynamicOptions['attendance_makeup'] ?? [],
        optionsPlace: dynamicOptions['place'] ?? [],
        onChanged: onDataChanged,
      );
    }
    if (sn == 'All Saints Education') {
      return AllSaintsEducationEntry(
        members: members,
        reportData: reportData,
        pPurple: pPurple,
        statusOptions: dynamicOptions['status_detail'] ?? [],
        onChanged: onDataChanged,
      );
    }
    if (sn == 'Cell Group Service') {
      return CellServiceEntry(
        members: members, 
        reportData: reportData, 
        pPurple: pPurple, 
        statusOptions: dynamicOptions['status_detail'] ?? [], 
        onChanged: onDataChanged,
      );
    }
    if (sn == 'Morning Light') {
      return MorningLightEntry(
        members: members,
        reportData: reportData,
        pPurple: pPurple,
        statusOptions: dynamicOptions['status_detail'] ?? [],
        onChanged: onDataChanged,
      );
    }
    if (sn == 'Workers Education') {
      return WorkersEducationEntry(
        members: members,
        reportData: reportData,
        pPurple: pPurple,
        statusOptions: dynamicOptions['status_detail'] ?? [],
        onChanged: onDataChanged,
      );
    }
    if (sn == 'Evangelism' || sn == 'Evangelism Part') return EvangelismEntry(members: members, reportData: reportData, pPurple: pPurple, statusOptions: dynamicOptions['status_detail'] ?? [], onChanged: onDataChanged);
    if (sn == 'BB File') return BbFileEntry(students: members, reportData: reportData, pPurple: pPurple, statusOptions: dynamicOptions['level_status'] ?? [], methodOptions: dynamicOptions['method'] ?? [], monthOptions: dynamicOptions['month'] ?? [], onChanged: onDataChanged);
    if (sn == 'Visitations and Counselling') return VisitationsEntry(members: members, reportData: reportData, pPurple: pPurple, optionsReason: dynamicOptions['visitation_reason'] ?? [], optionsResult: dynamicOptions['status_detail'] ?? [], onChanged: onDataChanged);
    if (sn == 'Workers Daily Participation') return DailyParticipationEntry(members: members, reportData: reportData, pPurple: pPurple, statusOptions: dynamicOptions['status_detail'] ?? [], onChanged: onDataChanged);

    return Center(child: Text("Module not found: $sn", style: GoogleFonts.merriweather()));
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 850;
    double sideMargin = isDesktop ? 30 : 12;

    String displayTitle = widget.sheetName == "Evangelism Part" ? "Evangelism" : widget.sheetName;
    bool isPastReport = !DateUtils.isSameDay(selectedDate, DateTime.now());

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
      },
      child: Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(Colors.white),
          elevation: 0.5,
          automaticallyImplyLeading: false,
          titleSpacing: isDesktop ? 0 : 8,
          leadingWidth: isDesktop ? 240 : 48,
          leading: isDesktop
              ? Padding(
                  padding: EdgeInsets.only(left: sideMargin),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                        onPressed: () => Navigator.pop(context, true),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      const VerticalDivider(indent: 14, endIndent: 14, width: 14),
                      IconButton(
                        icon: const Icon(Icons.undo, size: 20),
                        onPressed: _undo,
                        tooltip: "Undo (Ctrl+Z)",
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.redo, size: 20),
                        onPressed: _redo,
                        tooltip: "Redo",
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _save,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _saveStatus,
                          style: GoogleFonts.merriweather(
                            fontWeight: FontWeight.bold,
                            color: AppPalette.fg(_saveStatus == "Saved" ? Colors.green : pPurple),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  onPressed: () => Navigator.pop(context, true),
                ),
          title: Text(
            displayTitle,
            style: GoogleFonts.merriweather(
              fontSize: isDesktop ? 20 : 16,
              fontWeight: FontWeight.w900,
              color: AppPalette.fg(pPurple),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          centerTitle: true,
          actions: [
            if (isDesktop && _hasDayToggle) _buildDayToggle(),
            if (isDesktop)
              InkWell(
                onTap: _pickAnotherDate,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppPalette.bg(isPastReport ? Colors.orange.shade50 : pPurple.withValues(alpha: 0.08)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppPalette.line(isPastReport ? Colors.orange.shade300 : pPurple.withValues(alpha: 0.2)),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPastReport ? Icons.history_rounded : Icons.calendar_today_rounded,
                        size: 14,
                        color: AppPalette.fg(isPastReport ? Colors.orange[900] : pPurple),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        DateFormat('MMM d, yyyy (E)').format(selectedDate),
                        style: GoogleFonts.merriweather(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppPalette.fg(isPastReport ? Colors.orange[900] : pPurple),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(right: sideMargin),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.print_outlined, size: 20),
                    onPressed: () {},
                    tooltip: "Print",
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.delete_sweep_outlined, size: 22, color: AppPalette.fg(Colors.red)),
                    onPressed: _clearGrid,
                    tooltip: "Clear table",
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: isLoading
            ? Center(child: CircularProgressIndicator(color: pPurple))
            : Column(
                children: [
                  if (_hasDualModeForCurrentDuty)
                    Container(
                      margin: EdgeInsets.fromLTRB(sideMargin, 8, sideMargin, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppPalette.bg(Colors.purple.shade50),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppPalette.line(Colors.purple.shade200)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _dualModeIsChurch ? "Mode: Church-Wide (All Units)" : "Mode: Department Only",
                            style: GoogleFonts.merriweather(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: AppPalette.fg(pPurple),
                            ),
                          ),
                          Switch(
                            value: _dualModeIsChurch,
                            activeThumbColor: pPurple,
                            onChanged: (val) {
                              setState(() => _dualModeIsChurch = val);
                              _loadInitialData();
                            },
                          ),
                        ],
                      ),
                    ),

                  if (!isDesktop)
                    Container(
                      margin: EdgeInsets.fromLTRB(sideMargin, 8, sideMargin, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppPalette.bg(Colors.white),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.18))),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.undo, size: 19),
                                    onPressed: _undo,
                                    tooltip: "Undo",
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: const Icon(Icons.redo, size: 19),
                                    onPressed: _redo,
                                    tooltip: "Redo",
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    height: 18,
                                    width: 1,
                                    color: AppPalette.bg(Colors.grey.shade300),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: _save,
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppPalette.bg(_saveStatus == "Saved"
                                            ? Colors.green.withValues(alpha: 0.1)
                                            : pPurple.withValues(alpha: 0.08)),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: AppPalette.line(_saveStatus == "Saved"
                                              ? Colors.green
                                              : pPurple.withValues(alpha: 0.3)),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _saveStatus == "Saved" ? Icons.check_circle : Icons.save_rounded,
                                            size: 14,
                                            color: AppPalette.fg(_saveStatus == "Saved" ? Colors.green : pPurple),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _saveStatus,
                                            style: GoogleFonts.merriweather(
                                              fontWeight: FontWeight.bold,
                                              color: AppPalette.fg(_saveStatus == "Saved" ? Colors.green : pPurple),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              InkWell(
                                onTap: _pickAnotherDate,
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isPastReport ? Icons.history_rounded : Icons.calendar_today_rounded,
                                        size: 13,
                                        color: AppPalette.fg(isPastReport ? Colors.orange[900] : pPurple),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        DateFormat('MMM d (E)').format(selectedDate),
                                        style: GoogleFonts.merriweather(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppPalette.fg(isPastReport ? Colors.orange[900] : pPurple),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_hasDayToggle) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _buildDayToggle(),
                            ),
                          ],
                        ],
                      ),
                    ),

                  const SizedBox(height: 8),

                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: sideMargin),
                    child: Row(
                      children: [
                        _statCardSmall("Total members", "${members.length}", pPurple, isDesktop),
                        const SizedBox(width: 8),
                        _uploadCard(isDesktop),
                        const SizedBox(width: 8),
                        _statCardSmall(_pendingInfo.label, "${_pendingInfo.count}", Colors.orange[800]!, isDesktop),
                      ],
                    ),
                  ),

                  if (_isServiceSheet && members.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(sideMargin, 6, sideMargin, 0),
                      child: Text(
                        _pendingInfo.detail,
                        style: GoogleFonts.merriweather(fontSize: 10.5, color: AppPalette.fg(Colors.orange[900]), fontWeight: FontWeight.w600),
                      ),
                    ),

                  const SizedBox(height: 10),

                  Expanded(
                    child: Container(
                      width: double.infinity,
                      margin: EdgeInsets.fromLTRB(sideMargin, 0, sideMargin, 16),
                      decoration: BoxDecoration(
                        color: AppPalette.bg(Colors.white),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.2))),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _buildSelectedModule(),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _statCardSmall(String l, String v, Color c, bool isDesktop) {
    return Expanded(
      child: Container(
        height: isDesktop ? 46 : 50,
        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 12 : 6, vertical: 4),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppPalette.line(c.withValues(alpha: 0.22)), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: isDesktop
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(l, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Text(v, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w900, color: AppPalette.fg(c))),
                    ],
                  ),
                  Icon(Icons.info_outline, size: 16, color: AppPalette.fg(c.withValues(alpha: 0.5))),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      v,
                      style: GoogleFonts.merriweather(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.fg(c),
                      ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      l,
                      style: GoogleFonts.merriweather(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppPalette.fg(Colors.grey.shade700),
                      ),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _uploadCard(bool isDesktop) {
    return Expanded(
      child: InkWell(
        onTap: _handleUpload,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: isDesktop ? 46 : 50,
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 12 : 6, vertical: 4),
          decoration: BoxDecoration(
            color: AppPalette.bg(Colors.blue.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppPalette.line(Colors.blue.withValues(alpha: 0.3)), width: 1.2),
          ),
          child: isDesktop
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      groupEvidenceCount > 0 ? "$groupEvidenceCount Photos" : "Add evidence",
                      style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.blue), fontWeight: FontWeight.bold),
                    ),
                    Icon(Icons.camera_alt_outlined, color: AppPalette.fg(Colors.blue), size: 18),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_outlined, color: AppPalette.fg(Colors.blue), size: 16),
                    const SizedBox(height: 1),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        groupEvidenceCount > 0 ? "$groupEvidenceCount Photos" : "Add evidence",
                        style: GoogleFonts.merriweather(
                          fontSize: 10,
                          color: AppPalette.fg(Colors.blue),
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _handleUpload() {
  final unitName = widget.cellName.isNotEmpty && widget.cellName != "N/A"
      ? widget.cellName
      : (widget.team.isNotEmpty && widget.team != "N/A"
          ? widget.team
          : (widget.dept.isNotEmpty && widget.dept != "N/A" ? widget.dept : widget.location));

  showDialog(
    context: context,
    builder: (ctx) => EvidenceGalleryDialog(
      sheetName: widget.sheetName,
      unitName: unitName,
      reportDate: selectedDate,
      pPurple: pPurple,
      onEvidenceChanged: _loadInitialData,
    ),
  );
}
}