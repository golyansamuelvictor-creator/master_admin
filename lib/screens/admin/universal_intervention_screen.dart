// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/absentee_logic.dart';
import '../../core/offering_categories.dart';
import '../../core/table_export.dart';
import 'package:master_admin/core/app_palette.dart';
import 'package:flutter/services.dart';
import '../../widgets/app_menus.dart';
import '../../widgets/h_scroll.dart';

/// Universal Intervention: the members who missed a duty in the period
/// (absentees), or, for Counseling and Visitations, "Those who need
/// Counseling and Visitations" gathered from the other duties.
///
/// Every table: Location, Sub-location, Department, Team, Cell group, Name.
///  * Service Attendance: Service style, Style count, Missed, Current status;
///    Pre-attendance / Real time and Wed / Sun toggles.
///  * Cell Service, Offering, Evangelism, Morning Light, ASE, Workers
///    Education, Workers Daily Participation: Missed and Current status, with
///    each duty's own day / week / kind toggles (all follow the period).
///  * Counseling and Visitations: Current status (why the member is listed),
///    Kind of visitation needed and why they weren't visited yet.
/// "Current status" is compiled by AI from the last 4 reasons given for
/// missing (absence-status-ai); until then the latest reason shows.
/// More than 1000 members are shown 1000 at a time.
class UniversalInterventionScreen extends StatefulWidget {
  final String duty;
  final String unitName;
  final String? buttonTitle;
  /// The leader's unit path ({location, sub_location, department, team,
  /// cell_group}, only the role's levels); {} = whole church.
  final Map<String, String>? scope;
  /// Church-wide group (장년회, 부녀회 ...) for group leaders.
  final String? group;

  /// Roles with two views (DualMode): the toggle's title and labels, and the
  /// own-department view (the wide view is [scope] / [group]).
  final String? dualTitle;
  final (String, String) dualLabels;
  final Map<String, String>? deptScope;

  const UniversalInterventionScreen({
    super.key,
    required this.duty,
    required this.unitName,
    this.buttonTitle,
    this.scope,
    this.group,
    this.dualTitle,
    this.dualLabels = const ("Church-wide", "Department only"),
    this.deptScope,
  });

  @override
  State<UniversalInterventionScreen> createState() => _UniversalInterventionScreenState();
}

class _UniversalInterventionScreenState extends State<UniversalInterventionScreen> {
  final Color headerDarkNavy = const Color(0xFF1E2D4A);
  final Color actionBtnBlue = const Color(0xFF2B4C7E);
  final Color gridLineColor = const Color(0xFFCBD5E1);
  final Color letterBg = const Color(0xFFF1F5F9);
  final Color cornerBg = const Color(0xFFE2E8F0);
  final Color rowEvenBg = Colors.white;
  final Color rowOddBg = const Color(0xFFF6F9FD);
  static const Color _selColor = Color(0xFF2B6CB0);

  final double letterRowHeight = 22.0;
  final double headerRowHeight = 32.0;
  final double dataRowHeight = 30.0;
  final double rowNumWidth = 48.0;
  static const int _pageSize = 1000;

  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScrollData = ScrollController();
  final ScrollController _verticalScrollRowNumbers = ScrollController();
  final FocusNode _gridFocus = FocusNode();

  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoading = true;
  String? _loadError;
  String _screenTitle = "";
  final Set<String> _hiddenColumns = {};
  bool _wide = true; // dual-mode roles: the wide view (true) or own department (false)
  bool get _dual => widget.dualTitle != null && widget.deptScope != null;

  // Period (default: the last 30 days); one day is allowed
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String _periodLabel = "Last 30 days";

  // Per-duty toggles, all applied inside the period
  bool _pre = false; // Service Attendance: pre-attendance (true) / real time (false)
  String? _day; // one day of the duty (null = every day)
  bool _avg = false; // Evangelism / Workers Daily Participation: weekly average
  String? _offCol; // Offering: one kind (null = any kind)
  int? _offWeek; // Offering: week 1–5 of the month (null = every week)

  // Selected Service Style per member { memberId: 'In-person' }
  final Map<String, String> _memberSelectedStyle = {};
  String _searchQuery = "";

  // "Current status" compiled by AI: member id → status
  final Map<String, String> _aiStatus = {};
  bool _aiBusy = false;
  String? _aiNote;
  int _loadSeq = 0;

  // 1000 rows per page
  int _page = 0;

  // Selection (Excel-like): rows are indices in the current page, columns
  // indices in the visible columns
  int? _r0, _c0, _r1, _c1;

  final Map<String, Set<String>> _activeFilters = {};

  bool get _isSA => widget.duty.startsWith('Service Attendance');
  bool get _isVisit => widget.duty.contains('Visitation');
  bool get _isOffering => widget.duty.contains('Offering');
  bool get _hasAverage => widget.duty.startsWith('Evangelism') || widget.duty == 'Workers Daily Participation';

  static const Map<String, double> _colWidths = {
    "Loc": 85,
    "Sub-Loc": 95,
    "Dept": 95,
    "Team": 80,
    "Cell Group": 105,
    "Name": 150,
    "Service Style": 135,
    "Style Count": 90,
    "Missed": 80,
    "Current Status": 230,
    "Kind of Visitation Needed": 190,
    "Reason Not Visited": 220,
  };

  List<String> get _allColumns => [
        "Loc",
        "Sub-Loc",
        "Dept",
        "Team",
        "Cell Group",
        "Name",
        if (_isSA) ...["Service Style", "Style Count"],
        if (!_isVisit) "Missed",
        "Current Status",
        if (_isVisit) ...["Kind of Visitation Needed", "Reason Not Visited"],
      ];

  List<String> get _visibleColumns => _allColumns.where((c) => !_hiddenColumns.contains(c)).toList();
  double get _baseTableWidth => _visibleColumns.fold(0.0, (acc, k) => acc + (_colWidths[k] ?? 100));

  int get _pageCount => math.max(1, (_filteredData.length / _pageSize).ceil());
  List<Map<String, dynamic>> get _pageRows {
    final from = _page * _pageSize;
    if (from >= _filteredData.length) return const [];
    return _filteredData.sublist(from, math.min(_filteredData.length, from + _pageSize));
  }

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
    if (_isVisit) _screenTitle = "Those Who Need Counseling and Visitations";
    // the app's own right-click menu only (the browser's showed on top of it)
    if (kIsWeb) BrowserContextMenu.disableContextMenu();

    _verticalScrollData.addListener(() {
      if (_verticalScrollRowNumbers.hasClients && _verticalScrollRowNumbers.offset != _verticalScrollData.offset) {
        _verticalScrollRowNumbers.jumpTo(_verticalScrollData.offset);
      }
    });
    _verticalScrollRowNumbers.addListener(() {
      if (_verticalScrollData.hasClients && _verticalScrollData.offset != _verticalScrollRowNumbers.offset) {
        _verticalScrollData.jumpTo(_verticalScrollRowNumbers.offset);
      }
    });

    if (_isOffering) {
      OfferingCategories.load().then((_) {
        if (mounted) setState(() {});
      });
    }
    _load();
  }

  @override
  void dispose() {
    if (kIsWeb) BrowserContextMenu.enableContextMenu();
    _horizontalScroll.dispose();
    _verticalScrollData.dispose();
    _verticalScrollRowNumbers.dispose();
    _gridFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Loading

  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final res = _isVisit ? await _loadVisitNeeds() : await _loadAbsentees();
      if (!mounted || seq != _loadSeq) return;
      for (final it in res) {
        it['_m'] = _extractMember(it);
      }
      setState(() {
        _data = res;
        _isLoading = false;
        _page = 0;
        _clearSel();
      });
      _applyFilters();
      if (!_isVisit) _compileStatuses(seq);
    } catch (e) {
      debugPrint("Error loading intervention list: $e");
      if (mounted && seq == _loadSeq) {
        setState(() {
          _isLoading = false;
          _loadError = e is PostgrestException ? e.message : e.toString();
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadAbsentees() async {
    final res = await AbsenteeLogic.getDetailedInterventionList(
      duty: widget.duty,
      unitName: widget.unitName,
      scope: _dual && !_wide ? widget.deptScope : widget.scope,
      group: _dual && !_wide ? null : widget.group,
      startDate: _startDate,
      endDate: _endDate,
      pre: _pre,
      day: _day,
      offeringColumn: _offCol,
      offeringWeek: _offWeek,
    );
    for (var item in res) {
      final m = _extractMember(item);
      final mid = m['id']?.toString() ?? "";
      final List<dynamic> styles = item['service_styles'] ?? [];
      if (!_memberSelectedStyle.containsKey(mid) && styles.isNotEmpty) {
        _memberSelectedStyle[mid] = styles.first.toString();
      }
    }
    return res;
  }

  /// Counseling and Visitations: the members found among the other duties
  /// (visitation_needs, 20_round19.sql), inside the leader's own units.
  Future<List<Map<String, dynamic>>> _loadVisitNeeds() async {
    final scope = _dual && !_wide ? widget.deptScope : widget.scope;
    final group = _dual && !_wide ? null : widget.group;
    String? s(String k) {
      final v = (scope?[k] ?? '').trim();
      return v.isEmpty || v.toUpperCase() == 'N/A' ? null : v;
    }
    final f = DateFormat('yyyy-MM-dd');
    final results = await Future.wait<dynamic>([
      Supabase.instance.client.rpc('visitation_needs', params: {
        'p_from': f.format(_startDate),
        'p_to': f.format(_endDate),
        'p_location': s('location'),
        'p_sub': s('sub_location'),
        'p_dept': s('department'),
        'p_team': s('team'),
        'p_cell': s('cell_group'),
      }),
      AbsenteeLogic.scopedMembers(unitName: widget.unitName, scope: scope, group: group),
    ]);
    final ids = {for (final m in (results[1] as List)) m['id']?.toString()};
    final rows = <Map<String, dynamic>>[];
    for (final raw in (results[0] as List)) {
      final r = Map<String, dynamic>.from(raw as Map);
      if (ids.isNotEmpty && !ids.contains(r['member_id']?.toString())) continue;
      rows.add({
        'member': {
          'id': r['member_id'],
          'english_name': r['english_name'],
          'location': r['location'],
          'sub_location': r['sub_location'],
          'department': r['department'],
          'team': r['team'],
          'cell_group': r['cell_group'],
        },
        'current_status': r['current_status'] ?? '',
        'kinds': List<String>.from((r['kinds'] as List? ?? const []).map((e) => e.toString())),
        'visit_status': r['visit_status'],
        'not_visited_reason': r['not_visited_reason'],
        'missed_count': (r['reasons'] as List? ?? const []).length,
      });
    }
    return rows;
  }

  /// Current status by AI for the members with reasons, kept in
  /// member_current_status so each is compiled once per new reason.
  Future<void> _compileStatuses(int seq) async {
    final db = Supabase.instance.client;
    final items = <String, List<String>>{};
    for (final it in _data) {
      final reasons = List<String>.from((it['reasons'] as List? ?? const []).map((e) => e.toString()));
      final id = _extractMember(it)['id']?.toString() ?? '';
      if (reasons.isNotEmpty && id.isNotEmpty) items[id] = reasons;
    }
    if (items.isEmpty) return;
    String key(List<String> r) {
      final k = r.join(' | ');
      return k.length > 900 ? k.substring(0, 900) : k;
    }
    setState(() {
      _aiBusy = true;
      _aiNote = null;
    });
    try {
      // 1. what was compiled before (same reasons → same status)
      final ids = items.keys.toList();
      for (int i = 0; i < ids.length; i += 150) {
        final chunk = ids.sublist(i, math.min(ids.length, i + 150));
        final rows = await db.from('member_current_status').select('member_id, status, reasons_key').eq('duty_name', widget.duty).inFilter('member_id', chunk);
        for (final r in rows) {
          final id = r['member_id'].toString();
          if (items[id] != null && r['reasons_key'] == key(items[id]!)) _aiStatus[id] = r['status'].toString();
        }
      }
      if (!mounted || seq != _loadSeq) return;
      setState(() {});
      // 2. the rest, by AI, 60 at a time (the page in view first)
      // the AI compiles the page in view (another page: when it is opened)
      final shownIds = {for (final it in _pageRows) _extractMember(it)['id']?.toString()};
      final todo = items.keys.where((id) => !_aiStatus.containsKey(id) && shownIds.contains(id)).toList();
      for (int i = 0; i < todo.length; i += 60) {
        final chunk = todo.sublist(i, math.min(todo.length, i + 60));
        final r = await db.functions.invoke('absence-status-ai', body: {
          'duty': widget.duty,
          'items': [for (final id in chunk) {'id': id, 'reasons': items[id]}],
        });
        if (!mounted || seq != _loadSeq) return;
        final st = Map<String, dynamic>.from(((r.data as Map?)?['statuses'] as Map?) ?? const {});
        if (st.isEmpty) continue;
        final up = <Map<String, dynamic>>[];
        st.forEach((id, s) {
          _aiStatus[id] = s.toString();
          up.add({'member_id': id, 'duty_name': widget.duty, 'status': s.toString(), 'reasons_key': key(items[id]!), 'updated_at': DateTime.now().toUtc().toIso8601String()});
        });
        setState(() {});
        try {
          await db.from('member_current_status').upsert(up, onConflict: 'member_id,duty_name');
        } catch (_) {}
      }
    } catch (e) {
      // without the function / table the latest reason stays as the status
      final why = e is FunctionException
          ? "AI function: ${e.status} ${e.details is Map ? ((e.details as Map)['error'] ?? '') : (e.details ?? '')}".trim()
          : e is PostgrestException
              ? e.message
              : e.toString();
      _aiNote = "AI status unavailable ($why). Showing the latest reason instead.";
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _aiBusy = false);
    }
  }

  Map<String, dynamic> _extractMember(dynamic item) {
    if (item == null || item is! Map) return {};
    // worked out once per row (it was rebuilt for every cell and filter)
    final cached = item['_m'];
    if (cached is Map<String, dynamic>) return cached;
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

  String _missedText(Map<String, dynamic> item) {
    final missed = _getMissedCount(item);
    if (_avg && _hasAverage) {
      final weeks = math.max(1, (item['weeks'] as num?)?.toInt() ?? 1);
      final a = missed / weeks;
      return "${a.toStringAsFixed(a == a.roundToDouble() ? 0 : 1)}/wk";
    }
    return "${missed}x";
  }

  /// Current status: the AI's compiled status, or the latest reason given
  String _statusText(Map<String, dynamic> item) {
    if (_isVisit) return (item['current_status'] ?? '').toString();
    final id = _extractMember(item)['id']?.toString() ?? '';
    final ai = _aiStatus[id];
    if (ai != null && ai.isNotEmpty) return ai;
    final reasons = List<String>.from((item['reasons'] as List? ?? const []).map((e) => e.toString()));
    if (reasons.isNotEmpty) return reasons.length == 1 ? reasons.first : "${reasons.first} (+${reasons.length - 1} earlier)";
    final care = (item['last_recovery_outcome'] ?? '').toString();
    if (care.isNotEmpty && care != 'No Care Logged') return "Care: $care";
    return "No reason given";
  }

  String _kindsText(Map<String, dynamic> item) => List<String>.from(item['kinds'] ?? const []).join(', ');

  String _notVisitedText(Map<String, dynamic> item) {
    final st = (item['visit_status'] ?? '').toString();
    final why = (item['not_visited_reason'] ?? '').toString();
    if (st.isEmpty) return "Not visited yet";
    if (st.startsWith('Visited')) return why.isEmpty ? st : "$st · $why";
    return why.isEmpty ? "Not visited · no reason given" : "Not visited · $why";
  }

  /// The text of one cell (table, filters, copy and export use the same).
  String _cellValue(Map<String, dynamic> item, String col) {
    final m = _extractMember(item);
    final mid = m['id']?.toString() ?? "";
    switch (col) {
      case "Loc":
        return _getLocation(m);
      case "Sub-Loc":
        return _getSubLocation(m);
      case "Dept":
        return _getDepartment(m);
      case "Team":
        return _getTeam(m);
      case "Cell Group":
        return _getCellGroup(m);
      case "Name":
        return _getName(m);
      case "Service Style":
        return _memberSelectedStyle[mid] ?? "None";
      case "Style Count":
        final style = _memberSelectedStyle[mid] ?? "None";
        return "${(item['style_counts']?[style] ?? 0)}";
      case "Missed":
        return _missedText(item);
      case "Current Status":
        return _statusText(item);
      case "Kind of Visitation Needed":
        return _kindsText(item);
      case "Reason Not Visited":
        return _notVisitedText(item);
    }
    return "";
  }

  // ---------------------------------------------------------------------------
  // Period: one day or a range

  String _fmtDay(DateTime d) => DateFormat('EEE d MMM yyyy').format(d);

  void _setPeriod(DateTime a, DateTime b, String label) {
    setState(() {
      _startDate = DateTime(a.year, a.month, a.day);
      _endDate = DateTime(b.year, b.month, b.day);
      _periodLabel = label;
    });
    _load();
  }

  Offset? _menuPos;

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final box = context.findRenderObject() as RenderBox?;
    final pos = _menuPos ?? (box == null ? const Offset(40, 120) : box.localToGlobal(const Offset(40, 110)));
    _menuPos = null;
    showOfficeMenu(context, pos, [
      OfficeMenuItem("Today", icon: Icons.today_rounded, onTap: () => _setPeriod(today, today, _fmtDay(today))),
      OfficeMenuItem("Yesterday", icon: Icons.history_rounded, onTap: () {
        final y = today.subtract(const Duration(days: 1));
        _setPeriod(y, y, _fmtDay(y));
      }),
      OfficeMenuItem("One day…", icon: Icons.event_rounded, onTap: _pickOneDay),
      const OfficeMenuItem.divider(),
      OfficeMenuItem("This week", icon: Icons.view_week_rounded, onTap: () => _setPeriod(today.subtract(Duration(days: today.weekday - 1)), today, "This week")),
      OfficeMenuItem("Last 7 days", icon: Icons.date_range_rounded, onTap: () => _setPeriod(today.subtract(const Duration(days: 6)), today, "Last 7 days")),
      OfficeMenuItem("This month", icon: Icons.calendar_view_month_rounded, onTap: () => _setPeriod(DateTime(today.year, today.month, 1), today, "This month")),
      OfficeMenuItem("Last month", icon: Icons.calendar_month_outlined, onTap: () => _setPeriod(DateTime(today.year, today.month - 1, 1), DateTime(today.year, today.month, 0), "Last month")),
      OfficeMenuItem("Last 30 days", icon: Icons.calendar_month_rounded, onTap: () => _setPeriod(today.subtract(const Duration(days: 30)), today, "Last 30 days")),
      const OfficeMenuItem.divider(),
      OfficeMenuItem("Custom range…", icon: Icons.edit_calendar_rounded, onTap: _pickCustomRange),
    ]);
  }

  Widget _pickerTheme(BuildContext c, Widget? child) => Theme(
        data: Theme.of(c).copyWith(
          colorScheme: AppPalette.isDark
              ? const ColorScheme.dark(primary: Color(0xFF9DB7E0), surface: Color(0xFF1F2430))
              : ColorScheme.light(primary: headerDarkNavy),
        ),
        child: child!,
      );

  Future<void> _pickOneDay() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDate: _endDate.isAfter(DateTime.now()) ? DateTime.now() : _endDate,
      helpText: 'Select one day',
      builder: _pickerTheme,
    );
    if (d != null) _setPeriod(d, d, _fmtDay(d));
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: _pickerTheme,
    );
    if (picked != null) {
      _setPeriod(picked.start, picked.end,
          picked.start == picked.end ? _fmtDay(picked.start) : "${DateFormat('MMM d').format(picked.start)} - ${DateFormat('MMM d').format(picked.end)}");
    }
  }

  // ---------------------------------------------------------------------------
  // Filters, paging, selection

  void _applyFilters() {
    setState(() {
      _filteredData = _data.where((item) {
        final m = _extractMember(item);
        final name = _getName(m).toLowerCase();
        if (_searchQuery.isNotEmpty && !name.contains(_searchQuery.toLowerCase())) return false;
        for (final e in _activeFilters.entries) {
          if (e.value.isEmpty) continue;
          final v = _cellValue(item, e.key);
          if (!e.value.contains(v.isEmpty ? "N/A" : v)) return false;
        }
        return true;
      }).toList();
      if (_page >= _pageCount) _page = _pageCount - 1;
      _clearSel();
    });
  }

  void _goPage(int p) {
    setState(() {
      _page = p.clamp(0, _pageCount - 1);
      _clearSel();
    });
    if (_verticalScrollData.hasClients) _verticalScrollData.jumpTo(0);
    if (!_isVisit && !_aiBusy) _compileStatuses(_loadSeq);
  }

  void _clearSel() {
    _r0 = _c0 = _r1 = _c1 = null;
  }

  bool get _shift => HardwareKeyboard.instance.isShiftPressed;

  void _selectCell(int r, int c) {
    _gridFocus.requestFocus();
    setState(() {
      if (_shift && _r0 != null) {
        _r1 = r;
        _c1 = c;
      } else {
        _r0 = _r1 = r;
        _c0 = _c1 = c;
      }
    });
  }

  void _selectRow(int r) {
    _gridFocus.requestFocus();
    final last = _visibleColumns.length - 1;
    setState(() {
      if (_shift && _r0 != null) {
        _r1 = r;
      } else {
        _r0 = _r1 = r;
      }
      _c0 = 0;
      _c1 = last;
    });
  }

  void _selectColumn(int c) {
    _gridFocus.requestFocus();
    final n = _pageRows.length;
    if (n == 0) return;
    setState(() {
      if (_shift && _c0 != null) {
        _c1 = c;
      } else {
        _c0 = _c1 = c;
      }
      _r0 = 0;
      _r1 = n - 1;
    });
  }

  void _selectAll() {
    final n = _pageRows.length;
    if (n == 0) return;
    setState(() {
      _r0 = 0;
      _r1 = n - 1;
      _c0 = 0;
      _c1 = _visibleColumns.length - 1;
    });
  }

  bool _inSel(int r, int c) {
    if (_r0 == null || _c0 == null) return false;
    return r >= math.min(_r0!, _r1!) && r <= math.max(_r0!, _r1!) && c >= math.min(_c0!, _c1!) && c <= math.max(_c0!, _c1!);
  }

  bool _rowSelected(int r) => _r0 != null && r >= math.min(_r0!, _r1!) && r <= math.max(_r0!, _r1!) && math.min(_c0!, _c1!) == 0 && math.max(_c0!, _c1!) == _visibleColumns.length - 1;
  bool _colSelected(int c) => _c0 != null && c >= math.min(_c0!, _c1!) && c <= math.max(_c0!, _c1!) && math.min(_r0!, _r1!) == 0 && math.max(_r0!, _r1!) == _pageRows.length - 1;

  /// Copies the selection (tab-separated, pastes into Excel / Sheets)
  void _copySelection() {
    if (_r0 == null) return;
    final cols = _visibleColumns;
    final rows = _pageRows;
    final out = StringBuffer();
    for (int r = math.min(_r0!, _r1!); r <= math.max(_r0!, _r1!) && r < rows.length; r++) {
      final line = <String>[];
      for (int c = math.min(_c0!, _c1!); c <= math.max(_c0!, _c1!) && c < cols.length; c++) {
        line.add(_cellValue(rows[r], cols[c]));
      }
      out.writeln(line.join('\t'));
    }
    Clipboard.setData(ClipboardData(text: out.toString().trimRight()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied"), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 1)));
  }

  // ---------------------------------------------------------------------------
  // Build

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
              icon: Icon(Icons.arrow_back_ios_new, color: AppPalette.fg(const Color(0xFF1E2D4A)), size: 19),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            actions: [
              IconButton(
                tooltip: tr("Columns"),
                icon: Icon(Icons.view_week_rounded, color: AppPalette.fg(const Color(0xFF1E2D4A)), size: 21),
                onPressed: _showColumnVisibilityDialog,
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppPalette.fg(const Color(0xFF1E6B3A))),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text("Export"),
                  onPressed: _exportAsExcelCsv,
                ),
              ),
            ],
            bottom: !_dual
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(46),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: FittedBox(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text("${widget.dualTitle}  ", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(const Color(0xFF4A148C)))),
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(visualDensity: VisualDensity.compact),
                            segments: [
                              ButtonSegment(value: true, label: Text(widget.dualLabels.$1)),
                              ButtonSegment(value: false, label: Text(widget.dualLabels.$2)),
                            ],
                            selected: {_wide},
                            onSelectionChanged: (v) {
                              setState(() => _wide = v.first);
                              _load();
                            },
                          ),
                        ]),
                      ),
                    ),
                  ),
          ),
          body: Column(
            children: [
              _buildTopBar(),
              // Ctrl+C / Ctrl+A act on the table's selection (not in the search box)
              Expanded(
                child: Focus(
                  focusNode: _gridFocus,
                  onKeyEvent: (node, e) {
                    if (e is! KeyDownEvent) return KeyEventResult.ignored;
                    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
                    if (ctrl && e.logicalKey == LogicalKeyboardKey.keyC) {
                      _copySelection();
                      return KeyEventResult.handled;
                    }
                    if (ctrl && e.logicalKey == LogicalKeyboardKey.keyA) {
                      _selectAll();
                      return KeyEventResult.handled;
                    }
                    if (e.logicalKey == LogicalKeyboardKey.escape && _r0 != null) {
                      setState(_clearSel);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: _buildSpreadsheetGrid(),
                ),
              ),
              _buildPager(),
            ],
          ),
        ),
      ),
    );
  }

  void _rowMenu(Offset pos, Map<String, dynamic> item) {
    final m = _extractMember(item);
    final name = _getName(m);
    showOfficeMenu(context, pos, [
      if (_r0 != null) OfficeMenuItem("Copy selection", icon: Icons.content_copy_rounded, shortcut: "Ctrl+C", onTap: _copySelection),
      OfficeMenuItem("Log care for $name", icon: Icons.volunteer_activism_outlined, onTap: () => _showMaintenanceDialog(m)),
      const OfficeMenuItem.divider(),
      OfficeMenuItem("Copy name", icon: Icons.person_outline_rounded, onTap: () => Clipboard.setData(ClipboardData(text: name))),
      OfficeMenuItem("Copy row", icon: Icons.table_rows_outlined, onTap: () {
        Clipboard.setData(ClipboardData(text: _visibleColumns.map((c) => _cellValue(item, c)).join('\t')));
      }),
      OfficeMenuItem("Select all", icon: Icons.select_all_rounded, shortcut: "Ctrl+A", onTap: _selectAll),
      const OfficeMenuItem.divider(),
      OfficeMenuItem("Columns…", icon: Icons.view_week_rounded, onTap: _showColumnVisibilityDialog),
      OfficeMenuItem("Change period…", icon: Icons.date_range_outlined, shortcut: "Ctrl+D", onTap: _pickDateRange),
      OfficeMenuItem("Reload", icon: Icons.refresh_rounded, shortcut: "F5", onTap: _load),
      OfficeMenuItem("Export Excel / PDF", icon: Icons.ios_share_rounded, shortcut: "Ctrl+Shift+E", onTap: _exportAsExcelCsv),
      OfficeMenuItem("Print…", icon: Icons.print_rounded, shortcut: "Ctrl+P", onTap: () => TableExport.preview(context, _interventionTable())),
    ]);
  }

  // ---- the bar above the table: period, search and the duty's toggles

  Widget _chip(String label, bool on, VoidCallback onTap, {String? tip}) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Tooltip(
          message: tip ?? label,
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppPalette.bg(on ? headerDarkNavy : Colors.white),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppPalette.line(on ? headerDarkNavy : gridLineColor)),
              ),
              child: Text(label, style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(on ? Colors.white : headerDarkNavy))),
            ),
          ),
        ),
      );

  Widget _group(List<Widget> children) => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppPalette.bg(letterBg),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppPalette.line(gridLineColor)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );

  void _set(VoidCallback f) {
    setState(f);
    _load();
  }

  List<Widget> _dutyToggles() {
    final out = <Widget>[];
    if (_isSA) {
      out.add(_group([
        _chip("Real time", !_pre, () => _set(() => _pre = false)),
        _chip("Pre-attendance", _pre, () => _set(() => _pre = true)),
      ]));
    }
    final days = AbsenteeLogic.daysOf(widget.duty);
    if (days.isNotEmpty && !_isVisit) {
      String short(String d) => d == 'Sunday' ? 'Sun' : d == 'Wednesday' ? 'Wed' : d;
      out.add(_group([
        _chip(_isSA || widget.duty == 'All Saints Education' ? "Both" : "All days", _day == null, () => _set(() => _day = null)),
        for (final d in days) _chip(short(d), _day == d, () => _set(() => _day = d), tip: d),
      ]));
    }
    if (_hasAverage) {
      out.add(_group([
        _chip("Count", !_avg, () => setState(() => _avg = false), tip: "Times missed in the period"),
        _chip("Weekly average", _avg, () => setState(() => _avg = true), tip: "Times missed per week, on average"),
      ]));
    }
    if (_isOffering) {
      out.add(Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        height: 30,
        decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppPalette.line(gridLineColor))),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: _offCol,
            isDense: true,
            style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(headerDarkNavy)),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text("Any offering")),
              for (final c in OfferingCategories.list) DropdownMenuItem<String?>(value: c.column, child: Text(c.label)),
            ],
            onChanged: (v) => _set(() => _offCol = v),
          ),
        ),
      ));
      out.add(_group([
        _chip("All weeks", _offWeek == null, () => _set(() => _offWeek = null)),
        for (int w = 1; w <= 5; w++)
          _chip("W$w", _offWeek == w, () => _set(() => _offWeek = w),
              tip: "Week $w${_offCol != null && _offCol != 'offering_weekly' ? ' (counts what was given in weeks 1–$w)' : ''}"),
      ]));
    }
    return out;
  }

  Widget _buildTopBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.line(gridLineColor), width: 0.6),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HScroll(
          child: Row(children: [
            // Period: one day or a range
            InkWell(
              onTapDown: (d) => _menuPos = d.globalPosition,
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppPalette.bg(headerDarkNavy.withValues(alpha: 0.06)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppPalette.line(headerDarkNavy.withValues(alpha: 0.2))),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.calendar_month_rounded, size: 15, color: AppPalette.fg(headerDarkNavy)),
                  const SizedBox(width: 6),
                  Text("Period: $_periodLabel", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(headerDarkNavy))),
                  const Icon(Icons.arrow_drop_down, size: 16),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 190,
              height: 30,
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
            ..._dutyToggles(),
            const SizedBox(width: 10),
            if (_aiBusy)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 6),
                Text("AI is compiling statuses…", style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.blueGrey))),
              ]),
          ]),
        ),
        if (_aiNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_aiNote!, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.orange.shade800))),
          ),
      ]),
    );
  }

  // ---- paging: 1000 rows at a time

  Widget _buildPager() {
    final total = _filteredData.length;
    final from = total == 0 ? 0 : _page * _pageSize + 1;
    final to = math.min(total, (_page + 1) * _pageSize);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          tooltip: tr("Previous 1000"),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: _page > 0 ? () => _goPage(_page - 1) : null,
        ),
        Flexible(
          child: Text(
            total == 0 ? "No members" : "$from–$to of ${NumberFormat.decimalPattern().format(total)} members${_pageCount > 1 ? '  ·  page ${_page + 1} of $_pageCount' : ''}",
            textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(headerDarkNavy)),
          ),
        ),
        IconButton(
          tooltip: tr("Next 1000"),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: _page < _pageCount - 1 ? () => _goPage(_page + 1) : null,
        ),
      ]),
    );
  }

  Widget _buildSpreadsheetGrid() {
    final cols = _visibleColumns;
    final rows = _pageRows;

    return LayoutBuilder(builder: (context, constraints) {
      double availableWidth = constraints.maxWidth - rowNumWidth - 24;
      double baseTotalWidth = _baseTableWidth;
      double scalingFactor = math.max(1.0, availableWidth / baseTotalWidth);
      // only the row numbers (and the header rows) stay fixed
      final rest = cols;
      double dataTableWidth = math.max(availableWidth, rest.fold(0.0, (acc, k) => acc + (_colWidths[k] ?? 100)) * scalingFactor);

      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.line(gridLineColor), width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row numbers (tap to select the row)
            Container(
              width: rowNumWidth,
              decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(2, 0))]),
              child: Column(
                children: [
                  Row(children: [
                    _buildCornerBox(),
                  ]),
                  Expanded(
                    child: ListView.builder(
                      controller: _verticalScrollRowNumbers,
                      physics: const ClampingScrollPhysics(),
                      itemCount: rows.length,
                      itemExtent: dataRowHeight,
                      itemBuilder: (context, index) {
                        final sel = _rowSelected(index);
                        return Row(children: [
                        GestureDetector(
                          onTap: () => _selectRow(index),
                          child: Container(
                            width: rowNumWidth,
                            height: dataRowHeight,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppPalette.bg(sel ? _selColor.withValues(alpha: 0.22) : (index.isEven ? const Color(0xFFFBFDFB) : const Color(0xFFEEF3F0))),
                              border: Border(
                                right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5),
                                bottom: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5),
                              ),
                            ),
                            child: Text("${_page * _pageSize + index + 1}",
                                style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.w600, color: AppPalette.fg(sel ? _selColor : const Color(0xFF475569)))),
                          ),
                        ),
                        ]);
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable data pane
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
                        _buildColumnLettersRow(rest, scalingFactor),
                        _buildExcelHeadersRow(rest, scalingFactor),
                        Expanded(
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : _loadError != null
                                  ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text("Couldn't load the list (run 20_round19.sql): $_loadError", textAlign: TextAlign.center)))
                                  : rows.isEmpty
                                      ? Center(child: Text(_isVisit ? "Nobody needs counseling or visitation in this period." : "No intervention records found for this period."))
                                      : ListView.builder(
                                          controller: _verticalScrollData,
                                          physics: const ClampingScrollPhysics(),
                                          itemCount: rows.length,
                                          itemExtent: dataRowHeight,
                                          itemBuilder: (context, index) => _buildCompactDataRow(index, rows[index], rest, scalingFactor),
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
    return GestureDetector(
      onTap: _selectAll,
      child: Container(
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
              child: Tooltip(message: tr("Select all"), child: Icon(Icons.select_all_rounded, size: 13, color: AppPalette.fg(const Color(0xFF64748B)))),
            ),
            Container(
              height: headerRowHeight - 1,
              alignment: Alignment.center,
              child: Text("#", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(headerDarkNavy))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnLettersRow(List<String> cols, double factor, {int offset = 0}) {
    return Container(
      height: letterRowHeight,
      decoration: BoxDecoration(color: AppPalette.bg(letterBg), border: Border(bottom: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
      child: Row(
        children: List.generate(cols.length, (i) {
          final colWidth = (_colWidths[cols[i]] ?? 100) * factor;
          final sel = _colSelected(i + offset);
          return GestureDetector(
            onTap: () => _selectColumn(i + offset),
            child: Container(
              width: colWidth,
              height: letterRowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? AppPalette.bg(_selColor.withValues(alpha: 0.22)) : null,
                border: Border(right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5)),
              ),
              child: Text(_getExcelColumnLetter(i + offset), style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.w600, color: AppPalette.fg(sel ? _selColor : const Color(0xFF64748B)))),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildExcelHeadersRow(List<String> cols, double factor, {int offset = 0}) {
    return Container(
      height: headerRowHeight,
      color: AppPalette.bg(headerDarkNavy),
      child: Row(
        children: List.generate(cols.length, (i) {
          final col = cols[i];
          final colWidth = (_colWidths[col] ?? 100) * factor;
          final hasFilter = (_activeFilters[col] ?? const {}).isNotEmpty;
          return Container(
            width: colWidth,
            height: headerRowHeight,
            padding: const EdgeInsets.only(left: 6, right: 2),
            decoration: BoxDecoration(border: Border(right: BorderSide(color: AppPalette.line(Colors.white.withValues(alpha: 0.18)), width: 0.5))),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _selectColumn(i + offset),
                    child: Text(
                      col,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                  ),
                ),
                // filter button: a funnel, filled and amber when a filter is on
                Tooltip(
                  message: hasFilter ? tr("Filter on · tap to change") : tr("Filter"),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => _showCheckboxFilter(col),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: hasFilter ? Colors.amber.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Icon(hasFilter ? Icons.filter_alt_rounded : Icons.filter_list_rounded, size: 14, color: hasFilter ? Colors.amberAccent : Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCompactDataRow(int index, Map<String, dynamic> item, List<String> cols, double factor, {int offset = 0}) {
    final m = _extractMember(item);
    final mid = m['id']?.toString() ?? "";
    final missedCount = _getMissedCount(item);
    final List<dynamic> memberStyles = item['service_styles'] ?? [];
    final Map<String, dynamic> styleCounts = item['style_counts'] ?? {};
    String currentStyle = _memberSelectedStyle[mid] ?? (memberStyles.isNotEmpty ? memberStyles.first.toString() : "Standard");
    int countForCurrentStyle = (styleCounts[currentStyle] ?? 0) as int;
    final Color rowBg = index.isEven ? rowEvenBg : rowOddBg;

    Widget cell(int c, Widget child, {Alignment align = Alignment.center}) {
      final width = (_colWidths[cols[c]] ?? 100) * factor;
      final sel = _inSel(index, c + offset);
      final anchor = _r0 == index && _c0 == c + offset;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectCell(index, c + offset),
        child: Container(
          width: width,
          height: dataRowHeight,
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: sel ? AppPalette.bg(_selColor.withValues(alpha: 0.12)) : null,
            border: anchor
                ? Border.all(color: AppPalette.line(_selColor), width: 1.6)
                : Border(right: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5)),
          ),
          child: child,
        ),
      );
    }

    Widget text(String v, {bool bold = false, Color? color, bool italic = false, TextAlign align = TextAlign.center}) => Text(
          v.isEmpty ? "-" : v,
          textAlign: align,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(fontSize: 11.5, fontWeight: bold ? FontWeight.w600 : FontWeight.normal, fontStyle: italic ? FontStyle.italic : null, color: AppPalette.fg(color ?? Colors.black87)),
        );

    return OfficeRightClick(
      longPress: true,
      onMenu: (p) => _rowMenu(p, item),
      child: Container(
        height: dataRowHeight,
        decoration: BoxDecoration(color: AppPalette.bg(rowBg), border: Border(bottom: BorderSide(color: AppPalette.line(gridLineColor), width: 0.5))),
        child: Row(
          children: List.generate(cols.length, (c) {
            final col = cols[c];
            switch (col) {
              case "Name":
                return cell(c, text(_getName(m), bold: true));
              case "Service Style":
                return cell(
                  c,
                  memberStyles.isEmpty
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
                              if (val != null) setState(() => _memberSelectedStyle[mid] = val);
                            },
                          ),
                        ),
                );
              case "Style Count":
                return cell(
                  c,
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppPalette.bg(countForCurrentStyle > 0 ? Colors.blue.shade50 : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text("${countForCurrentStyle}x",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(countForCurrentStyle > 0 ? Colors.blue[900] : Colors.grey[600]))),
                  ),
                );
              case "Missed":
                return cell(c, Text(_missedText(item), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(missedCount >= 4 ? Colors.red[700] : Colors.orange[800]))));
              case "Current Status":
                final st = _statusText(item);
                return cell(c, Tooltip(message: st, waitDuration: const Duration(milliseconds: 500), child: text(st, color: Colors.blueGrey.shade800, align: TextAlign.left)), align: Alignment.centerLeft);
              case "Kind of Visitation Needed":
                return cell(c, text(_kindsText(item), bold: true, color: const Color(0xFF6A1B9A)));
              case "Reason Not Visited":
                final nv = _notVisitedText(item);
                return cell(c, Tooltip(message: nv, child: text(nv, italic: !nv.startsWith('Visited'), color: nv.startsWith('Visited') ? Colors.green.shade800 : Colors.red.shade700, align: TextAlign.left)), align: Alignment.centerLeft);
              default:
                return cell(c, text(_cellValue(item, col)));
            }
          }),
        ),
      ),
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
                    setState(_clearSel);
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

  /// Every filtered row (all pages), as shown
  ExportTable _interventionTable() {
    final cols = _visibleColumns;
    final rows = [for (final item in _filteredData) cols.map((c) => _cellValue(item, c)).toList()];
    final parts = <String>[
      widget.duty,
      "Period: $_periodLabel",
      if (_isSA) _pre ? "Pre-attendance" : "Real time",
      if (_day != null) "Day: $_day",
      if (_isOffering && _offCol != null) OfferingCategories.list.where((c) => c.column == _offCol).map((c) => c.label).join(),
      if (_isOffering && _offWeek != null) "Week $_offWeek",
      if (_avg && _hasAverage) "Weekly average",
      "${rows.length} members",
    ];
    return ExportTable(
      title: "$_screenTitle – ${widget.unitName}",
      subtitle: parts.join(' · '),
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
                decoration: InputDecoration(labelText: tr("Outcome"), border: const OutlineInputBorder()),
                items: ['Recovered', 'Sick', 'Working', 'Travelled', 'Unresolved'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setST(() => selectedOutcome = v!),
              ),
              const SizedBox(height: 12),
              TextField(controller: noteCtrl, decoration: InputDecoration(hintText: tr("Notes..."), border: const OutlineInputBorder()), maxLines: 2),
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
    final values = <String>{for (final item in _data) _cellValue(item, column).isEmpty ? "N/A" : _cellValue(item, column)};
    final options = values.toList()..sort();
    final chosen = Set<String>.from(_activeFilters[column] ?? const <String>{});
    String q = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final shown = options.where((o) => q.isEmpty || o.toLowerCase().contains(q.toLowerCase())).toList();
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(children: [
              Icon(Icons.filter_list_rounded, size: 18, color: AppPalette.fg(headerDarkNavy)),
              const SizedBox(width: 6),
              Expanded(child: Text("Filter $column", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.fg(headerDarkNavy)))),
            ]),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(hintText: tr("Search..."), isDense: true, prefixIcon: const Icon(Icons.search, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6))),
                    onChanged: (v) => setDialogState(() => q = v),
                  ),
                  CheckboxListTile(
                    dense: true,
                    title: const Text("Select all", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    value: chosen.isEmpty,
                    onChanged: (_) => setDialogState(chosen.clear),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final opt = shown[i];
                        return CheckboxListTile(
                          dense: true,
                          title: Text(opt, style: const TextStyle(fontSize: 11.5)),
                          value: chosen.contains(opt),
                          onChanged: (v) => setDialogState(() {
                            if (v == true) {
                              chosen.add(opt);
                            } else {
                              chosen.remove(opt);
                            }
                          }),
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
                  _activeFilters.remove(column);
                  _applyFilters();
                  Navigator.pop(context);
                },
                child: const Text("Clear"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(actionBtnBlue)),
                onPressed: () {
                  _activeFilters[column] = chosen;
                  _applyFilters();
                  Navigator.pop(context);
                },
                child: Text("Apply Filter", style: TextStyle(color: AppPalette.fg(Colors.white))),
              ),
            ],
          );
        },
      ),
    );
  }
}
