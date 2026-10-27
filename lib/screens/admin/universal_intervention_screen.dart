// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/absentee_logic.dart';
import '../../core/table_export.dart';
import 'package:master_admin/core/app_palette.dart';
import 'package:flutter/services.dart';
import '../../widgets/app_menus.dart';

class UniversalInterventionScreen extends StatefulWidget {
  final String duty;
  final String unitName;
  final String? buttonTitle;
  /// The leader's unit path ({location, sub_location, department, team,
  /// cell_group}, only the role's levels); {} = whole church.
  final Map<String, String>? scope;
  /// Church-wide group (장년회, 부녀회 ...) for group leaders.
  final String? group;

  const UniversalInterventionScreen({
    super.key,
    required this.duty,
    required this.unitName,
    this.buttonTitle,
    this.scope,
    this.group,
  });

  @override
  State<UniversalInterventionScreen> createState() => _UniversalInterventionScreenState();
}

class _UniversalInterventionScreenState extends State<UniversalInterventionScreen> {
  final Color headerDarkNavy   = const Color(0xFF1E2D4A);
  final Color actionBtnBlue    = const Color(0xFF2B4C7E);
  final Color gridLineColor    = const Color(0xFFCBD5E1);
  final Color letterBg         = const Color(0xFFF1F5F9);
  final Color cornerBg         = const Color(0xFFE2E8F0);
  final Color rowEvenBg        = Colors.white;
  final Color rowOddBg         = const Color(0xFFF6F9FD);

  final double letterRowHeight = 22.0;
  final double headerRowHeight = 32.0;
  final double dataRowHeight   = 30.0;
  final double rowNumWidth     = 42.0;

  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScrollData = ScrollController();
  final ScrollController _verticalScrollRowNumbers = ScrollController();

  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoading = true;
  String _screenTitle = "";
  final Set<String> _hiddenColumns = {};

  // Period / Date Range (Default: Last 30 Days)
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String _periodLabel = "Last 30 Days";

  // Selected Service Style per member { memberId: 'In-person' }
  final Map<String, String> _memberSelectedStyle = {};
  String _globalStyleFilter = "All Styles";
  String _searchQuery = "";
  List<String> _allDutyStyles = [];

  final Map<String, Set<String>> _activeFilters = {
    "Loc": {},
    "Sub-Loc": {},
    "Dept": {},
    "Team": {},
    "Cell Group": {},
    "Name": {},
    "Service Style": {},
    "Missed": {},
  };

  final Map<String, double> _colWidths = {
    "Loc": 85,
    "Sub-Loc": 95,
    "Dept": 95,
    "Team": 80,
    "Cell Group": 105,
    "Name": 140,
    "Service Style": 135, // Column before Missed
    "Style Count": 90,    // Times attended in that style
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
    "Service Style",
    "Style Count",
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
    _screenTitle = _formatToTitleCase(widget.buttonTitle ?? widget.duty);

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
      final res = await AbsenteeLogic.getDetailedInterventionList(
        duty: widget.duty,
        unitName: widget.unitName,
        scope: widget.scope,
        group: widget.group,
        startDate: _startDate,
        endDate: _endDate,
      );

      final Set<String> distinctStyles = {"All Styles"};

      for (var item in res) {
        final m = _extractMember(item);
        final mid = m['id']?.toString() ?? "";
        final List<dynamic> styles = item['service_styles'] ?? [];
        final List<dynamic> dutyStyles = item['all_duty_styles'] ?? [];

        for (var s in dutyStyles) distinctStyles.add(s.toString());
        for (var s in styles) distinctStyles.add(s.toString());

        // Default to the first style or "In-person"
        if (!_memberSelectedStyle.containsKey(mid) && styles.isNotEmpty) {
          _memberSelectedStyle[mid] = styles.first.toString();
        }
      }

      if (mounted) {
        setState(() {
          _data = res;
          _filteredData = res;
          _allDutyStyles = distinctStyles.toList();
          _isLoading = false;
        });
        _applyFilters();
      }
    } catch (e) {
      debugPrint("Error loading intervention list: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

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

  String _getLocation(Map<String, dynamic> m) => (m['location'] ?? "").toString();
  String _getSubLocation(Map<String, dynamic> m) => (m['sub_location'] ?? "").toString();
  String _getDepartment(Map<String, dynamic> m) => (m['department'] ?? "").toString();
  String _getTeam(Map<String, dynamic> m) => (m['team'] ?? "").toString();
  String _getCellGroup(Map<String, dynamic> m) => (m['cell_group'] ?? "").toString();
  String _getName(Map<String, dynamic> m) => (m['english_name'] ?? m['full_name'] ?? "").toString();

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(colorScheme: ColorScheme.light(primary: headerDarkNavy)),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _periodLabel = "${DateFormat('MMM d').format(_startDate)} - ${DateFormat('MMM d').format(_endDate)}";
      });
      _load();
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredData = _data.where((item) {
        final m = _extractMember(item);
        final mid = m['id']?.toString() ?? "";
        final missedCount = _getMissedCount(item);
        final selectedStyle = _memberSelectedStyle[mid] ?? "None";

        final name = _getName(m).toLowerCase();
        if (_searchQuery.isNotEmpty && !name.contains(_searchQuery.toLowerCase())) {
          return false;
        }

        if (_globalStyleFilter != "All Styles" && selectedStyle != _globalStyleFilter) {
          final List<dynamic> styles = item['service_styles'] ?? [];
          if (!styles.contains(_globalStyleFilter)) return false;
        }

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
               matches("Service Style", selectedStyle) &&
               matches("Missed", "$missedCount Times");
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): _load,
        ...officeKeys({
          LogicalKeyboardKey.keyP: () => TableExport.preview(context, _interventionTable()),
          LogicalKeyboardKey.keyD: _pickDateRange,
        }, ctrlShift: {
          LogicalKeyboardKey.keyE: _exportAsExcelCsv,
        }),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        title: Text(
          _screenTitle,
          style: GoogleFonts.merriweather(fontWeight: FontWeight.w800, fontSize: 15, color: AppPalette.fg(const Color(0xFF1E2D4A))),
        ),
        centerTitle: true,
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: AppPalette.fg(Color(0xFF1E2D4A)), size: 19),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: tr("Columns"),
            icon: Icon(Icons.view_column_outlined, color: AppPalette.fg(Color(0xFF1E2D4A)), size: 20),
            onPressed: _showColumnVisibilityDialog,
          ),
          IconButton(
            tooltip: tr("Export Excel"),
            icon: Icon(Icons.file_download_outlined, color: AppPalette.fg(Color(0xFF1E2D4A)), size: 20),
            onPressed: _exportAsExcelCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          // Divided Top Bar: Period Calendar (Left) | Search & Style Dropdown (Right)
          _buildDividedTopBar(),
          Expanded(child: _buildSpreadsheetGrid()),
        ],
      ),
        ),
      ),
    );
  }

  void _rowMenu(Offset pos, Map<String, dynamic> item, List<String> cols) {
    final m = _extractMember(item);
    final name = _getName(m);
    showOfficeMenu(context, pos, [
      OfficeMenuItem("Log care for $name", icon: Icons.volunteer_activism_outlined, onTap: () => _showMaintenanceDialog(m)),
      const OfficeMenuItem.divider(),
      OfficeMenuItem("Copy name", icon: Icons.content_copy, onTap: () => Clipboard.setData(ClipboardData(text: name))),
      OfficeMenuItem("Copy row", icon: Icons.table_rows_outlined, onTap: () {
        final t = _interventionTable();
        final i = _filteredData.indexOf(item);
        if (i >= 0 && i < t.rows.length) Clipboard.setData(ClipboardData(text: t.rows[i].join('\t')));
      }),
      const OfficeMenuItem.divider(),
      OfficeMenuItem("Columns…", icon: Icons.view_column_outlined, onTap: _showColumnVisibilityDialog),
      OfficeMenuItem("Change period…", icon: Icons.date_range_outlined, shortcut: "Ctrl+D", onTap: _pickDateRange),
      OfficeMenuItem("Reload", icon: Icons.refresh_rounded, shortcut: "F5", onTap: _load),
      OfficeMenuItem("Download Excel / PDF", icon: Icons.file_download_outlined, shortcut: "Ctrl+Shift+E", onTap: _exportAsExcelCsv),
      OfficeMenuItem("Print…", icon: Icons.print_rounded, shortcut: "Ctrl+P", onTap: () => TableExport.preview(context, _interventionTable())),
    ]);
  }

  Widget _buildDividedTopBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.line(gridLineColor), width: 0.6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Row(
        children: [
          // LEFT HALF: Period / Date Calendar Selector
          Expanded(
            flex: 1,
            child: InkWell(
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppPalette.bg(headerDarkNavy.withValues(alpha: 0.06)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppPalette.line(headerDarkNavy.withValues(alpha: 0.2))),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, size: 15, color: AppPalette.fg(headerDarkNavy)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Period: $_periodLabel",
                        style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(headerDarkNavy)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 16),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // RIGHT HALF: Search + Global Style Dropdown Filter
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: tr("Search name..."),
                        hintStyle: const TextStyle(fontSize: 11),
                        prefixIcon: const Icon(Icons.search, size: 15),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onChanged: (q) {
                        _searchQuery = q;
                        _applyFilters();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 32,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _allDutyStyles.contains(_globalStyleFilter) ? _globalStyleFilter : "All Styles",
                      isDense: true,
                      style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.black87), fontWeight: FontWeight.bold),
                      items: _allDutyStyles.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) {
                        setState(() => _globalStyleFilter = v ?? "All Styles");
                        _applyFilters();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.line(gridLineColor), width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row Number Column
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
                              right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5),
                              bottom: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5),
                            ),
                          ),
                          child: Text("${index + 1}", style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppPalette.fg(const Color(0xFF475569)))),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Data Pane
            Expanded(
              child: Scrollbar(
                controller: _horizontalScroll,
                thumbVisibility: true,
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
                              ? const Center(child: CircularProgressIndicator())
                              : _filteredData.isEmpty
                                  ? const Center(child: Text("No intervention records found for this period."))
                                  : ListView.builder(
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
          right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5),
          bottom: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: letterRowHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
            child: Icon(Icons.grid_view_rounded, size: 12, color: AppPalette.fg(Color(0xFF64748B))),
          ),
          Container(
            height: headerRowHeight - 1,
            alignment: Alignment.center,
            child: Text("#", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(headerDarkNavy))),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnLettersRow(List<String> cols, double factor) {
    return Container(
      height: letterRowHeight,
      decoration: BoxDecoration(color: AppPalette.bg(letterBg), border: Border(bottom: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
      child: Row(
        children: List.generate(cols.length, (i) {
          String k = cols[i];
          double colWidth = (_colWidths[k] ?? 100) * factor;
          return Container(
            width: colWidth,
            height: letterRowHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border(right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
            child: Text(_getExcelColumnLetter(i), style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.w600, color: AppPalette.fg(const Color(0xFF64748B)))),
          );
        }),
      ),
    );
  }

  Widget _buildExcelHeadersRow(List<String> cols, double factor) {
    return Container(
      height: headerRowHeight,
      color: AppPalette.bg(headerDarkNavy),
      child: Row(
        children: cols.map((col) {
          double colWidth = (_colWidths[col] ?? 100) * factor;
          bool filterable = _activeFilters.containsKey(col);
          bool hasFilter = filterable && _activeFilters[col]!.isNotEmpty;

          return Container(
            width: colWidth,
            height: headerRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(border: Border(right: BorderSide(color: AppPalette.line(Colors.white.withValues(alpha: 0.18)), width: 0.5))),
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
                      style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                  ),
                  if (filterable)
                    Icon(
                      hasFilter ? Icons.filter_alt : Icons.arrow_drop_down,
                      size: 14,
                      color: AppPalette.fg(hasFilter ? Colors.amberAccent : Colors.white70),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCompactDataRow(int index, Map<String, dynamic> item, List<String> cols, double factor) {
    final m = _extractMember(item);
    final mid = m['id']?.toString() ?? "";
    final missedCount = _getMissedCount(item);
    final List<dynamic> memberStyles = item['service_styles'] ?? [];
    final Map<String, dynamic> styleCounts = item['style_counts'] ?? {};

    // Current selected service style for this member (populated from entry_field_options)
    String currentStyle = _memberSelectedStyle[mid] ?? (memberStyles.isNotEmpty ? memberStyles.first.toString() : "Standard");
    int countForCurrentStyle = (styleCounts[currentStyle] ?? 0) as int;

    final bool isEven = index % 2 == 0;
    final Color rowBg = isEven ? rowEvenBg : rowOddBg;

    return OfficeRightClick(
      longPress: true,
      onMenu: (p) => _rowMenu(p, item, cols),
      child: Container(
      height: dataRowHeight,
      decoration: BoxDecoration(color: AppPalette.bg(rowBg), border: Border(bottom: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
      child: Row(
        children: cols.map((col) {
          double width = (_colWidths[col] ?? 100) * factor;

          if (col == "Loc") return _cellText(_getLocation(m), width: width);
          if (col == "Sub-Loc") return _cellText(_getSubLocation(m), width: width);
          if (col == "Dept") return _cellText(_getDepartment(m), width: width);
          if (col == "Team") return _cellText(_getTeam(m), width: width);
          if (col == "Cell Group") return _cellText(_getCellGroup(m), width: width);
          if (col == "Name") return _cellText(_getName(m), width: width, isBold: true);

          // NEW COLUMN 1: SERVICE STYLE (Dropdown of official options from entry_field_options)
          if (col == "Service Style") {
            return Container(
              width: width,
              height: dataRowHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(border: Border(right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
              child: memberStyles.isEmpty
                  ? Text("-", style: TextStyle(fontSize: 10, color: AppPalette.fg(Colors.grey)))
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: memberStyles.contains(currentStyle) ? currentStyle : memberStyles.first.toString(),
                        isDense: true,
                        isExpanded: true,
                        iconSize: 13,
                        style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.black87), fontWeight: FontWeight.bold),
                        items: memberStyles.map((s) => DropdownMenuItem(value: s.toString(), child: Center(child: Text(s.toString(), overflow: TextOverflow.ellipsis)))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _memberSelectedStyle[mid] = val;
                            });
                          }
                        },
                      ),
                    ),
            );
          }

          // NEW COLUMN 2: STYLE COUNT (Counts how many times of the selected style they attended)
          if (col == "Style Count") {
            return Container(
              width: width,
              height: dataRowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppPalette.bg(countForCurrentStyle > 0 ? Colors.blue.shade50 : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "${countForCurrentStyle}x",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppPalette.fg(countForCurrentStyle > 0 ? Colors.blue[900] : Colors.grey[600]),
                  ),
                ),
              ),
            );
          }

          if (col == "Missed") {
            return Container(
              width: width,
              height: dataRowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
              child: Text(
                "${missedCount}x",
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(missedCount >= 4 ? Colors.red[700] : Colors.orange[800])),
              ),
            );
          }

          if (col == "Care Status") {
            return Container(
              width: width,
              height: dataRowHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(border: Border(right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
              child: Text(item['last_recovery_outcome'] ?? "No Care Logged", overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: AppPalette.fg(Colors.blueGrey[600]))),
            );
          }

          if (col == "Action") {
            return Container(
              width: width,
              height: dataRowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
              child: SizedBox(
                height: 20,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(actionBtnBlue), padding: const EdgeInsets.symmetric(horizontal: 6), elevation: 0),
                  onPressed: () => _showMaintenanceDialog(m),
                  child: Text("Log Care", style: TextStyle(fontSize: 10, color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold)),
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
              decoration: BoxDecoration(border: Border(right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
              child: Text(item['last_reason'] ?? "-", overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.black87))),
            );
          }

          return const SizedBox.shrink();
        }).toList(),
      ),
      ),
    );
  }

  Widget _cellText(String val, {required double width, bool isBold = false}) {
    return Container(
      width: width,
      height: dataRowHeight,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      child: Text(val.isEmpty ? "-" : val, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: isBold ? FontWeight.w600 : FontWeight.normal, color: AppPalette.fg(Colors.black87))),
    );
  }

  void _showColumnVisibilityDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Text("Show / Hide Columns", style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.fg(headerDarkNavy))),
          content: SizedBox(
            width: 300,
            height: 350,
            child: ListView.builder(
              itemCount: _allColumns.length,
              itemBuilder: (context, i) {
                String col = _allColumns[i];
                bool isVisible = !_hiddenColumns.contains(col);
                return CheckboxListTile(
                  dense: true,
                  title: Text(col, style: const TextStyle(fontSize: 12)),
                  value: isVisible,
                  onChanged: (val) {
                    if (val == false && _visibleColumns.length <= 1) return;
                    setDialogState(() {
                      if (val == true) _hiddenColumns.remove(col);
                      else _hiddenColumns.add(col);
                    });
                    setState(() {});
                  },
                );
              },
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(headerDarkNavy)),
              onPressed: () => Navigator.pop(ctx),
              child: Text("Done", style: TextStyle(color: AppPalette.fg(Colors.white), fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  ExportTable _interventionTable() {
    final cols = _visibleColumns.where((c) => c != "Action").toList();
    final rows = <List<String>>[];
    for (var item in _filteredData) {
      final m = _extractMember(item);
      final mid = m['id']?.toString() ?? "";
      final missed = _getMissedCount(item);
      final style = _memberSelectedStyle[mid] ?? "None";
      final count = (item['style_counts']?[style] ?? 0);
      rows.add(cols.map((col) {
        if (col == "Loc") return _getLocation(m);
        if (col == "Sub-Loc") return _getSubLocation(m);
        if (col == "Dept") return _getDepartment(m);
        if (col == "Team") return _getTeam(m);
        if (col == "Cell Group") return _getCellGroup(m);
        if (col == "Name") return _getName(m);
        if (col == "Service Style") return style;
        if (col == "Style Count") return "$count";
        if (col == "Missed") return "$missed";
        if (col == "Care Status") return (item['last_recovery_outcome'] ?? "No Care Logged").toString();
        if (col == "Reason") return (item['last_reason'] ?? "-").toString();
        return "";
      }).toList());
    }
    return ExportTable(
      title: "$_screenTitle – ${widget.unitName}",
      subtitle: "${widget.duty} · ${rows.length} members",
      headers: cols,
      rows: rows,
    );
  }

  /// Excel (.xlsx), PDF, Print preview or Copy.
  void _exportAsExcelCsv() => TableExport.showMenu(context, _interventionTable);

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
          title: Text("Care Log: ${_getName(Map<String, dynamic>.from(memberMap))}", style: TextStyle(color: AppPalette.fg(headerDarkNavy), fontSize: 14, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedOutcome,
                decoration: InputDecoration(labelText: tr("Outcome"), border: OutlineInputBorder()),
                items: ['Recovered', 'Sick', 'Working', 'Travelled', 'Unresolved'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setST(() => selectedOutcome = v!),
              ),
              const SizedBox(height: 12),
              TextField(controller: noteCtrl, decoration: InputDecoration(hintText: tr("Notes..."), border: OutlineInputBorder()), maxLines: 2),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(actionBtnBlue)),
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
                if (mounted) _load();
              },
              child: Text("Save Log", style: TextStyle(color: AppPalette.fg(Colors.white))),
            ),
          ],
        ),
      ),
    );
  }

  void _showCheckboxFilter(String column) {
    Set<String> values = {};
    for (var item in _data) {
      final m = _extractMember(item);
      final mid = m['id']?.toString() ?? "";
      if (column == "Loc") values.add(_getLocation(m));
      else if (column == "Sub-Loc") values.add(_getSubLocation(m));
      else if (column == "Dept") values.add(_getDepartment(m));
      else if (column == "Team") values.add(_getTeam(m));
      else if (column == "Cell Group") values.add(_getCellGroup(m));
      else if (column == "Name") values.add(_getName(m));
      else if (column == "Service Style") values.add(_memberSelectedStyle[mid] ?? "None");
      else if (column == "Missed") values.add("${_getMissedCount(item)} Times");
    }
    final options = values.toList()..sort();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text("Filter $column", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.fg(headerDarkNavy))),
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
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(actionBtnBlue)),
              onPressed: () {
                _applyFilters();
                Navigator.pop(context);
              },
              child: Text("Apply Filter", style: TextStyle(color: AppPalette.fg(Colors.white))),
            ),
          ],
        ),
      ),
    );
  }
}