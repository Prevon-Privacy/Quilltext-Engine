import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

void insertHeadingAfterSelection(EditorState editorState, int level) {
  insertNodeAfterSelection(
    editorState,
    headingNode(level: level),
  );
}

void insertQuoteAfterSelection(EditorState editorState) {
  insertNodeAfterSelection(
    editorState,
    quoteNode(),
  );
}

void insertCheckboxAfterSelection(EditorState editorState) {
  insertNodeAfterSelection(
    editorState,
    todoListNode(checked: false),
  );
}

void insertBulletedListAfterSelection(EditorState editorState) {
  insertNodeAfterSelection(
    editorState,
    bulletedListNode(),
  );
}

void insertNumberedListAfterSelection(EditorState editorState) {
  insertNodeAfterSelection(
    editorState,
    numberedListNode(),
  );
}

bool insertNodeAfterSelection(
  EditorState editorState,
  Node node,
) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return false;
  }

  final currentNode = editorState.getNodeAtPath(selection.end.path);
  if (currentNode == null) {
    return false;
  }
  node.updateAttributes({
    blockComponentTextDirection:
        currentNode.attributes[blockComponentTextDirection],
  });

  final transaction = editorState.transaction;
  final delta = currentNode.delta;
  if (delta != null && delta.isEmpty) {
    // The empty line is replaced, and deleting it would delete the rows nested
    // under it too. Carry them over: under the new block when it can draw
    // children, else right below it at its own level. Either way they stay
    // visible and in order.
    final kids = currentNode.children.toList();
    transaction
      ..insertNode(selection.end.path, node)
      ..deleteNode(currentNode);
    if (kids.isNotEmpty) {
      final at = indentableBlockTypes.contains(node.type)
          ? [...selection.end.path, 0]
          : selection.end.path.next;
      transaction.insertNodes(at, kids);
    }
    transaction.afterSelection =
        Selection.collapsed(Position(path: selection.end.path));
  } else {
    final next = selection.end.path.next;
    transaction
      ..insertNode(next, node)
      ..afterSelection = Selection.collapsed(Position(path: next));
  }

  editorState.apply(transaction);
  return true;
}
