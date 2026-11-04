// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:master_admin/core/app_palette.dart';
import 'place_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServiceAttendanceEntry extends StatefulWidget {
  final List<dynamic> members;
  final Map<String, Map<String, dynamic>> reportData;
  final Color pPurple;
  final List<String> optionsPre, optionsActual, optionsMakeup, optionsPlace;
  final VoidCallback onChanged;

  const ServiceAttendanceEntry({
    super.key,
    required this.members,
    required this.reportData,
    required this.pPurple,
    required this.optionsPre,
    required this.optionsActual,
    required this.optionsMakeup,
    required this.optionsPlace,
    required this.onChanged,
  });

  @override
  State<ServiceAttendanceEntry> createState() => _ServiceAttendanceEntryState();
}

class _ServiceAttendanceEntryState extends State<ServiceAttendanceEntry> {
  // Synchronized scroll controllers for frozen panes
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

  // Column definitions (A - M)
  final List<String> _colLetters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M"];
  final List<String> _colTitles = [
    "Location",
    "Sub-Location",
    "Department",
    "Team",
    "Cell Group",
    "English Name",
    "Duty",
    "Pre-Attendance",
    "Actual Attendance",
    "Makeup Attendance",
    "Place",
    "Situation",
    "Strategy",
  ];
  final List<double> _baseWidths = [105, 115, 115, 95, 95, 160, 110, 130, 135, 140, 115, 200, 200];

  @override
  void initState() {
    super.initState();
    _loadHiddenCols();
    BrowserContextMenu.disableContextMenu();

    _rowNumScrollController = ScrollController();
    _contentVertScrollController = ScrollController();
    _horizScrollController = ScrollController();

    // High performance linked vertical scroll synchronization
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

  List<dynamic> get _filteredMembers {
    if (_activeFilters.isEmpty) return widget.members;
    return widget.members.where((m) {
      for (final entry in _activeFilters.entries) {
        final colIdx = entry.key;
        final allowedVals = entry.value;
        final val = _getCellValue(m, colIdx);
        final checkVal = val.isEmpty ? "(Blank)" : val;
        if (!allowedVals.contains(checkVal)) return false;
      }
      return true;
    }).toList();
  }

  String _getCellValue(dynamic m, int col) {
    final mid = m['id'].toString();
    switch (col) {
      case 0: return m['location']?.toString() ?? "";
      case 1: return m['sub_location']?.toString() ?? "";
      case 2: return m['department']?.toString() ?? "";
      case 3: return m['team']?.toString() ?? "";
      case 4: return m['cell_group']?.toString() ?? "";
      case 5: return m['english_name']?.toString() ?? "";
      case 6: return m['duty']?.toString() ?? "";
      case 7: return widget.reportData[mid]?['attendance_pre']?.toString() ?? "";
      case 8: return widget.reportData[mid]?['attendance_realtime']?.toString() ?? "";
      case 9: return widget.reportData[mid]?['attendance_makeup']?.toString() ?? "";
      case 10: return widget.reportData[mid]?['place']?.toString() ?? "";
      case 11: return widget.reportData[mid]?['situation_notes']?.toString() ?? ""; // Exactly matches Supabase SQL
      case 12: return widget.reportData[mid]?['strategy_notes']?.toString() ?? "";
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
    final count = _filteredMembers.length;
    if (count == 0) return;
    _focusNode.requestFocus();
    setState(() {
      _selStartCol = c; _selEndCol = c;
      _selStartRow = 0; _selEndRow = count - 1;
    });
  }

  void _selectAll() {
    final count = _filteredMembers.length;
    if (count == 0) return;
    _focusNode.requestFocus();
    setState(() {
      _selStartRow = 0; _selStartCol = 0;
      _selEndRow = count - 1; _selEndCol = _colTitles.length - 1;
    });
  }

  void _copySelection() {
    if (_selStartRow == null) return;
    final members = _filteredMembers;
    final minR = math.min(_selStartRow!, _selEndRow!);
    final maxR = math.max(_selStartRow!, _selEndRow!);
    final minC = math.min(_selStartCol!, _selEndCol!);
    final maxC = math.max(_selStartCol!, _selEndCol!);

    final buffer = StringBuffer();
    for (int r = minR; r <= maxR; r++) {
      if (r >= members.length) break;
      final m = members[r];
      final rowVals = <String>[];
      for (int c = minC; c <= maxC; c++) {
        rowVals.add(_getCellValue(m, c));
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
    final members = _filteredMembers;
    final minR = math.min(_selStartRow!, _selEndRow!);
    final maxR = math.max(_selStartRow!, _selEndRow!);
    final minC = math.min(_selStartCol!, _selEndCol!);

    bool modified = false;

    if (lines.length == 1 && !lines[0].contains('\t')) {
      final val = lines[0].trim();
      for (int r = minR; r <= maxR; r++) {
        if (r >= members.length) break;
        final mid = members[r]['id'].toString();
        widget.reportData.putIfAbsent(mid, () => {});
        for (int c = minC; c <= math.max(_selStartCol!, _selEndCol!); c++) {
          if (_setEditableValue(mid, c, val)) modified = true;
        }
      }
    } else {
      for (int i = 0; i < lines.length; i++) {
        final r = minR + i;
        if (r >= members.length) break;
        final mid = members[r]['id'].toString();
        widget.reportData.putIfAbsent(mid, () => {});
        final cells = lines[i].split('\t');
        for (int j = 0; j < cells.length; j++) {
          final c = minC + j;
          if (c > _colTitles.length - 1) break;
          if (_setEditableValue(mid, c, cells[j].trim())) modified = true;
        }
      }
    }

    if (modified) {
      widget.onChanged();
      setState(() {});
    }
  }

  bool _setEditableValue(String mid, int c, String? val) {
    if (c == 7) { widget.reportData[mid]!['attendance_pre'] = val; return true; }
    if (c == 8) { widget.reportData[mid]!['attendance_realtime'] = val; return true; }
    if (c == 9) { widget.reportData[mid]!['attendance_makeup'] = val; return true; }
    if (c == 10) { widget.reportData[mid]!['place'] = val; return true; }
    if (c == 11) { widget.reportData[mid]!['situation_notes'] = val; return true; } // Aligned with DB
    if (c == 12) { widget.reportData[mid]!['strategy_notes'] = val; return true; }
    return false;
  }

  void _clearSelection() {
    if (_selStartRow == null) return;
    final members = _filteredMembers;
    final minR = math.min(_selStartRow!, _selEndRow!);
    final maxR = math.max(_selStartRow!, _selEndRow!);
    final minC = math.min(_selStartCol!, _selEndCol!);
    final maxC = math.max(_selStartCol!, _selEndCol!);

    bool modified = false;
    for (int r = minR; r <= maxR; r++) {
      if (r >= members.length) break;
      final mid = members[r]['id'].toString();
      widget.reportData.putIfAbsent(mid, () => {});
      for (int c = minC; c <= maxC; c++) {
        if (_setEditableValue(mid, c, null)) modified = true;
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
      items: [
        PopupMenuItem(value: 'copy', height: 32, child: Row(children: [Icon(Icons.copy, size: 14), SizedBox(width: 8), Text("Copy", style: TextStyle(fontSize: 12)), Spacer(), Text("Ctrl+C", style: TextStyle(fontSize: 10, color: AppPalette.fg(Colors.grey)))])),
        PopupMenuItem(value: 'paste', height: 32, child: Row(children: [Icon(Icons.paste, size: 14), SizedBox(width: 8), Text("Paste", style: TextStyle(fontSize: 12)), Spacer(), Text("Ctrl+V", style: TextStyle(fontSize: 10, color: AppPalette.fg(Colors.grey)))])),
        PopupMenuItem(value: 'clear', height: 32, child: Row(children: [Icon(Icons.backspace_outlined, size: 14, color: AppPalette.fg(Colors.red)), SizedBox(width: 8), Text("Clear Selection", style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.red))), Spacer(), Text("Del", style: TextStyle(fontSize: 10, color: AppPalette.fg(Colors.grey)))])),
        PopupMenuDivider(height: 1),
        PopupMenuItem(value: 'row', height: 32, child: Row(children: [Icon(Icons.table_rows_outlined, size: 14), SizedBox(width: 8), Text("Select Entire Row", style: TextStyle(fontSize: 12))])),
        PopupMenuItem(value: 'col', height: 32, child: Row(children: [Icon(Icons.view_column_outlined, size: 14), SizedBox(width: 8), Text("Select Entire Column", style: TextStyle(fontSize: 12))])),
        PopupMenuItem(value: 'all', height: 32, child: Row(children: [Icon(Icons.select_all, size: 14), SizedBox(width: 8), Text("Select All", style: TextStyle(fontSize: 12)), Spacer(), Text("Ctrl+A", style: TextStyle(fontSize: 10, color: AppPalette.fg(Colors.grey)))])),
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
    for (final m in widget.members) {
      final val = _getCellValue(m, colIdx);
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
                    decoration: InputDecoration(hintText: tr("Search..."), isDense: true, prefixIcon: const Icon(Icons.search, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                    onChanged: (q) => setDialogState(() => query = q),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    TextButton(onPressed: () => setDialogState(() => temp.addAll(distinct)), child: const Text("Select All", style: TextStyle(fontSize: 11))),
                    const Spacer(),
                    TextButton(onPressed: () => setDialogState(() => temp.clear()), child: Text("Clear All", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.red)))),
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
                style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(widget.pPurple), foregroundColor: AppPalette.fg(Colors.white)),
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

  // ---- show / hide columns (remembered on this device)
  final Set<int> _hiddenCols = {};
  String get _hideKey => 'entry_hidden_cols_${widget.runtimeType}';

  Future<void> _loadHiddenCols() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getStringList(_hideKey) ?? const [];
      if (!mounted) return;
      setState(() {
        _hiddenCols
          ..clear()
          ..addAll(saved.map(int.tryParse).whereType<int>().where((c) => c >= 0 && c < _colTitles.length));
      });
    } catch (_) {}
  }

  Future<void> _saveHiddenCols() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_hideKey, [for (final c in _hiddenCols) '$c']);
    } catch (_) {}
  }

  void _chooseColumns(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text("Show / hide columns"),
          content: SizedBox(
            width: 320,
            child: ListView(shrinkWrap: true, children: [
              Text("The first column shown stays fixed on the left.", style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
              for (int c = 0; c < _colTitles.length; c++)
                CheckboxListTile(
                  dense: true,
                  value: !_hiddenCols.contains(c),
                  title: Text("${_colLetters[c]} · ${_colTitles[c]}"),
                  onChanged: (v) {
                    if (v == false && _colTitles.length - _hiddenCols.length <= 1) return;
                    set(() => v == true ? _hiddenCols.remove(c) : _hiddenCols.add(c));
                    setState(() {});
                    _saveHiddenCols();
                  },
                ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () {
                set(_hiddenCols.clear);
                setState(() {});
                _saveHiddenCols();
              },
              child: const Text("Show all"),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text("Done")),
          ],
        ),
      ),
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
            // Hidden columns are left out; the first column shown stays fixed
            // on the left (with the row numbers) and the header rows stay on
            // top while the rest scrolls both ways.
            final vis = [for (int c = 0; c < _colTitles.length; c++) if (!_hiddenCols.contains(c)) c];
            final availWidth = constraints.maxWidth - _rowNumColWidth;
            final baseSum = vis.fold<double>(0, (s, c) => s + _baseWidths[c]);
            final scale = (baseSum > 0 && availWidth > baseSum) ? (availWidth / baseSum) : 1.0;
            final widths = _baseWidths.map((w) => w * scale).toList();
            final rest = vis; // only the row numbers (and the header rows) stay fixed
            final totalTableWidth = rest.fold<double>(0, (s, c) => s + widths[c]);
            final filtered = _filteredMembers;

            Widget letter(int i) {
              final isColSel = _selStartCol != null &&
                  i >= math.min(_selStartCol!, _selEndCol!) &&
                  i <= math.max(_selStartCol!, _selEndCol!) &&
                  _selStartRow == 0 &&
                  _selEndRow == filtered.length - 1;
              return GestureDetector(
                onTap: () => _selectColumn(i),
                child: Container(
                  width: widths[i],
                  height: _alphaHeaderHeight,
                  color: AppPalette.bg(isColSel ? widget.pPurple.withValues(alpha: 0.25) : const Color(0xFFF1F5F9)),
                  alignment: Alignment.center,
                  child: Text(_colLetters[i], style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppPalette.fg(isColSel ? widget.pPurple : Colors.grey[700]))),
                ),
              );
            }

            Widget title(int i) {
              final isFiltered = _activeFilters.containsKey(i);
              return Container(
                width: widths[i],
                height: _titleHeaderHeight,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppPalette.bg(const Color(0xFF1E293B)),
                  border: Border(right: BorderSide(color: AppPalette.line(Colors.grey.withValues(alpha: 0.3)), width: 0.8)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _selectColumn(i),
                        child: Text(_colTitles[i], softWrap: false, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    InkWell(
                      onTap: () => _openFilterDialog(i),
                      child: Icon(isFiltered ? Icons.filter_alt : Icons.filter_alt_outlined, size: 13, color: AppPalette.fg(isFiltered ? const Color(0xFFF59E0B) : Colors.white70)),
                    ),
                  ],
                ),
              );
            }

            Widget rowNumber(int idx) {
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
                    color: AppPalette.bg(isRowSel ? widget.pPurple.withValues(alpha: 0.15) : const Color(0xFFF1F5F9)),
                    border: Border(
                      bottom: BorderSide(color: AppPalette.line(Colors.grey.withValues(alpha: 0.3)), width: 0.8),
                      right: BorderSide(color: AppPalette.line(Colors.grey.withValues(alpha: 0.4)), width: 1.2),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      "${idx + 1}",
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(isRowSel ? widget.pPurple : Colors.grey[700])),
                    ),
                  ),
                ),
              );
            }

            return Container(
              width: double.infinity,
              height: double.infinity,
              color: AppPalette.bg(Colors.white),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. FROZEN LEFT PANE: corner + row numbers + the first column shown
                  Container(
                    width: _rowNumColWidth,
                    decoration: BoxDecoration(
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(2, 0))],
                    ),
                    child: Column(
                      children: [
                        Row(children: [
                          Container(
                            height: _totalHeaderHeight,
                            width: _rowNumColWidth,
                            color: AppPalette.bg(const Color(0xFFE2E8F0)),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // show / hide columns (small screens)
                                InkWell(
                                  onTap: () => _chooseColumns(context),
                                  child: Tooltip(message: 'Show / hide columns', child: Icon(Icons.view_week_rounded, size: 15, color: AppPalette.fg(widget.pPurple))),
                                ),
                                const SizedBox(height: 4),
                                InkWell(
                                  onTap: _selectAll,
                                  child: Tooltip(message: 'Select all', child: Text("#", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                                ),
                              ],
                            ),
                          ),
                        ]),
                        Expanded(
                          child: ListView.builder(
                            controller: _rowNumScrollController,
                            physics: const ClampingScrollPhysics(),
                            itemCount: filtered.length,
                            itemExtent: _rowHeight,
                            itemBuilder: (ctx, idx) => Row(children: [
                              rowNumber(idx),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. SCROLLABLE DATA PANE (header fixed on top, rows virtualized)
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _horizScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                        width: totalTableWidth,
                        child: Column(
                          children: [
                            SizedBox(height: _alphaHeaderHeight, child: Row(children: [for (final i in rest) letter(i)])),
                            SizedBox(height: _titleHeaderHeight, child: Row(children: [for (final i in rest) title(i)])),
                            Expanded(
                              child: ListView.builder(
                                controller: _contentVertScrollController,
                                physics: const ClampingScrollPhysics(),
                                itemCount: filtered.length,
                                itemExtent: _rowHeight,
                                itemBuilder: (ctx, r) {
                                  final m = filtered[r];
                                  final isEven = r.isEven;
                                  return SizedBox(
                                    height: _rowHeight,
                                    child: Row(children: [for (final c in rest) _buildCell(m, r, c, widths[c], isEven)]),
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
            );
          },
        ),
      ),
    );
  }

  /// A text cell that isn't being edited is plain text: a field in every
  /// cell caught the finger's sideways drag (the grid stuck when scrolling
  /// on phones) and made typing slow. Tap the cell to type in it.
  Widget _readOnlyCell(String val, String? hint) => Text(
        val.isEmpty ? (hint ?? '') : val,
        textAlign: TextAlign.center,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: val.isEmpty
            ? TextStyle(fontSize: 10, color: AppPalette.fg(Colors.grey.shade400))
            : GoogleFonts.merriweather(fontSize: 10.5),
      );

  Widget _buildCell(dynamic m, int r, int c, double width, bool isEven) {
    final isSel = _isCellSelected(r, c);
    final isAnc = _isAnchor(r, c);
    final mid = m['id'].toString();
    widget.reportData.putIfAbsent(mid, () => {});

    Widget content;
    // Static columns: Location, Sub, Dept, Team, Cell, English Name, Duty
    if (c <= 6) {
      final t = _getCellValue(m, c);
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        child: Text(t, softWrap: false, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: c == 5 ? FontWeight.bold : FontWeight.normal)),
      );
    }
    // Place: choose the kind of place, then which one (location, sub-location,
    // home cell …); saved as text such as "Sub Location: Kyebando"
    else if (c == 10) {
      final val = _getCellValue(m, c);
      content = InkWell(
        onTap: () async {
          _selectCell(r, c);
          final v = await PlacePicker.pick(context, options: widget.optionsPlace, member: m, current: val);
          if (v == null || !mounted) return;
          widget.onChanged();
          setState(() => _setEditableValue(mid, c, v));
        },
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            Expanded(
              child: Text(val.isEmpty ? '—' : val,
                  textAlign: TextAlign.center, softWrap: false, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(val.isEmpty ? Colors.grey : Colors.black87), fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.arrow_drop_down_rounded, size: 16, color: AppPalette.fg(Colors.grey.shade600)),
          ]),
        ),
      );
    }
    // Dropdowns: Pre, Actual, Makeup
    else if (c >= 7 && c <= 9) {
      final List<String> opts = (c == 7)
          ? widget.optionsPre
          : (c == 8)
              ? widget.optionsActual
              : (c == 9)
                  ? widget.optionsMakeup
                  : widget.optionsPlace;
      final val = _getCellValue(m, c);
      content = DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: opts.contains(val) ? val : null,
          isDense: true, isExpanded: true, iconSize: 14,
          style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.black87), fontWeight: FontWeight.w600),
          items: opts.map((s) => DropdownMenuItem(value: s, child: Center(child: Text(s, softWrap: false, overflow: TextOverflow.ellipsis)))).toList(),
          onChanged: (v) {
            _selectCell(r, c);
            widget.onChanged();
            setState(() => _setEditableValue(mid, c, v));
          },
        ),
      );
    }
    // Text Inputs: Situation & Strategy
    else {
      final val = _getCellValue(m, c);
      content = Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _isAnchor(r, c)
            ? TextFormField(
          key: ValueKey("${mid}_$c"),
          initialValue: val,
          autofocus: true,
          textAlign: TextAlign.center,
          style: GoogleFonts.merriweather(fontSize: 10.5),
          decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4)),
          onTap: () => _selectCell(r, c),
          onChanged: (v) {
            widget.onChanged();
            _setEditableValue(mid, c, v);
          },
        )
            : _readOnlyCell(val, ''),
      );
    }

    return GestureDetector(
      onTap: () => _selectCell(r, c),
      onSecondaryTapDown: (d) => _showContextMenu(d.globalPosition, r, c),
      child: Container(
        width: width,
        height: _rowHeight,
        decoration: BoxDecoration(
          color: AppPalette.bg(isSel ? widget.pPurple.withValues(alpha: 0.12) : (isEven ? Colors.white : const Color(0xFFF8FAFC))),
          border: isAnc
              ? Border.all(color: AppPalette.line(widget.pPurple), width: 1.8)
              : Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.25)), width: 0.6),
        ),
        child: content,
      ),
    );
  }
}