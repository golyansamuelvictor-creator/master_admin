import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/compilation_rules.dart';
import '../core/i18n.dart';
import '../core/table_export.dart';

const Color _kPurple = Color(0xFF4A148C);
final _f = DateFormat('yyyy-MM-dd');

/// All Saints Mobilised In-Person Service (ASMIS): a Sunday when all the
/// locations gather in one place (special_services, 21_round20.sql).
class Asmis {
  Asmis._();

  /// The ASMIS day whose pre-attendance check is open on [day] (from the
  /// check's first day up to the service itself), if any.
  static Future<Map<String, dynamic>?> openOn(DateTime day) async {
    try {
      final d = _f.format(day);
      final rows = await Supabase.instance.client
          .from('special_services')
          .select()
          .eq('kind', 'asmis')
          .gte('service_date', d)
          .order('service_date')
          .limit(3);
      for (final r in rows) {
        final s = DateTime.tryParse(r['service_date'].toString());
        if (s == null) continue;
        final from = DateTime.tryParse((r['pre_from'] ?? '').toString()) ?? s.subtract(const Duration(days: 14));
        if (!day.isBefore(from) && !day.isAfter(s)) return Map<String, dynamic>.from(r);
      }
    } catch (_) {}
    return null;
  }

  static String label(Map s) => "${s['name'] ?? 'All Saints Mobilised In-Person Service'} · ${DateFormat('EEE d MMM yyyy').format(DateTime.parse(s['service_date'].toString()))}";
}

/// Entry form › ASMIS pre-attendance: the same members as the Service
/// Attendance form and the same answers as its pre-attendance, saved for the
/// ASMIS day with the date of the check (the latest check counts).
class AsmisPreAttendanceScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  final DateTime checkDate;
  final List<dynamic> members;
  final List<String> options;
  const AsmisPreAttendanceScreen({super.key, required this.service, required this.checkDate, required this.members, required this.options});
  @override
  State<AsmisPreAttendanceScreen> createState() => _AsmisPreAttendanceScreenState();
}

class _AsmisPreAttendanceScreenState extends State<AsmisPreAttendanceScreen> {
  final _db = Supabase.instance.client;
  final Map<String, String?> _answer = {}; // member → this check's answer
  final Map<String, String> _latest = {}; // member → latest earlier answer
  bool _loading = true, _saving = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ids = [for (final m in widget.members) m['id']];
      for (int i = 0; i < ids.length; i += 150) {
        final rows = await _db
            .from('asmis_pre_attendance')
            .select('member_id, status, check_date')
            .eq('service_id', widget.service['id'])
            .inFilter('member_id', ids.sublist(i, (i + 150).clamp(0, ids.length)))
            .order('check_date', ascending: false);
        for (final r in rows) {
          final id = r['member_id'].toString();
          final s = (r['status'] ?? '').toString();
          if (r['check_date'].toString().startsWith(_f.format(widget.checkDate))) {
            _answer[id] = s;
          } else {
            _latest.putIfAbsent(id, () => s);
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final rows = [
      for (final e in _answer.entries)
        if ((e.value ?? '').isNotEmpty)
          {'service_id': widget.service['id'], 'member_id': e.key, 'check_date': _f.format(widget.checkDate), 'status': e.value, 'updated_at': DateTime.now().toUtc().toIso8601String()},
    ];
    try {
      for (int i = 0; i < rows.length; i += 200) {
        await _db.from('asmis_pre_attendance').upsert(rows.sublist(i, (i + 200).clamp(0, rows.length)), onConflict: 'service_id,member_id,check_date');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("ASMIS pre-attendance saved (${rows.length})"), backgroundColor: Colors.green.shade700));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save (run 21_round20.sql): ${e is PostgrestException ? e.message : e}")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = widget.members.where((m) => q.isEmpty || '${m['english_name']} ${m['cell_group']} ${m['team']}'.toLowerCase().contains(q)).toList();
    final answered = _answer.values.where((v) => (v ?? '').isNotEmpty).length;
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
      appBar: AppBar(
        centerTitle: true,
        title: Text("ASMIS pre-attendance", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple))),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded, size: 18),
              label: const Text("Save"),
            ),
          ),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFEDE3F8)), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(Asmis.label(widget.service), textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(_kPurple))),
            if ((widget.service['venue'] ?? '').toString().isNotEmpty) Text("Venue: ${widget.service['venue']}", style: const TextStyle(fontSize: 12)),
            Text("Check of ${DateFormat('EEE d MMM').format(widget.checkDate)} · $answered of ${widget.members.length} answered · the latest check counts",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.blueGrey.shade700))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: tr("Search name, team or cell"), isDense: true, border: const OutlineInputBorder()),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 40),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final m = list[i];
                    final id = m['id'].toString();
                    final v = _answer[id];
                    final prev = _latest[id];
                    return Card(
                      elevation: 0.4,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text((m['english_name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              Text(
                                [m['team'], m['cell_group'], if (prev != null && prev.isNotEmpty) 'last check: $prev'].where((x) => (x ?? '').toString().isNotEmpty).join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700)),
                              ),
                            ]),
                          ),
                          SizedBox(
                            width: 150,
                            child: DropdownButton<String>(
                              value: widget.options.contains(v) ? v : null,
                              isExpanded: true,
                              hint: Text(prev ?? "—", style: const TextStyle(fontSize: 12)),
                              items: [for (final o in widget.options) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))],
                              onChanged: (x) => setState(() => _answer[id] = x),
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// The results of the ASMIS days per unit (pre-attendance vs real-time
/// attendance) and the days compared over time. Opened from the ASMIS
/// schedule (Service Attendance › Policies, standards & goals › ASMIS).
class AsmisScreen extends StatefulWidget {
  final String? initialService;
  const AsmisScreen({super.key, this.initialService});
  @override
  State<AsmisScreen> createState() => _AsmisScreenState();
}

class _AsmisScreenState extends State<AsmisScreen> {
  final _db = Supabase.instance.client;
  static const _levels = ['location', 'sub_location', 'department', 'team', 'cell_group'];
  static const _levelNames = ['Locations', 'Sub-locations', 'Departments', 'Teams', 'Cell groups'];
  static const _orderKeys = ['Location', 'Sub-location', 'Dept', 'Team', 'Cell'];
  int _level = 0;
  List<Map<String, dynamic>> _rows = [];
  String? _service;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.initialService;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _db.rpc('asmis_summary', params: {'p_level': _levels[_level]});
      final rows = List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        final ids = rows.map((e) => e['service_id'].toString()).toSet();
        if (_service == null || !ids.contains(_service)) _service = rows.isEmpty ? null : rows.first['service_id'].toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load (run 21_round20.sql): ${e is PostgrestException ? e.message : e}";
      });
    }
  }

  /// the ASMIS days, newest first: (id, date, name, venue)
  List<Map<String, dynamic>> get _days {
    final seen = <String>{};
    return [
      for (final r in _rows)
        if (seen.add(r['service_id'].toString())) r,
    ];
  }

  int _n(dynamic v) => (v as num?)?.toInt() ?? 0;
  String _pct(int a, int b) => b == 0 ? '–' : '${(a * 100 / b).toStringAsFixed(1)}%';

  ExportTable _table(List<Map<String, dynamic>> rows, Map<String, dynamic>? day) => ExportTable(
        title: "ASMIS – ${day == null ? '' : Asmis.label(day)}",
        subtitle: _levelNames[_level],
        headers: const ['Unit', 'Members', 'Pre: answered', 'Pre: coming', 'Pre %', 'Attended', 'Attendance %', 'In person'],
        rows: [
          for (final r in rows)
            [
              r['unit'].toString(),
              '${_n(r['members'])}',
              '${_n(r['pre_answered'])}',
              '${_n(r['pre_coming'])}',
              _pct(_n(r['pre_coming']), _n(r['members'])),
              '${_n(r['attended'])}',
              _pct(_n(r['attended']), _n(r['members'])),
              '${_n(r['inperson'])}',
            ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final day = days.where((d) => d['service_id'].toString() == _service).firstOrNull;
    var rows = _rows.where((r) => r['service_id'].toString() == _service && r['unit'] != '(not set)').toList();
    final order = CompLevel.orderNames(rows.map((r) => r['unit'].toString()), _orderKeys[_level]);
    rows.sort((a, b) => order.indexOf(a['unit'].toString()).compareTo(order.indexOf(b['unit'].toString())));
    final total = {
      for (final k in ['members', 'pre_answered', 'pre_coming', 'attended', 'inperson']) k: rows.fold<int>(0, (a, r) => a + _n(r[k])),
    };
    // over time: each day's totals, oldest first
    final hist = [
      for (final d in days.reversed)
        () {
          final rs = _rows.where((r) => r['service_id'] == d['service_id']);
          final m = rs.fold<int>(0, (a, r) => a + _n(r['members']));
          return (
            DateFormat('d MMM yy').format(DateTime.parse(d['service_date'].toString())),
            m == 0 ? 0.0 : 100.0 * rs.fold<int>(0, (a, r) => a + _n(r['pre_coming'])) / m,
            m == 0 ? 0.0 : 100.0 * rs.fold<int>(0, (a, r) => a + _n(r['attended'])) / m,
          );
        }(),
    ];
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
      appBar: AppBar(
        centerTitle: true,
        title: Text("ASMIS results", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple))),
        actions: [IconButton(tooltip: tr("Reload"), icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
              : days.isEmpty
                  ? const Center(child: Text("No ASMIS day has been set yet.", textAlign: TextAlign.center))
                  : ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 90), children: [
                      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
                        DropdownButton<String>(
                          value: _service,
                          items: [for (final d in days) DropdownMenuItem(value: d['service_id'].toString(), child: Text(Asmis.label(d), overflow: TextOverflow.ellipsis))],
                          onChanged: (v) => setState(() => _service = v),
                        ),
                        DropdownButton<int>(
                          value: _level,
                          items: [for (int i = 0; i < _levelNames.length; i++) DropdownMenuItem(value: i, child: Text(_levelNames[i]))],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _level = v);
                            _load();
                          },
                        ),
                        IconButton(tooltip: tr('Excel / PDF / Print'), icon: Icon(Icons.download_rounded, color: AppPalette.fg(_kPurple)), onPressed: () => TableExport.showMenu(context, () => _table(rows, day))),
                      ]),
                      if (day != null && (day['venue'] ?? '').toString().isNotEmpty)
                        Text("Venue: ${day['venue']}", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.blueGrey.shade700))),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          border: TableBorder.all(color: AppPalette.line(Colors.grey.shade300), width: 0.8),
                          headingRowColor: WidgetStateProperty.all(AppPalette.bg(const Color(0xFFF3E5F5))),
                          headingRowHeight: 40,
                          dataRowMinHeight: 30,
                          dataRowMaxHeight: 34,
                          columnSpacing: 18,
                          columns: const [
                            DataColumn(label: Text("Unit")),
                            DataColumn(numeric: true, label: Text("Members")),
                            DataColumn(numeric: true, label: Text("Pre: answered")),
                            DataColumn(numeric: true, label: Text("Pre: coming")),
                            DataColumn(numeric: true, label: Text("Pre %")),
                            DataColumn(numeric: true, label: Text("Attended")),
                            DataColumn(numeric: true, label: Text("Attendance %")),
                            DataColumn(numeric: true, label: Text("In person")),
                          ],
                          rows: [
                            DataRow(
                              color: WidgetStateProperty.all(AppPalette.bg(const Color(0xFFFFF8E1))),
                              cells: [
                                const DataCell(Text("General total", style: TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text('${total['members']}')),
                                DataCell(Text('${total['pre_answered']}')),
                                DataCell(Text('${total['pre_coming']}')),
                                DataCell(Text(_pct(total['pre_coming']!, total['members']!))),
                                DataCell(Text('${total['attended']}')),
                                DataCell(Text(_pct(total['attended']!, total['members']!), style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text('${total['inperson']}')),
                              ],
                            ),
                            for (final r in rows)
                              DataRow(cells: [
                                DataCell(Text(r['unit'].toString(), style: const TextStyle(fontWeight: FontWeight.w600))),
                                DataCell(Text('${_n(r['members'])}')),
                                DataCell(Text('${_n(r['pre_answered'])}')),
                                DataCell(Text('${_n(r['pre_coming'])}')),
                                DataCell(Text(_pct(_n(r['pre_coming']), _n(r['members'])))),
                                DataCell(Text('${_n(r['attended'])}')),
                                DataCell(Text(_pct(_n(r['attended']), _n(r['members'])))),
                                DataCell(Text('${_n(r['inperson'])}')),
                              ]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text("Over time: pre-attendance (coming) and attendance, % of members",
                          textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(_kPurple))),
                      const SizedBox(height: 8),
                      LayoutBuilder(builder: (context, box) {
                        final w = (hist.length * 90.0).clamp(box.maxWidth, 4000.0);
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: w,
                            height: 260,
                            child: BarChart(BarChartData(
                              maxY: 100,
                              minY: 0,
                              alignment: BarChartAlignment.spaceAround,
                              gridData: const FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 20),
                              borderData: FlBorderData(show: false),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 34, interval: 20, getTitlesWidget: (x, m) => Text("${x.toInt()}%", style: const TextStyle(fontSize: 10)))),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 26,
                                    getTitlesWidget: (x, m) {
                                      final i = x.toInt();
                                      if (i < 0 || i >= hist.length) return const SizedBox();
                                      return SideTitleWidget(meta: m, child: Text(hist[i].$1, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600)));
                                    },
                                  ),
                                ),
                              ),
                              barGroups: [
                                for (int i = 0; i < hist.length; i++)
                                  BarChartGroupData(x: i, barsSpace: 4, barRods: [
                                    BarChartRodData(toY: hist[i].$2.clamp(0, 100).toDouble(), width: 14, color: Colors.blueGrey.shade300),
                                    BarChartRodData(toY: hist[i].$3.clamp(0, 100).toDouble(), width: 14, color: _kPurple),
                                  ]),
                              ],
                            )),
                          ),
                        );
                      }),
                      Wrap(alignment: WrapAlignment.center, spacing: 14, children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 12, height: 12, color: Colors.blueGrey.shade300), const SizedBox(width: 5), const Text("Pre-attendance: coming", style: TextStyle(fontSize: 11))]),
                        Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 12, height: 12, color: _kPurple), const SizedBox(width: 5), const Text("Attended (real time)", style: TextStyle(fontSize: 11))]),
                      ]),
                    ]),
    );
  }
}

/// Service Attendance › Policies, standards & goals › ASMIS: the schedule of
/// All Saints Mobilised In-Person Services for every leader — theme, date,
/// time, venue, subjects, what to prepare and notes. Coming services first;
/// once a service has passed it moves to History (searchable by date or
/// keyword). Internal Affairs ("Manage ASMIS") adds and edits them.
class AsmisScheduleView extends StatefulWidget {
  const AsmisScheduleView({super.key});
  @override
  State<AsmisScheduleView> createState() => _AsmisScheduleViewState();
}

class _AsmisScheduleViewState extends State<AsmisScheduleView> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true, _canManage = false, _history = false;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _db.rpc('has_admin_action', params: {'p_action': 'Manage ASMIS'}).then((r) {
      if (mounted) setState(() => _canManage = r == true);
    }).catchError((_) {});
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db.from('special_services').select().eq('kind', 'asmis').order('service_date', ascending: false);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(r);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load the ASMIS schedule (run 22_round21.sql): ${e is PostgrestException ? e.message : e}";
      });
    }
  }

  static List<String> _lines(dynamic v) => (v ?? '').toString().split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _edit([Map<String, dynamic>? d]) async {
    DateTime date = d == null ? DateTime.now() : DateTime.parse(d['service_date'].toString());
    if (d == null) date = date.add(Duration(days: (7 - date.weekday) % 7)); // the coming Sunday
    DateTime pre = d?['pre_from'] != null ? DateTime.parse(d!['pre_from'].toString()) : date.subtract(const Duration(days: 14));
    final c = {
      for (final k in ['name', 'theme', 'service_time', 'venue', 'subjects', 'preparation', 'notes'])
        k: TextEditingController(text: (d?[k] ?? (k == 'name' ? 'All Saints Mobilised In-Person Service' : '')).toString()),
    };
    InputDecoration deco(String l, {String? hint}) => InputDecoration(labelText: tr(l), hintText: hint == null ? null : tr(hint), border: const OutlineInputBorder(), isDense: true, alignLabelWithHint: true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(d == null ? "New ASMIS" : "Edit ASMIS"),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: c['name'], decoration: deco("Name")),
                const SizedBox(height: 10),
                TextField(controller: c['theme'], decoration: deco("Theme")),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.event_rounded),
                  title: Text("Date: ${DateFormat('EEE d MMM yyyy').format(date)}"),
                  onTap: () async {
                    final x = await showDatePicker(context: ctx, firstDate: DateTime(2023), lastDate: DateTime(2035), initialDate: date);
                    if (x != null) {
                      set(() {
                        // the check window moves with the date
                        if (pre == date.subtract(const Duration(days: 14))) pre = x.subtract(const Duration(days: 14));
                        date = x;
                      });
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text("Pre-attendance check from: ${DateFormat('EEE d MMM').format(pre)}"),
                  subtitle: const Text("Leaders check who is coming from this day (2 weeks before by default)"),
                  onTap: () async {
                    final x = await showDatePicker(context: ctx, firstDate: DateTime(2023), lastDate: date, initialDate: pre.isAfter(date) ? date : pre);
                    if (x != null) set(() => pre = x);
                  },
                ),
                Row(children: [
                  Expanded(child: TextField(controller: c['service_time'], decoration: deco("Time", hint: "e.g. 9:00 AM"))),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: TextField(controller: c['venue'], decoration: deco("Venue"))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: c['subjects'], minLines: 2, maxLines: 6, decoration: deco("Subjects", hint: "One per line")),
                const SizedBox(height: 10),
                TextField(controller: c['preparation'], minLines: 2, maxLines: 6, decoration: deco("What to prepare", hint: "One per line")),
                const SizedBox(height: 10),
                TextField(controller: c['notes'], minLines: 2, maxLines: 6, decoration: deco("Notes")),
              ]),
            ),
          ),
          actions: [
            if (d != null)
              TextButton(
                onPressed: () async {
                  try {
                    await _db.from('special_services').delete().eq('id', d['id']);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("Couldn't remove: ${e is PostgrestException ? e.message : e}")));
                  }
                },
                child: Text("Remove", style: TextStyle(color: AppPalette.fg(Colors.red.shade700))),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            FilledButton(
              onPressed: () async {
                final row = <String, dynamic>{
                  'kind': 'asmis',
                  'service_date': _f.format(date),
                  'pre_from': _f.format(pre),
                  for (final e in c.entries) e.key: e.value.text.trim(),
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                };
                try {
                  if (d == null) {
                    await _db.from('special_services').insert(row);
                  } else {
                    await _db.from('special_services').update(row).eq('id', d['id']);
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("Couldn't save: ${e is PostgrestException ? e.message : e}")));
                }
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _load();
  }

  Widget _card(Map<String, dynamic> d, {required bool upcoming}) {
    final date = DateTime.parse(d['service_date'].toString());
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final pre = DateTime.tryParse((d['pre_from'] ?? '').toString()) ?? date.subtract(const Duration(days: 14));
    final daysLeft = date.difference(today).inDays;
    final open = !today.isBefore(pre) && !today.isAfter(date);
    final subjects = _lines(d['subjects']);
    final prep = _lines(d['preparation']);
    Widget label(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 3),
          child: Row(children: [
            Icon(i, size: 15, color: AppPalette.fg(_kPurple)),
            const SizedBox(width: 6),
            Text(t, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12, color: AppPalette.fg(_kPurple))),
          ]),
        );
    final details = <Widget>[
      if (subjects.isNotEmpty) ...[
        label(Icons.menu_book_rounded, "Subjects"),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final x in subjects)
            Chip(visualDensity: VisualDensity.compact, label: Text(x, style: const TextStyle(fontSize: 11.5)), backgroundColor: AppPalette.bg(const Color(0xFFF3ECFB))),
        ]),
      ],
      if (prep.isNotEmpty) ...[
        label(Icons.checklist_rounded, "What to prepare"),
        for (final x in prep)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("•  ", style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(child: Text(x, style: GoogleFonts.merriweather(fontSize: 12))),
            ]),
          ),
      ],
      if ((d['notes'] ?? '').toString().trim().isNotEmpty) ...[
        label(Icons.sticky_note_2_outlined, "Notes"),
        SelectableText(d['notes'].toString(), style: GoogleFonts.merriweather(fontSize: 12, height: 1.4)),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: [
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AsmisScreen(initialService: d['id'].toString()))),
          icon: const Icon(Icons.bar_chart_rounded, size: 18),
          label: const Text("Results"),
        ),
        if (_canManage)
          TextButton.icon(onPressed: () => _edit(d), icon: const Icon(Icons.edit_rounded, size: 18), label: const Text("Edit")),
      ]),
    ];
    final head = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // the date badge
      Container(
        width: 58,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: upcoming ? AppPalette.solid(_kPurple) : AppPalette.bg(Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text(DateFormat('MMM').format(date).toUpperCase(), style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: FontWeight.bold, color: upcoming ? Colors.white70 : AppPalette.fg(Colors.grey.shade700))),
          Text("${date.day}", style: GoogleFonts.merriweather(fontSize: 22, fontWeight: FontWeight.w900, color: upcoming ? Colors.white : AppPalette.fg(Colors.grey.shade800))),
          Text(DateFormat('EEE yyyy').format(date), style: GoogleFonts.merriweather(fontSize: 9, color: upcoming ? Colors.white70 : AppPalette.fg(Colors.grey.shade700))),
        ]),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((d['name'] ?? 'All Saints Mobilised In-Person Service').toString(), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13.5)),
          if ((d['theme'] ?? '').toString().trim().isNotEmpty)
            Text("Theme: ${d['theme']}", style: GoogleFonts.merriweather(fontSize: 12.5, fontStyle: FontStyle.italic, color: AppPalette.fg(_kPurple))),
          const SizedBox(height: 3),
          Wrap(spacing: 10, runSpacing: 2, children: [
            if ((d['service_time'] ?? '').toString().trim().isNotEmpty) _info(Icons.schedule_rounded, d['service_time'].toString()),
            if ((d['venue'] ?? '').toString().trim().isNotEmpty) _info(Icons.place_rounded, d['venue'].toString()),
            if (upcoming) _info(Icons.fact_check_outlined, open ? "Pre-attendance open" : "Pre-attendance from ${DateFormat('d MMM').format(pre)}"),
          ]),
        ]),
      ),
      if (upcoming)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppPalette.bg(daysLeft <= 7 ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9)), borderRadius: BorderRadius.circular(10)),
          child: Text(daysLeft == 0 ? "Today" : (daysLeft == 1 ? "Tomorrow" : "in $daysLeft days"),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(daysLeft <= 7 ? Colors.orange.shade900 : Colors.green.shade800))),
        ),
    ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(const Color(0xFFE4DAF2))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      clipBehavior: Clip.antiAlias,
      child: upcoming
          ? Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, ...details]))
          : Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                title: head,
                childrenPadding: const EdgeInsets.fromLTRB(82, 0, 12, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: details,
              ),
            ),
    );
  }

  Widget _info(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 13, color: AppPalette.fg(Colors.blueGrey.shade600)),
        const SizedBox(width: 3),
        Text(t, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.blueGrey.shade700))),
      ]);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    bool past(Map d) => DateTime.parse(d['service_date'].toString()).isBefore(today);
    final q = _q.trim().toLowerCase();
    bool hit(Map d) {
      if (q.isEmpty) return true;
      final date = DateTime.parse(d['service_date'].toString());
      final text = [
        d['name'], d['theme'], d['venue'], d['subjects'], d['preparation'], d['notes'], d['service_time'],
        d['service_date'], DateFormat('d MMM yyyy').format(date), DateFormat('MMMM yyyy').format(date), DateFormat('EEEE').format(date),
      ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
      return q.split(RegExp(r'\s+')).every(text.contains);
    }
    final upcoming = _rows.where((d) => !past(d) && hit(d)).toList()
      ..sort((a, b) => a['service_date'].toString().compareTo(b['service_date'].toString()));
    final history = _rows.where((d) => past(d) && hit(d)).toList(); // newest first
    final list = _history ? history : upcoming;
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(color: AppPalette.bg(Colors.white), border: Border(bottom: BorderSide(color: AppPalette.line(Colors.black12)))),
        child: Row(children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: tr("Search theme, venue, date …"),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: false, label: Text("Coming (${upcoming.length})")),
              ButtonSegment(value: true, label: Text("History (${history.length})")),
            ],
            selected: {_history},
            onSelectionChanged: (v) => setState(() => _history = v.first),
          ),
          if (_canManage) ...[
            const SizedBox(width: 4),
            IconButton.filled(
              tooltip: tr("New ASMIS"),
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(backgroundColor: AppPalette.solid(_kPurple), foregroundColor: Colors.white),
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded, size: 18),
            ),
          ],
        ]),
      ),
      Expanded(
        child: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
            : RefreshIndicator(
                onRefresh: _load,
                child: list.isEmpty
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Text(
                            q.isNotEmpty
                                ? "Nothing matches \"$_q\"."
                                : (_history ? "No past ASMIS yet." : (_canManage ? "No coming ASMIS. Tap + to add one." : "No coming ASMIS has been announced yet.")),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey.shade600)),
                          ),
                        ),
                      ])
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 40),
                        children: [for (final d in list) _card(d, upcoming: !_history)],
                      ),
              ),
      ),
    ]);
  }
}
