import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';

/// Chart axis labels that never overlap:
/// · fit in their space → straight
/// · too long for their space → tilted ~35°, cut with "…" (full name on
///   hover / long-press)
/// `count` = how many labels share the axis.
Widget axisLabel(String text, TitleMeta meta, {required int count, TextStyle? style, double maxWidth = 84}) {
  final st = style ?? const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold);
  final slot = meta.parentAxisSize / math.max(1, count);
  final tp = TextPainter(text: TextSpan(text: text, style: st), maxLines: 1, textDirection: TextDirection.ltr)..layout();
  if (tp.width <= slot - 4) {
    return Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: st, maxLines: 1));
  }
  return Tooltip(
    message: text,
    child: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Transform.rotate(
        angle: -0.6, // about 35°
        alignment: Alignment.topRight,
        child: SizedBox(
          width: math.min(maxWidth, tp.width + 2),
          child: Text(text, style: st, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right),
        ),
      ),
    ),
  );
}

/// Room under the axis for tilted labels.
const double kTiltedAxisReserve = 62;

/// Many bars: the chart gets wider than the screen and scrolls sideways, so
/// every bar keeps its room (about `slot` px per bar).
Widget chartScroll({required int bars, required Widget child, double slot = 46}) {
  return LayoutBuilder(builder: (context, c) {
    final need = bars * slot + 60;
    if (!c.hasBoundedWidth || need <= c.maxWidth) return child;
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(width: need, height: c.hasBoundedHeight ? c.maxHeight - 10 : null, child: child),
      ),
    );
  });
}
