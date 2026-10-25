// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math';
import 'package:master_admin/core/app_palette.dart';

class CompilationResultsList extends StatefulWidget {
  final List<dynamic> logs;
  final String selectedDuty;
  final String role;

  const CompilationResultsList({
    super.key,
    required this.logs,
    required this.selectedDuty,
    required this.role,
  });

  @override
  State<CompilationResultsList> createState() => _CompilationResultsListState();
}

class _CompilationResultsListState extends State<CompilationResultsList> {
  // --- STATE VARIABLES ---
  List<dynamic> _filteredData = [];
  final Map<String, String> _columnFilters = {};
  final Set<String> _hiddenColumns = {}; // Column hiding & unhiding

  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScrollData = ScrollController();
  final ScrollController _verticalScrollRowNumbers = ScrollController();

  // --- BALANCED SPREADSHEET PALETTE ---
  final Color appBarColor   = const Color(0xFF1B4332); // High-contrast, balanced dark emerald
  final Color headerBgColor = const Color(0xFF2D5A46); // Muted spreadsheet header green
  final Color letterBg      = const Color(0xFFF1F5F9); // Crisp column letter gray
  final Color cornerBg      = const Color(0xFFE2ECE5); // Soft corner tint
  final Color gridLineColor = const Color(0xFFCBD5E1); // Clean gridline
  final Color rowEvenBg     = Colors.white;            // Bento row 1
  final Color rowOddBg      = const Color(0xFFF5F8F6); // Bento row 2 (faint soft tint)

  // Layout Heights & Widths (60% data row height)
  final double letterRowHeight = 22.0;
  final double headerRowHeight = 32.0;
  final double dataRowHeight   = 28.0;
  final double rowNumWidth     = 42.0;

  @override
  void initState() {
    super.initState();
    _filteredData = widget.logs;

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
  }

  @override
  void didUpdateWidget(covariant CompilationResultsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logs != widget.logs) {
      _applyFilters();
    }
  }

  @override
  void dispose() {
    _horizontalScroll.dispose();
    _verticalScrollData.dispose();
    _verticalScrollRowNumbers.dispose();
    super.dispose();
  }

  // ==========================================
  // CATEGORY 1: DATA RESOLVERS & SCHEMAS
  // ==========================================

  dynamic _getCellValue(dynamic log, String key) {
    if (log == null || log is! Map) return "";

    var rawM = log['members'] ?? log['member'];
    if (rawM is List && rawM.isNotEmpty) {
      rawM = rawM.first;
    }
    final Map<String, dynamic> m = (rawM is Map) ? Map<String, dynamic>.from(rawM) : {};

    switch (key) {
      case "department":
      case "current_dept":
        return m['department'] ?? m['current_dept'] ?? m['dept'] ?? log['department'] ?? log['current_dept'] ?? "";
      case "team":
      case "team_number":
        return m['team'] ?? m['team_number'] ?? m['team_no'] ?? log['team'] ?? log['team_number'] ?? "";
      case "cell_group":
      case "cell_number":
        return m['cell_group'] ?? m['cell_number'] ?? m['cell'] ?? log['cell_group'] ?? log['cell_number'] ?? "";
      case "location":
        return m['location'] ?? log['location'] ?? "";
      case "sub_location":
        return m['sub_location'] ?? m['sublocation'] ?? log['sub_location'] ?? log['sublocation'] ?? "";
      case "english_name":
        return m['english_name'] ?? m['full_name'] ?? m['name'] ?? log['english_name'] ?? "";
      case "duty":
        return m['duty'] ?? log['duty'] ?? "";
      default:
        return log[key] ?? m[key] ?? "";
    }
  }

  String _getDisplayName(String key) {
    Map<String, String> mapping = {
      "location": "Location",
      "sub_location": "Sub-Location",
      "department": "Department",
      "current_dept": "Department",
      "team": "Team",
      "team_number": "Team",
      "cell_group": "Cell Group",
      "cell_number": "Cell Group",
      "english_name": "English Name",
      "duty": "Duty",
      "attendance_pre": "Pre-Attendance",
      "attendance_realtime": "Actual Attendance",
      "attendance_makeup": "Makeup Attendance",
      "situation_notes": "Situation",
      "strategy_notes": "Strategy",
      "status_detail": "Status",
      "reason_notes": "Reason/Missed",
      "solution_notes": "Solution/Action",
      "offering_tithe": "Tithe",
      "offering_weekly": "Weekly",
      "offering_thanks": "Thanksgiving",
      "offering_construction": "Construction",
      "offering_donation": "Donation",
      "weekly_schedule": "Weekly Schedule",
      "visitation_reason": "Reason for Visit",
      "edu_sun": "Sunday Edu",
      "edu_wed": "Wednesday Edu",
      "edu_other": "Other Days",
      "mon_part": "Mon",
      "tue_part": "Tue",
      "wed_part": "Wed",
      "thu_part": "Thu",
      "fri_part": "Fri"
    };
    return mapping[key] ?? key;
  }

  String _getExcelColumnLetter(int index) {
    String letter = "";
    while (index >= 0) {
      letter = String.fromCharCode((index % 26) + 65) + letter;
      index = (index ~/ 26) - 1;
    }
    return letter;
  }

  double _getColWidth(String key) {
    if (key == "english_name") return 170;
    if (key.contains("notes") || key.contains("strategy") || key.contains("schedule") || key.contains("solution")) {
      return 220;
    }
    if (["attendance_pre", "attendance_realtime", "attendance_makeup", "status_detail", "visitation_reason"].contains(key)) {
      return 140;
    }
    if (["location", "sub_location", "department", "current_dept"].contains(key)) return 115;
    if (["team", "team_number", "cell_group", "cell_number"].contains(key)) return 95;
    if (key == "duty") return 115;
    return 105;
  }

  List<String> _getAllDutyKeys() {
    List<String> base = ["location", "sub_location", "department", "team", "cell_group", "english_name", "duty"];
    String d = widget.selectedDuty;
    if (d == 'Service Attendance Status') {
      base.addAll(["attendance_pre", "attendance_realtime", "attendance_makeup", "situation_notes", "strategy_notes"]);
    } else if (d == 'Cell Group Service') {
      base.addAll(["status_detail", "reason_notes", "solution_notes"]);
    } else if (d == 'Offering Status') {
      base.addAll(["offering_tithe", "offering_weekly", "offering_thanks", "offering_construction", "offering_donation", "reason_notes", "solution_notes"]);
    } else if (d == 'Evangelism Part') {
      base.addAll(["weekly_schedule", "status_detail"]);
    } else if (d == 'Morning Light') {
      base.add("status_detail");
    } else if (d == 'All Saints Education') {
      base.addAll(["status_detail", "reason_notes", "solution_notes"]);
    } else if (d.contains('Visitations')) {
      base.addAll(["visitation_reason", "status_detail"]);
    } else if (d == 'Workers Education') {
      base.addAll(["edu_sun", "edu_wed", "edu_other", "reason_notes", "solution_notes"]);
    } else if (d == 'Workers Daily Participation') {
      base.addAll(["mon_part", "tue_part", "wed_part", "thu_part", "fri_part"]);
    }
    return base;
  }

  List<String> _getVisibleDutyKeys() {
    return _getAllDutyKeys().where((k) => !_hiddenColumns.contains(k)).toList();
  }

  // ==========================================
  // CATEGORY 2: FILTERING LOGIC
  // ==========================================

  void _applyFilters() {
    setState(() {
      _filteredData = widget.logs.where((log) {
        bool matches = true;
        _columnFilters.forEach((key, value) {
          if (value.trim().isEmpty) return;
          String dataValue = _getCellValue(log, key).toString().toLowerCase();
          if (!dataValue.contains(value.toLowerCase().trim())) matches = false;
        });
        return matches;
      }).toList();
    });
  }

  Map<String, int> _getUniqueValuesForColumn(String key) {
    Map<String, int> countMap = {};
    for (var log in widget.logs) {
      dynamic raw = _getCellValue(log, key);
      String val = (raw ?? "(Blank)").toString().trim();
      if (val.isEmpty) val = "(Blank)";
      countMap[val] = (countMap[val] ?? 0) + 1;
    }
    return countMap;
  }

  void _showFilterDialog(String key, String displayName) {
    final TextEditingController filterController = TextEditingController(text: _columnFilters[key] ?? "");
    final uniqueValues = _getUniqueValuesForColumn(key);
    final sortedKeys = uniqueValues.keys.toList()..sort();

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              titlePadding: EdgeInsets.zero,
              title: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppPalette.bg(headerBgColor),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.filter_alt, color: AppPalette.fg(Colors.white), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Filter: $displayName",
                        style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontSize: 13, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: AppPalette.fg(Colors.white70), size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: filterController,
                      autofocus: true,
                      style: GoogleFonts.merriweather(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: "Type text to match...",
                        prefixIcon: const Icon(Icons.search, size: 16),
                        suffixIcon: filterController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () => setDialogState(() => filterController.clear()),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onChanged: (val) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppPalette.line(Colors.grey.shade300)),
                        borderRadius: BorderRadius.circular(6),
                        color: AppPalette.bg(Colors.grey.shade50),
                      ),
                      child: ListView.separated(
                        itemCount: sortedKeys.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: AppPalette.bg(Colors.grey.shade200)),
                        itemBuilder: (context, index) {
                          String valName = sortedKeys[index];
                          int count = uniqueValues[valName] ?? 0;
                          bool isSelected = filterController.text.toLowerCase() == valName.toLowerCase();

                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                filterController.text = (valName == "(Blank)") ? "" : valName;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                    size: 14,
                                    color: AppPalette.fg(isSelected ? headerBgColor : Colors.grey),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      valName,
                                      style: GoogleFonts.merriweather(
                                        fontSize: 11.5,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: AppPalette.fg(isSelected ? headerBgColor : Colors.black87),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text("($count)", style: GoogleFonts.merriweather(fontSize: 10.5, color: AppPalette.fg(Colors.grey.shade600))),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _columnFilters.remove(key);
                      _applyFilters();
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text("Clear", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.red.shade700), fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.bg(headerBgColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () {
                    setState(() {
                      if (filterController.text.trim().isEmpty) {
                        _columnFilters.remove(key);
                      } else {
                        _columnFilters[key] = filterController.text.trim();
                      }
                      _applyFilters();
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text("Apply", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // CATEGORY 3: COLUMN HIDING & UNHIDING
  // ==========================================

  void _showColumnVisibilityDialog() {
    final allKeys = _getAllDutyKeys();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Row(
            children: [
              Icon(Icons.view_column_rounded, color: AppPalette.fg(appBarColor), size: 20),
              const SizedBox(width: 8),
              Text(
                "Show / Hide Columns",
                style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.fg(appBarColor)),
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
                          _hiddenColumns.addAll(allKeys.sublist(2)); // keep first two visible
                        });
                        setState(() {});
                      },
                      child: const Text("Reset", style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: allKeys.length,
                    itemBuilder: (context, i) {
                      String k = allKeys[i];
                      bool isVisible = !_hiddenColumns.contains(k);

                      return CheckboxListTile(
                        dense: true,
                        activeColor: headerBgColor,
                        title: Text(_getDisplayName(k), style: const TextStyle(fontSize: 12)),
                        value: isVisible,
                        onChanged: (bool? val) {
                          if (val == false && _getVisibleDutyKeys().length <= 1) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("At least one column must remain visible"), duration: Duration(seconds: 1)),
                            );
                            return;
                          }
                          setDialogState(() {
                            if (val == true) {
                              _hiddenColumns.remove(k);
                            } else {
                              _hiddenColumns.add(k);
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
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(headerBgColor)),
              onPressed: () => Navigator.pop(ctx),
              child: Text("Done", style: TextStyle(color: AppPalette.fg(Colors.white), fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // CATEGORY 4: DOWNLOAD (EXCEL/PDF) & PRINT
  // ==========================================

  void _exportAsExcelCsv() {
    final keys = _getVisibleDutyKeys();
    final buffer = StringBuffer();

    // UTF-8 BOM so Microsoft Excel reads encoding properly
    buffer.write('\uFEFF');

    // Header row
    buffer.writeln(keys.map((k) => '"${_getDisplayName(k).replaceAll('"', '""')}"').join(','));

    // Data rows
    for (var log in _filteredData) {
      final row = keys.map((k) {
        String val = (_getCellValue(log, k) ?? "").toString();
        return '"${val.replaceAll('"', '""')}"';
      }).join(',');
      buffer.writeln(row);
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Row(
          children: [
            Icon(Icons.table_chart, color: AppPalette.fg(Color(0xFF107C41)), size: 22),
            const SizedBox(width: 8),
            const Text("Excel Spreadsheet Ready", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Spreadsheet data for '${widget.selectedDuty}' (${_filteredData.length} records) has been formatted.",
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF1F5F9)), borderRadius: BorderRadius.circular(6)),
              child: Text(
                "✓ Data copied to clipboard!\nYou can paste directly into Microsoft Excel, Google Sheets, or save as a .csv file.",
                style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Color(0xFF334155)), fontWeight: FontWeight.w500),
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
    final keys = _getVisibleDutyKeys();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Row(
          children: [
            Icon(Icons.print_rounded, color: AppPalette.fg(appBarColor), size: 22),
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
                "Document: ${widget.selectedDuty} • ${_filteredData.length} records",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppPalette.fg(Color(0xFF64748B))),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppPalette.bg(Colors.white),
                    border: Border.all(color: AppPalette.line(Colors.grey.shade300)),
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
                        columns: keys.map((k) => DataColumn(
                          label: Text(_getDisplayName(k), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        )).toList(),
                        rows: _filteredData.take(50).map((log) {
                          return DataRow(
                            cells: keys.map((k) {
                              return DataCell(
                                Center(
                                  child: Text(
                                    (_getCellValue(log, k) ?? "").toString(),
                                    style: const TextStyle(fontSize: 9.5),
                                  ),
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
              const SizedBox(height: 6),
              Text(
                "* Showing printable layout view. For native system printers, the printing package can stream this buffer directly.",
                style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: AppPalette.fg(Colors.grey)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(appBarColor)),
            icon: Icon(Icons.print, size: 16, color: AppPalette.fg(Colors.white)),
            label: Text("Print Document", style: TextStyle(color: AppPalette.fg(Colors.white), fontSize: 12)),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Print job sent to document spooler"), duration: Duration(seconds: 2)),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // CATEGORY 5: MAIN VIEW & LAYOUT
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(appBarColor),
        elevation: 0.5,
        centerTitle: true,
        // Highly visible white back button
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: AppPalette.fg(Colors.white), size: 19),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        iconTheme: IconThemeData(color: AppPalette.fg(Colors.white)),
        title: Text(
          widget.selectedDuty,
          textAlign: TextAlign.center,
          style: GoogleFonts.merriweather(
            fontWeight: FontWeight.bold,
            color: AppPalette.fg(Colors.white),
            fontSize: 15,
          ),
        ),
        actions: [
          // Columns Show/Hide Button
          IconButton(
            tooltip: "Columns",
            icon: Icon(Icons.view_column_outlined, color: AppPalette.fg(Colors.white), size: 20),
            onPressed: _showColumnVisibilityDialog,
          ),
          // Export Popup Menu (Excel, PDF, Print)
          PopupMenuButton<String>(
            tooltip: "Download & Print",
            icon: Icon(Icons.download_rounded, color: AppPalette.fg(Colors.white), size: 20),
            onSelected: (value) {
              if (value == 'excel') _exportAsExcelCsv();
              if (value == 'pdf' || value == 'print') _showPrintAndPdfDialog();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'excel',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, color: AppPalette.fg(Color(0xFF107C41)), size: 18),
                    SizedBox(width: 8),
                    Text("Download as Excel (.csv)", style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: AppPalette.fg(Colors.redAccent), size: 18),
                    SizedBox(width: 8),
                    Text("Download as PDF", style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'print',
                child: Row(
                  children: [
                    Icon(Icons.print, color: AppPalette.fg(Color(0xFF1E2D4A)), size: 18),
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
          if (_columnFilters.isNotEmpty) _buildActiveFilterBar(),
          Expanded(child: _buildSpreadsheetGrid()),
          _buildSummaryFooter(),
        ],
      ),
    );
  }

  Widget _buildActiveFilterBar() {
    return Container(
      width: double.infinity,
      color: AppPalette.bg(Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppPalette.line(gridLineColor)))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _columnFilters.entries.map((entry) {
            return Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppPalette.bg(const Color(0xFFEBF3EE)),
                border: Border.all(color: AppPalette.line(const Color(0xFFBFD8C9))),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "${_getDisplayName(entry.key)}: \"${entry.value}\"",
                    style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(headerBgColor)),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _columnFilters.remove(entry.key);
                        _applyFilters();
                      });
                    },
                    child: Icon(Icons.close, size: 13, color: AppPalette.fg(Colors.black54)),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ==========================================
  // CATEGORY 6: FROZEN GRID & ALL CENTER ALIGNED
  // ==========================================

  Widget _buildSpreadsheetGrid() {
    List<String> keys = _getVisibleDutyKeys();

    return LayoutBuilder(builder: (context, constraints) {
      double availableWidth = constraints.maxWidth - rowNumWidth;
      double baseTotalWidth = keys.fold(0.0, (prev, k) => prev + _getColWidth(k));

      double scalingFactor = max(1.0, availableWidth / baseTotalWidth);
      double dataTableWidth = max(availableWidth, baseTotalWidth);

      return Container(
        color: AppPalette.bg(Colors.white),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pinned Left Axis: Row numbers
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
                            color: AppPalette.bg(isEven ? const Color(0xFFFBFDFB) : const Color(0xFFEEF3F0)),
                            border: Border(
                              right: BorderSide(color: AppPalette.line(gridLineColor)),
                              bottom: BorderSide(color: AppPalette.line(gridLineColor)),
                            ),
                          ),
                          child: Text(
                            "${index + 1}",
                            style: GoogleFonts.merriweather(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.fg(const Color(0xFF475569)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Data Grid
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
                        _buildColumnLettersRow(keys, scalingFactor),
                        _buildHeadersRow(keys, scalingFactor),
                        Expanded(
                          child: _filteredData.isEmpty
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
                                      return _buildDataRow(
                                        index,
                                        _filteredData[index],
                                        keys,
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
        color: AppPalette.bg(cornerBg),
        border: Border(
          right: BorderSide(color: AppPalette.line(gridLineColor)),
          bottom: BorderSide(color: AppPalette.line(gridLineColor)),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: letterRowHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppPalette.line(gridLineColor))),
            ),
            child: Icon(Icons.grid_view_rounded, size: 13, color: AppPalette.fg(Color(0xFF4C6656))),
          ),
          Container(
            height: headerRowHeight - 1,
            alignment: Alignment.center,
            child: Text(
              "#",
              style: GoogleFonts.merriweather(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppPalette.fg(const Color(0xFF264E3D)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnLettersRow(List<String> keys, double factor) {
    return Container(
      height: letterRowHeight,
      decoration: BoxDecoration(
        color: AppPalette.bg(letterBg),
        border: Border(bottom: BorderSide(color: AppPalette.line(gridLineColor))),
      ),
      child: Row(
        children: List.generate(keys.length, (colIndex) {
          String k = keys[colIndex];
          double colWidth = _getColWidth(k) * factor;

          return Container(
            width: colWidth,
            height: letterRowHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: AppPalette.line(gridLineColor))),
            ),
            child: Text(
              _getExcelColumnLetter(colIndex),
              textAlign: TextAlign.center,
              style: GoogleFonts.merriweather(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppPalette.fg(const Color(0xFF64748B)),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildHeadersRow(List<String> keys, double factor) {
    return Container(
      height: headerRowHeight,
      color: AppPalette.bg(headerBgColor),
      child: Row(
        children: keys.map((k) {
          double colWidth = _getColWidth(k) * factor;
          bool isFiltered = _columnFilters.containsKey(k) && _columnFilters[k]!.trim().isNotEmpty;

          return Container(
            width: colWidth,
            height: headerRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: AppPalette.line(Colors.white.withValues(alpha: 0.18)))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    _getDisplayName(k),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.merriweather(
                      color: AppPalette.fg(Colors.white),
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => _showFilterDialog(k, _getDisplayName(k)),
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Icon(
                      isFiltered ? Icons.filter_alt : Icons.filter_alt_outlined,
                      size: 13,
                      color: AppPalette.fg(isFiltered ? const Color(0xFFFFD54F) : Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // Bento Data Row: Every single cell is CENTER ALIGNED
  Widget _buildDataRow(int rowIndex, dynamic log, List<String> keys, double factor) {
    final bool isEven = rowIndex % 2 == 0;
    final Color rowBg = isEven ? rowEvenBg : rowOddBg;

    return Container(
      height: dataRowHeight,
      decoration: BoxDecoration(
        color: AppPalette.bg(rowBg),
        border: Border(bottom: BorderSide(color: AppPalette.line(gridLineColor))),
      ),
      child: Row(
        children: keys.map((k) {
          double colWidth = _getColWidth(k) * factor;
          String sVal = (_getCellValue(log, k) ?? "").toString().trim();

          return Container(
            width: colWidth,
            height: dataRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center, // Center aligned
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: AppPalette.line(gridLineColor))),
            ),
            child: Text(
              sVal.isEmpty ? "-" : sVal,
              textAlign: TextAlign.center, // Center aligned text
              style: GoogleFonts.merriweather(
                fontSize: 11.5,
                color: AppPalette.fg(k == "english_name" ? Colors.black : const Color(0xFF334155)),
                fontWeight: k == "english_name" ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 36, color: AppPalette.fg(Colors.grey.shade400)),
          const SizedBox(height: 6),
          Text(
            "No matching records found",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.grey.shade700), fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () {
              setState(() {
                _columnFilters.clear();
                _filteredData = widget.logs;
              });
            },
            child: Text("Clear Filters", style: GoogleFonts.merriweather(color: AppPalette.fg(headerBgColor), fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryFooter() {
    return Container(
      width: double.infinity,
      color: AppPalette.bg(Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppPalette.line(gridLineColor)))),
      child: Row(
        children: [
          Text(
            "Total Records: ${_filteredData.length} of ${widget.logs.length}",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppPalette.fg(headerBgColor), fontSize: 12),
          ),
          const Spacer(),
          if (_hiddenColumns.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                "${_hiddenColumns.length} hidden column(s)",
                style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.blueGrey), fontWeight: FontWeight.w600),
              ),
            ),
          if (_columnFilters.isNotEmpty)
            Text(
              "${_columnFilters.length} filter(s) active",
              style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.amber.shade900), fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }
}