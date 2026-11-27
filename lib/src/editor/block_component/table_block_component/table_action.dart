import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

class TableActions {
  const TableActions._();

  static void add(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _addCol(node, position, editorState);
    } else {
      _addRow(node, position, editorState);
    }
  }

  static void delete(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _deleteCol(node, position, editorState);
    } else {
      _deleteRow(node, position, editorState);
    }
  }

  static void duplicate(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _duplicateCol(node, position, editorState);
    } else {
      _duplicateRow(node, position, editorState);
    }
  }

  static void clear(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _clearCol(node, position, editorState);
    } else {
      _clearRow(node, position, editorState);
    }
  }

  static void setBgColor(
    Node node,
    int position,
    EditorState editorState,
    String? color,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _setColBgColor(node, position, editorState, color);
    } else {
      _setRowBgColor(node, position, editorState, color);
    }
  }

  /// Whether row 0 ([TableDirection.row]) or column 0 ([TableDirection.col]) of
  /// [table] is marked as its header.
  static bool isHeader(Node table, TableDirection dir) =>
      table.attributes[dir == TableDirection.col
          ? TableBlockKeys.headerCol
          : TableBlockKeys.headerRow] ==
      true;

  /// Marks (or unmarks) row 0 / column 0 as the header (one undo step). Marking
  /// tints the line with [kDefaultTableHeaderRowColor] unless it already has a
  /// color; unmarking removes only that default tint, never a color the person
  /// chose.
  static void setHeader(
    Node table,
    EditorState editorState,
    TableDirection dir,
    bool on,
  ) {
    final col = dir == TableDirection.col;
    final colorKey = col
        ? TableCellBlockKeys.colBackgroundColor
        : TableCellBlockKeys.rowBackgroundColor;
    final count =
        table.attributes[col ? TableBlockKeys.rowsLen : TableBlockKeys.colsLen]
            as int;
    final transaction = editorState.transaction;
    for (var i = 0; i < count; i++) {
      final cell = col ? getCellNode(table, 0, i) : getCellNode(table, i, 0);
      if (cell == null) continue;
      final current = cell.attributes[colorKey] as String?;
      if (on && current == null) {
        transaction.updateNode(cell, {colorKey: kDefaultTableHeaderRowColor});
      } else if (!on && current == kDefaultTableHeaderRowColor) {
        transaction.updateNode(cell, {colorKey: null});
      }
    }
    transaction.updateNode(table, {
      col ? TableBlockKeys.headerCol : TableBlockKeys.headerRow: on,
    });
    editorState.apply(transaction, withUpdateSelection: false);
  }

  /// Fills one [cell] (null clears it). Beats the row and column fills.
  static void setCellBgColor(
    Node cell,
    EditorState editorState,
    String? color,
  ) {
    final transaction = editorState.transaction
      ..updateNode(cell, {TableCellBlockKeys.cellBackgroundColor: color});
    editorState.apply(transaction, withUpdateSelection: false);
  }

  /// The cell of [table] that holds the caret, or null when the caret is
  /// elsewhere.
  static Node? cellAtSelection(Node table, EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null) return null;
    Node? n = editorState.getNodeAtPath(selection.start.path);
    while (n != null && n.type != TableCellBlockKeys.type) {
      n = n.parent;
    }
    return n != null && identical(n.parent, table) ? n : null;
  }

  /// Whether the row or column at [position] may be moved: the pinned header
  /// line may not.
  static bool canMove(Node table, int position, TableDirection dir) =>
      !(position == 0 && isHeader(table, dir));

  /// Moves the row or column [from] so it ends up at index [to] (one undo
  /// step; the lines in between shift by one). Sizes and fills travel with the
  /// line. Returns false, changing nothing, when the indexes are equal or out
  /// of range, or when the move would touch the pinned header.
  static bool move(
    Node table,
    int from,
    int to,
    EditorState editorState,
    TableDirection dir,
  ) =>
      _moveLine(table, from, to, editorState, dir);

  /// Empties every cell of [table] (one undo step). The grid, its sizes and
  /// its colors stay.
  static void clearTable(Node table, EditorState editorState) {
    final transaction = editorState.transaction;
    for (final cell in table.children.toList()) {
      _clearCellContent(transaction, cell);
    }
    editorState.apply(transaction, withUpdateSelection: false);
  }

  /// Removes the whole [table] (one undo step). The caret moves to the start
  /// of the block after it, else the end of the block before it; a table that
  /// was the only block leaves one empty paragraph.
  static void deleteTable(Node table, EditorState editorState) {
    final path = table.path;
    final next = table.next;
    final prev = table.previous;
    final transaction = editorState.transaction;
    if (next?.delta != null) {
      transaction
        ..deleteNode(table)
        ..afterSelection = Selection.collapsed(Position(path: path));
    } else if (prev?.delta != null) {
      transaction
        ..deleteNode(table)
        ..afterSelection = Selection.collapsed(
          Position(path: prev!.path, offset: prev.delta!.length),
        );
    } else {
      transaction
        ..deleteNode(table)
        ..insertNode(path, paragraphNode())
        ..afterSelection = Selection.collapsed(Position(path: path));
    }
    editorState.apply(transaction);
  }
}

/// Replaces everything in [cell] with one empty paragraph. Children go last to
/// first so each delete path is still valid when the operations are applied in
/// order.
void _clearCellContent(Transaction transaction, Node cell) {
  final path = cell.path;
  final old = cell.children.toList();
  // The empty paragraph goes in AFTER the old content, then the old content is deleted. Deleting first
  // and inserting at the same index made the transaction shift that insert backwards, and undo left
  // extra empty paragraphs in the cell.
  transaction.insertNode([...path, old.length], paragraphNode(text: ''));
  for (final child in old.reversed) {
    transaction.deleteNode(child);
  }
}

bool _moveLine(
  Node table,
  int from,
  int to,
  EditorState editorState,
  TableDirection dir,
) {
  final cols = table.attributes[TableBlockKeys.colsLen] as int;
  final rows = table.attributes[TableBlockKeys.rowsLen] as int;
  final isCol = dir == TableDirection.col;
  final count = isCol ? cols : rows;
  if (from == to || from < 0 || to < 0 || from >= count || to >= count) {
    return false;
  }
  if (TableActions.isHeader(table, dir) && (from == 0 || to == 0)) {
    return false;
  }
  if (table.children.length != cols * rows) return false;

  int remap(int i) {
    if (i == from) return to;
    if (from < to && i > from && i <= to) return i - 1;
    if (from > to && i >= to && i < from) return i + 1;
    return i;
  }

  // Where the caret sits now, so it can follow its cell.
  final caretCell = TableActions.cellAtSelection(table, editorState);
  final selection = editorState.selection;
  final caretInCell = caretCell != null && selection != null;

  // Children stay in column-major order (the Tab key and "add" rely on it), so
  // the moved grid is written back whole instead of patching positions.
  final fresh = <Node>[];
  for (var c = 0; c < cols; c++) {
    for (var r = 0; r < rows; r++) {
      final cell = getCellNode(table, c, r);
      if (cell == null) return false;
      fresh.add(cell);
    }
  }
  final moved = <Node>[
    for (final cell in fresh)
      cell.copyWith(
        keepIds: true,
        attributes: {
          ...cell.attributes,
          TableCellBlockKeys.colPosition: isCol
              ? remap(cell.attributes[TableCellBlockKeys.colPosition] as int)
              : cell.attributes[TableCellBlockKeys.colPosition],
          TableCellBlockKeys.rowPosition: isCol
              ? cell.attributes[TableCellBlockKeys.rowPosition]
              : remap(cell.attributes[TableCellBlockKeys.rowPosition] as int),
        },
      ),
  ]..sort((a, b) {
      final byCol = (a.attributes[TableCellBlockKeys.colPosition] as int)
          .compareTo(b.attributes[TableCellBlockKeys.colPosition] as int);
      return byCol != 0
          ? byCol
          : (a.attributes[TableCellBlockKeys.rowPosition] as int)
              .compareTo(b.attributes[TableCellBlockKeys.rowPosition] as int);
    });

  // Insert the new grid after the old one, then delete the old cells: the
  // other order makes the transaction shift the insert path backwards.
  final cellCount = table.children.length;
  final transaction = editorState.transaction
    ..insertNodes([...table.path, cellCount], moved, deepCopy: false)
    ..deleteNodesAtPath([...table.path, 0], cellCount);

  if (caretInCell) {
    var c = caretCell.attributes[TableCellBlockKeys.colPosition] as int;
    var r = caretCell.attributes[TableCellBlockKeys.rowPosition] as int;
    if (isCol) {
      c = remap(c);
    } else {
      r = remap(r);
    }
    transaction.afterSelection = Selection.collapsed(
      Position(path: [...table.path, c * rows + r, 0], offset: 0),
    );
  } else {
    transaction.afterSelection = selection;
  }
  editorState.apply(transaction);
  return true;
}

/// Where a caret cell lands after a row/column edit: the new (col,row), and
/// [reset] when its own line was deleted (the caret then goes to the start of
/// the neighbouring cell).
typedef _CellMove = ({int c, int r, bool reset});

/// Applies [transaction] and keeps the caret in the same logical cell. Cells are
/// stored column-major (index = col * rows + row), so a bare path would point at
/// a different cell once a line is added or removed. [map] gives the new cell of
/// an old (col,row); [oldRows] / [newRows] are the row counts before / after.
void _applyKeepingCaret(
  Transaction transaction,
  Node table,
  EditorState editorState,
  int oldRows,
  int newRows,
  _CellMove Function(int c, int r) map,
) {
  final sel = editorState.selection;
  final tp = table.path;
  var touched = false;
  Position remap(Position p) {
    final path = p.path;
    if (path.length <= tp.length ||
        !path.sublist(0, tp.length).equals(tp)) {
      return p;
    }
    touched = true;
    final idx = path[tp.length];
    final m = map(idx ~/ oldRows, idx % oldRows);
    final cell = m.c * newRows + m.r;
    if (m.reset) return Position(path: [...tp, cell, 0], offset: 0);
    return Position(
      path: [...tp, cell, ...path.sublist(tp.length + 1)],
      offset: p.offset,
    );
  }

  if (sel != null) {
    final next = Selection(start: remap(sel.start), end: remap(sel.end));
    if (touched) transaction.afterSelection = next;
  }
  editorState.apply(transaction, withUpdateSelection: touched);
}

_CellMove _deleteMap(int idx, int c, int r, int count, bool isCol) {
  final i = isCol ? c : r;
  int fix(int v) => v > idx ? v - 1 : v;
  if (i == idx) {
    final to = idx < count - 1 ? idx : idx - 1;
    return isCol
        ? (c: to, r: r, reset: true)
        : (c: c, r: to, reset: true);
  }
  return isCol ? (c: fix(c), r: r, reset: false) : (c: c, r: fix(r), reset: false);
}

void _addCol(Node tableNode, int position, EditorState editorState) {
  assert(position >= 0);

  final transaction = editorState.transaction;

  List<Node> cellNodes = [];
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (position != colsLen) {
    for (var i = position; i < colsLen; i++) {
      for (var j = 0; j < rowsLen; j++) {
        final node = getCellNode(tableNode, i, j)!;
        transaction.updateNode(node, {TableCellBlockKeys.colPosition: i + 1});
      }
    }
  }

  for (var i = 0; i < rowsLen; i++) {
    final node = Node(
      type: TableCellBlockKeys.type,
      attributes: {
        TableCellBlockKeys.colPosition: position,
        TableCellBlockKeys.rowPosition: i,
      },
    );
    node.insert(paragraphNode());
    final firstCellInRow = getCellNode(tableNode, 0, i);
    if (firstCellInRow?.attributes
            .containsKey(TableCellBlockKeys.rowBackgroundColor) ??
        false) {
      node.updateAttributes({
        TableCellBlockKeys.rowBackgroundColor:
            firstCellInRow!.attributes[TableCellBlockKeys.rowBackgroundColor],
      });
    }

    cellNodes.add(newCellNode(tableNode, node));
  }

  late Path insertPath;
  if (position == 0) {
    insertPath = getCellNode(tableNode, 0, 0)!.path;
  } else {
    insertPath = getCellNode(tableNode, position - 1, rowsLen - 1)!.path.next;
  }
  transaction.insertNodes(insertPath, cellNodes);
  transaction.updateNode(tableNode, {TableBlockKeys.colsLen: colsLen + 1});

  _applyKeepingCaret(
    transaction,
    tableNode,
    editorState,
    rowsLen,
    rowsLen,
    (c, r) => (c: c >= position ? c + 1 : c, r: r, reset: false),
  );
}

void _addRow(Node tableNode, int position, EditorState editorState) {
  assert(position >= 0);

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen];
  final int colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  // One transaction for the whole edit: one apply, one undo step, and no
  // half-built table is ever visible or synced.
  final transaction = editorState.transaction;

  for (var i = 0; i < colsLen; i++) {
    final firstCellInCol = getCellNode(tableNode, i, 0);
    final colBgColor =
        firstCellInCol?.attributes[TableCellBlockKeys.colBackgroundColor];
    final containsColBgColor = colBgColor != null;

    final node = Node(
      type: TableCellBlockKeys.type,
      attributes: {
        TableCellBlockKeys.colPosition: i,
        TableCellBlockKeys.rowPosition: position,
        if (containsColBgColor)
          TableCellBlockKeys.colBackgroundColor: colBgColor,
      },
      children: [paragraphNode()],
    );

    final anchor = position == 0
        ? firstCellInCol
        : getCellNode(tableNode, i, position - 1);
    if (anchor == null) {
      AppFlowyEditorLog.editor.debug('unable to insert row');
      return;
    }
    final insertPath = position == 0 ? anchor.path : anchor.path.next;

    for (var j = position; j < rowsLen; j++) {
      final cellNode = getCellNode(tableNode, i, j);
      if (cellNode == null) {
        AppFlowyEditorLog.editor.debug('unable to insert row');
        return;
      }
      transaction.updateNode(cellNode, {TableCellBlockKeys.rowPosition: j + 1});
    }

    transaction.insertNode(insertPath, node);
  }

  transaction.updateNode(tableNode, {TableBlockKeys.rowsLen: rowsLen + 1});

  _applyKeepingCaret(
    transaction,
    tableNode,
    editorState,
    rowsLen,
    rowsLen + 1,
    (c, r) => (c: c, r: r >= position ? r + 1 : r, reset: false),
  );
}

void _deleteCol(Node tableNode, int col, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (colsLen == 1) {
    if (editorState.document.root.children.length == 1) {
      final emptyParagraph = paragraphNode();
      transaction.insertNode(tableNode.path, emptyParagraph);
    }
    // Not disposed: undo puts this very node back.
    transaction.deleteNode(tableNode);
    editorState.apply(transaction, withUpdateSelection: false);
    return;
  }

  _updateCellPositions(
      transaction, tableNode, col + 1, 0, -1, 0);
  transaction.deleteNodes([
    for (var i = 0; i < rowsLen; i++) getCellNode(tableNode, col, i)!,
  ]);
  transaction.updateNode(tableNode, {
    TableBlockKeys.colsLen: colsLen - 1,
    if (col == 0 && tableNode.attributes[TableBlockKeys.headerCol] == true)
      TableBlockKeys.headerCol: false,
  });

  _applyKeepingCaret(
    transaction,
    tableNode,
    editorState,
    rowsLen,
    rowsLen,
    (c, r) => _deleteMap(col, c, r, colsLen, true),
  );
}

void _deleteRow(Node tableNode, int row, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (rowsLen == 1) {
    if (editorState.document.root.children.length == 1) {
      final emptyParagraph = paragraphNode();
      transaction.insertNode(tableNode.path, emptyParagraph);
    }
    // Not disposed: undo puts this very node back.
    transaction.deleteNode(tableNode);
    editorState.apply(transaction, withUpdateSelection: false);
    return;
  }

  _updateCellPositions(transaction, tableNode, 0, row + 1, 0, -1);
  transaction.deleteNodes([
    for (var i = 0; i < colsLen; i++) getCellNode(tableNode, i, row)!,
  ]);
  transaction.updateNode(tableNode, {
    TableBlockKeys.rowsLen: rowsLen - 1,
    if (row == 0 && tableNode.attributes[TableBlockKeys.headerRow] == true)
      TableBlockKeys.headerRow: false,
  });

  _applyKeepingCaret(
    transaction,
    tableNode,
    editorState,
    rowsLen,
    rowsLen - 1,
    (c, r) => _deleteMap(row, c, r, rowsLen, false),
  );
}

void _duplicateCol(Node tableNode, int col, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];
  List<Node> nodes = [];
  for (var i = 0; i < rowsLen; i++) {
    final node = getCellNode(tableNode, col, i)!;
    nodes.add(
      node.copyWith(
        attributes: {
          ...node.attributes,
          TableCellBlockKeys.colPosition: col + 1,
          TableCellBlockKeys.rowPosition: i,
        },
      ),
    );
  }
  _updateCellPositions(transaction, tableNode, col + 1, 0, 1, 0);
  transaction.insertNodes(
    getCellNode(tableNode, col, rowsLen - 1)!.path.next,
    nodes,
  );

  transaction.updateNode(tableNode, {TableBlockKeys.colsLen: colsLen + 1});

  _applyKeepingCaret(
    transaction,
    tableNode,
    editorState,
    rowsLen,
    rowsLen,
    (c, r) => (c: c > col ? c + 1 : c, r: r, reset: false),
  );
}

void _duplicateRow(Node tableNode, int row, EditorState editorState) {
  final transaction = editorState.transaction;
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  for (var i = 0; i < colsLen; i++) {
    for (var j = row + 1; j < rowsLen; j++) {
      transaction.updateNode(getCellNode(tableNode, i, j)!, {
        TableCellBlockKeys.colPosition: i,
        TableCellBlockKeys.rowPosition: j + 1,
      });
    }
    final node = getCellNode(tableNode, i, row)!;
    transaction.insertNode(
      node.path.next,
      node.copyWith(
        attributes: {
          ...node.attributes,
          TableCellBlockKeys.rowPosition: row + 1,
          TableCellBlockKeys.colPosition: i,
        },
      ),
    );
  }

  transaction.updateNode(tableNode, {TableBlockKeys.rowsLen: rowsLen + 1});

  _applyKeepingCaret(
    transaction,
    tableNode,
    editorState,
    rowsLen,
    rowsLen + 1,
    (c, r) => (c: c, r: r > row ? r + 1 : r, reset: false),
  );
}

void _setColBgColor(
  Node tableNode,
  int col,
  EditorState editorState,
  String? color,
) {
  final transaction = editorState.transaction;

  final rowslen = tableNode.attributes[TableBlockKeys.rowsLen];
  for (var i = 0; i < rowslen; i++) {
    final node = getCellNode(tableNode, col, i)!;
    transaction.updateNode(
      node,
      {
        TableCellBlockKeys.colBackgroundColor: color,
        if (node.attributes[TableCellBlockKeys.cellBackgroundColor] != null)
          TableCellBlockKeys.cellBackgroundColor: null,
      },
    );
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _setRowBgColor(
  Node tableNode,
  int row,
  EditorState editorState,
  String? color,
) {
  final transaction = editorState.transaction;

  final colsLen = tableNode.attributes[TableBlockKeys.colsLen];
  for (var i = 0; i < colsLen; i++) {
    final node = getCellNode(tableNode, i, row)!;
    transaction.updateNode(
      node,
      {
        TableCellBlockKeys.rowBackgroundColor: color,
        if (node.attributes[TableCellBlockKeys.cellBackgroundColor] != null)
          TableCellBlockKeys.cellBackgroundColor: null,
      },
    );
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _clearCol(
  Node tableNode,
  int col,
  EditorState editorState,
) {
  final transaction = editorState.transaction;

  final rowsLen = tableNode.attributes[TableBlockKeys.rowsLen];
  for (var i = 0; i < rowsLen; i++) {
    _clearCellContent(transaction, getCellNode(tableNode, col, i)!);
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _clearRow(
  Node tableNode,
  int row,
  EditorState editorState,
) {
  final transaction = editorState.transaction;

  final colsLen = tableNode.attributes[TableBlockKeys.colsLen];
  for (var i = 0; i < colsLen; i++) {
    _clearCellContent(transaction, getCellNode(tableNode, i, row)!);
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

dynamic newCellNode(Node tableNode, n) {
  final row = n.attributes[TableCellBlockKeys.rowPosition] as int;
  final col = n.attributes[TableCellBlockKeys.colPosition] as int;
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen];
  final int colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (!n.attributes.containsKey(TableCellBlockKeys.height)) {
    double nodeHeight = double.tryParse(
      tableNode.attributes[TableBlockKeys.rowDefaultHeight].toString(),
    )!;
    if (row < rowsLen) {
      nodeHeight = double.tryParse(
            getCellNode(tableNode, 0, row)!
                .attributes[TableCellBlockKeys.height]
                .toString(),
          ) ??
          nodeHeight;
    }
    n.updateAttributes({TableCellBlockKeys.height: nodeHeight});
  }

  if (!n.attributes.containsKey(TableCellBlockKeys.width)) {
    double nodeWidth = double.tryParse(
      tableNode.attributes[TableBlockKeys.colDefaultWidth].toString(),
    )!;
    if (col < colsLen) {
      nodeWidth = double.tryParse(
            getCellNode(tableNode, col, 0)!
                .attributes[TableCellBlockKeys.width]
                .toString(),
          ) ??
          nodeWidth;
    }
    n.updateAttributes({TableCellBlockKeys.width: nodeWidth});
  }

  return n;
}

/// Queues the position shifts on [transaction]; the caller applies it, so a row
/// or column edit stays ONE transaction.
void _updateCellPositions(
  Transaction transaction,
  Node tableNode,
  int fromCol,
  int fromRow,
  int addToCol,
  int addToRow,
) {
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  for (var i = fromCol; i < colsLen; i++) {
    for (var j = fromRow; j < rowsLen; j++) {
      transaction.updateNode(getCellNode(tableNode, i, j)!, {
        TableCellBlockKeys.colPosition: i + addToCol,
        TableCellBlockKeys.rowPosition: j + addToRow,
      });
    }
  }
}
