import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';
import '../../core/i18n.dart';
import '../../core/table_export.dart';
import '../../core/xlsx_safe.dart';
import '../../widgets/h_scroll.dart';
import 'student_duties.dart' show StudentsConfig;

const Color _kPurple = Color(0xFF4A148C);

/// Theology › Students (center_students, 21_round20.sql / 22_round21.sql): the
/// BB File's details (Student's Dept … Marital Status) plus Center code,
/// Center instructor, the center they attend and their class level. BB
/// students who reach Passed Interview are added by the database; others are
/// added here one by one or from an Excel file. Graduates join the members
/// table. A BB student "Guided by: Student" takes the units of the center
/// student with that name.
class CenterStudentsTab extends StatefulWidget {
  final bool canEdit;
  final StudentsConfig? cfg;
  const CenterStudentsTab({super.key, required this.canEdit, this.cfg});
  @override
  State<CenterStudentsTab> createState() => _CenterStudentsTabState();
}

/// (column, label, group)
const _fields = <(String, String, String)>[
  ('student_name', "Name (English)", 'Student'),
  ('korean_name', "Korean name", 'Student'),
  ('center_code', "Center code", 'Center'),
  ('center_instructor', "Center instructor", 'Center'),
  ('center_place', "Center (attends)", 'Center'),
  ('class_level', "Class level", 'Center'),
  ('month', "Opening month", 'Center'),
  ('status', "Status", 'Center'),
  ('repeater', "New / Repeater", 'Student'),
  ('gender', "Gender", 'Student'),
  ('dob', "Date of birth (YYYYMMDD)", 'Student'),
  ('contact', "Contact", 'Student'),
  ('method', "Evangelism type", 'Student'),
  ('years_of_faith', "Years of faith", 'Student'),
  ('denomination', "Denomination", 'Student'),
  ('church', "Church", 'Student'),
  ('job', "Job", 'Student'),
  ('evangelist_name', "Evangelist", 'Student'),
  ('guide_location', "Location", 'Guide'),
  ('guide_sub_location', "Sub Location", 'Guide'),
  ('guide_dept', "Department", 'Guide'),
  ('guide_team', "Team", 'Guide'),
  ('guide_cell', "Cell Group", 'Guide'),
  ('guide_name', "Name", 'Guide'),
  ('guide_korean_name', "Korean name", 'Guide'),
  ('guide_scj_id', "Scj_id", 'Guide'),
  ('teacher_location', "Location", 'BB teacher'),
  ('teacher_sub_location', "Sub Location", 'BB teacher'),
  ('teacher_dept', "Department", 'BB teacher'),
  ('teacher_team', "Team", 'BB teacher'),
  ('teacher_cell', "Cell Group", 'BB teacher'),
  ('teacher_name', "Name", 'BB teacher'),
  ('teacher_korean_name', "Korean name", 'BB teacher'),
  ('teacher_scj_id', "Scj_id", 'BB teacher'),
  ('student_level', "Level", 'Student'),
  ('nationality', "Nationality", 'More'),
  ('language_main', "Main language", 'More'),
  ('language_secondary', "Secondary language", 'More'),
  ('language_level', "Secondary level", 'More'),
  ('email', "Email", 'More'),
  ('country', "Country", 'More'),
  ('city', "Municipality", 'More'),
  ('street', "Street / Village", 'More'),
  ('homecountry', "Homecountry (foreigner)", 'More'),
  ('marital_status', "Marital status", 'More'),
];

class _CenterStudentsTabState extends State<CenterStudentsTab> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _q = '';
  String? _status = 'Active', _center, _level;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _db.from('center_students').select().order('student_name');
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(r);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load the students (run 22_round21.sql): ${e is PostgrestException ? e.message : e}";
        });
      }
    }
  }

  Future<void> _lookup(Map<String, TextEditingController> c, String who) async {
    final id = c['${who}_scj_id']!.text.trim();
    if (id.isEmpty) return;
    try {
      final m = await _db.from('members').select('english_name, korean_name, location, sub_location, department, team, cell_group').eq('scj_id', id).limit(1).maybeSingle();
      if (m == null) return;
      c['${who}_name']!.text = (m['english_name'] ?? '').toString();
      c['${who}_korean_name']!.text = (m['korean_name'] ?? '').toString();
      c['${who}_location']!.text = (m['location'] ?? '').toString();
      c['${who}_sub_location']!.text = (m['sub_location'] ?? '').toString();
      c['${who}_dept']!.text = (m['department'] ?? '').toString();
      c['${who}_team']!.text = (m['team'] ?? '').toString();
      c['${who}_cell']!.text = (m['cell_group'] ?? '').toString();
    } catch (_) {}
  }

  Future<void> _edit([Map<String, dynamic>? s]) async {
    final c = {for (final f in _fields) f.$1: TextEditingController(text: (s?[f.$1] ?? (f.$1 == 'status' ? 'Active' : '')).toString())};
    String? note;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Widget field((String, String, String) f) {
            final scj = f.$1.endsWith('_scj_id');
            final choices = _choices(f.$1);
            if (choices != null) {
              final v = c[f.$1]!.text;
              return SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: choices.contains(v) ? v : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr(f.$2), isDense: true, border: const OutlineInputBorder()),
                  items: [for (final o in {...choices, if (v.isNotEmpty) v}) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
                  onChanged: widget.canEdit ? (x) => set(() => c[f.$1]!.text = x ?? '') : null,
                ),
              );
            }
            return SizedBox(
              width: 220,
              child: TextField(
                controller: c[f.$1],
                readOnly: !widget.canEdit,
                decoration: InputDecoration(
                  labelText: tr(f.$2),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: scj && widget.canEdit
                      ? IconButton(
                          tooltip: tr("Fill from member list"),
                          icon: const Icon(Icons.search_rounded, size: 18),
                          onPressed: () async {
                            await _lookup(c, f.$1.startsWith('guide') ? 'guide' : 'teacher');
                            set(() {});
                          })
                      : null,
                ),
              ),
            );
          }

          final groups = <String, List<(String, String, String)>>{};
          for (final f in _fields) {
            groups.putIfAbsent(f.$3, () => []).add(f);
          }
          return Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820, maxHeight: 820),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
                  child: Row(children: [
                    Expanded(child: Text(s == null ? "New student" : "${s['student_name']}", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16))),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx, false)),
                  ]),
                ),
                if (note != null) Text(note!, style: TextStyle(color: AppPalette.fg(Colors.red.shade700), fontSize: 12)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: Column(children: [
                      for (final g in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 8),
                          child: Text(g.key == 'Guide' ? "Center guide" : g.key, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(_kPurple))),
                        ),
                        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [for (final f in g.value) field(f)]),
                      ],
                    ]),
                  ),
                ),
                if (widget.canEdit)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      // graduation: the student joins the members table
                      if (s != null && s['status'] != 'Graduated' && s['member_id'] == null)
                        TextButton.icon(
                          icon: const Icon(Icons.school_rounded, size: 18),
                          label: const Text("Graduate"),
                          onPressed: () async {
                            final done = await _graduate(s);
                            if (done && ctx.mounted) Navigator.pop(ctx, false);
                          },
                        ),
                      const Spacer(),
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text("Save"),
                        onPressed: () {
                          if (c['student_name']!.text.trim().isEmpty) {
                            set(() => note = "The name is needed.");
                            return;
                          }
                          Navigator.pop(ctx, true);
                        },
                      ),
                    ]),
                  ),
              ]),
            ),
          );
        },
      ),
    );
    if (ok != true) return;
    final row = <String, dynamic>{for (final e in c.entries) e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim()};
    row['status'] ??= 'Active';
    row['updated_at'] = DateTime.now().toUtc().toIso8601String();
    try {
      if (s == null) {
        await _db.from('center_students').insert(row);
      } else {
        await _db.from('center_students').update(row).eq('id', s['id']);
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: ${e is PostgrestException ? e.message : e}")));
    }
  }

  /// Choices of a field (center, class level, status), or null for free text.
  List<String>? _choices(String k) => switch (k) {
        'center_place' => widget.cfg?.centers.isNotEmpty == true ? widget.cfg!.centers : null,
        'class_level' => widget.cfg?.levels ?? const ['Introductory', 'Intermediate', 'Advanced'],
        'status' => const ['Active', 'Graduated', 'Dropped'],
        _ => null,
      };

  /// Graduate: the unit the new member joins (the department defaults to
  /// app_config.graduate_department), and the date of birth if missing.
  Future<bool> _graduate(Map<String, dynamic> s) async {
    final c = {
      'location': TextEditingController(text: (s['guide_location'] ?? s['center_location'] ?? '').toString()),
      'sub_location': TextEditingController(text: (s['guide_sub_location'] ?? '').toString()),
      'department': TextEditingController(),
      'team': TextEditingController(),
      'cell_group': TextEditingController(),
      'dob': TextEditingController(text: (s['dob'] ?? '').toString()),
      'scj_id': TextEditingController(),
    };
    const labels = {
      'location': "Location", 'sub_location': "Sub-location", 'department': "Department (empty = New Saints)", 'team': "Team",
      'cell_group': "Cell group", 'dob': "Date of birth (YYYY-MM-DD)", 'scj_id': "Scj_id (optional)",
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Graduate ${s['student_name']}"),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text("They are added to the members table in this unit and marked Graduated here.", style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
              const SizedBox(height: 10),
              for (final e in c.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(controller: e.value, decoration: InputDecoration(labelText: tr(labels[e.key]!), isDense: true, border: const OutlineInputBorder())),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Graduate")),
        ],
      ),
    );
    if (ok != true || c['location']!.text.trim().isEmpty) return false;
    String? v(String k) => c[k]!.text.trim().isEmpty ? null : c[k]!.text.trim();
    try {
      await _db.rpc('graduate_center_student', params: {
        'p_id': s['id'],
        'p_location': v('location'),
        'p_sub': v('sub_location'),
        'p_dept': v('department'),
        'p_team': v('team'),
        'p_cell': v('cell_group'),
        'p_extra': {if (v('dob') != null) 'dob': v('dob'), if (v('scj_id') != null) 'scj_id': v('scj_id')},
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${s['student_name']} graduated and joined the members"), backgroundColor: Colors.green.shade700));
      _load();
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't graduate: ${e is PostgrestException ? e.message : e}")));
      return false;
    }
  }

  /// Excel upload: the first row holds the column names (as in the template:
  /// the labels or the column keys); each other row is one student.
  Future<void> _upload() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
    final bytes = res?.files.first.bytes;
    if (bytes == null) return;
    try {
      final book = decodeExcelSafe(bytes);
      final sheet = book.tables[book.tables.keys.first]!;
      if (sheet.maxRows < 2) throw "The file has no rows under the header.";
      String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');
      final byName = <String, String>{};
      for (final f in _fields) {
        byName[norm(f.$1)] = f.$1;
        byName[norm(f.$2)] = f.$1;
        byName[norm(_header(f))] = f.$1;
      }
      final head = sheet.rows.first;
      final map = <int, String>{};
      for (int i = 0; i < head.length; i++) {
        final k = byName[norm((head[i]?.value ?? '').toString())];
        if (k != null) map[i] = k;
      }
      if (!map.values.contains('student_name')) throw "No \"Name (English)\" column found. Use the template.";
      final rows = <Map<String, dynamic>>[];
      for (final r in sheet.rows.skip(1)) {
        final row = <String, dynamic>{};
        for (final e in map.entries) {
          final v = e.key < r.length ? (r[e.key]?.value ?? '').toString().trim() : '';
          if (v.isNotEmpty) row[e.value] = v;
        }
        if ((row['student_name'] ?? '').toString().isEmpty) continue;
        row['status'] ??= 'Active';
        rows.add(row);
      }
      for (int i = 0; i < rows.length; i += 200) {
        await _db.from('center_students').insert(rows.sublist(i, (i + 200).clamp(0, rows.length)));
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${rows.length} students added"), backgroundColor: Colors.green.shade700));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't upload: ${e is PostgrestException ? e.message : e}")));
    }
  }

  String _header((String, String, String) f) => f.$3 == 'Guide' ? "Guide ${f.$2}" : (f.$3 == 'BB teacher' ? "Teacher ${f.$2}" : f.$2);

  /// The upload template: the column names and one example row.
  Future<void> _template() async {
    final book = xl.Excel.createExcel();
    final sheet = book[book.getDefaultSheet() ?? 'Sheet1'];
    for (int i = 0; i < _fields.length; i++) {
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        ..value = xl.TextCellValue(_header(_fields[i]))
        ..cellStyle = xl.CellStyle(bold: true);
      final ex = switch (_fields[i].$1) {
        'student_name' => 'John Doe',
        'center_place' => widget.cfg?.centers.firstOrNull ?? 'Nansana',
        'class_level' => widget.cfg?.levels.firstOrNull ?? 'Introductory',
        'status' => 'Active',
        'gender' => 'Male',
        'dob' => '19990105',
        _ => '',
      };
      if (ex.isNotEmpty) sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = xl.TextCellValue(ex);
    }
    if (kIsWeb) {
      book.save(fileName: 'center_students_template.xlsx'); // the browser downloads it
    } else {
      final bytes = book.encode();
      if (bytes == null) return;
      await FilePicker.platform.saveFile(dialogTitle: 'Center students template', fileName: 'center_students_template.xlsx', bytes: Uint8List.fromList(bytes));
    }
  }

  ExportTable _export(List<Map<String, dynamic>> list) => ExportTable(
        title: "Center students",
        headers: [for (final f in _fields) _header(f)],
        rows: [for (final s in list) [for (final f in _fields) (s[f.$1] ?? '').toString()]],
      );

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = _rows.where((s) {
      if (_status != null && (s['status'] ?? 'Active') != _status) return false;
      if (_center != null && s['center_place'] != _center) return false;
      if (_level != null && s['class_level'] != _level) return false;
      return q.isEmpty || "${s['student_name']} ${s['korean_name']} ${s['center_code']} ${s['guide_name']} ${s['center_instructor']} ${s['center_place']}".toLowerCase().contains(q);
    }).toList();
    final centers = {for (final s in _rows) (s['center_place'] ?? '').toString()}.where((c) => c.isNotEmpty).toList()..sort();
    Widget pick(String all, String? v, List<String> opts, IconData i, void Function(String?) set) => PopupMenuButton<String>(
          onSelected: (x) => setState(() => set(x == '\u0000' ? null : x)),
          itemBuilder: (_) => [PopupMenuItem(value: '\u0000', child: Text(all)), for (final o in opts) PopupMenuItem(value: o, child: Text(o))],
          child: Chip(visualDensity: VisualDensity.compact, avatar: Icon(i, size: 16), label: Text(v ?? all)),
        );
    return Column(children: [
      // one compact line of tools
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        child: HScroll(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
            SizedBox(
              width: 210,
              height: 34,
              child: TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 17), hintText: tr("Search name, center, guide"), isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 6), border: const OutlineInputBorder()),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            pick("All statuses", _status, const ['Active', 'Graduated', 'Dropped'], Icons.verified_rounded, (x) => _status = x),
            pick("All centers", _center, centers, Icons.location_city_rounded, (x) => _center = x),
            pick("All levels", _level, widget.cfg?.levels ?? const ['Introductory', 'Intermediate', 'Advanced'], Icons.stairs_rounded, (x) => _level = x),
            Tooltip(
              message: "${list.length} students · BB students who pass the interview are added automatically",
              child: Text("${list.length}", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_kPurple))),
            ),
            IconButton(tooltip: tr('Excel / PDF / Print'), icon: Icon(Icons.download_rounded, color: AppPalette.fg(_kPurple)), onPressed: () => TableExport.showMenu(context, () => _export(list))),
            if (widget.canEdit) ...[
              PopupMenuButton<String>(
                tooltip: tr("Excel upload"),
                icon: Icon(Icons.upload_file_rounded, color: AppPalette.fg(_kPurple)),
                onSelected: (v) => v == 'template' ? _template() : _upload(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'upload', child: Text("Upload students from Excel")),
                  PopupMenuItem(value: 'template', child: Text("Download the Excel template")),
                ],
              ),
              FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text("Add student")),
            ],
          ]),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
                : list.isEmpty
                    ? Center(child: Text("No center students yet.", style: TextStyle(color: AppPalette.fg(Colors.grey))))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final s = list[i];
                          return Card(
                            elevation: 0.5,
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            child: ListTile(
                              dense: true,
                              onTap: () => _edit(s),
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: AppPalette.bg(_kPurple.withValues(alpha: 0.1)),
                                child: Icon(Icons.school_rounded, size: 18, color: AppPalette.fg(_kPurple)),
                              ),
                              title: Text("${s['student_name']}${(s['korean_name'] ?? '').toString().isNotEmpty ? ' · ${s['korean_name']}' : ''}",
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                [
                                  if ((s['center_place'] ?? '').toString().isNotEmpty) "${s['center_place']}",
                                  if ((s['class_level'] ?? '').toString().isNotEmpty) "${s['class_level']}",
                                  if ((s['center_code'] ?? '').toString().isNotEmpty) "Code ${s['center_code']}",
                                  if ((s['center_instructor'] ?? '').toString().isNotEmpty) "Instructor ${s['center_instructor']}",
                                  [s['guide_location'], s['guide_sub_location'], s['guide_team'], s['guide_cell']].where((x) => (x ?? '').toString().isNotEmpty).join(' › '),
                                ].where((x) => x.isNotEmpty).join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Text((s['status'] ?? '').toString(),
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(s['status'] == 'Dropped' ? Colors.red.shade700 : (s['status'] == 'Graduated' ? Colors.blue.shade700 : Colors.green.shade700)))),
                            ),
                          );
                        },
                      ),
      ),
    ]);
  }
}
