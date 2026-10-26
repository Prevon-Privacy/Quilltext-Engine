// Every document edit a columns block supports, as plain functions over the
// document so the block's widget, the host app's menu and the keyboard
// commands all do exactly the same thing (and each is ONE undo step).
//
// Shape of the data:
//   columns            (the block; no attributes)
//     column           (weight: its share of the width, absent = 1)
//       paragraph ...  (any blocks except another columns block or a table)
//     column ...
//
// Rules the functions keep:
//   * a columns block has 2..[ColumnsBlockConstants.maxColumns] columns;
//   * a column is never empty (it always holds at least one block);
//   * when only one column is left the block dissolves: its blocks take the
//     block's place in the page, so the person never sees a one-column block.
// A deletion that crosses columns can break these (select-and-delete runs over
// several blocks), so [ColumnsActions.repair] puts them right afterwards.

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/plugins/blocks/columns/columns_block_constant.dart';

class ColumnsActions {
  const ColumnsActions._();

  /// Whether [node] sits inside a columns block or a table cell, where another
  /// columns block cannot go (nested columns are unreadable on a phone).
  static bool isNested(Node? node) {
    for (var n = node?.parent; n != null; n = n.parent) {
      if (n.type == ColumnsBlockKeys.type ||
          n.type == TableCellBlockKeys.type) {
        return true;
      }
    }
    return false;
  }

  /// The columns block that [node] is inside, or null.
  static Node? columnsOf(Node? node) {
    for (var n = node; n != null; n = n.parent) {
      if (n.type == ColumnsBlockKeys.type) return n;
    }
    return null;
  }

  /// The column of [columns] that holds the caret, or null.
  static Node? columnAtSelection(Node columns, EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null) return null;
    Node? n = editorState.getNodeAtPath(selection.start.path);
    while (n != null && n.parent != columns) {
      n = n.parent;
    }
    return n != null && n.type == ColumnBlockKeys.type ? n : null;
  }

  static List<Node> _columns(Node columns) =>
      columns.children.where((c) => c.type == ColumnBlockKeys.type).toList();

  /// Inserts a columns block of [count] empty columns at the caret's block and
  /// guarantees an empty paragraph outside it on each open side, so the caret
  /// can always leave it. An empty [currentNode] is replaced; otherwise the
  /// block goes after it. The caret lands in the first column. Returns false
  /// (changing nothing) inside another columns block or a table cell.
  static bool insert(
    EditorState editorState, {
    required Node currentNode,
    int count = 2,
  }) {
    if (isNested(currentNode)) return false;
    count = count.clamp(2, ColumnsBlockConstants.maxColumns);
    final columns = columnsNode(
      children: [for (var i = 0; i < count; i++) columnNode()],
    );

    final path = currentNode.path;
    final replaceCurrent = currentNode.delta?.isEmpty ?? false;
    final transaction = editorState.transaction;

    final needsLeading = replaceCurrent && currentNode.previous == null;
    final blockPath =
        replaceCurrent ? (needsLeading ? path.next : path) : path.next;
    final following = currentNode.next;
    final needsTrailing = following == null ||
        following.type == ColumnsBlockKeys.type ||
        following.type == TableBlockKeys.type;

    if (needsLeading) {
      transaction.insertNode(path, paragraphNode());
    }
    transaction.insertNode(blockPath, columns);
    if (needsTrailing) {
      transaction.insertNode(blockPath.next, paragraphNode());
    }
    if (replaceCurrent) {
      transaction.deleteNode(currentNode);
    }
    transaction.afterSelection = Selection.collapsed(
      Position(path: [...blockPath, 0, 0], offset: 0),
    );
    editorState.apply(transaction);
    return true;
  }

  /// Adds an empty column so it ends up at [position] (0 = leftmost). It takes
  /// the average width of the others. Returns false at the column limit.
  static bool addColumn(Node columns, int position, EditorState editorState) {
    final cols = _columns(columns);
    if (cols.length >= ColumnsBlockConstants.maxColumns) return false;
    final at = position.clamp(0, cols.length);
    final average = cols.isEmpty
        ? 1.0
        : cols.map(columnWeightOf).reduce((a, b) => a + b) / cols.length;
    final transaction = editorState.transaction
      ..insertNode(
        [...columns.path, at],
        columnNode(weight: average == 1.0 ? null : average),
      )
      ..afterSelection = Selection.collapsed(
        Position(path: [...columns.path, at, 0], offset: 0),
      );
    editorState.apply(transaction);
    return true;
  }

  /// Removes the column at [position] with everything in it. When that leaves
  /// one column the block dissolves (see [unwrap]). Where the caret goes: the
  /// end of the column on its left, else the start of the one that took its
  /// place.
  static bool removeColumn(
    Node columns,
    int position,
    EditorState editorState,
  ) {
    final cols = _columns(columns);
    if (position < 0 || position >= cols.length) return false;

    if (cols.length <= 2) {
      // The block dissolves into the column that stays.
      final keep = cols[position == 0 ? 1 : 0];
      return _dissolve(
        columns,
        editorState,
        keep.children.toList(),
        caretAtEnd: position != 0,
      );
    }

    final transaction = editorState.transaction..deleteNode(cols[position]);
    if (position > 0) {
      final left = cols[position - 1];
      final target = left.children.isEmpty ? null : left.children.last;
      transaction.afterSelection = target == null
          ? Selection.collapsed(Position(path: left.path))
          : Selection.collapsed(
              Position(
                path: target.path,
                offset: target.delta?.length ?? 0,
              ),
            );
    } else {
      transaction.afterSelection = Selection.collapsed(
        Position(path: [...columns.path, 0, 0], offset: 0),
      );
    }
    editorState.apply(transaction);
    return true;
  }

  /// Swaps the column at [from] to index [to] (the ones between shift over).
  static bool moveColumn(
    Node columns,
    int from,
    int to,
    EditorState editorState,
  ) {
    final cols = _columns(columns);
    if (from == to ||
        from < 0 ||
        to < 0 ||
        from >= cols.length ||
        to >= cols.length) {
      return false;
    }
    final original = cols[from];
    final copy = original.copyWith();
    final transaction = editorState.transaction;
    if (to > from) {
      transaction
        ..insertNode([...columns.path, to + 1], copy, deepCopy: false)
        ..deleteNode(original);
    } else {
      transaction
        ..insertNode([...columns.path, to], copy, deepCopy: false)
        ..deleteNode(original);
    }
    // Keep the caret in the same block, which now lives in the moved copy.
    final selection = editorState.selection;
    if (selection != null &&
        columnAtSelection(columns, editorState) == original) {
      final rel = selection.start.path.sublist(columns.path.length + 1);
      transaction.afterSelection = Selection.collapsed(
        Position(
          path: [...columns.path, to, ...rel],
          offset: selection.start.offset,
        ),
      );
    }
    editorState.apply(transaction);
    return true;
  }

  /// Gives every column the same width (one undo step).
  static bool equalize(Node columns, EditorState editorState) {
    final cols = _columns(columns);
    final transaction = editorState.transaction;
    var any = false;
    for (final c in cols) {
      if (c.attributes[ColumnBlockKeys.weight] != null) {
        transaction.updateNode(c, {ColumnBlockKeys.weight: null});
        any = true;
      }
    }
    if (!any) return false;
    editorState.apply(transaction, withUpdateSelection: false);
    return true;
  }

  /// Whether every column already has the same width.
  static bool isEqual(Node columns) {
    final cols = _columns(columns);
    if (cols.isEmpty) return true;
    final first = columnWeightOf(cols.first);
    return cols.every((c) => (columnWeightOf(c) - first).abs() < 0.001);
  }

  /// Deletes the whole columns block with everything in it (one undo step). The
  /// caret lands at the start of the next block, else the end of the previous
  /// one; a page left with nothing gets one empty paragraph.
  static bool deleteBlock(Node columns, EditorState editorState) {
    if (columns.parent == null) return false;
    final path = columns.path;
    final next = columns.next;
    final prev = columns.previous;
    final transaction = editorState.transaction;
    if (next != null) {
      transaction
        ..deleteNode(columns)
        ..afterSelection = Selection.collapsed(Position(path: path));
    } else if (prev != null) {
      transaction
        ..deleteNode(columns)
        ..afterSelection = Selection.collapsed(
          Position(path: prev.path, offset: prev.delta?.length ?? 0),
        );
    } else {
      transaction
        ..deleteNode(columns)
        ..insertNode(path, paragraphNode())
        ..afterSelection = Selection.collapsed(Position(path: path));
    }
    editorState.apply(transaction);
    return true;
  }

  /// Dissolves the columns block: every column's blocks, left to right, take
  /// its place in the page (one undo step). Nothing is deleted.
  static bool unwrap(Node columns, EditorState editorState) {
    final blocks = <Node>[
      for (final c in _columns(columns)) ...c.children,
    ];
    return _dissolve(columns, editorState, blocks, caretAtEnd: false);
  }

  static bool _dissolve(
    Node columns,
    EditorState editorState,
    List<Node> blocks, {
    required bool caretAtEnd,
  }) {
    if (columns.parent == null) return false;
    final transaction = editorState.transaction;
    final path = columns.path;
    if (blocks.isEmpty) {
      transaction
        ..insertNode(path.next, paragraphNode())
        ..deleteNode(columns);
      transaction.afterSelection = Selection.collapsed(Position(path: path));
      editorState.apply(transaction);
      return true;
    }
    // New blocks go in after the old block, then the old block goes: the other
    // order makes the transaction shift the insert path backwards.
    transaction
      ..insertNodes(path.next, blocks)
      ..deleteNode(columns);
    final targetIndex = caretAtEnd ? blocks.length - 1 : 0;
    final target = blocks[targetIndex];
    transaction.afterSelection = Selection.collapsed(
      Position(
        path: path.parent + [path.last + targetIndex],
        offset: caretAtEnd ? (target.delta?.length ?? 0) : 0,
      ),
    );
    editorState.apply(transaction);
    return true;
  }

  /// Whether [columns] breaks a rule in the header: fewer than two columns, an
  /// empty column, or a child that is not a column.
  static bool needsRepair(Node columns) {
    final children = columns.children;
    if (children.length < 2) return true;
    for (final c in children) {
      if (c.type != ColumnBlockKeys.type || c.children.isEmpty) return true;
    }
    return false;
  }

  /// Puts a broken columns block right (one undo step): an empty column gets
  /// an empty paragraph, a block left with no column is removed, and one left
  /// with a single column dissolves. Returns false when nothing needed doing.
  static bool repair(Node columns, EditorState editorState) {
    if (columns.parent == null || !needsRepair(columns)) return false;
    final cols = _columns(columns);
    final transaction = editorState.transaction;

    if (cols.isEmpty) {
      final root = editorState.document.root;
      if (root.children.length == 1) {
        transaction.insertNode(columns.path.next, paragraphNode());
      }
      transaction.deleteNode(columns);
      editorState.apply(transaction, withUpdateSelection: false);
      return true;
    }

    if (cols.length == 1) {
      final blocks = cols.first.children.toList();
      if (blocks.isEmpty) {
        // A lone empty column: just remove the block.
        final root = editorState.document.root;
        if (root.children.length == 1) {
          transaction.insertNode(columns.path.next, paragraphNode());
        }
        transaction.deleteNode(columns);
      } else {
        transaction
          ..insertNodes(columns.path.next, blocks)
          ..deleteNode(columns);
      }
      editorState.apply(transaction, withUpdateSelection: false);
      return true;
    }

    var changed = false;
    for (final c in cols) {
      if (c.children.isEmpty) {
        transaction.insertNode([...c.path, 0], paragraphNode());
        changed = true;
      }
    }
    if (!changed) return false;
    editorState.apply(transaction, withUpdateSelection: false);
    return true;
  }

  /// Backspace at the very start of a block inside a column. Returns true when
  /// the key was consumed: the first block of a column never merges into
  /// whatever is to its left (that would drag it out of its column), and an
  /// empty column that holds only that block is removed instead.
  static bool backspaceAtColumnStart(Node block, EditorState editorState) {
    final column = block.parent;
    if (column == null || column.type != ColumnBlockKeys.type) return false;
    if (!identical(column.children.first, block)) return false;
    final columns = column.parent;
    if (columns == null || columns.type != ColumnsBlockKeys.type) return false;
    final empty = block.delta?.isEmpty ?? false;
    if (empty && column.children.length == 1) {
      removeColumn(columns, _columns(columns).indexOf(column), editorState);
    }
    return true;
  }
}
