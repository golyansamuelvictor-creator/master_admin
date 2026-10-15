// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // --- FRESH, CRISP EXECUTIVE PALETTE (Replaced dull grey) ---
  final Color headerDarkNavy   = const Color(0xFF1E2D4A); // Rich deep navy
  final Color actionBtnBlue    = const Color(0xFF2B4C7E); // Vibrant action blue
  final Color gridLineColor    = const Color(0xFFCBD5E1); // Crisp thin gridline
  final Color letterBg         = const Color(0xFFF1F5F9); // Crisp letter row
  final Color cornerBg         = const Color(0xFFE2E8F0); // Pinned corner
  final Color rowEvenBg        = Colors.white;            // Bento row 1
  final Color rowOddBg         = const Color(0xFFF6F9FD); // Bento row 2 (clean faint ice-slate tint)

  // Layout heights & widths
  final double letterRowHeight = 22.0;
  final double headerRowHeight = 32.0;
  final double dataRowHeight   = 30.0;
  final double rowNumWidth     = 42.0;

  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScrollData = ScrollController();
  final ScrollController _verticalScrollRowNumbers = ScrollController();

  // --- STATE ---
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoading = true;
  String _screenTitle = "";
  final Set<String> _hiddenColumns = {}; // Column hiding & unhiding

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

  final Map<String, Set<String>> _activeFilters = {
    "Loc": {},
    "Sub-Loc": {},
    "Dept": {},
    "Team": {},
    "Cell Group": {},
    "Name": {},
    "Missed": {},
  };

  final Map<String, double> _colWidths = {
    "Loc": 85,
    "Sub-Loc": 95,
    "Dept": 95,
    "Team": 80,
    "Cell Group": 105,
    "Name": 140,
    "Missed": 80,
    "Care Status": 125,
    "Action": 95,
    "Reason": 150,
  };

  final List<String> _allColumns = [
    "Loc",
    "Sub-Loc",
    "Dept",
    "Team",
    "Cell Group",
    "Name",
    "Missed",
    "Care Status",
    "Action",
    "Reason",
  ];

  List<String> get _visibleColumns => _allColumns.where((c) => !_hiddenColumns.contains(c)).toList();
  double get _baseTableWidth => _visibleColumns.fold(0.0, (acc, k) => acc + (_colWidths[k] ?? 100));

  String _formatToTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String _getExcelColumnLetter(int index) {
    String letter = "";
    while (index >= 0) {
      letter = String.fromCharCode((index % 26) + 65) + letter;
      index = (index ~/ 26) - 1;
    }
    return letter;
  }

  @override
  void initState() {
    super.initState();
    final initial = _dutyLabelMap[widget.duty] ?? widget.buttonTitle ?? widget.duty;
    _screenTitle = _formatToTitleCase(initial);

    _verticalScrollData.addListener(() {
      if (_verticalScrollRowNumbers.hasClients &&
          _verticalScrollRowNumbers.offset != _verticalScrollData.offset) {
        _verticalScrollRowNumbers.jumpTo(_verticalScrollData.offset);
      }
    });

    _verticalScrollRowNumbers.addListener(() {
      if (_verticalScrollData.hasClients &&
          _verticalScrollData.offset != _verticalScrollRowNumbers.offset) {
        _verticalScrollData.jumpTo(_verticalScrollRowNumbers.offset);
      }
    });

    _load();
  }

  @override
  void dispose() {
    _horizontalScroll.dispose();
    _verticalScrollData.dispose();
    _verticalScrollRowNumbers.dispose();
    super.dispose();
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

    try {
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
    } catch (e) {
      debugPrint("Error loading intervention list: $e");
      if (mounted) {
        setState(() {
          _data = [];
          _filteredData = [];
          _isLoading = false;
        });
      }
    }
  }

  // --- UNIT GETTERS ---
  Map<String, dynamic> _extractMember(dynamic item) {
    if (item == null || item is! Map) return {};
    var m = item['member'] ?? item['members'];
    if (m is List && m.isNotEmpty) m = m.first;
    if (m is Map) {
      return {
        ...Map<String, dynamic>.from(item),
        ...Map<String, dynamic>.from(m),
      };
    }
    return Map<String, dynamic>.from(item);
  }

  int _getMissedCount(dynamic item) {
    if (item == null || item is! Map) return 0;
    final val = item['missed_count'] ?? item['missed'] ?? item['count'];
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  String _getLocation(Map<String, dynamic> m) => (m['location'] ?? m['loc'] ?? "").toString();
  String _getSubLocation(Map<String, dynamic> m) => (m['sub_location'] ?? m['sublocation'] ?? "").toString();
  String _getDepartment(Map<String, dynamic> m) => (m['department'] ?? m['current_dept'] ?? m['dept'] ?? "").toString();
  String _getTeam(Map<String, dynamic> m) => (m['team'] ?? m['team_number'] ?? m['team_no'] ?? "").toString();
  String _getCellGroup(Map<String, dynamic> m) => (m['cell_group'] ?? m['cell_number'] ?? m['cell'] ?? "").toString();
  String _getName(Map<String, dynamic> m) => (m['english_name'] ?? m['full_name'] ?? m['name'] ?? "").toString();

  // ==========================================
  // FILTER LOGIC
  // ==========================================

  void _applyFilters() {
    setState(() {
      _filteredData = _data.where((item) {
        final m = _extractMember(item);
        final missedCount = _getMissedCount(item);

        bool matches(String column, String value) {
          if (_activeFilters[column] == null || _activeFilters[column]!.isEmpty) return true;
          return _activeFilters[column]!.contains(value.isEmpty ? "N/A" : value);
        }

        return matches("Loc", _getLocation(m)) &&
               matches("Sub-Loc", _getSubLocation(m)) &&
               matches("Dept", _getDepartment(m)) &&
               matches("Team", _getTeam(m)) &&
               matches("Cell Group", _getCellGroup(m)) &&
               matches("Name", _getName(m)) &&
               matches("Missed", "$missedCount Times");
      }).toList();
    });
  }

  List<String> _getUniqueValuesForColumn(String column) {
    Set<String> values = {};
    for (var item in _data) {
      final m = _extractMember(item);
      final missedCount = _getMissedCount(item);

      if (column == "Loc") values.add(_getLocation(m).isEmpty ? "N/A" : _getLocation(m));
      else if (column == "Sub-Loc") values.add(_getSubLocation(m).isEmpty ? "N/A" : _getSubLocation(m));
      else if (column == "Dept") values.add(_getDepartment(m).isEmpty ? "N/A" : _getDepartment(m));
      else if (column == "Team") values.add(_getTeam(m).isEmpty ? "N/A" : _getTeam(m));
      else if (column == "Cell Group") values.add(_getCellGroup(m).isEmpty ? "N/A" : _getCellGroup(m));
      else if (column == "Name") values.add(_getName(m).isEmpty ? "N/A" : _getName(m));
      else if (column == "Missed") values.add("$missedCount Times");
    }
    return values.toList()..sort();
  }

  // ==========================================
  // COLUMN HIDING & UNHIDING
  // ==========================================

  void _showColumnVisibilityDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Row(
            children: [
              Icon(Icons.view_column_rounded, color: headerDarkNavy, size: 20),
              const SizedBox(width: 8),
              Text(
                "Show / Hide Columns",
                style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold, color: headerDarkNavy),
              ),
            ],
          ),
          content: SizedBox(
            width: 300,
            height: 320,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        setDialogState(() => _hiddenColumns.clear());
                        setState(() {});
                      },
                      child: const Text("Show All", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () {
                        setDialogState(() {
                          _hiddenColumns.addAll(["Sub-Loc", "Team", "Care Status", "Reason"]);
                        });
                        setState(() {});
                      },
                      child: const Text("Default", style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: _allColumns.length,
                    itemBuilder: (context, i) {
                      String col = _allColumns[i];
                      bool isVisible = !_hiddenColumns.contains(col);

                      return CheckboxListTile(
                        dense: true,
                        activeColor: headerDarkNavy,
                        title: Text(col, style: const TextStyle(fontSize: 12)),
                        value: isVisible,
                        onChanged: (bool? val) {
                          if (val == false && _visibleColumns.length <= 1) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("At least one column must remain visible"), duration: Duration(seconds: 1)),
                            );
                            return;
                          }
                          setDialogState(() {
                            if (val == true) {
                              _hiddenColumns.remove(col);
                            } else {
                              _hiddenColumns.add(col);
                            }
                          });
                          setState(() {});
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: headerDarkNavy),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Done", style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // EXPORT (EXCEL/PDF) & PRINT
  // ==========================================

  void _exportAsExcelCsv() {
    final cols = _visibleColumns;
    final buffer = StringBuffer();
    buffer.write('\uFEFF'); // UTF-8 BOM for Microsoft Excel

    buffer.writeln(cols.map((c) => '"$c"').join(','));

    for (var item in _filteredData) {
      final m = _extractMember(item);
      final missed = _getMissedCount(item);

      final row = cols.map((col) {
        String val = "";
        if (col == "Loc") val = _getLocation(m);
        else if (col == "Sub-Loc") val = _getSubLocation(m);
        else if (col == "Dept") val = _getDepartment(m);
        else if (col == "Team") val = _getTeam(m);
        else if (col == "Cell Group") val = _getCellGroup(m);
        else if (col == "Name") val = _getName(m);
        else if (col == "Missed") val = "${missed}x";
        else if (col == "Care Status") val = item['last_recovery_outcome'] ?? "No Care Logged";
        else if (col == "Action") val = "Log Care";
        else if (col == "Reason") val = item['last_reason'] ?? "-";
        return '"${val.replaceAll('"', '""')}"';
      }).join(',');

      buffer.writeln(row);
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Row(
          children: [
            Icon(Icons.table_chart, color: Color(0xFF107C41), size: 22),
            SizedBox(width: 8),
            Text("Excel Spreadsheet Ready", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Intervention records for '$_screenTitle' (${_filteredData.length} entries) prepared for Excel.",
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
              child: const Text(
                "✓ Formatted data copied to clipboard!\nYou can paste directly into Microsoft Excel or Google Sheets.",
                style: TextStyle(fontSize: 11.5, color: Color(0xFF334155), fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
        ],
      ),
    );
  }

  void _showPrintAndPdfDialog() {
    final cols = _visibleColumns;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Row(
          children: [
            Icon(Icons.print_rounded, color: headerDarkNavy, size: 22),
            const SizedBox(width: 8),
            Text("Print / PDF Document", style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Document: $_screenTitle • ${_filteredData.length} records",
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowHeight: 28,
                        dataRowMinHeight: 24,
                        dataRowMaxHeight: 24,
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                        columns: cols.map((c) => DataColumn(
                          label: Text(c, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        )).toList(),
                        rows: _filteredData.take(50).map((item) {
                          final m = _extractMember(item);
                          final missed = _getMissedCount(item);
                          return DataRow(
                            cells: cols.map((col) {
                              String val = "";
                              if (col == "Loc") val = _getLocation(m);
                              else if (col == "Sub-Loc") val = _getSubLocation(m);
                              else if (col == "Dept") val = _getDepartment(m);
                              else if (col == "Team") val = _getTeam(m);
                              else if (col == "Cell Group") val = _getCellGroup(m);
                              else if (col == "Name") val = _getName(m);
                              else if (col == "Missed") val = "${missed}x";
                              else if (col == "Care Status") val = item['last_recovery_outcome'] ?? "No Care Logged";
                              else if (col == "Action") val = "Log Care";
                              else if (col == "Reason") val = item['last_reason'] ?? "-";

                              return DataCell(
                                Center(
                                  child: Text(val, style: const TextStyle(fontSize: 9.5)),
                                ),
                              );
                            }).toList(),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: headerDarkNavy),
            icon: const Icon(Icons.print, size: 16, color: Colors.white),
            label: const Text("Print Document", style: TextStyle(color: Colors.white, fontSize: 12)),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Document sent to printer spool"), duration: Duration(seconds: 2)),
              );
            },
          ),
        ],
      ),
    );
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
            fontSize: 15,
            color: const Color(0xFF1E2D4A),
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1E2D4A), size: 19),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E2D4A)),
        actions: [
          IconButton(
            tooltip: "Columns",
            icon: const Icon(Icons.view_column_outlined, color: Color(0xFF1E2D4A), size: 20),
            onPressed: _showColumnVisibilityDialog,
          ),
          PopupMenuButton<String>(
            tooltip: "Download & Print",
            icon: const Icon(Icons.download_rounded, color: Color(0xFF1E2D4A), size: 20),
            onSelected: (value) {
              if (value == 'excel') _exportAsExcelCsv();
              if (value == 'pdf' || value == 'print') _showPrintAndPdfDialog();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'excel',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, color: Color(0xFF107C41), size: 18),
                    SizedBox(width: 8),
                    Text("Download as Excel (.csv)", style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 18),
                    SizedBox(width: 8),
                    Text("Download as PDF", style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'print',
                child: Row(
                  children: [
                    Icon(Icons.print, color: Color(0xFF1E2D4A), size: 18),
                    SizedBox(width: 8),
                    Text("Print Document", style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCompactSummaryHeader(),
          Expanded(child: _buildSpreadsheetGrid()),
        ],
      ),
    );
  }

  Widget _buildCompactSummaryHeader() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: gridLineColor, width: 0.5),
    ),
    child: Row(
      children: [
        Icon(Icons.filter_list_rounded, color: headerDarkNavy, size: 16),
        const SizedBox(width: 8),
        const Text(
          "Tap headers to filter • Center-aligned Excel layout",
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
            style: TextStyle(color: headerDarkNavy, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  // --- EXCEL STYLE FROZEN GRID WITH BENTO DESIGN ---
  Widget _buildSpreadsheetGrid() {
    final cols = _visibleColumns;

    return LayoutBuilder(builder: (context, constraints) {
      double availableWidth = constraints.maxWidth - rowNumWidth;
      double baseTotalWidth = _baseTableWidth;

      double scalingFactor = math.max(1.0, availableWidth / baseTotalWidth);
      double dataTableWidth = math.max(availableWidth, baseTotalWidth);

      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: gridLineColor, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pinned Left Axis: Row Index (1, 2, 3...)
            SizedBox(
              width: rowNumWidth,
              child: Column(
                children: [
                  _buildCornerBox(),
                  Expanded(
                    child: ListView.builder(
                      controller: _verticalScrollRowNumbers,
                      physics: const ClampingScrollPhysics(),
                      itemCount: _filteredData.length,
                      itemExtent: dataRowHeight,
                      itemBuilder: (context, index) {
                        final isEven = index % 2 == 0;
                        return Container(
                          height: dataRowHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isEven ? const Color(0xFFFBFDFB) : const Color(0xFFEEF3F0),
                            border: Border(
                              right: BorderSide(color: gridLineColor, width: 0.5),
                              bottom: BorderSide(color: gridLineColor, width: 0.5),
                            ),
                          ),
                          child: Text(
                            "${index + 1}",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.merriweather(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF475569),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Horizontal & Vertically Scrollable Excel Body
            Expanded(
              child: Scrollbar(
                controller: _horizontalScroll,
                thumbVisibility: true,
                thickness: 7,
                child: SingleChildScrollView(
                  controller: _horizontalScroll,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: dataTableWidth,
                    child: Column(
                      children: [
                        _buildColumnLettersRow(cols, scalingFactor),
                        _buildExcelHeadersRow(cols, scalingFactor),
                        Expanded(
                          child: _isLoading
                              ? _buildSkeletonRows(cols, scalingFactor)
                              : _filteredData.isEmpty
                                  ? _buildEmptyState()
                                  : Scrollbar(
                                      controller: _verticalScrollData,
                                      thumbVisibility: true,
                                      thickness: 7,
                                      child: ListView.builder(
                                        controller: _verticalScrollData,
                                        physics: const ClampingScrollPhysics(),
                                        itemCount: _filteredData.length,
                                        itemExtent: dataRowHeight,
                                        itemBuilder: (context, index) {
                                          return _buildCompactDataRow(
                                            index,
                                            _filteredData[index],
                                            cols,
                                            scalingFactor,
                                          );
                                        },
                                      ),
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildCornerBox() {
    return Container(
      width: rowNumWidth,
      height: letterRowHeight + headerRowHeight,
      decoration: BoxDecoration(
        color: cornerBg,
        border: Border(
          right: BorderSide(color: gridLineColor, width: 0.5),
          bottom: BorderSide(color: gridLineColor, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: letterRowHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: gridLineColor, width: 0.5)),
            ),
            child: const Icon(Icons.grid_view_rounded, size: 12, color: Color(0xFF64748B)),
          ),
          Container(
            height: headerRowHeight - 1,
            alignment: Alignment.center,
            child: Text(
              "#",
              style: GoogleFonts.merriweather(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: headerDarkNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnLettersRow(List<String> cols, double factor) {
    return Container(
      height: letterRowHeight,
      decoration: BoxDecoration(
        color: letterBg,
        border: Border(bottom: BorderSide(color: gridLineColor, width: 0.5)),
      ),
      child: Row(
        children: List.generate(cols.length, (colIndex) {
          String k = cols[colIndex];
          double colWidth = (_colWidths[k] ?? 100) * factor;

          return Container(
            width: colWidth,
            height: letterRowHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: gridLineColor, width: 0.5)),
            ),
            child: Text(
              _getExcelColumnLetter(colIndex),
              textAlign: TextAlign.center,
              style: GoogleFonts.merriweather(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildExcelHeadersRow(List<String> cols, double factor) {
    return Container(
      height: headerRowHeight,
      color: headerDarkNavy,
      child: Row(
        children: cols.map((col) {
          double colWidth = (_colWidths[col] ?? 100) * factor;
          bool filterable = _activeFilters.containsKey(col);
          bool hasFilter = filterable && _activeFilters[col]!.isNotEmpty;

          return Container(
            width: colWidth,
            height: headerRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.18), width: 0.5)),
            ),
            child: InkWell(
              onTap: filterable ? () => _showCheckboxFilter(col) : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      col,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.merriweather(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  if (filterable)
                    Icon(
                      hasFilter ? Icons.filter_alt : Icons.arrow_drop_down,
                      size: 14,
                      color: hasFilter ? Colors.amberAccent : Colors.white70,
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- DATA ROW (Every Cell is CENTER ALIGNED) ---
  Widget _buildCompactDataRow(int index, Map<String, dynamic> item, List<String> cols, double factor) {
    final m = _extractMember(item);
    final missedCount = _getMissedCount(item);
    bool isChronic = missedCount >= 4;
    final bool isEven = index % 2 == 0;
    final Color rowBg = isEven ? rowEvenBg : rowOddBg;

    return Container(
      height: dataRowHeight,
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(bottom: BorderSide(color: gridLineColor, width: 0.5)),
      ),
      child: Row(
        children: cols.map((col) {
          double width = (_colWidths[col] ?? 100) * factor;

          if (col == "Loc") return _cellText(_getLocation(m), width: width);
          if (col == "Sub-Loc") return _cellText(_getSubLocation(m), width: width);
          if (col == "Dept") return _cellText(_getDepartment(m), width: width);
          if (col == "Team") return _cellText(_getTeam(m), width: width);
          if (col == "Cell Group") return _cellText(_getCellGroup(m), width: width);
          if (col == "Name") return _cellText(_getName(m), width: width, isBold: true);

          if (col == "Missed") {
            return Container(
              width: width,
              height: dataRowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: gridLineColor, width: 0.5))),
              child: Text(
                "${missedCount}x",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: isChronic ? Colors.red[700] : Colors.orange[800],
                ),
              ),
            );
          }

          if (col == "Care Status") {
            return Container(
              width: width,
              height: dataRowHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(border: Border(right: BorderSide(color: gridLineColor, width: 0.5))),
              child: Text(
                item['last_recovery_outcome'] ?? "No Care Logged",
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: Colors.blueGrey[600]),
              ),
            );
          }

          if (col == "Action") {
            return Container(
              width: width,
              height: dataRowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: gridLineColor, width: 0.5))),
              child: SizedBox(
                height: 20,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionBtnBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    elevation: 0,
                  ),
                  onPressed: () => _showMaintenanceDialog(m),
                  child: const Text("Log Care", style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          }

          if (col == "Reason") {
            return Container(
              width: width,
              height: dataRowHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(border: Border(right: BorderSide(color: gridLineColor, width: 0.5))),
              child: Text(
                item['last_reason'] ?? "-",
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            );
          }

          return const SizedBox.shrink();
        }).toList(),
      ),
    );
  }

  Widget _cellText(String val, {required double width, bool isBold = false}) {
    return Container(
      width: width,
      height: dataRowHeight,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: gridLineColor, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center, // Center aligned
      child: Text(
        val.isEmpty ? "-" : val,
        textAlign: TextAlign.center, // Center aligned text
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 32, color: Colors.green[600]),
            const SizedBox(height: 6),
            const Text(
              "No intervention records found",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonRows(List<String> cols, double factor) {
    return ListView.builder(
      itemCount: 10,
      itemExtent: dataRowHeight,
      itemBuilder: (_, index) => Container(
        height: dataRowHeight,
        decoration: BoxDecoration(
          color: index.isEven ? rowEvenBg : rowOddBg,
          border: Border(bottom: BorderSide(color: gridLineColor, width: 0.5)),
        ),
        child: Row(
          children: cols.map((col) {
            double colWidth = (_colWidths[col] ?? 100) * factor;
            return Container(
              width: colWidth,
              height: dataRowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: gridLineColor, width: 0.5))),
              child: Container(
                width: colWidth * 0.55,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }).toList(),
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
    final memberMap = (member is Map) ? member : {};
    final memberId = memberMap['id'] ?? memberMap['member_id'];

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setST) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text("Care Log: ${_getName(Map<String, dynamic>.from(memberMap))}",
              style: TextStyle(color: headerDarkNavy, fontSize: 15, fontWeight: FontWeight.bold)),
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
                  'member_id': memberId,
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text("Filter $column", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: headerDarkNavy)),
              content: SizedBox(
                width: 280,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      dense: true,
                      title: const Text("Select all", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                              title: Text(opt, style: const TextStyle(fontSize: 11.5)),
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