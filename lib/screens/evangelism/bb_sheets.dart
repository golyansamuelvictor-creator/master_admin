// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';
import '../../core/i18n.dart';
import '../../core/table_export.dart';
import 'bb_workspace_screen.dart' show BbSettings;

const Color _kPurple = Color(0xFF4A148C);

/// Opens a BB table on its own full-screen page.
void bbFullScreen(BuildContext context, String title, Widget child) => Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
          appBar: AppBar(
            centerTitle: true,
            title: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(_kPurple))),
          ),
          body: child,
        ),
      ),
    );
const Color _kAuto = Color(0xFFFFEBEE); // auto columns (Excel: red, don't edit)

enum _Kind { text, pick, auto }

/// One column of a sheet: Excel letter, group (row 1), Korean title (row 2),
/// English title (row 3).
class _Col {
  final String letter;
  final String group;
  final String ko;
  final String en;
  final String? key; // bb_students column (null for computed)
  final _Kind kind;
  final double width;
  final List<String> Function(BbSettings c)? options;
  final String Function(Map<String, dynamic> s)? auto;
  const _Col(this.letter, this.group, this.ko, this.en, this.key, this.kind, {this.width = 110, this.options, this.auto});
}

String _v(Map s, String k) => (s[k] ?? '').toString().trim();

// ---------------------------------------------------------------------------
// Derived values (the Excel formulas)

int? _age(Map s) {
  final d = _v(s, 'dob').replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length != 8) return null;
  final b = DateTime.tryParse('${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6, 8)}');
  if (b == null) return null;
  final now = DateTime.now();
  var a = now.year - b.year;
  if (now.month < b.month || (now.month == b.month && now.day < b.day)) a--;
  return a;
}

/// BB File E "Dept": Underage / Elderly / MG / WG / YG from age, gender and marital status.
String bbDeptGroup(Map s) {
  final a = _age(s);
  if (a == null) return '';
  final g = _v(s, 'gender').toLowerCase();
  final male = g.startsWith('m') || g.contains('남');
  final female = g.startsWith('f') || g.contains('여');
  final ms = _v(s, 'marital_status').toLowerCase();
  if (a < 18) return 'Underage';
  if (a > 69) return '자문-Elderly';
  if (ms == 'married' || ms == 'single parent') return male ? '장년-MG' : (female ? '부녀-WG' : '-');
  if (ms == 'single') {
    if (a > 39) return male ? '장년-MG' : (female ? '부녀-WG' : '-');
    return '청년-YG';
  }
  return '-';
}

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
String _koMonth(String m) {
  final i = _months.indexWhere((x) => x.toLowerCase() == m.toLowerCase());
  return i < 0 ? '' : '${i + 1}월';
}

String _interview(Map s) {
  final st = _v(s, 'level_status');
  if (st.isEmpty) return '';
  if (st == 'Passed Interview') return 'Passed';
  if (st == 'Failed Interview') return 'Failed';
  return 'Pending';
}

const _rosterKeys = ['center_place', 'month', 'student_name', 'new_old', 'level_status', 'bb_status', 'guide_name', 'guide_scj_id', 'guided_by_type', 'teacher_name', 'teacher_scj_id'];

/// Attendance A "Counter": 12 = complete and attended, 11 = complete but never
/// attended, otherwise how many of the 11 details are filled in.
int bbCounter(Map s, int attended) {
  final filled = _rosterKeys.where((k) => _v(s, k).isNotEmpty).length;
  if (filled >= 11) return attended > 0 ? 12 : 11;
  return filled;
}

// ---------------------------------------------------------------------------
// Columns

const _gStudent = '수강생 Student';
const _gGuide = '센터 인도자 Center Guide';
const _gTeacher = '복음방교사 BB teacher';
const _gInfo = 'STUDENT INFORMATION';

List<_Col> _bbFileCols(Map<String, int> attended, BbSettings cfg) => [
      _Col('A', _gStudent, 'Auto', 'Evangelism Stage', 'level_status', _Kind.auto, width: 120),
      _Col('B', _gStudent, 'Auto', 'Center Place', 'center_place', _Kind.auto),
      _Col('C', _gStudent, 'Auto', 'Month', 'month', _Kind.auto, width: 90),
      _Col('D', _gStudent, 'Auto', 'No.', 'student_no', _Kind.auto, width: 50),
      _Col('E', _gStudent, '부서', 'Dept', null, _Kind.auto, width: 90, auto: bbDeptGroup),
      _Col('F', _gStudent, '이름(풀네임)', '모국어 English Name', 'student_name', _Kind.text, width: 160),
      _Col('G', _gStudent, '한국어발음', 'Korean', 'korean_name', _Kind.text),
      _Col('H', _gStudent, '신규/리피터', 'New/Repeater', 'repeater', _Kind.pick, options: (c) => c.options['repeater'] ?? const ['New', 'Repeater']),
      _Col('I', _gStudent, '성별', 'Gender', 'gender', _Kind.pick, width: 80, options: (c) => c.options['gender'] ?? const ['Male', 'Female']),
      _Col('J', _gStudent, '만 나이', 'Age', null, _Kind.auto, width: 55, auto: (s) => _age(s)?.toString() ?? ''),
      _Col('K', _gStudent, '법정생년월일(8자리)', 'Legal Date of Birth YYYYMMDD', 'dob', _Kind.text, width: 120),
      _Col('L', _gStudent, '연락처(전화번호)', 'Contact (Country Code)', 'contact', _Kind.text, width: 130),
      _Col('M', _gStudent, '전도유형', 'Evangelism Type', 'method', _Kind.pick, width: 150, options: (c) => c.options['method'] ?? const []),
      _Col('N', _gStudent, '복음방 횟수', 'BB times', null, _Kind.auto, width: 65, auto: (s) => '${attended[s['id'].toString()] ?? 0}'),
      _Col('O', _gStudent, '센터 이름', 'Center Month', null, _Kind.auto, width: 70, auto: (s) => _koMonth(_v(s, 'month'))),
      _Col('P', _gStudent, '신앙년수', 'Years of Faith 00y 00m', 'years_of_faith', _Kind.text),
      _Col('Q', _gStudent, '교단', 'Denomination', 'denomination', _Kind.text),
      _Col('R', _gStudent, '교회', 'Church', 'church', _Kind.text),
      _Col('S', _gStudent, '직업', 'Job', 'job', _Kind.text),
      _Col('T', _gStudent, 'Auto', 'Center Place (Location-Sublocation)', null, _Kind.auto, width: 140, auto: (s) {
        final c = _v(s, 'center_place');
        final u = cfg.centerUnits[c] ?? '';
        return u.isEmpty ? c : '$c ($u)';
      }),
      _Col('U', _gStudent, '전도사', 'Evangelist', 'evangelist_name', _Kind.text),
      _Col('V', _gGuide, '지역', 'Jiyeok', 'guide_location', _Kind.text),
      _Col('W', _gGuide, '팀', 'Team', 'guide_team', _Kind.text, width: 80),
      _Col('X', _gGuide, '구역', 'Cell', 'guide_cell', _Kind.text, width: 80),
      _Col('Y', _gGuide, '부서', 'Dept', 'guide_dept', _Kind.text, width: 90),
      _Col('Z', _gGuide, '이름', 'English Name', 'guide_name', _Kind.auto, width: 140),
      _Col('AA', _gGuide, '한국어발음', 'Korean Name', 'guide_korean_name', _Kind.text),
      _Col('AB', _gGuide, '고유번호', 'SCJ ID Number', 'guide_scj_id', _Kind.auto, width: 120),
      _Col('AC', _gTeacher, '지역', 'Jiyeok', 'teacher_location', _Kind.text),
      _Col('AD', _gTeacher, '팀', 'Team', 'teacher_team', _Kind.text, width: 80),
      _Col('AE', _gTeacher, '구역', 'Cell', 'teacher_cell', _Kind.text, width: 80),
      _Col('AF', _gTeacher, '부서', 'Dept', 'teacher_dept', _Kind.text, width: 90),
      _Col('AG', _gTeacher, '이름', 'English Name', 'teacher_name', _Kind.auto, width: 140),
      _Col('AH', _gTeacher, '한국어발음', 'Korean Name', 'teacher_korean_name', _Kind.text),
      _Col('AI', _gTeacher, '고유번호', 'SCJ ID - Number', 'teacher_scj_id', _Kind.auto, width: 120),
      _Col('AJ', '', 'Interview Status', 'Interview Status', null, _Kind.auto, width: 90, auto: _interview),
      _Col('AK', '', 'Level', 'Level', 'student_level', _Kind.text, width: 80),
      _Col('AL', _gInfo, '국적-Nationality', 'Nationality', 'nationality', _Kind.text),
      _Col('AM', _gInfo, '언어-Language', '주언어 Main', 'language_main', _Kind.text),
      _Col('AN', _gInfo, '언어-Language', '가능언어 Secondary', 'language_secondary', _Kind.text),
      _Col('AO', _gInfo, '언어-Language', '수준 Sec. Level', 'language_level', _Kind.text, width: 90),
      _Col('AP', _gInfo, '이메일-Email', 'Email', 'email', _Kind.text, width: 160),
      _Col('AQ', _gInfo, '거주지-Address(Current)', "거주'국가'명 Country", 'country', _Kind.text),
      _Col('AR', _gInfo, '거주지-Address(Current)', "거주'도시'명 Municipality", 'city', _Kind.text),
      _Col('AS', _gInfo, '거주지-Address(Current)', '원어/현거주지 Street/Village', 'street', _Kind.text, width: 150),
      _Col('AT', _gInfo, '원어/모국거주지', 'Homecountry (foreigner)', 'homecountry', _Kind.text),
      _Col('AU', _gInfo, 'Maritial Status', 'Maritial Status', 'marital_status', _Kind.pick, options: (c) => c.options['marital_status'] ?? const ['Married', 'Single', 'Single Parent']),
    ];

List<_Col> _attendanceCols(Map<String, int> attended) => [
      _Col('A', 'BY', "Counter (Auto, Don't Edit)", 'Counter', null, _Kind.auto, width: 70, auto: (s) => '${bbCounter(s, attended[s['id'].toString()] ?? 0)}'),
      _Col('B', 'BY', 'No.', 'No.', 'student_no', _Kind.auto, width: 50),
      _Col('C', 'BY', 'Center Place', 'Center Place', 'center_place', _Kind.pick, options: (c) => c.centers),
      _Col('D', 'BY', 'Month', 'Month', 'month', _Kind.pick, width: 100, options: (c) => c.months),
      _Col('E', 'BY', "Fruit's name", "Fruit's name", 'student_name', _Kind.text, width: 160),
      _Col('F', 'BY', 'New/Old', 'New/Old', 'new_old', _Kind.pick, width: 80, options: (c) => c.options['new_old'] ?? const ['New', 'Old']),
      _Col('G', 'BY', 'Evangelism Stage', 'Evangelism Stage', 'level_status', _Kind.pick, width: 130, options: (c) => c.stageNames),
      _Col('H', 'BY', 'Status', 'Status', 'bb_status', _Kind.pick, width: 95, options: (c) => c.options['bb_status'] ?? const ['Active', 'Not Active', 'Dropped']),
      _Col('I', 'BY', 'Guide Name', 'Guide Name', 'guide_name', _Kind.text, width: 140),
      _Col('J', 'BY', 'SCJ ID Number', 'SCJ ID Number', 'guide_scj_id', _Kind.text, width: 120),
      _Col('K', 'BY', 'Guided by Saint/Student', 'Guided by Saint/Student', 'guided_by_type', _Kind.pick, width: 100, options: (c) => c.options['guided_by_type'] ?? const ['Saint', 'Student']),
      _Col('L', 'BY', 'Teacher Name', 'Teacher Name', 'teacher_name', _Kind.text, width: 140),
      _Col('M', 'BY', 'SCJ ID Number', 'SCJ ID Number', 'teacher_scj_id', _Kind.text, width: 120),
    ];

String _letters(int n) {
  // 0 → A … 25 → Z, 26 → AA
  var s = '';
  n += 1;
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

// ---------------------------------------------------------------------------
// The sheet

/// BB File sheet (columns A–AU) or Attendance sheet (A–M + one column per
/// study day, Mon … Sun, of the chosen week, marked Present / Absent; each
/// mark is saved with its study day and date), with the Excel sheet's three
/// header rows.
class BbSheet extends StatefulWidget {
  final bool attendance;
  final BbSettings cfg;
  final List<Map<String, dynamic>> students;
  final Map<String, int> attended; // all-time attended count per student
  final bool canEdit;
  final VoidCallback onSaved;
  /// Shown in its own full-screen page (no "Full screen" button there).
  final bool fullScreen;
  const BbSheet({super.key, required this.attendance, required this.cfg, required this.students, required this.attended, required this.canEdit, required this.onSaved, this.fullScreen = false});
  @override
  State<BbSheet> createState() => _BbSheetState();
}

class _BbSheetState extends State<BbSheet> {
  final _db = Supabase.instance.client;
  final Map<String, Map<String, dynamic>> _dirty = {}; // student → changed fields
  final Map<String, Map<String, (String, String?)>> _marks = {}; // student → date → (status, note)
  final Map<String, Map<String, (String, String?)>> _markDirty = {};
  final _h = ScrollController();
  String _q = '';
  String? _center, _month;
  bool _saving = false;
  late DateTime _start = _monday(DateTime.now());
  static const int _days = 7; // Mon … Sun (columns N – T)
  static const double _rowH = 28;
  static const List<String> _studyDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static DateTime _monday(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));
  static String _studyDay(DateTime d) => _studyDays[d.weekday - 1];

  List<DateTime> get _dates => [for (int i = 0; i < _days; i++) DateTime(_start.year, _start.month, _start.day + i)];
  final _f = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    if (widget.attendance) _loadMarks();
  }

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  Future<void> _loadMarks() async {
    try {
      final rows = <dynamic>[];
      final end = _dates.last;
      for (int from = 0;; from += 1000) {
        final page = await _db
            .from('logs_bb_attendance')
            .select('student_id, report_date, status, notes')
            .gte('report_date', _f.format(_start))
            .lte('report_date', _f.format(end))
            .order('report_date', ascending: true)
            .range(from, from + 999);
        rows.addAll(page);
        if (page.length < 1000) break;
      }
      _marks.clear();
      for (final r in rows) {
        _marks.putIfAbsent(r['student_id'].toString(), () => {})[r['report_date'].toString().split('T').first] = (_norm(r['status']), r['notes']?.toString());
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  String _norm(dynamic s) {
    final v = (s ?? '').toString().toLowerCase();
    if (const {'attended', 'a', 'present', 'yes', 'in-person', 'online'}.contains(v)) return 'Present';
    if (v.isEmpty) return '';
    return 'Absent';
  }

  String _val(Map<String, dynamic> s, _Col c) {
    if (c.auto != null) return c.auto!(s);
    final id = s['id'].toString();
    final d = _dirty[id];
    if (d != null && d.containsKey(c.key)) return (d[c.key] ?? '').toString();
    return _v(s, c.key!);
  }

  Map<String, dynamic> _merged(Map<String, dynamic> s) => {...s, ...?_dirty[s['id'].toString()]};

  void _set(Map<String, dynamic> s, String key, String? v) {
    setState(() => _dirty.putIfAbsent(s['id'].toString(), () => {})[key] = (v ?? '').trim().isEmpty ? null : v!.trim());
  }

  Future<void> _lookup(Map<String, dynamic> s, String who) async {
    final id = (_dirty[s['id'].toString()]?['${who}_scj_id'] ?? s['${who}_scj_id'] ?? '').toString().trim();
    if (id.isEmpty) return;
    try {
      final m = await _db.from('members').select('english_name, location, sub_location, department, team, cell_group').eq('scj_id', id).limit(1).maybeSingle();
      if (m == null) return;
      setState(() {
        final d = _dirty.putIfAbsent(s['id'].toString(), () => {});
        d['${who}_name'] = m['english_name'];
        d['${who}_location'] = m['location'];
        d['${who}_sub_location'] = m['sub_location'];
        d['${who}_dept'] = m['department'];
        d['${who}_team'] = m['team'];
        d['${who}_cell'] = m['cell_group'];
      });
    } catch (_) {}
  }

  Future<void> _mark(Map<String, dynamic> s, DateTime d) async {
    if (!widget.canEdit) return;
    final id = s['id'].toString(), k = _f.format(d);
    final cur = _markDirty[id]?[k] ?? _marks[id]?[k];
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text("${s['student_name']} · ${_studyDay(d)} ${DateFormat('d MMM yyyy').format(d)}", style: const TextStyle(fontWeight: FontWeight.bold))),
          ListTile(leading: Icon(Icons.check_circle_rounded, color: AppPalette.fg(Colors.green.shade700)), title: const Text("Present"), onTap: () => Navigator.pop(ctx, 'Present')),
          ListTile(leading: Icon(Icons.cancel_rounded, color: AppPalette.fg(Colors.red.shade700)), title: const Text("Absent"), onTap: () => Navigator.pop(ctx, 'Absent')),
          if (cur != null) ListTile(leading: const Icon(Icons.backspace_outlined), title: const Text("Clear"), onTap: () => Navigator.pop(ctx, '')),
        ]),
      ),
    );
    if (pick == null) return;
    String? note;
    if (pick == 'Absent') {
      final c = TextEditingController(text: cur?.$2 ?? '');
      note = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Reason for missing"),
          content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: tr("e.g. sick, travelled, work"))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text("Skip")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text("Save")),
          ],
        ),
      );
    }
    setState(() => _markDirty.putIfAbsent(id, () => {})[k] = (pick, (note ?? '').isEmpty ? null : note));
  }

  int get _changes => _dirty.length + _markDirty.values.fold<int>(0, (a, m) => a + m.length);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      for (final e in _dirty.entries) {
        await _db.from('bb_students').update(e.value).eq('id', e.key);
      }
      final up = <Map<String, dynamic>>[];
      final del = <(String, String)>[];
      _markDirty.forEach((sid, m) => m.forEach((d, v) {
            if (v.$1.isEmpty) {
              del.add((sid, d));
            } else {
              up.add({
                'student_id': sid,
                'report_date': d,
                'study_day': _studyDay(DateTime.parse(d)),
                'status': v.$1,
                'notes': v.$2,
                'leader_id': _db.auth.currentUser?.id,
              });
            }
          }));
      if (up.isNotEmpty) await _db.from('logs_bb_attendance').upsert(up, onConflict: 'student_id,report_date');
      for (final x in del) {
        await _db.from('logs_bb_attendance').delete().eq('student_id', x.$1).eq('report_date', x.$2);
      }
      // keep the saved values on screen (also in the full-screen copy)
      for (final s in widget.students) {
        final d = _dirty[s['id'].toString()];
        if (d != null) s.addAll(d);
      }
      _dirty.clear();
      _markDirty.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved")));
      widget.onSaved();
      if (widget.attendance) await _loadMarks();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: ${e is PostgrestException ? e.message : e}"), backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addStudent() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.attendance ? "New fruit" : "New student"),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: tr("Fruit's name (English)"))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text("Add")),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await _db.from('bb_students').insert({'student_name': name, 'bb_status': 'Active', 'owner_email': _db.auth.currentUser?.email});
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't add: ${e is PostgrestException ? e.message : e}")));
    }
  }

  // ---- drawing

  Widget _box(String t, double w, double h, {Color? bg, Color? fg, bool bold = false, int lines = 1, double size = 10.5, Alignment align = Alignment.center}) => Container(
        width: w,
        height: h,
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: bg == null ? null : AppPalette.bg(bg), border: Border.all(color: AppPalette.line(Colors.black26), width: 0.5)),
        child: Text(t, maxLines: lines, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: AppPalette.fg(fg ?? Colors.black87))),
      );

  Widget _cell(Map<String, dynamic> s, _Col c, int r) {
    final id = s['id'].toString();
    final val = _val(s, c);
    final bg = c.kind == _Kind.auto ? _kAuto : (r.isEven ? Colors.white : const Color(0xFFF8FAFC));
    if (!widget.canEdit || c.kind == _Kind.auto) {
      return Tooltip(message: val, waitDuration: const Duration(milliseconds: 700), child: _box(val, c.width, _rowH, bg: bg, bold: c.key == 'student_name'));
    }
    if (c.kind == _Kind.pick) {
      final opts = c.options?.call(widget.cfg) ?? const <String>[];
      return PopupMenuButton<String>(
        tooltip: tr(c.en),
        onSelected: (v) => _set(s, c.key!, v == '\u0000' ? null : v),
        itemBuilder: (_) => [const PopupMenuItem(value: '\u0000', child: Text("—")), for (final o in opts) PopupMenuItem(value: o, child: Text(o))],
        child: _box(val, c.width, _rowH, bg: _dirty[id]?.containsKey(c.key) == true ? const Color(0xFFFFF8E1) : bg),
      );
    }
    final changed = _dirty[id]?.containsKey(c.key) == true;
    return Container(
      width: c.width,
      height: _rowH,
      decoration: BoxDecoration(color: AppPalette.bg(changed ? const Color(0xFFFFF8E1) : bg), border: Border.all(color: AppPalette.line(Colors.black26), width: 0.5)),
      child: TextFormField(
        key: ValueKey('$id-${c.key}'),
        initialValue: val,
        textAlign: TextAlign.center,
        style: GoogleFonts.merriweather(fontSize: 10.5, fontWeight: c.key == 'student_name' ? FontWeight.bold : FontWeight.normal),
        decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 7, horizontal: 4)),
        onChanged: (v) {
          final first = _dirty[id]?.containsKey(c.key) != true;
          _dirty.putIfAbsent(id, () => {})[c.key!] = v.trim().isEmpty ? null : v.trim();
          if (first) setState(() {}); // shows the change and counts it on Save
        },
        onEditingComplete: () {
          setState(() {});
          if (c.key == 'guide_scj_id') _lookup(s, 'guide');
          if (c.key == 'teacher_scj_id') _lookup(s, 'teacher');
        },
        onFieldSubmitted: (_) {
          if (c.key == 'guide_scj_id') _lookup(s, 'guide');
          if (c.key == 'teacher_scj_id') _lookup(s, 'teacher');
        },
      ),
    );
  }

  Widget _markCell(Map<String, dynamic> s, DateTime d, int r) {
    final id = s['id'].toString(), k = _f.format(d);
    final v = _markDirty[id]?[k] ?? _marks[id]?[k];
    final st = v?.$1 ?? '';
    final changed = _markDirty[id]?.containsKey(k) == true;
    final bg = st == 'Present' ? const Color(0xFFE8F5E9) : (st == 'Absent' ? const Color(0xFFFFEBEE) : (r.isEven ? Colors.white : const Color(0xFFF8FAFC)));
    return InkWell(
      onTap: () => _mark(s, d),
      child: Tooltip(
        message: st == 'Absent' ? "Absent${(v?.$2 ?? '').isEmpty ? '' : ': ${v!.$2}'}" : st,
        child: Container(
          width: 64,
          height: _rowH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppPalette.bg(bg),
            border: Border.all(color: AppPalette.line(changed ? Colors.orange : Colors.black26), width: changed ? 1.2 : 0.5),
          ),
          child: Text(st, style: GoogleFonts.merriweather(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppPalette.fg(st == 'Present' ? Colors.green.shade800 : Colors.red.shade700))),
        ),
      ),
    );
  }

  ExportTable _export(List<_Col> cols, List<Map<String, dynamic>> list) {
    final headers = [for (final c in cols) "${c.letter} ${c.en}", if (widget.attendance) ...[for (final d in _dates) "${_studyDay(d)} ${DateFormat('d MMM').format(d)}", 'Number of times']];
    return ExportTable(
      title: widget.attendance ? "BB Attendance" : "BB File",
      subtitle: widget.attendance ? "Week of ${DateFormat('d MMM').format(_dates.first)} – ${DateFormat('d MMM yyyy').format(_dates.last)}" : '',
      headers: headers,
      rows: [
        for (final s in list)
          [
            for (final c in cols) _val(s, c),
            if (widget.attendance) ...[
              for (final d in _dates) (_markDirty[s['id'].toString()]?[_f.format(d)] ?? _marks[s['id'].toString()]?[_f.format(d)])?.$1 ?? '',
              '${widget.attended[s['id'].toString()] ?? 0}',
            ],
          ]
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cols = widget.attendance ? _attendanceCols(widget.attended) : _bbFileCols(widget.attended, widget.cfg);
    final q = _q.toLowerCase();
    final list = widget.students.map(_merged).where((s) {
      if (_center != null && _v(s, 'center_place') != _center) return false;
      if (_month != null && _v(s, 'month') != _month) return false;
      return q.isEmpty || '${s['student_name']} ${s['guide_name']} ${s['teacher_name']} ${s['contact']}'.toLowerCase().contains(q);
    }).toList();
    final dates = widget.attendance ? _dates : const <DateTime>[];
    final width = cols.fold<double>(0, (a, c) => a + c.width) + dates.length * 64 + (widget.attendance ? 80 : 0);

    // header row 1: groups (merged)
    final groupCells = <Widget>[];
    for (int i = 0; i < cols.length;) {
      int j = i;
      double w = 0;
      while (j < cols.length && cols[j].group == cols[i].group) {
        w += cols[j].width;
        j++;
      }
      groupCells.add(_box(cols[i].group, w, 26, bg: const Color(0xFF1E293B), fg: Colors.white, bold: true));
      i = j;
    }
    if (widget.attendance) {
      groupCells.add(_box("Attendance · week of ${DateFormat('d MMM').format(dates.first)} – ${DateFormat('d MMM yyyy').format(dates.last)}", dates.length * 64 + 80, 26,
          bg: const Color(0xFF2E7D32), fg: Colors.white, bold: true));
    }

    final row2 = [
      for (final c in cols) Tooltip(message: "Column ${c.letter}", child: _box(c.ko, c.width, 30, bg: c.kind == _Kind.auto ? const Color(0xFFC62828) : const Color(0xFF334155), fg: Colors.white, lines: 2, size: 9.5)),
      if (widget.attendance) ...[
        for (int i = 0; i < dates.length; i++)
          Tooltip(message: "Column ${_letters(13 + i)}", child: _box(_studyDay(dates[i]), 64, 30, bg: const Color(0xFF334155), fg: Colors.white, bold: true, size: 10.5)),
        _box("BY", 80, 30, bg: const Color(0xFF334155), fg: Colors.white, size: 9.5),
      ],
    ];
    final row3 = [
      for (final c in cols) _box(c.en, c.width, 34, bg: const Color(0xFF475569), fg: Colors.white, bold: true, lines: 2, size: 9.5),
      if (widget.attendance) ...[
        for (final d in dates) _box(DateFormat('d MMM\nyyyy').format(d), 64, 34, bg: const Color(0xFF475569), fg: Colors.white, bold: true, lines: 2, size: 9),
        _box("Number of times", 80, 34, bg: const Color(0xFF475569), fg: Colors.white, bold: true, lines: 2, size: 9),
      ],
    ];

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
          SizedBox(
            width: 240,
            child: TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: tr("Search name, guide, teacher"), isDense: true, border: const OutlineInputBorder()), onChanged: (v) => setState(() => _q = v)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _center = v == '\u0000' ? null : v),
            itemBuilder: (_) => [const PopupMenuItem(value: '\u0000', child: Text("All centers")), for (final c in widget.cfg.centers) PopupMenuItem(value: c, child: Text(c))],
            child: Chip(avatar: const Icon(Icons.location_city_rounded, size: 16), label: Text(_center ?? "All centers")),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _month = v == '\u0000' ? null : v),
            itemBuilder: (_) => [const PopupMenuItem(value: '\u0000', child: Text("All months")), for (final m in widget.cfg.months) PopupMenuItem(value: m, child: Text(m))],
            child: Chip(avatar: const Icon(Icons.calendar_month_rounded, size: 16), label: Text(_month ?? "All months")),
          ),
          if (widget.attendance) ...[
            IconButton(
              tooltip: tr("Previous week"),
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () {
                _start = _start.subtract(const Duration(days: 7));
                _loadMarks();
              },
            ),
            TextButton(
              onPressed: () async {
                final d = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 60)), initialDate: _start, helpText: tr("Any day of the week"));
                if (d != null) {
                  _start = _monday(d);
                  _loadMarks();
                }
              },
              child: Text("Week: ${DateFormat('d MMM').format(_dates.first)} – ${DateFormat('d MMM yyyy').format(_dates.last)}"),
            ),
            IconButton(
              tooltip: tr("Next week"),
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () {
                _start = _start.add(const Duration(days: 7));
                _loadMarks();
              },
            ),
          ],
          IconButton(tooltip: tr('Excel / PDF / Print'), icon: Icon(Icons.download_rounded, color: AppPalette.fg(_kPurple)), onPressed: () => TableExport.showMenu(context, () => _export(cols, list))),
          if (!widget.fullScreen)
            IconButton(
              tooltip: tr('Fullscreen View'),
              icon: Icon(Icons.open_in_full_rounded, color: AppPalette.fg(Colors.blueGrey)),
              onPressed: () => bbFullScreen(
                context,
                widget.attendance ? "Attendance" : "BB File",
                BbSheet(attendance: widget.attendance, cfg: widget.cfg, students: widget.students, attended: widget.attended, canEdit: widget.canEdit, onSaved: widget.onSaved, fullScreen: true),
              ),
            ),
          if (widget.canEdit) ...[
            OutlinedButton.icon(onPressed: _addStudent, icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text("Add row")),
            ElevatedButton.icon(
              onPressed: _changes == 0 || _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded, size: 18),
              label: Text(_changes == 0 ? "Saved" : "Save ($_changes)"),
            ),
          ],
        ]),
      ),
      Text("${list.length} rows${widget.attendance ? ' · tap a study day to mark Present / Absent (saved with the day and date)' : ''} · red columns are filled in automatically",
          style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
      const SizedBox(height: 4),
      Expanded(
        child: Scrollbar(
          controller: _h,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _h,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: groupCells),
                Row(children: row2),
                Row(children: row3),
                Expanded(
                  child: list.isEmpty
                      ? Center(child: Text(widget.canEdit ? "No rows yet. Tap \"Add row\"." : "No students in your unit yet.", style: TextStyle(color: AppPalette.fg(Colors.grey))))
                      : ListView.builder(
                          itemCount: list.length,
                          itemExtent: _rowH,
                          itemBuilder: (_, r) {
                            final s = list[r];
                            return Row(children: [
                              for (final c in cols) _cell(s, c, r),
                              if (widget.attendance) ...[
                                for (final d in dates) _markCell(s, d, r),
                                _box('${widget.attended[s['id'].toString()] ?? 0}', 80, _rowH, bold: true, bg: const Color(0xFFE8F5E9)),
                              ],
                            ]);
                          },
                        ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
