// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_palette.dart';
import '../core/sheet_formula.dart';
import '../core/table_export.dart';
import '../widgets/office_shell.dart';

/// Cloud Sheets (Excel style): the original hub + ribbon layout with private
/// workbooks, several sheets, formulas (=SUM(A1:A9) …), templates, a
/// Functions tab, right-click menu, shortcuts, sorting, filter, Excel / CSV
/// import, Excel / PDF export and print preview. Saves automatically.
class SpreadsheetScreen extends StatefulWidget {
  final String title, userEmail, userRole;
  const SpreadsheetScreen({super.key, required this.title, required this.userEmail, required this.userRole});
  @override
  State<SpreadsheetScreen> createState() => _SpreadsheetScreenState();
}

const Color _kPurple = Color(0xFF4A148C);
const Color _kGreen = Color(0xFF1B5E20);

class _Sheet {
  String? id; // spreadsheet_contents.id
  String name;
  List<List<String>> raw; // [row][col]
  _Sheet({this.id, required this.name, required this.raw});

  int get rows => raw.length;
  int get cols => raw.isEmpty ? 0 : raw.first.length;

  static List<List<String>> blank(int r, int c) => List.generate(r, (_) => List.filled(c, '', growable: true), growable: true);

  String at(int r, int c) => (r >= 0 && r < raw.length && c >= 0 && c < raw[r].length) ? raw[r][c] : '';

  void ensure(int r, int c) {
    final cols = c > this.cols ? c : this.cols;
    for (final row in raw) {
      while (row.length < cols) {
        row.add('');
      }
    }
    while (raw.length < r) {
      raw.add(List.filled(cols, '', growable: true));
    }
  }

  /// Last row / column that has something in it.
  (int, int) get usedRange {
    int lastR = -1, lastC = -1;
    for (int r = 0; r < raw.length; r++) {
      for (int c = 0; c < raw[r].length; c++) {
        if (raw[r][c].isNotEmpty) {
          if (r > lastR) lastR = r;
          if (c > lastC) lastC = c;
        }
      }
    }
    return (lastR, lastC);
  }

  Map<String, dynamic> toJson() {
    // trim empty trailing rows / columns to keep saves small, but remember the grid size
    final (lastR, lastC) = usedRange;
    return {
      'v': 2,
      'nrows': rows,
      'ncols': cols,
      'cells': [for (int r = 0; r <= lastR; r++) raw[r].sublist(0, lastC + 1)],
    };
  }

  static _Sheet fromJson(String? id, String name, dynamic data) {
    if (data is Map && data['v'] == 2) {
      final nr = (data['nrows'] as num?)?.toInt() ?? 100;
      final nc = (data['ncols'] as num?)?.toInt() ?? 26;
      final s = _Sheet(id: id, name: name, raw: blank(nr < 1 ? 1 : nr, nc < 1 ? 1 : nc));
      final cells = data['cells'] as List? ?? const [];
      for (int r = 0; r < cells.length; r++) {
        final row = cells[r] as List? ?? const [];
        for (int c = 0; c < row.length; c++) {
          s.ensure(r + 1, c + 1);
          s.raw[r][c] = (row[c] ?? '').toString();
        }
      }
      return s;
    }
    // Older saves: a list of {r: 1, c0: ..., c25: ...}
    final s = _Sheet(id: id, name: name, raw: blank(100, 26));
    if (data is List) {
      for (int r = 0; r < data.length; r++) {
        final m = data[r];
        if (m is! Map) continue;
        s.ensure(r + 1, 26);
        for (int c = 0; c < 26; c++) {
          final v = m['c$c'];
          if (v != null) s.raw[r][c] = v.toString();
        }
      }
    }
    return s;
  }

  /// A sheet filled from [rows] (padded to at least 100 × 26).
  static _Sheet filled(String name, List<List<String>> rows) {
    final s = _Sheet(name: name, raw: [for (final r in rows) List<String>.from(r, growable: true)]);
    if (s.raw.isEmpty) s.raw = blank(1, 1);
    s.ensure(s.rows < 100 ? 100 : s.rows + 20, s.cols < 26 ? 26 : s.cols);
    return s;
  }
}

// ---------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------
List<List<String>> _rowsN(List<String> header, int n, List<String> Function(int row) body) => [header, for (int i = 0; i < n; i++) body(i + 2)];

final Map<String, List<_Sheet> Function()> _templateSheets = {
  'blank': () => [_Sheet(name: 'Sheet 1', raw: _Sheet.blank(100, 26))],
  'budget': () => [
        _Sheet.filled('Budget', [
          ['Item', 'Category', 'Planned (UGX)', 'Actual (UGX)', 'Difference'],
          for (int r = 2; r <= 16; r++) ['', '', '', '', '=C$r-D$r'],
          ['TOTAL', '', '=SUM(C2:C16)', '=SUM(D2:D16)', '=C17-D17'],
        ]),
      ],
  'attendance': () => [
        _Sheet.filled('Attendance', _rowsN(['No.', 'Name', 'Cell / Team', 'Wk 1', 'Wk 2', 'Wk 3', 'Wk 4', 'Wk 5', 'Present', 'Rate'], 30,
            (r) => ['${r - 1}', '', '', '', '', '', '', '', '=COUNTIF(D$r:H$r,"P")', '=ROUND(I$r/5*100,0)'])
          ..add(['', 'Write P for present, A for absent', '', '', '', '', '', '', '', ''])),
      ],
  'contacts': () => [
        _Sheet.filled('Contacts', _rowsN(['No.', 'Full name', 'Phone', 'Email', 'Cell / Team', 'Department', 'Birthday', 'Notes'], 40, (r) => ['${r - 1}', '', '', '', '', '', '', ''])),
      ],
  'offering': () => [
        _Sheet.filled('Offering', [
          ['Date', 'Name', 'Tithe', 'Weekly', 'Thanks', 'Construction', 'Other', 'Total'],
          for (int r = 2; r <= 31; r++) ['', '', '', '', '', '', '', '=SUM(C$r:G$r)'],
          ['TOTAL', '', '=SUM(C2:C31)', '=SUM(D2:D31)', '=SUM(E2:E31)', '=SUM(F2:F31)', '=SUM(G2:G31)', '=SUM(H2:H31)'],
        ]),
      ],
  'event': () => [
        _Sheet.filled('Plan', _rowsN(['Task', 'Owner', 'Due date', 'Status', 'Cost (UGX)', 'Notes'], 20, (r) => ['', '', '', 'Not started', '', ''])
          ..add(['TOTAL COST', '', '', '', '=SUM(E2:E21)', ''])),
        _Sheet.filled('Guests', _rowsN(['Name', 'Phone', 'Invited by', 'Confirmed (Y/N)'], 50, (r) => ['', '', '', ''])
          ..add(['Confirmed', '', '', '=COUNTIF(D2:D51,"Y")'])),
      ],
  'inventory': () => [
        _Sheet.filled('Inventory', [
          ['Item', 'Location', 'Quantity', 'Unit cost (UGX)', 'Value', 'Condition'],
          for (int r = 2; r <= 31; r++) ['', '', '', '', '=C$r*D$r', ''],
          ['TOTAL', '', '=SUM(C2:C31)', '', '=SUM(E2:E31)', ''],
        ]),
      ],
  'weekly': () => [
        _Sheet.filled('Weekly report', [
          ['Unit', 'Members', 'Service', 'Cell service', 'Education', 'Evangelism', 'Offering', 'Attendance %'],
          for (int r = 2; r <= 13; r++) ['', '', '', '', '', '', '', '=IF(B$r>0,ROUND(C$r/B$r*100,1),"")'],
          ['TOTAL', '=SUM(B2:B13)', '=SUM(C2:C13)', '=SUM(D2:D13)', '=SUM(E2:E13)', '=SUM(F2:F13)', '=SUM(G2:G13)', '=IF(B14>0,ROUND(C14/B14*100,1),"")'],
        ]),
      ],
  'tasks': () => [
        _Sheet.filled('Tasks', _rowsN(['Task', 'Assigned to', 'Start', 'Due', 'Priority', 'Status', 'Done?'], 30, (r) => ['', '', '', '', 'Normal', 'Open', ''])
          ..add(['Done', '', '', '', '', '', '=COUNTIF(G2:G31,"Y")'])),
      ],
  'timetable': () => [
        _Sheet.filled('Timetable', [
          ['Time', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
          for (final t in const ['06:00', '07:00', '08:00', '09:00', '10:00', '11:00', '12:00', '14:00', '16:00', '18:00', '19:00', '20:00']) [t, '', '', '', '', '', '', ''],
        ]),
      ],
};

Widget _miniGrid(List<List<String>> rows) {
  // darkify:off — template previews look like paper
  final shown = rows.take(6).map((r) => r.take(5).toList()).toList();
  return Container(
    width: 260,
    height: 150,
    color: Colors.white,
    child: Table(
      border: TableBorder.all(color: const Color(0xFFCBD5E1), width: 0.6),
      children: [
        for (int i = 0; i < shown.length; i++)
          TableRow(
            decoration: BoxDecoration(color: i == 0 ? const Color(0xFFE8F5E9) : Colors.white),
            children: [
              for (int c = 0; c < 5; c++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                  child: Text(
                    c < shown[i].length && !shown[i][c].startsWith('=') ? shown[i][c] : (c < shown[i].length && shown[i][c].isNotEmpty ? 'ƒ' : ''),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(fontSize: 9, color: const Color(0xFF1F2937), fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal),
                  ),
                ),
            ],
          ),
      ],
    ),
  );
  // darkify:on
}

final List<OfficeTemplate> _templates = [
  OfficeTemplate('blank', 'Blank sheet', 'An empty grid', Icons.grid_on_rounded),
  OfficeTemplate('budget', 'Budget', 'Planned vs actual with totals', Icons.account_balance_wallet_outlined, preview: () => _miniGrid(_templateSheets['budget']!().first.raw)),
  OfficeTemplate('attendance', 'Attendance register', '5 weeks, present count and rate', Icons.how_to_reg_outlined, preview: () => _miniGrid(_templateSheets['attendance']!().first.raw)),
  OfficeTemplate('contacts', 'Member contacts', 'Name, phone, unit, birthday', Icons.contacts_outlined, preview: () => _miniGrid(_templateSheets['contacts']!().first.raw)),
  OfficeTemplate('offering', 'Offering record', 'Per person, per type, with totals', Icons.volunteer_activism_outlined, preview: () => _miniGrid(_templateSheets['offering']!().first.raw)),
  OfficeTemplate('event', 'Event planner', 'Tasks, costs and a guest list', Icons.event_available_outlined, preview: () => _miniGrid(_templateSheets['event']!().first.raw)),
  OfficeTemplate('inventory', 'Inventory', 'Items, quantity and value', Icons.inventory_2_outlined, preview: () => _miniGrid(_templateSheets['inventory']!().first.raw)),
  OfficeTemplate('weekly', 'Weekly unit report', 'Duties per unit with attendance %', Icons.summarize_outlined, preview: () => _miniGrid(_templateSheets['weekly']!().first.raw)),
  OfficeTemplate('tasks', 'Task tracker', 'Owner, dates, priority, status', Icons.task_alt_outlined, preview: () => _miniGrid(_templateSheets['tasks']!().first.raw)),
  OfficeTemplate('timetable', 'Timetable', 'A week by the hour', Icons.calendar_view_week_outlined, preview: () => _miniGrid(_templateSheets['timetable']!().first.raw)),
];

const Map<String, String> _templateTitles = {
  'blank': 'Untitled spreadsheet',
  'budget': 'Budget',
  'attendance': 'Attendance register',
  'contacts': 'Member contacts',
  'offering': 'Offering record',
  'event': 'Event planner',
  'inventory': 'Inventory',
  'weekly': 'Weekly unit report',
  'tasks': 'Task tracker',
  'timetable': 'Timetable',
};

// Functions tab: what the formula engine supports
const Map<String, List<(String, String, String)>> _functions = {
  'Math': [
    ('SUM', '=SUM(range)', 'Adds the numbers'),
    ('AVERAGE', '=AVERAGE(range)', 'Average of the numbers'),
    ('MIN', '=MIN(range)', 'Smallest number'),
    ('MAX', '=MAX(range)', 'Largest number'),
    ('ROUND', '=ROUND(A1,0)', 'Rounds to N decimals'),
    ('ABS', '=ABS(A1)', 'Value without the sign'),
  ],
  'Count': [
    ('COUNT', '=COUNT(range)', 'How many numbers'),
    ('COUNTA', '=COUNTA(range)', 'How many filled cells'),
    ('COUNTIF', '=COUNTIF(range,"P")', 'How many match'),
    ('SUMIF', '=SUMIF(range,">0")', 'Adds the ones that match'),
  ],
  'Logic': [
    ('IF', '=IF(A1>50,"Pass","Fail")', 'One value or another'),
    ('AND', '=AND(A1>0,B1>0)', 'All are true'),
    ('OR', '=OR(A1>0,B1>0)', 'Any is true'),
    ('NOT', '=NOT(A1>0)', 'The opposite'),
  ],
  'Text': [
    ('CONCAT', '=CONCAT(A1," ",B1)', 'Joins text'),
    ('LEN', '=LEN(A1)', 'Number of characters'),
    ('UPPER', '=UPPER(A1)', 'CAPITAL LETTERS'),
    ('LOWER', '=LOWER(A1)', 'small letters'),
    ('TRIM', '=TRIM(A1)', 'Removes extra spaces'),
  ],
  'Date': [
    ('TODAY', '=TODAY()', "Today's date"),
  ],
};

class _SpreadsheetScreenState extends State<SpreadsheetScreen> {
  final _db = Supabase.instance.client;

  // hub
  List<Map<String, dynamic>> _books = [];
  bool _loadingBooks = true;
  String _search = '';

  // editor
  bool _open = false;
  String? _bookId;
  final _titleC = TextEditingController();
  List<_Sheet> _sheets = [];
  final List<String> _deletedSheetIds = [];
  int _active = 0;
  int _gridVersion = 0;
  PlutoGridStateManager? _sm;
  final _fxC = TextEditingController();
  final _fxFocus = FocusNode();
  int _curRow = 0, _curCol = 0;
  Timer? _saveTimer;
  String _saveState = 'saved';
  late SheetEngine _engine;

  // layout
  int _tab = 1; // File, Home, Insert, Data, Functions, View
  double _zoom = 1.0;
  bool _showFormulas = false;
  bool _freezeFirst = false;

  _Sheet get _sheet => _sheets[_active];

  @override
  void initState() {
    super.initState();
    OfficeBrowserMenu.acquire();
    _loadBooks();
  }

  @override
  void dispose() {
    OfficeBrowserMenu.release();
    _saveTimer?.cancel();
    if (_open && _saveState == 'unsaved') _save();
    _titleC.dispose();
    _fxC.dispose();
    _fxFocus.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  // ------------------------------------------------------------------
  // Data
  // ------------------------------------------------------------------
  Future<void> _loadBooks() async {
    setState(() => _loadingBooks = true);
    try {
      final r = await _db.from('workbooks').select('id, title, last_modified, created_at').order('last_modified', ascending: false);
      if (mounted) {
        setState(() {
          _books = List<Map<String, dynamic>>.from(r);
          _loadingBooks = false;
        });
      }
    } catch (e) {
      debugPrint("Workbooks error: $e");
      if (mounted) setState(() => _loadingBooks = false);
    }
  }

  Future<String> _newBook(String title, List<_Sheet> sheets) async {
    final wb = await _db.from('workbooks').insert({'title': title, 'owner_email': widget.userEmail}).select('id').single();
    final id = wb['id'].toString();
    for (int i = 0; i < sheets.length; i++) {
      final row = await _db.from('spreadsheet_contents').insert({'workbook_id': id, 'sheet_name': sheets[i].name, 'grid_data': sheets[i].toJson(), 'sort_order': i}).select('id').single();
      sheets[i].id = row['id'].toString();
    }
    return id;
  }

  Future<void> _create(OfficeTemplate t) async {
    try {
      if (_open) await _close();
      final sheets = (_templateSheets[t.key] ?? _templateSheets['blank']!)();
      final id = await _newBook(_templateTitles[t.key] ?? t.name, sheets);
      await _openBook(id);
    } catch (e) {
      _snack("Couldn't create the spreadsheet: ${e is PostgrestException ? e.message : e}");
    }
  }

  Future<void> _pickTemplate() async {
    final t = await showOfficeTemplates(context, title: "Sheet templates", templates: _templates, accent: _kGreen);
    if (t != null) await _create(t);
  }

  Future<void> _openBook(String id) async {
    try {
      final wb = await _db.from('workbooks').select().eq('id', id).single();
      final rows = await _db.from('spreadsheet_contents').select().eq('workbook_id', id);
      final list = List<Map<String, dynamic>>.from(rows)
        ..sort((a, b) {
          final o = ((a['sort_order'] as num?) ?? 0).compareTo((b['sort_order'] as num?) ?? 0);
          return o != 0 ? o : (a['sheet_name'] ?? '').toString().compareTo((b['sheet_name'] ?? '').toString());
        });
      final sheets = list.map((r) => _Sheet.fromJson(r['id']?.toString(), (r['sheet_name'] ?? 'Sheet').toString(), r['grid_data'])).toList();
      if (sheets.isEmpty) sheets.add(_Sheet(name: 'Sheet 1', raw: _Sheet.blank(100, 26)));
      setState(() {
        _bookId = id;
        _titleC.text = (wb['title'] ?? 'Untitled spreadsheet').toString();
        _sheets = sheets;
        _deletedSheetIds.clear();
        _active = 0;
        _curRow = 0;
        _curCol = 0;
        _rebuildEngine();
        _fxC.text = _sheet.at(0, 0);
        _gridVersion++;
        _saveState = 'saved';
        _open = true;
      });
    } catch (e) {
      _snack("Couldn't open the spreadsheet.");
    }
  }

  void _markDirty() {
    setState(() => _saveState = 'unsaved');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), _save);
  }

  Future<void> _save() async {
    final id = _bookId;
    if (id == null) return;
    _saveTimer?.cancel();
    if (mounted) setState(() => _saveState = 'saving');
    try {
      for (final sid in List<String>.from(_deletedSheetIds)) {
        await _db.from('spreadsheet_contents').delete().eq('id', sid);
        _deletedSheetIds.remove(sid);
      }
      for (int i = 0; i < _sheets.length; i++) {
        final s = _sheets[i];
        final data = {'sheet_name': s.name, 'grid_data': s.toJson(), 'sort_order': i, 'updated_at': DateTime.now().toUtc().toIso8601String()};
        if (s.id == null) {
          final row = await _db.from('spreadsheet_contents').insert({...data, 'workbook_id': id}).select('id').single();
          s.id = row['id'].toString();
        } else {
          await _db.from('spreadsheet_contents').update(data).eq('id', s.id!);
        }
      }
      await _db.from('workbooks').update({
        'title': _titleC.text.trim().isEmpty ? 'Untitled spreadsheet' : _titleC.text.trim(),
        'last_modified': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      if (mounted) setState(() => _saveState = 'saved');
    } catch (e) {
      debugPrint("Sheet save error: $e");
      if (mounted) {
        setState(() => _saveState = 'error');
        _snack(e is PostgrestException && e.code == '23505' ? "Two sheets have the same name. Rename one." : "Couldn't save the spreadsheet.");
      }
    }
  }

  Future<void> _close() async {
    if (_saveState != 'saved') await _save();
    if (!mounted) return;
    setState(() {
      _open = false;
      _sm = null;
    });
    _loadBooks();
  }

  Future<void> _renameBook(Map<String, dynamic> b) async {
    final name = await officeAsk(context, "Rename spreadsheet", (b['title'] ?? '').toString(), ok: "Rename");
    if (name == null || name.isEmpty) return;
    await _db.from('workbooks').update({'title': name}).eq('id', b['id']);
    _loadBooks();
  }

  Future<void> _duplicateBook(Map<String, dynamic> b) async {
    try {
      final rows = await _db.from('spreadsheet_contents').select().eq('workbook_id', b['id']);
      final list = List<Map<String, dynamic>>.from(rows)..sort((a, c) => ((a['sort_order'] as num?) ?? 0).compareTo((c['sort_order'] as num?) ?? 0));
      final sheets = list.map((r) => _Sheet.fromJson(null, (r['sheet_name'] ?? 'Sheet').toString(), r['grid_data'])).toList();
      await _newBook("${b['title'] ?? 'Spreadsheet'} (copy)", sheets.isEmpty ? [_Sheet(name: 'Sheet 1', raw: _Sheet.blank(100, 26))] : sheets);
      _loadBooks();
      _snack("Copy made.");
    } catch (_) {
      _snack("Couldn't duplicate it.");
    }
  }

  Future<void> _deleteBook(Map<String, dynamic> b) async {
    if (!await officeConfirm(context, "Delete \"${b['title']}\"?", "All its sheets are deleted. This can't be undone.")) return;
    await _db.from('spreadsheet_contents').delete().eq('workbook_id', b['id']);
    await _db.from('workbooks').delete().eq('id', b['id']);
    _loadBooks();
  }

  // ------------------------------------------------------------------
  // Formulas
  // ------------------------------------------------------------------
  void _rebuildEngine() {
    final s = _sheet;
    _engine = SheetEngine((r, c) => s.at(r, c), maxRows: s.rows, maxCols: s.cols);
  }

  String _display(int r, int c) => _engine.display(r, c);

  String _shown(int r, int c) {
    final raw = _sheet.at(r, c);
    return raw.startsWith('=') && !_showFormulas ? _display(r, c) : raw;
  }

  /// After any edit: recompute formula cells and refresh what changed.
  void _refreshFormulas() {
    final sm = _sm;
    if (sm == null || _showFormulas) return;
    _engine.clearCache();
    bool changed = false;
    for (int r = 0; r < _sheet.rows && r < sm.refRows.length; r++) {
      final row = sm.refRows[r];
      for (int c = 0; c < _sheet.cols; c++) {
        final raw = _sheet.raw[r][c];
        if (!raw.startsWith('=')) continue;
        final cell = row.cells['c$c'];
        if (cell == null) continue;
        final d = _display(r, c);
        if (cell.value?.toString() != d) {
          sm.changeCellValue(cell, d, callOnChangedEvent: false, force: true, notify: false);
          changed = true;
        }
      }
    }
    if (changed) sm.notifyListeners();
  }

  void _setRaw(int r, int c, String value, {bool updateGrid = true}) {
    _sheet.ensure(r + 1, c + 1);
    _sheet.raw[r][c] = value;
    if (updateGrid && _sm != null && r < _sm!.refRows.length) {
      final cell = _sm!.refRows[r].cells['c$c'];
      if (cell != null) {
        _engine.clearCache();
        _sm!.changeCellValue(cell, _shown(r, c), callOnChangedEvent: false, force: true, notify: true);
      }
    }
    _refreshFormulas();
    if (r == _curRow && c == _curCol && !_fxFocus.hasFocus) _fxC.text = value;
    _markDirty();
  }

  void _onGridChanged(PlutoGridOnChangedEvent e) {
    final field = e.column.field;
    if (!field.startsWith('c')) return;
    final c = int.tryParse(field.substring(1));
    if (c == null) return;
    final r = e.rowIdx;
    final v = (e.value ?? '').toString();
    _sheet.ensure(r + 1, c + 1);
    _sheet.raw[r][c] = v;
    if (v.startsWith('=') && !_showFormulas) {
      _engine.clearCache();
      final cell = e.row.cells[field];
      if (cell != null) _sm?.changeCellValue(cell, _display(r, c), callOnChangedEvent: false, force: true);
    }
    _refreshFormulas();
    if (r == _curRow && c == _curCol) _fxC.text = v;
    _markDirty();
  }

  void _onGridState() {
    final sm = _sm;
    if (sm == null) return;
    final r = sm.currentRowIdx;
    final String? f = sm.currentColumnField;
    if (r == null || f == null || !f.startsWith('c')) return;
    final c = int.tryParse(f.substring(1));
    if (c == null || (r == _curRow && c == _curCol)) return;
    setState(() {
      _curRow = r;
      _curCol = c;
      if (!_fxFocus.hasFocus) _fxC.text = _sheet.at(r, c);
    });
  }

  // ------------------------------------------------------------------
  // Structure
  // ------------------------------------------------------------------
  void _rebuildGrid() {
    setState(() {
      _rebuildEngine();
      _gridVersion++;
      _sm = null;
    });
  }

  void _insertRow({required bool below}) {
    final at = (below ? _curRow + 1 : _curRow).clamp(0, _sheet.rows);
    _sheet.raw.insert(at, List.filled(_sheet.cols, '', growable: true));
    _rebuildGrid();
    _markDirty();
  }

  void _deleteRow() {
    if (_sheet.rows <= 1) return;
    _sheet.raw.removeAt(_curRow.clamp(0, _sheet.rows - 1));
    if (_curRow >= _sheet.rows) _curRow = _sheet.rows - 1;
    _rebuildGrid();
    _markDirty();
  }

  void _insertCol({required bool right}) {
    final at = (right ? _curCol + 1 : _curCol).clamp(0, _sheet.cols);
    for (final row in _sheet.raw) {
      row.insert(at, '');
    }
    _rebuildGrid();
    _markDirty();
  }

  void _deleteCol() {
    if (_sheet.cols <= 1) return;
    final at = _curCol.clamp(0, _sheet.cols - 1);
    for (final row in _sheet.raw) {
      if (at < row.length) row.removeAt(at);
    }
    if (_curCol >= _sheet.cols) _curCol = _sheet.cols - 1;
    _rebuildGrid();
    _markDirty();
  }

  void _addRows(int n) {
    _sheet.ensure(_sheet.rows + n, _sheet.cols);
    _rebuildGrid();
    _markDirty();
  }

  void _addCols(int n) {
    _sheet.ensure(_sheet.rows, _sheet.cols + n);
    _rebuildGrid();
    _markDirty();
  }

  void _sort({required bool ascending, required bool hasHeader}) {
    final c = _curCol;
    final start = hasHeader ? 1 : 0;
    if (_sheet.rows <= start + 1) return;
    final body = _sheet.raw.sublist(start);
    final filled = body.where((r) => r.any((v) => v.isNotEmpty)).toList();
    final empty = body.where((r) => r.every((v) => v.isEmpty)).toList();
    int cmp(List<String> a, List<String> b) {
      final x = c < a.length ? a[c] : '', y = c < b.length ? b[c] : '';
      if (x.isEmpty && y.isEmpty) return 0;
      if (x.isEmpty) return 1;
      if (y.isEmpty) return -1;
      final nx = num.tryParse(x.replaceAll(',', '')), ny = num.tryParse(y.replaceAll(',', ''));
      final r = (nx != null && ny != null) ? nx.compareTo(ny) : x.toLowerCase().compareTo(y.toLowerCase());
      return ascending ? r : -r;
    }

    filled.sort(cmp);
    _sheet.raw
      ..removeRange(start, _sheet.raw.length)
      ..addAll([...filled, ...empty]);
    _rebuildGrid();
    _markDirty();
  }

  void _removeDuplicates() {
    final seen = <String>{};
    int removed = 0;
    final kept = <List<String>>[];
    for (final r in _sheet.raw) {
      final key = r.join('\u0001');
      if (r.every((v) => v.isEmpty)) {
        kept.add(r);
      } else if (seen.add(key)) {
        kept.add(r);
      } else {
        removed++;
      }
    }
    if (removed == 0) {
      _snack("No duplicate rows found.");
      return;
    }
    _sheet.raw = kept;
    _rebuildGrid();
    _markDirty();
    _snack("$removed duplicate row(s) removed.");
  }

  void _toggleFilter() {
    final sm = _sm;
    if (sm == null) return;
    sm.setShowColumnFilter(!sm.showColumnFilter);
    setState(() {});
  }

  void _addSheet() {
    var n = _sheets.length + 1;
    while (_sheets.any((s) => s.name == 'Sheet $n')) {
      n++;
    }
    setState(() {
      _sheets.add(_Sheet(name: 'Sheet $n', raw: _Sheet.blank(100, 26)));
      _active = _sheets.length - 1;
    });
    _rebuildGrid();
    _markDirty();
  }

  void _switchSheet(int i) {
    if (i == _active || i < 0 || i >= _sheets.length) return;
    setState(() {
      _active = i;
      _curRow = 0;
      _curCol = 0;
      _fxC.text = _sheet.at(0, 0);
    });
    _rebuildGrid();
  }

  Future<void> _renameSheet(int i) async {
    final name = await officeAsk(context, "Rename sheet", _sheets[i].name, ok: "Rename");
    if (name == null || name.isEmpty) return;
    if (_sheets.any((s) => s != _sheets[i] && s.name.toLowerCase() == name.toLowerCase())) {
      _snack("Another sheet already has that name.");
      return;
    }
    setState(() => _sheets[i].name = name);
    _markDirty();
  }

  void _duplicateSheet(int i) {
    final src = _sheets[i];
    var name = "${src.name} (copy)";
    while (_sheets.any((s) => s.name == name)) {
      name = "$name+";
    }
    setState(() {
      _sheets.insert(i + 1, _Sheet(name: name, raw: [for (final r in src.raw) List<String>.from(r, growable: true)]));
      _active = i + 1;
    });
    _rebuildGrid();
    _markDirty();
  }

  Future<void> _deleteSheet(int i) async {
    if (_sheets.length <= 1) return;
    if (!await officeConfirm(context, "Delete sheet \"${_sheets[i].name}\"?", "Its cells are deleted when the spreadsheet saves.")) return;
    setState(() {
      final s = _sheets.removeAt(i);
      if (s.id != null) _deletedSheetIds.add(s.id!);
      if (_active >= _sheets.length) _active = _sheets.length - 1;
    });
    _rebuildGrid();
    _markDirty();
  }

  void _moveSheet(int i, int d) {
    final to = i + d;
    if (to < 0 || to >= _sheets.length) return;
    setState(() {
      final s = _sheets.removeAt(i);
      _sheets.insert(to, s);
      _active = to;
    });
    _rebuildGrid();
    _markDirty();
  }

  List<OfficeMenuItem> _sheetMenuItems(int i) => [
        OfficeMenuItem("Rename", icon: Icons.drive_file_rename_outline, onTap: () => _renameSheet(i)),
        OfficeMenuItem("Duplicate", icon: Icons.copy_rounded, onTap: () => _duplicateSheet(i)),
        OfficeMenuItem("Move left", icon: Icons.chevron_left, onTap: i > 0 ? () => _moveSheet(i, -1) : null),
        OfficeMenuItem("Move right", icon: Icons.chevron_right, onTap: i < _sheets.length - 1 ? () => _moveSheet(i, 1) : null),
        const OfficeMenuItem.divider(),
        OfficeMenuItem("Delete", icon: Icons.delete_outline, color: Colors.red.shade700, onTap: _sheets.length > 1 ? () => _deleteSheet(i) : null),
      ];

  // ------------------------------------------------------------------
  // Clipboard (right-click menu; Ctrl+C / Ctrl+V on selected cells also work in the grid)
  // ------------------------------------------------------------------
  Future<void> _copyCell({bool cut = false}) async {
    await Clipboard.setData(ClipboardData(text: _sheet.at(_curRow, _curCol)));
    if (cut) _setRaw(_curRow, _curCol, '');
  }

  /// Pastes text; tab / new-line separated text (from Excel or Sheets) fills several cells.
  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text;
    if (t == null || t.isEmpty) return;
    final lines = t.replaceAll('\r\n', '\n').split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    if (lines.length == 1 && !lines.first.contains('\t')) {
      _setRaw(_curRow, _curCol, lines.first);
      return;
    }
    for (int i = 0; i < lines.length; i++) {
      final parts = lines[i].split('\t');
      for (int j = 0; j < parts.length; j++) {
        _sheet.ensure(_curRow + i + 1, _curCol + j + 1);
        _sheet.raw[_curRow + i][_curCol + j] = parts[j];
      }
    }
    _rebuildGrid();
    _markDirty();
  }

  void _insertNow(String v) => _setRaw(_curRow, _curCol, v);

  Future<void> _hyperlink() async {
    final cur = _sheet.at(_curRow, _curCol);
    if (cur.startsWith('http://') || cur.startsWith('https://')) {
      await launchUrl(Uri.parse(cur), mode: LaunchMode.externalApplication);
      return;
    }
    final url = await officeAsk(context, "Hyperlink for ${SheetEngine.colName(_curCol)}${_curRow + 1}", 'https://', ok: "Insert");
    if (url != null && url.isNotEmpty) _setRaw(_curRow, _curCol, url);
  }

  void _insertFunction(String fn, {String? template}) {
    String text;
    if (template != null && !template.contains('range')) {
      text = template;
    } else {
      final col = SheetEngine.colName(_curCol);
      final range = "${col}1:$col${(_curRow > 0 ? _curRow : 1)}";
      text = (template ?? "=$fn(range)").replaceFirst('range', range);
    }
    _fxC.text = text;
    _fxFocus.requestFocus();
    _fxC.selection = TextSelection.collapsed(offset: text.length);
  }

  void _showFunctions(String cat) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text("$cat functions", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15))),
          for (final f in _functions[cat] ?? const <(String, String, String)>[])
            ListTile(
              leading: Icon(Icons.functions_rounded, color: AppPalette.fg(_kGreen)),
              title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${f.$3} · ${f.$2}"),
              onTap: () {
                Navigator.pop(ctx);
                _insertFunction(f.$1, template: f.$2);
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _rightClick(Offset pos) {
    final cell = "${SheetEngine.colName(_curCol)}${_curRow + 1}";
    final v = _sheet.at(_curRow, _curCol);
    return showOfficeMenu(context, pos, [
      OfficeMenuItem("Cut  ($cell)", icon: Icons.content_cut, shortcut: "Ctrl+X", onTap: () => _copyCell(cut: true)),
      OfficeMenuItem("Copy", icon: Icons.content_copy, shortcut: "Ctrl+C", onTap: () => _copyCell()),
      OfficeMenuItem("Paste", icon: Icons.content_paste, shortcut: "Ctrl+V", color: Colors.orange.shade800, onTap: _paste),
      const OfficeMenuItem.divider(),
      OfficeMenuItem("Insert row above", icon: Icons.vertical_align_top_rounded, onTap: () => _insertRow(below: false)),
      OfficeMenuItem("Insert row below", icon: Icons.vertical_align_bottom_rounded, onTap: () => _insertRow(below: true)),
      OfficeMenuItem("Insert column left", icon: Icons.west_rounded, onTap: () => _insertCol(right: false)),
      OfficeMenuItem("Insert column right", icon: Icons.east_rounded, onTap: () => _insertCol(right: true)),
      OfficeMenuItem("Delete row", icon: Icons.playlist_remove_rounded, onTap: _deleteRow),
      OfficeMenuItem("Delete column", icon: Icons.backspace_outlined, onTap: _deleteCol),
      OfficeMenuItem("Clear contents", icon: Icons.layers_clear, shortcut: "Delete", onTap: () => _setRaw(_curRow, _curCol, '')),
      const OfficeMenuItem.divider(),
      OfficeMenuItem(_sm?.showColumnFilter == true ? "Hide filter" : "Filter", icon: Icons.filter_alt_outlined, shortcut: "Ctrl+Shift+L", onTap: _toggleFilter),
      OfficeMenuItem("Sort A → Z", icon: Icons.sort_by_alpha, onTap: () => _sort(ascending: true, hasHeader: true)),
      OfficeMenuItem("Sort Z → A", icon: Icons.sort, onTap: () => _sort(ascending: false, hasHeader: true)),
      OfficeMenuItem("Insert function…", icon: Icons.functions_rounded, onTap: () => _showFunctions('Math')),
      OfficeMenuItem(v.startsWith('http') ? "Open hyperlink" : "Hyperlink…", icon: Icons.link, shortcut: "Ctrl+K", onTap: _hyperlink),
    ]);
  }

  // ------------------------------------------------------------------
  // Import / export / print
  // ------------------------------------------------------------------
  static String _cellText(xl.Data? d) {
    final v = d?.value;
    if (v == null) return '';
    if (v is xl.FormulaCellValue) return '=${v.formula}';
    if (v is xl.IntCellValue) return v.value.toString();
    if (v is xl.DoubleCellValue) return SheetEngine.format(v.value);
    if (v is xl.BoolCellValue) return v.value ? 'TRUE' : 'FALSE';
    return v.toString();
  }

  Future<List<_Sheet>?> _pickImport() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv'], withData: true);
    final f = r?.files.firstOrNull;
    if (f == null || f.bytes == null) return null;
    try {
      if ((f.extension ?? '').toLowerCase() == 'csv') {
        final text = utf8.decode(f.bytes!, allowMalformed: true).replaceAll('\r\n', '\n');
        final rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(text);
        final raw = [for (final row in rows) [for (final v in row) v.toString()]];
        return [_Sheet.filled(f.name.replaceAll(RegExp(r'\.csv$', caseSensitive: false), ''), raw)];
      }
      final book = xl.Excel.decodeBytes(f.bytes!);
      final out = <_Sheet>[];
      for (final name in book.tables.keys) {
        final t = book.tables[name]!;
        out.add(_Sheet.filled(name, [
          for (final row in t.rows) [for (final d in row) _cellText(d)]
        ]));
      }
      return out.isEmpty ? null : out;
    } catch (e) {
      debugPrint("Import error: $e");
      _snack("That file couldn't be read. Use .xlsx or .csv.");
      return null;
    }
  }

  Future<void> _importAsNewBook() async {
    final sheets = await _pickImport();
    if (sheets == null) return;
    try {
      final id = await _newBook(sheets.first.name.isEmpty ? 'Imported spreadsheet' : sheets.first.name, sheets);
      await _openBook(id);
    } catch (e) {
      _snack("Couldn't import: ${e is PostgrestException ? e.message : e}");
    }
  }

  Future<void> _importIntoSheet() async {
    final sheets = await _pickImport();
    if (sheets == null) return;
    if (!mounted) return;
    if (!await officeConfirm(context, "Replace \"${_sheet.name}\"?", "The current cells of this sheet are replaced with the file's first sheet.", ok: "Replace")) return;
    _sheet.raw = sheets.first.raw;
    _rebuildGrid();
    _markDirty();
  }

  String get _fileBase => (_titleC.text.trim().isEmpty ? 'spreadsheet' : _titleC.text.trim()).replaceAll(RegExp(r'[^A-Za-z0-9가-힣 _-]'), '');

  Future<void> _exportXlsx() async {
    try {
      final book = xl.Excel.createExcel();
      final def = book.getDefaultSheet() ?? 'Sheet1';
      for (int i = 0; i < _sheets.length; i++) {
        final s = _sheets[i];
        final name = s.name.length > 31 ? s.name.substring(0, 31) : s.name;
        if (i == 0) book.rename(def, name);
        final sheet = book[name];
        final eng = SheetEngine((r, c) => s.at(r, c), maxRows: s.rows, maxCols: s.cols);
        for (int r = 0; r < s.rows; r++) {
          for (int c = 0; c < s.cols; c++) {
            final rawV = s.raw[r][c];
            if (rawV.isEmpty) continue;
            final shown = rawV.startsWith('=') ? eng.display(r, c) : rawV;
            final n = num.tryParse(shown.replaceAll(',', ''));
            final xl.CellValue value = n == null ? xl.TextCellValue(shown) : (n is int ? xl.IntCellValue(n) : xl.DoubleCellValue(n.toDouble()));
            sheet.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r), value);
          }
        }
      }
      final file = "$_fileBase.xlsx";
      final bytes = book.save(fileName: file); // on the web this downloads the file
      if (!kIsWeb && bytes != null) {
        await FilePicker.platform.saveFile(dialogTitle: "Save spreadsheet", fileName: file, bytes: Uint8List.fromList(bytes));
      }
      _snack("Excel file downloaded: $file");
    } catch (e) {
      debugPrint("Export error: $e");
      _snack("Couldn't export the spreadsheet.");
    }
  }

  /// The used part of the current sheet, as shown (formulas calculated).
  ExportTable _printTable() {
    final s = _sheet;
    final (lastR, lastC) = s.usedRange;
    final cols = lastC < 0 ? 1 : lastC + 1;
    final eng = SheetEngine((r, c) => s.at(r, c), maxRows: s.rows, maxCols: s.cols);
    return ExportTable(
      title: "${_titleC.text.trim().isEmpty ? 'Spreadsheet' : _titleC.text.trim()} – ${s.name}",
      headers: ['#', for (int c = 0; c < cols; c++) SheetEngine.colName(c)],
      rows: [
        for (int r = 0; r <= lastR; r++) ['${r + 1}', for (int c = 0; c < cols; c++) s.at(r, c).startsWith('=') ? eng.display(r, c) : s.at(r, c)],
      ],
    );
  }

  Future<void> _print() async {
    final t = _printTable();
    if (t.isEmpty) {
      _snack("This sheet is empty.");
      return;
    }
    await TableExport.preview(context, t);
  }

  Future<void> _pdf() async {
    final t = _printTable();
    if (t.isEmpty) {
      _snack("This sheet is empty.");
      return;
    }
    await TableExport.pdf(context, t);
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _open ? _editor() : _hub());

  String _when(dynamic v) {
    final t = DateTime.tryParse((v ?? '').toString())?.toLocal();
    return t == null ? '—' : DateFormat('d MMM yyyy, HH:mm').format(t);
  }

  Widget _hub() {
    final q = _search.trim().toLowerCase();
    final books = q.isEmpty ? _books : _books.where((b) => (b['title'] ?? '').toString().toLowerCase().contains(q)).toList();
    return CallbackShortcuts(
      key: const ValueKey('hub'),
      bindings: officeKeys({LogicalKeyboardKey.keyN: () => _create(_templates.first), LogicalKeyboardKey.keyO: _importAsNewBook}),
      child: Focus(
        autofocus: true,
        child: OfficeHub(
          title: "Cloud Sheets Hub",
          accent: _kPurple,
          accent2: Colors.indigo,
          actions: [
            OfficeHubAction("New Sheet", Icons.add_box, Colors.green, () => _create(_templates.first)),
            OfficeHubAction("Open Existing", Icons.folder, Colors.blue, () => _snack("Pick a spreadsheet from the list, or search for it.")),
            OfficeHubAction("Templates", Icons.dashboard_customize, Colors.orange, _pickTemplate),
            OfficeHubAction("Import Excel / CSV", Icons.upload_file_rounded, Colors.teal, _importAsNewBook),
          ],
          templates: _templates,
          onTemplate: _create,
          onAllTemplates: _pickTemplate,
          files: books,
          loading: _loadingBooks,
          searchHint: "Search files…",
          emptyText: _books.isEmpty ? "No spreadsheets yet. Start one from a template." : "No spreadsheets match.",
          onSearch: (v) => setState(() => _search = v),
          fileIcon: Icons.table_chart,
          fileIconColor: Colors.green,
          fileSubtitle: (b) => "Sync date: ${_when(b['last_modified'] ?? b['created_at'])}",
          onOpen: (b) => _openBook(b['id'].toString()),
          fileMenu: (b) => [
            OfficeMenuItem("Open", icon: Icons.open_in_new, onTap: () => _openBook(b['id'].toString())),
            OfficeMenuItem("Rename", icon: Icons.drive_file_rename_outline, onTap: () => _renameBook(b)),
            OfficeMenuItem("Make a copy", icon: Icons.copy_rounded, onTap: () => _duplicateBook(b)),
            const OfficeMenuItem.divider(),
            OfficeMenuItem("Delete", icon: Icons.delete_outline, color: Colors.red.shade700, onTap: () => _deleteBook(b)),
          ],
          onRefresh: _loadBooks,
          guideIcon: Icons.help_center_outlined,
          guideLines: const [
            "Full Excel-style right-click menu on the grid and on sheet tabs.",
            "Formulas: =SUM(A1:A10), =AVERAGE(B2:B9), =IF(C2>50,\"Pass\",\"Fail\"), =COUNTIF(D2:D40,\"P\") — see the Functions tab.",
            "Scroll arrows for fine control; zoom slider beside the sheet tabs.",
            "Paste straight from Excel or Google Sheets. Import / download .xlsx; print with preview (Ctrl+P).",
            "Saves automatically (Ctrl+S saves now). Your spreadsheets are private to your account.",
          ],
        ),
      ),
    );
  }

  List<OfficeRibbonTab> _ribbonTabs() {
    OfficeAction a(IconData i, String l, VoidCallback? f, {String? tip, bool sel = false}) => OfficeAction(i, l, f, tooltip: tip, accent: _kPurple, selected: sel);
    final filterOn = _sm?.showColumnFilter == true;
    return [
      OfficeRibbonTab("File", () => [
            a(Icons.note_add_outlined, "New", _pickTemplate, tip: "New from a template"),
            a(Icons.folder_open, "Open", _close, tip: "Back to my spreadsheets"),
            a(Icons.cloud_upload_outlined, "Save", _save, tip: "Ctrl+S"),
            a(Icons.drive_file_rename_outline, "Rename", () async {
              final n = await officeAsk(context, "Rename spreadsheet", _titleC.text, ok: "Rename");
              if (n != null && n.isNotEmpty) {
                _titleC.text = n;
                _markDirty();
              }
            }),
            const OfficeRibbonGap(),
            a(Icons.upload_file_rounded, "Import into sheet", _importIntoSheet),
            a(Icons.grid_on_rounded, "Download Excel", _exportXlsx),
            a(Icons.picture_as_pdf_outlined, "Download PDF", _pdf),
            a(Icons.print_outlined, "Print", _print, tip: "Ctrl+P"),
            const OfficeRibbonGap(),
            a(Icons.close, "Close", _close),
          ]),
      OfficeRibbonTab("Home", () => [
            a(Icons.content_cut, "Cut", () => _copyCell(cut: true)),
            a(Icons.content_copy, "Copy", () => _copyCell()),
            a(Icons.content_paste, "Paste", _paste),
            a(Icons.layers_clear, "Clear", () => _setRaw(_curRow, _curCol, '')),
            const OfficeRibbonGap(),
            a(Icons.sort_by_alpha, "Sort A→Z", () => _sort(ascending: true, hasHeader: true)),
            a(Icons.sort, "Sort Z→A", () => _sort(ascending: false, hasHeader: true)),
            a(Icons.filter_alt_outlined, filterOn ? "Hide filter" : "Filter", _toggleFilter, tip: "Ctrl+Shift+L", sel: filterOn),
            const OfficeRibbonGap(),
            a(Icons.functions_rounded, "AutoSum", () => _insertFunction('SUM'), tip: "Alt+="),
          ]),
      OfficeRibbonTab("Insert", () => [
            a(Icons.vertical_align_top_rounded, "Row above", () => _insertRow(below: false)),
            a(Icons.vertical_align_bottom_rounded, "Row below", () => _insertRow(below: true)),
            a(Icons.west_rounded, "Column left", () => _insertCol(right: false)),
            a(Icons.east_rounded, "Column right", () => _insertCol(right: true)),
            a(Icons.add_rounded, "+10 rows", () => _addRows(10)),
            a(Icons.view_column_outlined, "+5 columns", () => _addCols(5)),
            const OfficeRibbonGap(),
            a(Icons.post_add_rounded, "Sheet", _addSheet),
            a(Icons.today_outlined, "Today's date", () => _insertNow(DateFormat('yyyy-MM-dd').format(DateTime.now())), tip: "Ctrl+;"),
            a(Icons.schedule, "Time", () => _insertNow(DateFormat('HH:mm').format(DateTime.now()))),
            a(Icons.link, "Hyperlink", _hyperlink, tip: "Ctrl+K"),
          ]),
      OfficeRibbonTab("Data", () => [
            a(Icons.sort_by_alpha, "Sort A→Z (keep header)", () => _sort(ascending: true, hasHeader: true)),
            a(Icons.sort, "Sort Z→A (keep header)", () => _sort(ascending: false, hasHeader: true)),
            a(Icons.swap_vert, "Sort all rows", () => _sort(ascending: true, hasHeader: false)),
            a(Icons.filter_alt_outlined, filterOn ? "Hide filter" : "Filter", _toggleFilter, sel: filterOn),
            a(Icons.cleaning_services_outlined, "Remove duplicates", _removeDuplicates),
            const OfficeRibbonGap(),
            a(Icons.playlist_remove_rounded, "Delete row", _deleteRow),
            a(Icons.backspace_outlined, "Delete column", _deleteCol),
          ]),
      OfficeRibbonTab(
          "Functions",
          () => [
                for (final cat in _functions.keys) a(Icons.functions_rounded, cat, () => _showFunctions(cat)),
                const OfficeRibbonGap(),
                for (final fn in const ['SUM', 'AVERAGE', 'MIN', 'MAX', 'COUNT']) a(Icons.calculate_outlined, fn, () => _insertFunction(fn)),
              ],
          color: Colors.green.shade800),
      OfficeRibbonTab("View", () => [
            a(Icons.zoom_in, "Zoom in", () => _setZoom(_zoom + 0.1), tip: "Ctrl+="),
            a(Icons.zoom_out, "Zoom out", () => _setZoom(_zoom - 0.1), tip: "Ctrl+-"),
            a(Icons.fit_screen_outlined, "100%", () => _setZoom(1.0), tip: "Ctrl+0"),
            const OfficeRibbonGap(),
            a(Icons.code, _showFormulas ? "Show values" : "Show formulas", () {
              setState(() => _showFormulas = !_showFormulas);
              _rebuildGrid();
            }, tip: "Ctrl+`", sel: _showFormulas),
            a(Icons.view_sidebar_outlined, _freezeFirst ? "Unfreeze column A" : "Freeze column A", () {
              setState(() => _freezeFirst = !_freezeFirst);
              _rebuildGrid();
            }, sel: _freezeFirst),
          ]),
    ];
  }

  void _setZoom(double z) {
    final v = (z.clamp(0.5, 2.0) * 10).round() / 10;
    if (v == _zoom) return;
    setState(() => _zoom = v);
    _rebuildGrid();
  }

  void _scrollGrid({double dy = 0, double dx = 0}) {
    final sc = _sm?.scroll;
    if (sc == null) return;
    if (dy != 0) {
      final v = sc.vertical;
      if (v != null) v.animateTo((v.offset + dy).clamp(0, double.infinity).toDouble(), duration: const Duration(milliseconds: 80), curve: Curves.linear);
    }
    if (dx != 0) {
      final h = sc.horizontal;
      if (h != null) h.animateTo((h.offset + dx).clamp(0, double.infinity).toDouble(), duration: const Duration(milliseconds: 80), curve: Curves.linear);
    }
  }

  Widget _editor() {
    final status = officeSaveStatus(_saveState);
    return PopScope(
      key: const ValueKey('editor'),
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: CallbackShortcuts(
        bindings: {
          ...officeKeys({
            LogicalKeyboardKey.keyS: _save,
            LogicalKeyboardKey.keyP: _print,
            LogicalKeyboardKey.keyK: _hyperlink,
            LogicalKeyboardKey.semicolon: () => _insertNow(DateFormat('yyyy-MM-dd').format(DateTime.now())),
            LogicalKeyboardKey.equal: () => _setZoom(_zoom + 0.1),
            LogicalKeyboardKey.minus: () => _setZoom(_zoom - 0.1),
            LogicalKeyboardKey.digit0: () => _setZoom(1.0),
            LogicalKeyboardKey.backquote: () {
              setState(() => _showFormulas = !_showFormulas);
              _rebuildGrid();
            },
            LogicalKeyboardKey.pageDown: () => _switchSheet(_active + 1),
            LogicalKeyboardKey.pageUp: () => _switchSheet(_active - 1),
          }, ctrlShift: {
            LogicalKeyboardKey.keyL: _toggleFilter,
          }),
          const SingleActivator(LogicalKeyboardKey.equal, alt: true): () => _insertFunction('SUM'),
        },
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final touch = box.maxWidth < 700;
          final s = _sheet;
          final rowH = (touch ? 28.0 : 16.5) * _zoom;
          final fs = (touch ? 12.0 : 10.5) * _zoom;
          final colW = 100.0 * _zoom;
          return Scaffold(
            backgroundColor: AppPalette.bg(Colors.white),
            body: SafeArea(
              child: Column(children: [
                OfficeHeaderCard(
                  accent: _kPurple,
                  titleController: _titleC,
                  onTitleChanged: (_) => _markDirty(),
                  subtitle: "${widget.userEmail} · ${status.$1}",
                  subtitleColor: status.$3,
                  onClose: _close,
                  actions: [
                    if (wide)
                      TextButton.icon(onPressed: _save, icon: Icon(status.$2, size: 16, color: AppPalette.fg(status.$3)), label: const Text("SAVE", style: TextStyle(fontSize: 10)))
                    else
                      IconButton(tooltip: "Save now (Ctrl+S)", onPressed: _save, icon: Icon(status.$2, color: AppPalette.fg(status.$3))),
                    IconButton(tooltip: "Download Excel (.xlsx)", icon: Icon(Icons.download_rounded, color: AppPalette.fg(_kGreen)), onPressed: _exportXlsx),
                  ],
                ),
                OfficeRibbon(tabs: _ribbonTabs(), active: _tab, onTab: (i) => setState(() => _tab = i), accent: _kPurple),
                // fx bar (rounded, as before) with the cell name
                Container(
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppPalette.bg(const Color(0xFFFBFBFE)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.25))),
                  ),
                  child: Row(children: [
                    Container(
                      width: 58,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppPalette.line(Colors.black12))),
                      child: Text("${SheetEngine.colName(_curCol)}${_curRow + 1}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const VerticalDivider(indent: 6, endIndent: 6),
                    Text("fx", style: TextStyle(fontStyle: FontStyle.italic, color: AppPalette.fg(Colors.grey), fontWeight: FontWeight.bold, fontSize: 16)),
                    const VerticalDivider(indent: 6, endIndent: 6),
                    Expanded(
                      child: TextField(
                        controller: _fxC,
                        focusNode: _fxFocus,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero, hintText: "Type a value or =formula, then press Enter"),
                        onSubmitted: (v) {
                          _setRaw(_curRow, _curCol, v);
                          _sm?.setKeepFocus(true);
                        },
                      ),
                    ),
                    InkWell(onTap: () => _setRaw(_curRow, _curCol, _fxC.text), child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.check_rounded, size: 18, color: AppPalette.fg(_kGreen)))),
                    InkWell(onTap: () => _fxC.text = _sheet.at(_curRow, _curCol), child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 18, color: AppPalette.fg(Colors.red.shade400)))),
                  ]),
                ),
                // Grid
                Expanded(
                  child: Row(children: [
                    Expanded(
                      child: OfficeRightClick(
                        onMenu: _rightClick,
                        child: PlutoGrid(
                          key: ValueKey('grid-$_active-$_gridVersion'),
                          columns: [
                            PlutoColumn(
                              title: '#',
                              field: 'r',
                              type: PlutoColumnType.number(),
                              width: 42 * _zoom.clamp(0.8, 2.0).toDouble(),
                              minWidth: 34,
                              readOnly: true,
                              enableSorting: false,
                              enableContextMenu: false,
                              enableColumnDrag: false,
                              enableEditingMode: false,
                              enableFilterMenuItem: false,
                              frozen: PlutoColumnFrozen.start,
                              textAlign: PlutoColumnTextAlign.center,
                              titleTextAlign: PlutoColumnTextAlign.center,
                            ),
                            for (int c = 0; c < s.cols; c++)
                              PlutoColumn(
                                title: SheetEngine.colName(c),
                                field: 'c$c',
                                type: PlutoColumnType.text(),
                                width: colW,
                                minWidth: 30,
                                enableSorting: false,
                                enableContextMenu: false,
                                enableColumnDrag: false,
                                enableDropToResize: true,
                                frozen: _freezeFirst && c == 0 ? PlutoColumnFrozen.start : PlutoColumnFrozen.none,
                                textAlign: PlutoColumnTextAlign.center,
                                titleTextAlign: PlutoColumnTextAlign.center,
                              ),
                          ],
                          rows: [
                            for (int r = 0; r < s.rows; r++)
                              PlutoRow(cells: {
                                'r': PlutoCell(value: r + 1),
                                for (int c = 0; c < s.cols; c++) 'c$c': PlutoCell(value: _shown(r, c)),
                              }),
                          ],
                          onLoaded: (e) {
                            _sm = e.stateManager;
                            e.stateManager.addListener(_onGridState);
                          },
                          onChanged: _onGridChanged,
                          configuration: PlutoGridConfiguration(
                            enableMoveDownAfterSelecting: true,
                            scrollbar: const PlutoGridScrollbarConfig(isAlwaysShown: true, scrollbarThickness: 10),
                            style: AppPalette.isDark
                                ? PlutoGridStyleConfig.dark(
                                    rowHeight: rowH,
                                    columnHeight: 22 * _zoom.clamp(0.9, 2.0).toDouble(),
                                    cellTextStyle: TextStyle(fontSize: fs, color: AppPalette.fg(Colors.white)),
                                    columnTextStyle: GoogleFonts.merriweather(fontSize: 10 * _zoom.clamp(0.9, 2.0).toDouble(), fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.white)),
                                  )
                                : PlutoGridStyleConfig(
                                    rowHeight: rowH,
                                    columnHeight: 22 * _zoom.clamp(0.9, 2.0).toDouble(),
                                    activatedBorderColor: _kGreen,
                                    activatedColor: const Color(0xFFE8F5E9),
                                    cellTextStyle: TextStyle(fontSize: fs, color: AppPalette.fg(Colors.black87)),
                                    columnTextStyle: GoogleFonts.merriweather(fontSize: 10 * _zoom.clamp(0.9, 2.0).toDouble(), fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87)),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    if (wide) OfficeScrollArrows(axis: Axis.vertical, onBack: () => _scrollGrid(dy: -60), onForward: () => _scrollGrid(dy: 60)),
                  ]),
                ),
                if (wide) OfficeScrollArrows(axis: Axis.horizontal, leadingGap: 35, onBack: () => _scrollGrid(dx: -120), onForward: () => _scrollGrid(dx: 120)),
                // Sheet tabs + zoom
                Container(
                  height: 36,
                  decoration: BoxDecoration(color: AppPalette.bg(Colors.grey[100]), border: Border(top: BorderSide(color: AppPalette.line(Colors.black12)))),
                  child: Row(children: [
                    IconButton(tooltip: "Previous sheet (Ctrl+PgUp)", visualDensity: VisualDensity.compact, icon: const Icon(Icons.chevron_left, size: 20), onPressed: _active > 0 ? () => _switchSheet(_active - 1) : null),
                    IconButton(tooltip: "Next sheet (Ctrl+PgDn)", visualDensity: VisualDensity.compact, icon: const Icon(Icons.chevron_right, size: 20), onPressed: _active < _sheets.length - 1 ? () => _switchSheet(_active + 1) : null),
                    const VerticalDivider(width: 8),
                    Expanded(
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _sheets.length,
                        itemBuilder: (ctx, i) {
                          final sel = i == _active;
                          return OfficeRightClick(
                            longPress: true,
                            onMenu: (p) => showOfficeMenu(ctx, p, _sheetMenuItems(i)),
                            child: InkWell(
                              onTap: () => _switchSheet(i),
                              onDoubleTap: () => _renameSheet(i),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 15),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppPalette.bg(sel ? Colors.white : Colors.transparent),
                                  border: Border(top: BorderSide(color: AppPalette.line(sel ? _kPurple : Colors.transparent), width: 3)),
                                ),
                                child: Text(_sheets[i].name,
                                    style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.bold : FontWeight.normal, color: AppPalette.fg(sel ? _kPurple : Colors.black54))),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    IconButton(tooltip: "Add sheet", visualDensity: VisualDensity.compact, icon: Icon(Icons.add, size: 18, color: AppPalette.fg(Colors.green)), onPressed: _addSheet),
                    if (wide)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text("${s.rows} × ${s.cols}", style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.grey[600]))),
                      ),
                    Text("${(_zoom * 100).round()}%", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    SizedBox(
                      width: wide ? 110 : 80,
                      child: Slider(
                        value: _zoom,
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        activeColor: _kPurple,
                        onChanged: (v) => setState(() => _zoom = (v * 10).round() / 10),
                        onChangeEnd: (_) => _rebuildGrid(),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }
}
