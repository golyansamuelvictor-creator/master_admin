// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;

class MemberSyncTool extends StatefulWidget {
  const MemberSyncTool({super.key});

  @override
  State<MemberSyncTool> createState() => _MemberSyncToolState();
}

class _MemberSyncToolState extends State<MemberSyncTool> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isProcessing = false;
  String _log = "Ready to sync. Select an Excel file to begin.";
  int? _totalInFile;
  int? _totalUpserted;
  int? _totalDropped;
  bool _showColumnGuide = false;

  final Color _primaryPurple = const Color(0xFF4A148C);
  final Color _backgroundColor = const Color(0xFFF8FAFC);

  /// Helper to safely extract and trim string cell values
  String? _getCellValue(List<Data?> row, int index) {
    if (index >= row.length) return null;
    final cell = row[index];
    if (cell == null || cell.value == null) return null;
    final val = cell.value.toString().trim();
    return val.isEmpty ? null : val;
  }

  /// Full synchronization logic matching SQL member table order
  Future<void> _startFullSync() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );

    if (result == null || result.files.first.bytes == null) return;

    setState(() {
      _isProcessing = true;
      _log = "Step 1: Reading Excel file...";
      _totalInFile = null;
      _totalUpserted = null;
      _totalDropped = null;
    });

    try {
      final bytes = result.files.first.bytes!;
      final excel = Excel.decodeBytes(bytes);
      final sheetName = excel.tables.keys.first;
      final table = excel.tables[sheetName];

      if (table == null || table.maxRows <= 1) {
        throw Exception("The uploaded spreadsheet contains no data rows.");
      }

      // Detect header mappings if present in row 0
      final headerRow = table.rows[0];
      final Map<String, int> headerMap = {};
      for (int c = 0; c < headerRow.length; c++) {
        final val = _getCellValue(headerRow, c)?.toLowerCase().replaceAll(' ', '_');
        if (val != null) {
          headerMap[val] = c;
        }
      }

      // Col index resolver: uses header row position if recognized, otherwise falls back to SQL column index
      int col(String name, int defaultIndex) => headerMap[name] ?? defaultIndex;

      // Existing members (paged), so required columns can be filled in for
      // rows that leave them blank and so we know which records already exist.
      setState(() => _log = "Step 2: Loading existing member records...");
      final Map<String, Map<String, dynamic>> existingByScj = {};
      int offset = 0;
      while (true) {
        final page = await _supabase
            .from('members')
            .select('scj_id, english_name, sub_location, dob, location, reg_status')
            .order('id')
            .range(offset, offset + 999);
        for (final r in page) {
          final id = r['scj_id']?.toString().trim();
          if (id != null && id.isNotEmpty) existingByScj[id] = Map<String, dynamic>.from(r);
        }
        if (page.length < 1000) break;
        offset += 1000;
      }

      final List<Map<String, dynamic>> upsertData = [];
      final List<String> scjIdsInFile = [];
      final Set<String> locationsInFile = {};
      final List<String> skipped = [];

      setState(() => _log = "Step 3: Parsing member records...");

      for (int i = 1; i < table.maxRows; i++) {
        final row = table.rows[i];

        // scj_id is at SQL column index 9 (Column J)
        final scjId = _getCellValue(row, col('scj_id', 9));
        if (scjId == null) continue;

        scjIdsInFile.add(scjId);

        final memberMap = <String, dynamic>{
          'scj_id': scjId,
          'location': _getCellValue(row, col('location', 1)),
          'sub_location': _getCellValue(row, col('sub_location', 2)),
          'department': _getCellValue(row, col('department', 3)),
          'team': _getCellValue(row, col('team', 4)),
          'cell_group': _getCellValue(row, col('cell_group', 5)),
          'duty': _getCellValue(row, col('duty', 6)),
          'english_name': _getCellValue(row, col('english_name', 7)),
          'korean_name': _getCellValue(row, col('korean_name', 8)),
          'dob': _getCellValue(row, col('dob', 11)),
          'gender': _getCellValue(row, col('gender', 12)),
          'reg_status': _getCellValue(row, col('reg_status', 13)),
          'appointment': _getCellValue(row, col('appointment', 14)),
          'bol_dept': _getCellValue(row, col('bol_dept', 16)),
          'sub_location_id': _getCellValue(row, col('sub_location_id', 17)),
          'dept_id': _getCellValue(row, col('dept_id', 18)),
          'team_id': _getCellValue(row, col('team_id', 19)),
          'cell_id': _getCellValue(row, col('cell_id', 20)),
          'nationality': _getCellValue(row, col('nationality', 21)),
          'marital_status': _getCellValue(row, col('marital_status', 22)),
          'photograph_url': _getCellValue(row, col('photograph_url', 23)),
          'health_status': _getCellValue(row, col('health_status', 24)),
          'email_address': _getCellValue(row, col('email_address', 26)),
          'physical_address': _getCellValue(row, col('physical_address', 27)),
          'emergency_contact': _getCellValue(row, col('emergency_contact', 28)),
          'family_info': _getCellValue(row, col('family_info', 29)),
          'relatives_in_scj': _getCellValue(row, col('relatives_in_scj', 30)),
          'date_joined': _getCellValue(row, col('date_joined', 31)),
          'faith_in_pp': _getCellValue(row, col('faith_in_pp', 32)),
          'occupation': _getCellValue(row, col('occupation', 33)),
          'education_level': _getCellValue(row, col('education_level', 34)),
          'special_skills': _getCellValue(row, col('special_skills', 35)),
          'spiritual_genealogy': _getCellValue(row, col('spiritual_genealogy', 36)),
          'instructor_name': _getCellValue(row, col('instructor_name', 37)),
          'evangelist_name': _getCellValue(row, col('evangelist_name', 38)),
          'bb_teacher_name': _getCellValue(row, col('bb_teacher_name', 39)),
          'guide_name': _getCellValue(row, col('guide_name', 40)),
          'introduced_by_id': _getCellValue(row, col('introduced_by_id', 41)),
        };

        // book_of_life is GENERATED from bol_dept in the database and can't be
        // written (writing it made the whole sync fail); use it to fill bol_dept.
        final bolFromSheet = _getCellValue(row, col('book_of_life', 10));
        if (memberMap['bol_dept'] == null && bolFromSheet != null) memberMap['bol_dept'] = bolFromSheet;

        // phone_numbers is a list column (text[]): "0700..., 0780..." -> ["0700...", "0780..."]
        final phones = _getCellValue(row, col('phone_numbers', 25));
        if (phones != null) {
          memberMap['phone_numbers'] = phones
              .split(RegExp(r'[,;/]'))
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList();
        }

        // Blank cells are left out so they never wipe existing data
        memberMap.removeWhere((key, value) => value == null);

        // english_name, sub_location and dob are required by the table. For an
        // existing member, keep the stored value when the sheet leaves it blank.
        final existing = existingByScj[scjId];
        for (final req in const ['english_name', 'sub_location', 'dob']) {
          if (memberMap[req] == null && existing != null && existing[req] != null) {
            memberMap[req] = existing[req];
          }
        }
        if (memberMap['english_name'] == null || memberMap['sub_location'] == null || memberMap['dob'] == null) {
          skipped.add(scjId);
          continue;
        }

        final loc = (memberMap['location'] ?? existing?['location'])?.toString();
        if (loc != null && loc.isNotEmpty) locationsInFile.add(loc);

        upsertData.add(memberMap);
      }

      if (upsertData.isEmpty) {
        throw Exception("No valid rows with an SCJ ID, name, sub-location and date of birth were found in the file.");
      }

      // Step 4: upsert. Rows are grouped by which columns they fill, because a
      // bulk upsert sets every column in the batch: a row without (say) a phone
      // would otherwise have its stored phone overwritten with NULL.
      setState(() => _log = "Step 4: Updating ${upsertData.length} records in database...");
      final Map<String, List<Map<String, dynamic>>> byColumns = {};
      for (final m in upsertData) {
        final keys = m.keys.toList()..sort();
        byColumns.putIfAbsent(keys.join(','), () => []).add(m);
      }
      for (final group in byColumns.values) {
        for (int i = 0; i < group.length; i += 100) {
          final chunk = group.sublist(i, (i + 100 > group.length) ? group.length : i + 100);
          await _supabase.from('members').upsert(chunk, onConflict: 'scj_id');
        }
      }

      // Step 5: mark members missing from the file as Dropped — but only in the
      // locations this file covers. (Before, uploading one location's sheet
      // marked every other member of the church as Dropped.)
      setState(() => _log = "Step 5: Checking for omitted members to mark as dropped...");
      final Set<String> fileScjIdSet = scjIdsInFile.toSet();
      final List<String> toDrop = [];
      existingByScj.forEach((id, r) {
        final loc = (r['location'] ?? '').toString();
        final status = (r['reg_status'] ?? '').toString();
        if (status != 'Dropped' && locationsInFile.contains(loc) && !fileScjIdSet.contains(id)) {
          toDrop.add(id);
        }
      });

      int droppedCount = 0;
      if (toDrop.isNotEmpty) {
        for (int i = 0; i < toDrop.length; i += 100) {
          final chunk = toDrop.sublist(
            i,
            (i + 100 > toDrop.length) ? toDrop.length : i + 100,
          );
          await _supabase
              .from('members')
              .update({'reg_status': 'Dropped'})
              .inFilter('scj_id', chunk);
          droppedCount += chunk.length;
        }
      }

      if (skipped.isNotEmpty) {
        debugPrint("Member sync skipped (missing name / sub-location / dob): ${skipped.join(', ')}");
      }

      setState(() {
        _totalInFile = scjIdsInFile.length;
        _totalUpserted = upsertData.length;
        _totalDropped = droppedCount;
        _log = skipped.isEmpty
            ? "Full sync completed successfully."
            : "Sync completed. ${skipped.length} row(s) skipped because name, sub-location or date of birth is missing: ${skipped.take(20).join(', ')}${skipped.length > 20 ? ' ...' : ''}";
      });
    } catch (e) {
      setState(() => _log = "Error: $e");
      debugPrint("Sync Error: $e");
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
          "Member Database Sync",
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
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildWarningCard(),
              const SizedBox(height: 14),
              _buildGuideCard(),
              const SizedBox(height: 14),
              if (_totalInFile != null) ...[
                _buildSummaryCard(),
                const SizedBox(height: 14),
              ],
              _buildStatusCard(),
              const SizedBox(height: 18),
              _buildSyncButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact Notice Card: height reduced by half with larger font styles
  Widget _buildWarningCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Important Notice",
                  style: GoogleFonts.merriweather(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF92400E),
                    fontSize: 17.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "This operation synchronizes members using their SCJ ID as the unique key. Existing members will have their details updated, and any active members not present in the uploaded spreadsheet will be marked as Dropped.",
                  style: GoogleFonts.merriweather(
                    color: const Color(0xFF78350F),
                    fontSize: 14.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact Guide Card: height reduced with larger fonts
  Widget _buildGuideCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
            title: Text(
              "Excel Column Order Reference",
              style: GoogleFonts.merriweather(
                fontWeight: FontWeight.w900,
                fontSize: 17.5,
                color: const Color(0xFF1E293B),
              ),
            ),
            subtitle: Text(
              _showColumnGuide
                  ? "Matching 42 member table columns"
                  : "Click to preview expected column structure",
              style: GoogleFonts.merriweather(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            trailing: IconButton(
              icon: Icon(
                _showColumnGuide ? Icons.expand_less : Icons.expand_more,
                color: _primaryPurple,
                size: 26,
              ),
              onPressed: () => setState(() => _showColumnGuide = !_showColumnGuide),
            ),
          ),
          if (_showColumnGuide) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Columns must match the SQL table order. Columns marked with tags are handled automatically by the system:",
                    style: GoogleFonts.merriweather(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildColumnBadge(0, "id", "Auto Primary Key (Skipped)"),
                  _buildColumnBadge(1, "location", "Uploadable"),
                  _buildColumnBadge(2, "sub_location", "Uploadable"),
                  _buildColumnBadge(3, "department", "Uploadable"),
                  _buildColumnBadge(4, "team", "Uploadable"),
                  _buildColumnBadge(5, "cell_group", "Uploadable"),
                  _buildColumnBadge(6, "duty", "Uploadable"),
                  _buildColumnBadge(7, "english_name", "Uploadable"),
                  _buildColumnBadge(8, "korean_name", "Uploadable"),
                  _buildColumnBadge(9, "scj_id", "Conflict Match Key (Required)"),
                  _buildColumnBadge(10, "book_of_life", "Uploadable"),
                  _buildColumnBadge(11, "dob", "Uploadable (Date)"),
                  _buildColumnBadge(12, "gender", "Uploadable"),
                  _buildColumnBadge(13, "reg_status", "Defaults to 'Active'"),
                  _buildColumnBadge(14, "appointment", "Uploadable"),
                  _buildColumnBadge(15, "created_at", "Database Timestamp (Skipped)"),
                  _buildColumnBadge(16, "bol_dept", "Uploadable"),
                  _buildColumnBadge(17, "sub_location_id", "Optional Foreign Key"),
                  _buildColumnBadge(18, "dept_id", "Optional Foreign Key"),
                  _buildColumnBadge(19, "team_id", "Optional Foreign Key"),
                  _buildColumnBadge(20, "cell_id", "Optional Foreign Key"),
                  _buildColumnBadge(21, "nationality", "Uploadable"),
                  _buildColumnBadge(22, "marital_status", "Uploadable"),
                  _buildColumnBadge(23, "photograph_url", "Uploadable"),
                  _buildColumnBadge(24, "health_status", "Uploadable"),
                  _buildColumnBadge(25, "phone_numbers", "Uploadable"),
                  _buildColumnBadge(26, "email_address", "Uploadable"),
                  _buildColumnBadge(27, "physical_address", "Uploadable"),
                  _buildColumnBadge(28, "emergency_contact", "Uploadable"),
                  _buildColumnBadge(29, "family_info", "Uploadable"),
                  _buildColumnBadge(30, "relatives_in_scj", "Uploadable"),
                  _buildColumnBadge(31, "date_joined", "Uploadable (Date)"),
                  _buildColumnBadge(32, "faith_in_pp", "Uploadable"),
                  _buildColumnBadge(33, "occupation", "Uploadable"),
                  _buildColumnBadge(34, "education_level", "Uploadable"),
                  _buildColumnBadge(35, "special_skills", "Uploadable"),
                  _buildColumnBadge(36, "spiritual_genealogy", "Uploadable"),
                  _buildColumnBadge(37, "instructor_name", "Uploadable"),
                  _buildColumnBadge(38, "evangelist_name", "Uploadable"),
                  _buildColumnBadge(39, "bb_teacher_name", "Uploadable"),
                  _buildColumnBadge(40, "guide_name", "Uploadable"),
                  _buildColumnBadge(41, "introduced_by_id", "Optional Foreign Key"),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColumnBadge(int index, String name, String tag) {
    final isSkipped = tag.contains("Skipped");
    final isKey = tag.contains("Key");

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 75,
            child: Text(
              "Col $index",
              style: GoogleFonts.robotoMono(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.merriweather(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: isKey
                  ? Colors.purple.shade50
                  : isSkipped
                      ? Colors.orange.shade50
                      : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isKey
                    ? Colors.purple.shade200
                    : isSkipped
                        ? Colors.orange.shade300
                        : Colors.grey.shade300,
              ),
            ),
            child: Text(
              tag,
              style: GoogleFonts.merriweather(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isKey
                    ? _primaryPurple
                    : isSkipped
                        ? Colors.orange.shade900
                        : Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Sync Summary",
            style: GoogleFonts.merriweather(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSummaryItem("Total in File", "${_totalInFile ?? 0}", Colors.blue.shade700),
              _buildSummaryItem("Upserted", "${_totalUpserted ?? 0}", Colors.green.shade700),
              _buildSummaryItem("Marked Dropped", "${_totalDropped ?? 0}", Colors.red.shade700),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
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
              value,
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
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        children: [
          if (_isProcessing) ...[
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: 10),
          ],
          Text(
            _log,
            textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(
              fontWeight: FontWeight.w700,
              fontSize: 15.5,
              color: _log.startsWith("Error") ? Colors.red.shade700 : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primaryPurple,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade300,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1.5,
      ),
      onPressed: _isProcessing ? null : _startFullSync,
      icon: const Icon(Icons.sync, size: 24),
      label: Text(
        _isProcessing ? "Processing Synchronization..." : "Upload Excel & Sync Members",
        style: GoogleFonts.merriweather(
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}