import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';

import '../core/app_palette.dart';
import '../core/app_sizes.dart';
import '../core/i18n.dart';

/// The standard card: duty-card height, title + optional one detail line,
/// never taller (long text ends with "…").
class CompactCard extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? background;
  final Color? titleColor;
  final double? height;
  final bool selected;

  const CompactCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.background,
    this.titleColor,
    this.height,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasSub = (subtitle ?? '').isNotEmpty;
    return SizedBox(
      height: height ?? (hasSub ? AppSizes.listCard : AppSizes.card),
      child: Material(
        color: AppPalette.bg(background ?? (selected ? const Color(0xFFF1E8FB) : Colors.white)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppPalette.line(selected ? const Color(0xFF4A148C) : Colors.black.withValues(alpha: 0.08))),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.merriweather(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppPalette.fg(titleColor ?? Colors.black87))),
                  if (hasSub)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.merriweather(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
                    ),
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Cards side by side on wide screens (1, 2 or 3 columns), each card its
/// standard height. [shrinkWrap] for use inside another scroll view.
class CardGrid extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double extent;
  final bool shrinkWrap;
  final EdgeInsets? padding;
  const CardGrid({super.key, required this.itemCount, required this.itemBuilder, this.extent = AppSizes.card, this.shrinkWrap = false, this.padding});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return GridView.builder(
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        padding: padding ?? EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: AppSizes.columns(c.maxWidth),
          mainAxisExtent: extent,
          mainAxisSpacing: 8,
          crossAxisSpacing: 10,
        ),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    });
  }
}
