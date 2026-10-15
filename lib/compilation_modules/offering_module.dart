// ignore_for_file: curly_braces_in_flow_control_structures, unused_element
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

class _OfferingUnitStat {
  final String unitName;
  final int totalSaints;
  final int givers;
  final int tithe;
  final int weekly;
  final int thanks;
  final int construction;
  final int donation;

  _OfferingUnitStat({
    required this.unitName,
    required this.totalSaints,
    required this.givers,
    required this.tithe,
    required this.weekly,
    required this.thanks,
    required this.construction,
    required this.donation,
  });

  double get giversPct => totalSaints > 0 ? (givers / totalSaints * 100.0) : 0.0;
  double get tithePct => totalSaints > 0 ? (tithe / totalSaints * 100.0) : 0.0;
  double get weeklyPct => totalSaints > 0 ? (weekly / totalSaints * 100.0) : 0.0;
  double get thanksPct => totalSaints > 0 ? (thanks / totalSaints * 100.0) : 0.0;
  double get constructionPct => totalSaints > 0 ? (construction / totalSaints * 100.0) : 0.0;
  double get donationPct => totalSaints > 0 ? (donation / totalSaints * 100.0) : 0.0;
}

class OfferingModule extends StatefulWidget {
  final List<dynamic> logs;
  final String timePeriod;
  final String level;
  final String analyticsMode;
  final String groupBy;
  final double targetValue;

  // Hierarchical scope & drill-down filters
  final String selectedLocation;
  final String selectedSubLocation;
  final String selectedDepartment;
  final String selectedTeam;
  final String activeUnitLabel;

  // Role booleans
  final bool isChurchWide;
  final bool isLocationLeader;
  final bool isSubLocationLeader;
  final bool isDeptLeader;
  final bool isTeamLeader;
  final bool isGroupLeader;

  // User metadata
  final String userRole;
  final String userDept;
  final String userSub;
  final String userLoc;
  final String userTeam;

  const OfferingModule({
    super.key,
    required this.logs,
    required this.timePeriod,
    required this.level,
    this.analyticsMode = 'Summary',
    this.groupBy = 'Cell',
    this.targetValue = 80.0,
    this.selectedLocation = '',
    this.selectedSubLocation = '',
    this.selectedDepartment = '',
    this.selectedTeam = '',
    this.activeUnitLabel = 'Unit name',
    this.isChurchWide = false,
    this.isLocationLeader = false,
    this.isSubLocationLeader = false,
    this.isDeptLeader = false,
    this.isTeamLeader = false,
    this.isGroupLeader = false,
    this.userRole = '',
    this.userDept = '',
    this.userSub = '',
    this.userLoc = '',
    this.userTeam = '',
  });

  @override
  State<OfferingModule> createState() => _OfferingModuleState();
}

class _OfferingModuleState extends State<OfferingModule> {
  static const Color pPurple = Color(0xFF4A148C);

  List<Map<String, dynamic>> _masterMembers = [];
  bool _isLoadingMembers = false;
  String _selectedChartUnit = 'General total';

  @override
  void initState() {
    super.initState();
    _fetchMasterMembers();
  }

  @override
  void didUpdateWidget(covariant OfferingModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedLocation != widget.selectedLocation ||
        oldWidget.selectedSubLocation != widget.selectedSubLocation ||
        oldWidget.selectedDepartment != widget.selectedDepartment ||
        oldWidget.selectedTeam != widget.selectedTeam ||
        oldWidget.groupBy != widget.groupBy) {
      _selectedChartUnit = 'General total';
    }
  }

  // --- SUPABASE CAPACITY FETCHING (ALL SAINTS) ---
  Future<void> _fetchMasterMembers() async {
    try {
      setState(() => _isLoadingMembers = true);
      final res = await Supabase.instance.client
          .from('members')
          .select('id, name, location, sub_location, current_dept, dept, team_number, team, cell_number, cell');

      if (mounted) {
        setState(() {
          _masterMembers = List<Map<String, dynamic>>.from(res as List);
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMembers = false);
      }
      debugPrint('OfferingModule: members table fetch note: $e');
    }
  }

  // --- STRICT CASCADING FILTER ---
  bool _matchesCascade(Map<String, dynamic> item) {
    Map<String, dynamic> m = {};
    if (item['members'] is Map) {
      m = Map<String, dynamic>.from(item['members']);
    }

    String loc = item['location']?.toString() ?? m['location']?.toString() ?? '';
    String sub = item['sub_location']?.toString() ?? m['sub_location']?.toString() ?? '';
    String dept = item['current_dept']?.toString() ?? item['dept']?.toString() ?? m['current_dept']?.toString() ?? m['dept']?.toString() ?? '';
    String team = item['team_number']?.toString() ?? item['team']?.toString() ?? m['team_number']?.toString() ?? m['team']?.toString() ?? '';

    if (widget.selectedLocation.isNotEmpty &&
        widget.selectedLocation != 'All' &&
        widget.selectedLocation != 'Church Wide') {
      if (loc.isNotEmpty && loc.toLowerCase() != widget.selectedLocation.toLowerCase()) {
        return false;
      }
    }

    if (widget.selectedSubLocation.isNotEmpty &&
        widget.selectedSubLocation != 'All' &&
        widget.selectedSubLocation != 'Sub-location status') {
      if (sub.isNotEmpty && sub.toLowerCase() != widget.selectedSubLocation.toLowerCase()) {
        return false;
      }
    }

    if (widget.selectedDepartment.isNotEmpty &&
        widget.selectedDepartment != 'All' &&
        widget.selectedDepartment != 'Dept status') {
      if (dept.isNotEmpty && dept.toLowerCase() != widget.selectedDepartment.toLowerCase()) {
        return false;
      }
    }

    if (widget.selectedTeam.isNotEmpty &&
        widget.selectedTeam != 'All' &&
        widget.selectedTeam != 'Team status') {
      if (team.isNotEmpty && team.toLowerCase() != widget.selectedTeam.toLowerCase()) {
        return false;
      }
    }

    return true;
  }

  // --- UNIT GROUPING KEY ---
  String _getUnitKey(Map<String, dynamic> item) {
    Map<String, dynamic> m = {};
    if (item['members'] is Map) {
      m = Map<String, dynamic>.from(item['members']);
    }

    String k = 'cell_number';
    String gb = widget.groupBy.toLowerCase().trim();
    if (gb.contains('team')) k = 'team_number';
    else if (gb.contains('dept')) k = 'current_dept';
    else if (gb.contains('sub')) k = 'sub_location';
    else if (gb.contains('loc')) k = 'location';

    String val = item[k]?.toString() ?? m[k]?.toString() ?? '';
    if (val.isEmpty) {
      if (k == 'cell_number') val = item['cell']?.toString() ?? m['cell']?.toString() ?? '';
      if (k == 'team_number') val = item['team']?.toString() ?? m['team']?.toString() ?? '';
      if (k == 'current_dept') val = item['dept']?.toString() ?? m['dept']?.toString() ?? '';
      if (k == 'sub_location') val = item['sub']?.toString() ?? m['sub']?.toString() ?? '';
      if (k == 'location') val = item['loc']?.toString() ?? m['loc']?.toString() ?? '';
    }
    return val.trim().isNotEmpty ? val.trim() : 'Unassigned';
  }

  // --- HELPER: CHECK IF OFFERING WAS PAID ---
  bool _isPaid(dynamic val) {
    if (val == null) return false;
    final s = val.toString().trim().toLowerCase();
    return s == 'yes' || s == 'paid' || s == 'true' || s == 'done' || s == '1';
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    try {
      return DateTime.parse(val.toString());
    } catch (_) {
      return null;
    }
  }

  // --- AGGREGATION PIPELINE ---
  List<_OfferingUnitStat> _calculateStats() {
    // 1. Cascaded logs
    final cascadedLogs = widget.logs.where((l) {
      if (l is! Map) return false;
      return _matchesCascade(Map<String, dynamic>.from(l));
    }).toList();

    // 2. Cascaded master members (Saints capacity)
    final cascadedMembers = _masterMembers.where((m) => _matchesCascade(m)).toList();

    // Group members by unit for true capacity
    final Map<String, int> unitSaintsCount = {};
    for (var m in cascadedMembers) {
      final u = _getUnitKey(m);
      if (u != 'Unassigned') {
        unitSaintsCount[u] = (unitSaintsCount[u] ?? 0) + 1;
      }
    }

    // Group logs by unit
    final Map<String, List<dynamic>> unitLogs = {};
    for (var l in cascadedLogs) {
      final u = _getUnitKey(Map<String, dynamic>.from(l));
      if (u != 'Unassigned') {
        unitLogs.putIfAbsent(u, () => []).add(l);
      }
    }

    final Set<String> allUnits = {...unitSaintsCount.keys, ...unitLogs.keys};
    final sortedUnits = allUnits.toList()..sort((a, b) => a.compareTo(b));

    List<_OfferingUnitStat> stats = [];

    for (var u in sortedUnits) {
      final uLogs = unitLogs[u] ?? [];
      int saints = unitSaintsCount[u] ?? 0;

      // Fallback to distinct members in logs if master capacity is unavailable
      if (saints == 0) {
        final distinctIds = <dynamic>{};
        for (var l in uLogs) {
          final mid = l['member_id'] ?? l['members']?['id'] ?? l['id'];
          if (mid != null) distinctIds.add(mid);
        }
        saints = distinctIds.isNotEmpty ? distinctIds.length : uLogs.length;
      }

      int t = uLogs.where((l) => _isPaid(l['offering_tithe'])).length;
      int w = uLogs.where((l) => _isPaid(l['offering_weekly'])).length;
      int th = uLogs.where((l) => _isPaid(l['offering_thanks'])).length;
      int c = uLogs.where((l) => _isPaid(l['offering_construction'])).length;
      int d = uLogs.where((l) => _isPaid(l['offering_donation'])).length;

      int givers = uLogs.where((l) =>
        _isPaid(l['offering_tithe']) ||
        _isPaid(l['offering_weekly']) ||
        _isPaid(l['offering_thanks']) ||
        _isPaid(l['offering_construction']) ||
        _isPaid(l['offering_donation'])
      ).length;

      // Ensure total capacity is at least equal to maximum recorded count
      saints = math.max(saints, math.max(givers, math.max(t, math.max(w, math.max(th, math.max(c, d))))));

      stats.add(_OfferingUnitStat(
        unitName: u,
        totalSaints: saints,
        givers: givers,
        tithe: t,
        weekly: w,
        thanks: th,
        construction: c,
        donation: d,
      ));
    }

    return stats;
  }

  _OfferingUnitStat _calculateTotalStat(List<_OfferingUnitStat> stats) {
    int totalSaints = 0;
    int givers = 0;
    int tithe = 0;
    int weekly = 0;
    int thanks = 0;
    int construction = 0;
    int donation = 0;

    for (var s in stats) {
      totalSaints += s.totalSaints;
      givers += s.givers;
      tithe += s.tithe;
      weekly += s.weekly;
      thanks += s.thanks;
      construction += s.construction;
      donation += s.donation;
    }

    return _OfferingUnitStat(
      unitName: 'General total',
      totalSaints: totalSaints,
      givers: givers,
      tithe: tithe,
      weekly: weekly,
      thanks: thanks,
      construction: construction,
      donation: donation,
    );
  }

  // --- UI: TABLE SUMMARY (13 Columns) ---
  Widget _buildOfferingTable(List<_OfferingUnitStat> stats, _OfferingUnitStat totalStat) {
    const double rh = 24.0;
    const double hh = 28.0;

    final Map<int, TableColumnWidth> colWidths = {
      0: const FixedColumnWidth(130), // Unit name
      1: const FixedColumnWidth(65),  // Saints
      2: const FixedColumnWidth(65),  // Givers
      3: const FixedColumnWidth(55),  // Tithe
      4: const FixedColumnWidth(50),  // Tithe %
      5: const FixedColumnWidth(55),  // Wkly
      6: const FixedColumnWidth(50),  // Wkly %
      7: const FixedColumnWidth(55),  // Thks
      8: const FixedColumnWidth(50),  // Thks %
      9: const FixedColumnWidth(55),  // Const
      10: const FixedColumnWidth(50), // Const %
      11: const FixedColumnWidth(55), // Donat
      12: const FixedColumnWidth(50), // Donat %
    };

    List<String> headers = [
      widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : "Unit name",
      "Saints", "Givers", "Tithe", "%", "Wkly", "%", "Thks", "%", "Const", "%", "Donat", "%"
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: colWidths,
        border: TableBorder.all(color: Colors.black87, width: 1.0),
        children: [
          // Header Row
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFF1E293B)),
            children: headers.map((title) {
              return SizedBox(
                height: hh,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: Text(
                      title,
                      style: GoogleFonts.merriweather(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          // Data Rows
          ...stats.asMap().entries.map((entry) {
            int idx = entry.key;
            _OfferingUnitStat u = entry.value;
            final isEven = idx.isEven;
            final rowColor = isEven ? Colors.white : const Color(0xFFF8FAFC);

            return TableRow(
              decoration: BoxDecoration(color: rowColor),
              children: [
                _cellText(u.unitName, rh, isBold: true, align: TextAlign.left, padLeft: 6),
                _cellText("${u.totalSaints}", rh),
                _cellText("${u.givers}", rh, color: pPurple, isBold: true),
                _cellText("${u.tithe}", rh),
                _cellPercent(u.tithePct, rh, pPurple),
                _cellText("${u.weekly}", rh),
                _cellPercent(u.weeklyPct, rh, Colors.blue[800]!),
                _cellText("${u.thanks}", rh),
                _cellPercent(u.thanksPct, rh, Colors.orange[900]!),
                _cellText("${u.construction}", rh),
                _cellPercent(u.constructionPct, rh, Colors.teal[800]!),
                _cellText("${u.donation}", rh),
                _cellPercent(u.donationPct, rh, Colors.indigo[800]!),
              ],
            );
          }),

          // General Total Summary Row
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFEDE7F6)),
            children: [
              _cellText("General total", 26.0, isBold: true, color: pPurple, align: TextAlign.left, padLeft: 6),
              _cellText("${totalStat.totalSaints}", 26.0, isBold: true),
              _cellText("${totalStat.givers}", 26.0, isBold: true, color: pPurple),
              _cellText("${totalStat.tithe}", 26.0, isBold: true),
              _cellPercent(totalStat.tithePct, 26.0, pPurple, isBold: true),
              _cellText("${totalStat.weekly}", 26.0, isBold: true),
              _cellPercent(totalStat.weeklyPct, 26.0, Colors.blue[900]!, isBold: true),
              _cellText("${totalStat.thanks}", 26.0, isBold: true),
              _cellPercent(totalStat.thanksPct, 26.0, Colors.orange[900]!, isBold: true),
              _cellText("${totalStat.construction}", 26.0, isBold: true),
              _cellPercent(totalStat.constructionPct, 26.0, Colors.teal[900]!, isBold: true),
              _cellText("${totalStat.donation}", 26.0, isBold: true),
              _cellPercent(totalStat.donationPct, 26.0, Colors.indigo[900]!, isBold: true),
            ],
          ),
        ],
      ),
    );
  }

  // --- UI: DYNAMIC UNIT SELECTOR PILLS ---
  Widget _buildUnitPillBar(List<_OfferingUnitStat> stats) {
    final List<String> units = ['General total', ...stats.map((s) => s.unitName)];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: units.map((u) {
            final isSelected = _selectedChartUnit == u;
            return Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: ChoiceChip(
                label: Text(
                  u,
                  style: GoogleFonts.merriweather(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
                selected: isSelected,
                selectedColor: pPurple,
                backgroundColor: const Color(0xFFF1F5F9),
                visualDensity: VisualDensity.compact,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedChartUnit = u);
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // --- UI: DYNAMIC TREND CHART (Linked to Unit Selector) ---
  Widget _buildTrendChart(List<_OfferingUnitStat> stats) {
    // Filter cascaded logs
    final cascadedLogs = widget.logs.where((l) {
      if (l is! Map) return false;
      return _matchesCascade(Map<String, dynamic>.from(l));
    }).toList();

    // Further filter by selected unit if not General total
    final filteredLogs = _selectedChartUnit == 'General total'
        ? cascadedLogs
        : cascadedLogs.where((l) => _getUnitKey(Map<String, dynamic>.from(l)) == _selectedChartUnit).toList();

    Map<DateTime, List<dynamic>> timeMap = {};
    for (var log in filteredLogs) {
      DateTime? d = _parseDate(log['report_date'] ?? log['date'] ?? log['created_at']);
      if (d != null) {
        timeMap.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(log);
      }
    }

    var sortedDates = timeMap.keys.toList()..sort();
    if (sortedDates.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUnitPillBar(stats),
          const SizedBox(height: 120, child: Center(child: Text("No offering date records found for trend chart"))),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUnitPillBar(stats),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Displaying: $_selectedChartUnit",
                style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  _legItem("Tithe", pPurple),
                  _legItem("Weekly", Colors.blue),
                  _legItem("Thanks", Colors.orange),
                  _legItem("Const", Colors.teal),
                  _legItem("Donat", Colors.indigo),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          height: 320,
          child: LineChart(
            LineChartData(
              maxY: 100,
              minY: 0,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 20,
                getDrawingHorizontalLine: (val) => FlLine(
                  color: Colors.grey.withValues(alpha: 0.18),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: const Border(
                  bottom: BorderSide(color: Colors.black45, width: 1),
                  left: BorderSide(color: Colors.black45, width: 1),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: 20,
                    getTitlesWidget: (v, m) => Text(
                      "${v.toInt()}%",
                      style: GoogleFonts.merriweather(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 28,
                    getTitlesWidget: (v, m) {
                      int idx = v.toInt();
                      if (idx < 0 || idx >= sortedDates.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          DateFormat('dd/MM').format(sortedDates[idx]),
                          style: GoogleFonts.merriweather(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                _lineData(sortedDates, timeMap, 'offering_tithe', pPurple),
                _lineData(sortedDates, timeMap, 'offering_weekly', Colors.blue),
                _lineData(sortedDates, timeMap, 'offering_thanks', Colors.orange),
                _lineData(sortedDates, timeMap, 'offering_construction', Colors.teal),
                _lineData(sortedDates, timeMap, 'offering_donation', Colors.indigo),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- UI: RANKING LIST ---
  Widget _buildRankingList(List<_OfferingUnitStat> stats, bool isTop) {
    if (stats.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text("No ranking data found", style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final sorted = List<_OfferingUnitStat>.from(stats);
    sorted.sort((a, b) => isTop ? b.giversPct.compareTo(a.giversPct) : a.giversPct.compareTo(b.giversPct));
    final displayList = sorted.take(5).toList();

    return Column(
      children: displayList.asMap().entries.map((entry) {
        int rank = entry.key + 1;
        _OfferingUnitStat item = entry.value;
        final color = isTop ? Colors.green[700]! : Colors.red[700]!;

        return ListTile(
          dense: true,
          leading: CircleAvatar(
            backgroundColor: isTop ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12),
            radius: 16,
            child: Text(
              "#$rank",
              style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          title: Row(
            children: [
              Icon(isTop ? Icons.payments_rounded : Icons.money_off_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(item.unitName, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          subtitle: Text(
            "Saints: ${item.totalSaints} | Givers: ${item.givers} (Tithe: ${item.tithe}, Wkly: ${item.weekly})",
            style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
          trailing: Text(
            "${item.giversPct.toStringAsFixed(1)}%",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: color),
          ),
        );
      }).toList(),
    );
  }

  // --- PDF REPORT EXPORT ---
  Future<void> _exportPdf(List<_OfferingUnitStat> stats, _OfferingUnitStat totalStat) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.merriweatherRegular();
    final fontBold = await PdfGoogleFonts.merriweatherBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Offering & Giving Participation Report (All Saints)',
                      style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.purple900)),
                  pw.Text(
                    'Generated: ${DateTime.now().toLocal().toString().split(' ')[0]}',
                    style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Level: ${widget.level} | Group By: ${widget.groupBy} | Period: ${widget.timePeriod}'
              '${widget.selectedLocation.isNotEmpty ? ' | Loc: ${widget.selectedLocation}' : ''}'
              '${widget.selectedSubLocation.isNotEmpty ? ' | Sub: ${widget.selectedSubLocation}' : ''}'
              '${widget.selectedDepartment.isNotEmpty ? ' | Dept: ${widget.selectedDepartment}' : ''}'
              '${widget.selectedTeam.isNotEmpty ? ' | Team: ${widget.selectedTeam}' : ''}',
              style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: [
                widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : 'Unit',
                'Saints',
                'Givers',
                'Tithe',
                'Tithe %',
                'Wkly',
                'Wkly %',
                'Thks',
                'Thks %',
                'Const',
                'Const %',
                'Donat',
                'Donat %',
              ],
              data: [
                ...stats.map((u) => [
                      u.unitName,
                      '${u.totalSaints}',
                      '${u.givers}',
                      '${u.tithe}',
                      '${u.tithePct.toStringAsFixed(0)}%',
                      '${u.weekly}',
                      '${u.weeklyPct.toStringAsFixed(0)}%',
                      '${u.thanks}',
                      '${u.thanksPct.toStringAsFixed(0)}%',
                      '${u.construction}',
                      '${u.constructionPct.toStringAsFixed(0)}%',
                      '${u.donation}',
                      '${u.donationPct.toStringAsFixed(0)}%',
                    ]),
                [
                  'General Total',
                  '${totalStat.totalSaints}',
                  '${totalStat.givers}',
                  '${totalStat.tithe}',
                  '${totalStat.tithePct.toStringAsFixed(0)}%',
                  '${totalStat.weekly}',
                  '${totalStat.weeklyPct.toStringAsFixed(0)}%',
                  '${totalStat.thanks}',
                  '${totalStat.thanksPct.toStringAsFixed(0)}%',
                  '${totalStat.construction}',
                  '${totalStat.constructionPct.toStringAsFixed(0)}%',
                  '${totalStat.donation}',
                  '${totalStat.donationPct.toStringAsFixed(0)}%',
                ],
              ],
              headerStyle: pw.TextStyle(font: fontBold, fontSize: 7.5, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.purple900),
              cellStyle: pw.TextStyle(font: font, fontSize: 7.5),
              cellAlignment: pw.Alignment.center,
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
              rowDecoration: const pw.BoxDecoration(),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // --- HELPERS ---
  Widget _cellText(String text, double height, {
    Color? color,
    bool isBold = false,
    TextAlign align = TextAlign.center,
    double padLeft = 0,
  }) {
    return SizedBox(
      height: height,
      child: Container(
        alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.center,
        padding: EdgeInsets.only(left: padLeft, right: 2),
        child: Text(
          text,
          style: GoogleFonts.merriweather(
            fontSize: 9.5,
            color: color ?? Colors.black87,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        ),
      ),
    );
  }

  Widget _cellPercent(double pct, double height, Color color, {bool isBold = false}) {
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          "${pct.toStringAsFixed(0)}%",
          style: GoogleFonts.merriweather(
            fontSize: 9.0,
            color: color,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
          ),
        ),
      ),
    );
  }

  LineChartBarData _lineData(List<DateTime> dates, Map<DateTime, List<dynamic>> map, String key, Color color) {
    return LineChartBarData(
      isCurved: true,
      color: color,
      barWidth: 2.5,
      dotData: FlDotData(show: dates.length <= 4),
      spots: List.generate(dates.length, (i) {
        var dayLogs = map[dates[i]]!;
        int count = dayLogs.where((l) => _isPaid(l[key])).length;
        double pct = dayLogs.isNotEmpty ? (count / dayLogs.length * 100) : 0.0;
        return FlSpot(i.toDouble(), pct);
      }),
    );
  }

  Widget _legItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.merriweather(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
        ),
      ],
    );
  }

  Widget _section(String title, Widget content, BuildContext context, {VoidCallback? onPdf}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.black12, width: 1.0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.merriweather(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: pPurple,
                    ),
                  ),
                ),
                if (onPdf != null)
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 20, color: pPurple),
                    tooltip: 'Export PDF Report',
                    onPressed: onPdf,
                  ),
                IconButton(
                  icon: const Icon(Icons.open_in_full_rounded, size: 19, color: Colors.blueGrey),
                  tooltip: 'Fullscreen View',
                  onPressed: () => _showFull(context, title, content),
                ),
              ],
            ),
          ),
          content,
        ],
      ),
    );
  }

  void _showFull(BuildContext ctx, String title, Widget content) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: pPurple,
            foregroundColor: Colors.white,
            title: Text(title, style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.bold)),
            centerTitle: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: content,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<_OfferingUnitStat> unitStats = _calculateStats();
    final _OfferingUnitStat totalStat = _calculateTotalStat(unitStats);

    if (_isLoadingMembers && _masterMembers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(color: pPurple),
        ),
      );
    }

    return Column(
      children: [
        if (widget.analyticsMode == 'Ranking') ...[
          _section(
            "Top giving units",
            _buildRankingList(unitStats, true),
            context,
          ),
          _section(
            "Units requiring financial counseling",
            _buildRankingList(unitStats, false),
            context,
          ),
        ] else ...[
          _section(
            "Offering summary table",
            _buildOfferingTable(unitStats, totalStat),
            context,
            onPdf: () => _exportPdf(unitStats, totalStat),
          ),
          const SizedBox(height: 10),
          _section(
            "Giving trends (%)",
            _buildTrendChart(unitStats),
            context,
          ),
        ],
      ],
    );
  }
}