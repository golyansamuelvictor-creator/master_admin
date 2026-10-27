// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:master_admin/core/app_palette.dart';

class TargetSetterScreen extends StatefulWidget {
  final String? userRole;
  final List<String>? allowedDuties;

  const TargetSetterScreen({
    super.key,
    this.userRole,
    this.allowedDuties, required String userLoc, required String userSub, required String userDept,
  });

  @override
  State<TargetSetterScreen> createState() => _TargetSetterScreenState();
}

class _TargetSetterScreenState extends State<TargetSetterScreen> {
  final _supabase = Supabase.instance.client;
  final Color pPurple = const Color(0xFF4A148C);
  bool _isLoading = false;

  // --- FORM STATE ---
  String _selectedLevel = 'Team';
  String? _selectedUnitName;
  String? _selectedDuty;
  DateTime _selectedMonth = DateTime.now();
  final TextEditingController _targetController = TextEditingController(text: "80");

  List<String> _unitOptions = [];
  final List<String> _levels = ['Location', 'Sub location', 'Department', 'Team', 'Cell'];
  List<String> _duties = [];

  @override
  void initState() {
    super.initState();
    _determineAuthorizedDuties();
    _fetchUnits();
  }

  // ==========================================
  // CATEGORY 1: JURISDICTION RESOLUTION
  // ==========================================

  void _determineAuthorizedDuties() {
    // If explicitly provided via constructor
    if (widget.allowedDuties != null && widget.allowedDuties!.isNotEmpty) {
      _duties = List.from(widget.allowedDuties!);
      _selectedDuty = _duties.first;
      return;
    }

    // Role-based duty assignment
    String r = widget.userRole?.toLowerCase() ?? "";

    if (r == 'edu_dept_sec' || r == 'edu_dept_leader') {
      _duties = ['Workers Education', 'All Saints Education'];
    } else if (r == 'ia_maintenance_mgr') {
      _duties = ['Service Attendance Status', 'Visitations and Counselling'];
    } else if (r == 'ia_mgr_1' || r == 'ia_mgr_2') {
      _duties = ['Cell Group Service', 'Workers Daily Participation'];
    } else if (r == 'evang_dept_sec' || r == 'evang_dept_leader') {
      _duties = ['Evangelism'];
    } else if (r == 'fin_dept_sec' || r == 'fin_dept_leader') {
      _duties = ['Offering Status'];
    } else {
      // Default / Admin / IA Leader: All duties
      _duties = [
        'Service Attendance Status',
        'Cell Group Service',
        'Offering Status',
        'Evangelism',
        'Morning Light',
        'All Saints Education',
        'Visitations and Counselling',
        'Workers Education',
        'Workers Daily Participation',
      ];
    }

    if (_duties.isNotEmpty) {
      _selectedDuty = _duties.first;
    }
  }

  // ==========================================
  // CATEGORY 2: DATA LOGIC (Fetch Units & Save)
  // ==========================================

  Future<void> _fetchUnits() async {
    setState(() => _isLoading = true);
    try {
      String table = '';
      String nameField = 'name';

      if (_selectedLevel == 'Location') {
        table = 'locations';
        nameField = 'location'; // Safe lookup for locations table
      } else if (_selectedLevel == 'Sub location') {
        table = 'sub_locations';
      } else if (_selectedLevel == 'Department') {
        table = 'departments';
      } else if (_selectedLevel == 'Team') {
        table = 'teams';
      } else {
        table = 'cell_groups';
      }

      final res = await _supabase.from(table).select(nameField);

      setState(() {
        _unitOptions = res
            .map((e) => e[nameField]?.toString() ?? "")
            .where((name) => name.isNotEmpty && name.toLowerCase() != 'church')
            .toSet()
            .toList();

        _selectedUnitName = _unitOptions.isNotEmpty ? _unitOptions.first : null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Fetch Units Error: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTarget() async {
    if (_selectedUnitName == null || _targetController.text.trim().isEmpty || _selectedDuty == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please fill in all target details."),
      ));
      return;
    }

    setState(() => _isLoading = true);
    try {
      DateTime period = DateTime(_selectedMonth.year, _selectedMonth.month, 1);

      await _supabase.from('unit_targets').upsert({
        'unit_level': _selectedLevel,
        'unit_name': _selectedUnitName,
        'duty_name': _selectedDuty,
        'target_value': double.parse(_targetController.text.trim()),
        'target_period': DateFormat('yyyy-MM-dd').format(period),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green,
          content: Text("Target set successfully!"),
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Save Target Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Error saving target: $e"),
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==========================================
  // CATEGORY 3: UI LAYOUT (Title & Sentence Case Only)
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        title: Text(
          "Set unit targets",
          style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple), fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppPalette.fg(Color(0xFF4A148C))),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4A148C)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(children: [
                _buildFormCard(),
                const SizedBox(height: 30),
                _buildSaveButton(),
              ]),
            ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.line(Colors.grey.shade200)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label("1. Select hierarchy level"),
        _dropdown(_levels, _selectedLevel, (v) {
          setState(() => _selectedLevel = v!);
          _fetchUnits();
        }),
        const SizedBox(height: 20),

        _label("2. Select specific unit"),
        _dropdown(_unitOptions, _selectedUnitName, (v) => setState(() => _selectedUnitName = v)),
        const SizedBox(height: 20),

        _label("3. Select target duty"),
        _dropdown(_duties, _selectedDuty, (v) => setState(() => _selectedDuty = v)),
        const SizedBox(height: 20),

        _label("4. Target percentage (%)"),
        TextField(
          controller: _targetController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: "e.g. 85.0",
            suffixText: "%",
            filled: true,
            fillColor: AppPalette.bg(Colors.grey[50]),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
          ),
          style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),

        _label("5. Target month"),
        ListTile(
          tileColor: AppPalette.bg(Colors.grey[50]),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppPalette.line(Colors.grey.shade300)),
          ),
          title: Text(
            DateFormat('MMMM yyyy').format(_selectedMonth),
            style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          trailing: Icon(Icons.calendar_month, color: AppPalette.fg(Color(0xFF4A148C))),
          onTap: () => _pickMonth(),
        ),
      ]),
    );
  }

  // ==========================================
  // CATEGORY 4: HELPERS
  // ==========================================

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13, color: AppPalette.fg(Colors.blueGrey)),
    ),
  );

  Widget _dropdown(List<String> items, String? val, Function(String?) onCh) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.grey[50]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.line(Colors.grey.shade300)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(val) ? val : (items.isNotEmpty ? items.first : null),
          isExpanded: true,
          items: items.map((e) => DropdownMenuItem(
            value: e,
            child: Text(e, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.w600)),
          )).toList(),
          onChanged: onCh,
        ),
      ),
    );
  }

  void _pickMonth() async {
    DateTime? p = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (p != null) setState(() => _selectedMonth = p);
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppPalette.bg(pPurple),
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: _saveTarget,
      child: Text(
        "Officially set target",
        style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }
}