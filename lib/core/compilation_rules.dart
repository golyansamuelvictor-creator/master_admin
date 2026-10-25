// Shared rules for the compilation screen and every compilation module.
//
// One place decides:
//   * which hierarchy level a label like "Sub location status" means
//   * which unit a member or report row belongs to at that level
//   * the order units are listed in (table rows == chart bars == legend)
//   * how many sessions a period contains (for per-session averages)
//   * whether an answer such as "ML Didn't" is a yes or a no
//
// Before this file each module had its own copy of these rules and they
// disagreed (the table grouped one level lower than the chart, and
// "sub location status" was matched as "location status").

class CompLevel {
  CompLevel._();

  static const String church = 'church';
  static const String group = 'group';
  static const String location = 'location';
  static const String subLocation = 'sub_location';
  static const String dept = 'dept';
  static const String team = 'team';
  static const String cell = 'cell';
  static const String member = 'member';

  static const List<String> orderedBOLGroups = ["교역자", "자문회", "장년회", "부녀회", "청년회"];
  static const List<String> orderedLocations = [
    "24Dept", "MOU", "New Location", "Wakiso", "Lubaga", "Busega",
    "Kawempe", "Makerere", "Makindye", "Nakawa", "Mukono", "Entebbe", "UAE"
  ];
  static const List<String> orderedDepartments = ["장년회", "부녀회", "청년회", "신학부", "새신자"];

  /// Normalises a sidebar label ("Sub location status", "Dept status", ...).
  /// Uses startsWith so "sub location status" is never mistaken for "location status".
  static String of(String level) {
    final l = level.trim().toLowerCase();
    if (l.startsWith('church')) return church;
    if (l.startsWith('group')) return group;
    if (l.startsWith('sub location') || l.startsWith('sub-location') || l.startsWith('sub_location')) return subLocation;
    if (l.startsWith('location')) return location;
    if (l.startsWith('dept') || l.startsWith('department')) return dept;
    if (l.startsWith('team')) return team;
    if (l.startsWith('cell')) return cell;
    if (l.startsWith('member')) return member;
    return church;
  }

  /// Human title for the unit column / chart axis at this level.
  static String unitTitle(String level) {
    switch (of(level)) {
      case church:
      case location:
        return 'Locations';
      case group:
        return 'Book of Life';
      case subLocation:
        return 'Sub-locations';
      case dept:
        return 'Departments';
      case team:
        return 'Teams';
      case cell:
        return 'Cell groups';
      case member:
        return 'Members';
    }
    return 'Units';
  }

  // Report rows are grouped by the member's CURRENT unit (the joined `members`
  // map) — the same columns the screen filters on and the headcount uses —
  // and fall back to the unit stored on the report.
  static String _field(dynamic record, List<String> keys) {
    if (record is! Map) return '';
    final nested = record['members'] is Map ? record['members'] as Map : const {};
    for (final k in keys) {
      for (final v in [nested[k], record[k]]) {
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
      }
    }
    return '';
  }

  /// MOU is one location of its own. Its members are stored with
  /// department = 'MOU' and location = an MOU branch (MOUWakiso, MOULubaga ...).
  static const String mou = 'MOU';

  static bool isMouName(String? s) => (s ?? '').trim().toUpperCase().startsWith('MOU');

  static bool isMou(dynamic record) =>
      _field(record, ['department', 'dept', 'guide_dept']).toUpperCase().contains('MOU') ||
      isMouName(_field(record, ['location', 'guide_location']));

  /// Location bucket used by every module: MOU and Church/24부서 rows are grouped.
  static String locationBucket(dynamic record) {
    if (isMou(record)) return mou;
    final loc = _field(record, ['location', 'guide_location']);
    final l = loc.toLowerCase();
    if (l == '24dept' || l == '24부서' || l == 'church' || l == '교회') return '24Dept';
    return loc.isNotEmpty ? loc : 'Other';
  }

  /// The unit a member row or report row belongs to at [level].
  /// BB rows use the guide's unit.
  static String unitKey(dynamic record, String level) {
    String v;
    switch (of(level)) {
      case church:
      case location:
        return locationBucket(record);
      case group:
        v = _field(record, ['book_of_life', 'bol_dept']);
        break;
      case subLocation:
        v = _field(record, ['sub_location', 'guide_sub_location']);
        break;
      case dept:
        v = _field(record, ['department', 'dept', 'guide_dept']);
        break;
      case team:
        v = _field(record, ['team', 'team_number', 'guide_team']);
        break;
      case cell:
        v = _field(record, ['cell_group', 'cell_name', 'guide_cell', 'unit_name']);
        break;
      case member:
        v = _field(record, ['english_name', 'student_name']);
        break;
      default:
        v = '';
    }
    return v.isNotEmpty ? v : 'Other';
  }

  /// Every unit present in members or logs, in a stable order.
  /// The table rows, chart bars and legend must all use this same list.
  static List<String> orderedUnits(Iterable<dynamic> members, Iterable<dynamic> logs, String level) {
    final Set<String> keys = {};
    for (final m in members) {
      keys.add(unitKey(m, level));
    }
    for (final l in logs) {
      keys.add(unitKey(l, level));
    }

    final lv = of(level);
    List<String> preferred = const [];
    if (lv == church || lv == location) preferred = orderedLocations;
    if (lv == group) preferred = orderedBOLGroups;
    if (lv == dept) preferred = orderedDepartments;

    if (lv == group) {
      // Book of Life view only shows the five official groups
      return orderedBOLGroups.where(keys.contains).toList();
    }

    final first = preferred.where(keys.contains).toList();
    final rest = keys.where((k) => !preferred.contains(k) && k != 'Other').toList();
    final sorted = naturalSort(rest);
    return [...first, ...sorted, if (keys.contains('Other')) 'Other'];
  }

  /// Groups [items] by unit for the given level.
  static Map<String, List<dynamic>> groupBy(Iterable<dynamic> items, String level) {
    final Map<String, List<dynamic>> out = {};
    for (final i in items) {
      out.putIfAbsent(unitKey(i, level), () => []).add(i);
    }
    return out;
  }

  /// Sorts "Team 2" before "Team 10".
  static List<String> naturalSort(Iterable<String> items) {
    int numOf(String s) {
      final m = RegExp(r'\d+').firstMatch(s);
      return m != null ? int.parse(m.group(0)!) : 1 << 30;
    }

    final list = List<String>.from(items);
    list.sort((a, b) {
      final na = numOf(a), nb = numOf(b);
      if (na != nb) return na.compareTo(nb);
      return a.compareTo(b);
    });
    return list;
  }
}

class CompPeriod {
  CompPeriod._();

  static DateTime? _date(dynamic record) {
    if (record is! Map) return null;
    final v = record['report_date'];
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  /// Monday of the week the report belongs to, as yyyy-MM-dd.
  static String weekKey(DateTime d) {
    final monday = DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
    return "${monday.year.toString().padLeft(4, '0')}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}";
  }

  static String _fmt(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  static DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  /// Date range of the standard data categories:
  ///   Weekly status  = the last 5 calendar weeks (Mon–Sun), this week included
  ///   Monthly status = the last 4 calendar months, this month included
  ///   Current status = the last 7 days (the screen keeps only the latest session)
  static (DateTime, DateTime) currentRange(String timePeriod, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (timePeriod == 'Weekly status') return (mondayOf(today).subtract(const Duration(days: 28)), today);
    if (timePeriod == 'Monthly status') return (DateTime(today.year, today.month - 3, 1), today);
    return (today.subtract(const Duration(days: 6)), today);
  }

  /// The same-length range just before [currentRange] (for growth comparisons).
  static (DateTime, DateTime) previousRange(String timePeriod, DateTime now) {
    final (start, _) = currentRange(timePeriod, now);
    final end = start.subtract(const Duration(days: 1));
    if (timePeriod == 'Weekly status') return (start.subtract(const Duration(days: 35)), end);
    if (timePeriod == 'Monthly status') return (DateTime(start.year, start.month - 4, 1), end);
    return (start.subtract(const Duration(days: 7)), end);
  }

  /// Trend-chart bucket of a report: its week (Monday) for Weekly status,
  /// its month for Monthly status, otherwise its own date.
  static String bucketKey(dynamic record, String timePeriod) {
    final d = _date(record);
    if (d == null) return '';
    if (timePeriod == 'Weekly status') return weekKey(d);
    if (timePeriod == 'Monthly status') return _fmt(DateTime(d.year, d.month, 1));
    return _fmt(d);
  }

  /// Every bucket of the period, oldest first — Week 1..Week 5 or the 4
  /// months — so weeks without reports still appear on the chart.
  /// Null for Current / Custom (those use the dates that have reports).
  static List<String>? expectedBuckets(String timePeriod, {DateTime? now}) {
    final n = now ?? DateTime.now();
    if (timePeriod == 'Weekly status') {
      final m = mondayOf(n);
      return [for (int i = 4; i >= 0; i--) _fmt(m.subtract(Duration(days: 7 * i)))];
    }
    if (timePeriod == 'Monthly status') {
      return [for (int i = 3; i >= 0; i--) _fmt(DateTime(n.year, n.month - i, 1))];
    }
    return null;
  }

  /// Number of weekly sessions in [logs] (at least 1).
  /// Summary tables divide period totals by this so a 5-week period shows
  /// an average week instead of 5 weeks added against one headcount.
  static int sessionCount(Iterable<dynamic> logs) {
    final Set<String> weeks = {};
    for (final l in logs) {
      final d = _date(l);
      if (d != null) weeks.add(weekKey(d));
    }
    return weeks.isEmpty ? 1 : weeks.length;
  }

  /// Divides a period total by the number of sessions, rounded to whole people.
  static int perSession(int total, int sessions) =>
      sessions <= 1 ? total : (total / sessions).round();
}

class CompStatus {
  CompStatus._();

  static String norm(dynamic v) => (v ?? '').toString().trim().toLowerCase();

  /// True for answers that mean "did not happen":
  /// Absentee, CS Absentee, ASE Absence, ML Didn't, Did Not Evangelize,
  /// WE Missed, Not Visited, No ...
  /// Substring checks such as contains('did') used to count "ML Didn't" as done.
  static bool isNegative(dynamic v) {
    final s = norm(v);
    if (s.isEmpty) return false;
    if (s == 'no' || s == 'n' || s == '0' || s == 'false' || s == 'none' || s == 'x') return true;
    const markers = ['absent', 'absence', 'didn', 'did not', 'didnt', 'not ', 'missed', 'failed', 'unpaid', 'no show'];
    return markers.any(s.contains);
  }

  /// True for any filled-in answer that is not negative.
  static bool isPositive(dynamic v) => norm(v).isNotEmpty && !isNegative(v);
}
