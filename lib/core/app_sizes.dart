import 'package:flutter/widgets.dart';

/// One set of sizes for every screen (General feedback: "use the duty cards
/// height as the standard height for all cards", screens use the full width).
class AppSizes {
  AppSizes._();

  /// Duty / item / menu cards (one line).
  static const double card = 50;

  /// Person and record cards in lists with a search bar (name + one detail line).
  static const double listCard = 50;

  /// Title bar cards: a little higher than item cards.
  static const double titleCard = 58;

  /// Space at the screen edges (about 0.3 cm): screens use the full width.
  static const double gutter = 12;

  /// Widest a card gets before a second / third column is added.
  static const double cardMaxWidth = 520;

  /// Columns for card grids at this width.
  static int columns(double width) => width >= 1300 ? 3 : (width >= 760 ? 2 : 1);

  static const EdgeInsets page = EdgeInsets.fromLTRB(gutter, gutter, gutter, 32);
}
