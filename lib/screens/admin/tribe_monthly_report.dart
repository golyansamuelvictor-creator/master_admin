import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';
import '../../core/compilation_rules.dart';
import '../../core/i18n.dart';
import '../../core/table_export.dart';

/// Performance Report › Tribe monthly report: 예배 출결 현황 (service
/// attendance), the sheet the Internal Affairs Department Secretary sends to
/// the tribe every month. Compiled from the members list and the Service
/// Attendance reports (tribe_attendance_report, 20_round19.sql); any number
/// can be corrected before downloading. The Excel file has the same layout
/// and formulas as the tribe's template.
class TribeMonthlyReport extends StatefulWidget {
  const TribeMonthlyReport({super.key});

  /// Can the signed-in user compile it? (admins and the "Tribe Monthly
  /// Report" action, given to the Internal Affairs Department Secretary)
  static Future<bool> allowed() async {
    try {
      final r = await Supabase.instance.client.rpc('has_admin_action', params: {'p_action': 'Tribe Monthly Report'});
      return r == true;
    } catch (_) {
      return false;
    }
  }

  @override
  State<TribeMonthlyReport> createState() => _TribeMonthlyReportState();
}

/// The numbers the sheet needs per church; the rest are formulas.
const _keys = [
  'new_total', 'new_inperson', 'new_online', 'new_other', //
  'roll', 'inperson', 'online', //
  'absent_once', 'long_manageable', 'long_unmanageable',
];

class _TribeMonthlyReportState extends State<TribeMonthlyReport> {
  static const _purple = Color(0xFF4A148C);
  static const _cNew = Color(0xFFFBE4D5); // the template's colours
  static const _cHead = Color(0xFFE6E4E4);
  static const _cAbs = Color(0xFFDDEBF7);

  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
  bool _loading = true;
  String? _error;
  String _tribe = '도마지파';
  int _long = 8;
  List<Map<String, dynamic>> _rows = [];
  final Map<String, Map<String, int>> _edits = {}; // church → key → corrected value

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
      final r = Map<String, dynamic>.from(await Supabase.instance.client
          .rpc('tribe_attendance_report', params: {'p_month': DateFormat('yyyy-MM-dd').format(_month)}) as Map);
      final rows = List<Map<String, dynamic>>.from((r['rows'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
      // the churches in the Compilation screen's order (24Dept, MOU, New Location, Wakiso …)
      final order = CompLevel.orderNames(rows.map((e) => e['church'].toString()), 'Location');
      rows.sort((a, b) => order.indexOf(a['church'].toString()).compareTo(order.indexOf(b['church'].toString())));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _tribe = (r['tribe'] ?? _tribe).toString();
        _long = (r['long_absence'] as num?)?.toInt() ?? 8;
        _edits.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is PostgrestException ? e.message : e.toString();
      });
    }
  }

  int _v(Map<String, dynamic> r, String k) => _edits[r['church']]?[k] ?? (r[k] as num?)?.toInt() ?? 0;

  /// Every column of the sheet (C … S) for one church, as numbers.
  /// Other (L) = roll − (in-person + online + absent), as in the template.
  List<num?> _cols(Map<String, dynamic> r) => _calc([for (final k in _keys) _v(r, k)]);

  List<num?> _calc(List<int> v) {
    final newTotal = v[0], ni = v[1], no = v[2], nx = v[3];
    final roll = v[4], ip = v[5], on = v[6];
    final once = v[7], lm = v[8], lu = v[9];
    final absent = once + lm + lu;
    final other = roll - (ip + on + absent);
    final ng = ni + no + nx, att = ip + on + other;
    double? pct(num a, num b) => b == 0 ? null : a / b;
    return [newTotal, ni, no, nx, ng, pct(ng, newTotal), roll, ip, on, other, att, pct(att, roll), once, lm, lu, absent, pct(absent, roll)];
  }

  List<num?> get _total {
    final sum = List<int>.filled(_keys.length, 0);
    for (final r in _rows) {
      for (int i = 0; i < _keys.length; i++) {
        sum[i] += _v(r, _keys[i]);
      }
    }
    return _calc(sum);
  }

  static const _editable = {0: 'new_total', 1: 'new_inperson', 2: 'new_online', 3: 'new_other', 6: 'roll', 7: 'inperson', 8: 'online', 12: 'absent_once', 13: 'long_manageable', 14: 'long_unmanageable'};

  Future<void> _edit(Map<String, dynamic> r, String key, String label) async {
    final c = TextEditingController(text: '${_v(r, key)}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("${r['church']} · $label"),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(helperText: tr("Compiled: ${(r[key] as num?)?.toInt() ?? 0}"), border: const OutlineInputBorder()),
          onSubmitted: (s) => Navigator.pop(ctx, int.tryParse(s.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _edits[r['church']]?.remove(key);
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text("Use compiled"),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text("Apply")),
        ],
      ),
    );
    if (v == null) return;
    setState(() => _edits.putIfAbsent(r['church'].toString(), () => {})[key] = v);
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final months = [for (int i = 0; i < 24; i++) DateTime(now.year, now.month - i, 1)];
    final m = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Report month"),
        children: [
          for (final d in months)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text(DateFormat('MMMM yyyy').format(d), style: TextStyle(fontWeight: d == _month ? FontWeight.bold : FontWeight.normal)),
            ),
        ],
      ),
    );
    if (m != null && m != _month) {
      setState(() => _month = m);
      _load();
    }
  }

  // ---------------------------------------------------------------- headers

  static const _groups = [
    ('1) 전월 입교자 출석 현황', "Last month's new members", 6, _cNew),
    ('2) 전성도 출석 현황', 'All saints', 6, _cHead),
    ('3) 결석 현황', 'Absentees', 5, _cAbs),
  ];
  static const _heads = [
    ('전월 입교자 수', 'New members'),
    ('대면예배', 'In-person'),
    ('온라인예배', 'Online'),
    ('기타예배', 'Other'),
    ('출석수(계)', 'Attended'),
    ('출석율(%)', 'Rate'),
    ('출결재적', 'Roll'),
    ('대면예배', 'In-person'),
    ('온라인예배', 'Online'),
    ('기타예배', 'Other'),
    ('출석수(계)', 'Attended'),
    ('출석율(%)', 'Rate'),
    ('일회성결석', 'One-off'),
    ('관리가능', 'Long · manageable'),
    ('관리불가능', 'Long · not manageable'),
    ('결석수(계)', 'Absent'),
    ('결석율(%)', 'Rate'),
  ];

  String _fmt(num? v, int col) {
    if (v == null) return '–';
    if (col == 5 || col == 11 || col == 16) return '${(v * 100).toStringAsFixed(1)}%';
    return NumberFormat.decimalPattern().format(v);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final title = "예배 출결 현황 · ${DateFormat('MMMM yyyy').format(_month)}";
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
      appBar: AppBar(
        centerTitle: true,
        title: Text("Tribe monthly report", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(_purple))),
        actions: [
          IconButton(tooltip: tr("Reload"), icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 40), children: [
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: Text(DateFormat('MMMM yyyy').format(_month)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E6B3A)),
            onPressed: _loading || _rows.isEmpty ? null : _downloadExcel,
            icon: const Icon(Icons.grid_on_rounded, size: 18),
            label: const Text("Download Excel"),
          ),
          OutlinedButton.icon(
            onPressed: _loading || _rows.isEmpty ? null : () => TableExport.showMenu(context, _table),
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text("PDF / Print"),
          ),
        ]),
        const SizedBox(height: 8),
        Text(title, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: AppPalette.fg(_purple))),
        Text("$_tribe · from the members list and Service Attendance (real time). Tap a number to correct it before downloading.",
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Padding(padding: const EdgeInsets.all(20), child: Text("Couldn't compile the report (run 20_round19.sql): $_error", textAlign: TextAlign.center))
        else
          _grid(),
        const SizedBox(height: 12),
        if (!_loading && _error == null) _notes(),
      ]),
    );
  }

  Widget _cell(String t, double w, {double h = 30, Color? bg, bool bold = false, Color? fg, int lines = 1, VoidCallback? onTap, bool edited = false}) {
    Widget c = Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: AppPalette.bg(edited ? const Color(0xFFFFF3C4) : bg ?? Colors.white),
        border: Border.all(color: AppPalette.line(Colors.black26), width: 0.6),
      ),
      child: Text(t,
          textAlign: TextAlign.center,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.merriweather(fontSize: 10.5, height: 1.15, fontWeight: bold ? FontWeight.w800 : FontWeight.normal, color: AppPalette.fg(fg ?? Colors.black87))),
    );
    if (onTap != null) c = InkWell(onTap: onTap, child: c);
    return c;
  }

  Widget _grid() {
    const wA = 78.0, wB = 110.0, w = 76.0;
    final groupRow = Row(mainAxisSize: MainAxisSize.min, children: [
      _cell('지파명', wA, h: 30, bg: _cHead, bold: true),
      _cell('교회명', wB, h: 30, bg: _cHead, bold: true),
      for (final g in _groups) _cell("${g.$1}\n${g.$2}", w * g.$3, h: 30, bg: g.$4, bold: true, lines: 2),
    ]);
    final headRow = Row(mainAxisSize: MainAxisSize.min, children: [
      _cell('Tribe', wA, h: 44, bg: _cHead, fg: Colors.grey.shade700),
      _cell('Church', wB, h: 44, bg: _cHead, fg: Colors.grey.shade700),
      for (int i = 0; i < _heads.length; i++)
        _cell("${_heads[i].$1}\n${_heads[i].$2}", w, h: 44, bold: true, lines: 3, bg: i < 6 ? _cNew : (i < 12 ? _cHead : _cAbs)),
    ]);
    Widget dataRow(String church, List<num?> v, {Map<String, dynamic>? r, bool total = false, required bool first}) => Row(mainAxisSize: MainAxisSize.min, children: [
          _cell(first ? _tribe : '', wA, bg: _cHead, bold: true),
          _cell(church, wB, bg: total ? _cHead : null, bold: true),
          for (int i = 0; i < v.length; i++)
            _cell(
              _fmt(v[i], i),
              w,
              bold: total || i == 4 || i == 10 || i == 15,
              bg: total ? _cHead : (i == 5 || i == 11 || i == 16 ? const Color(0xFFF7F7F7) : null),
              edited: r != null && _editable.containsKey(i) && (_edits[r['church']]?.containsKey(_editable[i]) ?? false),
              onTap: r != null && _editable.containsKey(i) ? () => _edit(r, _editable[i]!, "${_heads[i].$2} (${_heads[i].$1})") : null,
            ),
        ]);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          groupRow,
          headRow,
          for (int i = 0; i < _rows.length; i++) dataRow(_rows[i]['church'].toString(), _cols(_rows[i]), r: _rows[i], first: i == 0),
          dataRow('계 (Total)', _total, total: true, first: false),
        ]),
      ),
    );
  }

  Widget _notes() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppPalette.line(Colors.black12))),
        child: DefaultTextStyle.merge(
          style: TextStyle(fontSize: 11.5, height: 1.4, color: AppPalette.fg(Colors.blueGrey.shade800)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("How it is compiled", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppPalette.fg(_purple))),
            const SizedBox(height: 4),
            const Text("• Roll (출결재적): the church's members, Dropped members left out. MOU and 24Dept are churches of their own."),
            const Text("• Each member counts once: in-person if they attended in person at least once this month, else online, else another way."),
            const Text("• Other (기타예배) = roll − in-person − online − absentees, as in the template (it includes members who were not reported)."),
            Text("• Absentees: no attendance this month. One-off: fewer than $_long services missed in a row; long-term: $_long or more."),
            const Text("• Long-term absentees are manageable (관리가능) when their latest care log of the last 90 days has a workable outcome."),
            const Text("• New members (전월 입교자): status 입교, joined last month (date joined or course completion date)."),
            const Text("• Corrected numbers show in yellow and are used in the downloads."),
          ]),
        ),
      );

  // -------------------------------------------------------------- downloads

  ExportTable _table() => ExportTable(
        title: "예배 출결 현황 – ${DateFormat('MMMM yyyy').format(_month)}",
        subtitle: _tribe,
        headers: ['교회명', for (final h in _heads) "${h.$1} (${h.$2})"],
        rows: [
          for (final r in _rows) [r['church'].toString(), for (int i = 0; i < _heads.length; i++) _fmt(_cols(r)[i], i)],
          ['계', for (int i = 0; i < _heads.length; i++) _fmt(_total[i], i)],
        ],
      );

  /// The tribe's template: same columns (A–T), headers, colours and formulas.
  Future<void> _downloadExcel() async {
    try {
      final book = xl.Excel.createExcel();
      final def = book.getDefaultSheet() ?? 'Sheet1';
      book.rename(def, '예배출석현황');
      final s = book['예배출석현황'];
      xl.CellIndex at(int col, int row) => xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);
      final thin = xl.Border(borderStyle: xl.BorderStyle.Thin);
      xl.CellStyle st({String? bg, bool bold = false, bool wrap = false, xl.NumFormat? fmt, int size = 11}) => xl.CellStyle(
            bold: bold,
            fontSize: size,
            backgroundColorHex: bg == null ? xl.ExcelColor.none : xl.ExcelColor.fromHexString(bg),
            horizontalAlign: xl.HorizontalAlign.Center,
            verticalAlign: xl.VerticalAlign.Center,
            textWrapping: wrap ? xl.TextWrapping.WrapText : null,
            leftBorder: thin,
            rightBorder: thin,
            topBorder: thin,
            bottomBorder: thin,
            numberFormat: fmt ?? xl.NumFormat.standard_0,
          );
      void put(int col, int row, xl.CellValue v, xl.CellStyle style) {
        final c = s.cell(at(col, row));
        c.value = v;
        c.cellStyle = style;
      }

      const head = '#E6E4E4', newBg = '#FBE4D5', absBg = '#DDEBF7';
      // 1: title
      s.merge(at(0, 0), at(18, 0), customValue: xl.TextCellValue('예배 출결 현황'));
      s.cell(at(0, 0)).cellStyle = xl.CellStyle(bold: true, fontSize: 26, horizontalAlign: xl.HorizontalAlign.Center, verticalAlign: xl.VerticalAlign.Center);
      put(19, 1, xl.TextCellValue(DateFormat('yyyy-MM').format(_month)), st());
      // 3–5: headers
      void mergeHead(int c1, int r1, int c2, int r2, String text, String bg) {
        s.merge(at(c1, r1), at(c2, r2), customValue: xl.TextCellValue(text));
        for (int c = c1; c <= c2; c++) {
          for (int r = r1; r <= r2; r++) {
            s.cell(at(c, r)).cellStyle = st(bg: bg, bold: true, wrap: true, size: 10);
          }
        }
      }

      mergeHead(0, 2, 0, 4, '지파명', head);
      mergeHead(1, 2, 1, 4, '교회명', head);
      mergeHead(2, 2, 7, 2, '1)전월 입교자 출석 현황', newBg);
      mergeHead(8, 2, 13, 2, '2)전성도 출석 현황', head);
      mergeHead(14, 2, 18, 2, '3)결석 현황', absBg);
      const long = [
        '전월\n입교자 수\n(작성기준참고)', '대면예배\n(정식 예배시간과 \n장소 출석)', '온라인예배\n(정식 예배시간 \n출석)', '기타예배\n정식 예배시간 외\n(대체예배 포함)', '출석수(계)', '출석율(%)',
        '출결재적\n(작성기준참고)', '대면예배\n(정식 예배시간과 \n장소 출석자)', '온라인예배\n(정식 예배시간 \n출석)', '기타예배\n정식 예배시간 외\n(대체예배 포함)', '출석수(계)', '출석율(%)',
        '일회성결석\n(연속8회미만)',
      ];
      for (int i = 0; i < long.length; i++) {
        mergeHead(2 + i, 3, 2 + i, 4, long[i], i < 6 ? newBg : (i < 12 ? head : absBg));
      }
      mergeHead(15, 3, 16, 3, '장기결석\n(연속8회이상)', absBg);
      mergeHead(17, 3, 17, 4, '결석수(계)', absBg);
      mergeHead(18, 3, 18, 4, '결석율(%)', absBg);
      put(15, 4, xl.TextCellValue('관리가능'), st(bg: absBg, bold: true, size: 10));
      put(16, 4, xl.TextCellValue('관리불가능'), st(bg: absBg, bold: true, size: 10));
      put(19, 4, xl.TextCellValue('검산'), st(bold: true, size: 10));

      // 6…: one row per church, the same formulas as the template
      final first = 5;
      final last = first + _rows.length - 1;
      final pct = xl.NumFormat.standard_10;
      for (int i = 0; i < _rows.length; i++) {
        final r = _rows[i];
        final row = first + i, n = row + 1; // n = the Excel row number
        put(1, row, xl.TextCellValue(r['church'].toString()), st(bold: true));
        put(2, row, xl.IntCellValue(_v(r, 'new_total')), st());
        put(3, row, xl.IntCellValue(_v(r, 'new_inperson')), st());
        put(4, row, xl.IntCellValue(_v(r, 'new_online')), st());
        put(5, row, xl.IntCellValue(_v(r, 'new_other')), st());
        put(6, row, xl.FormulaCellValue('SUM(D$n:F$n)'), st(bold: true));
        put(7, row, xl.FormulaCellValue('IFERROR(G$n/C$n,0)'), st(fmt: pct));
        put(8, row, xl.IntCellValue(_v(r, 'roll')), st());
        put(9, row, xl.IntCellValue(_v(r, 'inperson')), st());
        put(10, row, xl.IntCellValue(_v(r, 'online')), st());
        put(11, row, xl.FormulaCellValue('I$n-(J$n+K$n+R$n)'), st());
        put(12, row, xl.FormulaCellValue('SUM(J$n:L$n)'), st(bold: true));
        put(13, row, xl.FormulaCellValue('IFERROR(M$n/I$n,0)'), st(fmt: pct));
        put(14, row, xl.IntCellValue(_v(r, 'absent_once')), st());
        put(15, row, xl.IntCellValue(_v(r, 'long_manageable')), st());
        put(16, row, xl.IntCellValue(_v(r, 'long_unmanageable')), st());
        put(17, row, xl.FormulaCellValue('SUM(O$n:Q$n)'), st(bold: true));
        put(18, row, xl.FormulaCellValue('IFERROR(R$n/I$n,0)'), st(fmt: pct));
        put(19, row, xl.FormulaCellValue('I$n=M$n+R$n'), st());
      }
      if (_rows.isNotEmpty) {
        s.merge(at(0, first), at(0, last), customValue: xl.TextCellValue(_tribe));
        for (int r = first; r <= last; r++) {
          s.cell(at(0, r)).cellStyle = st(bg: head, bold: true);
        }
      }
      // total row (계)
      final t = last + 1, tn = t + 1, a = first + 1, b = last + 1;
      put(0, t, xl.TextCellValue(''), st(bg: head));
      put(1, t, xl.TextCellValue('계'), st(bg: head, bold: true));
      const cols = 'CDEFGHIJKLMNOPQRS';
      for (int c = 2; c <= 18; c++) {
        final col = cols[c - 2];
        final f = switch (col) {
          'G' => 'SUM(D$tn:F$tn)',
          'H' => 'IFERROR(G$tn/C$tn,0)',
          'M' => 'SUM(J$tn:L$tn)',
          'N' => 'IFERROR(M$tn/I$tn,0)',
          'R' => 'SUM(O$tn:Q$tn)',
          'S' => 'IFERROR(R$tn/I$tn,0)',
          _ => 'SUM($col$a:$col$b)',
        };
        put(c, t, xl.FormulaCellValue(f), st(bg: head, bold: true, fmt: const {'H', 'N', 'S'}.contains(col) ? pct : null));
      }
      put(19, t, xl.FormulaCellValue('I$tn=M$tn+R$tn'), st(bg: head));

      // the template's column widths and header heights
      const widths = [17.6, 30.3, 14.3, 18.1, 13.0, 13.0, 12.3, 11.7, 14.3, 18.1, 13.0, 13.0, 12.3, 11.7, 14.3, 11.7, 13.0, 12.3, 11.7, 6.5];
      for (int c = 0; c < widths.length; c++) {
        s.setColumnWidth(c, widths[c]);
      }
      s.setRowHeight(0, 40);
      s.setRowHeight(2, 26.25);
      s.setRowHeight(3, 37.15);
      s.setRowHeight(4, 41.5);

      final name = '예배출석현황_${DateFormat('yyyy_MM').format(_month)}.xlsx';
      if (kIsWeb) {
        book.save(fileName: name);
      } else {
        final bytes = book.encode();
        if (bytes == null) throw 'Could not build the file';
        await FilePicker.platform.saveFile(dialogTitle: 'Save Excel file', fileName: name, bytes: Uint8List.fromList(bytes));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Downloaded $name"), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Excel export failed: $e"), backgroundColor: Colors.red.shade700));
    }
  }
}
