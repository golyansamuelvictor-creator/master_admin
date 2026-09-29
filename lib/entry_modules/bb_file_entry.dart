// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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

  static const double _rowHeight = 27.0;
  static const double _rowNumColWidth = 46.0;
  static const double _alphaHeaderHeight = 20.0;
  static const double _titleHeaderHeight = 32.0;
  static const double _totalHeaderHeight = _alphaHeaderHeight + _titleHeaderHeight;

  final List<String> _colLetters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K"];
  final List<String> _colTitles = [
    "Student Name",
    "Level Status",
    "Month",
    "Guide ID",
    "Guide Details",
    "Teacher ID",
    "Teacher Details",
    "Address",
    "Center Place",
    "Method",
    "Study / Attendance",
  ];
  final List<double> _baseWidths = [150, 120, 100, 100, 240, 100, 240, 170, 170, 110, 130];

  @override
  void initState() {
    super.initState();
    BrowserContextMenu.disableContextMenu();
    _loadLocationSuggestions();

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

  Future<void> _loadLocationSuggestions() async {
    try {
      final res = await _supabase.from('sub_locations').select('location_name, name');
      if (mounted) {
        setState(() {
          _locationSuggestions = (res as List).map((e) => "${e['location_name']}, ${e['name']}").toList();
        });
      }
    } catch (e) {
      debugPrint("Error loading location suggestions: $e");
    }
  }

  Future<void> _lookupStaff(String idNumber, String studentId, String fieldPrefix) async {
    if (idNumber.length < 5) return;
    try {
      final data = await _supabase.from('members').select().eq('id_number', idNumber).maybeSingle();
      if (data != null && mounted) {
        setState(() {
          String info = "${data['location']} | ${data['sub_location']} | ${data['current_dept']} | ${data['team_number']} | ${data['cell_number']} | ${data['korean_name']}";
          widget.reportData[studentId]!['${fieldPrefix}_info'] = info;
        });
        widget.onChanged();
      }
    } catch (e) {
      debugPrint("Lookup error: $e");
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

  String _getCellValue(dynamic s, int col) {
    final id = s['id'].toString();
    switch (col) {
      case 0: return s['student_name']?.toString() ?? "";
      case 1: return widget.reportData[id]?['level_status']?.toString() ?? "";
      case 2: return widget.reportData[id]?['month']?.toString() ?? "";
      case 3: return widget.reportData[id]?['guide_id']?.toString() ?? "";
      case 4: return widget.reportData[id]?['guide_info']?.toString() ?? "";
      case 5: return widget.reportData[id]?['teacher_id']?.toString() ?? "";
      case 6: return widget.reportData[id]?['teacher_info']?.toString() ?? "";
      case 7: return widget.reportData[id]?['address']?.toString() ?? "";
      case 8: return widget.reportData[id]?['center_place']?.toString() ?? "";
      case 9: return widget.reportData[id]?['method']?.toString() ?? "";
      case 10: return widget.reportData[id]?['study_att']?.toString() ?? "";
      default: return "";
    }
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

  bool _setEditableValue(String id, int c, String? val) {
    if (c == 1) { widget.reportData[id]!['level_status'] = val; return true; }
    if (c == 2) { widget.reportData[id]!['month'] = val; return true; }
    if (c == 3) {
      widget.reportData[id]!['guide_id'] = val;
      if (val != null) _lookupStaff(val, id, "guide");
      return true;
    }
    if (c == 4) { widget.reportData[id]!['guide_info'] = val; return true; }
    if (c == 5) {
      widget.reportData[id]!['teacher_id'] = val;
      if (val != null) _lookupStaff(val, id, "teacher");
      return true;
    }
    if (c == 6) { widget.reportData[id]!['teacher_info'] = val; return true; }
    if (c == 7) { widget.reportData[id]!['address'] = val; return true; }
    if (c == 8) { widget.reportData[id]!['center_place'] = val; return true; }
    if (c == 9) { widget.reportData[id]!['method'] = val; return true; }
    if (c == 10) { widget.reportData[id]!['study_att'] = val; return true; }
    return false;
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
    return Focus(
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

          return Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.white,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Frozen Left Pane: Corner + Row Numbers
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
                        child: SingleChildScrollView(
                          controller: _rowNumScrollController,
                          physics: const ClampingScrollPhysics(),
                          child: Column(
                            children: List.generate(filtered.length, (idx) {
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
                                  child: Center(child: Text("${idx + 1}", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isRowSel ? widget.pPurple : Colors.grey[700]))),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Scrollable Data Pane: Sticky Header + 2D Data Rows
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: totalTableWidth,
                      child: Column(
                        children: [
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
                                                child: Text(_colTitles[i], softWrap: false, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
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

                          Expanded(
                            child: SingleChildScrollView(
                              controller: _contentVertScrollController,
                              physics: const ClampingScrollPhysics(),
                              child: Column(
                                children: List.generate(filtered.length, (r) {
                                  final s = filtered[r];
                                  final isEven = r.isEven;
                                  return SizedBox(
                                    height: _rowHeight,
                                    child: Row(
                                      children: List.generate(_colTitles.length, (c) {
                                        return _buildCell(s, r, c, widths[c], isEven);
                                      }),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCell(dynamic s, int r, int c, double width, bool isEven) {
    final isSel = _isCellSelected(r, c);
    final isAnc = _isAnchor(r, c);
    final id = s['id'].toString();
    widget.reportData.putIfAbsent(id, () => {});

    Widget content;
    // 0: Student Name (Static)
    if (c == 0) {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        child: Text(s['student_name'] ?? "-", softWrap: false, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }
    // 1: Level Status (Dropdown)
    else if (c == 1) {
      final cur = _getCellValue(s, c);
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
            _selectCell(r, c);
            widget.onChanged();
            setState(() => _setEditableValue(id, c, v));
          },
        ),
      );
    }
    // 2: Month (Dropdown)
    else if (c == 2) {
      final cur = _getCellValue(s, c);
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
            _selectCell(r, c);
            widget.onChanged();
            setState(() => _setEditableValue(id, c, v));
          },
        ),
      );
    }
    // 3: Guide ID (Input with auto-lookup)
    else if (c == 3) {
      final val = _getCellValue(s, c);
      content = Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          textAlign: TextAlign.center,
          style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(hintText: "Enter ID", border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4)),
          controller: TextEditingController(text: val)..selection = TextSelection.collapsed(offset: val.length),
          onTap: () => _selectCell(r, c),
          onChanged: (v) {
            widget.onChanged();
            widget.reportData[id]!['guide_id'] = v;
            _lookupStaff(v, id, "guide");
          },
        ),
      );
    }
    // 4: Guide Details (Auto-filled Info)
    else if (c == 4) {
      final text = widget.reportData[id]!['guide_info']?.toString() ?? "Awaiting ID...";
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        child: Text(text, softWrap: false, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 9.5, color: Colors.blueGrey[700], fontStyle: FontStyle.italic)),
      );
    }
    // 5: Teacher ID (Input with auto-lookup)
    else if (c == 5) {
      final val = _getCellValue(s, c);
      content = Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          textAlign: TextAlign.center,
          style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(hintText: "Enter ID", border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4)),
          controller: TextEditingController(text: val)..selection = TextSelection.collapsed(offset: val.length),
          onTap: () => _selectCell(r, c),
          onChanged: (v) {
            widget.onChanged();
            widget.reportData[id]!['teacher_id'] = v;
            _lookupStaff(v, id, "teacher");
          },
        ),
      );
    }
    // 6: Teacher Details (Auto-filled Info)
    else if (c == 6) {
      final text = widget.reportData[id]!['teacher_info']?.toString() ?? "Awaiting ID...";
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        child: Text(text, softWrap: false, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 9.5, color: Colors.blueGrey[700], fontStyle: FontStyle.italic)),
      );
    }
    // 7: Address (Input)
    else if (c == 7) {
      final val = _getCellValue(s, c);
      content = Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          textAlign: TextAlign.center,
          style: GoogleFonts.merriweather(fontSize: 10.5),
          decoration: const InputDecoration(hintText: "Search address...", border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4)),
          controller: TextEditingController(text: val)..selection = TextSelection.collapsed(offset: val.length),
          onTap: () => _selectCell(r, c),
          onChanged: (v) {
            widget.onChanged();
            _setEditableValue(id, c, v);
          },
        ),
      );
    }
    // 8: Center Place (Autocomplete)
    else if (c == 8) {
      final val = _getCellValue(s, c);
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
            _selectCell(r, c);
            widget.onChanged();
            setState(() => widget.reportData[id]!['center_place'] = selection);
          },
          fieldViewBuilder: (context, controller, focus, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focus,
              textAlign: TextAlign.center,
              style: GoogleFonts.merriweather(fontSize: 10.5),
              decoration: const InputDecoration(hintText: "Type location...", border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4)),
              onTap: () => _selectCell(r, c),
              onChanged: (v) {
                widget.onChanged();
                widget.reportData[id]!['center_place'] = v;
              },
            );
          },
        ),
      );
    }
    // 9: Method (Dropdown)
    else if (c == 9) {
      final cur = _getCellValue(s, c);
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
            _selectCell(r, c);
            widget.onChanged();
            setState(() => _setEditableValue(id, c, v));
          },
        ),
      );
    }
    // 10: Study / Attendance (Input)
    else {
      final val = _getCellValue(s, c);
      content = Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          textAlign: TextAlign.center,
          style: GoogleFonts.merriweather(fontSize: 10.5),
          decoration: const InputDecoration(hintText: "0 / /", border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4)),
          controller: TextEditingController(text: val)..selection = TextSelection.collapsed(offset: val.length),
          onTap: () => _selectCell(r, c),
          onChanged: (v) {
            widget.onChanged();
            _setEditableValue(id, c, v);
          },
        ),
      );
    }

    return GestureDetector(
      onTap: () => _selectCell(r, c),
      onSecondaryTapDown: (d) => _showContextMenu(d.globalPosition, r, c),
      child: Container(
        width: width,
        height: _rowHeight,
        decoration: BoxDecoration(
          color: isSel ? widget.pPurple.withValues(alpha: 0.12) : (isEven ? Colors.white : const Color(0xFFF8FAFC)),
          border: isAnc
              ? Border.all(color: widget.pPurple, width: 1.8)
              : Border.all(color: Colors.grey.withValues(alpha: 0.25), width: 0.6),
        ),
        child: content,
      ),
    );
  }
}