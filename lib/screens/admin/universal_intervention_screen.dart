// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/absentee_logic.dart';

class UniversalInterventionScreen extends StatefulWidget {
  final String duty;
  final String unitName;
  final String? buttonTitle;

  const UniversalInterventionScreen({
    super.key,
    required this.duty,
    required this.unitName,
    this.buttonTitle,
  });

  @override
  State<UniversalInterventionScreen> createState() => _UniversalInterventionScreenState();
}

class _UniversalInterventionScreenState extends State<UniversalInterventionScreen> {
  // --- THEME COLORS ---
  // Faded / Muted Dark Navy Blue
  final Color headerDarkBlue = const Color(0xFF1E2D4A).withValues(alpha: 0.88);
  final Color actionBtnBlue   = const Color(0xFF2A4365);
  final Color tableBorderColor = const Color(0xFFCBD5E1); // Thin slate border

  // --- STATE ---
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoading = true;
  String _screenTitle = "";

  // Dynamic Duty Label Fallback Map
  final Map<String, String> _dutyLabelMap = {
    'Workers Education': 'Missed Workers Education',
    'Visitations and Counselling': 'Counseling and Visit Needs',
    'Workers Daily Participation': 'Non-Participants',
    'Cell Group Service': 'Cell Service Absentees',
    'Evangelism Part': "Those Who Didn't Evangelize",
    'Service Attendance Status': 'Service Absentees',
    'Evangelism': "Those Who Didn't Evangelize",
    'Morning Light': 'Those Who Missed Morning Light',
    'All Saints Education': "Those Who Don't Attend ASE",
    'Offering Status': "Those Who Didn't Offer",
  };

  // Active filters across all unit levels
  final Map<String, Set<String>> _activeFilters = {
    "Loc": {},
    "Sub-Loc": {},
    "Dept": {},
    "Team": {},
    "Cell Group": {},
    "Name": {},
    "Missed": {},
  };

  // Base column widths
  final Map<String, double> _colWidths = {
    "Loc": 80,
    "Sub-Loc": 90,
    "Dept": 90,
    "Team": 75,
    "Cell Group": 100,
    "Name": 130,
    "Missed": 75,
    "Care Status": 115,
    "Action": 95,
    "Reason": 140,
  };

  double get _baseTableWidth => _colWidths.values.reduce((a, b) => a + b);

  String _formatToTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  @override
  void initState() {
    super.initState();
    final initial = _dutyLabelMap[widget.duty] ?? widget.buttonTitle ?? widget.duty;
    _screenTitle = _formatToTitleCase(initial);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);

    try {
      final configRes = await Supabase.instance.client
          .from('app_duty_config')
          .select('intervention_label')
          .eq('duty_name', widget.duty)
          .maybeSingle();

      if (configRes != null && configRes['intervention_label'] != null) {
        if (mounted) {
          setState(() {
            _screenTitle = _formatToTitleCase(configRes['intervention_label']);
          });
        }
      }
    } catch (_) {}

    final res = await AbsenteeLogic.getDetailedInterventionList(
      duty: widget.duty,
      unitName: widget.unitName,
    );

    if (mounted) {
      setState(() {
        _data = res;
        _filteredData = res;
        _isLoading = false;
      });
    }
  }

  // --- UNIT GETTERS ---
  String _getLocation(Map<String, dynamic> m) => (m['location'] ?? "").toString();
  String _getSubLocation(Map<String, dynamic> m) => (m['sub_location'] ?? m['sublocation'] ?? "").toString();
  String _getDepartment(Map<String, dynamic> m) => (m['department'] ?? m['current_dept'] ?? "").toString();
  String _getTeam(Map<String, dynamic> m) => (m['team'] ?? m['team_number'] ?? "").toString();
  String _getCellGroup(Map<String, dynamic> m) => (m['cell_group'] ?? m['cell_number'] ?? "").toString();
  String _getName(Map<String, dynamic> m) => (m['english_name'] ?? m['full_name'] ?? m['name'] ?? "").toString();

  // ==========================================
  // FILTER LOGIC
  // ==========================================

  void _applyFilters() {
    setState(() {
      _filteredData = _data.where((item) {
        final m = item['member'];

        bool matches(String column, String value) {
          if (_activeFilters[column]!.isEmpty) return true;
          return _activeFilters[column]!.contains(value);
        }

        return matches("Loc", _getLocation(m)) &&
               matches("Sub-Loc", _getSubLocation(m)) &&
               matches("Dept", _getDepartment(m)) &&
               matches("Team", _getTeam(m)) &&
               matches("Cell Group", _getCellGroup(m)) &&
               matches("Name", _getName(m)) &&
               matches("Missed", "${item['missed_count']} Times");
      }).toList();
    });
  }

  List<String> _getUniqueValuesForColumn(String column) {
    Set<String> values = {};
    for (var item in _data) {
      final m = item['member'];
      if (column == "Loc") values.add(_getLocation(m).isEmpty ? "N/A" : _getLocation(m));
      else if (column == "Sub-Loc") values.add(_getSubLocation(m).isEmpty ? "N/A" : _getSubLocation(m));
      else if (column == "Dept") values.add(_getDepartment(m).isEmpty ? "N/A" : _getDepartment(m));
      else if (column == "Team") values.add(_getTeam(m).isEmpty ? "N/A" : _getTeam(m));
      else if (column == "Cell Group") values.add(_getCellGroup(m).isEmpty ? "N/A" : _getCellGroup(m));
      else if (column == "Name") values.add(_getName(m).isEmpty ? "N/A" : _getName(m));
      else if (column == "Missed") values.add("${item['missed_count']} Times");
    }
    return values.toList()..sort();
  }

  // ==========================================
  // UI BUILD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          _screenTitle,
          style: GoogleFonts.merriweather(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: const Color(0xFF1E2D4A),
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Color(0xFF1E2D4A)),
      ),
      body: Column(
        children: [
          _buildCompactSummaryHeader(),
          Expanded(child: _buildInterventionTable()),
        ],
      ),
    );
  }

  // --- TOP CARD (Search & Instruction Bar) ---
  Widget _buildCompactSummaryHeader() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: tableBorderColor, width: 0.5),
    ),
    child: Row(
      children: [
        Icon(Icons.filter_list_rounded, color: headerDarkBlue, size: 18),
        const SizedBox(width: 8),
        const Text(
          "Tap headers to filter • Scroll sideways for all units",
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
        ),
        const Spacer(),
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => setState(() {
            _activeFilters.forEach((k, v) => v.clear());
            _applyFilters();
          }),
          child: Text(
            "Clear filters",
            style: TextStyle(color: headerDarkBlue, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  // --- THE TABLE WRAPPER ---
  Widget _buildInterventionTable() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tableBorderColor, width: 0.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Span at least the full card width or horizontal scroll if larger
            final effectiveTableWidth = math.max(constraints.maxWidth, _baseTableWidth);

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: effectiveTableWidth,
                child: Column(
                  children: [
                    _buildTableHeader(),
                    Expanded(
                      child: _isLoading
                          ? _buildSkeletonRows()
                          : _filteredData.isEmpty
                              ? _buildEmptyStateRows()
                              : ListView.builder(
                                  itemCount: _filteredData.length,
                                  itemBuilder: (c, i) => _buildCompactDataRow(i, _filteredData[i]),
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // --- HEADER ROW (Faded Dark Blue, Thin Borders) ---
  Widget _buildTableHeader() {
    return Container(
      decoration: BoxDecoration(
        color: headerDarkBlue,
        border: Border(bottom: BorderSide(color: tableBorderColor, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      child: Row(
        children: [
          _headerCell("Loc", width: _colWidths["Loc"]!, filterable: true),
          _headerCell("Sub-Loc", width: _colWidths["Sub-Loc"]!, filterable: true),
          _headerCell("Dept", width: _colWidths["Dept"]!, filterable: true),
          _headerCell("Team", width: _colWidths["Team"]!, filterable: true),
          _headerCell("Cell Group", width: _colWidths["Cell Group"]!, filterable: true),
          _headerCell("Name", width: _colWidths["Name"]!, filterable: true),
          _headerCell("Missed", width: _colWidths["Missed"]!, filterable: true),
          _headerCell("Care Status", width: _colWidths["Care Status"]!, filterable: false),
          _headerCell("Action", width: _colWidths["Action"]!, filterable: false),
          _headerCell("Reason", width: _colWidths["Reason"]!, filterable: false),
        ],
      ),
    );
  }

  Widget _headerCell(String label, {required double width, required bool filterable}) {
    bool hasActiveFilter = _activeFilters[label]?.isNotEmpty ?? false;

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: filterable ? () => _showCheckboxFilter(label) : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            if (filterable)
              Icon(
                Icons.arrow_drop_down,
                size: 15,
                color: hasActiveFilter ? Colors.amberAccent : Colors.white60,
              ),
          ],
        ),
      ),
    );
  }

  // --- DATA ROW (Thin Lines, Half Height) ---
  Widget _buildCompactDataRow(int index, Map<String, dynamic> item) {
    final m = item['member'];
    bool isChronic = item['missed_count'] >= 4;

    return Container(
      decoration: BoxDecoration(
        color: index.isEven ? Colors.white : const Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: tableBorderColor, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: Row(
        children: [
          _cellText(_getLocation(m), width: _colWidths["Loc"]!),
          _cellText(_getSubLocation(m), width: _colWidths["Sub-Loc"]!),
          _cellText(_getDepartment(m), width: _colWidths["Dept"]!),
          _cellText(_getTeam(m), width: _colWidths["Team"]!),
          _cellText(_getCellGroup(m), width: _colWidths["Cell Group"]!),
          _cellText(_getName(m), width: _colWidths["Name"]!, isBold: true),
          SizedBox(
            width: _colWidths["Missed"]!,
            child: Center(
              child: Text(
                "${item['missed_count']}x",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isChronic ? Colors.red[700] : Colors.orange[800],
                ),
              ),
            ),
          ),
          SizedBox(
            width: _colWidths["Care Status"]!,
            child: Center(
              child: Text(
                item['last_recovery_outcome'] ?? "No Care Logged",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.blueGrey[600]),
              ),
            ),
          ),
          SizedBox(
            width: _colWidths["Action"]!,
            child: Center(
              child: SizedBox(
                height: 24,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionBtnBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: () => _showMaintenanceDialog(m),
                  child: const Text("Log Care", style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
          SizedBox(
            width: _colWidths["Reason"]!,
            child: Center(
              child: Text(
                item['last_reason'] ?? "-",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cellText(String val, {required double width, bool isBold = false}) {
    return SizedBox(
      width: width,
      child: Center(
        child: Text(
          val.isEmpty ? "-" : val,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.w600 : FontWeight.normal),
        ),
      ),
    );
  }

  // --- EMPTY STATE ROWS (Structure never disappears!) ---
  Widget _buildEmptyStateRows() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tableBorderColor, width: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 20, color: Colors.green[600]),
              const SizedBox(width: 8),
              const Text(
                "No intervention records found for this unit",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
              ),
            ],
          ),
        ),
        // Empty placeholder rows with thin borders showing the grid
        for (int i = 0; i < 4; i++)
          Container(
            decoration: BoxDecoration(
              color: i.isEven ? Colors.white : const Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: tableBorderColor, width: 0.5)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            child: Row(
              children: [
                _emptyCell(_colWidths["Loc"]!),
                _emptyCell(_colWidths["Sub-Loc"]!),
                _emptyCell(_colWidths["Dept"]!),
                _emptyCell(_colWidths["Team"]!),
                _emptyCell(_colWidths["Cell Group"]!),
                _emptyCell(_colWidths["Name"]!),
                _emptyCell(_colWidths["Missed"]!),
                _emptyCell(_colWidths["Care Status"]!),
                _emptyCell(_colWidths["Action"]!),
                _emptyCell(_colWidths["Reason"]!),
              ],
            ),
          ),
      ],
    );
  }

  Widget _emptyCell(double width) => SizedBox(
    width: width,
    child: const Center(
      child: Text("-", style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
    ),
  );

  // --- SKELETON LOADER ROWS ---
  Widget _buildSkeletonRows() {
    return ListView.builder(
      itemCount: 8,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (_, index) => Container(
        decoration: BoxDecoration(
          color: index.isEven ? Colors.white : const Color(0xFFF8FAFC),
          border: Border(bottom: BorderSide(color: tableBorderColor, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            _skeletonBar(_colWidths["Loc"]!),
            _skeletonBar(_colWidths["Sub-Loc"]!),
            _skeletonBar(_colWidths["Dept"]!),
            _skeletonBar(_colWidths["Team"]!),
            _skeletonBar(_colWidths["Cell Group"]!),
            _skeletonBar(_colWidths["Name"]!),
            _skeletonBar(_colWidths["Missed"]!),
            _skeletonBar(_colWidths["Care Status"]!),
            _skeletonBar(_colWidths["Action"]!),
            _skeletonBar(_colWidths["Reason"]!),
          ],
        ),
      ),
    );
  }

  Widget _skeletonBar(double width) {
    return SizedBox(
      width: width,
      child: Center(
        child: Container(
          width: width * 0.55,
          height: 10,
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // DIALOGS
  // ==========================================

  void _showMaintenanceDialog(dynamic member) {
    String selectedOutcome = 'Recovered';
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setST) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text("Care Log: ${_getName(member)}", style: TextStyle(color: headerDarkBlue, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedOutcome,
                decoration: const InputDecoration(labelText: "Outcome", border: OutlineInputBorder()),
                items: ['Recovered', 'Sick', 'Working', 'Travelled', 'Unresolved']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) => setST(() => selectedOutcome = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(hintText: "Maintenance notes...", border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: actionBtnBlue),
              onPressed: () async {
                final user = Supabase.instance.client.auth.currentUser;
                await Supabase.instance.client.from('member_recovery_logs').insert({
                  'member_id': member['id'],
                  'duty_name': widget.duty,
                  'outcome': selectedOutcome,
                  'summary': noteCtrl.text,
                  'recorded_by': user?.id,
                });

                if (!c.mounted) return;
                Navigator.pop(c);

                if (mounted) {
                  _load();
                }
              },
              child: const Text("Save Log", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCheckboxFilter(String column) {
    List<String> options = _getUniqueValuesForColumn(column);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: Text("Filter $column", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: headerDarkBlue)),
              content: SizedBox(
                width: 280,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      dense: true,
                      title: const Text("Select all", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      value: _activeFilters[column]!.isEmpty,
                      onChanged: (_) => setDialogState(() => _activeFilters[column]!.clear()),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: options.map((opt) {
                            bool isChecked = _activeFilters[column]!.contains(opt);
                            return CheckboxListTile(
                              dense: true,
                              title: Text(opt, style: const TextStyle(fontSize: 12)),
                              value: isChecked,
                              onChanged: (v) {
                                setDialogState(() {
                                  if (v == true) _activeFilters[column]!.add(opt);
                                  else _activeFilters[column]!.remove(opt);
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: actionBtnBlue),
                  onPressed: () {
                    _applyFilters();
                    Navigator.pop(context);
                  },
                  child: const Text("Apply Filter", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}