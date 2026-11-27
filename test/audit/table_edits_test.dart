// Audit of table row/column edits: the caret stays in its logical cell, a move keeps ids, each edit is
// ONE sound transaction, undo of deleting the last line works, and the cell keys respect multi-paragraph
// cells and non-text first children.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// 2 cols x 2 rows: a0 a1 / b0 b1 (`cols[c][r]`), table at [0], a paragraph after it.
EditorState _state() {
  final table = TableNode.fromList([
    ['a0', 'a1'],
    ['b0', 'b1'],
  ]);
  final doc = Document.blank()
    ..insert([0], [table.node, paragraphNode(text: 'after')]);
  return EditorState(document: doc)..disableSealTimer = true;
}

Node _table(EditorState s) => s.document.root.children.first;

String _caretText(EditorState s) =>
    s.getNodeAtPath(s.selection!.start.path)!.delta!.toPlainText();

void _caret(EditorState s, int col, int row, int rows, [int child = 0]) {
  s.selection = Selection.collapsed(
    Position(path: [0, col * rows + row, child], offset: 0),
  );
}

void _expectSound(Node table) {
  final cols = table.attributes[TableBlockKeys.colsLen] as int;
  final rows = table.attributes[TableBlockKeys.rowsLen] as int;
  expect(table.children.length, cols * rows, reason: 'cells != cols*rows');
  final seen = <String>{};
  for (final c in table.children) {
    final key = '${c.attributes[TableCellBlockKeys.colPosition]},'
        '${c.attributes[TableCellBlockKeys.rowPosition]}';
    expect(seen.add(key), isTrue, reason: 'duplicate cell $key');
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  main2();
  group('caret stays in its logical cell', () {
    test('add row below row 1', () async {
      final s = _state();
      _caret(s, 1, 0, 2);
      expect(_caretText(s), 'b0');
      TableActions.add(_table(s), 2, s, TableDirection.row);
      await _settle();
      expect(_caretText(s), 'b0');
    });

    test('add row above row 0 moves caret down with its cell', () async {
      final s = _state();
      _caret(s, 1, 1, 2);
      TableActions.add(_table(s), 0, s, TableDirection.row);
      await _settle();
      expect(_caretText(s), 'b1');
    });

    test('add column before column 0', () async {
      final s = _state();
      _caret(s, 0, 1, 2);
      TableActions.add(_table(s), 0, s, TableDirection.col);
      await _settle();
      expect(_caretText(s), 'a1');
    });

    test('delete a row above the caret', () async {
      final s = _state();
      _caret(s, 1, 1, 2);
      TableActions.delete(_table(s), 0, s, TableDirection.row);
      await _settle();
      expect(_caretText(s), 'b1');
    });

    test('delete the caret row: lands in the row that took its place', () async {
      final s = _state();
      _caret(s, 1, 0, 2);
      TableActions.delete(_table(s), 0, s, TableDirection.row);
      await _settle();
      expect(_caretText(s), 'b1');
    });

    test('delete the last column with the caret in it: previous column',
        () async {
      final s = _state();
      _caret(s, 1, 1, 2);
      TableActions.delete(_table(s), 1, s, TableDirection.col);
      await _settle();
      expect(_caretText(s), 'a1');
    });

    test('duplicate row keeps the caret in the original cell', () async {
      final s = _state();
      _caret(s, 1, 1, 2);
      TableActions.duplicate(_table(s), 0, s, TableDirection.row);
      await _settle();
      expect(_caretText(s), 'b1');
    });
  });

  test('moving a row or column keeps every cell and paragraph id', () async {
    for (final dir in TableDirection.values) {
      final s = _state();
      final before = [
        for (final c in _table(s).children) c.id,
        for (final c in _table(s).children) c.children.first.id,
      ]..sort();
      TableActions.move(_table(s), 0, 1, s, dir);
      await _settle();
      final after = [
        for (final c in _table(s).children) c.id,
        for (final c in _table(s).children) c.children.first.id,
      ]..sort();
      expect(after, before, reason: '$dir');
    }
  });

  group('each edit is ONE sound transaction', () {
    final edits = <String, void Function(EditorState)>{
      'add row': (s) => TableActions.add(_table(s), 1, s, TableDirection.row),
      'add col': (s) => TableActions.add(_table(s), 1, s, TableDirection.col),
      'delete row': (s) =>
          TableActions.delete(_table(s), 0, s, TableDirection.row),
      'delete col': (s) =>
          TableActions.delete(_table(s), 0, s, TableDirection.col),
      'duplicate row': (s) =>
          TableActions.duplicate(_table(s), 0, s, TableDirection.row),
      'duplicate col': (s) =>
          TableActions.duplicate(_table(s), 0, s, TableDirection.col),
    };
    edits.forEach((name, run) {
      test(name, () async {
        final s = _state();
        var applied = 0;
        final unsound = <String>[];
        final sub = s.transactionStream.listen((e) {
          if (e.$1 != TransactionTime.after) return;
          applied++;
          try {
            _expectSound(_table(s));
          } catch (e) {
            unsound.add('$e');
          }
        });
        run(s);
        await _settle();
        await sub.cancel();
        expect(unsound, isEmpty);
        expect(applied, 1);
        _expectSound(_table(s));
        // one undo step restores the original 2x2
        s.undoManager.undo();
        await _settle();
        expect(_table(s).children.length, 4);
        _expectSound(_table(s));
      });
    });
  });

  test('delete the only column, then undo: no disposed node', () async {
    final table = TableNode.fromList([
      ['x', 'y'],
    ]);
    final s = EditorState(
      document: Document.blank()
        ..insert([0], [table.node, paragraphNode(text: 'after')]),
    )..disableSealTimer = true;
    TableActions.delete(_table(s), 0, s, TableDirection.col);
    await _settle();
    expect(s.document.root.children.first.type, isNot(TableBlockKeys.type));
    s.undoManager.undo();
    await _settle();
    expect(_table(s).type, TableBlockKeys.type);
    // The restored table is live: an edit on it must not hit a disposed notifier.
    TableActions.add(_table(s), 1, s, TableDirection.row);
    await _settle();
    expect(_table(s).attributes[TableBlockKeys.rowsLen], 3);
  });

  group('cell keys', () {
    Future<EditorState> pump(
      WidgetTester tester, {
      Node? secondCellFirstChild,
      int cellIndex = 2,
    }) async {
      final table = TableNode.fromList([
        ['a0', 'a1'],
        ['b0', 'b1'],
      ]);
      table.node.children.first.insert(paragraphNode(text: 'a0 second'));
      if (secondCellFirstChild != null) {
        final cell = table.node.children[cellIndex];
        cell.children.first.unlink();
        cell.insert(secondCellFirstChild);
      }
      final s = EditorState(
        document: Document.blank()
          ..insert([0], [table.node, paragraphNode(text: 'after')]),
      )..disableSealTimer = true;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AppFlowyEditor(editorState: s))),
      );
      await tester.pumpAndSettle();
      return s;
    }

    testWidgets('Left at start of the 2nd paragraph stays in the cell',
        (tester) async {
      final s = await pump(tester);
      s.selection = Selection.collapsed(
        Position(path: [0, 0, 1], offset: 0),
      );
      final before = s.selection;
      expect(leftInTableCell.handler(s), KeyEventResult.ignored);
      await tester.pump();
      expect(s.selection, before);
    });

    testWidgets('Right at end of the 1st paragraph stays in the cell',
        (tester) async {
      final s = await pump(tester);
      s.selection = Selection.collapsed(
        Position(path: [0, 0, 0], offset: 2),
      );
      final before = s.selection;
      expect(rightInTableCell.handler(s), KeyEventResult.ignored);
      await tester.pump();
      expect(s.selection, before);
    });

    testWidgets('Tab into a cell whose first child is not text moves on',
        (tester) async {
      final s = await pump(
        tester,
        secondCellFirstChild: Node(type: 'divider'),
      );
      s.selection = Selection.collapsed(
        Position(path: [0, 1, 0], offset: 0),
      );
      // (col0,row1) -> Tab -> (col1,row1), index 3 (text); then divider cell is index 2.
      s.selection = Selection.collapsed(
        Position(path: [0, 0, 0], offset: 0),
      );
      tabInTableCell.handler(s);
      await tester.pump();
      expect(s.selection!.start.path, [0, 2, 0]);
    });

    testWidgets('Enter into a cell whose first child is not text moves on',
        (tester) async {
      final s = await pump(
        tester,
        secondCellFirstChild: Node(type: 'divider'),
        cellIndex: 1,
      );
      s.selection = Selection.collapsed(
        Position(path: [0, 0, 1], offset: 0),
      );
      enterInTableCell.handler(s);
      await tester.pump();
      expect(s.selection!.start.path, [0, 1, 0]);
    });

    testWidgets('Enter with a multi-node selection falls through',
        (tester) async {
      final s = await pump(tester);
      s.selection = Selection(
        start: Position(path: [0, 0, 0], offset: 0),
        end: Position(path: [0, 0, 1], offset: 3),
      );
      expect(enterInTableCell.handler(s), KeyEventResult.ignored);
    });
  });
}

EditorState _state3() {
  final table = TableNode.fromList([
    ['a0', 'a1', 'a2'],
    ['b0', 'b1', 'b2'],
    ['c0', 'c1', 'c2'],
  ]);
  return EditorState(
    document: Document.blank()
      ..insert([0], [table.node, paragraphNode(text: 'after')]),
  )..disableSealTimer = true;
}

void main2() {
  // Caret in a NON-first cell (col1,row1 = 'b1') of a 3x3 table.
  final cases = <String, (void Function(EditorState), String)>{
    'add row above caret row': (
      (s) => TableActions.add(_table(s), 1, s, TableDirection.row),
      'b1'
    ),
    'add row below caret row': (
      (s) => TableActions.add(_table(s), 2, s, TableDirection.row),
      'b1'
    ),
    'add column left of caret column': (
      (s) => TableActions.add(_table(s), 1, s, TableDirection.col),
      'b1'
    ),
    'add column right of caret column': (
      (s) => TableActions.add(_table(s), 2, s, TableDirection.col),
      'b1'
    ),
    'delete the caret row -> row that took its place': (
      (s) => TableActions.delete(_table(s), 1, s, TableDirection.row),
      'b2'
    ),
    'delete the caret column -> column that took its place': (
      (s) => TableActions.delete(_table(s), 1, s, TableDirection.col),
      'c1'
    ),
    'delete a row before the caret row': (
      (s) => TableActions.delete(_table(s), 0, s, TableDirection.row),
      'b1'
    ),
    'delete a column before the caret column': (
      (s) => TableActions.delete(_table(s), 0, s, TableDirection.col),
      'b1'
    ),
    'duplicate caret row': (
      (s) => TableActions.duplicate(_table(s), 1, s, TableDirection.row),
      'b1'
    ),
    'duplicate row before caret': (
      (s) => TableActions.duplicate(_table(s), 0, s, TableDirection.row),
      'b1'
    ),
    'duplicate caret column': (
      (s) => TableActions.duplicate(_table(s), 1, s, TableDirection.col),
      'b1'
    ),
    'duplicate column before caret': (
      (s) => TableActions.duplicate(_table(s), 0, s, TableDirection.col),
      'b1'
    ),
    'move caret row up': (
      (s) => TableActions.move(_table(s), 1, 0, s, TableDirection.row),
      'b1'
    ),
    'move caret row down': (
      (s) => TableActions.move(_table(s), 1, 2, s, TableDirection.row),
      'b1'
    ),
    'move caret column left': (
      (s) => TableActions.move(_table(s), 1, 0, s, TableDirection.col),
      'b1'
    ),
    'move caret column right': (
      (s) => TableActions.move(_table(s), 1, 2, s, TableDirection.col),
      'b1'
    ),
    'move another row across the caret row': (
      (s) => TableActions.move(_table(s), 0, 2, s, TableDirection.row),
      'b1'
    ),
  };
  group('3x3 caret mapping (caret in b1)', () {
    cases.forEach((name, c) {
      test(name, () async {
        final s = _state3();
        _caret(s, 1, 1, 3);
        expect(_caretText(s), 'b1');
        c.$1(s);
        await _settle();
        expect(_caretText(s), c.$2);
      });
    });
  });

  group('transactions per user-level edit', () {
    final edits = <String, void Function(EditorState)>{
      'clear row': (s) =>
          TableActions.clear(_table(s), 1, s, TableDirection.row),
      'clear column': (s) =>
          TableActions.clear(_table(s), 1, s, TableDirection.col),
      'move row': (s) =>
          TableActions.move(_table(s), 0, 2, s, TableDirection.row),
      'move column': (s) =>
          TableActions.move(_table(s), 0, 2, s, TableDirection.col),
      'header row on': (s) =>
          TableActions.setHeader(_table(s), s, TableDirection.row, true),
      'header col on': (s) =>
          TableActions.setHeader(_table(s), s, TableDirection.col, true),
      'row color': (s) => TableActions.setBgColor(
          _table(s), 1, s, '0xFF112233', TableDirection.row),
      'clear table': (s) => TableActions.clearTable(_table(s), s),
    };
    edits.forEach((name, run) {
      test(name, () async {
        final s = _state3();
        var applied = 0;
        final unsound = <String>[];
        final sub = s.transactionStream.listen((e) {
          if (e.$1 != TransactionTime.after) return;
          applied++;
          try {
            _expectSound(_table(s));
          } catch (e) {
            unsound.add('$e');
          }
        });
        run(s);
        await _settle();
        await sub.cancel();
        expect(unsound, isEmpty);
        expect(applied, 1);
      });
    });
  });

  for (final dir in TableDirection.values) {
    test('delete the last $dir, undo, then edit again: no errors', () async {
      final table = TableNode.fromList(
        dir == TableDirection.col
            ? [
                ['x', 'y'],
              ]
            : [
                ['x'],
                ['y'],
              ],
      );
      final s = EditorState(
        document: Document.blank()
          ..insert([0], [table.node, paragraphNode(text: 'after')]),
      )..disableSealTimer = true;
      TableActions.delete(_table(s), 0, s, dir);
      await _settle();
      s.undoManager.undo();
      await _settle();
      TableActions.add(_table(s), 1, s, TableDirection.row);
      await _settle();
      TableActions.add(_table(s), 1, s, TableDirection.col);
      await _settle();
      _expectSound(_table(s));
      s.undoManager.undo();
      s.undoManager.undo();
      await _settle();
      _expectSound(_table(s));
    });
  }

  group('redo restores the post-edit document', () {
    final edits = <String, void Function(EditorState)>{
      'add row': (s) => TableActions.add(_table(s), 1, s, TableDirection.row),
      'delete column': (s) =>
          TableActions.delete(_table(s), 1, s, TableDirection.col),
      'move row': (s) =>
          TableActions.move(_table(s), 0, 2, s, TableDirection.row),
    };
    edits.forEach((name, run) {
      test(name, () async {
        final s = _state3();
        run(s);
        await _settle();
        final post = s.document.toJson().toString();
        s.undoManager.undo();
        await _settle();
        s.undoManager.redo();
        await _settle();
        expect(s.document.toJson().toString(), post);
        _expectSound(_table(s));
      });
    });
  });
}
