// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'group_scope.dart';
import 'compilation_rules.dart' show CompStatus;
import 'package:master_admin/core/offering_categories.dart';

class AbsenteeLogic {
  static final _supabase = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> getDetailedInterventionList({
    required String duty,
    required String unitName,
    String? unitType,
    DateTime? startDate,
    DateTime? endDate,
    // The leader's whole unit path, e.g. {location, sub_location, department,
    // team, cell_group}; only the levels of the role are given. An empty map
    // means the whole church. (Matching by one unit name mixed units that
    // share a name: every "Cell 3" or "팀1" in the church.)
    Map<String, String>? scope,
    // Church-wide group leaders (장년회, 부녀회 ...): their group across the church
    String? group,
    // Service Attendance: absentees of the pre-attendance check (true) or of
    // real-time attendance (false)
    bool pre = false,
    // One day of the duty (as in the entry form: "Sunday", "Wednesday",
    // "Mon" ...); null = every day of the period
    String? day,
    // Offering: one kind of offering (its logs_offering column) and one week
    // of the month (1–5). Apart from weekly kinds, an offering counts for the
    // whole month: given in week 1, still counted in weeks 2–5.
    String? offeringColumn,
    int? offeringWeek,
  }) async {
    try {
      String table = _getTableName(duty);
      String dbLookupName = duty == "Evangelism Part" ? "Evangelism" : duty;
      // the members load while the options are read
      final Future<List<dynamic>> membersFuture = scopedMembers(unitName: unitName, unitType: unitType, scope: scope, group: group).catchError((_) => <dynamic>[]);

      // 1. Fetch OFFICIAL styles & absentee options directly from entry_field_options table
      List<dynamic> rawOptions = [];
      try {
        final optRes = await _supabase
            .from('entry_field_options')
            .select('field_key, option_label, sort_order')
            .eq('sheet_name', dbLookupName)
            .eq('is_active', true)
            .order('sort_order');
        rawOptions = optRes as List;
      } catch (_) {
        rawOptions = [];
      }

      // Identify absentee labels vs valid attendance styles from DB
      final Set<String> absenteeLabels = {};
      final Set<String> validStyleLabels = {};

      for (var opt in rawOptions) {
        final label = (opt['option_label'] ?? '').toString().trim();
        final fieldKey = (opt['field_key'] ?? '').toString().trim();
        if (label.isEmpty) continue;

        // Skip non-attendance fields (months, reasons, levels)
        if (fieldKey == 'month' || fieldKey == 'level_status' || fieldKey == 'visitation_reason') continue;

        final lower = label.toLowerCase();
        if (lower.contains('absent') || 
            lower.contains('didn') || 
            lower == 'no' || 
            lower.contains('not visited') || 
            lower.contains('missed')) {
          absenteeLabels.add(label);
        } else {
          validStyleLabels.add(label);
        }
      }

      // Default fallbacks if DB table is unseeded
      if (absenteeLabels.isEmpty) {
        absenteeLabels.addAll(["Absentee", "CS Absentee", "ASE Absence", "Not Visited", "No", "ML Didn't", "WE Missed", "Did Not Evangelize"]);
      }
      if (validStyleLabels.isEmpty) {
        validStyleLabels.addAll(["In-person", "On-line", "Call", "Meet", "Summary", "CS In-Person", "CS Online", "ASE In-person", "ASE Online", "Active", "Evangelised", "WE Attended", "ML Did"]);
      }

      // 2. Fetch members
      final List<dynamic> members = await membersFuture;

      if (members.isEmpty) return [];

      // 3. Fetch logs within selected date range
      // Only this unit's members' logs. (Before, the latest N rows of the whole
      // church were read, so members whose report wasn't among them showed up
      // as false absentees.)
      // Logs and care history are read 150 members at a time, 6 requests
      // at once (one after another took ~20 round trips for 3000 members).
      final ids = members.map((m) => m['id']).where((id) => id != null).toList();
      final chunks = <List<dynamic>>[
        for (int i = 0; i < ids.length; i += 150) ids.sublist(i, (i + 150 > ids.length) ? ids.length : i + 150),
      ];
      Future<List<dynamic>> inParallel(Future<List<dynamic>> Function(List<dynamic> chunk) load) async {
        final out = <dynamic>[];
        for (int i = 0; i < chunks.length; i += 6) {
          final parts = await Future.wait(chunks.skip(i).take(6).map(load));
          for (final p in parts) {
            out.addAll(p);
          }
        }
        return out;
      }

      final careFuture = inParallel((chunk) async {
        try {
          return await _supabase
              .from('member_recovery_logs')
              .select('member_id, outcome, contact_date, summary')
              .eq('duty_name', duty)
              .inFilter('member_id', chunk)
              .order('contact_date', ascending: false);
        } catch (_) {
          return const [];
        }
      });

      List<dynamic> allLogs = [];
      try {
        allLogs = await inParallel((chunk) async {
          var query = _supabase.from(table).select().inFilter('member_id', chunk);
          if (startDate != null) {
            query = query.gte('report_date', DateFormat('yyyy-MM-dd').format(startDate));
          }
          if (endDate != null) {
            query = query.lte('report_date', DateFormat('yyyy-MM-dd').format(endDate));
          }
          return await query.order('report_date', ascending: false).limit(5000);
        });
      } catch (e) {
        allLogs = [];
      }

      // One day of the duty / one week of the month
      if (day != null && day.isNotEmpty) {
        allLogs = allLogs.where((l) => dayOf(duty, l) == day).toList();
      }
      final bool isOffering = duty.contains('Offering');
      OfferingCategory? cat;
      if (isOffering && offeringColumn != null) {
        for (final c in OfferingCategories.list) {
          if (c.column == offeringColumn) cat = c;
        }
      }
      final bool cumulative = isOffering && offeringColumn != null && !(cat?.weekly ?? offeringColumn == 'offering_weekly');
      if (isOffering && offeringWeek != null) {
        allLogs = allLogs.where((l) => cumulative ? weekOfMonth(l) <= offeringWeek : weekOfMonth(l) == offeringWeek).toList();
      }

      // 4. Recovery/Care History (newest first), by member
      final Map<String, dynamic> lastCareOf = {};
      for (final r in await careFuture) {
        lastCareOf.putIfAbsent(r['member_id']?.toString() ?? '', () => r);
      }
      // each member's logs, newest first (looking them up per member in the
      // whole list was members × logs comparisons: very slow for big units)
      final Map<String, List<dynamic>> logsOf = {};
      for (final l in allLogs) {
        logsOf.putIfAbsent((l['member_id'] ?? l['id_member'])?.toString() ?? '', () => []).add(l);
      }

      List<Map<String, dynamic>> results = [];

      // Sessions held by this unit in the period (a date anyone reported on).
      // A member with no report for one of them is counted absent too.
      // A date counts as a session only when a fair share of the unit was
      // reported that day; one stray entry (a late make-up, a single member
      // reported on a Tuesday) used to mark everybody else absent.
      final Map<String, Set<String>> reportedOn = {};
      for (final l in allLogs) {
        final d = (l['report_date'] ?? '').toString().split('T').first;
        if (d.isEmpty) continue;
        reportedOn.putIfAbsent(d, () => {}).add((l['member_id'] ?? '').toString());
      }
      final int needed = members.length < 5 ? 1 : (members.length * 0.3).ceil();
      final Set<String> sessionDates = {
        for (final e in reportedOn.entries)
          if (e.value.length >= needed) e.key,
      };

      for (var member in members) {
        final memberIdStr = member['id']?.toString() ?? "";
        if (memberIdStr.isEmpty) continue;

        final memberLogs = logsOf[memberIdStr] ?? const [];
        
        int missedCount = 0;
        String lastReason = "No reason logged";
        final Map<String, int> styleCounts = {
          for (var s in validStyleLabels) s: 0,
        };
        final Set<String> memberObservedStyles = {};

        final Set<String> reportedDates = {
          for (final l in memberLogs) (l['report_date'] ?? '').toString().split('T').first,
        };
        final int notReported = sessionDates.difference(reportedDates).length;

        final List<String> reasons = []; // the last (up to 4) reasons given when missed
        for (var log in memberLogs) {
          // Check if log represents an Absence (a blank answer counts too)
          final bool missed = isOffering && offeringColumn != null
              ? !(OfferingCategories.amount(log[offeringColumn]) > 0 || CompStatus.isPositive(log[offeringColumn]))
              : (_checkIfMissedWithLabels(duty, log, absenteeLabels, pre: pre) || _isBlankLog(duty, log, pre: pre));
          if (missed) {
            missedCount++;
            final why = _reasonOf(log);
            if (why.isNotEmpty && reasons.length < 4) reasons.add(why);
            if (lastReason == "No reason logged") {
              lastReason = log['reason_notes'] ?? 
                           log['situation_notes'] ?? 
                           log['visitation_reason'] ?? 
                           "No reason logged";
            }
          } else {
            // Find which valid attendance style matches this log
            String matchedStyle = _matchLogToStyle(log, validStyleLabels);
            if (matchedStyle.isNotEmpty) {
              memberObservedStyles.add(matchedStyle);
              styleCounts[matchedStyle] = (styleCounts[matchedStyle] ?? 0) + 1;
            }
          }
        }

        final lastCare = lastCareOf[memberIdStr];

        if (cumulative) {
          // given at least once in the period (up to the chosen week): offered
          final gave = memberLogs.any((l) => OfferingCategories.amount(l[offeringColumn]) > 0 || CompStatus.isPositive(l[offeringColumn]));
          missedCount = gave ? 0 : 1;
          if (!gave && lastReason == "No reason logged") lastReason = "Did not offer in the period";
        } else if (notReported > 0) {
          missedCount += notReported;
          if (lastReason == "No reason logged") lastReason = "Not reported / did not participate";
        }

        // Include members who missed at least once in this period
        if (missedCount > 0) {
          // If member has no positive styles logged in period, provide all valid styles with 0 count
          final availableStyles = memberObservedStyles.isNotEmpty 
              ? memberObservedStyles.toList() 
              : validStyleLabels.toList();

          results.add({
            'member': member,
            'missed_count': missedCount,
            'last_reason': lastReason,
            'service_styles': availableStyles,
            'all_duty_styles': validStyleLabels.toList(),
            'style_counts': styleCounts,
            'last_recovery_outcome': lastCare?['outcome'] ?? "No Care Logged",
            'maintenance_status': lastCare?['outcome'] ?? "Pending Care",
            'last_contact_date': lastCare?['contact_date'] ?? "Never",
            'maintenance_note': lastCare?['summary'] ?? "No maintenance notes yet.",
            'reasons': reasons,
            'sessions': sessionDates.length,
            'weeks': {for (final d in sessionDates) _weekKey(d)}.length,
          });
        }
      }

      results.sort((a, b) => (b['missed_count'] as int).compareTo(a['missed_count'] as int));
      return results;
    } catch (e) { 
      return []; 
    }
  }

  /// The members of the leader's units (the same choice as the absentee
  /// lists), 1000 at a time.
  static Future<List<dynamic>> scopedMembers({
    required String unitName,
    String? unitType,
    Map<String, String>? scope,
    String? group,
  }) async {
    List<dynamic> members = [];
      bool fetchAll = unitName.isEmpty || unitName.toLowerCase() == 'all';
      const cols = 'id, english_name, duty, location, sub_location, department, team, cell_group';

      // All rows, 1000 at a time (a single request stops at 1000 members)
      Future<List<dynamic>> paged(PostgrestFilterBuilder<List<Map<String, dynamic>>> Function() q) async {
        final out = <dynamic>[];
        for (int from = 0;; from += 1000) {
          final page = await q().order('english_name').range(from, from + 999);
          out.addAll(page);
          if (page.length < 1000) break;
        }
        return out;
      }

      if (group != null && group.isNotEmpty) {
        members = await paged(() => GroupScope.filter(_supabase.from('members').select(cols), group));
      } else if (scope != null) {
        members = await paged(() {
          var q = _supabase.from('members').select(cols);
          scope.forEach((col, val) {
            final v = val.trim();
            if (col == '@church_level') {
              // a church department's own members (Department only / Church level view)
              q = q.or('location.in.(Church,"Church Workers","Church Main"),location.is.null');
            } else if (v.isNotEmpty && v.toUpperCase() != 'N/A') {
              q = q.eq(col, v);
            }
          });
          return q;
        });
      } else if (fetchAll) {
        final res = await _supabase.from('members').select('id, english_name, duty, location, sub_location, department, team, cell_group');
        members = res as List;
      } else if (unitType != null && unitType.isNotEmpty) {
        final res = await _supabase.from('members').select('id, english_name, duty, location, sub_location, department, team, cell_group').eq(unitType, unitName);
        members = res as List;
      } else {
        try {
          final res = await _supabase.from('members').select('id, english_name, duty, location, sub_location, department, team, cell_group').or(
            'department.eq.$unitName,team.eq.$unitName,cell_group.eq.$unitName,sub_location.eq.$unitName,location.eq.$unitName'
          );
          members = res as List;
        } catch (_) {
          try {
            final allM = await _supabase.from('members').select('id, english_name, duty, location, sub_location, department, team, cell_group');
            members = (allM as List).where((m) {
              final d = (m['department'] ?? '').toString().toLowerCase().trim();
              final t = (m['team'] ?? '').toString().toLowerCase().trim();
              final c = (m['cell_group'] ?? '').toString().toLowerCase().trim();
              final s = (m['sub_location'] ?? '').toString().toLowerCase().trim();
              final l = (m['location'] ?? '').toString().toLowerCase().trim();
              final target = unitName.toLowerCase().trim();
              return d == target || t == target || c == target || s == target || l == target;
            }).toList();
          } catch (_) {
            members = [];
          }
        }
      }

      return members;
  }

  /// The column that holds the duty's day (as chosen in the entry form).
  static String? dayColumn(String duty) {
    if (duty.startsWith('Service Attendance')) return 'service_day';
    if (duty == 'All Saints Education') return 'education_day';
    if (duty.contains('Morning Light')) return 'ml_day';
    if (duty == 'Workers Education') return 'edu_day';
    if (duty == 'Workers Daily Participation') return 'part_day';
    if (duty.startsWith('Evangelism')) return 'evang_day';
    return null;
  }

  /// The days of a duty, as the entry form offers them.
  static List<String> daysOf(String duty) {
    if (duty.startsWith('Service Attendance') || duty == 'All Saints Education') return const ['Sunday', 'Wednesday'];
    if (duty.contains('Morning Light')) return const ['Mon', 'Tue', 'Thu', 'Fri'];
    if (duty == 'Workers Daily Participation') return const ['Mon', 'Tue', 'Thu', 'Fri', 'Sat'];
    if (duty == 'Workers Education' || duty.startsWith('Evangelism')) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return const [];
  }

  /// A report's day: its day column, or (older reports) its date's weekday.
  static String dayOf(String duty, Map log) {
    final col = dayColumn(duty);
    final v = col == null ? '' : (log[col] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
    final d = DateTime.tryParse((log['report_date'] ?? '').toString());
    if (d == null) return '';
    if (duty.startsWith('Service Attendance') || duty == 'All Saints Education') {
      return d.weekday <= DateTime.wednesday ? 'Wednesday' : 'Sunday';
    }
    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
  }

  /// Offering: the week of the month (1–5) of a report.
  static int weekOfMonth(Map log) {
    final w = int.tryParse(RegExp(r'\d+').firstMatch((log['offering_week'] ?? '').toString())?.group(0) ?? '');
    if (w != null && w >= 1 && w <= 5) return w;
    final d = DateTime.tryParse((log['report_date'] ?? '').toString());
    return d == null ? 1 : ((d.day - 1) ~/ 7) + 1;
  }

  static String _weekKey(String date) {
    final d = DateTime.tryParse(date);
    if (d == null) return date;
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return DateFormat('yyyy-MM-dd').format(monday);
  }

  /// What the leader wrote about a miss.
  static String _reasonOf(Map log) {
    for (final k in const ['reason_notes', 'situation_notes', 'correction_note', 'solution_notes', 'strategy_notes']) {
      final v = (log[k] ?? '').toString().trim();
      if (v.isNotEmpty && v.toLowerCase() != 'no reason logged') return v;
    }
    return '';
  }

  // Matches a log row to one of the official valid styles from entry_field_options
  static String _matchLogToStyle(dynamic log, Set<String> validStyles) {
    if (log == null || log is! Map) return "";

    final candidates = [
      log['attendance_realtime'],
      log['status_detail'],
      log['attendance_makeup'],
      log['attendance_pre'],
      log['method'],
      log['place'],
    ];

    for (var cand in candidates) {
      if (cand == null) continue;
      final str = cand.toString().trim();
      for (var style in validStyles) {
        if (style.toLowerCase() == str.toLowerCase()) {
          return style; // Exact match found from entry_field_options!
        }
      }
    }
    return "";
  }

  /// The answer that says whether the member took part, per duty, in order.
  /// Pre-attendance (a plan made before the service) and make-up (done
  /// afterwards) are not the attendance itself. Reading every column before
  /// meant a "No" in pre-attendance or make-up marked members who attended
  /// as absent, so almost the whole name list showed up.
  static List<String> _answerKeysFor(String duty, {bool pre = false}) {
    if (duty.startsWith('Service Attendance')) return pre ? const ['attendance_pre'] : const ['attendance_realtime'];
    if (duty.contains('Morning Light')) return const ['status_detail', 'mon_ml', 'mon_part'];
    return const ['status_detail', 'mon_part', 'mon_ml', 'attendance_realtime'];
  }

  static String _answer(String duty, Map log, {bool pre = false}) {
    for (final k in _answerKeysFor(duty, pre: pre)) {
      final v = (log[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// A report row whose answer is empty (nothing was chosen).
  static bool _isBlankLog(String duty, dynamic log, {bool pre = false}) {
    if (log == null || log is! Map) return false;
    if (duty.contains('Offering') || duty.contains('Visitation')) return false;
    if (!_answerKeysFor(duty, pre: pre).any(log.containsKey)) return false;
    return _answer(duty, log, pre: pre).isEmpty;
  }

  static bool _checkIfMissedWithLabels(String duty, dynamic log, Set<String> absenteeLabels, {bool pre = false}) {
    if (log == null || log is! Map) return false;

    // Offering: missed when nothing was given in any kind of offering
    if (duty.contains('Offering')) return !OfferingCategories.allColumns.any((c) => OfferingCategories.amount(log[c]) > 0 || CompStatus.isPositive(log[c]));

    final str = _answer(duty, log, pre: pre);
    if (str.isEmpty) return false;
    final lower = str.toLowerCase();
    if (absenteeLabels.any((a) => a.toLowerCase() == lower)) return true;
    return CompStatus.isNegative(str);
  }

  static String _getTableName(String duty) {
    switch (duty) {
      case 'Service Attendance Status': return 'logs_service_attendance_status';
      case 'All Saints Education': return 'logs_all_saints_education';
      case 'Cell Group Service': return 'logs_cell_service';
      case 'Offering Status': return 'logs_offering';
      case 'Evangelism Part':
      case 'Evangelism': return 'logs_evangelism';
      case 'Morning Light': return 'logs_morning_light';
      case 'Visitations and Counselling': return 'logs_visitations';
      case 'Workers Education': return 'logs_workers_education';
      case 'Workers Daily Participation': return 'logs_workers_participation';
      default: return 'member_logs';
    }
  }
}