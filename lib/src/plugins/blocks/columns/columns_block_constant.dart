class ColumnsBlockConstants {
  const ColumnsBlockConstants._();

  /// Space between two side-by-side columns (the divider line sits in its
  /// middle).
  static const double gap = 16;

  /// Width of the touch/mouse target around a divider. Wider than the line it
  /// draws so a finger can find it.
  static const double resizerHitWidth = 24;

  /// Narrowest a column can be dragged to.
  static const double minColumnWidth = 72;

  /// When the average column would be narrower than this, the columns stack
  /// one above the other instead of sitting side by side (a phone, or a
  /// narrow window, or columns nested in an indent).
  static const double stackBelowColumnWidth = 120;

  /// Most columns one block can hold.
  static const int maxColumns = 5;

  /// Height of the strip above every column that holds its grip while editing.
  static const double gripStrip = 20;

  /// Space between stacked columns.
  static const double stackedGap = 8;
}
