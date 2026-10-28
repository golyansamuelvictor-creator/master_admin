// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:typed_data';
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/table_export.dart';
import '../../core/app_sizes.dart';
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

/// Monthly executive report: every duty of the role compiled into one report
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
      netGrowth = newConverts - dropouts;

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

      if (mounted && req == _req) setState(() => _isLoading = false);
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
      if (missingUnits.isNotEmpty) "Follow up the units that have not reported (see the accountability table).",
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
    final obs = TextEditingController(text: _insight('observation', _autoSummary));
    final root = TextEditingController(text: _insight('root_cause', _autoProblems));
    final act = TextEditingController(text: _insight('recommended_action', _autoActions));
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
      setState(() => _managerInsights = {..._managerInsights, ...row});
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
        title: "Executive report – $_unitKey",
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
    final doc = pw.Document(theme: theme, title: 'Executive report');
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
        pw.Text("EXECUTIVE PERFORMANCE REPORT", style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
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
          "Executive performance report",
          style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple), fontSize: 16),
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
                const SizedBox(height: 12),

                // KPI Grid
                _buildKPIGrid(width),
                const SizedBox(height: 14),

                // Operational duties performance
                _sectionTitle("Operational duties performance and trends"),
                const SizedBox(height: 8),
                _buildDutyGrid(width),
                const SizedBox(height: 12),
                _buildDutyTable(),
                const SizedBox(height: 14),

                // Accountability drilldown
                _sectionTitle("Reporting compliance and unit accountability"),
                const SizedBox(height: 8),
                _buildAccountabilityDrilldownCard(),
                const SizedBox(height: 14),

                // Managerial insights
                Row(children: [
                  Expanded(child: _sectionTitle("Managerial insights and recommendations")),
                  TextButton.icon(onPressed: _editInsights, icon: const Icon(Icons.edit_note_rounded, size: 18), label: const Text("Write findings")),
                ]),
                const SizedBox(height: 6),
                _build14PointCard(1, "Executive summary", _insight('observation', _autoSummary)),
                _build14PointCard(11, "Problem areas and root causes", _insight('root_cause', _autoProblems)),
                _build14PointCard(13, "Recommended leadership actions", _insight('recommended_action', _autoActions)),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.18))),
      ),
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
        boxShadow: [BoxShadow(color: pPurple.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))],
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
              _metricCol("Previous period", "+$newConvertsPrev", Colors.white70),
              _metricCol("Dropouts", "-$dropouts", Colors.redAccent),
              _metricCol("Recoveries", "$successfulRecoveries", Colors.amberAccent),
              _metricCol("Service attendance", "${churchAvgAttendance.toStringAsFixed(1)}%", Colors.white),
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

  Widget _buildKPIGrid(double width) {
    final cards = [
      _kpiCard("Units that sent every duty", "${attendanceCompliance.toStringAsFixed(1)}%", Icons.assignment_turned_in, Colors.blue[800]!),
      _kpiCard("Service attendance", "${churchAvgAttendance.toStringAsFixed(1)}%", Icons.people_alt, Colors.green[800]!),
      _kpiCard("Average of all duties", "${overallRate.toStringAsFixed(1)}%", Icons.insights_rounded, Colors.purple[800]!),
      _kpiCard("Recovery results", "$successfulRecoveries recovered", Icons.refresh, Colors.orange[800]!),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: width >= 900 ? 4 : 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: width >= 900 ? 4.2 : 2.7,
      children: cards,
    );
  }

  Widget _kpiCard(String t, String v, IconData i, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.16))),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4)],
        ),
        child: Row(
          children: [
            Icon(i, color: AppPalette.fg(c), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(v, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.w900, color: AppPalette.fg(c)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(t, style: GoogleFonts.merriweather(fontSize: 11.5, color: AppPalette.fg(Colors.grey[700]), fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      );

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
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: width >= 1300 ? 5 : (width >= 900 ? 4 : (width >= 560 ? 3 : 2)),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 112,
      ),
      itemBuilder: (context, i) {
        final d = _dutyStats[i];
        bool up = d.isPositive;
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppPalette.bg(Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.16))),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4)],
          ),
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
                    decoration: BoxDecoration(color: AppPalette.bg(up ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1)), borderRadius: BorderRadius.circular(6)),
                    child: Text("${up ? '+' : ''}${d.diff.toStringAsFixed(1)}%", style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(up ? Colors.green[800] : Colors.red[800]))),
                  ),
                ],
              ),
              Text(d.title, style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[900])), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(d.currentCount == 0 ? "No reports" : "${d.currentRate.toStringAsFixed(1)}%",
                  style: GoogleFonts.merriweather(fontSize: d.currentCount == 0 ? 13 : 17, fontWeight: FontWeight.w900, color: AppPalette.fg(d.currentCount == 0 ? Colors.grey : d.color))),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text("Prior: ${d.previousRate.toStringAsFixed(1)}%", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.grey[600])))),
                  Flexible(child: Text("${d.currentCount} logs", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.grey[600]), fontWeight: FontWeight.bold))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// The compiled table of all duties (what the PDF and Excel contain).
  Widget _buildDutyTable() {
    final t = _dutyTable();
    return _tableCard(
      title: "Compiled duties · $_periodText",
      headers: t.headers,
      rows: t.rows,
      footnote: "Rate = reports marked done ÷ (sessions × ${_dutyStats.any((d) => d.forWorkers) ? 'members, or workers for worker duties' : 'members'}). "
          "Previous period: $_prevText.",
    );
  }

  Widget _tableCard({required String title, required List<String> headers, required List<List<String>> rows, String? footnote, void Function(int row)? onRowTap}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.2))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[800]))),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: c.maxWidth),
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 36,
                columnSpacing: 18,
                horizontalMargin: 8,
                headingRowColor: WidgetStateProperty.all(AppPalette.bg(const Color(0xFFF3E5F5))),
                showCheckboxColumn: false,
                columns: [
                  for (int i = 0; i < headers.length; i++)
                    DataColumn(
                      numeric: i > 0,
                      label: Text(headers[i], style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple))),
                    ),
                ],
                rows: [
                  for (int r = 0; r < rows.length; r++)
                    DataRow(
                      onSelectChanged: onRowTap == null ? null : (_) => onRowTap(r),
                      cells: [
                        for (int i = 0; i < headers.length; i++)
                          DataCell(Text(
                            i < rows[r].length ? rows[r][i] : '',
                            style: GoogleFonts.merriweather(
                              fontSize: 11.5,
                              fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal,
                              color: AppPalette.fg(i > 0 && (i < rows[r].length && rows[r][i] == '—') ? Colors.red.shade700 : Colors.black87),
                            ),
                          )),
                      ],
                    ),
                ],
              ),
            ),
          );
        }),
        if (footnote != null) ...[
          const SizedBox(height: 6),
          Text(footnote, style: GoogleFonts.merriweather(fontSize: 10, fontStyle: FontStyle.italic, color: AppPalette.fg(Colors.black54))),
        ],
      ]),
    );
  }

  Widget _buildAccountabilityDrilldownCard() {
    final t = _unitTable();
    final nextLevel = _drillLevels.indexOf(_drilldownLevel) + 1 < _drillLevels.length ? _drillLevels[_drillLevels.indexOf(_drilldownLevel) + 1] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.2))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              Text("Show units by:", style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[800]))),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF3E5F5)), borderRadius: BorderRadius.circular(6)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _drillLevels.contains(_drilldownLevel) ? _drilldownLevel : _drillLevels.first,
                    isDense: true,
                    style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)),
                    items: _drillLevels
                        .where((l) => !_focus.any((f) => f.key == l))
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _drilldownLevel = v);
                        _loadReportData();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          Text(
            _units.isEmpty
                ? "No $_drilldownLevel units with members in your area."
                : missingUnits.isEmpty
                    ? "All ${_units.length} $_drilldownLevel units submitted their duties successfully."
                    : "${missingUnits.length} of ${_units.length} $_drilldownLevel units are missing a duty report:",
            style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.fg(missingUnits.isEmpty ? Colors.green[800] : Colors.red[900])),
          ),
          if (missingUnits.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: missingUnits.length,
                itemBuilder: (c, i) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppPalette.bg(Colors.red.withValues(alpha: 0.04)), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppPalette.line(Colors.red.withValues(alpha: 0.15)))),
                  child: Text(missingUnits[i], style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.red[900]))),
                ),
              ),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      if (_units.isNotEmpty)
        _tableCard(
          title: "Each $_drilldownLevel by duty${nextLevel == null ? '' : ' · tap a row to open it'}",
          headers: t.headers,
          rows: t.rows,
          footnote: "— = no report this period.",
          onRowTap: nextLevel == null
              ? null
              : (r) {
                  final unit = _units[r]['unit'].toString();
                  if (unit == '(not set)') return;
                  setState(() {
                    _focus.add(MapEntry(_drilldownLevel, unit));
                    _drilldownLevel = nextLevel;
                  });
                  _loadReportData();
                },
        ),
    ]);
  }

  Widget _build14PointCard(int point, String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.16))),
      ),
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
