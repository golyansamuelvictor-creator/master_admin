// ignore_for_file: curly_braces_in_flow_control_structures, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ApprovalCockpit extends StatefulWidget {
  final String role, unitName, selectedDuty;
  const ApprovalCockpit({
    super.key,
    required this.role,
    required this.unitName,
    required this.selectedDuty,
  });

  @override
  State<ApprovalCockpit> createState() => _ApprovalCockpitState();
}

class _ApprovalCockpitState extends State<ApprovalCockpit> {
  final _supabase = Supabase.instance.client;
  final Color pPurple = const Color(0xFF4A148C);

  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingBatches = [];
  List<Map<String, dynamic>> _approvedBatches = [];

  // Currently inspected report batch
  Map<String, dynamic>? _selectedReport;
  List<dynamic> _inspectedLogs = [];
  List<dynamic> _inspectedImages = [];
  bool _isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    _loadAllReports();
  }

  String _getTableName() {
    String d = widget.selectedDuty;
    if (d == 'Service Attendance Status') return 'logs_service_attendance_status';
    if (d == 'Cell Group Service') return 'logs_cell_service';
    if (d == 'Offering Status') return 'logs_offering';
    if (d == 'Evangelism' || d == 'Evangelism Part') return 'logs_evangelism';
    if (d == 'Morning Light') return 'logs_morning_light';
    if (d == 'All Saints Education') return 'logs_all_saints_education';
    if (d.contains('Visitations')) return 'logs_visitations';
    if (d == 'Workers Education') return 'logs_workers_education';
    if (d == 'Workers Daily Participation') return 'logs_workers_participation';
    return 'logs_service_attendance_status';
  }

  Future<void> _loadAllReports() async {
    setState(() => _isLoading = true);
    final tableName = _getTableName();

    try {
      // Fetch recent logs for this duty
      final res = await _supabase
          .from(tableName)
          .select('*, members!inner(*)')
          .order('created_at', ascending: false)
          .limit(300);

      final List<dynamic> logs = res as List<dynamic>;

      // Group individual member logs into consolidated report batches (by report_date + unit)
      Map<String, List<dynamic>> grouped = {};
      for (var l in logs) {
        String rDate = l['report_date']?.toString() ?? 'No Date';
        String unit = l['unit_name']?.toString() ??
            l['members']?['cell_group']?.toString() ??
            widget.unitName;
        String key = "$rDate::$unit";
        grouped.putIfAbsent(key, () => []).add(l);
      }

      List<Map<String, dynamic>> pending = [];
      List<Map<String, dynamic>> approved = [];

      grouped.forEach((key, batchLogs) {
        final first = batchLogs.first;
        final status = first['verification_status']?.toString().toLowerCase() ?? 'pending';

        DateTime? submittedAt = DateTime.tryParse(first['created_at']?.toString() ?? '');
        DateTime? approvedAt = DateTime.tryParse(first['updated_at']?.toString() ?? '');

        final batchData = {
          'key': key,
          'report_date': first['report_date'],
          'unit_name': first['unit_name'] ?? first['members']?['cell_group'] ?? widget.unitName,
          'verification_status': status,
          'submitted_at': submittedAt,
          'approved_at': approvedAt,
          'correction_note': first['correction_note'],
          'total_members': batchLogs.length,
          'logs': batchLogs,
        };

        if (status == 'approved') {
          approved.add(batchData);
        } else {
          pending.add(batchData);
        }
      });

      // Sort pending by submission date (newest submission first)
      pending.sort((a, b) {
        DateTime da = a['submitted_at'] ?? DateTime(2020);
        DateTime db = b['submitted_at'] ?? DateTime(2020);
        return db.compareTo(da);
      });

      // Sort approved by approval date (newest approval first)
      approved.sort((a, b) {
        DateTime da = a['approved_at'] ?? DateTime(2020);
        DateTime db = b['approved_at'] ?? DateTime(2020);
        return db.compareTo(da);
      });

      if (mounted) {
        setState(() {
          _pendingBatches = pending;
          _approvedBatches = approved;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Cockpit Load Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openReportInspection(Map<String, dynamic> batch) async {
    setState(() {
      _selectedReport = batch;
      _isLoadingDetails = true;
      _inspectedLogs = batch['logs'] as List<dynamic>;
    });

    try {
      final imgRes = await _supabase
          .from('report_evidence')
          .select()
          .eq('report_date', batch['report_date'])
          .eq('duty_name', widget.selectedDuty);

      if (mounted) {
        setState(() {
          _inspectedImages = imgRes;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      debugPrint("Evidence fetch error: $e");
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  Future<void> _processApproval(bool isApproved, {String? note}) async {
    if (_selectedReport == null) return;
    final tableName = _getTableName();
    final dateStr = _selectedReport!['report_date'];
    int level = widget.role.contains('team') ? 1 : widget.role.contains('dept') ? 2 : 3;

    try {
      await _supabase.from(tableName).update({
        'verification_status': isApproved ? 'approved' : 'flagged',
        'approval_level': isApproved ? level : 0,
        'flagged_for_correction': !isApproved,
        'correction_note': note,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('report_date', dateStr);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: isApproved ? Colors.green.shade800 : Colors.orange.shade800,
        content: Text(isApproved ? "Report Approved Successfully" : "Report Flagged for Correction"),
      ));

      setState(() => _selectedReport = null);
      _loadAllReports();
    } catch (e) {
      debugPrint("Approval Update Error: $e");
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return "Unknown";
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            "QC Approval Cockpit",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: pPurple, fontSize: 17),
          ),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () {
              if (_selectedReport != null) {
                setState(() => _selectedReport = null);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          bottom: _selectedReport == null
              ? TabBar(
                  labelColor: pPurple,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: pPurple,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.pending_actions_rounded, size: 17),
                          const SizedBox(width: 8),
                          Text("Pending Reports (${_pendingBatches.length})"),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.verified_outlined, size: 17),
                          const SizedBox(width: 8),
                          Text("Approved Reports (${_approvedBatches.length})"),
                        ],
                      ),
                    ),
                  ],
                )
              : null,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _selectedReport != null
                ? _buildInspectionView()
                : TabBarView(
                    children: [
                      _buildReportsList(_pendingBatches, isPendingTab: true),
                      _buildReportsList(_approvedBatches, isPendingTab: false),
                    ],
                  ),
      ),
    );
  }

  // --- List View for Pending & Approved Folders ---
  Widget _buildReportsList(List<Map<String, dynamic>> batches, {required bool isPendingTab}) {
    if (batches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPendingTab ? Icons.check_circle_outline_rounded : Icons.folder_open_rounded,
              size: 50,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              isPendingTab
                  ? "Clear! No reports awaiting verification."
                  : "No approved reports found for ${widget.selectedDuty}.",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllReports,
      child: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: batches.length,
        itemBuilder: (context, i) {
          final b = batches[i];
          final bool isApproved = b['verification_status'] == 'approved';
          final bool isFlagged = b['verification_status'] == 'flagged';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.black, width: 1.0), // Dark boundary
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3), // Shadow
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: () => _openReportInspection(b),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          b['unit_name'],
                          style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold, color: pPurple),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isApproved
                                ? Colors.green.shade50
                                : isFlagged
                                    ? Colors.red.shade50
                                    : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isApproved
                                  ? Colors.green.shade300
                                  : isFlagged
                                      ? Colors.red.shade300
                                      : Colors.orange.shade300,
                            ),
                          ),
                          child: Text(
                            isApproved
                                ? "Approved"
                                : isFlagged
                                    ? "Flagged"
                                    : "Awaiting QC",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isApproved
                                  ? Colors.green.shade800
                                  : isFlagged
                                      ? Colors.red.shade800
                                      : Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 18),

                    // Date of Activity
                    Row(
                      children: [
                        const Icon(Icons.event_note_rounded, size: 15, color: Colors.blueGrey),
                        const SizedBox(width: 6),
                        Text(
                          "Activity Date: ${b['report_date']}",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          "${b['total_members']} Entries",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Date of Submission
                    Row(
                      children: [
                        const Icon(Icons.upload_file_rounded, size: 15, color: Colors.blueGrey),
                        const SizedBox(width: 6),
                        Text(
                          "Date of Submission: ${_formatDate(b['submitted_at'])}",
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        ),
                      ],
                    ),

                    // Date of Approval (shown if approved)
                    if (isApproved) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.check_circle_rounded, size: 15, color: Colors.green.shade700),
                          const SizedBox(width: 6),
                          Text(
                            "Date of Approval: ${_formatDate(b['approved_at'])}",
                            style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],

                    if (isFlagged && b['correction_note'] != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        "Correction Note: ${b['correction_note']}",
                        style: TextStyle(fontSize: 11, color: Colors.red.shade800, fontStyle: FontStyle.italic),
                      ),
                    ],

                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        "Tap to Inspect & Audit →",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- Detailed Inspection View for QC Review ---
  Widget _buildInspectionView() {
    final b = _selectedReport!;
    final bool isApproved = b['verification_status'] == 'approved';

    final absentees = _inspectedLogs.where((l) =>
        ["Absentee", "CS Absentee", "No", "ASE Absence"]
            .contains(l['status_detail'] ?? l['attendance_realtime'])).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Report Header Info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.black, width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Inspecting: ${b['unit_name']}",
                  style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.bold, color: pPurple),
                ),
                const SizedBox(height: 4),
                Text("Duty: ${widget.selectedDuty}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text("Activity Date: ${b['report_date']}", style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                Text("Date of Submission: ${_formatDate(b['submitted_at'])}", style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                if (isApproved)
                  Text("Date of Approval: ${_formatDate(b['approved_at'])}",
                      style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 1. Evidence Photos
          _sectionHeader(Icons.camera_alt_rounded, "Physical Evidence (Photos)"),
          _buildEvidenceGallery(),
          const SizedBox(height: 20),

          // 2. Absentee Audit
          _sectionHeader(Icons.rule_folder_rounded, "Data Consistency Audit (Absentees)"),
          _buildAbsenteeList(absentees),
          const SizedBox(height: 24),

          // 3. Approval Decision Actions
          if (!isApproved)
            _buildDecisionFooter()
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_rounded, color: Colors.green.shade800, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "This report has been approved and verified.",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, color: pPurple, size: 18),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
          ],
        ),
      );

  Widget _buildEvidenceGallery() {
    if (_isLoadingDetails) {
      return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
    }
    if (_inspectedImages.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
            SizedBox(width: 8),
            Text("No photos were uploaded with this report.", style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _inspectedImages.length,
        itemBuilder: (c, i) => Container(
          margin: const EdgeInsets.only(right: 12),
          width: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black, width: 1.0),
            image: DecorationImage(image: NetworkImage(_inspectedImages[i]['image_url']), fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  Widget _buildAbsenteeList(List<dynamic> abs) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            title: Text("Total Absentees: ${abs.length}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: const Text("Cross-check these reasons with the evidence photo.", style: TextStyle(fontSize: 11)),
            trailing: Icon(Icons.warning_amber_rounded, color: abs.isEmpty ? Colors.green : Colors.orange),
          ),
          const Divider(height: 0),
          ...abs.map((l) => ListTile(
                dense: true,
                leading: const CircleAvatar(backgroundColor: Colors.redAccent, radius: 4),
                title: Text(l['members']['english_name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text(
                  l['reason_notes'] ?? l['situation_notes'] ?? "No reason provided",
                  style: TextStyle(
                    color: (l['reason_notes'] == null && l['situation_notes'] == null) ? Colors.red : Colors.black54,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )),
          if (abs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text("No absentees to verify for this unit.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  Widget _buildDecisionFooter() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red, width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _showFlagDialog,
            icon: const Icon(Icons.flag_rounded, color: Colors.red, size: 18),
            label: const Text("Flag for Correction", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => _processApproval(true),
            icon: const Icon(Icons.verified_rounded, color: Colors.white, size: 18),
            label: const Text("Approve Report", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  void _showFlagDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Flag Report for Correction", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: "Enter reason for rejection (e.g., photo mismatch)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () {
              _processApproval(false, note: ctrl.text);
              Navigator.pop(c);
            },
            child: const Text("Return Report", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}