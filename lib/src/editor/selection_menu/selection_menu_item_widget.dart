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
    final Color background = isSelected
        ? style.selectionMenuItemSelectedColor
        : (isHovered ? style.selectionMenuItemHoverColor : Colors.transparent);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.0),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _onHover = true),
        onExit: (_) => setState(() => _onHover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.item.handler(
            widget.editorState,
            widget.menuService,
            context,
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 34.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20.0,
                  child: Center(
                    child: widget.item.icon(
                      widget.editorState,
                      isSelected,
                      style,
                    ),
                  ),
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: widget.item.nameBuilder
                          ?.call(widget.item.name, style, isSelected) ??
                      Text(
                        widget.item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          decoration: TextDecoration.none,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? style.selectionMenuItemSelectedTextColor
                              : style.selectionMenuItemTextColor,
                          fontSize: 13.0,
                        ),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
