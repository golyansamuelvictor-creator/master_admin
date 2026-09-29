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
  const EntryFormScreen({
    super.key, 
    required this.sheetName, 
    required this.cellName, 
    required this.location, 
    required this.subLocation, 
    required this.dept, 
    required this.team
  });

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final supabase = Supabase.instance.client;
  DateTime selectedDate = DateTime.now();
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

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      bool isBB = widget.sheetName == "BB File";
      var query = supabase.from(isBB ? 'bb_students' : 'members').select();

      // Safe scoping: prevents null query crashes when location is Church
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
      final logs = await supabase.from(_getTargetTable()).select().eq('report_date', DateFormat('yyyy-MM-dd').format(selectedDate));

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

  Future<void> _save() async {
    setState(() => _saveStatus = "Saving...");
    List<Map<String, dynamic>> logRows = [];
    String dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    
    String unitName = widget.cellName.isNotEmpty && widget.cellName != "N/A"
        ? widget.cellName
        : (widget.team.isNotEmpty && widget.team != "N/A" ? widget.team : widget.dept);

    reportData.forEach((mid, data) {
      if (data.isNotEmpty) {
        Map<String, dynamic> row = {
          'member_id': mid, 
          'leader_id': supabase.auth.currentUser!.id, 
          'report_date': dateStr,
          'unit_name': unitName,
          'verification_status': 'pending'
        };
        row.addAll(data); 
        logRows.add(row);
      }
    });
    try {
      await supabase.from(_getTargetTable()).upsert(logRows);
      setState(() => _saveStatus = "Saved");
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saveStatus = "Save");
    } catch (e) { 
      debugPrint("Entry Save Error: $e");
      setState(() => _saveStatus = "Save"); 
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
    bool isDesktop = width > 900;
    double sideMargin = isDesktop ? 40 : 15; 

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
          automaticallyImplyLeading: false, // Prevents default padding offset
          titleSpacing: 0,
          leadingWidth: isDesktop ? 260 : 210, // Adjusted width for left cluster
          leading: Padding(
            padding: EdgeInsets.only(left: sideMargin), // Matches the exact left edge of the table!
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18), 
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                const VerticalDivider(indent: 12, endIndent: 12, width: 15),
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
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          title: Text(
            widget.sheetName == "Evangelism Part" ? "Evangelism" : widget.sheetName, 
            style: GoogleFonts.merriweather(fontSize: isDesktop ? 22 : 18, fontWeight: FontWeight.w900, color: pPurple),
          ),
          centerTitle: true,
          actions: [
            Padding(
              padding: EdgeInsets.only(right: sideMargin), // Matches the exact right edge of the table!
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
        body: isLoading ? const Center(child: CircularProgressIndicator()) : Column(children: [
          const SizedBox(height: 8), 
          Padding(
            padding: EdgeInsets.symmetric(horizontal: sideMargin),
            child: Row(children: [
              _statCardSmall("Total members", "${members.length}", pPurple),
              const SizedBox(width: 10),
              _uploadCard(),
              const SizedBox(width: 10),
              _statCardSmall("Pending entries", "$_pendingCount", Colors.orange[800]!),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(child: Container(
            width: double.infinity, margin: EdgeInsets.fromLTRB(sideMargin, 0, sideMargin, 20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
            child: ClipRRect(borderRadius: BorderRadius.circular(15), child: _buildSelectedModule()),
          )),
        ]),
      ),
    );
  }

  Widget _statCardSmall(String l, String v, Color c) => Expanded(child: Container(height: 45, padding: const EdgeInsets.symmetric(horizontal: 15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.2), width: 1.5)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [Text(l, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)), const SizedBox(width: 8), Text(v, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w900, color: c))]), Icon(Icons.info_outline, size: 16, color: c.withValues(alpha: 0.5))])));
  Widget _uploadCard() => Expanded(child: InkWell(onTap: _handleUpload, child: Container(height: 45, padding: const EdgeInsets.symmetric(horizontal: 15), decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(groupEvidenceCount > 0 ? "$groupEvidenceCount Photos" : "Add evidence", style: GoogleFonts.merriweather(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)), const Icon(Icons.camera_alt_outlined, color: Colors.blue, size: 18)]))));
  Future<void> _handleUpload() async { FilePickerResult? r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.image); if (r != null) setState(() => groupEvidenceCount = r.files.length); }
}