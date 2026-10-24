// ignore_for_file: curly_braces_in_flow_control_structures, unused_element
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

class _EvangelismUnitStat {
  final String unitName;
  final int totalSaints;
  final int mon;
  final int tue;
  final int wed;
  final int thu;
  final int fri;
  final int sat;
  final int sun;

  _EvangelismUnitStat({
    required this.unitName,
    required this.totalSaints,
    required this.mon,
    required this.tue,
    required this.wed,
    required this.thu,
    required this.fri,
    required this.sat,
    required this.sun,
  });

  double get weeklyAvg => (mon + tue + wed + thu + fri + sat + sun) / 7.0;
  double get weeklyAvgPct => totalSaints > 0 ? (weeklyAvg / totalSaints * 100.0) : 0.0;
  double get monPct => totalSaints > 0 ? (mon / totalSaints * 100.0) : 0.0;
  double get tuePct => totalSaints > 0 ? (tue / totalSaints * 100.0) : 0.0;
  double get wedPct => totalSaints > 0 ? (wed / totalSaints * 100.0) : 0.0;
  double get thuPct => totalSaints > 0 ? (thu / totalSaints * 100.0) : 0.0;
  double get friPct => totalSaints > 0 ? (fri / totalSaints * 100.0) : 0.0;
  double get satPct => totalSaints > 0 ? (sat / totalSaints * 100.0) : 0.0;
  double get sunPct => totalSaints > 0 ? (sun / totalSaints * 100.0) : 0.0;
}

class EvangelismModule extends StatefulWidget {
  final List<dynamic> logs;
  final String timePeriod;
  final String level;
  final String analyticsMode;
  final String groupBy;
  final double targetValue;

  final String selectedLocation;
  final String selectedSubLocation;
  final String selectedDepartment;
  final String selectedTeam;
  final String activeUnitLabel;

  final bool isChurchWide;
  final bool isLocationLeader;
  final bool isSubLocationLeader;
  final bool isDeptLeader;
  final bool isTeamLeader;
  final bool isGroupLeader;

  final String userRole;
  final String userDept;
  final String userSub;
  final String userLoc;
  final String userTeam;

  const EvangelismModule({
    super.key,
    required this.logs,
    required this.timePeriod,
    required this.level,
    required this.analyticsMode,
    required this.groupBy,
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
  State<EvangelismModule> createState() => _EvangelismModuleState();
}

class _EvangelismModuleState extends State<EvangelismModule> {
  final _supabase = Supabase.instance.client;
  static const Color pPurple = Color(0xFF4A148C);

  List<Map<String, dynamic>> _masterMembers = [];
  bool _isLoadingMembers = false;
  String _selectedChartUnit = 'General total';

  bool get _is24ChurchDept {
    final r = widget.userRole.toLowerCase();
    final d = widget.userDept.toLowerCase();
    return (r.contains('_dept_') || r.startsWith('ia_') || d.contains('내무')) &&
        !widget.isLocationLeader &&
        !widget.isSubLocationLeader &&
        !widget.isDeptLeader &&
        !widget.isTeamLeader &&
        !widget.isGroupLeader;
  }

  @override
  void initState() {
    super.initState();
    _fetchMasterMembers();
  }

  @override
  void didUpdateWidget(covariant EvangelismModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedLocation != widget.selectedLocation ||
        oldWidget.selectedSubLocation != widget.selectedSubLocation ||
        oldWidget.selectedDepartment != widget.selectedDepartment ||
        oldWidget.selectedTeam != widget.selectedTeam ||
        oldWidget.level != widget.level ||
        oldWidget.groupBy != widget.groupBy ||
        oldWidget.logs != widget.logs) {
      _selectedChartUnit = 'General total';
      _fetchMasterMembers();
    }
  }

  // --- STANDARDIZED COLUMNS MATCHING YOUR MEMBERS TABLE ---
  Future<void> _fetchMasterMembers() async {
    try {
      setState(() => _isLoadingMembers = true);
      final lvl = widget.level.toLowerCase();

      dynamic mQuery = _supabase.from('members').select(
        'id, english_name, location, sub_location, department, team, cell_group'
      );

      // Scoping
      if (_is24ChurchDept && widget.groupBy == 'Church') {
        mQuery = mQuery.or('location.eq.Church,location.eq.Church Workers,location.eq.Church Main,location.is.null');
        if (widget.userDept.isNotEmpty && widget.userDept != 'Church') {
          mQuery = mQuery.eq('department', widget.userDept);
        }
      } else if (widget.isGroupLeader && widget.userDept.isNotEmpty) {
        mQuery = mQuery.eq('department', widget.userDept).neq('location', 'Mou').neq('location', 'New Saints');
      } else if (!widget.isChurchWide) {
        if (widget.userLoc.isNotEmpty && widget.userLoc != 'Church') {
          mQuery = mQuery.eq('location', widget.userLoc);
        }
        if (widget.isSubLocationLeader && widget.userSub.isNotEmpty) {
          mQuery = mQuery.eq('sub_location', widget.userSub);
        }
        if (widget.isDeptLeader && widget.userDept.isNotEmpty) {
          mQuery = mQuery.eq('department', widget.userDept);
        }
      }

      if (lvl.contains('sub location') || lvl.contains('sub-location')) {
        if (widget.selectedLocation.isNotEmpty && widget.selectedLocation.toLowerCase() != 'church') {
          mQuery = mQuery.eq('location', widget.selectedLocation);
        }
      } else if (lvl.contains('dept') && !_is24ChurchDept) {
        if (widget.selectedLocation.isNotEmpty && widget.selectedLocation.toLowerCase() != 'church') {
          mQuery = mQuery.eq('location', widget.selectedLocation);
        }
        if (widget.selectedSubLocation.isNotEmpty) {
          mQuery = mQuery.eq('sub_location', widget.selectedSubLocation);
        }
      } else if (lvl.contains('team')) {
        if (widget.selectedLocation.isNotEmpty && widget.selectedLocation.toLowerCase() != 'church') {
          mQuery = mQuery.eq('location', widget.selectedLocation);
        }
        if (widget.selectedSubLocation.isNotEmpty) {
          mQuery = mQuery.eq('sub_location', widget.selectedSubLocation);
        }
        if (widget.selectedDepartment.isNotEmpty) {
          mQuery = mQuery.eq('department', widget.selectedDepartment);
        }
      } else if (lvl.contains('cell')) {
        if (widget.selectedLocation.isNotEmpty && widget.selectedLocation.toLowerCase() != 'church') {
          mQuery = mQuery.eq('location', widget.selectedLocation);
        }
        if (widget.selectedSubLocation.isNotEmpty) {
          mQuery = mQuery.eq('sub_location', widget.selectedSubLocation);
        }
        if (widget.selectedDepartment.isNotEmpty) {
          mQuery = mQuery.eq('department', widget.selectedDepartment);
        }
        if (widget.selectedTeam.isNotEmpty) {
          mQuery = mQuery.eq('team', widget.selectedTeam);
        }
      }

      List<Map<String, dynamic>> allMembers = [];
      int offset = 0;
      const int pageSize = 1000;
      while (true) {
        final chunk = await mQuery.range(offset, offset + pageSize - 1);
        final list = List<Map<String, dynamic>>.from(chunk);
        allMembers.addAll(list);
        if (list.length < pageSize) break;
        offset += pageSize;
      }

      if (mounted) {
        setState(() {
          _masterMembers = allMembers;
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMembers = false);
      debugPrint('EvangelismModule: members query notice: $e');
    }
  }

  // --- CASCADING DRILL-DOWN FILTER ---
  bool _matchesCascade(Map<String, dynamic> item) {
    Map<String, dynamic> m = {};
    if (item['members'] is Map) {
      m = Map<String, dynamic>.from(item['members']);
    }

    String loc = item['location']?.toString() ?? m['location']?.toString() ?? '';
    String sub = item['sub_location']?.toString() ?? m['sub_location']?.toString() ?? '';
    String dept = item['department']?.toString() ?? m['department']?.toString() ?? '';
    String team = item['team']?.toString() ?? m['team']?.toString() ?? '';

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
        widget.selectedDepartment != 'Dept status' &&
        !_is24ChurchDept) {
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

  // --- UNIT GROUPING KEY (STANDARDIZED) ---
  String _getUnitKey(Map<String, dynamic> item) {
    Map<String, dynamic> m = {};
    if (item['members'] is Map) {
      m = Map<String, dynamic>.from(item['members']);
    }

    String gb = widget.groupBy.toLowerCase().trim();
    String val = '';

    if (gb.contains('cell')) {
      val = item['unit_name']?.toString() ?? item['cell_group']?.toString() ?? m['cell_group']?.toString() ?? '';
    } else if (gb.contains('team')) {
      val = item['team']?.toString() ?? m['team']?.toString() ?? '';
    } else if (gb.contains('dept')) {
      val = item['department']?.toString() ?? m['department']?.toString() ?? '';
    } else if (gb.contains('sub')) {
      val = item['sub_location']?.toString() ?? m['sub_location']?.toString() ?? '';
    } else if (gb.contains('loc')) {
      val = item['location']?.toString() ?? m['location']?.toString() ?? '';
    }

    return val.trim().isNotEmpty ? val.trim() : 'Unassigned';
  }

  bool _isEvangelised(dynamic val) {
    if (val == null) return false;
    final s = val.toString().trim().toLowerCase();
    return s == 'evangelised' ||
        s == 'evangelized' ||
        s == 'yes' ||
        s == 'done' ||
        s == 'true' ||
        s == '1' ||
        s.contains('participated');
  }

  // Dual-format day checker: checks both new 'evang_day' and legacy 'mon_part'
  bool _isDayEvangelised(dynamic log, String dayCode, String legacyField) {
    final evangDay = (log['evang_day'] ?? '').toString().trim().toLowerCase();
    if (evangDay.isNotEmpty) {
      if (evangDay == dayCode.toLowerCase()) {
        return _isEvangelised(log['status_detail']);
      }
      return false;
    }
    return _isEvangelised(log[legacyField]);
  }

  // --- AGGREGATION PIPELINE ---
  List<_EvangelismUnitStat> _calculateStats() {
    final cascadedLogs = widget.logs.where((l) {
      if (l is! Map) return false;
      return _matchesCascade(Map<String, dynamic>.from(l));
    }).toList();

    final cascadedMembers = _masterMembers.where((m) => _matchesCascade(m)).toList();

    final Map<String, int> unitSaintsCount = {};
    for (var m in cascadedMembers) {
      final u = _getUnitKey(m);
      if (u != 'Unassigned') {
        unitSaintsCount[u] = (unitSaintsCount[u] ?? 0) + 1;
      }
    }

    final Map<String, List<dynamic>> unitLogs = {};
    for (var l in cascadedLogs) {
      final u = _getUnitKey(Map<String, dynamic>.from(l));
      if (u != 'Unassigned') {
        unitLogs.putIfAbsent(u, () => []).add(l);
      }
    }

    if (_is24ChurchDept || widget.groupBy == 'Church') {
      return [];
    }

    final lvl = widget.level.toLowerCase();
    if (widget.isDeptLeader && lvl == 'dept status') return [];
    if (widget.isSubLocationLeader && (lvl.contains('sub location') || lvl.contains('sub-location'))) return [];
    if (widget.isTeamLeader && lvl == 'team status') return [];
    if (widget.isLocationLeader && lvl == 'location status') return [];

    final Set<String> allUnits = {...unitSaintsCount.keys, ...unitLogs.keys};
    final sortedUnits = allUnits.toList()..sort((a, b) => a.compareTo(b));

    List<_EvangelismUnitStat> stats = [];

    for (var u in sortedUnits) {
      final uLogs = unitLogs[u] ?? [];
      int saints = unitSaintsCount[u] ?? 0;

      if (saints == 0) {
        final distinctIds = <dynamic>{};
        for (var l in uLogs) {
          final mid = l['member_id'] ?? l['members']?['id'] ?? l['id'];
          if (mid != null) distinctIds.add(mid);
        }
        saints = distinctIds.isNotEmpty ? distinctIds.length : uLogs.length;
      }

      int mon = uLogs.where((l) => _isDayEvangelised(l, 'Mon', 'mon_part')).length;
      int tue = uLogs.where((l) => _isDayEvangelised(l, 'Tue', 'tue_part')).length;
      int wed = uLogs.where((l) => _isDayEvangelised(l, 'Wed', 'wed_part')).length;
      int thu = uLogs.where((l) => _isDayEvangelised(l, 'Thu', 'thu_part')).length;
      int fri = uLogs.where((l) => _isDayEvangelised(l, 'Fri', 'fri_part')).length;
      int sat = uLogs.where((l) => _isDayEvangelised(l, 'Sat', 'sat_part')).length;
      int sun = uLogs.where((l) => _isDayEvangelised(l, 'Sun', 'sun_part')).length;

      int maxDay = math.max(mon, math.max(tue, math.max(wed, math.max(thu, math.max(fri, math.max(sat, sun))))));
      saints = math.max(saints, maxDay);

      stats.add(_EvangelismUnitStat(
        unitName: u,
        totalSaints: saints,
        mon: mon,
        tue: tue,
        wed: wed,
        thu: thu,
        fri: fri,
        sat: sat,
        sun: sun,
      ));
    }

    return stats;
  }

  _EvangelismUnitStat _calculateTotalStat(List<dynamic> allLogs, List<Map<String, dynamic>> allMembers) {
    int totalSaints = allMembers.isNotEmpty ? allMembers.length : 0;

    int mon = allLogs.where((l) => _isDayEvangelised(l, 'Mon', 'mon_part')).length;
    int tue = allLogs.where((l) => _isDayEvangelised(l, 'Tue', 'tue_part')).length;
    int wed = allLogs.where((l) => _isDayEvangelised(l, 'Wed', 'wed_part')).length;
    int thu = allLogs.where((l) => _isDayEvangelised(l, 'Thu', 'thu_part')).length;
    int fri = allLogs.where((l) => _isDayEvangelised(l, 'Fri', 'fri_part')).length;
    int sat = allLogs.where((l) => _isDayEvangelised(l, 'Sat', 'sat_part')).length;
    int sun = allLogs.where((l) => _isDayEvangelised(l, 'Sun', 'sun_part')).length;

    int maxDay = math.max(mon, math.max(tue, math.max(wed, math.max(thu, math.max(fri, math.max(sat, sun))))));
    totalSaints = math.max(totalSaints, maxDay);

    return _EvangelismUnitStat(
      unitName: 'General total',
      totalSaints: totalSaints,
      mon: mon,
      tue: tue,
      wed: wed,
      thu: thu,
      fri: fri,
      sat: sat,
      sun: sun,
    );
  }

  // --- UI: TABLE SUMMARY (17 Columns) ---
  Widget _buildEvangelismTable(List<_EvangelismUnitStat> stats, _EvangelismUnitStat totalStat) {
    const double rh = 24.0;
    const double hh = 28.0;

    final Map<int, TableColumnWidth> colWidths = {
      0: const FixedColumnWidth(125),
      1: const FixedColumnWidth(60),
      2: const FixedColumnWidth(68),
      3: const FixedColumnWidth(50),
      4: const FixedColumnWidth(48),
      5: const FixedColumnWidth(50),
      6: const FixedColumnWidth(48),
      7: const FixedColumnWidth(50),
      8: const FixedColumnWidth(48),
      9: const FixedColumnWidth(50),
      10: const FixedColumnWidth(48),
      11: const FixedColumnWidth(50),
      12: const FixedColumnWidth(48),
      13: const FixedColumnWidth(50),
      14: const FixedColumnWidth(48),
      15: const FixedColumnWidth(50),
      16: const FixedColumnWidth(48),
    };

    List<String> headers = [
      widget.activeUnitLabel.isNotEmpty ? widget.activeUnitLabel : "Unit name",
      "Saints", "Weekly avg",
      "Mon", "Mon %", "Tue", "Tue %", "Wed", "Wed %",
      "Thu", "Thu %", "Fri", "Fri %", "Sat", "Sat %", "Sun", "Sun %"
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: colWidths,
        border: TableBorder.all(color: Colors.black, width: 1.0),
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
                        fontSize: 9.0,
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

          // General Total Summary Row (Prominent Top Row)
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFEDE7F6)),
            children: [
              _cellText("General total", 26.0, isBold: true, color: pPurple, align: TextAlign.left, padLeft: 6),
              _cellText("${totalStat.totalSaints}", 26.0, isBold: true),
              _cellText(totalStat.weeklyAvg.toStringAsFixed(1), 26.0, isBold: true, color: pPurple),
              _cellText("${totalStat.mon}", 26.0, isBold: true),
              _cellPercent(totalStat.monPct, 26.0, pPurple, isBold: true),
              _cellText("${totalStat.tue}", 26.0, isBold: true),
              _cellPercent(totalStat.tuePct, 26.0, pPurple, isBold: true),
              _cellText("${totalStat.wed}", 26.0, isBold: true),
              _cellPercent(totalStat.wedPct, 26.0, pPurple, isBold: true),
              _cellText("${totalStat.thu}", 26.0, isBold: true),
              _cellPercent(totalStat.thuPct, 26.0, pPurple, isBold: true),
              _cellText("${totalStat.fri}", 26.0, isBold: true),
              _cellPercent(totalStat.friPct, 26.0, pPurple, isBold: true),
              _cellText("${totalStat.sat}", 26.0, isBold: true),
              _cellPercent(totalStat.satPct, 26.0, Colors.blue[900]!, isBold: true),
              _cellText("${totalStat.sun}", 26.0, isBold: true),
              _cellPercent(totalStat.sunPct, 26.0, Colors.blue[900]!, isBold: true),
            ],
          ),

          // Child Data Rows (Only when drilled down)
          ...stats.asMap().entries.map((entry) {
            int idx = entry.key;
            _EvangelismUnitStat u = entry.value;
            final isEven = idx.isEven;
            final rowColor = isEven ? Colors.white : const Color(0xFFF8FAFC);

            return TableRow(
              decoration: BoxDecoration(color: rowColor),
              children: [
                _cellText(u.unitName, rh, isBold: true, align: TextAlign.left, padLeft: 6),
                _cellText("${u.totalSaints}", rh),
                _cellText(u.weeklyAvg.toStringAsFixed(1), rh, color: pPurple, isBold: true),
                _cellText("${u.mon}", rh),
                _cellPercent(u.monPct, rh, pPurple),
                _cellText("${u.tue}", rh),
                _cellPercent(u.tuePct, rh, pPurple),
                _cellText("${u.wed}", rh),
                _cellPercent(u.wedPct, rh, pPurple),
                _cellText("${u.thu}", rh),
                _cellPercent(u.thuPct, rh, pPurple),
                _cellText("${u.fri}", rh),
                _cellPercent(u.friPct, rh, pPurple),
                _cellText("${u.sat}", rh),
                _cellPercent(u.satPct, rh, Colors.blue[800]!),
                _cellText("${u.sun}", rh),
                _cellPercent(u.sunPct, rh, Colors.blue[800]!),
              ],
            );
          }),
        ],
      ),
    );
  }

  // --- UI: RANKING LIST ---
  Widget _buildRankingList(List<_EvangelismUnitStat> stats, bool isTop) {
    if (stats.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text("No ranking data found", style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final sorted = List<_EvangelismUnitStat>.from(stats);
    sorted.sort((a, b) => isTop ? b.weeklyAvgPct.compareTo(a.weeklyAvgPct) : a.weeklyAvgPct.compareTo(b.weeklyAvgPct));
    final displayList = sorted.take(5).toList();

    return Column(
      children: displayList.asMap().entries.map((entry) {
        int rank = entry.key + 1;
        _EvangelismUnitStat item = entry.value;
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
              Icon(isTop ? Icons.trending_up_rounded : Icons.priority_high_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(item.unitName, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          subtitle: Text(
            "Saints: ${item.totalSaints} | Wkly Avg: ${item.weeklyAvg.toStringAsFixed(1)}",
            style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
          trailing: Text(
            "${item.weeklyAvgPct.toStringAsFixed(1)}%",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: color),
          ),
        );
      }).toList(),
    );
  }

  // --- UI: DYNAMIC UNIT SELECTOR PILLS ---
  Widget _buildUnitPillBar(List<_EvangelismUnitStat> stats) {
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

  // --- UI: DYNAMIC 7-DAY BREAKDOWN CHART ---
  Widget _buildEvangelismChart(List<_EvangelismUnitStat> stats, _EvangelismUnitStat totalStat) {
    _EvangelismUnitStat active = totalStat;
    if (_selectedChartUnit != 'General total') {
      active = stats.firstWhere((s) => s.unitName == _selectedChartUnit, orElse: () => totalStat);
    }

    final List<double> percentages = [
      active.monPct,
      active.tuePct,
      active.wedPct,
      active.thuPct,
      active.friPct,
      active.satPct,
      active.sunPct,
    ];

    final List<int> counts = [
      active.mon,
      active.tue,
      active.wed,
      active.thu,
      active.fri,
      active.sat,
      active.sun,
    ];

    const List<String> days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stats.isNotEmpty) _buildUnitPillBar(stats),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Displaying: ${active.unitName} (${active.totalSaints} Saints)",
                style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.redAccent, width: 0.5),
                ),
                child: Text(
                  "Target: ${widget.targetValue.toInt()}%",
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          height: 320,
          child: BarChart(
            BarChartData(
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
                  bottom: BorderSide(color: Colors.black, width: 1.0),
                  left: BorderSide(color: Colors.black, width: 1.0),
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: widget.targetValue,
                    color: Colors.redAccent,
                    strokeWidth: 1.5,
                    dashArray: [5, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      labelResolver: (_) => '${widget.targetValue.toInt()}% Target',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 20,
                    getTitlesWidget: (val, meta) => Text(
                      "${val.toInt()}%",
                      style: GoogleFonts.merriweather(fontSize: 9, color: Colors.blueGrey),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (val, meta) {
                      int idx = val.toInt();
                      if (idx < 0 || idx >= days.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          days[idx],
                          style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final day = days[group.x.toInt()];
                    final count = counts[group.x.toInt()];
                    final pct = rod.toY.toStringAsFixed(1);
                    return BarTooltipItem(
                      "$day\n$count Evangelised ($pct%)",
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    );
                  },
                ),
              ),
              barGroups: List.generate(7, (i) {
                final pct = percentages[i];
                final isAboveTarget = pct >= widget.targetValue;
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: pct,
                      color: isAboveTarget ? pPurple : const Color(0xFF7E57C2),
                      width: 22,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  // --- PDF REPORT EXPORT ---
  Future<void> _exportPdf(List<_EvangelismUnitStat> stats, _EvangelismUnitStat totalStat) async {
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
                  pw.Text('Evangelism Daily Participation Report (All Saints)',
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
                'Wkly Avg',
                'Mon',
                'Mon %',
                'Tue',
                'Tue %',
                'Wed',
                'Wed %',
                'Thu',
                'Thu %',
                'Fri',
                'Fri %',
                'Sat',
                'Sat %',
                'Sun',
                'Sun %',
              ],
              data: [
                [
                  'General Total',
                  '${totalStat.totalSaints}',
                  totalStat.weeklyAvg.toStringAsFixed(1),
                  '${totalStat.mon}',
                  '${totalStat.monPct.toStringAsFixed(0)}%',
                  '${totalStat.tue}',
                  '${totalStat.tuePct.toStringAsFixed(0)}%',
                  '${totalStat.wed}',
                  '${totalStat.wedPct.toStringAsFixed(0)}%',
                  '${totalStat.thu}',
                  '${totalStat.thuPct.toStringAsFixed(0)}%',
                  '${totalStat.fri}',
                  '${totalStat.friPct.toStringAsFixed(0)}%',
                  '${totalStat.sat}',
                  '${totalStat.satPct.toStringAsFixed(0)}%',
                  '${totalStat.sun}',
                  '${totalStat.sunPct.toStringAsFixed(0)}%',
                ],
                ...stats.map((u) => [
                      u.unitName,
                      '${u.totalSaints}',
                      u.weeklyAvg.toStringAsFixed(1),
                      '${u.mon}',
                      '${u.monPct.toStringAsFixed(0)}%',
                      '${u.tue}',
                      '${u.tuePct.toStringAsFixed(0)}%',
                      '${u.wed}',
                      '${u.wedPct.toStringAsFixed(0)}%',
                      '${u.thu}',
                      '${u.thuPct.toStringAsFixed(0)}%',
                      '${u.fri}',
                      '${u.friPct.toStringAsFixed(0)}%',
                      '${u.sat}',
                      '${u.satPct.toStringAsFixed(0)}%',
                      '${u.sun}',
                      '${u.sunPct.toStringAsFixed(0)}%',
                    ]),
              ],
              headerStyle: pw.TextStyle(font: fontBold, fontSize: 7.0, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.purple900),
              cellStyle: pw.TextStyle(font: font, fontSize: 7.0),
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

  // --- CELL HELPERS ---
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

  // --- SECTION CONTAINER WITH DARK BORDER ---
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
    final cascadedMembers = _masterMembers.where((m) => _matchesCascade(m)).toList();
    final cascadedLogs = widget.logs.where((l) {
      if (l is! Map) return false;
      return _matchesCascade(Map<String, dynamic>.from(l));
    }).toList();

    final List<_EvangelismUnitStat> unitStats = _calculateStats();
    final _EvangelismUnitStat totalStat = _calculateTotalStat(cascadedLogs, cascadedMembers);

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
            "Top performing evangelism units",
            _buildRankingList(unitStats, true),
            context,
          ),
          _section(
            "Units requiring evangelism support",
            _buildRankingList(unitStats, false),
            context,
          ),
        ] else ...[
          _section(
            "Evangelism daily summary",
            _buildEvangelismTable(unitStats, totalStat),
            context,
            onPdf: () => _exportPdf(unitStats, totalStat),
          ),
          const SizedBox(height: 10),
          _section(
            "7-day breakdown (%)",
            _buildEvangelismChart(unitStats, totalStat),
            context,
          ),
        ],
      ],
    );
  }
}