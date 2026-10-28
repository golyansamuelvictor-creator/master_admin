// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';
import '../../core/i18n.dart';
import 'bb_workspace_screen.dart' show BbSettings;

const Color _kPurple = Color(0xFF4A148C);

/// One BB student: the Attendance sheet details (center, month, stage, status,
/// guide, teacher) and the BB File details (person, contact, faith, language,
/// address). The guide's and teacher's units are filled from the member list
/// by SCJ ID, so students guided or taught across units are counted right.
class BbStudentForm extends StatefulWidget {
  final Map<String, dynamic>? student;
  final BbSettings cfg;
  final bool readOnly;
  const BbStudentForm({super.key, this.student, required this.cfg, this.readOnly = false});
  @override
  State<BbStudentForm> createState() => _BbStudentFormState();
}

class _BbStudentFormState extends State<BbStudentForm> {
  final _db = Supabase.instance.client;
  late final Map<String, dynamic> _v = Map<String, dynamic>.from(widget.student ?? {});
  final Map<String, TextEditingController> _t = {};
  bool _saving = false;
  String? _lookupNote;

  static const _guideUnit = ['guide_location', 'guide_sub_location', 'guide_dept', 'guide_team', 'guide_cell'];
  static const _teacherUnit = ['teacher_location', 'teacher_sub_location', 'teacher_dept', 'teacher_team', 'teacher_cell'];

  TextEditingController _c(String k) => _t.putIfAbsent(k, () => TextEditingController(text: (_v[k] ?? '').toString()));

  @override
  void dispose() {
    for (final c in _t.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills a guide's / teacher's name and units from `members` by SCJ ID.
  Future<void> _lookup(String who) async {
    final id = _c('${who}_scj_id').text.trim();
    if (id.isEmpty) return;
    try {
      final m = await _db.from('members').select('english_name, location, sub_location, department, team, cell_group').eq('scj_id', id).limit(1).maybeSingle();
      if (m == null) {
        setState(() => _lookupNote = "No member with SCJ ID $id. Type the details by hand.");
        return;
      }
      setState(() {
        _lookupNote = null;
        _c('${who}_name').text = (m['english_name'] ?? '').toString();
        final keys = who == 'guide' ? _guideUnit : _teacherUnit;
        final vals = [m['location'], m['sub_location'], m['department'], m['team'], m['cell_group']];
        for (int i = 0; i < keys.length; i++) {
          _c(keys[i]).text = (vals[i] ?? '').toString();
        }
      });
    } catch (e) {
      setState(() => _lookupNote = "Couldn't look up $id: $e");
    }
  }

  Future<void> _save() async {
    if (_c('student_name').text.trim().isEmpty) {
      setState(() => _lookupNote = "The student's name is needed.");
      return;
    }
    setState(() => _saving = true);
    final row = <String, dynamic>{..._v};
    _t.forEach((k, c) {
      final v = c.text.trim();
      row[k] = v.isEmpty ? null : v;
    });
    for (final k in ['members', 'attended', 'missed']) {
      row.remove(k);
    }
    row['owner_email'] = _db.auth.currentUser?.email;
    try {
      if (row['id'] == null) {
        row.remove('id');
        await _db.from('bb_students').insert(row);
      } else {
        await _db.from('bb_students').update(row).eq('id', row['id']);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _lookupNote = "Couldn't save: ${e is PostgrestException ? e.message : e}";
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Remove ${_v['student_name']}?"),
        content: const Text("The student and their attendance are deleted."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Remove", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('bb_students').delete().eq('id', _v['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _lookupNote = "Couldn't remove: ${e is PostgrestException ? e.message : e}");
    }
  }

  Widget _text(String key, String label, {double width = 230, String? hint, TextInputType? type}) => SizedBox(
        width: width,
        child: TextField(
          controller: _c(key),
          readOnly: widget.readOnly,
          keyboardType: type,
          decoration: InputDecoration(labelText: tr(label), hintText: hint == null ? null : tr(hint), isDense: true, border: const OutlineInputBorder()),
        ),
      );

  Widget _pick(String key, String label, List<String> options, {double width = 230}) {
    final cur = (_v[key] ?? '').toString();
    final opts = [...options, if (cur.isNotEmpty && !options.contains(cur)) cur];
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: cur.isEmpty ? null : cur,
        isExpanded: true,
        decoration: InputDecoration(labelText: tr(label), isDense: true, border: const OutlineInputBorder()),
        items: [for (final o in opts) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
        onChanged: widget.readOnly ? null : (v) => setState(() => _v[key] = v),
      ),
    );
  }

  Widget _group(String title, List<Widget> fields) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(_kPurple))),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: fields),
        ]),
      );

  List<Widget> _person(String who) => [
        SizedBox(
          width: 230,
          child: TextField(
            controller: _c('${who}_scj_id'),
            readOnly: widget.readOnly,
            decoration: InputDecoration(
              labelText: tr("SCJ ID"),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: widget.readOnly ? null : IconButton(tooltip: tr("Fill from member list"), icon: const Icon(Icons.search_rounded, size: 18), onPressed: () => _lookup(who)),
            ),
            onSubmitted: (_) => _lookup(who),
          ),
        ),
        _text('${who}_name', "Name"),
        _text('${who}_korean_name', "Korean name"),
        _text('${who}_location', "Location", width: 150),
        _text('${who}_sub_location', "Sub-location", width: 150),
        _text('${who}_dept', "Department", width: 150),
        _text('${who}_team', "Team", width: 110),
        _text('${who}_cell', "Cell", width: 110),
      ];

  @override
  Widget build(BuildContext context) {
    final o = widget.cfg.options;
    final isNew = widget.student == null;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 820),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
            child: Row(children: [
              Expanded(
                child: Text(isNew ? "New BB student" : (widget.readOnly ? "${_v['student_name']}" : "Edit ${_v['student_name']}"),
                    style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              if (!isNew && !widget.readOnly)
                IconButton(tooltip: tr("Remove"), icon: Icon(Icons.delete_outline_rounded, color: AppPalette.fg(Colors.red.shade700)), onPressed: _delete),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
            ]),
          ),
          if (_lookupNote != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Text(_lookupNote!, style: TextStyle(color: AppPalette.fg(Colors.red.shade700), fontSize: 12))),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(children: [
                _group("Attendance details (needed for the student to count)", [
                  _text('student_name', "Fruit's name (English)", width: 300),
                  _pick('center_place', "Center place", widget.cfg.centers),
                  _pick('month', "Opening month", widget.cfg.months),
                  _pick('level_status', "Evangelism stage", widget.cfg.stageNames),
                  _pick('bb_status', "Status", o['bb_status'] ?? const ['Active', 'Not Active', 'Dropped']),
                  _pick('new_old', "New / Old", o['new_old'] ?? const ['New', 'Old']),
                  _pick('guided_by_type', "Guided by", o['guided_by_type'] ?? const ['Saint', 'Student']),
                ]),
                _group("Guide", _person('guide')),
                _group("BB teacher", _person('teacher')),
                _group("Student", [
                  _text('korean_name', "Korean name"),
                  _pick('repeater', "New / Repeater", o['repeater'] ?? const ['New', 'Repeater']),
                  _pick('gender', "Gender", o['gender'] ?? const ['Male', 'Female']),
                  _text('dob', "Date of birth", hint: "YYYYMMDD", type: TextInputType.number),
                  _pick('marital_status', "Marital status", o['marital_status'] ?? const ['Married', 'Single', 'Single Parent']),
                  _text('contact', "Contact", hint: "+256 700 000000", type: TextInputType.phone),
                  _text('email', "Email", type: TextInputType.emailAddress),
                  _text('job', "Job"),
                  _text('student_level', "Level"),
                ]),
                _group("Evangelism and faith", [
                  _pick('method', "Evangelism type", o['method'] ?? const []),
                  _text('evangelist_name', "Evangelist"),
                  _text('years_of_faith', "Years of faith", hint: "e.g. 05y 03m"),
                  _text('denomination', "Denomination"),
                  _text('church', "Church"),
                ]),
                _group("Language and address", [
                  _text('nationality', "Nationality"),
                  _text('language_main', "Main language"),
                  _text('language_secondary', "Second language"),
                  _text('language_level', "Second language level"),
                  _text('country', "Country (living)"),
                  _text('city', "City / municipality"),
                  _text('street', "Street / village", width: 300),
                  _text('homecountry', "Home country (foreigners)"),
                ]),
              ]),
            ),
          ),
          if (!widget.readOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
                  label: Text(isNew ? "Add student" : "Save"),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
