import 'dart:math' as math;

/// A small spreadsheet formula engine.
///
/// Cells that start with "=" are formulas. Supported:
///   numbers, "text", TRUE / FALSE, cell references (A1, $B$2) and ranges (A1:C5)
///   + - * / ^ & (join text), comparisons = <> < > <= >=, parentheses
///   SUM AVERAGE AVG MIN MAX COUNT COUNTA ROUND ABS IF AND OR NOT
///   CONCAT LEN UPPER LOWER TRIM SUMIF COUNTIF TODAY
/// Errors show as #ERR!, #REF!, #DIV/0!, #NAME? or #CYCLE!.
class FormulaError implements Exception {
  final String code;
  const FormulaError(this.code);
  @override
  String toString() => code;
}

class SheetEngine {
  /// Raw text of the cell at (row, col), 0-based; '' when empty.
  final String Function(int row, int col) raw;
  final int maxRows;
  final int maxCols;

  SheetEngine(this.raw, {this.maxRows = 100000, this.maxCols = 702});

  final Map<(int, int), Object> _cache = {};
  final Set<(int, int)> _evaluating = {};

  void clearCache() => _cache.clear();

  static String colName(int c) {
    var n = c + 1;
    var s = '';
    while (n > 0) {
      final m = (n - 1) % 26;
      s = String.fromCharCode(65 + m) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static int colIndex(String letters) {
    var n = 0;
    for (final ch in letters.toUpperCase().codeUnits) {
      n = n * 26 + (ch - 64);
    }
    return n - 1;
  }

  /// "B3" -> (2, 1)
  static (int, int)? parseRef(String ref) {
    final m = RegExp(r'^\$?([A-Za-z]{1,3})\$?(\d{1,6})$').firstMatch(ref.trim());
    if (m == null) return null;
    final row = int.parse(m.group(2)!) - 1;
    if (row < 0) return null;
    return (row, colIndex(m.group(1)!));
  }

  /// Value of a cell: num, String or bool (formulas evaluated).
  Object valueOf(int r, int c) {
    final key = (r, c);
    final hit = _cache[key];
    if (hit != null) return hit;
    final text = raw(r, c);
    Object v;
    if (text.startsWith('=')) {
      if (_evaluating.contains(key)) throw const FormulaError('#CYCLE!');
      _evaluating.add(key);
      try {
        v = evaluate(text.substring(1));
      } finally {
        _evaluating.remove(key);
      }
    } else {
      v = literal(text);
    }
    _cache[key] = v;
    return v;
  }

  static Object literal(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    final n = num.tryParse(t.replaceAll(',', ''));
    if (n != null && RegExp(r'^[-+]?[\d,]*\.?\d+(e[-+]?\d+)?$', caseSensitive: false).hasMatch(t)) return n;
    if (t.toUpperCase() == 'TRUE') return true;
    if (t.toUpperCase() == 'FALSE') return false;
    return text;
  }

  /// What the grid shows for a cell.
  String display(int r, int c) {
    final text = raw(r, c);
    if (!text.startsWith('=')) return text;
    try {
      return format(valueOf(r, c));
    } on FormulaError catch (e) {
      return e.code;
    } catch (_) {
      return '#ERR!';
    }
  }

  static String format(Object v) {
    if (v is bool) return v ? 'TRUE' : 'FALSE';
    if (v is num) {
      if (v.isNaN || v.isInfinite) return '#NUM!';
      if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
      var s = v.toStringAsFixed(10);
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      return s;
    }
    return v.toString();
  }

  Object evaluate(String formula) {
    final p = _Parser(_tokenize(formula), this);
    final v = p.parseExpression();
    if (!p.atEnd) throw const FormulaError('#ERR!');
    return v is _Range ? (v.values.isEmpty ? '' : v.values.first) : v;
  }

  // ---------------------------------------------------------------
  static List<_Tok> _tokenize(String s) {
    final out = <_Tok>[];
    int i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        i++;
        continue;
      }
      if (ch == '"') {
        final sb = StringBuffer();
        i++;
        while (i < s.length) {
          if (s[i] == '"') {
            if (i + 1 < s.length && s[i + 1] == '"') {
              sb.write('"');
              i += 2;
              continue;
            }
            break;
          }
          sb.write(s[i]);
          i++;
        }
        if (i >= s.length) throw const FormulaError('#ERR!');
        i++;
        out.add(_Tok('str', sb.toString()));
        continue;
      }
      final number = RegExp(r'^(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?').matchAsPrefix(s.substring(i));
      if (number != null) {
        out.add(_Tok('num', number.group(0)!));
        i += number.group(0)!.length;
        continue;
      }
      final word = RegExp(r'^\$?[A-Za-z_][A-Za-z0-9_.]*\$?\d*').matchAsPrefix(s.substring(i));
      if (word != null) {
        out.add(_Tok('word', word.group(0)!));
        i += word.group(0)!.length;
        continue;
      }
      final two = i + 1 < s.length ? s.substring(i, i + 2) : '';
      if (two == '<=' || two == '>=' || two == '<>') {
        out.add(_Tok('op', two));
        i += 2;
        continue;
      }
      if ('+-*/^&=<>(),:;%'.contains(ch)) {
        out.add(_Tok('op', ch == ';' ? ',' : ch));
        i++;
        continue;
      }
      throw const FormulaError('#ERR!');
    }
    return out;
  }
}

class _Tok {
  final String type; // num | str | word | op
  final String text;
  const _Tok(this.type, this.text);
}

class _Range {
  final List<Object> values; // row by row
  const _Range(this.values);
}

class _Parser {
  final List<_Tok> t;
  final SheetEngine e;
  int i = 0;
  _Parser(this.t, this.e);

  bool get atEnd => i >= t.length;
  _Tok? get peek => atEnd ? null : t[i];
  bool _isOp(String s) => !atEnd && t[i].type == 'op' && t[i].text == s;

  void _expect(String s) {
    if (!_isOp(s)) throw const FormulaError('#ERR!');
    i++;
  }

  // number conversions ------------------------------------------------
  static num toNum(Object v) {
    if (v is num) return v;
    if (v is bool) return v ? 1 : 0;
    if (v is _Range) return v.values.isEmpty ? 0 : toNum(v.values.first);
    final s = v.toString().trim();
    if (s.isEmpty) return 0;
    final n = num.tryParse(s.replaceAll(',', ''));
    if (n == null) throw const FormulaError('#VALUE!');
    return n;
  }

  static bool toBool(Object v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toUpperCase();
    if (s == 'TRUE') return true;
    if (s == 'FALSE' || s.isEmpty) return false;
    throw const FormulaError('#VALUE!');
  }

  static String toText(Object v) => v is _Range ? (v.values.isEmpty ? '' : SheetEngine.format(v.values.first)) : SheetEngine.format(v);

  // grammar -------------------------------------------------------------
  Object parseExpression() => _comparison();

  Object _comparison() {
    var left = _concat();
    while (!atEnd && t[i].type == 'op' && const ['=', '<>', '<', '>', '<=', '>='].contains(t[i].text)) {
      final op = t[i++].text;
      final right = _concat();
      left = _compare(left, right, op);
    }
    return left;
  }

  static bool _compare(Object a, Object b, String op) {
    int c;
    final an = a is num || (a is String && num.tryParse(a.trim()) != null && a.trim().isNotEmpty);
    final bn = b is num || (b is String && num.tryParse(b.trim()) != null && b.trim().isNotEmpty);
    if (an && bn) {
      c = toNum(a).compareTo(toNum(b));
    } else {
      c = toText(a).toLowerCase().compareTo(toText(b).toLowerCase());
    }
    switch (op) {
      case '=':
        return c == 0;
      case '<>':
        return c != 0;
      case '<':
        return c < 0;
      case '>':
        return c > 0;
      case '<=':
        return c <= 0;
      default:
        return c >= 0;
    }
  }

  Object _concat() {
    var left = _additive();
    while (_isOp('&')) {
      i++;
      left = toText(left) + toText(_additive());
    }
    return left;
  }

  Object _additive() {
    var left = _term();
    while (_isOp('+') || _isOp('-')) {
      final op = t[i++].text;
      final r = _term();
      left = op == '+' ? toNum(left) + toNum(r) : toNum(left) - toNum(r);
    }
    return left;
  }

  Object _term() {
    var left = _power();
    while (_isOp('*') || _isOp('/')) {
      final op = t[i++].text;
      final r = _power();
      if (op == '*') {
        left = toNum(left) * toNum(r);
      } else {
        final d = toNum(r);
        if (d == 0) throw const FormulaError('#DIV/0!');
        left = toNum(left) / d;
      }
    }
    return left;
  }

  Object _power() {
    var left = _unary();
    while (_isOp('^')) {
      i++;
      final r = toNum(_unary());
      left = _pow(toNum(left), r);
    }
    return left;
  }

  static num _pow(num a, num b) {
    final r = math.pow(a, b);
    if (r.isNaN || r.isInfinite) throw const FormulaError('#NUM!');
    return r;
  }

  Object _unary() {
    if (_isOp('-')) {
      i++;
      return -toNum(_unary());
    }
    if (_isOp('+')) {
      i++;
      return toNum(_unary());
    }
    var v = _primary();
    if (_isOp('%')) {
      i++;
      v = toNum(v) / 100;
    }
    return v;
  }

  Object _primary() {
    final tok = peek;
    if (tok == null) throw const FormulaError('#ERR!');
    if (tok.type == 'num') {
      i++;
      return num.parse(tok.text);
    }
    if (tok.type == 'str') {
      i++;
      return tok.text;
    }
    if (tok.type == 'op' && tok.text == '(') {
      i++;
      final v = parseExpression();
      _expect(')');
      return v;
    }
    if (tok.type == 'word') {
      i++;
      final w = tok.text;
      if (_isOp('(')) {
        i++;
        final args = <Object>[];
        if (!_isOp(')')) {
          args.add(parseExpression());
          while (_isOp(',')) {
            i++;
            args.add(parseExpression());
          }
        }
        _expect(')');
        return _call(w.toUpperCase(), args);
      }
      final up = w.toUpperCase();
      if (up == 'TRUE') return true;
      if (up == 'FALSE') return false;
      final a = SheetEngine.parseRef(w);
      if (a == null) throw const FormulaError('#NAME?');
      if (_isOp(':')) {
        i++;
        final nt = peek;
        if (nt == null || nt.type != 'word') throw const FormulaError('#REF!');
        i++;
        final b = SheetEngine.parseRef(nt.text);
        if (b == null) throw const FormulaError('#REF!');
        return _range(a, b);
      }
      if (a.$1 >= e.maxRows || a.$2 >= e.maxCols) throw const FormulaError('#REF!');
      return e.valueOf(a.$1, a.$2);
    }
    throw const FormulaError('#ERR!');
  }

  _Range _range((int, int) a, (int, int) b) {
    final r1 = a.$1 < b.$1 ? a.$1 : b.$1, r2 = a.$1 < b.$1 ? b.$1 : a.$1;
    final c1 = a.$2 < b.$2 ? a.$2 : b.$2, c2 = a.$2 < b.$2 ? b.$2 : a.$2;
    if ((r2 - r1 + 1) * (c2 - c1 + 1) > 200000) throw const FormulaError('#REF!');
    final vals = <Object>[];
    for (int r = r1; r <= r2 && r < e.maxRows; r++) {
      for (int c = c1; c <= c2 && c < e.maxCols; c++) {
        vals.add(e.valueOf(r, c));
      }
    }
    return _Range(vals);
  }

  /// All values of the arguments, ranges flattened.
  static List<Object> _flat(List<Object> args) => [for (final a in args) ...(a is _Range ? a.values : [a])];

  static List<num> _nums(List<Object> args) {
    final out = <num>[];
    for (final a in args) {
      if (a is _Range) {
        for (final v in a.values) {
          if (v is num) {
            out.add(v);
          } else if (v is String && v.trim().isNotEmpty && num.tryParse(v.trim()) != null) {
            out.add(num.parse(v.trim()));
          }
        }
      } else {
        out.add(toNum(a));
      }
    }
    return out;
  }

  static bool _matches(Object v, Object criterion) {
    final c = toText(criterion).trim();
    final m = RegExp(r'^(<=|>=|<>|<|>|=)?(.*)$').firstMatch(c)!;
    final op = m.group(1) ?? '=';
    final target = SheetEngine.literal(m.group(2)!);
    return _compare(v, target, op);
  }

  Object _call(String name, List<Object> args) {
    switch (name) {
      case 'SUM':
        return _nums(args).fold<num>(0, (a, b) => a + b);
      case 'AVERAGE':
      case 'AVG':
        final n = _nums(args);
        if (n.isEmpty) throw const FormulaError('#DIV/0!');
        return n.fold<num>(0, (a, b) => a + b) / n.length;
      case 'MIN':
        final n = _nums(args);
        return n.isEmpty ? 0 : n.reduce((a, b) => a < b ? a : b);
      case 'MAX':
        final n = _nums(args);
        return n.isEmpty ? 0 : n.reduce((a, b) => a > b ? a : b);
      case 'COUNT':
        return _nums(args.map((a) => a is _Range ? a : _Range([a])).toList()).length;
      case 'COUNTA':
        return _flat(args).where((v) => toText(v).isNotEmpty).length;
      case 'ROUND':
        if (args.isEmpty) throw const FormulaError('#ERR!');
        final x = toNum(args[0]);
        final d = args.length > 1 ? toNum(args[1]).toInt() : 0;
        final f = _pow(10, d.abs());
        return d >= 0 ? (x * f).round() / f : (x / f).round() * f;
      case 'ABS':
        if (args.isEmpty) throw const FormulaError('#ERR!');
        return toNum(args[0]).abs();
      case 'IF':
        if (args.length < 2) throw const FormulaError('#ERR!');
        return toBool(args[0]) ? args[1] : (args.length > 2 ? args[2] : false);
      case 'AND':
        return _flat(args).every(toBool);
      case 'OR':
        return _flat(args).any(toBool);
      case 'NOT':
        if (args.isEmpty) throw const FormulaError('#ERR!');
        return !toBool(args[0]);
      case 'CONCAT':
      case 'CONCATENATE':
        return _flat(args).map(toText).join();
      case 'LEN':
        return args.isEmpty ? 0 : toText(args[0]).length;
      case 'UPPER':
        return args.isEmpty ? '' : toText(args[0]).toUpperCase();
      case 'LOWER':
        return args.isEmpty ? '' : toText(args[0]).toLowerCase();
      case 'TRIM':
        return args.isEmpty ? '' : toText(args[0]).trim().replaceAll(RegExp(r'\s+'), ' ');
      case 'COUNTIF':
        if (args.length < 2 || args[0] is! _Range) throw const FormulaError('#ERR!');
        return (args[0] as _Range).values.where((v) => _matches(v, args[1])).length;
      case 'SUMIF':
        if (args.length < 2 || args[0] is! _Range) throw const FormulaError('#ERR!');
        final crit = (args[0] as _Range).values;
        final sum = args.length > 2 && args[2] is _Range ? (args[2] as _Range).values : crit;
        num total = 0;
        for (int k = 0; k < crit.length && k < sum.length; k++) {
          if (_matches(crit[k], args[1])) {
            final v = sum[k];
            if (v is num) total += v;
            if (v is String && num.tryParse(v.trim()) != null) total += num.parse(v.trim());
          }
        }
        return total;
      case 'TODAY':
        final d = DateTime.now();
        return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      default:
        throw const FormulaError('#NAME?');
    }
  }
}
