import 'package:flutter/material.dart';

/// One look for every compilation summary table (all modules + Ranking):
/// the header row and the "General total" row get their own fills, and
/// header text is a little larger than the cell text.
class CompStyle {
  CompStyle._();

  /// Header row: soft lavender with deep purple text
  static const Color headerBg = Color(0xFFE9DDFB);
  static const Color headerFg = Color(0xFF3B0764);

  /// "General total" row: warm gold tint
  static const Color totalBg = Color(0xFFFFF1CC);
  static const Color totalFg = Color(0xFF5B3A00);

  /// Unit label column of the total block
  static const Color labelBg = Color(0xFFF6F0FF);

  /// Cell text size in the tables, and the slightly larger header size
  static const double cellFont = 9.5;
  static const double headerFont = 10.5;

  /// Space between a summary table and its card edge (about 1 cm)
  static const double tableSideMargin = 38.0;

  static Color rateColor(double rate) {
    if (rate >= 80) return const Color(0xFF1B7F3B);
    if (rate >= 50) return const Color(0xFFB26A00);
    return const Color(0xFFB3261E);
  }
}
