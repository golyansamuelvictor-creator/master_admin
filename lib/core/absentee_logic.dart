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
        // Search across all unit levels (Cell Group, Team, Dept, Sub-Loc, Loc)
        try {
          final res = await _supabase.from('members').select().or(
            'cell_group.eq.$unitName,team.eq.$unitName,department.eq.$unitName,sub_location.eq.$unitName,location.eq.$unitName,cell_number.eq.$unitName,team_number.eq.$unitName,current_dept.eq.$unitName,sublocation.eq.$unitName'
          );
          members = res as List;
        } catch (_) {
          // Fallback if .or syntax or column doesn't match
          try {
            final res = await _supabase.from('members').select().eq('cell_group', unitName);
            members = res as List;
          } catch (_) {
            final res = await _supabase.from('members').select().eq('cell_number', unitName);
            members = res as List;
          }
        }
      }

      if (members.isEmpty) return [];

      // 2. Fetch last 8 weeks of logs (Filters like .eq() come BEFORE .order())
      List<dynamic> allLogs = [];
      try {
        final logsQuery = _supabase.from(table).select();
        final logsRes = await (fetchAll
            ? logsQuery.order('report_date', ascending: false).limit(members.length * 8)
            : logsQuery.eq('unit_name', unitName).order('report_date', ascending: false).limit(members.length * 8));
            
        allLogs = logsRes as List;

        // If unit_name in logs returned empty, fallback to fetching recent logs
        if (allLogs.isEmpty && !fetchAll) {
          final fallbackLogs = await _supabase
              .from(table)
              .select()
              .order('report_date', ascending: false)
              .limit(members.length * 8);
          allLogs = fallbackLogs as List;
        }
      } catch (_) {
        allLogs = [];
      }

      // 3. Fetch Maintenance/Recovery History for this duty
      final recoveryRes = await _supabase
          .from('member_recovery_logs')
          .select()
          .eq('duty_name', duty)
          .order('contact_date', ascending: false);
      List<dynamic> allRecovery = recoveryRes as List;

      List<Map<String, dynamic>> results = [];

      for (var member in members) {
        // Filter logs for this specific member
        var memberLogs = allLogs.where((l) => l['member_id'] == member['id']).toList();
        
        int missedCount = 0;
        String lastReason = "No reason logged";

        // Calculate frequency and get the most recent reason
        for (var log in memberLogs) {
          if (_checkIfMissed(duty, log)) {
            missedCount++;
            if (lastReason == "No reason logged") {
               lastReason = log['reason_notes'] ?? log['situation_notes'] ?? log['visitation_reason'] ?? "No reason logged";
            }
          }
        }

        // 4. Find the most recent Recovery Action for this member
        var lastCare = allRecovery.firstWhere(
          (r) => r['member_id'] == member['id'], 
          orElse: () => null
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
      return results;
    } catch (e) { 
      return []; 
    }
  }

  static bool _checkIfMissed(String duty, dynamic log) {
    if (duty.contains('Offering')) return log['offering_tithe'] == "No";
    if (duty.contains('Evangelism')) return log['mon_part'] == "No";
    if (duty.contains('Morning Light')) return log['mon_ml'] == "ML Didn't";
    
    // Default attendance check
    var status = (log['status_detail'] ?? log['attendance_realtime'] ?? "").toString();
    return ["Absentee", "CS Absentee", "ASE Absence", "Not Visited", "No"].contains(status);
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