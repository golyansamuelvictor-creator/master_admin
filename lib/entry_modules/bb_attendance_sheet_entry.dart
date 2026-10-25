// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';

class BbAttendanceSheet extends StatefulWidget {
  final List<dynamic> students;
  final DateTime selectedDate;
  final Color pPurple;
  final VoidCallback onSaved;

  const BbAttendanceSheet({
    super.key,
    required this.students,
    required this.selectedDate,
    required this.pPurple,
    required this.onSaved,
  });

  @override
  State<BbAttendanceSheet> createState() => _BbAttendanceSheetState();
}

class _BbAttendanceSheetState extends State<BbAttendanceSheet> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isSaving = false;
  String _searchQuery = "";
  String _selectedCenter = "All";

  // Maps student_id -> {'status': 'Attended' | 'Absent', 'notes': ''}
  final Map<String, Map<String, dynamic>> _attendanceData = {};

  @override
  void initState() {
    super.initState();
    _loadExistingAttendance();
  }

  Future<void> _loadExistingAttendance() async {
    setState(() => _isLoading = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);

    try {
      final res = await _supabase
          .from('logs_bb_attendance')
          .select()
          .eq('report_date', dateStr);

      final Map<String, Map<String, dynamic>> loaded = {};
      for (var row in res) {
        loaded[row['student_id'].toString()] = Map<String, dynamic>.from(row);
      }

      // Pre-fill missing students with 'Absent'
      for (var s in widget.students) {
        final sid = s['id'].toString();
        if (!loaded.containsKey(sid)) {
          loaded[sid] = {'status': 'Absent', 'notes': ''};
        }
      }

      if (mounted) {
        setState(() {
          _attendanceData.addAll(loaded);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading BB attendance: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAttendance() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: You are not logged in."), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);

    List<Map<String, dynamic>> rows = [];
    _attendanceData.forEach((sid, data) {
      rows.add({
        'student_id': sid,
        'report_date': dateStr,
        'status': data['status'] ?? 'Absent',
        'notes': data['notes'],
        'leader_id': user.id,
      });
    });

    try {
      await _supabase.from('logs_bb_attendance').upsert(
        rows,
        onConflict: 'student_id,report_date',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green[800],
          content: Text("Attendance for $dateStr saved successfully!"),
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onSaved();
      Navigator.pop(context);
    } catch (e) {
      debugPrint("Save error: $e");
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red[800], content: Text("Save failed: $e")),
        );
      }
    }
  }

  void _markAll(String status) {
    setState(() {
      for (var s in _filteredStudents) {
        final sid = s['id'].toString();
        _attendanceData.putIfAbsent(sid, () => {});
        _attendanceData[sid]!['status'] = status;
      }
    });
  }

  List<dynamic> get _filteredStudents {
    return widget.students.where((s) {
      final name = (s['student_name'] ?? '').toString().toLowerCase();
      final center = (s['center_place'] ?? '').toString();
      final matchesSearch = name.contains(_searchQuery.toLowerCase());
      final matchesCenter = _selectedCenter == "All" || center == _selectedCenter;
      return matchesSearch && matchesCenter;
    }).toList();
  }

  List<String> get _centers {
    final Set<String> cSet = {"All"};
    for (var s in widget.students) {
      final c = s['center_place']?.toString().trim();
      if (c != null && c.isNotEmpty) cSet.add(c);
    }
    return cSet.toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStudents;
    final dateStr = DateFormat('EEEE, MMM d, yyyy').format(widget.selectedDate);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    int attendedCount = filtered.where((s) {
      final sid = s['id'].toString();
      return _attendanceData[sid]?['status'] == 'Attended';
    }).length;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isMobile ? double.infinity : 760,
        height: isMobile ? MediaQuery.of(context).size.height * 0.9 : 660,
        padding: EdgeInsets.all(isMobile ? 14 : 20),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "BB Student Attendance",
                        style: GoogleFonts.merriweather(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.w900,
                          color: AppPalette.fg(widget.pPurple),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateStr,
                        style: GoogleFonts.merriweather(
                          fontSize: 11.5,
                          color: AppPalette.fg(Colors.grey[700]),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppPalette.bg(Colors.green.shade50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppPalette.line(Colors.green.shade300)),
                  ),
                  child: Text(
                    "$attendedCount / ${filtered.length} Attended",
                    style: GoogleFonts.merriweather(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: AppPalette.fg(Colors.green[800]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 20),

            // Filter Bar (Search + Center Dropdown + Bulk Actions)
            if (isMobile) ...[
              TextField(
                decoration: InputDecoration(
                  hintText: "Search student...",
                  prefixIcon: const Icon(Icons.search, size: 16),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onChanged: (q) => setState(() => _searchQuery = q),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _centers.contains(_selectedCenter) ? _selectedCenter : "All",
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: "Center",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      items: _centers.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)))).toList(),
                      onChanged: (v) => setState(() => _selectedCenter = v ?? "All"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _markAll('Attended'),
                    child: Text("All Attended", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.green))),
                  ),
                  TextButton(
                    onPressed: () => _markAll('Absent'),
                    child: Text("All Absent", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.red))),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: "Search student...",
                        prefixIcon: const Icon(Icons.search, size: 16),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onChanged: (q) => setState(() => _searchQuery = q),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _centers.contains(_selectedCenter) ? _selectedCenter : "All",
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: "Center",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      items: _centers.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(),
                      onChanged: (v) => setState(() => _selectedCenter = v ?? "All"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => _markAll('Attended'),
                    child: Text("All Attended", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.green))),
                  ),
                  TextButton(
                    onPressed: () => _markAll('Absent'),
                    child: Text("All Absent", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.red))),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),

            // Student List with Smooth 60/120 FPS scrolling
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text("No students found."))
                      : ScrollConfiguration(
                          behavior: const MaterialScrollBehavior().copyWith(
                            dragDevices: {
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.touch,
                              PointerDeviceKind.trackpad,
                            },
                          ),
                          child: ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final s = filtered[i];
                              final sid = s['id'].toString();
                              final status = _attendanceData[sid]?['status'] ?? 'Absent';
                              final isAttended = status == 'Attended';

                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: AppPalette.bg(isAttended ? Colors.green.withValues(alpha: 0.04) : Colors.transparent),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 15,
                                      backgroundColor: AppPalette.bg(widget.pPurple.withValues(alpha: 0.1)),
                                      child: Text(
                                        "${i + 1}",
                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppPalette.fg(widget.pPurple)),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s['student_name'] ?? 'Unnamed',
                                            style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            "Teacher: ${s['teacher_name'] ?? s['teacher_id'] ?? 'None'}  |  Center: ${s['center_place'] ?? 'N/A'}",
                                            style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.grey[600])),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    // One-Tap Attended / Absent Toggle
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _attendanceData.putIfAbsent(sid, () => {});
                                          _attendanceData[sid]!['status'] = isAttended ? 'Absent' : 'Attended';
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: AppPalette.bg(isAttended ? Colors.green : Colors.red.shade50),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: AppPalette.line(isAttended ? Colors.green : Colors.red.shade300)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isAttended ? Icons.check_circle : Icons.cancel_outlined,
                                              size: 14,
                                              color: AppPalette.fg(isAttended ? Colors.white : Colors.red),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isAttended ? "Attended" : "Absent",
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                                color: AppPalette.fg(isAttended ? Colors.white : Colors.red.shade900),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
            ),

            const SizedBox(height: 12),
            // Footer Save Button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  icon: _isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 16),
                  label: Text(_isSaving ? "Saving..." : "Save Attendance"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.bg(widget.pPurple),
                    foregroundColor: AppPalette.fg(Colors.white),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  ),
                  onPressed: _isSaving ? null : _saveAttendance,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}