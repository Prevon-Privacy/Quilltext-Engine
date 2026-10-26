import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// Document edits a file block supports. Every function is one transaction,
/// so one undo reverts it. Removing a block never deletes the attachment: the
/// bytes stay so undo works; a later sweep removes unreferenced ones.

/// Moves the block one slot up (`-1`) or down (`1`). False at that end.
bool moveFile(EditorState editorState, Node node, int direction) {
  final parent = node.parent;
  if (parent == null) return false;
  final current = node.path.last;
  if (direction < 0 && current == 0) return false;
  if (direction > 0 && current >= parent.children.length - 1) return false;
  final slot = direction < 0 ? current - 1 : current + 2;
  final moved = moveNodeAmongSiblings(editorState, node, slot);
  if (moved) {
    final newPath = node.path;
    editorState.selection = Selection(
      start: Position(path: newPath, offset: 0),
      end: Position(path: newPath, offset: 1),
    );
  }
  return moved;
}

/// Deletes the block and leaves the caret on a neighbour. A note that would
/// end up empty keeps one empty paragraph.
void removeFile(EditorState editorState, Node node) {
  final parent = node.parent;
  if (parent == null) return;
  final path = node.path;
  final transaction = editorState.transaction;
  if (parent.children.length == 1) {
    transaction
      ..insertNode(path, paragraphNode())
      ..deleteNode(node);
    transaction.afterSelection =
        Selection.collapsed(Position(path: path, offset: 0));
  } else {
    transaction.deleteNode(node);
    if (path.last < parent.children.length - 1) {
      transaction.afterSelection =
          Selection.collapsed(Position(path: path, offset: 0));
    } else {
      final prev = parent.children[path.last - 1];
      transaction.afterSelection = Selection.collapsed(
        Position(path: prev.path, offset: prev.delta?.length ?? 0),
      );
    }
  }
  editorState.apply(transaction);
}

/// Sets or clears "Hide" on a file block: one transaction, so one undo reverts
/// it. Visible is stored as the attribute's absence, so an untouched note body does not change.
void setFileHiddenFromAi(EditorState editorState, Node node, bool hidden) {
  editorState.apply(
    editorState.transaction
      ..updateNode(node, {FileBlockKeys.hiddenFromAi: hidden ? true : null}),
  );
}
