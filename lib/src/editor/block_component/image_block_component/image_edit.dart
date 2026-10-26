import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// Document edits an image block supports. Every function is one transaction,
/// so one undo reverts it.

/// Sets the image's width in dp, or `null` for "fill the page".
///
/// The height is always cleared: it was saved for the old width, and a fixed
/// height next to a new width would letterbox the picture.
void setImageWidth(EditorState editorState, Node node, double? width) {
  final transaction = editorState.transaction
    ..updateNode(node, {
      ImageBlockKeys.width: width,
      ImageBlockKeys.height: null,
    });
  transaction.afterSelection = editorState.selection;
  editorState.apply(transaction);
}

/// Sets a preset width: [fraction] of [available] dp, or full width at 1.0.
void setImageWidthFraction(
  EditorState editorState,
  Node node, {
  required double fraction,
  required double available,
}) {
  if (fraction >= 0.999 || available <= 0) {
    setImageWidth(editorState, node, null);
  } else {
    setImageWidth(editorState, node, (fraction * available).roundToDouble());
  }
}

/// `left`, `center` or `right`.
void setImageAlign(EditorState editorState, Node node, String align) {
  final transaction = editorState.transaction
    ..updateNode(node, {ImageBlockKeys.align: align});
  transaction.afterSelection = editorState.selection;
  editorState.apply(transaction);
}

/// Moves the block one slot up (`-1`) or down (`1`) among its siblings.
/// Returns false when it is already at that end.
bool moveImage(EditorState editorState, Node node, int direction) {
  final parent = node.parent;
  if (parent == null) return false;
  final current = node.path.last;
  // `moveNodeAmongSiblings` takes a slot in the pre-move list: the gap before
  // the previous sibling, or the gap after the next one.
  final slot = direction < 0 ? current - 1 : current + 2;
  if (direction < 0 && current == 0) return false;
  if (direction > 0 && current >= parent.children.length - 1) return false;
  final moved = moveNodeAmongSiblings(editorState, node, slot);
  if (moved) {
    // The block keeps its selection, now at its new path.
    final newPath = node.path;
    editorState.selection = Selection(
      start: Position(path: newPath, offset: 0),
      end: Position(path: newPath, offset: 1),
    );
  }
  return moved;
}

/// Deletes the image block and leaves the caret on its neighbour. A note that
/// would end up empty keeps one empty paragraph so there is always a place to
/// type.
void removeImage(EditorState editorState, Node node) {
  final parent = node.parent;
  if (parent == null) return;
  final path = node.path;
  final transaction = editorState.transaction;
  if (parent.children.length == 1) {
    transaction
      ..insertNode(path, paragraphNode())
      ..deleteNode(node);
    transaction.afterSelection = Selection.collapsed(
      Position(path: path, offset: 0),
    );
  } else {
    transaction.deleteNode(node);
    final hasNext = path.last < parent.children.length - 1;
    if (hasNext) {
      // The next block slides into this path.
      transaction.afterSelection = Selection.collapsed(
        Position(path: path, offset: 0),
      );
    } else {
      final prev = parent.children[path.last - 1];
      transaction.afterSelection = Selection.collapsed(
        Position(path: prev.path, offset: prev.delta?.length ?? 0),
      );
    }
  }
  editorState.apply(transaction);
}
