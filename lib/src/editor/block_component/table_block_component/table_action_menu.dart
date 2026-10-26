import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/toolbar/desktop/items/utils/overlay_util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

TableMenuActions? _readTableMenuActions(BuildContext context) {
  try {
    return context.read<TableMenuActions>();
  } on ProviderNotFoundException {
    return null;
  }
}

void showActionMenu(
  BuildContext context,
  Node node,
  EditorState editorState,
  int position,
  TableDirection dir,
) {
  // The host's own menu wins when it provides one (the host app does: a centered
  // popup with whole-table actions). The sheet and floating menu below are the
  // standalone fallback.
  final host = _readTableMenuActions(context);
  if (host != null) {
    host.showTableMenu(
      context,
      TableMenuRequest(
        table: node,
        editorState: editorState,
        position: position,
        dir: dir,
      ),
    );
    return;
  }
  if (blockHoverActionsTouchEnabled()) {
    _showTouchActionSheet(context, node, editorState, position, dir);
    return;
  }
  final Offset pos =
      (context.findRenderObject() as RenderBox).localToGlobal(Offset.zero);
  final rect = Rect.fromLTWH(
    pos.dx,
    pos.dy,
    context.size?.width ?? 0,
    context.size?.height ?? 0,
  );
  OverlayEntry? overlay;

  var (top, bottom, left) = positionFromRect(rect, editorState);
  top = top != null ? top - 35 : top;

  void dismissOverlay() {
    overlay?.remove();
    overlay = null;
  }

  overlay = FullScreenOverlayEntry(
    top: top,
    bottom: bottom,
    left: left,
    builder: (context) {
      return basicOverlay(
        context,
        width: 200,
        height: 230,
        children: [
          _menuItem(
              context,
              dir == TableDirection.col
                  ? AppFlowyEditorL10n.current.colAddBefore
                  : AppFlowyEditorL10n.current.rowAddBefore,
              dir == TableDirection.col
                  ? Icons.first_page
                  : Icons.vertical_align_top, () {
            TableActions.add(node, position, editorState, dir);
            dismissOverlay();
          }),
          _menuItem(
              context,
              dir == TableDirection.col
                  ? AppFlowyEditorL10n.current.colAddAfter
                  : AppFlowyEditorL10n.current.rowAddAfter,
              dir == TableDirection.col
                  ? Icons.last_page
                  : Icons.vertical_align_bottom, () {
            TableActions.add(node, position + 1, editorState, dir);
            dismissOverlay();
          }),
          _menuItem(
              context,
              dir == TableDirection.col
                  ? AppFlowyEditorL10n.current.colRemove
                  : AppFlowyEditorL10n.current.rowRemove,
              Icons.delete, () {
            TableActions.delete(node, position, editorState, dir);
            dismissOverlay();
          }),
          _menuItem(
              context,
              dir == TableDirection.col
                  ? AppFlowyEditorL10n.current.colDuplicate
                  : AppFlowyEditorL10n.current.rowDuplicate,
              Icons.content_copy, () {
            TableActions.duplicate(node, position, editorState, dir);
            dismissOverlay();
          }),
          _menuItem(
            context,
            AppFlowyEditorL10n.current.backgroundColor,
            Icons.format_color_fill,
            () {
              final cell = dir == TableDirection.col
                  ? getCellNode(node, position, 0)
                  : getCellNode(node, 0, position);
              final key = dir == TableDirection.col
                  ? TableCellBlockKeys.colBackgroundColor
                  : TableCellBlockKeys.rowBackgroundColor;

              _showColorMenu(
                context,
                (color) {
                  TableActions.setBgColor(
                    node,
                    position,
                    editorState,
                    color,
                    dir,
                  );
                },
                top: top,
                bottom: bottom,
                left: left,
                selectedColorHex: cell?.attributes[key],
              );
              dismissOverlay();
            },
          ),
          _menuItem(
              context,
              dir == TableDirection.col
                  ? AppFlowyEditorL10n.current.colClear
                  : AppFlowyEditorL10n.current.rowClear,
              Icons.clear, () {
            TableActions.clear(node, position, editorState, dir);
            dismissOverlay();
          }),
        ],
      );
    },
  ).build();
  Overlay.of(context, rootOverlay: true).insert(overlay!);
}

Widget _menuItem(
  BuildContext context,
  String text,
  IconData icon,
  Function() action,
) {
  return SizedBox(
    height: 36,
    child: TextButton.icon(
      onPressed: () {
        action();
      },
      icon: Icon(icon, color: Theme.of(context).iconTheme.color),
      style: buildOverlayButtonStyle(context),
      label: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              text,
              softWrap: false,
              maxLines: 1,
              overflow: TextOverflow.fade,
              style: TextStyle(
                color: Theme.of(context).textTheme.labelLarge?.color,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void _showColorMenu(
  BuildContext context,
  Function(String?) action, {
  double? top,
  double? bottom,
  double? left,
  String? selectedColorHex,
}) {
  OverlayEntry? overlay;

  void dismissOverlay() {
    overlay?.remove();
    overlay = null;
  }

  overlay = FullScreenOverlayEntry(
    top: top,
    bottom: bottom,
    left: left,
    builder: (context) {
      return ColorPicker(
        title: AppFlowyEditorL10n.current.highlightColor,
        selectedColorHex: selectedColorHex,
        colorOptions: generateHighlightColorOptions(),
        onSubmittedColorHex: (color, _) {
          action(color);
          dismissOverlay();
        },
        resetText: AppFlowyEditorL10n.current.clearHighlightColor,
        resetIconName: 'clear_highlight_color',
      );
    },
  ).build();
  Overlay.of(context, rootOverlay: true).insert(overlay!);
}

/// Touch: a bottom sheet instead of the desktop floating popup. The popup was
/// positioned from the handle's rect (and dismissed on any outside touch), so
/// on a phone with the keyboard up it opened off-screen or closed at once; a
/// modal sheet is always on-screen, has full-size tap targets, and is a real
/// route.
void _showTouchActionSheet(
  BuildContext context,
  Node node,
  EditorState editorState,
  int position,
  TableDirection dir,
) {
  final col = dir == TableDirection.col;
  // The sheet steals focus (keyboard + caret drop); put the caret back after
  // the action when its cell still exists.
  final caret = editorState.selection;
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) {
      Widget item(String text, IconData icon, VoidCallback action) => ListTile(
            leading: Icon(icon),
            title: Text(text),
            minVerticalPadding: 12,
            onTap: () {
              Navigator.of(sheetContext).pop();
              action();
              if (caret != null &&
                  editorState.getNodeAtPath(caret.start.path) != null) {
                editorState.selection = caret;
              }
            },
          );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(
                col
                    ? AppFlowyEditorL10n.current.colAddBefore
                    : AppFlowyEditorL10n.current.rowAddBefore,
                col ? Icons.first_page : Icons.vertical_align_top,
                () => TableActions.add(node, position, editorState, dir),
              ),
              item(
                col
                    ? AppFlowyEditorL10n.current.colAddAfter
                    : AppFlowyEditorL10n.current.rowAddAfter,
                col ? Icons.last_page : Icons.vertical_align_bottom,
                () => TableActions.add(node, position + 1, editorState, dir),
              ),
              item(
                col
                    ? AppFlowyEditorL10n.current.colDuplicate
                    : AppFlowyEditorL10n.current.rowDuplicate,
                Icons.content_copy,
                () => TableActions.duplicate(node, position, editorState, dir),
              ),
              item(
                AppFlowyEditorL10n.current.backgroundColor,
                Icons.format_color_fill,
                () {
                  final cell = col
                      ? getCellNode(node, position, 0)
                      : getCellNode(node, 0, position);
                  final key = col
                      ? TableCellBlockKeys.colBackgroundColor
                      : TableCellBlockKeys.rowBackgroundColor;
                  showModalBottomSheet<void>(
                    context: context,
                    useRootNavigator: true,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (colorContext) => SafeArea(
                      child: SingleChildScrollView(
                        child: ColorPicker(
                          title: AppFlowyEditorL10n.current.highlightColor,
                          selectedColorHex: cell?.attributes[key],
                          colorOptions: generateHighlightColorOptions(),
                          onSubmittedColorHex: (color, _) {
                            Navigator.of(colorContext).pop();
                            TableActions.setBgColor(
                              node,
                              position,
                              editorState,
                              color,
                              dir,
                            );
                          },
                          resetText:
                              AppFlowyEditorL10n.current.clearHighlightColor,
                          resetIconName: 'clear_highlight_color',
                        ),
                      ),
                    ),
                  );
                },
              ),
              item(
                col
                    ? AppFlowyEditorL10n.current.colClear
                    : AppFlowyEditorL10n.current.rowClear,
                Icons.clear,
                () => TableActions.clear(node, position, editorState, dir),
              ),
              item(
                col
                    ? AppFlowyEditorL10n.current.colRemove
                    : AppFlowyEditorL10n.current.rowRemove,
                Icons.delete,
                () => TableActions.delete(node, position, editorState, dir),
              ),
            ],
          ),
        ),
      );
    },
  );
}
