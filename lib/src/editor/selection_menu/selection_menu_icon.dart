import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';

class SelectionMenuIconWidget extends StatelessWidget {
  SelectionMenuIconWidget({
    super.key,
    this.name,
    this.icon,
    required this.isSelected,
    required this.style,
  }) {
    assert((name == null && icon != null) || ((name != null && icon == null)));
  }

  final String? name;
  final IconData? icon;
  final bool isSelected;
  final SelectionMenuStyle style;

  @override
  Widget build(BuildContext context) {
    if (icon != null) {
      return Icon(
        icon,
        size: 14.0,
        color: isSelected
            ? style.selectionMenuItemSelectedIconColor
            : style.selectionMenuItemIconColor,
      );
    } else if (name != null) {
      return EditorSvg(
        name: 'selection_menu/$name',
        width: 14.0,
        height: 14.0,
        color: isSelected
            ? style.selectionMenuItemSelectedIconColor
            : style.selectionMenuItemIconColor,
      );
    }
    throw UnimplementedError();
  }
}

/// The slash-menu icon of a heading: an "Aa" sample that shrinks with the
/// [level] (1 largest), matching the app's Block Type tiles. Replaces the old
/// "H1/H2/H3" artwork, whose names no longer match the labels
/// (Heading, Subheading, Small heading).
Widget headingMenuGlyph(
  int level, {
  required bool isSelected,
  required SelectionMenuStyle style,
}) {
  const sizes = <double>[16, 14, 12];
  return SizedBox(
    width: 20,
    height: 16,
    child: Center(
      child: Text(
        'Aa',
        maxLines: 1,
        style: TextStyle(
          fontSize: sizes[(level - 1).clamp(0, 2)],
          fontWeight: FontWeight.w800,
          height: 1,
          color: isSelected
              ? style.selectionMenuItemSelectedIconColor
              : style.selectionMenuItemIconColor,
        ),
      ),
    ),
  );
}
