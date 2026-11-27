import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/widgets.dart';

/// The drag-to-reorder mechanics shared by every way of picking a block up:
/// the per-row grip ([BlockHoverActionHandle]) and the left-margin hold
/// ([GutterReorderDetector]).
///
/// It moves [node] (with its subtree) to the slot under the pointer, at any
/// depth ([resolveReorderDrop]): between rows, below the last nested row, or at
/// the end of the note, the pointer's x choosing among the levels that fit. It
/// draws the drop indicator, auto-scrolls near the edges and ticks when the
/// slot changes. Every method is idempotent so a caller
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
      interceptor: _anchorForPointer,
    );
    editorState.scrollService?.startAutoScroll(global);
    final slot = resolveReorderDrop(editorState, node, global)?.target;
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

    final drop = resolveReorderDrop(editorState, node, global);
    if (drop == null) return;
    if (drop.target.parent.equals(node.path.parent)) {
      if (onDrop != null) {
        onDrop!(drop.target.last);
      } else {
        moveNodeAmongSiblings(editorState, node, drop.target.last);
      }
    } else {
      moveBlockTo(editorState, node, drop.target);
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

  /// The row the drop indicator is drawn against: the resolved slot's anchor,
  /// whatever node the selection service hit under the pointer.
  Node _anchorForPointer(BuildContext context, Node candidate) {
    final global = _lastGlobal;
    if (global == null) return candidate;
    return resolveReorderDrop(editorState, node, global)?.anchor ?? candidate;
  }
}

/// Where a dragged block lands: [target] is the slot (a path in the document
/// before the move) and [anchor] the row the indicator is drawn against.
class ReorderDrop {
  const ReorderDrop(this.target, this.anchor);
  final Path target;
  final Node anchor;
}

/// Rows a block can be dropped next to, in reading order: every block that
/// shows, except what sits inside a table or a columns block.
List<Node> _dropRows(EditorState editorState) {
  final rows = <Node>[];
  void walk(Node n) {
    rows.add(n);
    if (n.type == TableBlockKeys.type || n.type == ColumnsBlockKeys.type) {
      return;
    }
    n.children.forEach(walk);
  }

  editorState.document.root.children.forEach(walk);
  return rows;
}

RenderBox? _box(Node n) {
  final box = n.key.currentContext?.findRenderObject();
  return box is RenderBox && box.attached && box.hasSize ? box : null;
}

/// Resolves the pointer to a drop slot for [dragged], or null when there is
/// none (inside its own subtree, a block that cannot nest, no room to nest).
///
/// * Over a row's top half the slot is before it; over the bottom half, after
///   it (as its first child when it has children).
/// * Below the last row it is the end of the note.
/// * After a row that closes its group, the pointer's x picks the level: the
///   deepest one whose left edge is at or left of the pointer, up to the top.
ReorderDrop? resolveReorderDrop(
  EditorState editorState,
  Node dragged,
  Offset global,
) {
  final rows = _dropRows(editorState);
  if (rows.isEmpty) return null;
  Node? hit;
  RenderBox? hitBox;
  for (final r in rows) {
    final box = _box(r);
    if (box == null) continue;
    final top = box.localToGlobal(Offset.zero).dy;
    if (global.dy >= top && global.dy <= top + box.size.height) {
      hit = r;
      hitBox = box;
    }
  }
  final Node anchor;
  final bool after;
  if (hit != null && hitBox != null) {
    anchor = hit;
    final top = hitBox.localToGlobal(Offset.zero).dy;
    final childBox =
        _childrenShown(hit) ? _box(hit.children.first) : null;
    final ownBottom =
        childBox?.localToGlobal(Offset.zero).dy ?? top + hitBox.size.height;
    after = global.dy > (top + ownBottom) / 2;
  } else {
    final first = rows.first;
    final lastBox = _box(rows.last);
    final firstBox = _box(first);
    if (lastBox != null &&
        global.dy > lastBox.localToGlobal(Offset(0, lastBox.size.height)).dy) {
      anchor = rows.last;
      after = true;
    } else if (firstBox != null &&
        global.dy < firstBox.localToGlobal(Offset.zero).dy) {
      anchor = first;
      after = false;
    } else {
      return null;
    }
  }

  final candidates = <Path>[];
  if (!after) {
    candidates.add(anchor.path);
  } else if (_childrenShown(anchor)) {
    candidates.add([...anchor.path, 0]);
  } else {
    // After a leaf: its own level, then each ancestor it is the last child of.
    Node x = anchor;
    while (true) {
      candidates.add(x.path.next);
      final p = x.parent;
      if (p == null ||
          p.parent == null ||
          x.path.last != p.children.length - 1) {
        break;
      }
      x = p;
    }
  }

  Path target = candidates.first;
  if (after && !_childrenShown(anchor)) {
    // Deepest level whose left edge is at or left of the pointer.
    Node x = anchor;
    target = candidates.last;
    for (var i = 0; i < candidates.length; i++) {
      final left = _box(x)?.localToGlobal(Offset.zero).dx ?? 0;
      if (left <= global.dx) {
        target = candidates[i];
        break;
      }
      x = x.parent ?? x;
    }
  }

  // The pointer's level first, then the other levels, nearest first: a level
  // that cannot take the block (no room, not a container) must not leave a dead
  // zone under the finger.
  final ordered = [target, ...candidates.where((c) => !c.equals(target))];
  for (final t in ordered) {
    if (_dropAllowed(editorState, dragged, t)) return ReorderDrop(t, anchor);
  }
  return null;
}

/// Whether [dragged] may land at slot [target] (a path before the move).
bool _dropAllowed(EditorState editorState, Node dragged, Path target) {
  if (_isInside(dragged.path, target)) return false;
  final parentPath = target.parent;
  if (parentPath.equals(dragged.path.parent)) return true;
  if (!movableBlockTypes.contains(dragged.type)) return false;
  if (target.length > 1) {
    final parent = editorState.getNodeAtPath(parentPath);
    if (parent == null ||
        !indentableBlockTypes.contains(parent.type) ||
        blockHidesChildren(parent)) {
      return false;
    }
    if (!indentWouldFit(editorState, parent, dragged)) return false;
  }
  return true;
}

/// Whether [n] draws its children nested under itself: only list-like blocks
/// do (a table or columns block owns cells, a folded block hides its rows).
bool _childrenShown(Node n) =>
    n.children.isNotEmpty &&
    indentableBlockTypes.contains(n.type) &&
    !blockHidesChildren(n);

bool _isInside(Path ancestor, Path p) {
  if (p.length < ancestor.length) return false;
  for (var i = 0; i < ancestor.length; i++) {
    if (p[i] != ancestor[i]) return false;
  }
  return true;
}
