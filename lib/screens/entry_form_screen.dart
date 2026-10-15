// ignore_for_file: curly_braces_in_flow_control_structures, avoid_print
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
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

class EntryFormScreen extends StatefulWidget {
  final String sheetName, cellName, location, subLocation, dept, team;
  final DateTime? selectedDate; // Date selected from ReportsScreen (max 5 days ago)
  final String? initialMode;

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

  // --- EXCEL PRO STATE ---
  String _saveStatus = "Save";
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  bool get _isChurchLocation => widget.location.trim().toLowerCase() == 'church';

  @override
  void initState() {
    super.initState();
    // Initializes with the selected previous date if provided, otherwise today
    selectedDate = widget.selectedDate ?? DateTime.now();
    _loadInitialData();
  }

  // --- REAL-TIME PENDING LOGIC ---
  int get _pendingCount {
    if (members.isEmpty) return 0;
    int filled = reportData.values.where((v) => v.isNotEmpty && v.values.any((val) => val != null && val != "")).length;
    return members.length - filled;
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

  // Loads data for the selected date (including existing past reports from Supabase)
  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      bool isBB = widget.sheetName == "BB File";
      var query = supabase.from(isBB ? 'bb_students' : 'members').select();

      if (_isChurchLocation) {
        if (widget.dept.isNotEmpty && widget.dept != 'N/A') {
          query = query.eq('department', widget.dept);
        }
      } else {
        if (widget.location.isNotEmpty && widget.location != 'N/A') query = query.eq('location', widget.location);
        if (widget.subLocation.isNotEmpty && widget.subLocation != 'N/A') query = query.eq('sub_location', widget.subLocation);
        if (widget.dept.isNotEmpty && widget.dept != 'N/A') query = query.eq('department', widget.dept);
        if (widget.team.isNotEmpty && widget.team != 'N/A') query = query.eq('team', widget.team);

        if (!isBB) {
          if (widget.sheetName.contains('Workers')) {
            query = query.neq('duty', '구역원'); 
          } else if (widget.cellName.isNotEmpty && widget.cellName != 'N/A') {
            query = query.eq('cell_group', widget.cellName); 
          }
        }
      }

      final res = await query.order(isBB ? 'student_name' : 'english_name');
      
      // Queries logs for the specific selectedDate (pre-populating existing data for editing)
      final logs = await supabase
          .from(_getTargetTable())
          .select()
          .eq('report_date', DateFormat('yyyy-MM-dd').format(selectedDate));

      String dbLookupName = widget.sheetName.trim() == "Evangelism Part" ? "Evangelism" : widget.sheetName.trim();
      final optionsRes = await supabase.from('entry_field_options').select().eq('sheet_name', dbLookupName).eq('is_active', true);

      Map<String, List<String>> tempOpts = {};
      for (var opt in optionsRes) {
        tempOpts.putIfAbsent(opt['field_key'].toString().trim(), () => []).add(opt['option_label'].toString());
      }

      if (mounted) {
        setState(() {
          members = res;
          dynamicOptions = tempOpts;
          reportData = {for (var m in members) m['id'].toString(): {}};
          // Pre-fills existing report data so the user can edit it
          for (var log in logs) {
            String mid = log['member_id'].toString();
            if (reportData.containsKey(mid)) reportData[mid] = Map<String, dynamic>.from(log);
          }
          isLoading = false;
        });
      }
    } catch (e) { 
      debugPrint("Entry Initial Load Error: $e");
      if (mounted) setState(() => isLoading = false); 
    }
  }

  // Saves/upserts edits directly into Supabase under the selected report_date
  // Saves/upserts edits directly into Supabase under the selected report_date
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
    List<Map<String, dynamic>> logRows = [];
    String dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);

    String unitName = widget.cellName.isNotEmpty && widget.cellName != "N/A"
        ? widget.cellName
        : (widget.team.isNotEmpty && widget.team != "N/A" ? widget.team : widget.dept);

    // Fast lookup map to match member_id with full member record
    final Map<String, dynamic> memberLookup = {
      for (var m in members) m['id'].toString(): m
    };

    // Check if current sheet is Service Attendance Status
    final bool isServiceAttendance = widget.sheetName == 'Service Attendance Status';

    reportData.forEach((mid, data) {
      if (data.isNotEmpty) {
        final member = memberLookup[mid];

        Map<String, dynamic> row = {
          'member_id': int.tryParse(mid) ?? mid,
          'leader_id': currentUser.id,
          'report_date': dateStr,
          'unit_name': unitName,
          'verification_status': 'pending',

          // Hierarchy columns for all tables
          'location': member?['location'] ?? (widget.location != 'N/A' ? widget.location : null),
          'sub_location': member?['sub_location'] ?? (widget.subLocation != 'N/A' ? widget.subLocation : null),
          'department': member?['department'] ?? (widget.dept != 'N/A' ? widget.dept : null),
          'team': member?['team'] ?? (widget.team != 'N/A' ? widget.team : null),
          'cell_group': member?['cell_group'] ?? (widget.cellName != 'N/A' ? widget.cellName : null),
        };

        // ONLY attach reg_status and geo_category for Service Attendance Status
        if (isServiceAttendance) {
          row['reg_status'] = member?['reg_status'];
          row['geo_category'] = member?['geo_category'];
        }

        // Adds module-specific inputs
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
      await supabase.from(_getTargetTable()).upsert(logRows);

      if (mounted) {
        setState(() => _saveStatus = "Saved");
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          setState(() => _saveStatus = "Save");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green[800],
              content: Text("Report for $dateStr saved successfully!"),
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
  
  // Quick date change restricted to max 5 days back
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
      setState(() => selectedDate = picked);
      _loadInitialData();
    }
  }

  Widget _buildSelectedModule() {
    String sn = widget.sheetName;
    final void Function() onDataChanged = _recordHistory;

    if (sn == 'Service Attendance Status') return ServiceAttendanceEntry(members: members, reportData: reportData, pPurple: pPurple, optionsPre: dynamicOptions['attendance_pre'] ?? [], optionsActual: dynamicOptions['attendance_realtime'] ?? [], optionsMakeup: dynamicOptions['attendance_makeup'] ?? [], optionsPlace: dynamicOptions['place'] ?? [], onChanged: onDataChanged);
    if (sn == 'Cell Group Service') return CellServiceEntry(members: members, reportData: reportData, pPurple: pPurple, statusOptions: dynamicOptions['status_detail'] ?? [], onChanged: onDataChanged);
    if (sn == 'Evangelism' || sn == 'Evangelism Part') return EvangelismEntry(members: members, reportData: reportData, pPurple: pPurple, statusOptions: dynamicOptions['status_detail'] ?? [], onChanged: onDataChanged);
    if (sn == 'BB File') return BbFileEntry(students: members, reportData: reportData, pPurple: pPurple, statusOptions: dynamicOptions['level_status'] ?? [], methodOptions: dynamicOptions['method'] ?? [], monthOptions: dynamicOptions['month'] ?? [], onChanged: onDataChanged);
    if (sn == 'Morning Light') return MorningLightEntry(members: members, reportData: reportData, pPurple: pPurple, statusOptions: dynamicOptions['status_detail'] ?? [], onChanged: onDataChanged);
    if (sn == 'All Saints Education') return AllSaintsEducationEntry(members: members, reportData: reportData, pPurple: pPurple, statusOptions: dynamicOptions['status_detail'] ?? [], onChanged: onDataChanged);
    if (sn == 'Visitations and Counselling') return VisitationsEntry(members: members, reportData: reportData, pPurple: pPurple, optionsReason: dynamicOptions['visitation_reason'] ?? [], optionsResult: dynamicOptions['status_detail'] ?? [], onChanged: onDataChanged);
    if (sn == 'Workers Education') return WorkersEducationEntry(members: members, reportData: reportData, pPurple: pPurple, optionsSun: dynamicOptions['edu_sun'] ?? [], optionsWed: dynamicOptions['edu_wed'] ?? [], optionsOther: dynamicOptions['edu_other'] ?? [], onChanged: onDataChanged);
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
        backgroundColor: const Color(0xFFFBFBFE),
        appBar: AppBar(
          backgroundColor: Colors.white,
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
                            color: _saveStatus == "Saved" ? Colors.green : pPurple,
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
              color: pPurple,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          centerTitle: true,
          actions: [
            // Date Switcher in AppBar on Desktop
            if (isDesktop)
              InkWell(
                onTap: _pickAnotherDate,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isPastReport ? Colors.orange.shade50 : pPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isPastReport ? Colors.orange.shade300 : pPurple.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPastReport ? Icons.history_rounded : Icons.calendar_today_rounded,
                        size: 14,
                        color: isPastReport ? Colors.orange[900] : pPurple,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        DateFormat('MMM d, yyyy').format(selectedDate),
                        style: GoogleFonts.merriweather(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isPastReport ? Colors.orange[900] : pPurple,
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
                    icon: const Icon(Icons.delete_sweep_outlined, size: 22, color: Colors.red), 
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
                // Quick Action strip (Undo, Redo, Save, Date Selector)
                if (!isDesktop)
                  Container(
                    margin: EdgeInsets.fromLTRB(sideMargin, 8, sideMargin, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
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
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _save,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _saveStatus == "Saved" 
                                      ? Colors.green.withValues(alpha: 0.1) 
                                      : pPurple.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _saveStatus == "Saved" 
                                        ? Colors.green 
                                        : pPurple.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _saveStatus == "Saved" ? Icons.check_circle : Icons.save_rounded,
                                      size: 14,
                                      color: _saveStatus == "Saved" ? Colors.green : pPurple,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _saveStatus, 
                                      style: GoogleFonts.merriweather(
                                        fontWeight: FontWeight.bold, 
                                        color: _saveStatus == "Saved" ? Colors.green : pPurple,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Tap to switch date on mobile (max 5 days back)
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
                                  color: isPastReport ? Colors.orange[900] : pPurple,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('MMM d, yyyy').format(selectedDate),
                                  style: GoogleFonts.merriweather(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isPastReport ? Colors.orange[900] : pPurple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 8),

                // Responsive Stats Row
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: sideMargin),
                  child: Row(
                    children: [
                      _statCardSmall("Total members", "${members.length}", pPurple, isDesktop),
                      const SizedBox(width: 8),
                      _uploadCard(isDesktop),
                      const SizedBox(width: 8),
                      _statCardSmall("Pending entries", "$_pendingCount", Colors.orange[800]!, isDesktop),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Module Grid Container
                Expanded(
                  child: Container(
                    width: double.infinity,
                    margin: EdgeInsets.fromLTRB(sideMargin, 0, sideMargin, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: 0.22), width: 1.2),
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
                      Text(v, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w900, color: c)),
                    ],
                  ),
                  Icon(Icons.info_outline, size: 16, color: c.withValues(alpha: 0.5)),
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
                        color: c,
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
                        color: Colors.grey.shade700,
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
            color: Colors.blue.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 1.2),
          ),
          child: isDesktop
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      groupEvidenceCount > 0 ? "$groupEvidenceCount Photos" : "Add evidence",
                      style: GoogleFonts.merriweather(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold),
                    ),
                    const Icon(Icons.camera_alt_outlined, color: Colors.blue, size: 18),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.camera_alt_outlined, color: Colors.blue, size: 16),
                    const SizedBox(height: 1),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        groupEvidenceCount > 0 ? "$groupEvidenceCount Photos" : "Add evidence",
                        style: GoogleFonts.merriweather(
                          fontSize: 10,
                          color: Colors.blue,
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

  Future<void> _handleUpload() async { 
    FilePickerResult? r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.image); 
    if (r != null) setState(() => groupEvidenceCount = r.files.length); 
  }
}