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
