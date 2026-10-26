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

/// Touch counterpart of [blockHoverActionsEnabled]. There is no hover on
/// touch, so [BlockComponentActionWrapper] shows this handle persistently
/// instead of revealing it on `MouseRegion` enter/exit, and the drag it
/// offers is long-press activated (see [BlockHoverActionHandle.build] and
/// `_todoTouchReorderEnabled` in `todo_list_block_component.dart`, which this
/// mirrors) so a plain tap still places the caret.
bool blockHoverActionsTouchEnabled() {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.android:
      return true;
    default:
      return false;
  }
}

/// At the top level, adds the guard paragraph beside every non-text block RIGHT
/// NOW as a second recorded edit. The SurroundNonTextBlocksRule would otherwise
/// add it a moment later WITHOUT recording it, which shifts the paths an edit's
/// undo was recorded with (undo put a block one paragraph too early). Two
/// applies in the same synchronous run land in ONE undo item (the history item
/// is sealed on a timer), and each is recorded against the real document, so
/// undo restores the exact original layout. Call right after any edit that can
/// leave two non-text blocks side by side or a non-text block at an end.
void addNonTextGuardsNow(EditorState editorState, Node parent) {
  if (parent != editorState.document.root) return;
  if (!editorState.documentRules.any((r) => r is SurroundNonTextBlocksRule)) {
    return;
  }
  final missing = SurroundNonTextBlocksRule.missingGuardIndices(
      [for (final c in parent.children) c.delta != null]);
  if (missing.isEmpty) return;
  final guards = editorState.transaction;
  for (final i in missing.reversed) {
    guards.insertNode([i], paragraphNode());
  }
  guards.afterSelection = null;
  editorState.apply(guards, withUpdateSelection: false);
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
  addNonTextGuardsNow(editorState, parent);
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
  State<BlockHoverActionHandle> createState() => _BlockHoverActionHandleState();
}

class _BlockHoverActionHandleState extends State<BlockHoverActionHandle> {
  late final EditorState editorState =
      Provider.of<EditorState>(context, listen: false);

  late final BlockReorderSession _session =
      BlockReorderSession(editorState, widget.node);

  bool get _collapsed =>
      widget.node.attributes[blockComponentCollapsed] == true;

  @override
  void dispose() {
    _session.dispose();
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
    final touch = blockHoverActionsTouchEnabled();
    if (!blockHoverActionsEnabled() && !touch) return const SizedBox.shrink();

    final iconColor = editorState.editorStyle.textStyleConfiguration.text.color
            ?.withValues(alpha: 0.45) ??
        const Color(0x73808080);

    if (touch) {
      // PATCH 14: one shared touch grip (PATCH 11 gate, long-press activated
      // so a tap still places the caret), rendered as an INVISIBLE overlay
      // that BlockComponentActionWrapper lays over the row's own bullet /
      // checkbox (no gutter). Touch has no collapse chevron.
      return TouchReorderHandle(
        data: widget.node,
        color: iconColor,
        feedback: ReorderDragFeedback(
          node: widget.node,
          editorState: editorState,
        ),
        onDragStarted: () {
          _session.start();
          widget.state.alwaysShowActions = true;
        },
        onDragUpdate: (d) => _session.update(d.globalPosition),
        onDragEnd: ({required bool dropped}) => _finishDrag(dropped: dropped),
        invisible: true,
      );
    }

    final collapseIcon = Icon(
      _collapsed ? Icons.chevron_right : Icons.expand_more,
      size: 14,
      color: iconColor,
    );
    final dragIcon = Icon(Icons.drag_indicator, size: 16, color: iconColor);

    final collapseToggle = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleCollapsed,
        child: collapseIcon,
      ),
    );

    final dragHandle = MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<Node>(
        data: widget.node,
        dragAnchorStrategy: rowAnchoredDragAnchor(widget.node),
        axis: Axis.vertical,
        onDragStarted: () {
          _session.start();
          widget.state.alwaysShowActions = true;
        },
        onDragUpdate: (d) => _session.update(d.globalPosition),
        onDragEnd: (_) => _finishDrag(dropped: true),
        onDraggableCanceled: (_, __) => _finishDrag(dropped: false),
        feedback: ReorderDragFeedback(
          node: widget.node,
          editorState: editorState,
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: dragIcon),
        child: dragIcon,
      ),
    );

    return SizedBox(
      width: 22,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.node.children.isNotEmpty) collapseToggle,
          dragHandle,
        ],
      ),
    );
  }

  void _finishDrag({required bool dropped}) {
    widget.state.alwaysShowActions = false;
    _session.finish(dropped: dropped);
  }
}
