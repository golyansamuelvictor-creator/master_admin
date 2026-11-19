// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:typed_data';
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../core/xlsx_safe.dart';
import '../core/xlsx_fast.dart';
import 'package:excel/excel.dart' as xl;
import '../core/save_bytes.dart';
import 'package:master_admin/core/app_palette.dart';

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
  // rows skipped in the last upload: SCJ ID, name, reason (download as Excel)
  List<List<String>> _skippedRows = [];

  /// 보고예정자 (not yet registered): no real SCJ ID yet.
  static const _preStatus = '보고예정자';
  static bool _isRealScjId(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return false;
    if (RegExp(r'[\u3131-\uD79D]').hasMatch(t)) return false; // Korean text, e.g. 보고예정자
    return RegExp(r'\d').hasMatch(t);
  }

  static String _norm(Object? v) => (v ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// A stable temporary ID for a 보고예정자 member: the same person gets the
  /// same ID in every upload (name + date of birth + location).
  static String _tempId(String name, String dob, String location) {
    int h = 0x811c9dc5;
    for (final c in '${_norm(name)}|${_norm(dob)}|${_norm(location)}'.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return 'PRE-${h.toRadixString(16).toUpperCase().padLeft(8, '0')}';
  }

  Future<void> _downloadSkipped() async {
    final book = xl.Excel.createExcel();
    final sh = book[book.getDefaultSheet() ?? 'Sheet1'];
    sh.appendRow([for (final h in ['Row', 'SCJ ID', 'Name', 'Why it was skipped']) xl.TextCellValue(h)]);
    for (final r in _skippedRows) {
      sh.appendRow([for (final c in r) xl.TextCellValue(c)]);
    }
    final bytes = book.encode();
    if (bytes == null) return;
    await saveBytesAs(Uint8List.fromList(bytes), 'skipped_members.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }

  final Color _primaryPurple = const Color(0xFF4A148C);
  final Color _backgroundColor = const Color(0xFFF8FAFC);

  // Progress of the step running now (0–1), shown under the message
  double? _progress;

  /// Columns in the order of the members table: used when the file has no
  /// header row (column A = id, B = location ...).
  static const List<String> _sqlOrder = [
    'id', 'location', 'sub_location', 'department', 'team', 'cell_group', 'duty', 'english_name', 'korean_name',
    'scj_id', 'book_of_life', 'dob', 'gender', 'reg_status', 'appointment', 'created_at', 'bol_dept',
    'sub_location_id', 'dept_id', 'team_id', 'cell_id', 'nationality', 'marital_status', 'photograph_url',
    'health_status', 'phone_numbers', 'email_address', 'physical_address', 'emergency_contact', 'family_info',
    'relatives_in_scj', 'date_joined', 'faith_in_pp', 'occupation', 'education_level', 'special_skills',
    'spiritual_genealogy', 'instructor_name', 'evangelist_name', 'bb_teacher_name', 'guide_name', 'introduced_by_id',
  ];

  /// Never written from a file: set by the database (is_worker comes from
  /// duty and book_of_life from bol_dept; writing them fails).
  static const Set<String> _readOnly = {'id', 'created_at', 'is_worker', 'book_of_life'};
  static const List<String> _required = ['english_name', 'sub_location', 'dob'];
  static String _fieldName(String k) => const {'english_name': 'name', 'sub_location': 'sub-location', 'dob': 'date of birth'}[k] ?? k;
  static const Set<String> _uuidCols = {'sub_location_id', 'dept_id', 'team_id', 'cell_id', 'introduced_by_id', 'official_dept_id'};

  static String _headerKey(String s) {
    final k = s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-./]+'), '_').replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return _aliases[k] ?? k;
  }

  /// Header names of the church's sheets (SERVICE, 보예 …) → members columns.
  static const Map<String, String> _aliases = {
    'region': 'location',
    'sub_region': 'sub_location',
    'subregion': 'sub_location',
    'deptcurrent': 'department',
    'dept_current': 'department',
    'deptbook_of_life': 'book_of_life',
    'dept_book_of_life': 'book_of_life',
    'cell': 'cell_group',
    'reg_status': 'reg_status',
    'residence': 'geo_category',
    'status': 'member_status',
    'member_status': 'member_status',
    'center_code': 'center_code',
    'center_transfer': 'center_code',
    'eng_name': 'english_name',
    'english_name': 'english_name',
  };

  /// Same value in the file and in the database? (dates compared by day,
  /// numbers and lists as text, extra spaces ignored)
  static bool _same(dynamic stored, dynamic fromFile) {
    String norm(dynamic v) {
      if (v == null) return '';
      if (v is List) return v.map((e) => e.toString().trim()).join(',');
      var s = v.toString().trim();
      final d = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})([T ].*)?$').firstMatch(s);
      if (d != null) s = '${d.group(1)}-${d.group(2)!.padLeft(2, '0')}-${d.group(3)!.padLeft(2, '0')}';
      if (RegExp(r'^-?\d+\.0+$').hasMatch(s)) s = s.substring(0, s.indexOf('.'));
      return s.replaceAll(RegExp(r'\s+'), ' ');
    }
    return norm(stored) == norm(fromFile);
  }

  /// A cell's text in the form its column needs (null = leave as it is).
  /// Saves [rows]; when the database refuses a batch (for example a Book of
  /// Life name that isn't in the departments list), it is split up so only
  /// the bad rows are left out, and those are reported.
  Future<int> _save(List<Map<String, dynamic>> rows, List<String> failed) async {
    if (rows.isEmpty) return 0;
    try {
      await _supabase.from('members').upsert(rows, onConflict: 'scj_id');
      return rows.length;
    } catch (e) {
      if (rows.length == 1) {
        final msg = e is PostgrestException ? e.message : e.toString();
        failed.add("${rows.first['scj_id']} ($msg)");
        return 0;
      }
      final half = rows.length ~/ 2;
      return await _save(rows.sublist(0, half), failed) + await _save(rows.sublist(half), failed);
    }
  }

  static dynamic _convert(String col, String? v) {
    if (v == null || v.isEmpty) return null;
    if (col == 'phone_numbers') {
      final l = v.split(RegExp(r'[,;/]')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      return l.isEmpty ? null : l;
    }
    if (_uuidCols.contains(col)) {
      return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(v) ? v : null;
    }
    if (col == 'official') {
      final l = v.toLowerCase();
      if (['yes', 'y', 'true', '1', 'official'].contains(l)) return true;
      if (['no', 'n', 'false', '0', '-'].contains(l)) return false;
      return null;
    }
    if (col == 'date_joined') {
      return RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(v) ? v.substring(0, 10) : null;
    }
    return v;
  }

  Future<void> _step(String msg, [double? progress]) async {
    if (!mounted) return;
    setState(() {
      _log = msg;
      _progress = progress;
    });
    await Future<void>.delayed(Duration.zero); // let the screen draw
  }

  /// Reads the file (fast reader; the excel package only if that fails).
  Future<List<List<String?>>> _readRows(List<int> bytes) async {
    try {
      return await readXlsxFast(bytes, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
    } catch (e) {
      debugPrint('Fast reader failed, using the excel package: $e');
      await _step("Step 1: Reading Excel file (slower way)...");
      final excel = decodeExcelSafe(bytes);
      final table = excel.tables[excel.tables.keys.first];
      if (table == null) return [];
      return [
        for (final row in table.rows) // .rows is built once here (it rebuilds the whole sheet on every call)
          [
            for (final cell in row)
              () {
                final v = cell?.value?.toString().trim();
                return (v == null || v.isEmpty) ? null : v;
              }(),
          ],
      ];
    }
  }

  /// Full synchronization: only the columns you choose are updated.
  Future<void> _startFullSync() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result == null || result.files.first.bytes == null) return;

    setState(() {
      _isProcessing = true;
      _totalInFile = null;
      _totalUpserted = null;
      _totalDropped = null;
      _skippedRows = [];
    });

    try {
      await _step("Step 1: Reading Excel file...", 0);
      final rows = await _readRows(result.files.first.bytes!);
      if (rows.length <= 1) throw Exception("The uploaded spreadsheet contains no data rows.");

      // The members table's columns (from one stored row; the known list if empty)
      final known = <String>{..._sqlOrder, 'official_dept_id', 'geo_category', 'country', 'mou_church', 'course_completion_date', 'enrollment_year', 'official', 'member_status', 'center_code'};
      try {
        final one = await _supabase.from('members').select().limit(1);
        if (one.isNotEmpty) known
          ..clear()
          ..addAll(one.first.keys);
      } catch (_) {}

      // Header row: columns are matched by name, so the file can hold any of
      // them in any order. Without a header row the SQL order is used.
      final header = rows.first;
      final colIndex = <String, int>{};
      final ignored = <String>[];
      for (int c = 0; c < header.length; c++) {
        final h = header[c];
        if (h == null) continue;
        final k = _headerKey(h);
        if (known.contains(k) || k == 'book_of_life') {
          colIndex.putIfAbsent(k, () => c);
        } else {
          ignored.add(h);
        }
      }
      final hasHeader = colIndex.containsKey('scj_id');
      if (!hasHeader) {
        colIndex.clear();
        ignored.clear();
        for (int c = 0; c < _sqlOrder.length; c++) {
          colIndex[_sqlOrder[c]] = c;
        }
      }
      // book_of_life is worked out from bol_dept in the database: a
      // "book_of_life" column fills bol_dept (unless the file has bol_dept too)
      if (colIndex.containsKey('book_of_life')) {
        final i = colIndex.remove('book_of_life')!;
        if (known.contains('bol_dept')) colIndex.putIfAbsent('bol_dept', () => i);
      }
      colIndex.removeWhere((k, _) => _readOnly.contains(k));
      final dataRows = rows.length - 1;

      // Which columns to update
      if (!mounted) return;
      final choice = await showDialog<({Set<String> cols, bool markDropped})>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ColumnChoiceDialog(
          columns: colIndex.keys.where((k) => k != 'scj_id').toList(),
          ignored: ignored,
          rows: dataRows,
          hasHeader: hasHeader,
        ),
      );
      if (choice == null) {
        await _step("Sync cancelled. Nothing was changed.");
        return;
      }
      final chosen = choice.cols.toList();

      // Existing members: only the columns needed (paged)
      final need = <String>{'scj_id', 'location', 'reg_status', ..._required, ...chosen}.where(known.contains).toList();
      final Map<String, Map<String, dynamic>> existingByScj = {};
      int offset = 0;
      while (true) {
        await _step("Step 2: Loading existing member records... (${existingByScj.length})");
        final page = await _supabase.from('members').select(need.join(',')).order('id').range(offset, offset + 999);
        for (final r in page) {
          final id = r['scj_id']?.toString().trim();
          if (id != null && id.isNotEmpty) existingByScj[id] = Map<String, dynamic>.from(r);
        }
        if (page.length < 1000) break;
        offset += 1000;
      }

      // Compare the file with the database
      final List<Map<String, dynamic>> changedRows = [];
      final List<Map<String, dynamic>> newRows = [];
      final List<String> scjIdsInFile = [];
      final Set<String> locationsInFile = {};
      final List<String> skipped = [];
      final List<List<String>> skippedRows = [];
      final failed = <String>[];
      int preCount = 0;
      final renames = <String, String>{}; // PRE-… → the real SCJ ID now given
      // the 보고예정자 already stored, by name + date of birth
      final preByPerson = <String, String>{};
      existingByScj.forEach((id, r) {
        if (id.startsWith('PRE-')) preByPerson['${_norm(r['english_name'])}|${_norm(r['dob'])}'] = id;
      });
      void skip(int rowNo, String id, Object? name, String why) {
        skipped.add(id.isEmpty ? (name ?? '').toString() : id);
        skippedRows.add(['${rowNo + 1}', id, (name ?? '').toString(), why]);
      }
      int unchanged = 0;
      final scjCol = colIndex['scj_id']!;
      String? cell(List<String?> row, int? i) => (i == null || i >= row.length) ? null : row[i];
      // the existing rows are all sent with the same columns, so they go in
      // a few big batches (before, nearly every member was its own request)
      final writeCols = <String>{..._required, ...chosen, if (known.contains('reg_status')) 'reg_status'}.toList();

      for (int i = 1; i < rows.length; i++) {
        if (i % 500 == 0) await _step("Step 3: Checking rows... $i of $dataRows", i / rows.length);
        final row = rows[i];
        var scjId = cell(row, scjCol)?.trim() ?? '';
        final fromFile = <String, dynamic>{};
        for (final k in writeCols) {
          final v = _convert(k, cell(row, colIndex[k]));
          if (v != null) fromFile[k] = v;
        }
        final rawName = cell(row, colIndex['english_name']) ?? cell(row, colIndex['korean_name']);
        final statusCell = (cell(row, colIndex['reg_status']) ?? '').trim();
        bool isPre = false, renamed = false;
        if (!_isRealScjId(scjId)) {
          // 보고예정자 / no SCJ ID yet: a temporary ID
          final looksPre = scjId.contains(_preStatus) || statusCell.contains(_preStatus) || (scjId.isEmpty && (rawName ?? '').trim().isNotEmpty);
          if (!looksPre) continue; // an empty line
          if ((rawName ?? '').trim().isEmpty) {
            skip(i, scjId, rawName, "No SCJ ID and no name");
            continue;
          }
          final loc = (cell(row, colIndex['location']) ?? '').toString();
          final dob = (fromFile['dob'] ?? cell(row, colIndex['dob']) ?? '').toString();
          scjId = _tempId(rawName!, dob, loc);
          fromFile['reg_status'] = _preStatus;
          isPre = true;
          preCount++;
        } else if (!existingByScj.containsKey(scjId)) {
          // got a real SCJ ID: was this person stored as 보고예정자?
          final key = '${_norm(fromFile['english_name'] ?? rawName)}|${_norm(fromFile['dob'])}';
          final pre = preByPerson.remove(key);
          if (pre != null && existingByScj.containsKey(pre)) {
            renames[pre] = scjId;
            existingByScj[scjId] = {...existingByScj.remove(pre)!, 'scj_id': scjId};
            renamed = true;
          }
        }
        scjIdsInFile.add(scjId);
        final existing = existingByScj[scjId];

        final loc = (fromFile['location'] ?? existing?['location'])?.toString();
        if (loc != null && loc.isNotEmpty) locationsInFile.add(loc);

        if (existing != null) {
          // only the chosen columns count as changes; blank cells keep what is stored
          final changed = renamed || chosen.any((k) => fromFile.containsKey(k) && !_same(existing[k], fromFile[k]));
          if (!changed) {
            unchanged++;
            continue;
          }
          final out = <String, dynamic>{'scj_id': scjId};
          for (final k in writeCols) {
            // the status changes only when chosen (or for 보고예정자)
            final fileWins = k != 'reg_status' || chosen.contains(k) || isPre || renamed;
            out[k] = fileWins && fromFile.containsKey(k) ? fromFile[k] : existing[k];
          }
          // registered now: no longer 보고예정자
          if (renamed && (out['reg_status'] ?? '').toString().contains(_preStatus)) out['reg_status'] = 'Active';
          if (_required.any((k) => out[k] == null)) {
            skip(i, scjId, rawName, "Missing: ${_required.where((k) => out[k] == null).map(_fieldName).join(', ')}");
            continue;
          }
          changedRows.add(out);
        } else {
          if (_required.any((k) => fromFile[k] == null)) {
            skip(i, scjId, rawName, "Missing: ${_required.where((k) => fromFile[k] == null).map(_fieldName).join(', ')}");
            continue;
          }
          newRows.add({'scj_id': scjId, ...fromFile});
        }
      }

      if (changedRows.isEmpty && newRows.isEmpty && unchanged == 0) {
        throw Exception("No valid rows with an SCJ ID, name, sub-location and date of birth were found in the file.");
      }

      // 보고예정자 who now have a real SCJ ID: give them the new ID first
      for (final e in renames.entries) {
        await _step("Step 4: Giving registered members their SCJ ID... ${e.value}");
        try {
          await _supabase.from('members').update({'scj_id': e.value}).eq('scj_id', e.key);
        } catch (err) {
          failed.add("${e.value}: $err");
        }
      }

      // Save: changed members in batches of 500; new members grouped by the
      // columns they fill, so blank cells take the table's default values.
      final total = changedRows.length + newRows.length;
      int saved = 0, done = 0;
      for (int i = 0; i < changedRows.length; i += 500) {
        await _step("Step 4: Updating records... $done of $total", total == 0 ? null : done / total);
        final chunk = changedRows.sublist(i, (i + 500 > changedRows.length) ? changedRows.length : i + 500);
        saved += await _save(chunk, failed);
        done += chunk.length;
      }
      final Map<String, List<Map<String, dynamic>>> byColumns = {};
      for (final m in newRows) {
        final keys = m.keys.toList()..sort();
        byColumns.putIfAbsent(keys.join(','), () => []).add(m);
      }
      for (final group in byColumns.values) {
        for (int i = 0; i < group.length; i += 500) {
          await _step("Step 4: Adding new members... $done of $total", total == 0 ? null : done / total);
          final chunk = group.sublist(i, (i + 500 > group.length) ? group.length : i + 500);
          saved += await _save(chunk, failed);
          done += chunk.length;
        }
      }

      // Members missing from the file → Dropped, only in the locations this
      // file covers, and only when that was ticked.
      int droppedCount = 0;
      if (choice.markDropped) {
        await _step("Step 5: Checking for omitted members to mark as dropped...");
        final fileScjIdSet = scjIdsInFile.toSet();
        final List<String> toDrop = [];
        existingByScj.forEach((id, r) {
          final loc = (r['location'] ?? '').toString();
          final status = (r['reg_status'] ?? '').toString();
          if (status != 'Dropped' && locationsInFile.contains(loc) && !fileScjIdSet.contains(id)) toDrop.add(id);
        });
        for (int i = 0; i < toDrop.length; i += 200) {
          final chunk = toDrop.sublist(i, (i + 200 > toDrop.length) ? toDrop.length : i + 200);
          await _supabase.from('members').update({'reg_status': 'Dropped'}).inFilter('scj_id', chunk);
          droppedCount += chunk.length;
        }
      }

      if (failed.isNotEmpty) debugPrint("Member sync refused rows: ${failed.join('; ')}");
      if (skipped.isNotEmpty) {
        debugPrint("Member sync skipped (missing name / sub-location / dob): ${skipped.join(', ')}");
      }

      if (!mounted) return;
      setState(() {
        _progress = null;
        _totalInFile = scjIdsInFile.length;
        _totalUpserted = saved;
        _totalDropped = droppedCount;
        _skippedRows = skippedRows;
        final summary = "${changedRows.length} updated, ${newRows.length} new, $unchanged already up to date.";
        final notes = [
          if (preCount > 0) "$preCount 보고예정자 (not yet registered) kept with a temporary ID (PRE-…).",
          if (renames.isNotEmpty) "${renames.length} 보고예정자 received their SCJ ID.",
          if (skipped.isNotEmpty)
            "${skipped.length} row(s) skipped (download the list below to see why): ${skipped.take(10).join(', ')}${skipped.length > 10 ? ' ...' : ''}",
          if (failed.isNotEmpty)
            "${failed.length} row(s) not saved, the database refused them: ${failed.take(10).join('; ')}${failed.length > 10 ? ' ...' : ''}",
        ];
        _log = notes.isEmpty ? "Full sync completed successfully: $summary" : "Sync completed: $summary ${notes.join(' ')}";
      });
    } catch (e) {
      if (mounted) setState(() => _log = "Error: $e");
      debugPrint("Sync Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(_backgroundColor),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        title: Text(
          "Member Database Sync",
          style: GoogleFonts.merriweather(
            fontWeight: FontWeight.w900,
            color: AppPalette.fg(_primaryPurple),
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
        color: AppPalette.bg(const Color(0xFFFFFBEB)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(const Color(0xFFFDE68A)), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline_rounded, color: AppPalette.fg(Color(0xFFB45309)), size: 24),
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
                    color: AppPalette.fg(const Color(0xFF92400E)),
                    fontSize: 17.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "This operation synchronizes members using their SCJ ID as the unique key. After you pick the file you choose which columns to update; blank cells keep what is stored. Active members of the file's locations who are not in the file can be marked as Dropped (you choose).",
                  style: GoogleFonts.merriweather(
                    color: AppPalette.fg(const Color(0xFF78350F)),
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
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(Colors.grey.shade200), width: 1.5), boxShadow: AppPalette.cardShadow
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
                color: AppPalette.fg(const Color(0xFF1E293B)),
              ),
            ),
            subtitle: Text(
              _showColumnGuide
                  ? "Headers are matched by name, in any order"
                  : "Click to preview expected column structure",
              style: GoogleFonts.merriweather(
                fontSize: 14,
                color: AppPalette.fg(Colors.grey.shade600),
              ),
            ),
            trailing: IconButton(
              icon: Icon(
                _showColumnGuide ? Icons.expand_less : Icons.expand_more,
                color: AppPalette.fg(_primaryPurple),
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
                    "Put the column names in the first row (for example scj_id, location, dob); they can be in any order and you only need the ones you update. Without a header row, the columns must follow this SQL order:",
                    style: GoogleFonts.merriweather(
                      fontSize: 14,
                      color: AppPalette.fg(Colors.grey.shade700),
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
                  const SizedBox(height: 8),
                  Text(
                    "Also matched by header name: country, mou_church, geo_category, course_completion_date, enrollment_year, official_dept_id, official (Yes / No: Dubai Official), Status (Active / H-M / LTA), Center code (보예), Residence (Kampala / Village / Abroad). book_of_life fills bol_dept; is_worker is worked out from duty.",
                    style: GoogleFonts.merriweather(fontSize: 13, color: AppPalette.fg(Colors.grey.shade700)),
                  ),
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
              style: GoogleFonts.merriweather(fontSize: 13, color: AppPalette.fg(Colors.grey.shade600)),
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
              color: AppPalette.bg(isKey
                  ? Colors.purple.shade50
                  : isSkipped
                      ? Colors.orange.shade50
                      : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppPalette.line(isKey
                    ? Colors.purple.shade200
                    : isSkipped
                        ? Colors.orange.shade300
                        : Colors.grey.shade300),
              ),
            ),
            child: Text(
              tag,
              style: GoogleFonts.merriweather(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppPalette.fg(isKey
                    ? _primaryPurple
                    : isSkipped
                        ? Colors.orange.shade900
                        : Colors.grey.shade700),
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
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(const Color(0xFFE2E8F0)), width: 1.5), boxShadow: AppPalette.cardShadow
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Sync Summary",
            style: GoogleFonts.merriweather(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: AppPalette.fg(const Color(0xFF1E293B)),
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
          color: AppPalette.bg(color.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppPalette.line(color.withValues(alpha: 0.2))),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.merriweather(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: AppPalette.fg(color),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.merriweather(
                fontSize: 12.5,
                color: AppPalette.fg(Colors.grey.shade700),
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
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(Colors.grey.shade200), width: 1.5), boxShadow: AppPalette.cardShadow
      ),
      child: Column(
        children: [
          if (_isProcessing) ...[
            if (_progress == null)
              const CircularProgressIndicator(strokeWidth: 2.5)
            else
              LinearProgressIndicator(value: _progress, minHeight: 6, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 10),
          ],
          Text(
            _log,
            textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(
              fontWeight: FontWeight.w700,
              fontSize: 15.5,
              color: AppPalette.fg(_log.startsWith("Error") ? Colors.red.shade700 : const Color(0xFF1E293B)),
            ),
          ),
          if (_skippedRows.isNotEmpty && !_isProcessing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: _downloadSkipped,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text.rich(TextSpan(text: "${tr('Download the skipped rows')} (${_skippedRows.length})")),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSyncButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppPalette.bg(_primaryPurple),
        foregroundColor: AppPalette.fg(Colors.white),
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

/// After the file is read: which of its columns to update.
class _ColumnChoiceDialog extends StatefulWidget {
  final List<String> columns;
  final List<String> ignored;
  final int rows;
  final bool hasHeader;
  const _ColumnChoiceDialog({required this.columns, required this.ignored, required this.rows, required this.hasHeader});

  @override
  State<_ColumnChoiceDialog> createState() => _ColumnChoiceDialogState();
}

class _ColumnChoiceDialogState extends State<_ColumnChoiceDialog> {
  late final Set<String> _sel = widget.hasHeader ? widget.columns.toSet() : {};
  bool _markDropped = true;

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF4A148C);
    return AlertDialog(
      title: Text("Columns to update", textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(purple))),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(
              "${widget.rows} rows found. Members are matched by scj_id. Only the ticked columns are changed; blank cells keep what is stored.",
              style: GoogleFonts.merriweather(fontSize: 13),
            ),
            if (!widget.hasHeader)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("No header row with scj_id was found, so the columns are read in the SQL order. Tick the ones to update.",
                    style: GoogleFonts.merriweather(fontSize: 12.5, color: AppPalette.fg(Colors.orange.shade900))),
              ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton(onPressed: () => setState(() => _sel.addAll(widget.columns)), child: const Text("All")),
              TextButton(onPressed: () => setState(_sel.clear), child: const Text("None")),
              const Spacer(),
              Text("${_sel.length} of ${widget.columns.length}", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in widget.columns)
                FilterChip(
                  label: Text.rich(TextSpan(text: c), style: const TextStyle(fontSize: 12.5)),
                  selected: _sel.contains(c),
                  onSelected: (v) => setState(() => v ? _sel.add(c) : _sel.remove(c)),
                ),
            ]),
            if (widget.ignored.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text.rich(TextSpan(text: "${tr('Not a members column, ignored')}: ${widget.ignored.join(', ')}"),
                  style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
            ],
            const Divider(height: 22),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _markDropped,
              onChanged: (v) => setState(() => _markDropped = v),
              title: const Text("Mark members missing from this file as Dropped"),
              subtitle: const Text("Only in the locations the file covers"),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        FilledButton.icon(
          onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, (cols: _sel, markDropped: _markDropped)),
          icon: const Icon(Icons.sync, size: 18),
          label: const Text("Start sync"),
        ),
      ],
    );
  }
}
