// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AbsenteeLogic {
  static final _supabase = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> getDetailedInterventionList({
    required String duty,
    required String unitName,
    String? unitType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      String table = _getTableName(duty);
      String dbLookupName = duty == "Evangelism Part" ? "Evangelism" : duty;

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
      List<dynamic> members = [];
      bool fetchAll = unitName.isEmpty || unitName.toLowerCase() == 'all';

      if (fetchAll) {
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

      if (members.isEmpty) return [];

      // 3. Fetch logs within selected date range
      // Only this unit's members' logs. (Before, the latest N rows of the whole
      // church were read, so members whose report wasn't among them showed up
      // as false absentees.)
      List<dynamic> allLogs = [];
      try {
        final ids = members.map((m) => m['id']).where((id) => id != null).toList();
        for (int i = 0; i < ids.length; i += 150) {
          final chunk = ids.sublist(i, (i + 150 > ids.length) ? ids.length : i + 150);
          var query = _supabase.from(table).select().inFilter('member_id', chunk);
          if (startDate != null) {
            query = query.gte('report_date', DateFormat('yyyy-MM-dd').format(startDate));
          }
          if (endDate != null) {
            query = query.lte('report_date', DateFormat('yyyy-MM-dd').format(endDate));
          }
          final logsRes = await query.order('report_date', ascending: false).limit(5000);
          allLogs.addAll(logsRes as List);
        }
      } catch (e) {
        allLogs = [];
      }

      // 4. Fetch Recovery/Care History
      List<dynamic> allRecovery = [];
      try {
        final recoveryRes = await _supabase
            .from('member_recovery_logs')
            .select()
            .eq('duty_name', duty)
            .order('contact_date', ascending: false);
        allRecovery = recoveryRes as List;
      } catch (_) {
        allRecovery = [];
      }

      List<Map<String, dynamic>> results = [];

      // Sessions held by this unit in the period (a date anyone reported on).
      // A member with no report for one of them is counted absent too.
      final Set<String> sessionDates = {
        for (final l in allLogs)
          if ((l['report_date'] ?? '').toString().isNotEmpty) (l['report_date']).toString().split('T').first,
      };

      for (var member in members) {
        final memberIdStr = member['id']?.toString() ?? "";
        if (memberIdStr.isEmpty) continue;

        var memberLogs = allLogs.where((l) {
          final logMemberId = (l['member_id'] ?? l['id_member'])?.toString();
          return logMemberId == memberIdStr;
        }).toList();
        
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

        for (var log in memberLogs) {
          // Check if log represents an Absence (a blank answer counts too)
          if (_checkIfMissedWithLabels(duty, log, absenteeLabels) || _isBlankLog(duty, log)) {
            missedCount++;
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

        var lastCare = allRecovery.firstWhere(
          (r) => r['member_id']?.toString() == memberIdStr, 
          orElse: () => null,
        );

        if (notReported > 0) {
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
          });
        }
      }

      results.sort((a, b) => (b['missed_count'] as int).compareTo(a['missed_count'] as int));
      return results;
    } catch (e) { 
      return []; 
    }
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

  static const List<String> _answerKeys = [
    'status_detail', 'attendance_realtime', 'attendance_makeup', 'attendance_pre', 'mon_part', 'mon_ml',
  ];

  /// A report row whose answer fields are all empty (nothing was chosen).
  static bool _isBlankLog(String duty, dynamic log) {
    if (log == null || log is! Map) return false;
    if (duty.contains('Offering') || duty.contains('Visitation')) return false;
    final present = _answerKeys.where((k) => log.containsKey(k)).toList();
    if (present.isEmpty) return false;
    return present.every((k) => (log[k] ?? '').toString().trim().isEmpty);
  }

  static bool _looksAbsent(String lower) =>
      lower.contains('absent') || lower.contains('absence') || lower.contains('didn') || lower.contains('did not') ||
      lower.contains('not part') || lower.contains('no part') || lower.contains('missed') || lower == 'no' ||
      lower == 'none' || lower == 'nil' || lower == '-';

  static bool _checkIfMissedWithLabels(String duty, dynamic log, Set<String> absenteeLabels) {
    if (log == null || log is! Map) return false;

    if (duty.contains('Offering')) return log['offering_tithe'] == "No";

    final candidates = [
      log['status_detail'],
      log['attendance_realtime'],
      log['attendance_makeup'],
      log['attendance_pre'],
      log['mon_part'],
      log['mon_ml'],
    ];

    for (var cand in candidates) {
      if (cand == null) continue;
      final str = cand.toString().trim();
      if (str.isEmpty) continue;
      for (var abs in absenteeLabels) {
        if (abs.toLowerCase() == str.toLowerCase()) return true;
      }
      if (_looksAbsent(str.toLowerCase())) return true;
    }
    return false;
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