import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/widgets.dart';

/// PREVON PATCH 14 — indent / outdent rules shared by the touch swipe
/// (`TouchReorderHandle`) and the keyboard (`indentCommand` / `outdentCommand`
/// and their Ctrl/Cmd+] / [ aliases).
///
/// * **Who can move:** every block type that has a reorder grip — text blocks,
///   lists, headings, quotes, dividers, images and tables. A block is indented
///   by becoming the last child of its previous sibling, so the *previous
///   sibling* must be a container ([indentableBlockTypes]: paragraph, bulleted,
///   numbered, to-do — the only components that render children).
/// * **How deep:** as deep as the screen allows, not a fixed number. Each level
///   costs one indent step of width, and the row must keep at least
///   [kMinIndentedRowWidth] for its marker and a few words of text; past that a
///   wrapped line would degrade to a few characters per line. See
///   [indentWouldFit]. The row's text keeps wrapping inside that narrower
///   column, so wrapped lines stay inside the indent (hanging indent).

/// Block types that can be moved into / out of a parent by indentation.
const Set<String> movableBlockTypes = {
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
  TodoListBlockKeys.type,
  ParagraphBlockKeys.type,
  HeadingBlockKeys.type,
  QuoteBlockKeys.type,
  CollapsibleBlockKeys.type,
  DividerBlockKeys.type,
  ImageBlockKeys.type,
  TableBlockKeys.type,
};

/// Blocks a hold in the page margin can pick up and move. Everything that can
/// be indented, plus the columns block, which can be moved as a whole but never
/// nested under another block.
const Set<String> gutterReorderBlockTypes = {
  ...movableBlockTypes,
  ColumnsBlockKeys.type,
  FileBlockKeys.type,
};

/// Narrowest a row may get from indentation: marker + grip (~66dp) plus room
/// for roughly a dozen characters of body text.
const double kMinIndentedRowWidth = 170;

/// Width of one indent level, read from the previous block's own
/// configuration so a host that restyles indentation is respected.
double indentStepFor(EditorState editorState, Node container) {
  final builder = editorState.renderer.blockComponentBuilder(container.type);
  final padding =
      builder?.configuration.indentPadding(container, TextDirection.ltr);
  final step = padding?.horizontal ?? 24.0;
  return step > 0 ? step : 24.0;
}

/// How many levels of nesting [node] carries below itself (0 = a leaf).
int subtreeDepth(Node node) {
  var deepest = 0;
  for (final child in node.children) {
    final d = 1 + subtreeDepth(child);
    if (d > deepest) deepest = d;
  }
  return deepest;
}

/// Whether [node] still keeps at least [kMinIndentedRowWidth] once it (and its
/// own nested children) sit one level deeper, inside [container].
///
/// Uses the container's laid-out width, so it adapts to the phone, the desktop
/// column and any outer padding. An un-laid-out container is treated as
/// "fits" (nothing to measure).
bool indentWouldFit(EditorState editorState, Node container, Node node) {
  final box = container.key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return true;
  final step = indentStepFor(editorState, container);
  final widthAtNewLevel = box.size.width - step;
  final widthAtDeepestChild = widthAtNewLevel - subtreeDepth(node) * step;
  return widthAtDeepestChild >= kMinIndentedRowWidth;
}

/// Whether [node] can be indented under its previous sibling right now.
bool canIndentBlockNode(EditorState editorState, Node node) {
  final previous = node.previous;
  if (previous == null ||
      !indentableBlockTypes.contains(previous.type) ||
      !movableBlockTypes.contains(node.type)) {
    return false;
  }
  return indentWouldFit(editorState, previous, node);
}

/// Whether [node] can be moved out one level.
bool canOutdentBlockNode(Node node) {
  final parent = node.parent;
  return parent != null &&
      node.path.length > 1 &&
      indentableBlockTypes.contains(parent.type) &&
      movableBlockTypes.contains(node.type);
}

/// Selection-free indent of ONE block (used by the touch swipes): neither
/// needs nor moves the caret — setting a selection on mobile would pop the
/// keyboard. Returns the block at its new position (a new [Node] instance, so
/// a multi-step gesture can keep going), or null when nothing changed.
Node? tryIndentBlockNode(EditorState editorState, Node node) {
  if (!canIndentBlockNode(editorState, node)) return null;
  final previous = node.previous!;
  final target = [...previous.path, previous.children.length];
  final transaction = editorState.transaction
    ..deleteNode(node)
    ..insertNodes(target, [node], deepCopy: true);
  _applyMove(editorState, transaction, node.path, target);
  return editorState.getNodeAtPath(target);
}

/// See [tryIndentBlockNode]. Moves [node] out of its parent, to just after it.
Node? tryOutdentBlockNode(EditorState editorState, Node node) {
  if (!canOutdentBlockNode(node)) return null;
  final parent = node.parent!;
  final target = parent.path.sublist(0, parent.path.length - 1)
    ..add(parent.path.last + 1);
  final transaction = editorState.transaction
    ..deleteNode(node)
    ..insertNodes(target, [node], deepCopy: true);
  _applyMove(editorState, transaction, node.path, target);
  return editorState.getNodeAtPath(target);
}

/// Applies a delete-at-[from] + insert-at-[to] move and keeps the caret on the
/// same text: a path inside the moved block follows it, a path in a later
/// sibling shifts with the list. The selection is only written when it
/// actually changed, so a caret that did not move never re-opens the keyboard.
void _applyMove(
  EditorState editorState,
  Transaction transaction,
  Path from,
  Path to,
) {
  final before = editorState.selection;
  final after = before == null
      ? null
      : Selection(
          start: _remap(before.start, from, to),
          end: _remap(before.end, from, to),
        );
  transaction.afterSelection = after;
  editorState.apply(transaction, withUpdateSelection: false);
  if (after != null && after != before) editorState.selection = after;
}

Position _remap(Position p, Path from, Path to) {
  final path = [...p.path];
  final n = from.length;
  if (path.length >= n && _isPrefix(from, path)) {
    return Position(
      path: [...to, ...path.sublist(n)],
      offset: p.offset,
    );
  }
  // Not in the moved block: first the delete at [from], then the insert at [to].
  if (path.length >= n &&
      _isPrefix(from.sublist(0, n - 1), path) &&
      path[n - 1] > from[n - 1]) {
    path[n - 1]--;
  }
  final m = to.length;
  if (path.length >= m &&
      _isPrefix(to.sublist(0, m - 1), path) &&
      path[m - 1] >= to[m - 1]) {
    path[m - 1]++;
  }
  return Position(path: path, offset: p.offset);
}

bool _isPrefix(Path prefix, Path path) {
  if (path.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (path[i] != prefix[i]) return false;
  }
  return true;
}

bool indentBlockNode(EditorState editorState, Node node) =>
    tryIndentBlockNode(editorState, node) != null;

bool outdentBlockNode(EditorState editorState, Node node) =>
    tryOutdentBlockNode(editorState, node) != null;

/// The innermost block whose laid-out box contains [global] — the row under a
/// fingertip. (`selectionService.getNodeInOffset` only knows the top-level
/// blocks, so a nested row under the finger would resolve to its ancestor.)
Node? blockAtGlobalOffset(EditorState editorState, Offset global) {
  Node? found;
  Iterable<Node> level = editorState.document.root.children;
  while (true) {
    Node? hit;
    for (final n in level) {
      final box = n.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      if ((Offset.zero & box.size).contains(box.globalToLocal(global))) {
        hit = n;
        break;
      }
    }
    if (hit == null) return found;
    found = hit;
    level = hit.children;
  }
}
