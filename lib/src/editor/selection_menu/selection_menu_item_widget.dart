import 'package:prevon_quilltext_engine/src/editor/selection_menu/selection_menu_service.dart';
import 'package:prevon_quilltext_engine/src/editor/selection_menu/selection_menu_widget.dart';
import 'package:prevon_quilltext_engine/src/editor_state.dart';
import 'package:flutter/material.dart';

class SelectionMenuItemWidget extends StatefulWidget {
  const SelectionMenuItemWidget({
    super.key,
    required this.editorState,
    required this.menuService,
    required this.item,
    required this.isSelected,
    required this.selectionMenuStyle,
    this.width = 140.0,
  });

  final EditorState editorState;
  final SelectionMenuService menuService;
  final SelectionMenuItem item;
  final double width;
  final bool isSelected;
  final SelectionMenuStyle selectionMenuStyle;

  @override
  State<SelectionMenuItemWidget> createState() =>
      _SelectionMenuItemWidgetState();
}

class _SelectionMenuItemWidgetState extends State<SelectionMenuItemWidget> {
  var _onHover = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.selectionMenuStyle;
    // PREVON PATCH 11 (finding E): a hovered-but-unselected row used to reuse
    // the full selected palette, so hover and selection were visually
    // identical. Now only `isSelected` gets the selected colors; hover alone
    // gets the hover background plus the unselected label color (the icon
    // widget resolves `selectionMenuItemIconColor`, which equals the
    // unselected-label color in both the light and dark styles).
    final isSelected = widget.isSelected;
    final isHovered = _onHover && !widget.isSelected;
    return Container(
      padding: const EdgeInsets.fromLTRB(8.0, 5.0, 8.0, 5.0),
      child: SizedBox(
        width: widget.width,
        child: TextButton.icon(
          icon: widget.item.icon(
            widget.editorState,
            isSelected,
            widget.selectionMenuStyle,
          ),
          style: ButtonStyle(
            alignment: Alignment.centerLeft,
            overlayColor: WidgetStateProperty.all(
              style.selectionMenuItemSelectedColor,
            ),
            backgroundColor: isSelected
                ? WidgetStateProperty.all(
                    style.selectionMenuItemSelectedColor,
                  )
                : WidgetStateProperty.all(
                    isHovered
                        ? style.selectionMenuItemHoverColor
                        : Colors.transparent,
                  ),
          ),
          label: widget.item.nameBuilder
                  ?.call(widget.item.name, style, isSelected) ??
              Text(
                widget.item.name,
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: isSelected
                      ? style.selectionMenuItemSelectedTextColor
                      : (isHovered
                          ? style.selectionMenuUnselectedLabelColor
                          : style.selectionMenuItemTextColor),
                  fontSize: 12.0,
                ),
              ),
          onPressed: () {
            widget.item.handler(
              widget.editorState,
              widget.menuService,
              context,
            );
          },
          onHover: (value) {
            setState(() {
              _onHover = value;
            });
          },
        ),
      ),
    );
  }
}
