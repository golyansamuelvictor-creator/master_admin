import 'package:flutter/material.dart';

/// A toolbar line that never gets cut off: fills the width on wide screens
/// and scrolls sideways on small ones.
class HScroll extends StatelessWidget {
  final Widget child;
  const HScroll({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth.isFinite ? box.maxWidth : 0),
            child: child,
          ),
        ),
      );
}
