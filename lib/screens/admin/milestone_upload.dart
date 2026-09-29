// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border, BorderStyle;

class MilestoneUploadScreen extends StatefulWidget {
  const MilestoneUploadScreen({super.key});

  @override
  State<MilestoneUploadScreen> createState() => _MilestoneUploadScreenState();
}

class _MilestoneUploadScreenState extends State<MilestoneUploadScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isProcessing = false;
  String _statusMessage = "Ready to import. Select an Excel file to begin.";
  int? _successCount;
  int? _failedCount;
  List<String> _unmatchedScjIds = [];
  bool _showUnmatchedList = false;
  bool _showColumnGuide = false; // Expandable/collapsible column guide

  final Color _primaryPurple = const Color(0xFF4A148C);
  final Color _backgroundColor = const Color(0xFFF8FAFC);

  /// Helper to safely read and trim cell values
  String? _getCellValue(List<Data?> row, int index) {
    if (index >= row.length) return null;
    final cell = row[index];
    if (cell == null || cell.value == null) return null;
    final val = cell.value.toString().trim();
    return val.isEmpty ? null : val;
  }

  /// Safe date formatter to YYYY-MM-DD
  String _formatDate(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) {
      return DateTime.now().toIso8601String().split('T').first;
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate)) {
      return rawDate;
    }
    final parsed = DateTime.tryParse(rawDate);
    if (parsed != null) {
      return parsed.toIso8601String().split('T').first;
    }
    return rawDate;
  }

  Future<void> _pickAndProcessFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );

    if (result == null || result.files.first.bytes == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = "Reading spreadsheet data...";
      _successCount = null;
      _failedCount = null;
      _unmatchedScjIds = [];
      _showUnmatchedList = false;
    });

    try {
      final bytes = result.files.first.bytes!;
      final excel = Excel.decodeBytes(bytes);
      final sheetName = excel.tables.keys.first;
      final table = excel.tables[sheetName];

      if (table == null || table.maxRows <= 1) {
        throw Exception("The selected spreadsheet contains no data rows.");
      }

      // Step 1: Parse rows from Excel
      final List<_MilestoneRowData> pendingRows = [];
      final Set<String> uniqueScjIds = {};

      for (int i = 1; i < table.maxRows; i++) {
        final row = table.rows[i];
        final scjId = _getCellValue(row, 0); // Column A: SCJ ID
        if (scjId == null) continue;

        final milestoneName = _getCellValue(row, 1) ?? "General Milestone"; // Column B
        final rawDate = _getCellValue(row, 2); // Column C: Date
        final grade = _getCellValue(row, 3);   // Column D: Grade / Performance
        final notes = _getCellValue(row, 4);   // Column E: Optional Notes

        pendingRows.add(_MilestoneRowData(
          scjId: scjId,
          milestoneName: milestoneName,
          completionDate: _formatDate(rawDate),
          grade: grade,
          notes: notes,
        ));
        uniqueScjIds.add(scjId);
      }

      if (pendingRows.isEmpty) {
        throw Exception("No valid rows with an SCJ ID were found in the file.");
      }

      // Step 2: Batch lookup member UUIDs using scj_id
      setState(() => _statusMessage = "Matching member records in database...");
      final Map<String, dynamic> scjToMemberId = {};
      final scjIdList = uniqueScjIds.toList();

      for (int i = 0; i < scjIdList.length; i += 100) {
        final chunk = scjIdList.sublist(
          i,
          (i + 100 > scjIdList.length) ? scjIdList.length : i + 100,
        );

        final membersData = await _supabase
            .from('members')
            .select('id, scj_id')
            .inFilter('scj_id', chunk);

        for (final m in membersData) {
          final dbScjId = m['scj_id']?.toString().trim();
          if (dbScjId != null) {
            scjToMemberId[dbScjId] = m['id'];
          }
        }
      }

      // Step 3: Prepare milestone insert payloads
      final List<Map<String, dynamic>> recordsToInsert = [];
      final List<String> notFoundIds = [];

      for (final row in pendingRows) {
        final memberId = scjToMemberId[row.scjId];
        if (memberId != null) {
          recordsToInsert.add({
            'member_id': memberId,
            'milestone_name': row.milestoneName,
            'completion_date': row.completionDate,
            if (row.grade != null && row.grade!.isNotEmpty) 'grade': row.grade,
            if (row.notes != null && row.notes!.isNotEmpty) 'notes': row.notes,
          });
        } else {
          notFoundIds.add(row.scjId);
        }
      }

      // Step 4: Batch insert milestones
      if (recordsToInsert.isNotEmpty) {
        setState(() => _statusMessage = "Inserting ${recordsToInsert.length} milestone records...");
        for (int i = 0; i < recordsToInsert.length; i += 100) {
          final chunk = recordsToInsert.sublist(
            i,
            (i + 100 > recordsToInsert.length) ? recordsToInsert.length : i + 100,
          );
          await _supabase.from('member_milestones').insert(chunk);
        }
      }

      setState(() {
        _successCount = recordsToInsert.length;
        _failedCount = notFoundIds.length;
        _unmatchedScjIds = notFoundIds;
        _statusMessage = "Import completed: ${_successCount ?? 0} milestones imported successfully.";
      });
    } catch (e) {
      setState(() => _statusMessage = "Error: $e");
      debugPrint("Import Error: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          "Milestone Bulk Importer",
          style: GoogleFonts.merriweather(
            fontWeight: FontWeight.w900,
            color: _primaryPurple,
            fontSize: 23,
          ),
        ),
        centerTitle: true,
      ),
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTemplateGuideCard(),
              const SizedBox(height: 12),
              _buildCompactUploadBox(),
              const SizedBox(height: 12),
              if (_successCount != null) ...[
                _buildSummaryCard(),
                const SizedBox(height: 12),
              ],
              _buildStatusCard(),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact & Expandable Column Guide Card
  Widget _buildTemplateGuideCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showColumnGuide = !_showColumnGuide),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.table_chart_outlined, color: _primaryPurple, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Excel Template Format",
                          style: GoogleFonts.merriweather(
                            fontWeight: FontWeight.w900,
                            fontSize: 17.5,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _showColumnGuide
                              ? "Columns must follow this exact order in the active sheet:"
                              : "Click to preview expected 5-column structure (Columns A – E)",
                          style: GoogleFonts.merriweather(
                            fontSize: 13.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showColumnGuide ? Icons.expand_less : Icons.expand_more,
                    color: _primaryPurple,
                    size: 26,
                  ),
                ],
              ),
            ),
          ),
          if (_showColumnGuide) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Column(
                children: [
                  _buildGuideItem("Column A", "Member SCJ ID", "Required", "Unique member identifier (e.g. 1002345)"),
                  _buildGuideItem("Column B", "Milestone Name", "Required", "Training or graduation name (e.g. Level 1)"),
                  _buildGuideItem("Column C", "Completion Date", "Optional", "Format: YYYY-MM-DD (defaults to today)"),
                  _buildGuideItem("Column D", "Grade", "Optional", "Performance result (e.g. A, 85%, Pass, Distinction)"),
                  _buildGuideItem("Column E", "Notes", "Optional", "Additional remarks or certificate reference"),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGuideItem(String col, String label, String badge, String desc) {
    final isRequired = badge == "Required";
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              col,
              style: GoogleFonts.merriweather(
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
                color: _primaryPurple,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  label,
                  style: GoogleFonts.merriweather(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isRequired ? Colors.amber.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isRequired ? Colors.amber.shade300 : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    badge,
                    style: GoogleFonts.merriweather(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isRequired ? Colors.amber.shade900 : Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "— $desc",
                  style: GoogleFonts.merriweather(
                    fontSize: 13.5,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sleek dropzone: height reduced by half (~56px) with larger font
  Widget _buildCompactUploadBox() {
    return InkWell(
      onTap: _isProcessing ? null : _pickAndProcessFile,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isProcessing ? Colors.grey.shade300 : _primaryPurple.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _primaryPurple.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_upload_outlined, size: 22, color: _primaryPurple),
            ),
            const SizedBox(width: 14),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Upload Milestone Spreadsheet",
                  style: GoogleFonts.merriweather(
                    fontWeight: FontWeight.w900,
                    fontSize: 17.5,
                    color: _primaryPurple,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  "Click to browse or drop an Excel (.xlsx or .xls) file",
                  style: GoogleFonts.merriweather(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Import Summary",
            style: GoogleFonts.merriweather(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSummaryChip("Milestones Imported", "${_successCount ?? 0}", Colors.green.shade700),
              _buildSummaryChip("Unmatched IDs", "${_failedCount ?? 0}", (_failedCount ?? 0) > 0 ? Colors.red.shade700 : Colors.grey.shade600),
              _buildSummaryChip("Total Rows Processed", "${(_successCount ?? 0) + (_failedCount ?? 0)}", Colors.blue.shade700),
            ],
          ),
          if (_unmatchedScjIds.isNotEmpty) ...[
            const SizedBox(height: 14),
            InkWell(
              onTap: () => setState(() => _showUnmatchedList = !_showUnmatchedList),
              child: Row(
                children: [
                  Text(
                    _showUnmatchedList ? "Hide Unmatched SCJ IDs" : "View ${_unmatchedScjIds.length} Unmatched SCJ IDs",
                    style: GoogleFonts.merriweather(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _showUnmatchedList ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: Colors.red.shade800,
                  ),
                ],
              ),
            ),
            if (_showUnmatchedList) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _unmatchedScjIds.join(", "),
                  style: GoogleFonts.robotoMono(fontSize: 13, color: Colors.red.shade900),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryChip(String label, String count, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              count,
              style: GoogleFonts.merriweather(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.merriweather(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact Status Card: height reduced by half with larger font styles
  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        children: [
          if (_isProcessing) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 10),
          ],
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: _statusMessage.startsWith("Error")
                  ? Colors.red.shade700
                  : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _MilestoneRowData {
  final String scjId;
  final String milestoneName;
  final String completionDate;
  final String? grade;
  final String? notes;

  _MilestoneRowData({
    required this.scjId,
    required this.milestoneName,
    required this.completionDate,
    this.grade,
    this.notes,
  });
}