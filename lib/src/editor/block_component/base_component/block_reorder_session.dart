import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/widgets.dart';

/// The drag-to-reorder mechanics shared by every way of picking a block up:
/// the per-row grip ([BlockHoverActionHandle]) and the left-margin hold
/// ([GutterReorderDetector]).
///
/// It moves [node] among its OWN siblings only — never across parents or
/// nesting levels — drawing the drop indicator, auto-scrolling near the edges
/// and ticking when the slot changes. Every method is idempotent so a caller
/// may end the gesture from more than one place.
class BlockReorderSession {
  BlockReorderSession(this.editorState, this.node, {this.onDrop});

  final EditorState editorState;
  final Node node;

  /// Replaces the default single-node move on drop. Receives the target
  /// sibling index (in the pre-move document). Used by the checklist's
  /// completed-section divider, which moves a whole group of rows.
  final void Function(int targetIndex)? onDrop;

  bool _active = false;
  Offset? _lastGlobal;
  Path? _lastTickPath;

  bool get active => _active;

  void start() {
    _active = true;
    reorderDraggingNode.value = node;
  }

  void update(Offset global) {
    _lastGlobal = global;
    editorState.selectionService.renderDropTargetForOffset(
      global,
      interceptor: _clampDropToParent,
    );
    editorState.scrollService?.startAutoScroll(global);
    final slot = editorState.selectionService
        .getDropTargetRenderData(global, interceptor: _clampDropToParent)
        ?.dropPath;
    if (slot != null &&
        (_lastTickPath == null || !slot.equals(_lastTickPath!))) {
      if (_lastTickPath != null) reorderDropTick();
      _lastTickPath = slot;
    }
  }

  /// Ends the gesture. When [dropped] and the drag really started, moves the
  /// block to the slot under the last pointer position.
  void finish({required bool dropped}) {
    reorderDraggingNode.value = null;
    _lastTickPath = null;
    editorState.selectionService.removeDropTarget();
    editorState.scrollService?.stopAutoScroll();
    final wasActive = _active;
    _active = false;
    final global = _lastGlobal;
    _lastGlobal = null;
    if (!dropped || !wasActive || global == null) return;

    final data = editorState.selectionService.getDropTargetRenderData(
      global,
      interceptor: _clampDropToParent,
    );
    final dropPath = data?.dropPath;
    if (dropPath == null) return;
    // Never reorder across parents/nesting levels — only among siblings.
    if (!dropPath.parent.equals(node.path.parent)) return;
    if (onDrop != null) {
      onDrop!(dropPath.last);
    } else {
      moveNodeAmongSiblings(editorState, node, dropPath.last);
    }
  }

  /// Cleanup for an owner that is being disposed mid-drag.
  void dispose() {
    if (_active) {
      editorState.selectionService.removeDropTarget();
      editorState.scrollService?.stopAutoScroll();
      reorderDraggingNode.value = null;
      _active = false;
    }
  }

  /// Keeps the drop indicator within the dragged block's own parent: any
  /// hovered node outside that sibling set resolves to the nearest boundary
  /// sibling.
  Node _clampDropToParent(BuildContext context, Node candidate) {
    final parent = node.parent;
    if (parent == null) return candidate;

    Node? c = candidate;
    while (c != null && c.parent != parent) {
      c = c.parent;
    }
    return c ?? parent.children.first;
  }
}
