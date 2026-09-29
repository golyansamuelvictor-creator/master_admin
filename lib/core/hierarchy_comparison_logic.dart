import 'package:supabase_flutter/supabase_flutter.dart';

class HierarchyComparisonLogic {
  static final _supabase = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> getRankings({
    required String tableName,
    required String parentField,
    required String parentValue,
    required String childField,
  }) async {
    try {
      final res = await _supabase.from(tableName)
          .select('*, members!inner(*)')
          .eq('members.$parentField', parentValue);
      
      final List<dynamic> allLogs = res as List;
      Map<String, List<dynamic>> childGroups = {};

      for (var log in allLogs) {
        String childName = log['members'][childField]?.toString() ?? "Unknown";
        childGroups.putIfAbsent(childName, () => []).add(log);
      }

      List<Map<String, dynamic>> results = [];
      childGroups.forEach((name, logs) {
        int tot = logs.length;
        int success = 0;

        // Logic for different tables
        if (tableName.contains('attendance')) {
          success = logs.where((l) => l['attendance_realtime'] == "In-person").length;
        } else if (tableName.contains('offering')) {
          success = logs.where((l) => l['offering_tithe'] == "Yes").length;
        } else {
          // Default success logic for other modules
          success = logs.length; 
        }

        double score = tot > 0 ? (success / tot * 100) : 0;
        results.add({
          'unit_name': name,
          'score': score,
          'total': tot,
          'success': success,
        });
      });

      results.sort((a, b) => b['score'].compareTo(a['score']));
      return results;
    } catch (e) {
      return [];
    }
  }
}