import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';

/// One series of a [Bar3DChart] (e.g. "Goal" or "Overall").
class Bar3DSeries {
  final String name;
  final Color color;
  final List<double> values;
  final bool pct;
  const Bar3DSeries(this.name, this.color, this.values, {this.pct = false});
}

/// A plain 3D column chart: light coloured bars with a top and a side,
/// the value written above every bar, no grid. Each group (a center, a
/// region …) gets enough room for its bars and its name; when the screen is
/// too narrow the chart scrolls sideways instead of squeezing, so nothing
/// overlaps. Long names wrap on two lines, or tilt when the room is small.
class Bar3DChart extends StatelessWidget {
  final List<String> labels;
  final List<Bar3DSeries> series;
  final double height;
  const Bar3DChart({super.key, required this.labels, required this.series, this.height = 280});

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty || series.isEmpty) return const SizedBox.shrink();
    final n = labels.length;
    final perGroup = series.length * 30.0 + 26; // the least room a group needs
    return Column(children: [
      LayoutBuilder(builder: (ctx, bc) {
        final avail = bc.maxWidth.isFinite ? bc.maxWidth : 600.0;
        final slot = math.max(perGroup, math.min(170.0, (avail - 8) / n));
        final w = math.max(avail, slot * n + 8);
        final chart = SizedBox(
          width: w,
          height: height,
          child: CustomPaint(painter: _Bar3DPainter(labels: labels, series: series, slot: slot, dark: AppPalette.isDark)),
        );
        if (w <= avail + 0.5) return chart;
        return Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 8), child: chart),
        );
      }),
      const SizedBox(height: 6),
      Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 4, children: [
        for (final s in series)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 5),
            Text(s.name, style: GoogleFonts.merriweather(fontSize: 11.5, color: AppPalette.fg(Colors.black87))),
          ]),
      ]),
    ]);
  }
}

class _Bar3DPainter extends CustomPainter {
  final List<String> labels;
  final List<Bar3DSeries> series;
  final double slot;
  final bool dark;
  _Bar3DPainter({required this.labels, required this.series, required this.slot, required this.dark});

  String _fmt(double v, bool pct) {
    final r = (v * 10).round() / 10;
    final t = r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
    return pct ? '$t%' : t;
  }

  TextPainter _tp(String s, double size, Color c, {bool bold = false, double maxW = 200, int lines = 1}) => TextPainter(
        text: TextSpan(text: s, style: GoogleFonts.merriweather(fontSize: size, color: c, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: lines,
        ellipsis: '…',
      )..layout(maxWidth: maxW);

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    final s = series.length;
    final ink = dark ? const Color(0xEEFFFFFF) : const Color(0xDD1F1235);
    // labels: two lines when there is room, tilted otherwise
    final tilt = slot < 84;
    const double top = 26;
    final double bottom = tilt ? 64 : 44;
    final double chartH = size.height - top - bottom;
    if (chartH <= 20) return;
    final baseY = top + chartH;
    double maxV = 0;
    for (final x in series) {
      for (final v in x.values) {
        maxV = math.max(maxV, v);
      }
    }
    if (maxV <= 0) maxV = 1;

    final groupInner = slot - 18;
    final barW = math.min(30.0, groupInner / s * 0.72);
    final depth = barW * 0.35;
    final gap = (groupInner - barW * s - depth) / math.max(1, s);

    // floor line
    canvas.drawLine(Offset(4, baseY), Offset(size.width - 4, baseY), Paint()
      ..color = (dark ? Colors.white24 : const Color(0x33000000))
      ..strokeWidth = 1);

    for (int g = 0; g < n; g++) {
      final gx = 4 + slot * g + 9;
      for (int k = 0; k < s; k++) {
        final ser = series[k];
        final v = g < ser.values.length ? ser.values[g] : 0.0;
        final h = chartH * (v.clamp(0, maxV) / maxV) * 0.86;
        final x = gx + k * (barW + gap) + gap / 2;
        final yTop = baseY - h;
        final c = ser.color;
        // shadow, front, top, side
        canvas.drawRect(Rect.fromLTWH(x + depth * 0.5, baseY - 2, barW, 3), Paint()..color = const Color(0x14000000));
        canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x, yTop, barW, h)), Paint()..color = c);
        final topFace = Path()
          ..moveTo(x, yTop)
          ..lineTo(x + depth, yTop - depth)
          ..lineTo(x + barW + depth, yTop - depth)
          ..lineTo(x + barW, yTop)
          ..close();
        canvas.drawPath(topFace, Paint()..color = Color.lerp(c, Colors.white, 0.45)!);
        final side = Path()
          ..moveTo(x + barW, yTop)
          ..lineTo(x + barW + depth, yTop - depth)
          ..lineTo(x + barW + depth, baseY - depth)
          ..lineTo(x + barW, baseY)
          ..close();
        canvas.drawPath(side, Paint()..color = Color.lerp(c, Colors.black, 0.18)!);
        // value above the bar
        final tp = _tp(_fmt(v, ser.pct), 10, ink, bold: true, maxW: barW + depth + gap + 12);
        tp.paint(canvas, Offset(x + (barW + depth) / 2 - tp.width / 2, yTop - depth - tp.height - 1));
      }
      // the group's name
      final cx = 4 + slot * g + slot / 2;
      if (tilt) {
        final tp = _tp(labels[g], 10.5, ink, maxW: 110);
        canvas.save();
        canvas.translate(cx, baseY + 6);
        canvas.rotate(-math.pi / 5);
        tp.paint(canvas, Offset(-tp.width, 0));
        canvas.restore();
      } else {
        final tp = _tp(labels[g], 10.5, ink, maxW: slot - 6, lines: 2);
        tp.paint(canvas, Offset(cx - tp.width / 2, baseY + 6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Bar3DPainter old) => old.labels != labels || old.series != series || old.slot != slot || old.dark != dark;
}

/// Light colours for chart series (purple, blue, rose, teal, amber).
const List<Color> kLightSeries = [Color(0xFFB39DDB), Color(0xFF90CAF9), Color(0xFFF48FB1), Color(0xFF80CBC4), Color(0xFFFFCC80)];
