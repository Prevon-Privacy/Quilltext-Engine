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
  return indentBlocks(editorState, [node]);
}

/// The one indent every path uses (swipe, Tab, Ctrl/Cmd+], toolbar).
///
/// [nodes] are consecutive children of one parent whose previous sibling is a
/// container; they (with their subtrees, keeping ids) become its last children.
/// The selection follows the text, also when it sat inside a nested row.
/// Returns the first moved block at its new place, or null when nothing moved.
Node? indentBlocks(EditorState editorState, List<Node> nodes) {
  if (nodes.isEmpty) return null;
  final first = nodes.first;
  final previous = first.previous;
  if (previous == null ||
      !indentableBlockTypes.contains(previous.type) ||
      nodes.any((n) =>
          n.parent != first.parent || !movableBlockTypes.contains(n.type))) {
    return null;
  }
  final base = [...previous.path, previous.children.length];
  final before = editorState.selection;
  final transaction = editorState.transaction
    ..deleteNodes(nodes.reversed)
    ..insertNodes(base, nodes, deepCopy: true, keepIds: true);

  Position remap(Position p) {
    for (var i = 0; i < nodes.length; i++) {
      final from = nodes[i].path;
      if (_isPrefix(from, p.path)) {
        return Position(
          path: [
            ...previous.path,
            previous.children.length + i,
            ...p.path.sublist(from.length),
          ],
          offset: p.offset,
        );
      }
    }
    return p;
  }

  transaction.afterSelection = before == null
      ? null
      : Selection(start: remap(before.start), end: remap(before.end));
  editorState.apply(transaction, withUpdateSelection: false);
  final after = transaction.afterSelection;
  if (after != null && after != before) editorState.selection = after;
  return editorState.getNodeAtPath(base);
}

/// See [tryIndentBlockNode]. Moves [node] out of its parent, to just after it.
Node? tryOutdentBlockNode(EditorState editorState, Node node) {
  if (!canOutdentBlockNode(node)) return null;
  return outdentBlocks(editorState, [node]);
}

/// The one outdent every path uses (swipe, Shift+Tab, Ctrl/Cmd+[, toolbar).
///
/// [nodes] are consecutive children of one parent. They (with their own
/// subtrees) move to just after that parent, keeping their ids. The siblings
/// that sat BELOW them must not be left behind above them, or the reading order
/// flips: when the last moved block can hold children they become its trailing
/// children (levels kept, as in Notion); otherwise they move out with it.
/// Returns the first moved block at its new place, or null when nothing moved.
Node? outdentBlocks(EditorState editorState, List<Node> nodes) {
  if (nodes.isEmpty) return null;
  final parent = nodes.first.parent;
  if (parent == null || !canOutdentBlockNode(nodes.first)) return null;
  if (nodes
      .any((n) => n.parent != parent || !movableBlockTypes.contains(n.type))) {
    return null;
  }
  final last = nodes.last;
  final trailing = parent.children.skip(last.path.last + 1).toList();
  final adopt = indentableBlockTypes.contains(last.type);
  final target = parent.path.sublist(0, parent.path.length - 1)
    ..add(parent.path.last + 1);
  final lastTarget = [
    ...target.sublist(0, target.length - 1),
    target.last + nodes.length - 1
  ];
  final firstAdopted = last.children.length;
  final before = editorState.selection;

  // One insert: a second insert below the first would have its path shifted by
  // the transaction. The adopted rows go into the last moved block's copy.
  final moved = [for (final n in nodes) n.copyWith(keepIds: true)];
  final tail = [for (final n in trailing) n.copyWith(keepIds: true)];
  if (adopt) {
    tail.forEach(moved.last.insert);
  } else {
    moved.addAll(tail);
  }
  final transaction = editorState.transaction
    ..deleteNodes([...nodes, ...trailing].reversed)
    ..insertNodes(target, moved, deepCopy: false);

  Position remap(Position p) {
    final path = p.path;
    for (var i = 0; i < nodes.length; i++) {
      final from = nodes[i].path;
      if (_isPrefix(from, path)) {
        return Position(
          path: [
            ...target.sublist(0, target.length - 1),
            target.last + i,
            ...path.sublist(from.length)
          ],
          offset: p.offset,
        );
      }
    }
    for (var j = 0; j < trailing.length; j++) {
      final from = trailing[j].path;
      if (_isPrefix(from, path)) {
        final rest = path.sublist(from.length);
        final base = adopt
            ? [...lastTarget, firstAdopted + j]
            : [
                ...target.sublist(0, target.length - 1),
                target.last + nodes.length + j
              ];
        return Position(path: [...base, ...rest], offset: p.offset);
      }
    }
    return p;
  }

  transaction.afterSelection = before == null
      ? null
      : Selection(start: remap(before.start), end: remap(before.end));
  editorState.apply(transaction, withUpdateSelection: false);
  final after = transaction.afterSelection;
  if (after != null && after != before) editorState.selection = after;
  return editorState.getNodeAtPath(target);
}

/// Moves [node] (with its subtree, keeping ids) to the slot [target], a path in
/// the document BEFORE the move, at any depth. Returns the block at its new
/// place, or null when the slot is inside the block itself or changes nothing.
/// The one move every drag, "move down out of a group" and reorder path uses.
Node? moveBlockTo(EditorState editorState, Node node, Path target) {
  final from = node.path;
  if (_isPrefix(from, target)) return null;
  final to = [...target];
  final n = from.length;
  if (to.length >= n &&
      _isPrefix(from.sublist(0, n - 1), to) &&
      to[n - 1] > from[n - 1]) {
    to[n - 1]--;
  }
  if (to.equals(from)) return null;
  final transaction = editorState.transaction
    ..deleteNode(node)
    ..insertNodes(to, [node], deepCopy: true, keepIds: true);
  _applyMove(editorState, transaction, from, to);
  return editorState.getNodeAtPath(to);
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
