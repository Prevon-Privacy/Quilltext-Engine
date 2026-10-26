import 'package:flutter/material.dart';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// Delete key event.
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent deleteCommand = CommandShortcutEvent(
  key: 'Delete Key',
  getDescription: () => AppFlowyEditorL10n.current.cmdDeleteRight,
  command: 'delete, shift+delete',
  handler: _deleteCommandHandler,
);

CommandShortcutEventHandler _deleteCommandHandler = (editorState) {
  final selection = editorState.selection;
  final selectionType = editorState.selectionType;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  if (selectionType == SelectionType.block) {
    return _deleteInBlockSelection(editorState);
  } else if (selection.isCollapsed) {
    return _deleteInCollapsedSelection(editorState);
  } else {
    return _deleteInNotCollapsedSelection(editorState);
  }
};

/// Handle delete key event when selection is collapsed.
CommandShortcutEventHandler _deleteInCollapsedSelection = (editorState) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return KeyEventResult.ignored;
  }

  final position = selection.start;
  final node = editorState.getNodeAtPath(position.path);
  final delta = node?.delta;
  if (node == null || delta == null) {
    return KeyEventResult.ignored;
  }

  final transaction = editorState.transaction;

  if (position.offset == delta.length) {
    Node? tableParent = _mergeScopeOf(node);
    Node? nextTableParent;
    final next = node.findDownward((element) {
      nextTableParent = _mergeScopeOf(element);
      // break if only one is in a table or they're in different tables
      return tableParent != nextTableParent ||
          // merge the next node with delta
          element.delta != null;
    });
    // table nodes should be deleted using the table menu
    // in-table paragraphs should only be deleted inside the table
    if (next != null && tableParent == nextTableParent) {
      if (next.children.isNotEmpty) {
        final path = node.path + [node.children.length];
        transaction.insertNodes(path, next.children);
      }
      transaction
        ..deleteNode(next)
        ..mergeText(
          node,
          next,
        );
      editorState.apply(transaction);
      return KeyEventResult.handled;
    }
  } else {
    final nextIndex = delta.nextRunePosition(position.offset);
    if (nextIndex <= delta.length) {
      transaction.deleteText(
        node,
        position.offset,
        nextIndex - position.offset,
      );
      editorState.apply(transaction);
      return KeyEventResult.handled;
    }
  }

  return KeyEventResult.ignored;
};

/// The table or column a block lives in: text never merges across two
/// different ones.
Node? _mergeScopeOf(Node node) => node.findParent(
      (element) =>
          element.type == TableBlockKeys.type ||
          element.type == ColumnBlockKeys.type,
    );

/// Handle delete key event when selection is not collapsed.
CommandShortcutEventHandler _deleteInNotCollapsedSelection = (editorState) {
  final selection = editorState.selection;
  if (selection == null || selection.isCollapsed) {
    return KeyEventResult.ignored;
  }
  editorState.deleteSelection(selection);
  return KeyEventResult.handled;
};

CommandShortcutEventHandler _deleteInBlockSelection = (editorState) {
  final selection = editorState.selection;
  if (selection == null || editorState.selectionType != SelectionType.block) {
    return KeyEventResult.ignored;
  }
  final transaction = editorState.transaction;
  transaction.deleteNodesAtPath(selection.start.path);
  editorState
      .apply(transaction)
      .then((value) => editorState.selectionType = null);

  return KeyEventResult.handled;
};
