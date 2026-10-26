import 'dart:math' as math;

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/table_block_component/table_action_menu.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/table_block_component/table_drag.dart';
import 'package:flutter/material.dart';

class TableActionHandler extends StatefulWidget {
  const TableActionHandler({
    super.key,
    this.visible = false,
    this.height,
    required this.node,
    required this.editorState,
    required this.position,
    required this.alignment,
    required this.transform,
    required this.dir,
    this.menuBuilder,
  });

  final bool visible;
  final Node node;
  final EditorState editorState;
  final int position;
  final Alignment alignment;
  final Matrix4 transform;
  final double? height;
  final TableDirection dir;

  final TableBlockComponentMenuBuilder? menuBuilder;

  @override
  State<TableActionHandler> createState() => _TableActionHandlerState();
}

class _TableActionHandlerState extends State<TableActionHandler> {
  bool _visible = false;
  bool _menuShown = false;

  @override
  Widget build(BuildContext context) {
    // There is no hover on touch, so the hover-driven flags never turn true
    // there. Showing every row's and column's handle all the time (the first
    // fix) buried the table in grips and made each row taller than its cells.
    // On touch the handle now appears ONLY for the row and column the caret is
    // in — one small tab per axis — and is compact enough to sit inside a
    // cell's height. It floats outside the layout (Stack-positioned via
    // `transform`/`alignment`), so it never affects table sizing.
    final touch = blockHoverActionsTouchEnabled();
    Widget handle(bool caretHere) => Container(
          alignment: widget.alignment,
          transform: widget.transform,
          height: widget.height,
          child: Visibility(
            visible: (widget.visible ||
                    _visible ||
                    _menuShown ||
                    (touch && caretHere)) &&
                widget.editorState.editable,
            child: MouseRegion(
              onEnter: (_) => setState(() => _visible = true),
              onExit: (_) => setState(() => _visible = false),
              child: TableHandleDragger(
                node: widget.node,
                editorState: widget.editorState,
                position: widget.position,
                dir: widget.dir,
                child: widget.menuBuilder != null
                    ? widget.menuBuilder!(
                        widget.node,
                        widget.editorState,
                        widget.position,
                        widget.dir,
                        () => _menuShown = true,
                        () => setState(() => _menuShown = false),
                      )
                    : defaultMenuBuilder(
                        context,
                        widget.node,
                        widget.editorState,
                        widget.position,
                        widget.dir,
                      ),
              ),
            ),
          ),
        );
    if (!touch) return handle(false);
    return ListenableBuilder(
      listenable: widget.editorState.selectionNotifier,
      builder: (_, __) {
        final caretHere = tableCaretInLine(
          widget.editorState,
          widget.node,
          widget.dir,
          widget.position,
        );
        return handle(caretHere);
      },
    );
  }
}

Widget defaultMenuBuilder(
  BuildContext context,
  Node node,
  EditorState editorState,
  int position,
  TableDirection dir,
) {
  final icon = dir == TableDirection.col
      ? Transform.rotate(
          angle: math.pi / 2,
          child: TableDefaults.handlerIcon,
        )
      : TableDefaults.handlerIcon;

  if (blockHoverActionsTouchEnabled()) {
    // The default Card + dark icon theme rendered a near-black chip on the
    // dark note background (and the editor style's own text color is unset
    // — the host colors text per block — so it can't be used as the ink).
    // A mid grey reads on both light and dark pages without shouting.
    const ink = TableDefaults.borderColor;
    return Material(
      color: ink.withValues(alpha: 0.28),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => showActionMenu(context, node, editorState, position, dir),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: IconTheme(
              data: IconThemeData(
                size: 18,
                color: ink,
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }

  return Card(
    elevation: 3.0,
    margin: blockHoverActionsTouchEnabled() ? EdgeInsets.zero : null,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showActionMenu(
          context,
          node,
          editorState,
          position,
          dir,
        ),
        // Compact on touch: 28x28 fits inside a 40px row (the old 44x44 card
        // was taller than the cells) yet is still a usable tap target.
        child: blockHoverActionsTouchEnabled()
            ? SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: IconTheme(
                    data: const IconThemeData(size: 18),
                    child: icon,
                  ),
                ),
              )
            : icon,
      ),
    ),
  );
}

/// Whether the caret sits in row/column [position] of [table].
bool tableCaretInLine(
  EditorState editorState,
  Node table,
  TableDirection dir,
  int position,
) {
  final sel = editorState.selection;
  if (sel == null) return false;
  Node? n = editorState.getNodeAtPath(sel.start.path);
  while (n != null && n.type != TableCellBlockKeys.type) {
    n = n.parent;
  }
  if (n == null || !identical(n.parent, table)) return false;
  final key = dir == TableDirection.col
      ? TableCellBlockKeys.colPosition
      : TableCellBlockKeys.rowPosition;
  return n.attributes[key] == position;
}

/// Touch-only row/column handle that lives IN the table's layout (a gutter
/// left of the rows, a strip above the columns) instead of floating over the
/// cell border. A floating handle sat on the cell text and — because Flutter
/// only hit-tests a child inside its parent's bounds — was mostly outside the
/// bounds that receive taps, so tapping it did nothing. It renders only for
/// the row/column the caret is in; everywhere else it is empty space.
class TableTouchHandle extends StatelessWidget {
  const TableTouchHandle({
    super.key,
    required this.node,
    required this.editorState,
    required this.position,
    required this.dir,
    this.menuBuilder,
  });

  final Node node;
  final EditorState editorState;
  final int position;
  final TableDirection dir;
  final TableBlockComponentMenuBuilder? menuBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: editorState.selectionNotifier,
      builder: (context, _) {
        if (!editorState.editable ||
            !tableCaretInLine(editorState, node, dir, position)) {
          return const SizedBox.shrink();
        }
        return TableHandleDragger(
          node: node,
          editorState: editorState,
          position: position,
          dir: dir,
          child: menuBuilder != null
              ? menuBuilder!(node, editorState, position, dir, () {}, () {})
              : defaultMenuBuilder(context, node, editorState, position, dir),
        );
      },
    );
  }
}

/// Edge of the touch handle strip/gutter (handle is 28 + 2 breathing).
const double kTableTouchGutter = 30;
