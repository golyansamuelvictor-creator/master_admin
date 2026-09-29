// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

class ComplianceLogic {
  static final _supabase = Supabase.instance.client;

  // ==========================================
  // 1. GET MASTER LIST OF UNITS
  // ==========================================
  // Fetches the names of all active units (Cells, Teams, or Depts)
  static Future<List<String>> fetchMasterUnitList(String unitLevel) async {
    try {
      String table = '';
      String column = 'name';

      if (unitLevel == 'Cell') {
        table = 'cell_groups';
      } else if (unitLevel == 'Team') {
        table = 'teams';
      } else if (unitLevel == 'Dept') {
        table = 'departments';
      } else {
        table = 'locations';
        column = 'locations';
      }

      final res = await _supabase.from(table).select(column);
      return res.map((e) => e[column].toString()).toList();
    } catch (e) {
      debugPrint("Error fetching unit list: $e");
      return [];
    }
  }

  // ==========================================
  // 2. IDENTIFY MISSING REPORTS
  // ==========================================
  // Compares the Master List against who actually saved a log
  static Future<List<String>> getMissingReports({
    required String logTable, // e.g., 'logs_attendance'
    required String unitLevel, // e.g., 'Cell' or 'Team'
    required DateTime date,
  }) async {
    final String dateStr = DateFormat('yyyy-MM-dd').format(date);

    try {
      // 1. Get the list of every unit that SHOULD report
      List<String> masterList = await fetchMasterUnitList(unitLevel);

      // 2. Get the list of units that ACTUALLY reported in this specific table
      final List<dynamic> submittedData = await _supabase
          .from(logTable)
          .select('unit_name')
          .eq('report_date', dateStr);

      // Extract only the unique names of units that submitted
      Set<String> submittedNames = submittedData
          .map((e) => e['unit_name'].toString())
          .toSet();

      // 3. Subtract submitted units from the master list to find the "Gaps"
      List<String> missingUnits = masterList
          .where((unit) => !submittedNames.contains(unit))
          .toList();

      return missingUnits;
    } catch (e) {
      debugPrint("Compliance Logic Error: $e");
      return [];
    }
  }

  // ==========================================
  // 3. CALCULATE COMPLIANCE PERCENTAGE
  // ==========================================
  // Returns a number like 85.5 for 85.5% compliance
  static Future<double> calculateComplianceRate({
    required String logTable,
    required String unitLevel,
    required DateTime date,
  }) async {
    List<String> masterList = await fetchMasterUnitList(unitLevel);
    List<String> missing = await getMissingReports(
      logTable: logTable,
      unitLevel: unitLevel,
      date: date,
    );

    if (masterList.isEmpty) return 0.0;

    int totalCount = masterList.length;
    int submittedCount = totalCount - missing.length;

    return (submittedCount / totalCount) * 100;
  }
}