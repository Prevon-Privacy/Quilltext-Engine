import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// 2 columns x 3 rows. `cols[c][r]`.
EditorState _state({bool withNeighbours = true}) {
  final table = TableNode.fromList([
    ['a1', 'a2', 'a3'],
    ['b1', 'b2', 'b3'],
  ]);
  final doc = Document.blank();
  if (withNeighbours) {
    doc.insert([0], [
      paragraphNode(text: 'before'),
      table.node,
      paragraphNode(text: 'after'),
    ]);
  } else {
    doc.insert([0], [table.node]);
  }
  return EditorState(document: doc);
}

Node _table(EditorState s) =>
    s.document.root.children.firstWhere((n) => n.type == TableBlockKeys.type);

void main() {
  group('table text', () {
    test('rows are row-major and a cell joins its blocks', () {
      final s = _state();
      final t = _table(s);
      expect(tableRowsText(t), [
        ['a1', 'b1'],
        ['a2', 'b2'],
        ['a3', 'b3'],
      ]);
      expect(tableHasNoText(t), isFalse);
    });

    test('tsv puts tabs between cells and newlines between rows', () {
      final t = _table(_state());
      expect(tableToTsv(t), 'a1\tb1\na2\tb2\na3\tb3');
    });

    test('markdown has a header, a rule, and escapes pipes', () {
      final tbl = TableNode.fromList([
        ['h', 'x|y'],
        ['', 'z'],
      ]);
      expect(
        tableToMarkdown(tbl.node),
        '| h |   |\n| --- | --- |\n| x\\|y | z |',
      );
    });
  });

  group('clear', () {
    test('clearing a column empties its cells and keeps the others', () {
      final s = _state();
      final t = _table(s);
      TableActions.clear(t, 0, s, TableDirection.col);
      expect(tableRowsText(_table(s)), [
        ['', 'b1'],
        ['', 'b2'],
        ['', 'b3'],
      ]);
      // Exactly one block per cell: the old text is gone, not pushed down.
      for (final cell in _table(s).children) {
        expect(cell.children.length, 1);
      }
    });

    test('clearing a row empties that row only', () {
      final s = _state();
      TableActions.clear(_table(s), 1, s, TableDirection.row);
      expect(tableRowsText(_table(s)), [
        ['a1', 'b1'],
        ['', ''],
        ['a3', 'b3'],
      ]);
    });

    test('clear table empties every cell and keeps the grid', () {
      final s = _state();
      TableActions.clearTable(_table(s), s);
      final t = _table(s);
      expect(tableHasNoText(t), isTrue);
      expect(t.children.length, 6);
      expect(t.attributes[TableBlockKeys.colsLen], 2);
      expect(t.attributes[TableBlockKeys.rowsLen], 3);
    });

    test('clear table is one undo step', () {
      final s = _state();
      TableActions.clearTable(_table(s), s);
      s.undoManager.undo();
      expect(tableRowsText(_table(s))[0], ['a1', 'b1']);
    });
  });

  group('delete table', () {
    test('removes the table and keeps the neighbours', () {
      final s = _state();
      TableActions.deleteTable(_table(s), s);
      final kids = s.document.root.children;
      expect(kids.map((n) => n.type), ['paragraph', 'paragraph']);
      expect(kids.map((n) => n.delta!.toPlainText()), ['before', 'after']);
      // Caret lands at the start of the block that followed the table.
      expect(s.selection, Selection.collapsed(Position(path: [1])));
    });

    test('a table that was the only block leaves one empty paragraph', () {
      final s = _state(withNeighbours: false);
      // Document.blank() already carries one paragraph; drop it.
      for (final n in s.document.root.children.toList()) {
        if (n.type != TableBlockKeys.type) {
          s.apply(s.transaction..deleteNode(n));
        }
      }
      TableActions.deleteTable(_table(s), s);
      final kids = s.document.root.children;
      expect(kids.length, 1);
      expect(kids.single.type, 'paragraph');
      expect(kids.single.delta!.toPlainText(), '');
    });

    test('delete table is one undo step', () {
      final s = _state();
      TableActions.deleteTable(_table(s), s);
      s.undoManager.undo();
      expect(_table(s).children.length, 6);
    });
  });
}
