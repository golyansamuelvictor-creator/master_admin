// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:typed_data';
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/table_export.dart';
import '../../core/app_sizes.dart';
import '../../core/compilation_rules.dart';
import 'package:master_admin/core/app_palette.dart';

/// One duty in the report: this period against the period before.
class DutyStat {
  final String dutyName;
  final String label;
  final String tableName;
  final IconData icon;
  final Color color;
  final double currentRate;
  final double previousRate;
  final int currentCount; // reports this period
  final int previousCount;
  final int done;
  final int sessions;
  final int unitsReporting;
  final bool forWorkers;

  DutyStat({
    required this.dutyName,
    required this.tableName,
    required this.icon,
    required this.color,
    required this.currentRate,
    required this.previousRate,
    required this.currentCount,
    required this.previousCount,
    this.label = '',
    this.done = 0,
    this.sessions = 0,
    this.unitsReporting = 0,
    this.forWorkers = false,
  });

  double get diff => currentRate - previousRate;
  bool get isPositive => diff >= 0;
  String get title => label.isEmpty ? dutyName : label;
}

/// Performance Report (was the Monthly executive report): every duty of the role compiled into one report
/// for the leader's own unit (location, sub-location, department, team, cell
/// or church-wide group), with the period before for comparison.
///
/// The numbers are added up in the database (exec_report in 11_round10.sql)
/// with the same rule as the Compilation screen: rate = reports marked done ÷
/// (sessions × members). The area is decided on the server from the profile
/// and role, so nobody sees outside their unit. Which duties appear, their
/// order, colours and icons come from the `report_duties` table.
class MonthlyExecutiveReport extends StatefulWidget {
  final String? userRole;
  final String? userUnit;

  const MonthlyExecutiveReport({
    super.key,
    this.userRole,
    this.userUnit,
  });

  @override
  State<MonthlyExecutiveReport> createState() => _MonthlyExecutiveReportState();
}

class _MonthlyExecutiveReportState extends State<MonthlyExecutiveReport> {
  final _supabase = Supabase.instance.client;
  final Color pPurple = const Color(0xFF3B0764);
  bool _isLoading = true;
  String? _error;
  int _req = 0;

  // User jurisdiction
  String _activeRole = 'church_head_instructor';
  String _activeUnit = 'Church executive';
  String _userLoc = "";
  String _userSub = "";
  String _userDept = "";
  String _userTeam = "";
  String _userCell = "";
  String? _userId;

  // Report period selection
  final List<String> _periodOptions = [
    'Weekly',
    'Monthly',
    'Quarterly',
    'Half year',
    'Yearly',
    'Custom period',
  ];
  String _selectedPeriod = 'Monthly';
  DateTimeRange? _customRange;
  late DateTime _curStart, _curEnd;
  late DateTime _prevStart, _prevEnd;
  bool _includePending = true;

  // Accountability drilldown level
  static const Map<String, String> _levelCols = {
    'Location': 'location',
    'Sub location': 'sub_location',
    'Department': 'department',
    'Team': 'team',
    'Cell': 'cell_group',
  };
  String _drilldownLevel = 'Team';
  List<String> _drillLevels = ['Location', 'Sub location', 'Department', 'Team', 'Cell'];
  // Narrower view inside your area: [{level, value}] (tap a unit to open it)
  final List<MapEntry<String, String>> _focus = [];

  // Aggregated stats
  int totalSaints = 0;
  int totalWorkers = 0;
  int newConverts = 0;
  int newConvertsPrev = 0;
  int dropouts = 0;
  int successfulRecoveries = 0;
  int netGrowth = 0;
  int transfersIn = 0;
  int transfersOut = 0;

  // Performance comparison (units of the same level inside the same parent)
  String? _cmpDuty;
  String _cmpLevel = 'location';
  bool _cmpLoading = false;
  String? _cmpError;
  List<Map<String, String>> _cmpBuckets = [];
  List<Map<String, dynamic>> _cmpRows = []; // {unit, mine, rates: {label: rate}}
  int _cmpReq = 0;

  // AI compiled insights (not saved until "Save")
  Map<String, dynamic>? _ai;
  bool _aiBusy = false;

  double attendanceCompliance = 0.0;
  double churchAvgAttendance = 0.0;
  double overallRate = 0.0;
  List<String> missingUnits = [];
  List<Map<String, dynamic>> _units = [];
  Map<String, dynamic> _managerInsights = {};
  List<DutyStat> _dutyStats = [];

  bool get _isChurchWideScope {
    String r = _activeRole.toLowerCase();
    return r == 'admin' || r.startsWith('church_') || r.startsWith('korean_worker_') || r.contains('_dept_');
  }

  @override
  void initState() {
    super.initState();
    _calculatePeriods();
    _identifyAndLoad();
  }

  void _calculatePeriods() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Weekly':
        _curStart = now.subtract(const Duration(days: 6));
        _curEnd = now;
        _prevStart = _curStart.subtract(const Duration(days: 7));
        _prevEnd = _curStart.subtract(const Duration(days: 1));
        break;
      case 'Monthly':
        _curStart = DateTime(now.year, now.month, 1);
        _curEnd = now;
        _prevStart = DateTime(now.year, now.month - 1, 1);
        _prevEnd = DateTime(now.year, now.month, 0);
        break;
      case 'Quarterly':
        int q = ((now.month - 1) ~/ 3) * 3 + 1;
        _curStart = DateTime(now.year, q, 1);
        _curEnd = now;
        _prevStart = DateTime(now.year, q - 3, 1);
        _prevEnd = DateTime(now.year, q, 0);
        break;
      case 'Half year':
        int h = now.month <= 6 ? 1 : 7;
        _curStart = DateTime(now.year, h, 1);
        _curEnd = now;
        _prevStart = h == 1 ? DateTime(now.year - 1, 7, 1) : DateTime(now.year, 1, 1);
        _prevEnd = DateTime(_curStart.year, _curStart.month, 0);
        break;
      case 'Yearly':
        _curStart = DateTime(now.year, 1, 1);
        _curEnd = now;
        _prevStart = DateTime(now.year - 1, 1, 1);
        _prevEnd = DateTime(now.year - 1, 12, 31);
        break;
      case 'Custom period':
        if (_customRange != null) {
          _curStart = _customRange!.start;
          _curEnd = _customRange!.end;
          final duration = _curEnd.difference(_curStart);
          _prevEnd = _curStart.subtract(const Duration(days: 1));
          _prevStart = _prevEnd.subtract(duration);
        } else {
          _curStart = DateTime(now.year, now.month, 1);
          _curEnd = now;
          _prevStart = DateTime(now.year, now.month - 1, 1);
          _prevEnd = DateTime(now.year, now.month, 0);
        }
        break;
    }
  }

  Future<void> _identifyAndLoad() async {
    try {
      final user = _supabase.auth.currentUser;
      _userId = user?.id;
      if (user != null) {
        final profile = await _supabase.from('profiles').select().eq('id', user.id).maybeSingle();
        if (profile != null && mounted) {
          _activeRole = widget.userRole ?? profile['role'] ?? 'church_head_instructor';
          _userLoc = profile['location'] ?? "";
          _userSub = profile['sub_location'] ?? "";
          _userDept = profile['department'] ?? "";
          _userTeam = profile['team'] ?? "";
          _userCell = profile['cell_group'] ?? "";
          _activeUnit = widget.userUnit ?? _resolveUnitName();
        }
      }
    } catch (e) {
      debugPrint("Identify error: $e");
    }
    await _loadReportData(first: true);
  }

  String _resolveUnitName() {
    String r = _activeRole.toLowerCase();
    if (_isChurchWideScope) return "Church executive";
    if (r.contains('cell')) return _userCell.isNotEmpty ? _userCell : "Cell";
    if (r.contains('team')) return _userTeam.isNotEmpty ? _userTeam : "Team";
    if (r.contains('dept')) return _userDept.isNotEmpty ? _userDept : "Department";
    if (r.contains('sub_loc')) return _userSub.isNotEmpty ? _userSub : "Sub location";
    if (r.contains('loc')) return _userLoc.isNotEmpty ? _userLoc : "Location";
    return "Church admin";
  }

  /// Levels below the area the server gave (a team leader can't pick Location).
  void _setLevelsFromScope(List scope) {
    final fixed = {
      for (final f in scope)
        if (f is Map && f['op'] == 'eq') f['col'].toString(),
    };
    final cols = _levelCols.entries.toList();
    int deepest = -1;
    for (int i = 0; i < cols.length; i++) {
      if (fixed.contains(cols[i].value)) deepest = i;
    }
    final levels = [for (int i = deepest + 1; i < cols.length; i++) cols[i].key];
    _drillLevels = levels.isEmpty ? ['Cell'] : levels;
    if (!_drillLevels.contains(_drilldownLevel)) {
      _drilldownLevel = _drillLevels.length > 1 ? _drillLevels[0] : _drillLevels.last;
    }
  }

  String _d(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static IconData _icon(String name) => switch (name) {
        'groups' => Icons.groups_rounded,
        'meeting_room' => Icons.meeting_room_rounded,
        'school' => Icons.school_rounded,
        'wb_sunny' => Icons.wb_sunny_rounded,
        'campaign' => Icons.campaign_rounded,
        'support_agent' => Icons.support_agent_rounded,
        'volunteer' => Icons.volunteer_activism_rounded,
        'menu_book' => Icons.menu_book_rounded,
        'task' => Icons.assignment_turned_in_rounded,
        _ => Icons.assignment_rounded,
      };

  static Color _hex(String? h, Color fallback) {
    final s = (h ?? '').replaceAll('#', '');
    final v = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
    return v == null ? fallback : Color(v);
  }

  Future<void> _loadReportData({bool first = false}) async {
    if (!mounted) return;
    final req = ++_req;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final focus = [
        for (final f in _focus) {'col': _levelCols[f.key], 'op': 'eq', 'val': f.value},
      ];
      final res = await _supabase.rpc('exec_report', params: {
        'p_from': _d(_curStart),
        'p_to': _d(_curEnd),
        'p_prev_from': _d(_prevStart),
        'p_prev_to': _d(_prevEnd),
        'p_level': _levelCols[_drilldownLevel],
        'p_include_pending': _includePending,
        'p_focus': focus,
      });
      if (!mounted || req != _req) return;
      final j = Map<String, dynamic>.from(res as Map);
      if (first) {
        _setLevelsFromScope((j['scope'] as List?) ?? const []);
        if (_levelCols[_drilldownLevel] != j['level']) {
          // the level was adjusted to the area: load once more at that level
          return _loadReportData();
        }
      }

      int i(dynamic v) => (v as num?)?.toInt() ?? 0;
      double dd(dynamic v) => (v as num?)?.toDouble() ?? 0;

      totalSaints = i(j['members']);
      totalWorkers = i(j['workers']);
      newConverts = i(j['new_members']);
      newConvertsPrev = i(j['new_members_prev']);
      dropouts = i(j['dropouts']);
      successfulRecoveries = i(j['recoveries']);
      try {
        final t = await _supabase.rpc('report_transfers', params: {'p_from': _d(_curStart), 'p_to': _d(_curEnd), 'p_focus': focus});
        transfersIn = i((t as Map?)?['transfers_in']);
        transfersOut = i(t?['transfers_out']);
      } catch (_) {
        transfersIn = 0;
        transfersOut = 0;
      }
      netGrowth = newConverts - dropouts + transfersIn - transfersOut;

      _dutyStats = [
        for (final raw in (j['duties'] as List? ?? const []))
          () {
            final d = Map<String, dynamic>.from(raw as Map);
            return DutyStat(
              dutyName: d['duty'].toString(),
              label: (d['label'] ?? '').toString(),
              tableName: (d['table'] ?? '').toString(),
              icon: _icon((d['icon'] ?? '').toString()),
              color: _hex(d['color']?.toString(), pPurple),
              currentRate: dd(d['rate']),
              previousRate: dd(d['prev_rate']),
              currentCount: i(d['reports']),
              previousCount: i(d['prev_reports']),
              done: i(d['done']),
              sessions: i(d['sessions']),
              unitsReporting: i(d['units_reporting']),
              forWorkers: d['for_workers'] == true,
            );
          }(),
      ];

      _units = [for (final u in (j['units'] as List? ?? const [])) Map<String, dynamic>.from(u as Map)];

      final service = _dutyStats.where((d) => d.tableName == 'logs_service_attendance_status').firstOrNull;
      churchAvgAttendance = service?.currentRate ?? 0;
      final reported = _dutyStats.where((d) => d.currentCount > 0).toList();
      overallRate = reported.isEmpty ? 0 : reported.map((d) => d.currentRate).reduce((a, b) => a + b) / reported.length;

      // Compliance: units that sent every duty of the report this period
      missingUnits = [];
      int complete = 0;
      for (final u in _units) {
        final duties = Map<String, dynamic>.from(u['duties'] as Map? ?? {});
        final missing = _dutyStats.where((d) => ((duties[d.dutyName] as Map?)?['reports'] ?? 0) == 0).map((d) => d.title).toList();
        if (missing.isEmpty) {
          complete++;
        } else {
          missingUnits.add("${u['unit']}: ${missing.join(', ')}");
        }
      }
      attendanceCompliance = _units.isEmpty ? 0 : complete * 100 / _units.length;

      // Managerial insights saved for this period and unit
      try {
        final insights = await _supabase
            .from('manager_insights')
            .select()
            .eq('duty_name', 'Monthly Executive Summary')
            .eq('unit_id', _unitKey)
            .gte('period_start', _d(_curStart))
            .order('period_start', ascending: false)
            .limit(1)
            .maybeSingle();
        _managerInsights = insights ?? {};
      } catch (_) {
        _managerInsights = {};
      }

      _ai = null;
      if (mounted && req == _req) setState(() => _isLoading = false);
      if (_dutyStats.isNotEmpty) {
        if (_cmpDuty == null || !_dutyStats.any((d) => d.dutyName == _cmpDuty)) _cmpDuty = _dutyStats.first.dutyName;
        _loadComparison();
      }
    } catch (e) {
      debugPrint("Report aggregate error: $e");
      if (mounted && req == _req) {
        setState(() {
          _isLoading = false;
          _error = e is PostgrestException ? "Couldn't build the report: ${e.message}. Ask the admin to run 11_round10.sql." : "Couldn't build the report: $e";
        });
      }
    }
  }

  /// Which unit the saved insights belong to (role + area + the unit opened).
  String get _unitKey => [_activeUnit, for (final f in _focus) f.value].join(' › ');

  String get _periodText => "${DateFormat('d MMM').format(_curStart)} – ${DateFormat('d MMM yyyy').format(_curEnd)}";
  String get _prevText => "${DateFormat('d MMM').format(_prevStart)} – ${DateFormat('d MMM yyyy').format(_prevEnd)}";

  String _formatRole(String r) {
    return r.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? "" : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  // ==========================================
  // Written findings (from the numbers, when nobody has written them yet)
  // ==========================================
  String get _autoSummary {
    if (_dutyStats.every((d) => d.currentCount == 0)) return "No reports have been submitted for $_periodText yet.";
    final best = ([..._dutyStats.where((d) => d.currentCount > 0)]..sort((a, b) => b.currentRate.compareTo(a.currentRate))).first;
    final up = _dutyStats.where((d) => d.currentCount > 0 && d.diff > 0.5).map((d) => d.title).toList();
    final down = _dutyStats.where((d) => d.currentCount > 0 && d.diff < -0.5).map((d) => d.title).toList();
    return "$totalSaints members in the unit, ${newConverts >= 0 ? '+' : ''}$newConverts new and $dropouts dropped out (net ${netGrowth >= 0 ? '+' : ''}$netGrowth). "
        "Average duty rate ${overallRate.toStringAsFixed(1)}%, service attendance ${churchAvgAttendance.toStringAsFixed(1)}%. "
        "Strongest duty: ${best.title} (${best.currentRate.toStringAsFixed(1)}%)."
        "${up.isEmpty ? '' : ' Improved: ${up.join(', ')}.'}${down.isEmpty ? '' : ' Dropped: ${down.join(', ')}.'}";
  }

  String get _autoProblems {
    final weak = _dutyStats.where((d) => d.currentCount > 0 && d.currentRate < 60).map((d) => "${d.title} (${d.currentRate.toStringAsFixed(1)}%)").toList();
    final none = _dutyStats.where((d) => d.currentCount == 0).map((d) => d.title).toList();
    final parts = <String>[
      if (weak.isNotEmpty) "Below 60%: ${weak.join(', ')}.",
      if (none.isNotEmpty) "No reports at all: ${none.join(', ')}.",
      if (missingUnits.isNotEmpty) "${missingUnits.length} of ${_units.length} ${_drilldownLevel.toLowerCase()} units did not send every duty.",
    ];
    return parts.isEmpty ? "No persistent operational failures flagged for this evaluation period." : parts.join(' ');
  }

  String get _autoActions {
    final weak = ([..._dutyStats.where((d) => d.currentCount > 0)]..sort((a, b) => a.currentRate.compareTo(b.currentRate))).take(2).map((d) => d.title).toList();
    return [
      if (missingUnits.isNotEmpty) "Follow up the units that have not reported every duty.",
      if (weak.isNotEmpty) "Focus pastoral follow-up and education on ${weak.join(' and ')}.",
      if (dropouts > 0) "Visit the $dropouts member${dropouts == 1 ? '' : 's'} who dropped out and record the care in the absentee list.",
      "Review this report with unit leaders before the next period.",
    ].join(' ');
  }

  String _insight(String key, String auto) {
    final v = (_managerInsights[key] ?? '').toString().trim();
    return v.isEmpty ? auto : v;
  }

  Future<void> _editInsights() async {
    final obs = TextEditingController(text: _aiText('executive_summary') ?? _insight('observation', _autoSummary));
    final root = TextEditingController(text: _aiText('problems') ?? _insight('root_cause', _autoProblems));
    final act = TextEditingController(text: _aiText('actions') ?? _insight('recommended_action', _autoActions));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Findings for $_periodText", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: obs, maxLines: 4, decoration: InputDecoration(labelText: tr("Executive summary"), border: const OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: root, maxLines: 4, decoration: InputDecoration(labelText: tr("Problem areas and root causes"), border: const OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: act, maxLines: 4, decoration: InputDecoration(labelText: tr("Recommended leadership actions"), border: const OutlineInputBorder())),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final row = {
        'period_start': _d(_curStart),
        'period_end': _d(_curEnd),
        'duty_name': 'Monthly Executive Summary',
        'unit_id': _unitKey,
        'observation': obs.text.trim(),
        'root_cause': root.text.trim(),
        'recommended_action': act.text.trim(),
        'manager_id': _userId,
      };
      final id = _managerInsights['id'];
      if (id != null && _managerInsights['period_start'] == _d(_curStart)) {
        await _supabase.from('manager_insights').update(row).eq('id', id);
      } else {
        await _supabase.from('manager_insights').insert(row);
      }
      if (!mounted) return;
      setState(() {
        _managerInsights = {..._managerInsights, ...row};
        _ai = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Findings saved"), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save the findings: $e"), backgroundColor: Colors.red.shade700));
    }
  }

  // ==========================================
  // EXPORTS (Excel, PDF, Print)
  // ==========================================
  ExportTable _dutyTable() => ExportTable(
        title: "Performance report – $_unitKey",
        subtitle: "$_periodText (previous: $_prevText) · ${_includePending ? 'approved and pending reports' : 'approved reports only'}",
        headers: const ['Duty', 'Reports', 'Done', 'Sessions', 'Rate %', 'Previous %', 'Change'],
        rows: [
          for (final d in _dutyStats)
            [
              d.title,
              '${d.currentCount}',
              '${d.done}',
              '${d.sessions}',
              d.currentRate.toStringAsFixed(1),
              d.previousRate.toStringAsFixed(1),
              "${d.isPositive ? '+' : ''}${d.diff.toStringAsFixed(1)}",
            ],
        ],
      );

  ExportTable _unitTable() => ExportTable(
        title: "Unit accountability – $_drilldownLevel",
        subtitle: _periodText,
        headers: [_drilldownLevel, 'Members', for (final d in _dutyStats) d.title],
        rows: [
          for (final u in _units)
            [
              u['unit'].toString(),
              '${u['members'] ?? 0}',
              for (final d in _dutyStats) _unitCell(u, d),
            ],
        ],
      );

  String _unitCell(Map u, DutyStat d) {
    final x = (u['duties'] as Map?)?[d.dutyName] as Map?;
    if (x == null || (x['reports'] ?? 0) == 0) return '—';
    return "${(x['rate'] as num).toStringAsFixed(1)}%";
  }

  /// Both tables in one Excel sheet: duties first, then units.
  ExportTable _excelTable() {
    final duty = _dutyTable(), unit = _unitTable();
    final width = duty.headers.length > unit.headers.length ? duty.headers.length : unit.headers.length;
    List<String> pad(List<String> r) => [...r, for (int i = r.length; i < width; i++) ''];
    return ExportTable(
      title: duty.title,
      subtitle: duty.subtitle,
      headers: pad(duty.headers),
      rows: [
        for (final r in duty.rows) pad(r),
        pad([]),
        pad(['Members', '$totalSaints', 'New', '$newConverts', 'Dropouts', '$dropouts', 'Recovered', '$successfulRecoveries']),
        pad(['Transfers in', '$transfersIn', 'Transfers out', '$transfersOut']),
        pad([]),
        pad(unit.headers),
        for (final r in unit.rows) pad(r),
      ],
    );
  }

  Future<Uint8List> _pdf(PdfPageFormat format) async {
    pw.ThemeData theme;
    try {
      theme = pw.ThemeData.withFont(
        base: await PdfGoogleFonts.merriweatherRegular(),
        bold: await PdfGoogleFonts.merriweatherBold(),
        fontFallback: [await PdfGoogleFonts.notoSansKRRegular()],
      );
    } catch (_) {
      theme = pw.ThemeData();
    }
    final doc = pw.Document(theme: theme, title: 'Performance report');
    final duty = _dutyTable(), unit = _unitTable();
    pw.Widget table(ExportTable t, double fs) => pw.TableHelper.fromTextArray(
          headers: t.headers,
          data: t.fitted,
          headerStyle: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.purple900),
          cellStyle: pw.TextStyle(fontSize: fs),
          cellAlignment: pw.Alignment.center,
          cellAlignments: {0: pw.Alignment.centerLeft},
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.4),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        );
    pw.Widget box(String label, String value) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 6),
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
              pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
            ]),
          ),
        );
    pw.Widget para(int n, String title, String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text("$n. $title", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
          ]),
        );
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(26),
      header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text("PERFORMANCE REPORT", style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
        pw.Text("${_formatRole(_activeRole)} · $_unitKey · $_periodText (previous: $_prevText)", style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
      ]),
      footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Printed ${DateFormat('d MMM yyyy, HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
      ]),
      build: (ctx) => [
        pw.Row(children: [
          box("Members", "$totalSaints"),
          box("New members", "+$newConverts"),
          box("Dropouts", "-$dropouts"),
          box("Recovered", "$successfulRecoveries"),
          box("Transfers in / out", "+$transfersIn / -$transfersOut"),
          box("Service attendance", "${churchAvgAttendance.toStringAsFixed(1)}%"),
          box("Units complete", "${attendanceCompliance.toStringAsFixed(0)}%"),
        ]),
        pw.SizedBox(height: 10),
        pw.Text("Duties", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        table(duty, 8.5),
        pw.SizedBox(height: 12),
        pw.Text("Unit accountability – $_drilldownLevel", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        table(unit, unit.headers.length > 9 ? 6.5 : 7.5),
        pw.SizedBox(height: 12),
        pw.Text("Managerial insights and recommendations", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        para(1, "Executive summary", _insight('observation', _autoSummary)),
        para(11, "Problem areas and root causes", _insight('root_cause', _autoProblems)),
        para(13, "Recommended leadership actions", _insight('recommended_action', _autoActions)),
      ],
    ));
    return doc.save();
  }

  PdfPageFormat get _pdfFormat => _dutyStats.length > 7 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

  Future<void> _downloadPdf() async {
    try {
      final bytes = await _pdf(_pdfFormat);
      await Printing.sharePdf(bytes: bytes, filename: 'Executive_report_${_d(_curStart)}.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PDF export failed: $e"), backgroundColor: Colors.red.shade700));
    }
  }

  // ==========================================
  // UI LAYOUT
  // ==========================================

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 900;
    double sidePadding = isDesktop ? 16.0 : AppSizes.gutter;

    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppPalette.fg(const Color(0xFF3B0764))),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Performance Report",
          style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple), fontSize: 21),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadReportData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: sidePadding, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Toolbar
              _buildTopToolbar(isDesktop),
              if (_focus.isNotEmpty) ...[const SizedBox(height: 8), _buildFocusBar()],
              const SizedBox(height: 12),
              if (_isLoading)
                const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator(color: Color(0xFF3B0764))))
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(30),
                  child: Center(child: Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.red.shade800)))),
                )
              else ...[
                // Growth performance card
                _buildGrowthCard(),
                const SizedBox(height: 14),

                // Operational duties performance (tap a card for its trend)
                _sectionTitle("Operational duties performance and trends"),
                const SizedBox(height: 8),
                _buildDutyGrid(width),
                const SizedBox(height: 16),

                // Performance comparison with the units of the same level
                _sectionTitle("Performance comparison"),
                const SizedBox(height: 8),
                _buildComparison(),
                const SizedBox(height: 16),

                // Managerial insights
                Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _sectionTitle("Managerial insights and recommendations"),
                  Wrap(spacing: 4, children: [
                    TextButton.icon(
                      onPressed: _aiBusy ? null : _compileWithAi,
                      icon: _aiBusy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text("Compile with AI"),
                    ),
                    TextButton.icon(onPressed: _editInsights, icon: const Icon(Icons.edit_note_rounded, size: 18), label: const Text("Write findings")),
                  ]),
                ]),
                const SizedBox(height: 6),
                if (_ai != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: _raised().copyWith(color: AppPalette.bg(const Color(0xFFFFF8E1))),
                    child: Row(children: [
                      Icon(Icons.auto_awesome_rounded, size: 18, color: AppPalette.fg(Colors.amber.shade900)),
                      const SizedBox(width: 8),
                      Expanded(child: Text("Compiled by AI from ${_ai!['findings_used'] ?? 0} leaders' findings and the numbers above. Check it, then save it as the findings.",
                          style: const TextStyle(fontSize: 12))),
                      TextButton(onPressed: _editInsights, child: const Text("Review & save")),
                    ]),
                  ),
                _build14PointCard(1, "Executive summary", _aiText('executive_summary') ?? _insight('observation', _autoSummary)),
                _build14PointCard(11, "Problem areas and root causes", _aiText('problems') ?? _insight('root_cause', _autoProblems)),
                _build14PointCard(13, "Recommended leadership actions", _aiText('actions') ?? _insight('recommended_action', _autoActions)),
                const SizedBox(height: 35),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopToolbar(bool isDesktop) {
    final period = Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF3E5F5)), borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedPeriod,
          isDense: true,
          style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)),
          items: _periodOptions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
          onChanged: (v) async {
            if (v == null) return;
            if (v == 'Custom period') {
              final p = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime.now());
              if (p != null) {
                setState(() {
                  _selectedPeriod = v;
                  _customRange = p;
                  _calculatePeriods();
                });
                _loadReportData();
              }
            } else {
              setState(() {
                _selectedPeriod = v;
                _calculatePeriods();
              });
              _loadReportData();
            }
          },
        ),
      ),
    );
    final pending = FilterChip(
      label: Text(_includePending ? "With pending reports" : "Approved only", style: GoogleFonts.merriweather(fontSize: 11.5)),
      selected: _includePending,
      onSelected: (v) {
        setState(() => _includePending = v);
        _loadReportData();
      },
    );
    final exports = Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        icon: Icon(Icons.picture_as_pdf_rounded, color: AppPalette.fg(Colors.red), size: 20),
        tooltip: tr("Download PDF"),
        onPressed: _isLoading || _error != null ? null : _downloadPdf,
      ),
      IconButton(
        icon: Icon(Icons.table_view_rounded, color: AppPalette.fg(Colors.green), size: 20),
        tooltip: tr("Export Excel"),
        onPressed: _isLoading || _error != null ? null : () => TableExport.excel(context, _excelTable()),
      ),
      IconButton(
        icon: Icon(Icons.print_rounded, color: AppPalette.fg(Colors.blueGrey), size: 20),
        tooltip: tr("Print report"),
        onPressed: _isLoading || _error != null
            ? null
            : () => TableExport.previewBuilder(context, "Executive report", _pdf, fileName: 'Executive_report_${_d(_curStart)}.pdf', initial: _pdfFormat),
      ),
    ]);
    return Container(
      // as wide as the cards below it
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: _raised(),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 6,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shield_outlined, size: 18, color: AppPalette.fg(pPurple)),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isDesktop ? 420 : 240),
              child: Text(
                "${_formatRole(_activeRole)} • $_activeUnit",
                style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[900])),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          Text(_periodText, style: GoogleFonts.merriweather(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
          period,
          pending,
          exports,
        ],
      ),
    );
  }

  Widget _buildFocusBar() {
    return Center(
      child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ActionChip(
          avatar: const Icon(Icons.home_work_outlined, size: 16),
          label: Text(_activeUnit),
          onPressed: () {
            final first = _focus.isEmpty ? null : _focus.first.key;
            setState(() {
              _focus.clear();
              if (first != null) _drilldownLevel = first;
            });
            _loadReportData();
          },
        ),
        for (int i = 0; i < _focus.length; i++) ...[
          const Icon(Icons.chevron_right_rounded, size: 18),
          ActionChip(
            label: Text(_focus[i].value),
            onPressed: () {
              setState(() {
                final next = i + 1 < _focus.length ? _focus[i + 1].key : null;
                _focus.removeRange(i + 1, _focus.length);
                if (next != null) _drilldownLevel = next;
              });
              _loadReportData();
            },
          ),
        ],
      ]),
    );
  }

  Widget _buildGrowthCard() {
    bool up = netGrowth >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppPalette.solid(pPurple), AppPalette.solid(const Color(0xFF1E1B4B))], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: pPurple.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text("Total saint growth and stability", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white70), fontSize: 13, fontWeight: FontWeight.bold))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppPalette.bg(up ? Colors.green.withValues(alpha: 0.25) : Colors.red.withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(6)),
                child: Text("${up ? '+' : ''}$netGrowth saints", style: GoogleFonts.merriweather(color: AppPalette.fg(up ? Colors.greenAccent : Colors.redAccent), fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text("$totalSaints", style: GoogleFonts.merriweather(fontSize: 28, fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.white))),
          Text("Registered members in your unit · $totalWorkers workers", style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.white60))),
          Divider(color: AppPalette.bg(Colors.white24), height: 16),
          Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 18,
            runSpacing: 8,
            children: [
              _metricCol("New members", "+$newConverts", Colors.greenAccent),
              _metricCol("Previous Number", "+$newConvertsPrev", Colors.white70),
              _metricCol("Dropouts", "-$dropouts", Colors.redAccent),
              _metricCol("Transfers in", "+$transfersIn", Colors.lightBlueAccent),
              _metricCol("Transfers out", "-$transfersOut", Colors.orangeAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCol(String l, String v, Color c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.w900, color: AppPalette.fg(c))),
          Text(l, style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.white60))),
        ],
      );

  /// Every card of the report: white, raised from the page with a soft
  /// shadow underneath ([strong] for the Performance comparison).
  BoxDecoration _raised({bool strong = false}) => BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: pPurple.withValues(alpha: strong ? 0.22 : 0.12), blurRadius: strong ? 22 : 12, offset: Offset(0, strong ? 10 : 5)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      );

  /// Performance comparison: table or column chart
  bool _cmpChart = false;

  // ==========================================
  // CHANGE COLOURS (green up, red down, grey no change)
  // ==========================================
  static Color _changeColor(double diff) => diff > 0.05 ? Colors.green.shade700 : (diff < -0.05 ? Colors.red.shade700 : Colors.grey.shade600);
  static String _changeText(double diff) => diff.abs() <= 0.05 ? "0.0%" : "${diff > 0 ? '+' : ''}${diff.toStringAsFixed(1)}%";

  // ==========================================
  // DUTY CARDS (tap for the trend)
  // ==========================================
  Widget _buildDutyGrid(double width) {
    if (_dutyStats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(child: Text("Your role has no duties in this report.", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey)))),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _dutyStats.length,
      padding: const EdgeInsets.only(bottom: 4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: width >= 1300 ? 5 : (width >= 900 ? 4 : (width >= 560 ? 3 : 2)),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 112,
      ),
      itemBuilder: (context, i) {
        final d = _dutyStats[i];
        final c = _changeColor(d.diff);
        // floating card: raised, opens the trend when touched
        return Material(
          color: AppPalette.bg(Colors.white),
          elevation: 5,
          shadowColor: d.color.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openTrend(d),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(d.icon, color: AppPalette.fg(d.color), size: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppPalette.bg(c.withValues(alpha: 0.12)), borderRadius: BorderRadius.circular(6)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(d.diff > 0.05 ? Icons.arrow_upward_rounded : (d.diff < -0.05 ? Icons.arrow_downward_rounded : Icons.remove_rounded), size: 12, color: AppPalette.fg(c)),
                          Text(_changeText(d.diff), style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(c))),
                        ]),
                      ),
                    ],
                  ),
                  Text(d.title, style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[900])), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(d.currentCount == 0 ? "No reports" : "${d.currentRate.toStringAsFixed(1)}%",
                      style: GoogleFonts.merriweather(fontSize: d.currentCount == 0 ? 13 : 17, fontWeight: FontWeight.w900, color: AppPalette.fg(d.currentCount == 0 ? Colors.grey : d.color))),
                  Row(children: [
                    Expanded(child: Text("Previous: ${d.previousRate.toStringAsFixed(1)}%", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.grey[600])))),
                    Icon(Icons.show_chart_rounded, size: 15, color: AppPalette.fg(Colors.grey[500])),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> get _focusJson => [for (final f in _focus) {'col': _levelCols[f.key], 'op': 'eq', 'val': f.value}];

  /// The duty's trend in the report's own area, one point per SESSION as it
  /// is reported (each Wednesday / Sunday service, each week …), this period
  /// and the one before (perf_trend, 18_round17.sql).
  Future<(List<String>, List<double?>, List<double?>)> _trend(DutyStat d) async {
    final r = await _supabase.rpc('perf_trend', params: {
      'p_duty': d.dutyName,
      'p_from': _d(_curStart),
      'p_to': _d(_curEnd),
      'p_prev_from': _d(_prevStart),
      'p_prev_to': _d(_prevEnd),
      'p_include_pending': _includePending,
      'p_focus': _focusJson,
    });
    final rows = List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));
    var cur = rows.where((x) => x['period'] == 'cur').toList();
    var prev = rows.where((x) => x['period'] == 'prev').toList();
    if (cur.length > 16) cur = cur.sublist(cur.length - 16);
    // the sessions before, matched from the end (latest with latest)
    if (prev.length > cur.length) prev = prev.sublist(prev.length - cur.length);
    final labels = [for (final x in cur) x['bucket'].toString()];
    double? v(Map x) => ((x['reports'] as num?) ?? 0) == 0 ? null : (x['rate'] as num?)?.toDouble();
    final a = [for (final x in cur) v(x)];
    final pad = cur.length - prev.length;
    final b = [for (int i = 0; i < pad; i++) null, for (final x in prev) v(x)];
    return (labels, a, b);
  }

  void _openTrend(DutyStat d) {
    final future = _trend(d);
    Navigator.push(context, MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: AppPalette.bg(Colors.white),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(Colors.white),
          elevation: 0.5,
          centerTitle: true,
          title: Text(d.title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18, color: AppPalette.fg(pPurple))),
        ),
        body: SafeArea(
          child: FutureBuilder<(List<String>, List<double?>, List<double?>)>(
            future: future,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text("Couldn't load the trend (run 18_round17.sql): ${snap.error}", textAlign: TextAlign.center)));
              final (labels, a, b) = snap.data!;
              LineChartBarData line(List<double?> v, Color c, {bool dashed = false}) => LineChartBarData(
                    spots: [for (var i = 0; i < v.length; i++) if (v[i] != null) FlSpot(i.toDouble(), v[i]!)],
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: c,
                    barWidth: dashed ? 2 : 3.5,
                    dashArray: dashed ? [6, 4] : null,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: !dashed, color: c.withValues(alpha: 0.10)),
                  );
              final c = _changeColor(d.diff);
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 20, 16),
                child: Column(children: [
                  Text("$_unitKey · $_periodText", textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 12.5, color: AppPalette.fg(Colors.blueGrey.shade700))),
                  const SizedBox(height: 6),
                  Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 4, children: [
                    Text("${d.currentRate.toStringAsFixed(1)}%", style: GoogleFonts.merriweather(fontSize: 22, fontWeight: FontWeight.w900, color: AppPalette.fg(d.color))),
                    Text(_changeText(d.diff), style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.fg(c))),
                    Text("Previous ${d.previousRate.toStringAsFixed(1)}%", style: GoogleFonts.merriweather(fontSize: 13, color: AppPalette.fg(Colors.grey.shade700))),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(alignment: WrapAlignment.center, spacing: 16, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 18, height: 4, color: d.color), const SizedBox(width: 6), const Text("This period (each session)", style: TextStyle(fontSize: 12))]),
                    Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 18, height: 2, color: Colors.grey), const SizedBox(width: 6), Text("Previous ($_prevText)", style: const TextStyle(fontSize: 12))]),
                  ]),
                  const SizedBox(height: 12),
                  Expanded(
                    child: labels.isEmpty || (a.every((x) => x == null) && b.every((x) => x == null))
                        ? Center(child: Text("No reports in this period.", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey))))
                        : LineChart(LineChartData(
                            minY: 0,
                            maxY: 100,
                            minX: 0,
                            maxX: labels.length < 2 ? 1 : (labels.length - 1).toDouble(),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: 20,
                              getDrawingHorizontalLine: (v) => FlLine(color: AppPalette.line(Colors.grey.withValues(alpha: 0.18)), strokeWidth: 1),
                            ),
                            borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: AppPalette.line(Colors.black38)), left: BorderSide(color: AppPalette.line(Colors.black38)))),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, interval: 20, getTitlesWidget: (v, m) => Text("${v.toInt()}%", style: const TextStyle(fontSize: 10)))),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: 1,
                                  reservedSize: 30,
                                  getTitlesWidget: (v, m) {
                                    final i = v.toInt();
                                    if (i < 0 || i >= labels.length || v != i.toDouble()) return const SizedBox();
                                    return Padding(padding: const EdgeInsets.only(top: 6), child: Text(labels[i], style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)));
                                  },
                                ),
                              ),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            lineBarsData: [line(b, Colors.grey, dashed: true), line(a, d.color)],
                          )),
                  ),
                ]),
              );
            },
          ),
        ),
      ),
    ));
  }

  // ==========================================
  // PERFORMANCE COMPARISON
  // ==========================================
  static const _levelTitles = {
    'book_of_life': 'Groups',
    'location': 'Locations',
    'sub_location': 'Sub-locations',
    'department': 'Departments',
    'team': 'Teams',
    'cell_group': 'Cell groups',
  };
  // as the Compilation screen calls them
  static const _statusNames = {
    'book_of_life': 'Group status',
    'location': 'Location status',
    'sub_location': 'Sub-location status',
    'department': 'Dept status',
    'team': 'Team status',
    'cell_group': 'Cell status',
  };
  static const _cmpLevelKey = {
    'book_of_life': 'Group',
    'location': 'Location',
    'sub_location': 'Sub-location',
    'department': 'Dept',
    'team': 'Team',
    'cell_group': 'Cell',
  };

  List<String> _cmpLevels = []; // the levels this viewer may compare at
  String? _cmpPick; // the level picked (null = the viewer's own)
  final List<MapEntry<String, String>> _cmpFocus = []; // units opened in the comparison
  bool _cmpByRank = false; // list order: Compilation order (default) or by rank

  Future<void> _loadComparison() async {
    final duty = _cmpDuty;
    if (duty == null) return;
    final req = ++_cmpReq;
    setState(() {
      _cmpLoading = true;
      _cmpError = null;
    });
    try {
      final focus = [
        ..._focusJson,
        for (final f in _cmpFocus) {'col': f.key, 'op': 'eq', 'val': f.value},
      ];
      final r = await Future.wait<dynamic>([
        _supabase.rpc('perf_compare_v2', params: {
          'p_duty': duty,
          'p_from': _d(_curStart),
          'p_to': _d(_curEnd),
          'p_prev_from': _d(_prevStart),
          'p_prev_to': _d(_prevEnd),
          'p_include_pending': _includePending,
          'p_focus': focus,
          'p_level': _cmpPick,
        }),
        _supabase.rpc('perf_levels', params: {'p_focus': _focusJson}),
      ]);
      if (!mounted || req != _cmpReq) return;
      final byUnit = <String, Map<String, dynamic>>{};
      final buckets = <int, String>{};
      String level = 'location';
      for (final raw in (r[0] as List)) {
        final x = Map<String, dynamic>.from(raw as Map);
        final u = x['unit'].toString();
        level = (x['level'] ?? level).toString();
        buckets[(x['ord'] as num).toInt()] = x['bucket'].toString();
        final row = byUnit.putIfAbsent(u, () => {'unit': u, 'mine': x['is_mine'] == true, 'rates': <String, double?>{}});
        (row['rates'] as Map<String, double?>)[x['bucket'].toString()] = ((x['reports'] as num?) ?? 0) == 0 ? null : (x['rate'] as num?)?.toDouble();
      }
      // rank = by this period's rate
      final ranked = byUnit.values.toList()
        ..sort((a, b) => (((b['rates'] as Map)['This period'] as double?) ?? -1).compareTo((((a['rates'] as Map)['This period'] as double?) ?? -1)));
      for (var i = 0; i < ranked.length; i++) {
        ranked[i]['rank'] = ((ranked[i]['rates'] as Map)['This period']) == null ? null : i + 1;
      }
      setState(() {
        _cmpBuckets = [for (final k in (buckets.keys.toList()..sort())) {'label': buckets[k]!}];
        _cmpRows = ranked;
        _cmpLevel = level;
        _cmpLevels = [for (final x in (r[1] as List? ?? const [])) x.toString()];
        _cmpLoading = false;
      });
    } catch (e) {
      if (!mounted || req != _cmpReq) return;
      setState(() {
        _cmpLoading = false;
        _cmpError = "Couldn't compare: ${e is PostgrestException ? e.message : e}. Ask the admin to run 18_round17.sql.";
      });
    }
  }

  /// The rows in the Compilation screen's unit order, or by rank
  List<Map<String, dynamic>> get _cmpShown {
    if (_cmpByRank) return _cmpRows;
    final order = CompLevel.orderNames(_cmpRows.map((r) => r['unit'].toString()), _cmpLevelKey[_cmpLevel] ?? 'Location');
    return [..._cmpRows]..sort((a, b) => order.indexOf(a['unit'].toString()).compareTo(order.indexOf(b['unit'].toString())));
  }

  void _cmpOpen(Map<String, dynamic> row) {
    const next = {'location': 'sub_location', 'sub_location': 'department', 'department': 'team', 'team': 'cell_group'};
    final n = next[_cmpLevel];
    if (n == null) return; // cells and groups: nothing below
    setState(() {
      _cmpFocus.add(MapEntry(_cmpLevel, row['unit'].toString()));
      _cmpPick = n;
    });
    _loadComparison();
  }

  Widget _buildComparison() {
    final dutyItems = [for (final d in _dutyStats) DropdownMenuItem(value: d.dutyName, child: Text(d.title, overflow: TextOverflow.ellipsis))];
    String r(double? v) => v == null ? '—' : "${v.toStringAsFixed(1)}%";
    Widget pill(Widget child) => Container(
          height: 34,
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF3E5F5)), borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(child: child),
        );
    final ownLevel = _cmpLevels.isEmpty ? null : _cmpLevels.firstWhere((l) => l != 'book_of_life', orElse: () => _cmpLevels.first);
    final atOwn = _cmpFocus.isEmpty && (_cmpPick == null || _cmpPick == ownLevel) && _cmpLevel != 'book_of_life';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      // stands out: raised higher, with a purple edge
      decoration: _raised(strong: true).copyWith(border: Border.all(color: AppPalette.line(pPurple.withValues(alpha: 0.35)), width: 1.4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 6, children: [
          // the Compilation screen's levels: Group / Location / … / Cell status
          if (_cmpLevels.length > 1)
            pill(DropdownButton<String>(
              value: _cmpLevels.contains(_cmpPick ?? _cmpLevel) ? (_cmpPick ?? _cmpLevel) : null,
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)),
              items: [for (final l in _cmpLevels) DropdownMenuItem(value: l, child: Text(_statusNames[l] ?? l))],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _cmpPick = v;
                  _cmpFocus.clear();
                });
                _loadComparison();
              },
            )),
          Text("ranked on", style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[800]))),
          pill(DropdownButton<String>(
            value: _dutyStats.any((d) => d.dutyName == _cmpDuty) ? _cmpDuty : null,
            isDense: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)),
            items: dutyItems,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _cmpDuty = v);
              _loadComparison();
            },
          )),
          FilterChip(
            label: Text(_cmpByRank ? "Sorted by rank" : "Unit order"),
            selected: _cmpByRank,
            onSelected: (v) => setState(() => _cmpByRank = v),
          ),
          // switch between the table and the column chart
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.table_rows_rounded, size: 16), label: Text("Table")),
              ButtonSegment(value: true, icon: Icon(Icons.bar_chart_rounded, size: 16), label: Text("Chart")),
            ],
            selected: {_cmpChart},
            onSelectionChanged: (v) => setState(() => _cmpChart = v.first),
          ),
        ]),
        if (_cmpFocus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
              ActionChip(
                avatar: const Icon(Icons.arrow_upward_rounded, size: 16),
                label: const Text("Back"),
                onPressed: () {
                  setState(() {
                    final last = _cmpFocus.removeLast();
                    _cmpPick = last.key;
                  });
                  _loadComparison();
                },
              ),
              Text(_cmpFocus.map((f) => f.value).join(' › '), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ]),
          ),
        const SizedBox(height: 4),
        Text(
          atOwn
              ? "Your unit against the other ${(_levelTitles[_cmpLevel] ?? 'units').toLowerCase()} of the same level in your parent unit. One column per session as reported."
              : "${_levelTitles[_cmpLevel] ?? 'Units'} inside ${_cmpFocus.isEmpty ? 'your area' : _cmpFocus.last.value}. Tap a unit to open the units inside it.",
          textAlign: TextAlign.center,
          style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700)),
        ),
        const SizedBox(height: 8),
        if (_cmpLoading)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
        else if (_cmpError != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_cmpError!, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.red.shade800))))
        else if (_cmpRows.isEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text("No units to compare.", textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey))))
        else if (_cmpChart)
          _cmpBarChart()
        else
          LayoutBuilder(builder: (context, c) {
            final rows = _cmpShown;
            final canOpen = const {'location', 'sub_location', 'department', 'team'}.contains(_cmpLevel);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: c.maxWidth),
                child: DataTable(
                  headingRowHeight: 38,
                  dataRowMinHeight: 34,
                  dataRowMaxHeight: 40,
                  columnSpacing: 16,
                  horizontalMargin: 8,
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(AppPalette.bg(const Color(0xFFF3E5F5))),
                  columns: [
                    DataColumn(label: Text("Rank", style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)))),
                    DataColumn(label: Text((_levelTitles[_cmpLevel] ?? 'Unit').replaceAll(RegExp(r's$'), ''), style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)))),
                    for (final b in _cmpBuckets)
                      DataColumn(numeric: true, label: Text(b['label']!, style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)))),
                    DataColumn(numeric: true, label: Text("Change", style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)))),
                  ],
                  rows: [
                    for (final row in rows)
                      () {
                        final rates = row['rates'] as Map<String, double?>;
                        final cur = rates['This period'], prev = rates['Previous'];
                        final diff = (cur ?? 0) - (prev ?? 0);
                        final mine = row['mine'] == true;
                        final st = GoogleFonts.merriweather(fontSize: 11.5, fontWeight: mine ? FontWeight.w900 : FontWeight.normal);
                        return DataRow(
                          color: WidgetStateProperty.all(AppPalette.bg(mine ? Colors.amber.withValues(alpha: 0.14) : Colors.transparent)),
                          onSelectChanged: canOpen ? (_) => _cmpOpen(row) : null,
                          cells: [
                            DataCell(Text(row['rank'] == null ? '–' : "#${row['rank']}", style: st.copyWith(fontWeight: FontWeight.bold))),
                            DataCell(Text("${row['unit']}${mine ? '  (you)' : ''}${canOpen ? '  ›' : ''}", style: st.copyWith(fontWeight: FontWeight.bold))),
                            for (final b in _cmpBuckets) DataCell(Text(r(rates[b['label']]), style: st)),
                            DataCell(Text(cur == null || prev == null ? '—' : _changeText(diff), style: st.copyWith(fontWeight: FontWeight.bold, color: AppPalette.fg(_changeColor(diff))))),
                          ],
                        );
                      }(),
                  ],
                ),
              ),
            );
          }),
      ]),
    );
  }

  /// Column chart of the comparison: this period (and the period before) for
  /// each unit, in the same order as the table; tap a column to open the
  /// units inside it.
  Widget _cmpBarChart() {
    final rows = _cmpShown;
    final canOpen = const {'location', 'sub_location', 'department', 'team'}.contains(_cmpLevel);
    double? v(Map r, String k) => (r['rates'] as Map)[k] as double?;
    final width = (rows.length * 64.0).clamp(300.0, 4000.0);
    return Column(children: [
      Wrap(alignment: WrapAlignment.center, spacing: 16, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: pPurple, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 6), const Text("This period", style: TextStyle(fontSize: 12))]),
        Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 6), const Text("Previous", style: TextStyle(fontSize: 12))]),
        Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 6), const Text("Your unit", style: TextStyle(fontSize: 12))]),
      ]),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width < c.maxWidth ? c.maxWidth : width,
              height: 300,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 12, 4),
                child: BarChart(BarChartData(
                  maxY: 100,
                  minY: 0,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 20,
                    getDrawingHorizontalLine: (x) => FlLine(color: AppPalette.line(Colors.grey.withValues(alpha: 0.2)), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: AppPalette.line(Colors.black38)), left: BorderSide(color: AppPalette.line(Colors.black38)))),
                  barTouchData: BarTouchData(
                    touchCallback: (event, resp) {
                      if (!canOpen || event is! FlTapUpEvent || resp?.spot == null) return;
                      final i = resp!.spot!.touchedBarGroupIndex;
                      if (i >= 0 && i < rows.length) _cmpOpen(rows[i]);
                    },
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                        "${rows[g.x]['unit']}\n${ri == 0 ? 'This period' : 'Previous'}: ${rod.toY.toStringAsFixed(1)}%",
                        const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, interval: 20, getTitlesWidget: (x, m) => Text("${x.toInt()}%", style: const TextStyle(fontSize: 10)))),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        getTitlesWidget: (x, m) {
                          final i = x.toInt();
                          if (i < 0 || i >= rows.length) return const SizedBox();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: SizedBox(
                              width: 60,
                              child: Text(rows[i]['unit'].toString(),
                                  textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 9.5, fontWeight: rows[i]['mine'] == true ? FontWeight.w900 : FontWeight.w600)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < rows.length; i++)
                      BarChartGroupData(x: i, barsSpace: 3, barRods: [
                        BarChartRodData(
                          toY: (v(rows[i], 'This period') ?? 0).clamp(0, 100).toDouble(),
                          width: 14,
                          color: rows[i]['mine'] == true ? Colors.amber.shade700 : pPurple,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                        BarChartRodData(
                          toY: (v(rows[i], 'Previous') ?? 0).clamp(0, 100).toDouble(),
                          width: 10,
                          color: Colors.grey.shade400,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ]),
                  ],
                )),
              ),
            ),
          )),
      if (canOpen)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text("Tap a column to open the units inside it.", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
        ),
    ]);
  }

  // ==========================================
  // AI: managerial insights from the leaders' findings
  // ==========================================
  String? _aiText(String key) {
    final v = _ai?[key];
    if (v == null) return null;
    if (v is List) {
      if (v.isEmpty) return null;
      if (key == 'problems') {
        final roots = (_ai?['root_causes'] as List?) ?? const [];
        return [
          for (final x in v) "• $x",
          if (roots.isNotEmpty) "\nRoot causes:",
          for (final x in roots) "• $x",
        ].join('\n');
      }
      return [for (final x in v) "• $x"].join('\n');
    }
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  Future<void> _compileWithAi() async {
    setState(() => _aiBusy = true);
    try {
      final focus = [for (final f in _focus) {'col': _levelCols[f.key], 'op': 'eq', 'val': f.value}];
      final res = await _supabase.functions.invoke('report-insights-ai', body: {
        'from': _d(_curStart),
        'to': _d(_curEnd),
        'focus': focus,
        'unit': _unitKey,
        'numbers': {
          'members': totalSaints,
          'workers': totalWorkers,
          'new_members': newConverts,
          'new_members_previous': newConvertsPrev,
          'dropouts': dropouts,
          'recoveries': successfulRecoveries,
          'transfers_in': transfersIn,
          'transfers_out': transfersOut,
          'duties': [
            for (final d in _dutyStats) {'duty': d.title, 'rate': d.currentRate, 'previous_rate': d.previousRate, 'reports': d.currentCount},
          ],
          'comparison': [
            for (final r in _cmpRows.take(30)) {'unit': r['unit'], 'mine': r['mine'], 'rates': r['rates']},
          ],
        },
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      if (data['error'] != null) throw data['error'];
      if (mounted) setState(() => _ai = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text("AI summary isn't available: ${e is FunctionException ? (e.details ?? e.reasonPhrase ?? e.status) : e}. "
              "The administrator deploys the report-insights-ai function."),
        ));
      }
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Widget _build14PointCard(int point, String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: _raised(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 11, backgroundColor: AppPalette.bg(pPurple.withValues(alpha: 0.1)), child: Text("$point", style: TextStyle(color: AppPalette.fg(pPurple), fontSize: 12, fontWeight: FontWeight.bold))),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[900])))),
            ],
          ),
          const Divider(height: 14),
          Text(content, style: GoogleFonts.merriweather(fontSize: 13, color: AppPalette.fg(Colors.black87), height: 1.4)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 2),
        child: Text(title, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.blueGrey[900]))),
      );
}
