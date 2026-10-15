// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:supabase_flutter/supabase_flutter.dart';
// ignore: unused_import
import 'package:intl/intl.dart';

class AbsenteeLogic {
  static final _supabase = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> getDetailedInterventionList({
    required String duty,
    required String unitName,
    String? unitType, // Optional: 'cell_group', 'team', 'department', 'sub_location', 'location'
  }) async {
    try {
      String table = _getTableName(duty);
      
      // 1. Fetch members across all units OR for a specific unit
      List<dynamic> members = [];
      bool fetchAll = unitName.isEmpty || unitName.toLowerCase() == 'all';

      if (fetchAll) {
        final res = await _supabase.from('members').select();
        members = res as List;
      } else if (unitType != null && unitType.isNotEmpty) {
        final res = await _supabase.from('members').select().eq(unitType, unitName);
        members = res as List;
      } else {
        // Search across all unit levels with both new & old column names
        try {
          final res = await _supabase.from('members').select().or(
            'department.eq.$unitName,team.eq.$unitName,cell_group.eq.$unitName,sub_location.eq.$unitName,location.eq.$unitName'
          );
          members = res as List;
        } catch (_) {
          // Safe fallback: fetch members and match in-memory across all unit columns
          try {
            final allM = await _supabase.from('members').select();
            members = (allM as List).where((m) {
              final d = (m['department'] ?? m['current_dept'] ?? "").toString().toLowerCase().trim();
              final t = (m['team'] ?? m['team_number'] ?? "").toString().toLowerCase().trim();
              final c = (m['cell_group'] ?? m['cell_number'] ?? "").toString().toLowerCase().trim();
              final s = (m['sub_location'] ?? m['sublocation'] ?? "").toString().toLowerCase().trim();
              final l = (m['location'] ?? "").toString().toLowerCase().trim();
              final target = unitName.toLowerCase().trim();
              return d == target || t == target || c == target || s == target || l == target;
            }).toList();
          } catch (_) {
            members = [];
          }
        }
      }

      if (members.isEmpty) return [];

      // 2. Fetch logs safely without crashing on 'unit_name' or 'report_date'
      List<dynamic> allLogs = [];
      try {
        try {
          final logsRes = await _supabase
              .from(table)
              .select()
              .order('report_date', ascending: false)
              .limit(members.length * 12);
          allLogs = logsRes as List;
        } catch (_) {
          try {
            final logsRes = await _supabase
                .from(table)
                .select()
                .order('created_at', ascending: false)
                .limit(members.length * 12);
            allLogs = logsRes as List;
          } catch (_) {
            final logsRes = await _supabase
                .from(table)
                .select()
                .limit(members.length * 12);
            allLogs = logsRes as List;
          }
        }
      } catch (_) {
        allLogs = [];
      }

      // 3. Fetch Maintenance/Recovery History for this duty
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

      for (var member in members) {
        final memberIdStr = member['id']?.toString() ?? "";
        if (memberIdStr.isEmpty) continue;

        // String comparison to prevent int vs UUID type mismatch
        var memberLogs = allLogs.where((l) {
          final logMemberId = (l['member_id'] ?? l['id_member'])?.toString();
          return logMemberId == memberIdStr;
        }).toList();
        
        int missedCount = 0;
        String lastReason = "No reason logged";

        // Calculate frequency and get the most recent reason
        for (var log in memberLogs) {
          if (_checkIfMissed(duty, log)) {
            missedCount++;
            if (lastReason == "No reason logged") {
              lastReason = log['reason_notes'] ?? 
                           log['situation_notes'] ?? 
                           log['visitation_reason'] ?? 
                           "No reason logged";
            }
          }
        }

        // 4. Find the most recent Recovery Action for this member
        var lastCare = allRecovery.firstWhere(
          (r) => r['member_id']?.toString() == memberIdStr, 
          orElse: () => null,
        );

        // Only add to list if they have missed at least once
        if (missedCount > 0) {
          results.add({
            'member': member,
            'missed_count': missedCount,
            'last_reason': lastReason,
            'last_recovery_outcome': lastCare?['outcome'] ?? "No Care Logged",
            'maintenance_status': lastCare?['outcome'] ?? "Pending Care",
            'last_contact_date': lastCare?['contact_date'] ?? "Never",
            'maintenance_note': lastCare?['summary'] ?? "No maintenance notes yet.",
          });
        }
      }

      // Sort descending by missed count
      results.sort((a, b) => (b['missed_count'] as int).compareTo(a['missed_count'] as int));

      return results;
    } catch (e) { 
      return []; 
    }
  }

  /// Uses your EXACT status list: ["Absentee", "CS Absentee", "ASE Absence", "Not Visited", "No"]
  static bool _checkIfMissed(String duty, dynamic log) {
    if (log == null || log is! Map) return false;

    if (duty.contains('Offering')) return log['offering_tithe'] == "No";
    if (duty.contains('Evangelism')) return log['mon_part'] == "No";
    if (duty.contains('Morning Light')) return log['mon_ml'] == "ML Didn't";
    
    // Safely extract status from status_detail, attendance_realtime, or attendance_pre
    // Checks that non-null strings are actually non-empty
    String status = "";
    if (log['status_detail'] != null && log['status_detail'].toString().trim().isNotEmpty) {
      status = log['status_detail'].toString().trim();
    } else if (log['attendance_realtime'] != null && log['attendance_realtime'].toString().trim().isNotEmpty) {
      status = log['attendance_realtime'].toString().trim();
    } else if (log['attendance_pre'] != null && log['attendance_pre'].toString().trim().isNotEmpty) {
      status = log['attendance_pre'].toString().trim();
    }

    // Your exact status list
    const absenteeList = ["Absentee", "CS Absentee", "ASE Absence", "Not Visited", "No"];
    
    // Matches your exact values (case-insensitive and trimmed for reliability)
    return absenteeList.any((val) => val.toLowerCase() == status.toLowerCase());
  }

  static String _getTableName(String duty) {
    switch (duty) {
      case 'Service Attendance Status': return 'logs_service_attendance_status';
      case 'All Saints Education': return 'logs_all_saints_education';
      case 'Cell Group Service': return 'logs_cell_service';
      case 'Offering Status': return 'logs_offering';
      case 'Evangelism Part': return 'logs_evangelism';
      case 'Morning Light': return 'logs_morning_light';
      case 'Visitations and Counselling': return 'logs_visitations';
      case 'Workers Education': return 'logs_workers_education';
      case 'Workers Daily Participation': return 'logs_workers_participation';
      default: return 'member_logs';
    }
  }
}