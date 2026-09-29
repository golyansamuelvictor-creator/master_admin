// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math';

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

  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScrollData = ScrollController();
  final ScrollController _verticalScrollRowNumbers = ScrollController();

  // --- ELEGANT GREEN PALETTE ---
  final Color appBarGreen = const Color(0xFF0E6333); // Deep premium forest green
  final Color headerGreen = const Color(0xFF107C41); // Classic rich spreadsheet green
  final Color letterBg = const Color(0xFFF1F5F9);    // Crisp column index gray
  final Color cornerBg = const Color(0xFFE2ECE5);    // Soft tinted corner
  final Color gridLineColor = const Color(0xFFE2E8F0);// Clean gridline
  final Color rowNumberBg = const Color(0xFFF8FAF9); // Clean row index background

  // Layout Heights & Widths
  final double letterRowHeight = 26.0;
  final double headerRowHeight = 42.0;
  final double dataRowHeight = 46.0;
  final double rowNumWidth = 46.0;

  @override
  void initState() {
    super.initState();
    _filteredData = widget.logs;

    // Synchronize vertical scrolling between frozen row index and main table
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
  // CATEGORY 1: MAPPING & DATA SCHEMAS
  // ==========================================

  String _getDisplayName(String key) {
    Map<String, String> mapping = {
      "location": "Location",
      "sub_location": "Sub-Location",
      "current_dept": "Department",
      "team_number": "Team",
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
    if (key == "english_name") return 200;
    if (key.contains("notes") || key.contains("strategy") || key.contains("schedule") || key.contains("solution")) {
      return 240;
    }
    if (["attendance_pre", "attendance_realtime", "attendance_makeup", "status_detail", "visitation_reason"].contains(key)) {
      return 155;
    }
    if (["location", "sub_location", "current_dept"].contains(key)) return 115;
    if (["team_number", "cell_number"].contains(key)) return 95;
    if (key == "duty") return 120;
    return 110;
  }

  List<String> _getDutyKeys() {
    List<String> base = ["location", "sub_location", "current_dept", "team_number", "cell_number", "english_name", "duty"];
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

  // ==========================================
  // CATEGORY 2: FILTERING LOGIC
  // ==========================================

  void _applyFilters() {
    setState(() {
      _filteredData = widget.logs.where((log) {
        final m = log['members'] ?? {};
        bool matches = true;
        _columnFilters.forEach((key, value) {
          if (value.trim().isEmpty) return;
          String dataValue = "";
          if (["location", "sub_location", "current_dept", "team_number", "cell_number", "english_name", "duty"].contains(key)) {
            dataValue = m[key]?.toString().toLowerCase() ?? "";
          } else {
            dataValue = log[key]?.toString().toLowerCase() ?? "";
          }
          if (!dataValue.contains(value.toLowerCase().trim())) matches = false;
        });
        return matches;
      }).toList();
    });
  }

  Map<String, int> _getUniqueValuesForColumn(String key) {
    Map<String, int> countMap = {};
    for (var log in widget.logs) {
      final m = log['members'] ?? {};
      dynamic raw = (["location", "sub_location", "current_dept", "team_number", "cell_number", "english_name", "duty"].contains(key))
          ? m[key]
          : log[key];
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
                  color: headerGreen,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.filter_alt, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Filter: $displayName",
                        style: GoogleFonts.merriweather(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 18),
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
                    Text("Search value:", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: filterController,
                      autofocus: true,
                      style: GoogleFonts.merriweather(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "Type text to match...",
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: filterController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  setDialogState(() {
                                    filterController.clear();
                                  });
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onChanged: (val) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Distinct Values (${uniqueValues.length}):",
                      style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.grey.shade50,
                      ),
                      child: ListView.separated(
                        itemCount: sortedKeys.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                    size: 15,
                                    color: isSelected ? headerGreen : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      valName,
                                      style: GoogleFonts.merriweather(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? headerGreen : Colors.black87,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text("($count)", style: GoogleFonts.merriweather(fontSize: 11, color: Colors.grey.shade600)),
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
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _columnFilters.remove(key);
                      _applyFilters();
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text("Clear", style: GoogleFonts.merriweather(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: headerGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  child: Text("Apply", style: GoogleFonts.merriweather(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // CATEGORY 3: MAIN VIEW & LAYOUT
  // ==========================================

 @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: appBarGreen,
        elevation: 1,
        centerTitle: true, // Centers the title above
        title: Text(
          widget.selectedDuty,
          textAlign: TextAlign.center,
          style: GoogleFonts.merriweather(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        actions: [
          if (_columnFilters.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white12,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                icon: const Icon(Icons.filter_alt_off, size: 14, color: Colors.white),
                label: Text(
                  "Reset (${_columnFilters.length})",
                  style: GoogleFonts.merriweather(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _columnFilters.clear();
                    _filteredData = widget.logs;
                  });
                },
              ),
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
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: gridLineColor))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _columnFilters.entries.map((entry) {
            return Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                border: Border.all(color: const Color(0xFFA5D6A7)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "${_getDisplayName(entry.key)}: \"${entry.value}\"",
                    style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: headerGreen),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _columnFilters.remove(entry.key);
                        _applyFilters();
                      });
                    },
                    child: const Icon(Icons.close, size: 13, color: Colors.black54),
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
  // CATEGORY 4: FROZEN GRID LAYOUT
  // ==========================================

  Widget _buildSpreadsheetGrid() {
    List<String> keys = _getDutyKeys();

    return LayoutBuilder(builder: (context, constraints) {
      double availableWidth = constraints.maxWidth - rowNumWidth;
      double baseTotalWidth = keys.fold(0.0, (prev, k) => prev + _getColWidth(k));

      double scalingFactor = max(1.0, availableWidth / baseTotalWidth);
      double dataTableWidth = max(availableWidth, baseTotalWidth);

      return Container(
        color: Colors.white,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----------------------------------------------------
            // 1. PINNED LEFT AXIS: Corner Cell & Row Numbers (1, 2, 3...)
            // ----------------------------------------------------
            SizedBox(
              width: rowNumWidth,
              child: Column(
                children: [
                  // Top-Left Corner Box
                  _buildCornerBox(),

                  // Row Numbers Column
                  Expanded(
                    child: ListView.builder(
                      controller: _verticalScrollRowNumbers,
                      physics: const ClampingScrollPhysics(),
                      itemCount: _filteredData.length,
                      itemExtent: dataRowHeight,
                      itemBuilder: (context, index) {
                        return Container(
                          height: dataRowHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: rowNumberBg,
                            border: Border(
                              right: BorderSide(color: gridLineColor),
                              bottom: BorderSide(color: gridLineColor),
                            ),
                          ),
                          child: Text(
                            "${index + 1}",
                            style: GoogleFonts.merriweather(
                              fontSize: 12,
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

            // ----------------------------------------------------
            // 2. HORIZONTALLY SCROLLABLE DATA BODY (Headers + Cells)
            // ----------------------------------------------------
            Expanded(
              child: Scrollbar(
                controller: _horizontalScroll,
                thumbVisibility: true,
                thickness: 8,
                child: SingleChildScrollView(
                  controller: _horizontalScroll,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: dataTableWidth,
                    child: Column(
                      children: [
                        // Row 1: Column Letters (A, B, C...)
                        _buildColumnLettersRow(keys, scalingFactor),

                        // Row 2: Rich Green Column Headers with Filter Funnels
                        _buildGreenHeadersRow(keys, scalingFactor),

                        // Data Grid
                        Expanded(
                          child: _filteredData.isEmpty
                              ? _buildEmptyState()
                              : Scrollbar(
                                  controller: _verticalScrollData,
                                  thumbVisibility: true,
                                  thickness: 8,
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

  // Top-Left Corner Box
  Widget _buildCornerBox() {
    return Container(
      width: rowNumWidth,
      height: letterRowHeight + headerRowHeight,
      decoration: BoxDecoration(
        color: cornerBg,
        border: Border(
          right: BorderSide(color: gridLineColor),
          bottom: BorderSide(color: gridLineColor),
        ),
      ),
      child: Column(
        children: [
          // Top Part (aligned with Column Letters)
          Container(
            height: letterRowHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: gridLineColor)),
            ),
            child: const Icon(Icons.grid_view_rounded, size: 14, color: Color(0xFF5B7065)),
          ),
          // Bottom Part (aligned with Green Headers)
          Container(
            height: headerRowHeight - 1,
            alignment: Alignment.center,
            child: Text(
              "#",
              style: GoogleFonts.merriweather(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2E5A44),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Column Index Row (A, B, C, D...)
  Widget _buildColumnLettersRow(List<String> keys, double factor) {
    return Container(
      height: letterRowHeight,
      decoration: BoxDecoration(
        color: letterBg,
        border: Border(bottom: BorderSide(color: gridLineColor)),
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
              border: Border(right: BorderSide(color: gridLineColor)),
            ),
            child: Text(
              _getExcelColumnLetter(colIndex),
              style: GoogleFonts.merriweather(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          );
        }),
      ),
    );
  }

  // Rich Green Header Row with White Titles & Filter Funnel Icons
  Widget _buildGreenHeadersRow(List<String> keys, double factor) {
    return Container(
      height: headerRowHeight,
      color: headerGreen,
      child: Row(
        children: keys.map((k) {
          double colWidth = _getColWidth(k) * factor;
          bool isFiltered = _columnFilters.containsKey(k) && _columnFilters[k]!.trim().isNotEmpty;

          return Container(
            width: colWidth,
            height: headerRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.22))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _getDisplayName(k),
                    style: GoogleFonts.merriweather(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
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
                      size: 15,
                      color: isFiltered ? const Color(0xFFFFD54F) : Colors.white70,
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

  // Spreadsheet Data Row
  Widget _buildDataRow(int rowIndex, dynamic log, List<String> keys, double factor) {
    final m = log['members'] ?? {};

    return Container(
      height: dataRowHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: gridLineColor)),
      ),
      child: Row(
        children: keys.map((k) {
          double colWidth = _getColWidth(k) * factor;

          dynamic val = (["location", "sub_location", "current_dept", "team_number", "cell_number", "english_name", "duty"].contains(k))
              ? m[k]
              : log[k];

          String sVal = (val ?? "").toString().trim();

          bool isAttendanceOrStatusCol = [
            "attendance_pre",
            "attendance_realtime",
            "attendance_makeup",
            "status_detail"
          ].contains(k);

          bool isCenteredCol = [
            "location",
            "sub_location",
            "current_dept",
            "team_number",
            "cell_number",
            "duty"
          ].contains(k);

          return Container(
            width: colWidth,
            height: dataRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: gridLineColor)),
            ),
            child: isAttendanceOrStatusCol
                ? Row(
                    children: [
                      Expanded(
                        child: Text(
                          sVal,
                          style: GoogleFonts.merriweather(fontSize: 13, color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 18, color: Colors.black38),
                    ],
                  )
                : Align(
                    alignment: isCenteredCol ? Alignment.center : Alignment.centerLeft,
                    child: Text(
                      sVal,
                      style: GoogleFonts.merriweather(
                        fontSize: 13,
                        color: k == "english_name" ? Colors.black : const Color(0xFF334155),
                        fontWeight: k == "english_name" ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          );
        }).toList(),
      ),
    );
  }

  // Empty state when search filters produce no matches
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            "No matching records found",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() {
                _columnFilters.clear();
                _filteredData = widget.logs;
              });
            },
            child: Text("Clear Filters", style: GoogleFonts.merriweather(color: headerGreen, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // Minimal Clean Footer showing record counts
  Widget _buildSummaryFooter() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: gridLineColor))),
      child: Row(
        children: [
          Text(
            "Total Records: ${_filteredData.length} of ${widget.logs.length}",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: headerGreen, fontSize: 12),
          ),
          const Spacer(),
          if (_columnFilters.isNotEmpty)
            Text(
              "${_columnFilters.length} filter(s) active",
              style: GoogleFonts.merriweather(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }
}