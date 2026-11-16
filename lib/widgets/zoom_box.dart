import 'package:flutter/gestures.dart' show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';

/// Zoom in / out on a table or chart:
/// · the small − / + / reset buttons in its top-right corner
/// · Ctrl + mouse wheel (computers)
/// · once zoomed: drag to move around, pinch to zoom further (phones)
/// At normal size it behaves exactly like before (the page scrolls normally).
class ZoomBox extends StatefulWidget {
  final Widget child;
  final double maxScale;
  const ZoomBox({super.key, required this.child, this.maxScale = 3});

  @override
  State<ZoomBox> createState() => _ZoomBoxState();
}

class _ZoomBoxState extends State<ZoomBox> {
  final _tc = TransformationController();
  double _scale = 1;

  void _set(double s) {
    s = s.clamp(1.0, widget.maxScale).toDouble();
    setState(() => _scale = s);
    _tc.value = Matrix4.diagonal3Values(s, s, 1);
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (!ctrl) return;
    _set(_scale * (e.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15));
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Widget _btn(IconData i, String tip, VoidCallback? f) => Tooltip(
        message: tr(tip),
        child: InkWell(
          onTap: f,
          borderRadius: BorderRadius.circular(6),
          child: Padding(padding: const EdgeInsets.all(3), child: Icon(i, size: 16, color: AppPalette.fg(f == null ? Colors.black26 : Colors.black54))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final zoomed = _scale > 1.01;
    final body = zoomed
        ? InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: widget.maxScale,
            clipBehavior: Clip.hardEdge,
            onInteractionEnd: (_) {
              final s = _tc.value.getMaxScaleOnAxis();
              if ((s - _scale).abs() > 0.01) setState(() => _scale = s < 1.01 ? 1 : s);
            },
            child: widget.child,
          )
        : widget.child;
    return Listener(
      onPointerSignal: _onSignal,
      child: Stack(children: [
        body,
        Positioned(
          top: 2,
          right: 2,
          child: Container(
            decoration: BoxDecoration(
              color: AppPalette.bg(Colors.white.withValues(alpha: 0.85)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppPalette.line(Colors.black12)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _btn(Icons.zoom_out_rounded, "Zoom out", zoomed ? () => _set(_scale / 1.25) : null),
              _btn(Icons.zoom_in_rounded, "Zoom in (Ctrl + mouse wheel)", _scale < widget.maxScale ? () => _set(_scale * 1.25) : null),
              if (zoomed) _btn(Icons.fit_screen_rounded, "Normal size", () => _set(1)),
            ]),
          ),
        ),
      ]),
    );
  }
}
