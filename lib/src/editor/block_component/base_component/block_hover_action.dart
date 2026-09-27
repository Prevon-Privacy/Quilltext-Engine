import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A generic per-block hover handle usable as any block
/// builder's `actionBuilder`, offering a collapse toggle (when the block has
/// children) and a drag handle that reorders the block among its own
/// siblings. Generalizes the todo_list-only drag-to-reorder mechanism
/// (PREVON PATCH 9, see `todo_list_block_component.dart`) to every block
/// type via the block-component-action-wrapper mechanism that already
/// existed but no builder ever populated.
///
/// Desktop pointer affordance only, matching PATCH 9's own gate.
bool blockHoverActionsEnabled() {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}

/// Moves [node] to sibling index [targetIndex] among its own parent's
/// children — never across parents or nesting levels. No-ops when the move
/// changes nothing or [node] has no siblings. Returns true when a
/// transaction was applied.
bool moveNodeAmongSiblings(
  EditorState editorState,
  Node node,
  int targetIndex,
) {
  final parent = node.parent;
  if (parent == null) return false;
  final siblingCount = parent.children.length;
  if (siblingCount <= 1) return false;
  final current = node.path.last;
  final target = targetIndex.clamp(0, siblingCount);
  // Dropping onto your own slot (or the gap immediately after it) is a no-op.
  if (target == current || target == current + 1) return false;
  final transaction = editorState.transaction
    ..moveNode([...node.path.parent, target], node);
  transaction.afterSelection = null;
  editorState.apply(transaction, withUpdateSelection: false);
  return true;
}

class BlockHoverActionHandle extends StatefulWidget {
  const BlockHoverActionHandle({
    super.key,
    required this.node,
    required this.state,
  });

  final Node node;
  final BlockComponentActionState state;

  @override
  State<BlockHoverActionHandle> createState() =>
      _BlockHoverActionHandleState();
}

class _BlockHoverActionHandleState extends State<BlockHoverActionHandle> {
  bool _dragActive = false;
  Offset? _lastDragGlobal;

  late final EditorState editorState =
      Provider.of<EditorState>(context, listen: false);

  bool get _collapsed =>
      widget.node.attributes[blockComponentCollapsed] == true;

  @override
  void dispose() {
    if (_dragActive) {
      editorState.selectionService.removeDropTarget();
      editorState.scrollService?.stopAutoScroll();
    }
    super.dispose();
  }

  void _toggleCollapsed() {
    final transaction = editorState.transaction
      ..updateNode(widget.node, {blockComponentCollapsed: !_collapsed});
    transaction.afterSelection = null;
    editorState.apply(transaction, withUpdateSelection: false);
  }

  @override
  Widget build(BuildContext context) {
    if (!blockHoverActionsEnabled()) return const SizedBox.shrink();

    final iconColor =
        editorState.editorStyle.textStyleConfiguration.text.color
                ?.withValues(alpha: 0.45) ??
            const Color(0x73808080);

    return SizedBox(
      width: 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.node.children.isNotEmpty)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleCollapsed,
                child: Icon(
                  _collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 16,
                  color: iconColor,
                ),
              ),
            ),
          MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Draggable<Node>(
              data: widget.node,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              onDragStarted: () {
                _dragActive = true;
                widget.state.alwaysShowActions = true;
              },
              onDragUpdate: _onDragUpdate,
              onDragEnd: (_) => _finishDrag(dropped: true),
              onDraggableCanceled: (_, __) => _finishDrag(dropped: false),
              feedback: _buildDragFeedback(context),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: Icon(Icons.drag_indicator, size: 18, color: iconColor),
              ),
              child: Icon(Icons.drag_indicator, size: 18, color: iconColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragFeedback(BuildContext context) {
    final style = editorState.editorStyle.textStyleConfiguration.text;
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.9,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                blurRadius: 8,
                color: Colors.black.withValues(alpha: 0.15),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.drag_indicator,
                size: 16,
                color: style.color?.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  widget.node.delta?.toPlainText() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _lastDragGlobal = details.globalPosition;
    editorState.selectionService.renderDropTargetForOffset(
      details.globalPosition,
      interceptor: _clampDropToParent,
    );
    editorState.scrollService?.startAutoScroll(details.globalPosition);
  }

  void _finishDrag({required bool dropped}) {
    editorState.selectionService.removeDropTarget();
    editorState.scrollService?.stopAutoScroll();
    widget.state.alwaysShowActions = false;
    final wasActive = _dragActive;
    _dragActive = false;
    final global = _lastDragGlobal;
    _lastDragGlobal = null;
    if (!dropped || !wasActive || global == null) return;

    final data = editorState.selectionService.getDropTargetRenderData(
      global,
      interceptor: _clampDropToParent,
    );
    final dropPath = data?.dropPath;
    if (dropPath == null) return;
    // Never reorder across parents/nesting levels — only among siblings.
    if (!dropPath.parent.equals(widget.node.path.parent)) return;
    moveNodeAmongSiblings(editorState, widget.node, dropPath.last);
  }

  /// Keeps the drop indicator within the dragged block's own parent: any
  /// hovered node outside that sibling set resolves to the nearest boundary
  /// sibling.
  Node _clampDropToParent(BuildContext context, Node candidate) {
    final parent = widget.node.parent;
    if (parent == null) return candidate;

    Node? c = candidate;
    while (c != null && c.parent != parent) {
      c = c.parent;
    }
    return c ?? parent.children.first;
  }
}
