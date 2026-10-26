import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/table_block_component/table_drag.dart';

/// 3 columns x 3 rows. `cols[c][r]`: a1 a2 a3 / b1 b2 b3 / c1 c2 c3.
EditorState _state({bool header = false}) {
  final table = TableNode.fromList([
    ['a1', 'a2', 'a3'],
    ['b1', 'b2', 'b3'],
    ['c1', 'c2', 'c3'],
  ]);
  if (header) {
    table.node.updateAttributes({TableBlockKeys.headerRow: true});
  }
  final doc = Document.blank()
    ..insert([
      0
    ], [
      paragraphNode(text: 'before'),
      table.node,
      paragraphNode(text: 'after'),
    ]);
  return EditorState(document: doc);
}

Node _table(EditorState s) =>
    s.document.root.children.firstWhere((n) => n.type == TableBlockKeys.type);

List<List<String>> _rows(EditorState s) => tableRowsText(_table(s));

/// Children must stay column-major with matching positions: the Tab key and
/// "add row/column" rely on it.
void _expectCanonical(Node table) {
  final cols = table.attributes[TableBlockKeys.colsLen] as int;
  final rows = table.attributes[TableBlockKeys.rowsLen] as int;
  expect(table.children.length, cols * rows);
  for (var i = 0; i < table.children.length; i++) {
    final cell = table.children[i];
    expect(cell.attributes[TableCellBlockKeys.colPosition], i ~/ rows);
    expect(cell.attributes[TableCellBlockKeys.rowPosition], i % rows);
  }
}

void main() {
  group('move a column', () {
    test('first to last shifts the others left', () {
      final s = _state();
      final t = _table(s);
      expect(TableActions.move(t, 0, 2, s, TableDirection.col), isTrue);
      expect(_rows(s), [
        ['b1', 'c1', 'a1'],
        ['b2', 'c2', 'a2'],
        ['b3', 'c3', 'a3'],
      ]);
      _expectCanonical(_table(s));
    });

    test('last to first shifts the others right', () {
      final s = _state();
      TableActions.move(_table(s), 2, 0, s, TableDirection.col);
      expect(_rows(s).first, ['c1', 'a1', 'b1']);
      _expectCanonical(_table(s));
    });

    test('width and fill travel with the column', () {
      final s = _state();
      final t = _table(s);
      TableActions.setBgColor(t, 0, s, '0xFFFF0000', TableDirection.col);
      for (final r in [0, 1, 2]) {
        s.apply(
          s.transaction
            ..updateNode(getCellNode(t, 0, r)!, {TableCellBlockKeys.width: 99}),
        );
      }
      TableActions.move(_table(s), 0, 2, s, TableDirection.col);
      final moved = getCellNode(_table(s), 2, 1)!;
      expect(moved.attributes[TableCellBlockKeys.colBackgroundColor],
          '0xFFFF0000');
      expect(moved.attributes[TableCellBlockKeys.width], 99);
      expect(
        getCellNode(_table(s), 0, 1)!
            .attributes[TableCellBlockKeys.colBackgroundColor],
        isNull,
      );
    });

    test('is one undo step', () {
      final s = _state();
      TableActions.move(_table(s), 0, 2, s, TableDirection.col);
      s.undoManager.undo();
      expect(_rows(s).first, ['a1', 'b1', 'c1']);
      _expectCanonical(_table(s));
    });
  });

  group('move a row', () {
    test('first to last', () {
      final s = _state();
      expect(TableActions.move(_table(s), 0, 2, s, TableDirection.row), isTrue);
      expect(_rows(s), [
        ['a2', 'b2', 'c2'],
        ['a3', 'b3', 'c3'],
        ['a1', 'b1', 'c1'],
      ]);
      _expectCanonical(_table(s));
    });

    test('height and row fill travel with the row', () {
      final s = _state();
      final t = _table(s);
      TableActions.setBgColor(t, 2, s, '0xFF00FF00', TableDirection.row);
      TableActions.move(_table(s), 2, 0, s, TableDirection.row);
      for (var c = 0; c < 3; c++) {
        expect(
          getCellNode(_table(s), c, 0)!
              .attributes[TableCellBlockKeys.rowBackgroundColor],
          '0xFF00FF00',
        );
        expect(
          getCellNode(_table(s), c, 2)!
              .attributes[TableCellBlockKeys.rowBackgroundColor],
          isNull,
        );
      }
    });

    test('equal or out-of-range indexes change nothing', () {
      final s = _state();
      final t = _table(s);
      expect(TableActions.move(t, 1, 1, s, TableDirection.row), isFalse);
      expect(TableActions.move(t, 0, 3, s, TableDirection.row), isFalse);
      expect(TableActions.move(t, -1, 1, s, TableDirection.col), isFalse);
      expect(_rows(s).first, ['a1', 'b1', 'c1']);
    });

    test('the caret follows its cell', () {
      final s = _state();
      final t = _table(s);
      // Caret in a2 (col 0, row 1): children index 1.
      s.selection = Selection.collapsed(Position(path: [...t.path, 1, 0]));
      TableActions.move(t, 1, 0, s, TableDirection.row);
      final cell = TableActions.cellAtSelection(_table(s), s)!;
      expect(cell.attributes[TableCellBlockKeys.rowPosition], 0);
      expect(tableCellText(cell), 'a2');
    });
  });

  group('header row', () {
    test('it is pinned: nothing moves above it, it does not move', () {
      final s = _state(header: true);
      final t = _table(s);
      expect(TableActions.canMove(t, 0, TableDirection.row), isFalse);
      expect(TableActions.canMove(t, 1, TableDirection.row), isTrue);
      expect(TableActions.canMove(t, 0, TableDirection.col), isTrue);
      expect(TableActions.move(t, 0, 2, s, TableDirection.row), isFalse);
      expect(TableActions.move(t, 2, 0, s, TableDirection.row), isFalse);
      expect(TableActions.move(t, 2, 1, s, TableDirection.row), isTrue);
      expect(_rows(s)[0], ['a1', 'b1', 'c1']);
    });

    test('marking tints, unmarking removes only the default tint', () {
      final s = _state();
      final t = _table(s);
      TableActions.setHeader(t, s, TableDirection.row, true);
      expect(TableActions.isHeader(_table(s), TableDirection.row), isTrue);
      for (var c = 0; c < 3; c++) {
        expect(
          getCellNode(_table(s), c, 0)!
              .attributes[TableCellBlockKeys.rowBackgroundColor],
          kDefaultTableHeaderRowColor,
        );
      }
      TableActions.setHeader(_table(s), s, TableDirection.row, false);
      expect(TableActions.isHeader(_table(s), TableDirection.row), isFalse);
      expect(
        getCellNode(_table(s), 1, 0)!
            .attributes[TableCellBlockKeys.rowBackgroundColor],
        isNull,
      );
    });

    test('a color the person chose survives marking and unmarking', () {
      final s = _state();
      TableActions.setBgColor(
          _table(s), 0, s, '0xFF123456', TableDirection.row);
      TableActions.setHeader(_table(s), s, TableDirection.row, true);
      TableActions.setHeader(_table(s), s, TableDirection.row, false);
      expect(
        getCellNode(_table(s), 0, 0)!
            .attributes[TableCellBlockKeys.rowBackgroundColor],
        '0xFF123456',
      );
    });

    test('header column works the same way', () {
      final s = _state();
      TableActions.setHeader(_table(s), s, TableDirection.col, true);
      expect(TableActions.canMove(_table(s), 0, TableDirection.col), isFalse);
      expect(
          TableActions.move(_table(s), 0, 2, s, TableDirection.col), isFalse);
      expect(TableActions.move(_table(s), 2, 1, s, TableDirection.col), isTrue);
    });

    test('deleting the header row clears the flag', () {
      final s = _state(header: true);
      TableActions.delete(_table(s), 0, s, TableDirection.row);
      expect(TableActions.isHeader(_table(s), TableDirection.row), isFalse);
    });
  });

  group('cell fill', () {
    test('a cell fill sets one cell, a row fill then replaces it', () {
      final s = _state();
      final cell = getCellNode(_table(s), 1, 1)!;
      TableActions.setCellBgColor(cell, s, '0xFF0000FF');
      expect(
        getCellNode(_table(s), 1, 1)!
            .attributes[TableCellBlockKeys.cellBackgroundColor],
        '0xFF0000FF',
      );
      expect(
        getCellNode(_table(s), 0, 1)!
            .attributes[TableCellBlockKeys.cellBackgroundColor],
        isNull,
      );
      TableActions.setBgColor(
          _table(s), 1, s, '0xFF00FF00', TableDirection.row);
      expect(
        getCellNode(_table(s), 1, 1)!
            .attributes[TableCellBlockKeys.cellBackgroundColor],
        isNull,
      );
    });

    test('a cell fill travels when its row moves', () {
      final s = _state();
      TableActions.setCellBgColor(
        getCellNode(_table(s), 2, 0)!,
        s,
        '0xFF0000FF',
      );
      TableActions.move(_table(s), 0, 2, s, TableDirection.row);
      expect(
        getCellNode(_table(s), 2, 2)!
            .attributes[TableCellBlockKeys.cellBackgroundColor],
        '0xFF0000FF',
      );
    });
  });

  group('drag landing', () {
    const sizes = [100.0, 100.0, 100.0];

    test('no movement lands where it started', () {
      expect(tableDragTarget(sizes: sizes, from: 1, delta: 0), 1);
    });

    test('once the grabbed line centre crosses a boundary it lands there', () {
      expect(tableDragTarget(sizes: sizes, from: 0, delta: 51), 1);
      expect(tableDragTarget(sizes: sizes, from: 0, delta: 49), 0);
      expect(tableDragTarget(sizes: sizes, from: 2, delta: -101), 1);
    });

    test('is clamped to the table and to the header', () {
      expect(tableDragTarget(sizes: sizes, from: 0, delta: 900), 2);
      expect(tableDragTarget(sizes: sizes, from: 2, delta: -900), 0);
      expect(tableDragTarget(sizes: sizes, from: 2, delta: -900, first: 1), 1);
    });

    test('uneven sizes', () {
      expect(
        tableDragTarget(sizes: const [40, 200, 40], from: 0, delta: 100),
        1,
      );
    });
  });
}
