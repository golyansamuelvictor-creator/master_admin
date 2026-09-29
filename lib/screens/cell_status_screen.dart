// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // FIXED: Corrected import
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math; 
import 'entry_form_screen.dart';

class CellStatusScreen extends StatefulWidget {
  final String sheetName, cellName, initialMode, location, subLocation, dept, team;
  const CellStatusScreen({super.key, required this.sheetName, required this.cellName, required this.location, required this.subLocation, required this.dept, required this.team, required this.initialMode});

  @override
  State<CellStatusScreen> createState() => _CellStatusScreenState();
}

class _CellStatusScreenState extends State<CellStatusScreen> {
  final supabase = Supabase.instance.client;
  final Color pPurple = const Color(0xFF4A148C);
  final TextEditingController _findingsController = TextEditingController();

  List<String> _timeOptions = ['Current status', 'Weekly status', 'Monthly status', 'Custom period'];
  List<String> _visitOptions = ['Lta', 'H.m', 'Offline', 'Evangelism', 'Education', 'Offering'];
  
  String _selectedFilter = "Current status"; 
  String _visitCategory = "Lta"; 
  DateTimeRange? _customRange; 
  bool _isExpanded = false; 
  bool _isLoading = true;
  int _totalMembers = 0;
  List<dynamic> _logs = [];
  final ScrollController _sideScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  @override
  void dispose() {
    _sideScroll.dispose();
    _findingsController.dispose();
    super.dispose();
  }

  Future<void> _initScreen() async {
    await _fetchSidebarConfigs();
    await _fetchDashboardData();
    if (widget.initialMode != "dashboard") {
      WidgetsBinding.instance.addPostFrameCallback((_) => _navToEntry());
    }
  }

  Future<void> _fetchSidebarConfigs() async {
    try {
      final res = await supabase.from('compilation_ui_config').select().eq('is_active', true).order('sort_order');
      if (res.isNotEmpty && mounted) {
        setState(() {
          var t = res.where((e) => e['config_type'] == 'time_period').map((e) => e['label'].toString()).toList();
          var v = res.where((e) => e['config_type'] == 'visitation_category').map((e) => e['label'].toString()).toList();
          if (t.isNotEmpty) _timeOptions = t;
          if (v.isNotEmpty) _visitOptions = v;
        });
      }
    } catch (e) { debugPrint("Using fallbacks"); }
  }

  Future<void> _fetchDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final mRes = await supabase.from('members').select('id').eq('cell_group', widget.cellName);
      _totalMembers = mRes.length;

      DateTime now = DateTime.now();
      String table = _getTableName();
      var query = supabase.from(table).select('*, members!inner(*)').eq('unit_name', widget.cellName);
      
      if (_selectedFilter == "Weekly status") query = query.gte('report_date', DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 7))));
      else if (_selectedFilter == "Monthly status") query = query.gte('report_date', DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month, 1)));
      else if (_selectedFilter == "Custom period" && _customRange != null) {
        query = query.gte('report_date', DateFormat('yyyy-MM-dd').format(_customRange!.start)).lte('report_date', DateFormat('yyyy-MM-dd').format(_customRange!.end));
      } else query = query.eq('report_date', DateFormat('yyyy-MM-dd').format(now));

      final logRes = await query;
      if (mounted) setState(() { _logs = logRes; _isLoading = false; });
    } catch (e) { if (mounted) setState(() { _logs = []; _isLoading = false; }); }
  }

  String _getTableName() {
    if (widget.sheetName.contains('Attendance')) return 'logs_service_attendance_status';
    if (widget.sheetName.contains('Cell Group')) return 'logs_cell_service';
    if (widget.sheetName.contains('Offering')) return 'logs_offering';
    if (widget.sheetName.contains('Evangelism')) return 'logs_evangelism';
    if (widget.sheetName.contains('Visitations')) return 'logs_visitations';
    if (widget.sheetName.contains('Workers Education')) return 'logs_workers_education';
    if (widget.sheetName.contains('Morning Light')) return 'logs_morning_light';
    if (widget.sheetName.contains('All Saints Education')) return 'logs_all_saints_education';
    return 'logs_service_attendance_status';
  }

  int _count(String k, String v) => _logs.where((l) => l[k]?.toString().toLowerCase() == v.toLowerCase()).length;

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 1100;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context)),
        title: Text(widget.sheetName, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: pPurple, fontSize: 18)),
        actions: [IconButton(onPressed: _navToEntry, icon: const Icon(Icons.add_chart_rounded, color: Color(0xFF4A148C))), const SizedBox(width: 15)],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : Padding(
        padding: const EdgeInsets.all(15),
        child: isDesktop ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildSidebar(true), const SizedBox(width: 20), 
          Expanded(child: SingleChildScrollView(child: _buildMainContent())),
        ]) : ListView(children: [_buildSidebar(false), const SizedBox(height: 15), _buildMainContent()]),
      ),
    );
  }

  Widget _buildMainContent() => Column(children: [
    if (widget.sheetName == "Service Attendance Status") _buildExpandGeoBar(),
    _sectionCard("Detailed summary", _buildProfessionalTable(), onFull: () => _openFull("Detailed summary", _buildProfessionalTable())), 
    const SizedBox(height: 15), 
    _sectionCard("Participation distribution (%)", _buildChartSection(), onFull: () => _openFull("Participation analytics", _buildChartSection())),
    const SizedBox(height: 15),
    _buildFindingsBox(),
  ]);

  Widget _buildExpandGeoBar() => Align(alignment: Alignment.centerRight, child: TextButton.icon(
    onPressed: () => setState(() => _isExpanded = !_isExpanded),
    icon: Icon(_isExpanded ? Icons.unfold_less : Icons.unfold_more, size: 18),
    label: Text(_isExpanded ? "Squeeze geo-details" : "Expand geo-details (Kampala/Village/Abroad)", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: pPurple)),
  ));

  Widget _buildProfessionalTable() {
    List<String> h = []; String d = widget.sheetName;

    if (d == 'Service Attendance Status') {
      h = ["Period", "Saints", "Attended", "Att %", "In-person", "In-p %", "Online", "Onl %", "Abs", "Abs %"];
      if (_isExpanded) h.addAll(["Kla act", "Kla m-up", "Vil act", "Abr act"]);
    } 
    else if (d == 'Cell Group Service') h = ["Period", "Saints", "Attended", "%", "In-p", "%", "Onl", "%", "M-up", "%", "Abs", "%"];
    else if (d.contains('Offering')) h = ["Period", "Saints", "Tithe", "%", "Weekly", "%", "Thanks", "%", "Const", "%", "Donat", "%"];
    else if (d.contains('Evangelism')) h = ["Period", "Saints", "Mon", "%", "Tue", "%", "Wed", "%", "Thu", "%", "Fri", "%", "Sat", "%", "Sun", "%"];
    else if (d.contains('Morning Light')) h = ["Period", "Saints", "Mon", "%", "Tue", "%", "Wed", "%", "Thu", "%", "Fri", "%"];
    else if (d == 'All Saints Education') h = ["Period", "Saints", "Attended", "%", "In-p", "%", "Onl", "%", "M-up", "%", "Abs", "%"];
    else if (d.contains('Visitations')) h = ["Period", "Saints", "Visited", "Counselled", "Positive", "Negative"];
    else h = ["Period", "Saints", "Total", "%"];

    return LayoutBuilder(builder: (context, constraints) {
      double cellW = math.max(85.0, constraints.maxWidth / h.length);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.grey.withValues(alpha: 0.2)),
            child: DataTable(
              headingRowHeight: 45, dataRowMaxHeight: 34, dataRowMinHeight: 34,
              headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
              columnSpacing: 0, horizontalMargin: 0,
              border: TableBorder.all(color: Colors.grey.withValues(alpha: 0.3), width: 1.0),
              columns: h.map((s) => DataColumn(label: SizedBox(width: cellW, child: Center(child: Text(s, style: GoogleFonts.merriweather(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))))).toList(),
              rows: [DataRow(cells: _processRestoredCells(h, cellW))],
            ),
          ),
        ),
      );
    });
  }

  List<DataCell> _processRestoredCells(List<String> h, double cellW) {
    int tot = _totalMembers == 0 ? 1 : _totalMembers;
    List<DataCell> cells = [];
    void addC(String t, {Color? c, bool isP = false, bool isBold = false}) {
      String text = isP ? "${tot > 0 ? (double.parse(t)/tot*100).toStringAsFixed(1) : 0}%" : t;
      cells.add(DataCell(SizedBox(width: cellW, child: Center(child: Text(text, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: isP || isBold ? FontWeight.bold : FontWeight.w500, color: c ?? Colors.black87))))));
    }

    addC(_selectedFilter); addC("$tot");

    String d = widget.sheetName;
    if (d == 'Service Attendance Status') {
      int att = _logs.where((l) => l['attendance_realtime'] != 'Absentee').length;
      int ip = _count('attendance_realtime', 'In-person'), on = _count('attendance_realtime', 'On-line');
      addC("$att"); addC("$att", isP: true, c: pPurple); addC("$ip"); addC("$ip", isP: true); addC("$on"); addC("$on", isP: true); addC("${tot - att}", c: Colors.red); addC("${tot - att}", isP: true, c: Colors.red);
      if (_isExpanded) {
        addC("${_logs.where((l) => l['geo_category'] == 'Kampala' && l['attendance_realtime'] != 'Absentee').length}");
        addC("${_logs.where((l) => l['geo_category'] == 'Kampala' && l['attendance_makeup'] != null).length}");
        addC("${_logs.where((l) => l['geo_category'] == 'Village' && l['attendance_realtime'] != 'Absentee').length}");
        addC("${_logs.where((l) => l['geo_category'] == 'Abroad' && l['attendance_realtime'] != 'Absentee').length}");
      }
    } 
    else if (d == 'All Saints Education') {
      int ip = _count('status_detail', 'ASE In-person'), on = _count('status_detail', 'ASE Online'), mu = _count('status_detail', 'ASE Make Up'), ab = _count('status_detail', 'ASE Absence'), att = ip + on + mu;
      addC("$att"); addC("$att", isP: true); addC("$ip"); addC("$ip", isP: true); addC("$on"); addC("$on", isP: true); addC("$mu"); addC("$mu", isP: true); addC("$ab", c: Colors.red); addC("$ab", isP: true, c: Colors.red);
    }
    else if (d.contains('Visitations')) {
      int v = _logs.where((l) => l['visitation_reason'] == _visitCategory).length;
      int couns = _logs.where((l) => ["Education", "LTA"].contains(l['visitation_reason'])).length;
      int pos = _logs.where((l) => l['visitation_reason'] == _visitCategory && l['status_detail'] == "Positive").length;
      int neg = _logs.where((l) => l['visitation_reason'] == _visitCategory && l['status_detail'] == "Negative").length;
      addC("$v"); addC("$couns"); addC("$pos"); addC("$neg", c: Colors.red);
    }
    else if (d.contains('Offering')) {
      for (var k in ['offering_tithe', 'offering_weekly', 'offering_thanks', 'offering_construction', 'offering_donation']) {
        int count = _count(k, 'Paid'); addC("$count"); addC("$count", isP: true);
      }
    }
    else if (d.contains('Evangelism')) {
      for (var day in ['mon_part', 'tue_part', 'wed_part', 'thu_part', 'fri_part', 'sat_part', 'sun_part']) {
        int count = _count(day, 'Evangelised'); addC("$count"); addC("$count", isP: true);
      }
    }
    else if (d.contains('Morning Light')) {
      for (var day in ['mon_ml', 'tue_ml', 'wed_ml', 'thu_ml', 'fri_ml']) {
        int count = _count(day, 'ML Did'); addC("$count"); addC("$count", isP: true);
      }
    }
    else {
      addC("${_logs.length}"); addC("${_logs.length}", isP: true);
    }

    while (cells.length < h.length) cells.add(const DataCell(SizedBox()));
    return cells;
  }

  Widget _buildChartSection() {
    double successPct = _logs.isEmpty ? 0.0 : (_logs.length / (_totalMembers > 0 ? _totalMembers : 1)) * 100;

    return Column(children: [
      SizedBox(height: 280, child: Padding(
        padding: const EdgeInsets.only(right: 15, left: 5),
        child: BarChart(BarChartData(
          maxY: 100, 
          gridData: const FlGridData(show: false), 
          borderData: FlBorderData(
            show: true,
            border: const Border(
              left: BorderSide(color: Colors.blueGrey, width: 1.5),
              bottom: BorderSide(color: Colors.blueGrey, width: 1.5),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 45, getTitlesWidget: (v, m) => Text("${v.toInt()}%", style: GoogleFonts.merriweather(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 8), child: Text("Participation (%)", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.blueGrey))))),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barGroups: [
            BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: successPct, color: pPurple, width: 55, borderRadius: BorderRadius.circular(6))])
          ]
        )),
      )),
      const SizedBox(height: 15), 
      _buildLegend(), 
    ]);
  }

  Widget _buildLegend() => Wrap(spacing: 25, children: [_leg("Success percentage", pPurple), _leg("Pending/absentees", Colors.red[400]!)]);
  Widget _leg(String l, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 14, height: 14, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))), const SizedBox(width: 10), Text(l, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]))]);

  Widget _buildFindingsBox() => Container(
    padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: pPurple.withValues(alpha: 0.1))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Cell leader's findings", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: Colors.blueGrey, fontSize: 16)),
      const SizedBox(height: 12),
      TextField(controller: _findingsController, maxLines: 3, style: GoogleFonts.merriweather(fontSize: 14), decoration: InputDecoration(hintText: "Enter unit status observations...", filled: true, fillColor: const Color(0xFFFBFBFE), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerRight, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: pPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12)), onPressed: () {}, child: Text("Submit findings", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold))))
    ]),
  );

  Widget _sectionCard(String t, Widget c, {VoidCallback? onFull}) => Container(
    margin: const EdgeInsets.only(bottom: 15),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 8))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(title: Text(t, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: const Color(0xFF4A148C))), trailing: IconButton(icon: const Icon(Icons.open_in_full_rounded, size: 22), onPressed: onFull)),
      const Divider(height: 1),
      Padding(padding: const EdgeInsets.all(15), child: c),
    ]),
  );

  void _openFull(String t, Widget c) => Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (context) => Scaffold(backgroundColor: const Color(0xFFF1F5F9), appBar: AppBar(title: Text(t, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)), centerTitle: true), body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(20), child: c)))));

  Widget _buildSidebar(bool isDesktop) => Container(
    width: isDesktop ? 280 : double.infinity,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: Scrollbar(
      controller: _sideScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _sideScroll,
        padding: const EdgeInsets.all(15),
        child: Column(children: [
          _bentoNavCard("Data category", _timeOptions, _selectedFilter, (v) async {
            if (v == 'Custom period') {
              final p = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime.now());
              if (p != null) { setState(() { _customRange = p; _selectedFilter = v; }); _fetchDashboardData(); }
            } else setState(() { _selectedFilter = v; _fetchDashboardData(); });
          }),
          if (widget.sheetName.contains('Visitations'))
            _bentoNavCard("Visit category", _visitOptions, _visitCategory, (v) => setState(() => _visitCategory = v)),
        ]),
      ),
    ),
  );

  Widget _bentoNavCard(String t, List<String> i, String cur, Function(String) onS) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(t, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.blueGrey)),
    const SizedBox(height: 12),
    ...i.map((item) => InkWell(onTap: () => onS(item), child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), margin: const EdgeInsets.only(bottom: 5), decoration: BoxDecoration(color: cur == item ? pPurple : const Color(0xFFF3E5F5), borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(cur == item ? Icons.check_circle : Icons.circle_outlined, color: cur == item ? Colors.white : Colors.purple, size: 14), const SizedBox(width: 10), Expanded(child: Text(item, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: cur == item ? Colors.white : Colors.black87)))]))))
  ]);

  void _navToEntry() async {
    final bool? saved = await Navigator.push(context, MaterialPageRoute(builder: (c) => EntryFormScreen(sheetName: widget.sheetName, cellName: widget.cellName, location: widget.location, subLocation: widget.subLocation, dept: widget.dept, team: widget.team)));
    if (saved == true && mounted) Navigator.pop(context, true); else _fetchDashboardData();
  }
}