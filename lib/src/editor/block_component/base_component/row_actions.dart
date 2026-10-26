import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// PREVON PATCH 18 — row actions: move up / down, duplicate and delete the
/// row at the caret (or every selected row), the tap counterparts of the
/// margin-hold drag, shared by the editor's "+" popover.
///
/// The unit is a **row group**: the selected blocks that share one parent and
/// sit side by side (a collapsed caret is a group of one). Nested rows travel
/// with their parent, exactly like a drag. Nothing here crosses parents or
/// nesting levels; changing level is what indent / outdent are for.
///
/// Every action is one undo step (the history item is sealed right after, so
/// typing that follows never merges into it) and never pops the keyboard: the
/// selection is only written when it changed. Top-level non-text blocks keep
/// their guard paragraphs through [addNonTextGuardsNow], so a move, copy or
/// delete cannot leave two dividers touching or a note ending on a table.

/// The selected rows an action would act on, or null when none can be (no
/// selection, inside a table cell, a block with no grip, a selection that
/// spans different parents, or one that skips a row).
class RowGroup {
  RowGroup._(this.parent, this.nodes);

  final Node parent;

  /// The rows in document order, side by side under [parent].
  final List<Node> nodes;

  int get first => nodes.first.path.last;
  int get last => nodes.last.path.last;

  bool get canMoveUp => first > 0;
  bool get canMoveDown => last < parent.children.length - 1;
}

/// The [RowGroup] at the current selection, or null (see [RowGroup]).
RowGroup? selectedRowGroup(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null) return null;
  // `getSelectedNodes` is the clipboard's reader: it slices the first and last
  // rows' text to the selection IN PLACE. This must only look, so walk the
  // selected nodes and keep the top-most ones.
  final nodes = <Node>[];
  for (final n in editorState.getNodesInSelection(selection)) {
    if (nodes.any((kept) => kept.isParentOf(n))) continue;
    nodes.add(n);
  }
  if (nodes.isEmpty) return null;
  // `getNodesInSelection` hands them back in reverse for some selection
  // directions: put them in document order.
  nodes.sort((a, b) => _comparePaths(a.path, b.path));
  final parent = nodes.first.parent;
  if (parent == null) return null;
  for (final n in nodes) {
    if (!identical(n.parent, parent)) return null;
    if (!gutterReorderBlockTypes.contains(n.type)) return null;
  }
  // A table cell's content is the table's business, never a movable row.
  for (Node? a = parent; a != null; a = a.parent) {
    if (a.type == TableBlockKeys.type || a.type == TableCellBlockKeys.type) {
      return null;
    }
  }
  for (var i = 1; i < nodes.length; i++) {
    if (nodes[i].path.last != nodes[i - 1].path.last + 1) return null;
  }
  return RowGroup._(parent, nodes);
}

int _comparePaths(Path a, Path b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return a.length.compareTo(b.length);
}

/// Whether the rows at the selection can move one slot [up] or down.
bool canMoveRows(EditorState editorState, {required bool up}) {
  final g = selectedRowGroup(editorState);
  if (g == null) return false;
  return up ? g.canMoveUp : g.canMoveDown;
}

/// Moves the selected rows one slot up or down among their siblings, keeping
/// the selection on them. Returns false (nothing changed) at either end.
///
/// The neighbour hops over the group instead of the group hopping over the
/// neighbour: one node moves, however many rows were selected, and the rows
/// that stay put keep their identity (and their selection endpoints).
bool moveRows(EditorState editorState, {required bool up}) {
  final g = selectedRowGroup(editorState);
  if (g == null || !(up ? g.canMoveUp : g.canMoveDown)) return false;
  final selection = editorState.selection!;
  final anchors = _anchors(selection, g.nodes);
  final neighbor = g.parent.children[up ? g.first - 1 : g.last + 1];
  // `moveNodeAmongSiblings` takes a slot in the pre-move list: past the whole
  // group, or just before it.
  final slot = up ? g.last + 1 : g.first;
  if (!moveNodeAmongSiblings(editorState, neighbor, slot)) return false;
  _restoreSelection(editorState, selection, anchors, g.nodes);
  _sealHistory(editorState);
  return true;
}

/// Whether the rows at the selection can be duplicated: [canDuplicate], when
/// given, must accept every block in them (children included). The app uses it
/// to keep blocks that point at one stored object (a drawing) from being
/// copied into two rows that would edit the same thing.
bool canDuplicateRows(
  EditorState editorState, {
  bool Function(Node node)? canDuplicate,
}) {
  final g = selectedRowGroup(editorState);
  if (g == null) return false;
  if (canDuplicate == null) return true;
  bool ok(Node n) => canDuplicate(n) && n.children.every(ok);
  return g.nodes.every(ok);
}

/// Copies the selected rows (children included) to just below them and puts
/// the selection on the copies, at the same text offsets. Returns false when
/// nothing could be copied.
bool duplicateRows(
  EditorState editorState, {
  bool Function(Node node)? canDuplicate,
}) {
  if (!canDuplicateRows(editorState, canDuplicate: canDuplicate)) {
    return false;
  }
  final g = selectedRowGroup(editorState)!;
  final selection = editorState.selection!;
  final anchors = _anchors(selection, g.nodes);
  final copies = [for (final n in g.nodes) n.copyWith()];
  final at = [...g.parent.path, g.last + 1];
  final transaction = editorState.transaction
    ..insertNodes(at, copies, deepCopy: false);
  transaction.afterSelection = null;
  editorState.apply(transaction, withUpdateSelection: false);
  addNonTextGuardsNow(editorState, g.parent);
  // The guards (if any) may have shifted the copies: aim at where they are.
  _restoreSelection(editorState, selection, anchors, copies);
  _sealHistory(editorState);
  return true;
}

/// Deletes the selected rows (children included). The caret lands on the row
/// that slid into the gap, else the one above; a note left with nothing keeps
/// one empty paragraph so there is always somewhere to type. Returns the number
/// of rows deleted, 0 when nothing was.
int deleteRows(EditorState editorState) {
  final g = selectedRowGroup(editorState);
  if (g == null) return 0;
  final parent = g.parent;
  final count = g.nodes.length;
  final first = g.first;
  final remaining = parent.children.length - count;
  final transaction = editorState.transaction;
  if (remaining == 0) {
    transaction.insertNode([...parent.path, first], paragraphNode());
    transaction.deleteNodes(g.nodes);
    transaction.afterSelection = Selection.collapsed(
      Position(path: [...parent.path, first], offset: 0),
    );
  } else {
    transaction.deleteNodes(g.nodes);
    final hasNext = first + count < parent.children.length;
    if (hasNext) {
      transaction.afterSelection = Selection.collapsed(
        Position(path: [...parent.path, first], offset: 0),
      );
    } else {
      final prev = parent.children[first - 1];
      transaction.afterSelection = Selection.collapsed(
        Position(path: prev.path, offset: prev.delta?.length ?? 0),
      );
    }
  }
  editorState.apply(transaction);
  addNonTextGuardsNow(editorState, parent);
  _sealHistory(editorState);
  return count;
}

/// Lifts the children of every selected block that cannot draw children
/// (anything outside [indentableBlockTypes]: headings, quotes...) out to sit
/// right below it, at the block's own level, in their original order and with
/// their own subtrees. Run after turning a row into such a block: its nested
/// rows are kept in the document but such a block never shows them, so without
/// this they would be invisible, uneditable and still saved. Lossless, and one
/// undo step together with the conversion that just happened (the same
/// synchronous run lands in one history item). Returns how many rows moved.
int liftHiddenChildren(EditorState editorState, Selection selection) {
  final parents = <Node>[];
  for (final n in editorState.getNodesInSelection(selection)) {
    if (n.children.isEmpty || indentableBlockTypes.contains(n.type)) continue;
    // Tables, columns and the like own their children by design.
    if (n.delta == null) continue;
    parents.add(n);
  }
  if (parents.isEmpty) return 0;
  // Bottom-up so earlier paths stay valid while later ones are rewritten.
  parents.sort((a, b) => _comparePaths(b.path, a.path));
  final transaction = editorState.transaction;
  var moved = 0;
  for (final n in parents) {
    final kids = n.children.toList();
    transaction
      ..deleteNodes(kids)
      ..insertNodes(n.path.next, kids);
    moved += kids.length;
  }
  transaction.afterSelection = editorState.selection;
  editorState.apply(transaction, withUpdateSelection: false);
  return moved;
}

/// A mark of the newest history item (opaque), taken right after an action,
/// for an "Undo" button that must only undo THAT action: [undoIfLatest] does
/// nothing once anything newer (typing, another action) was recorded after it.
Object? latestHistoryItem(EditorState editorState) {
  final stack = editorState.undoManager.undoStack;
  return stack.isNonEmpty ? stack.last : null;
}

/// Undoes [item] when it is still the newest history item. Returns whether it
/// did.
bool undoIfLatest(EditorState editorState, Object? item) {
  if (item == null || !identical(latestHistoryItem(editorState), item)) {
    return false;
  }
  editorState.undoManager.undo();
  return true;
}

/// Seals the newest history item so what is typed next starts a fresh one.
void _sealHistory(EditorState editorState) {
  final stack = editorState.undoManager.undoStack;
  if (stack.isNonEmpty) stack.last.seal();
}

/// A selection endpoint expressed relative to one of the group's rows, so it
/// can be re-aimed after the rows moved or were copied.
typedef _Anchor = ({int index, Path rest, int offset});

_Anchor? _anchorOf(Position p, List<Node> nodes) {
  for (var i = 0; i < nodes.length; i++) {
    final np = nodes[i].path;
    if (p.path.length >= np.length && p.path.sublist(0, np.length).equals(np)) {
      return (index: i, rest: p.path.sublist(np.length), offset: p.offset);
    }
  }
  return null;
}

({_Anchor? start, _Anchor? end}) _anchors(
  Selection selection,
  List<Node> nodes,
) =>
    (
      start: _anchorOf(selection.start, nodes),
      end: _anchorOf(selection.end, nodes),
    );

/// Re-aims [before] at [nodes] (the rows' current paths) and writes it only
/// when it differs, so a caret that did not change never re-opens the keyboard.
void _restoreSelection(
  EditorState editorState,
  Selection before,
  ({_Anchor? start, _Anchor? end}) anchors,
  List<Node> nodes,
) {
  Position resolve(_Anchor? a, Position fallback) => a == null
      ? fallback
      : Position(
          path: [...nodes[a.index].path, ...a.rest],
          offset: a.offset,
        );
  final after = Selection(
    start: resolve(anchors.start, before.start),
    end: resolve(anchors.end, before.end),
  );
  if (editorState.selection != after) editorState.selection = after;
}
