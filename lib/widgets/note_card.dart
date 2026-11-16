import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';

const Color _kPurple = Color(0xFF4A148C);
const Color _kBlue = Color(0xFF1E3A8A);

/// A note that reads well: a coloured header with an icon, then numbered
/// points, each in its own soft row; key words before a colon are bold
/// ("Roll: …"). Used for "How it is compiled" and similar explanations.
class NoteCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> points;
  final String? footer;
  final Color color;
  const NoteCard({super.key, required this.title, required this.points, this.icon = Icons.info_outline_rounded, this.footer, this.color = _kPurple});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(color.withValues(alpha: 0.18))),
        boxShadow: AppPalette.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppPalette.solid(color), AppPalette.solid(Color.lerp(color, _kBlue, 0.55)!)]),
          ),
          child: Row(children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Column(children: [
            for (int i = 0; i < points.length; i++) NotePoint(n: i + 1, text: points[i], color: color),
          ]),
        ),
        if ((footer ?? '').isNotEmpty) NoteHighlight(text: footer!, color: color),
      ]),
    );
  }
}

/// One numbered point; "Key: rest" shows the key in bold.
class NotePoint extends StatelessWidget {
  final int n;
  final String text;
  final Color color;
  const NotePoint({super.key, required this.n, required this.text, this.color = _kPurple});

  @override
  Widget build(BuildContext context) {
    final i = text.indexOf(': ');
    final hasKey = i > 0 && i < 48;
    final style = GoogleFonts.merriweather(fontSize: 12, height: 1.45, color: AppPalette.fg(Colors.black87));
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
      decoration: BoxDecoration(color: AppPalette.bg(color.withValues(alpha: 0.045)), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppPalette.solid(color), shape: BoxShape.circle),
          child: Text.rich(TextSpan(text: '$n'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: hasKey
              ? Text.rich(TextSpan(children: [
                  TextSpan(text: "${tr(text.substring(0, i))}: ", style: const TextStyle(fontWeight: FontWeight.w900)),
                  TextSpan(text: tr(text.substring(i + 2))),
                ]), style: style)
              : Text(text, style: style),
        ),
      ]),
    );
  }
}

/// A highlighted remark (amber bar on the left).
class NoteHighlight extends StatelessWidget {
  final String text;
  final Color color;
  const NoteHighlight({super.key, required this.text, this.color = _kPurple});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppPalette.bg(const Color(0xFFFFF8E1)),
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: AppPalette.solid(const Color(0xFFF59E0B)), width: 4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lightbulb_outline_rounded, size: 16, color: AppPalette.fg(const Color(0xFFB45309))),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.merriweather(fontSize: 12, height: 1.4, color: AppPalette.fg(Colors.black87)))),
        ]),
      );
}

/// Free text written by people (policies, standards, goals) shown as a
/// designed note: lines starting with "-", "•", "*" or "1." become numbered
/// points; a line starting with ">" or "Note:" becomes a highlight; other
/// lines are paragraphs.
class NoteBody extends StatelessWidget {
  final String text;
  final Color color;
  const NoteBody({super.key, required this.text, this.color = _kPurple});

  @override
  Widget build(BuildContext context) {
    final out = <Widget>[];
    int n = 0;
    for (final raw in text.split('\n')) {
      final l = raw.trim();
      if (l.isEmpty) {
        n = 0;
        continue;
      }
      final bullet = RegExp(r'^([-•*]|\d+[.)])\s+').firstMatch(l);
      if (bullet != null) {
        n++;
        out.add(NotePoint(n: n, text: l.substring(bullet.end), color: color));
      } else if (l.startsWith('>') || l.toLowerCase().startsWith('note:')) {
        out.add(Padding(padding: const EdgeInsets.only(bottom: 6), child: NoteHighlight(text: l.replaceFirst(RegExp(r'^>\s*'), ''), color: color)));
      } else {
        n = 0;
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SelectableText(l, style: GoogleFonts.merriweather(fontSize: 13, height: 1.5, color: AppPalette.fg(Colors.black87))),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }
}
