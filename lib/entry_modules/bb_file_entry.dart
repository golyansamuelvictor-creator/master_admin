// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:master_admin/entry_modules/bb_attendance_sheet_entry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BbFileEntry extends StatefulWidget {
  final List<dynamic> students;
  final Map<String, Map<String, dynamic>> reportData;
  final Color pPurple;
  final List<String> statusOptions;
  final List<String> methodOptions;
  final List<String> monthOptions;
  final VoidCallback onChanged;

  const BbFileEntry({
    super.key,
    required this.students,
    required this.reportData,
    required this.pPurple,
    required this.statusOptions,
    required this.methodOptions,
    required this.monthOptions,
    required this.onChanged,
  });

  @override
  State<BbFileEntry> createState() => _BbFileEntryState();
}

class _BbFileEntryState extends State<BbFileEntry> {
  final _supabase = Supabase.instance.client;
  List<String> _locationSuggestions = [];

  late final ScrollController _rowNumScrollController;
  late final ScrollController _contentVertScrollController;
  late final ScrollController _horizScrollController;
  final FocusNode _focusNode = FocusNode();

  bool _isSyncing = false;
  int? _selStartRow, _selStartCol, _selEndRow, _selEndCol;
  final Map<int, Set<String>> _activeFilters = {};

  static const double _rowHeight = 28.0;
  static const double _rowNumColWidth = 46.0;
  static const double _alphaHeaderHeight = 20.0;
  static const double _titleHeaderHeight = 32.0;
  static const double _totalHeaderHeight = _alphaHeaderHeight + _titleHeaderHeight;

  // Master Column Definition
  final List<String> _allColKeys = [
    "student_name",
    "level_status",
    "month",
    "guide_scj_id",
    "guide_name",
    "guide_location",
    "guide_sub_location",
    "guide_dept",
    "guide_team",
    "guide_cell",
    "teacher_scj_id",
    "teacher_name",
    "teacher_location",
    "teacher_sub_location",
    "teacher_dept",
    "teacher_team",
    "teacher_cell",
    "address",
    "center_place",
    "method",
    "study_att",
  ];

  final List<String> _allColTitles = [
    "Student Name",
    "Level Status",
    "Month",
    "Guide SCJ ID",
    "Guide Name",
    "Guide Loc",
    "Guide Sub-Loc",
    "Guide Dept",
    "Guide Team",
    "Guide Cell",
    "Teacher SCJ ID",
    "Teacher Name",
    "Teacher Loc",
    "Teacher Sub-Loc",
    "Teacher Dept",
    "Teacher Team",
    "Teacher Cell",
    "Address",
    "Center Place",
    "Method",
    "Study / Att",
  ];

  final List<double> _allBaseWidths = [
    140, // Name
    110, // Status
    90,  // Month
    110, // G ID
    130, // G Name
    100, // G Loc
    110, // G Sub
    110, // G Dept
    90,  // G Team
    90,  // G Cell
    110, // T ID
    130, // T Name
    100, // T Loc
    110, // T Sub
    110, // T Dept
    90,  // T Team
    90,  // T Cell
    160, // Address
    150, // Center
    100, // Method
    110, // Study/Att
  ];

  // Set of visible column indices
  late Set<int> _visibleColIndices;

  @override
  void initState() {
    super.initState();
    BrowserContextMenu.disableContextMenu();
    _loadLocationSuggestions();

    _visibleColIndices = Set.from(List.generate(_allColKeys.length, (i) => i));

    _rowNumScrollController = ScrollController();
    _contentVertScrollController = ScrollController();
    _horizScrollController = ScrollController();

    _contentVertScrollController.addListener(() {
      if (_isSyncing) return;
      _isSyncing = true;
      if (_rowNumScrollController.hasClients &&
          _rowNumScrollController.offset != _contentVertScrollController.offset) {
        _rowNumScrollController.jumpTo(_contentVertScrollController.offset);
      }
      _isSyncing = false;
    });

    _rowNumScrollController.addListener(() {
      if (_isSyncing) return;
      _isSyncing = true;
      if (_contentVertScrollController.hasClients &&
          _contentVertScrollController.offset != _rowNumScrollController.offset) {
        _contentVertScrollController.jumpTo(_rowNumScrollController.offset);
      }
      _isSyncing = false;
    });
  }

  @override
  void dispose() {
    BrowserContextMenu.enableContextMenu();
    _rowNumScrollController.dispose();
    _contentVertScrollController.dispose();
    _horizScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Active columns based on visibility
  List<int> get _activeColIndices => _visibleColIndices.toList()..sort();
  List<String> get _colTitles => _activeColIndices.map((i) => _allColTitles[i]).toList();
  List<double> get _baseWidths => _activeColIndices.map((i) => _allBaseWidths[i]).toList();
  List<String> get _colLetters => List.generate(_activeColIndices.length, (i) => String.fromCharCode(65 + (i % 26)));

  Future<void> _loadLocationSuggestions() async {
    try {
      final res = await _supabase.from('sub_locations').select('location_name, name');
      if (mounted) {
        setState(() {
          _locationSuggestions = (res as List).map((e) => "${e['location_name']}, ${e['name']}").toList();
        });
      }
    } catch (e) {
      debugPrint("Location suggestions error: $e");
    }
  }

  // Auto Staff Lookup: populates individual columns directly
  Future<void> _lookupStaff(String scjId, String studentId, String prefix) async {
    final cleanId = scjId.trim();
    if (cleanId.length < 3) return;
    try {
      final data = await _supabase
          .from('members')
          .select('english_name, korean_name, location, sub_location, department, team, cell_group')
          .or('id_number.eq.$cleanId,member_id.eq.$cleanId')
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          widget.reportData.putIfAbsent(studentId, () => {});
          widget.reportData[studentId]!['${prefix}_name'] = data['english_name'] ?? data['korean_name'] ?? '';
          widget.reportData[studentId]!['${prefix}_location'] = data['location'] ?? '';
          widget.reportData[studentId]!['${prefix}_sub_location'] = data['sub_location'] ?? '';
          widget.reportData[studentId]!['${prefix}_dept'] = data['department'] ?? '';
          widget.reportData[studentId]!['${prefix}_team'] = data['team'] ?? '';
          widget.reportData[studentId]!['${prefix}_cell'] = data['cell_group'] ?? '';
        });
        widget.onChanged();
      }
    } catch (e) {
      debugPrint("Staff lookup error: $e");
    }
  }

  List<dynamic> get _filteredStudents {
    if (_activeFilters.isEmpty) return widget.students;
    return widget.students.where((s) {
      for (final entry in _activeFilters.entries) {
        final colIdx = entry.key;
        final allowedVals = entry.value;
        final val = _getCellValue(s, colIdx);
        final checkVal = val.isEmpty ? "(Blank)" : val;
        if (!allowedVals.contains(checkVal)) return false;
      }
      return true;
    }).toList();
  }

  String _getCellValue(dynamic s, int visibleColIdx) {
    final actualColIdx = _activeColIndices[visibleColIdx];
    final key = _allColKeys[actualColIdx];
    final id = s['id'].toString();
    final data = widget.reportData[id] ?? s;
    return (data[key] ?? s[key])?.toString() ?? "";
  }

  bool _isCellSelected(int r, int c) {
    if (_selStartRow == null || _selStartCol == null || _selEndRow == null || _selEndCol == null) return false;
    final minR = math.min(_selStartRow!, _selEndRow!);
    final maxR = math.max(_selStartRow!, _selEndRow!);
    final minC = math.min(_selStartCol!, _selEndCol!);
    final maxC = math.max(_selStartCol!, _selEndCol!);
    return r >= minR && r <= maxR && c >= minC && c <= maxC;
  }

  bool _isAnchor(int r, int c) => _selStartRow == r && _selStartCol == c;

  void _selectCell(int r, int c) {
    _focusNode.requestFocus();
    setState(() {
      _selStartRow = r; _selStartCol = c;
      _selEndRow = r; _selEndCol = c;
    });
  }

  void _selectRow(int r) {
    _focusNode.requestFocus();
    setState(() {
      _selStartRow = r; _selEndRow = r;
      _selStartCol = 0; _selEndCol = _colTitles.length - 1;
    });
  }

  void _selectColumn(int c) {
    final count = _filteredStudents.length;
    if (count == 0) return;
    _focusNode.requestFocus();
    setState(() {
      _selStartCol = c; _selEndCol = c;
      _selStartRow = 0; _selEndRow = count - 1;
    });
  }

  void _selectAll() {
    final count = _filteredStudents.length;
    if (count == 0) return;
    _focusNode.requestFocus();
    setState(() {
      _selStartRow = 0; _selStartCol = 0;
      _selEndRow = count - 1; _selEndCol = _colTitles.length - 1;
    });
  }

  void _copySelection() {
    if (_selStartRow == null) return;
    final students = _filteredStudents;
    final minR = math.min(_selStartRow!, _selEndRow!);
    final maxR = math.max(_selStartRow!, _selEndRow!);
    final minC = math.min(_selStartCol!, _selEndCol!);
    final maxC = math.max(_selStartCol!, _selEndCol!);

    final buffer = StringBuffer();
    for (int r = minR; r <= maxR; r++) {
      if (r >= students.length) break;
      final s = students[r];
      final rowVals = <String>[];
      for (int c = minC; c <= maxC; c++) {
        rowVals.add(_getCellValue(s, c));
      }
      buffer.writeln(rowVals.join('\t'));
    }

    Clipboard.setData(ClipboardData(text: buffer.toString().trimRight()));
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Copied (${maxR - minR + 1} rows) to clipboard"), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pasteSelection() async {
    if (_selStartRow == null) return;
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip == null || clip.text == null || clip.text!.isEmpty) return;

    final lines = clip.text!.split(RegExp(r'\r?\n')).where((l) => l.isNotEmpty).toList();
    final students = _filteredStudents;
    final minR = math.min(_selStartRow!, _selEndRow!);
    final maxR = math.max(_selStartRow!, _selEndRow!);
    final minC = math.min(_selStartCol!, _selEndCol!);

    bool modified = false;

    if (lines.length == 1 && !lines[0].contains('\t')) {
      final val = lines[0].trim();
      for (int r = minR; r <= maxR; r++) {
        if (r >= students.length) break;
        final id = students[r]['id'].toString();
        widget.reportData.putIfAbsent(id, () => {});
        for (int c = minC; c <= math.max(_selStartCol!, _selEndCol!); c++) {
          if (_setEditableValue(id, c, val)) modified = true;
        }
      }
    } else {
      for (int i = 0; i < lines.length; i++) {
        final r = minR + i;
        if (r >= students.length) break;
        final id = students[r]['id'].toString();
        widget.reportData.putIfAbsent(id, () => {});
        final cells = lines[i].split('\t');
        for (int j = 0; j < cells.length; j++) {
          final c = minC + j;
          if (c > _colTitles.length - 1) break;
          if (_setEditableValue(id, c, cells[j].trim())) modified = true;
        }
      }
    }

    if (modified) {
      widget.onChanged();
      setState(() {});
    }
  }

  bool _setEditableValue(String id, int visibleColIdx, String? val) {
    widget.reportData.putIfAbsent(id, () => {});
    final actualColIdx = _activeColIndices[visibleColIdx];
    final key = _allColKeys[actualColIdx];

    widget.reportData[id]![key] = val;

    // Trigger auto-lookups on SCJ ID input
    if (key == 'guide_scj_id' && val != null && val.isNotEmpty) {
      _lookupStaff(val, id, "guide");
    } else if (key == 'teacher_scj_id' && val != null && val.isNotEmpty) {
      _lookupStaff(val, id, "teacher");
    }

    return true;
  }

  void _clearSelection() {
    if (_selStartRow == null) return;
    final students = _filteredStudents;
    final minR = math.min(_selStartRow!, _selEndRow!);
    final maxR = math.max(_selStartRow!, _selEndRow!);
    final minC = math.min(_selStartCol!, _selEndCol!);
    final maxC = math.max(_selStartCol!, _selEndCol!);

    bool modified = false;
    for (int r = minR; r <= maxR; r++) {
      if (r >= students.length) break;
      final id = students[r]['id'].toString();
      widget.reportData.putIfAbsent(id, () => {});
      for (int c = minC; c <= maxC; c++) {
        if (_setEditableValue(id, c, null)) modified = true;
      }
    }

    if (modified) {
      widget.onChanged();
      setState(() {});
    }
  }

  // Column Visibility Dialog (Hide / Show Columns)
  void _openColumnVisibilityDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDlgState) {
          return AlertDialog(
            title: const Text("Column Visibility", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 320,
              height: 380,
              child: Column(
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setDlgState(() => _visibleColIndices = Set.from(List.generate(_allColKeys.length, (i) => i))),
                        child: const Text("Show All", style: TextStyle(fontSize: 12)),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setDlgState(() => _visibleColIndices = {0, 1, 2, 3, 10, 17}),
                        child: const Text("Reset Default", style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _allColTitles.length,
                      itemBuilder: (c, idx) {
                        final isVis = _visibleColIndices.contains(idx);
                        return CheckboxListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(_allColTitles[idx], style: const TextStyle(fontSize: 12)),
                          value: isVis,
                          onChanged: (val) {
                            if (val == false && _visibleColIndices.length <= 1) return; // Keep at least 1
                            setDlgState(() {
                              if (val == true) _visibleColIndices.add(idx);
                              else _visibleColIndices.remove(idx);
                            });
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
                style: ElevatedButton.styleFrom(backgroundColor: widget.pPurple, foregroundColor: Colors.white),
                onPressed: () {
                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: const Text("Done"),
              ),
            ],
          );
        });
      },
    );
  }

  // Export visible data to CSV/Excel Clipboard
  void _exportCsv() {
    final buffer = StringBuffer();
    // Headers
    buffer.writeln(_colTitles.join(','));
    // Rows
    for (final s in _filteredStudents) {
      final row = <String>[];
      for (int c = 0; c < _activeColIndices.length; c++) {
        final val = _getCellValue(s, c).replaceAll('"', '""');
        row.add('"$val"');
      }
      buffer.writeln(row.join(','));
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Exported active grid to CSV format! (Copied to Clipboard)"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showContextMenu(Offset pos, int r, int c) {
    if (!_isCellSelected(r, c)) _selectCell(r, c);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: const [
        PopupMenuItem(value: 'copy', height: 32, child: Row(children: [Icon(Icons.copy, size: 14), SizedBox(width: 8), Text("Copy", style: TextStyle(fontSize: 12)), Spacer(), Text("Ctrl+C", style: TextStyle(fontSize: 10, color: Colors.grey))])),
        PopupMenuItem(value: 'paste', height: 32, child: Row(children: [Icon(Icons.paste, size: 14), SizedBox(width: 8), Text("Paste", style: TextStyle(fontSize: 12)), Spacer(), Text("Ctrl+V", style: TextStyle(fontSize: 10, color: Colors.grey))])),
        PopupMenuItem(value: 'clear', height: 32, child: Row(children: [Icon(Icons.backspace_outlined, size: 14, color: Colors.red), SizedBox(width: 8), Text("Clear Selection", style: TextStyle(fontSize: 12, color: Colors.red)), Spacer(), Text("Del", style: TextStyle(fontSize: 10, color: Colors.grey))])),
        PopupMenuDivider(height: 1),
        PopupMenuItem(value: 'row', height: 32, child: Row(children: [Icon(Icons.table_rows_outlined, size: 14), SizedBox(width: 8), Text("Select Entire Row", style: TextStyle(fontSize: 12))])),
        PopupMenuItem(value: 'col', height: 32, child: Row(children: [Icon(Icons.view_column_outlined, size: 14), SizedBox(width: 8), Text("Select Entire Column", style: TextStyle(fontSize: 12))])),
        PopupMenuItem(value: 'all', height: 32, child: Row(children: [Icon(Icons.select_all, size: 14), SizedBox(width: 8), Text("Select All", style: TextStyle(fontSize: 12)), Spacer(), Text("Ctrl+A", style: TextStyle(fontSize: 10, color: Colors.grey))])),
      ],
    ).then((val) {
      if (val == 'copy') _copySelection();
      if (val == 'paste') _pasteSelection();
      if (val == 'clear') _clearSelection();
      if (val == 'row') _selectRow(r);
      if (val == 'col') _selectColumn(c);
      if (val == 'all') _selectAll();
    });
  }

  void _openFilterDialog(int colIdx) {
    final Set<String> distinct = {};
    for (final s in widget.students) {
      final val = _getCellValue(s, colIdx);
      distinct.add(val.isEmpty ? "(Blank)" : val);
    }
    final sorted = distinct.toList()..sort();
    final Set<String> temp = Set.from(_activeFilters[colIdx] ?? distinct);
    String query = "";

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          final list = sorted.where((s) => s.toLowerCase().contains(query.toLowerCase())).toList();
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            title: Text("Filter: ${_colTitles[colIdx]}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 280, height: 300,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(hintText: "Search...", isDense: true, prefixIcon: const Icon(Icons.search, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                    onChanged: (q) => setDialogState(() => query = q),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    TextButton(onPressed: () => setDialogState(() => temp.addAll(distinct)), child: const Text("Select All", style: TextStyle(fontSize: 11))),
                    const Spacer(),
                    TextButton(onPressed: () => setDialogState(() => temp.clear()), child: const Text("Clear All", style: TextStyle(fontSize: 11, color: Colors.red))),
                  ]),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (ctx, i) {
                        final val = list[i];
                        return CheckboxListTile(
                          dense: true, visualDensity: VisualDensity.compact,
                          title: Text(val, style: const TextStyle(fontSize: 11.5)),
                          value: temp.contains(val),
                          onChanged: (c) => setDialogState(() => c == true ? temp.add(val) : temp.remove(val)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () { setState(() => _activeFilters.remove(colIdx)); Navigator.pop(ctx); }, child: const Text("Reset")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: widget.pPurple, foregroundColor: Colors.white),
                onPressed: () {
                  setState(() {
                    if (temp.containsAll(distinct)) _activeFilters.remove(colIdx);
                    else _activeFilters[colIdx] = Set.from(temp);
                  });
                  Navigator.pop(ctx);
                },
                child: const Text("Apply"),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
          if (ctrl && event.logicalKey == LogicalKeyboardKey.keyC) { _copySelection(); return KeyEventResult.handled; }
          if (ctrl && event.logicalKey == LogicalKeyboardKey.keyV) { _pasteSelection(); return KeyEventResult.handled; }
          if (ctrl && event.logicalKey == LogicalKeyboardKey.keyA) { _selectAll(); return KeyEventResult.handled; }
          if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) { _clearSelection(); return KeyEventResult.handled; }
          return KeyEventResult.ignored;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availWidth = constraints.maxWidth - _rowNumColWidth;
            final baseSum = _baseWidths.fold<double>(0, (s, w) => s + w);
            final scale = (availWidth > baseSum) ? (availWidth / baseSum) : 1.0;
            final widths = _baseWidths.map((w) => w * scale).toList();
            final totalTableWidth = widths.fold<double>(0, (s, w) => s + w);
            final filtered = _filteredStudents;

            return Column(
              children: [
                // Utility Bar: Column Visibility, Download, Print
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  color: Colors.grey.shade50,
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                      icon: const Icon(Icons.how_to_reg_rounded, size: 14),
                      label: const Text("Take Daily Attendance", style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
    backgroundColor: Colors.green[700],
    foregroundColor: Colors.white,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 10),
  ),
  onPressed: () {
    showDialog(
      context: context,
      builder: (ctx) => BbAttendanceSheet(
        students: _filteredStudents,
        selectedDate: DateTime.now(), // or your selected date
        pPurple: widget.pPurple,
        onSaved: widget.onChanged,
      ),
    );
  },
                     ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.view_column_outlined, size: 14),
                        label: Text("Columns (${_activeColIndices.length}/${_allColTitles.length})", style: const TextStyle(fontSize: 11)),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                        onPressed: _openColumnVisibilityDialog,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.file_download_outlined, size: 14),
                        label: const Text("Export CSV", style: TextStyle(fontSize: 11)),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                        onPressed: _exportCsv,
                      ),
                      const Spacer(),
                      Text("Total: ${filtered.length} students", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Table Area
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Frozen Left Pane: Corner + Virtualized Row Numbers
                      SizedBox(
                        width: _rowNumColWidth,
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: _selectAll,
                              child: Container(
                                height: _totalHeaderHeight,
                                width: _rowNumColWidth,
                                color: const Color(0xFFE2E8F0),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.select_all, size: 14, color: Colors.black54),
                                    Text("#", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                controller: _rowNumScrollController,
                                physics: const ClampingScrollPhysics(),
                                itemCount: filtered.length,
                                itemExtent: _rowHeight,
                                itemBuilder: (ctx, idx) {
                                  final isRowSel = _selStartRow != null &&
                                      idx >= math.min(_selStartRow!, _selEndRow!) &&
                                      idx <= math.max(_selStartRow!, _selEndRow!) &&
                                      _selStartCol == 0 &&
                                      _selEndCol == _colTitles.length - 1;

                                  return GestureDetector(
                                    onTap: () => _selectRow(idx),
                                    onSecondaryTapDown: (d) => _showContextMenu(d.globalPosition, idx, 0),
                                    child: Container(
                                      height: _rowHeight,
                                      width: _rowNumColWidth,
                                      decoration: BoxDecoration(
                                        color: isRowSel ? widget.pPurple.withValues(alpha: 0.15) : const Color(0xFFF1F5F9),
                                        border: Border(
                                          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.3), width: 0.8),
                                          right: BorderSide(color: Colors.grey.withValues(alpha: 0.4), width: 1.2),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          "${idx + 1}",
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: isRowSel ? widget.pPurple : Colors.grey[700],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 2. Scrollable Data Pane: Sticky Header + Virtualized Rows
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _horizScrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          child: SizedBox(
                            width: totalTableWidth,
                            child: Column(
                              children: [
                                // FROZEN TOP HEADER ROW
                                Container(
                                  height: _totalHeaderHeight,
                                  color: const Color(0xFF1E293B),
                                  child: Column(
                                    children: [
                                      SizedBox(
                                        height: _alphaHeaderHeight,
                                        child: Row(
                                          children: List.generate(_colLetters.length, (i) {
                                            final isColSel = _selStartCol != null &&
                                                i >= math.min(_selStartCol!, _selEndCol!) &&
                                                i <= math.max(_selStartCol!, _selEndCol!) &&
                                                _selStartRow == 0 &&
                                                _selEndRow == filtered.length - 1;

                                            return GestureDetector(
                                              onTap: () => _selectColumn(i),
                                              child: Container(
                                                width: widths[i],
                                                color: isColSel ? widget.pPurple.withValues(alpha: 0.25) : const Color(0xFFF1F5F9),
                                                alignment: Alignment.center,
                                                child: Text(_colLetters[i], style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isColSel ? widget.pPurple : Colors.grey[700])),
                                              ),
                                            );
                                          }),
                                        ),
                                      ),
                                      SizedBox(
                                        height: _titleHeaderHeight,
                                        child: Row(
                                          children: List.generate(_colTitles.length, (i) {
                                            final isFiltered = _activeFilters.containsKey(i);
                                            return Container(
                                              width: widths[i],
                                              padding: const EdgeInsets.symmetric(horizontal: 6),
                                              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.withValues(alpha: 0.3), width: 0.8))),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: GestureDetector(
                                                      onTap: () => _selectColumn(i),
                                                      child: Text(_colTitles[i], softWrap: false, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                                    ),
                                                  ),
                                                  InkWell(
                                                    onTap: () => _openFilterDialog(i),
                                                    child: Icon(isFiltered ? Icons.filter_alt : Icons.filter_alt_outlined, size: 13, color: isFiltered ? const Color(0xFFF59E0B) : Colors.white70),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // VIRTUALIZED MAIN DATA ROWS (Ultra smooth 60/120fps)
                                Expanded(
                                  child: ListView.builder(
                                    controller: _contentVertScrollController,
                                    physics: const ClampingScrollPhysics(),
                                    itemCount: filtered.length,
                                    itemExtent: _rowHeight,
                                    itemBuilder: (ctx, r) {
                                      final s = filtered[r];
                                      final isEven = r.isEven;
                                      return SizedBox(
                                        height: _rowHeight,
                                        child: Row(
                                          children: List.generate(_activeColIndices.length, (c) {
                                            return _buildCell(s, r, c, widths[c], isEven);
                                          }),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCell(dynamic s, int r, int visibleColIdx, double width, bool isEven) {
    final actualColIdx = _activeColIndices[visibleColIdx];
    final key = _allColKeys[actualColIdx];
    final isSel = _isCellSelected(r, visibleColIdx);
    final isAnc = _isAnchor(r, visibleColIdx);
    final id = s['id'].toString();
    widget.reportData.putIfAbsent(id, () => {});

    Widget content;

    // Read-only / auto-calculated staff details
    final bool isStaffAutoCol = key.endsWith('_name') ||
                                key.endsWith('_location') ||
                                key.endsWith('_sub_location') ||
                                key.endsWith('_dept') ||
                                key.endsWith('_team') ||
                                key.endsWith('_cell');

    if (key == 'student_name') {
      final val = _getCellValue(s, visibleColIdx);
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        child: Text(
          val.isEmpty ? "Unnamed" : val,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    } else if (key == 'level_status') {
      final cur = _getCellValue(s, visibleColIdx);
      content = DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: widget.statusOptions.contains(cur) ? cur : null,
          isDense: true, isExpanded: true, iconSize: 14,
          style: GoogleFonts.merriweather(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
          items: [
            const DropdownMenuItem(value: null, child: Center(child: Text("-", style: TextStyle(color: Colors.grey, fontSize: 11)))),
            ...widget.statusOptions.map((o) => DropdownMenuItem(value: o, child: Center(child: Text(o, softWrap: false, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))))),
          ],
          onChanged: (v) {
            _selectCell(r, visibleColIdx);
            widget.onChanged();
            setState(() => _setEditableValue(id, visibleColIdx, v));
          },
        ),
      );
    } else if (key == 'month') {
      final cur = _getCellValue(s, visibleColIdx);
      content = DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: widget.monthOptions.contains(cur) ? cur : null,
          isDense: true, isExpanded: true, iconSize: 14,
          style: GoogleFonts.merriweather(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
          items: [
            const DropdownMenuItem(value: null, child: Center(child: Text("-", style: TextStyle(color: Colors.grey, fontSize: 11)))),
            ...widget.monthOptions.map((o) => DropdownMenuItem(value: o, child: Center(child: Text(o, softWrap: false, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))))),
          ],
          onChanged: (v) {
            _selectCell(r, visibleColIdx);
            widget.onChanged();
            setState(() => _setEditableValue(id, visibleColIdx, v));
          },
        ),
      );
    } else if (key == 'method') {
      final cur = _getCellValue(s, visibleColIdx);
      content = DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: widget.methodOptions.contains(cur) ? cur : null,
          isDense: true, isExpanded: true, iconSize: 14,
          style: GoogleFonts.merriweather(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
          items: [
            const DropdownMenuItem(value: null, child: Center(child: Text("-", style: TextStyle(color: Colors.grey, fontSize: 11)))),
            ...widget.methodOptions.map((o) => DropdownMenuItem(value: o, child: Center(child: Text(o, softWrap: false, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))))),
          ],
          onChanged: (v) {
            _selectCell(r, visibleColIdx);
            widget.onChanged();
            setState(() => _setEditableValue(id, visibleColIdx, v));
          },
        ),
      );
    } else if (isStaffAutoCol) {
      // Auto-filled read-only staff detail
      final val = _getCellValue(s, visibleColIdx);
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        child: Text(
          val.isEmpty ? "-" : val,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.merriweather(fontSize: 10, color: Colors.blueGrey[800], fontWeight: FontWeight.w500),
        ),
      );
    } else if (key == 'center_place') {
      final val = _getCellValue(s, visibleColIdx);
      content = Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Autocomplete<String>(
          initialValue: TextEditingValue(text: val),
          optionsBuilder: (textEditingValue) {
            if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
            return _locationSuggestions.where((option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
          },
          onSelected: (selection) {
            _selectCell(r, visibleColIdx);
            widget.onChanged();
            setState(() => widget.reportData[id]!['center_place'] = selection);
          },
          fieldViewBuilder: (context, controller, focus, onFieldSubmitted) {
            return TextFormField(
              controller: controller,
              focusNode: focus,
              textAlign: TextAlign.center,
              style: GoogleFonts.merriweather(fontSize: 10.5),
              decoration: const InputDecoration(hintText: "Location...", border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4)),
              onTap: () => _selectCell(r, visibleColIdx),
              onChanged: (v) {
                widget.onChanged();
                widget.reportData[id]!['center_place'] = v;
              },
            );
          },
        ),
      );
    } else {
      // Text Input (SCJ ID, Address, Study/Att)
      final val = _getCellValue(s, visibleColIdx);
      content = Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextFormField(
          key: ValueKey("${id}_$key"),
          initialValue: val,
          textAlign: TextAlign.center,
          style: GoogleFonts.merriweather(fontSize: 10.5),
          decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4)),
          onTap: () => _selectCell(r, visibleColIdx),
          onChanged: (v) {
            widget.onChanged();
            _setEditableValue(id, visibleColIdx, v);
          },
        ),
      );
    }

    return GestureDetector(
      onTap: () => _selectCell(r, visibleColIdx),
      onSecondaryTapDown: (d) => _showContextMenu(d.globalPosition, r, visibleColIdx),
      child: Container(
        width: width,
        height: _rowHeight,
        decoration: BoxDecoration(
          color: isSel
              ? widget.pPurple.withValues(alpha: 0.12)
              : (isStaffAutoCol ? const Color(0xFFF1F5F9) : (isEven ? Colors.white : const Color(0xFFF8FAFC))),
          border: isAnc
              ? Border.all(color: widget.pPurple, width: 1.8)
              : Border.all(color: Colors.grey.withValues(alpha: 0.25), width: 0.6),
        ),
        child: content,
      ),
    );
  }
}