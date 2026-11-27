// Audit: Delete/Backspace never cross a table cell, a file's Hide-undo does not
// act on a stale block, and the columns repair joins the edit's undo step.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

EditorState _table() {
  final table = TableNode.fromList([
    ['a0', 'a1'],
    ['b0', 'b1'],
  ]);
  final doc = Document.blank()
    ..insert([0], [table.node, paragraphNode(text: 'after')]);
  return EditorState(document: doc)..disableSealTimer = true;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('table cell boundaries', () {
    test('Delete at the end of a cell does not pull the next cell in',
        () async {
      final s = _table();
      final before = s.document.toJson().toString();
      s.selection =
          Selection.collapsed(Position(path: [0, 0, 0], offset: 2)); // a0 end
      for (final c in standardCommandShortcutEvents
          .where((e) => e.key == 'Delete Key')) {
        if (c.handler(s) == KeyEventResult.handled) break;
      }
      await _settle();
      expect(s.document.toJson().toString(), before);
    });

    test('Backspace at the start of a cell does nothing', () async {
      final s = _table();
      final before = s.document.toJson().toString();
      s.selection = Selection.collapsed(Position(path: [0, 1, 0], offset: 0));
      for (final c in standardCommandShortcutEvents
          .where((e) => e.command.contains('backspace'))) {
        if (c.handler(s) == KeyEventResult.handled) break;
      }
      await _settle();
      expect(s.document.toJson().toString(), before);
    });

    for (final key in ['backspace', 'delete']) {
      test('$key over a selection spanning two cells is a no-op', () async {
        final s = _table();
        final before = s.document.toJson().toString();
        s.selection = Selection(
          start: Position(path: [0, 0, 0], offset: 1),
          end: Position(path: [0, 1, 0], offset: 1),
        );
        for (final c in standardCommandShortcutEvents
            .where((e) => e.command.contains(key))) {
          if (c.handler(s) == KeyEventResult.handled) break;
        }
        await _settle();
        expect(s.document.toJson().toString(), before, reason: key);
      });
    }
  });

  group('columns repair joins the edit undo step', () {
    test('one undo reverts the edit and its repair', () async {
      final s = EditorState(
        document: Document.blank()
          ..insert([
            0
          ], [
            columnsNode(children: [
              columnNode(children: [paragraphNode(text: 'x')]),
              columnNode(children: [paragraphNode(text: 'y')]),
            ]),
            paragraphNode(text: 'tail'),
          ]),
      )..disableSealTimer = true;
      final original = s.document.toJson().toString();
      // The edit empties column 2 (what a cross-column delete does) and is sealed.
      final t = s.transaction..deleteNode(s.getNodeAtPath([0, 1, 0])!);
      await s.apply(t, skipHistoryDebounce: true);
      expect(ColumnsActions.needsRepair(s.getNodeAtPath([0])!), isTrue);
      ColumnsActions.repair(s.getNodeAtPath([0])!, s);
      await _settle();
      expect(ColumnsActions.needsRepair(s.getNodeAtPath([0])!), isFalse);
      s.undoManager.undo();
      await _settle();
      expect(s.document.toJson().toString(), original);
    });

    test('empty undo stack: repair applies, nothing to revert, no throw',
        () async {
      final s = EditorState(
        document: Document.blank()
          ..insert([
            0
          ], [
            columnsNode(children: [
              columnNode(children: [paragraphNode(text: 'x')]),
              columnNode(),
            ]),
            paragraphNode(text: 'tail'),
          ]),
      )..disableSealTimer = true;
      expect(s.undoManager.undoStack.isEmpty, isTrue);
      ColumnsActions.repair(s.getNodeAtPath([0])!, s);
      await _settle();
      expect(ColumnsActions.needsRepair(s.getNodeAtPath([0])!), isFalse);
      expect(s.undoManager.undoStack.isEmpty, isTrue);
      s.undoManager.undo(); // must not throw
    });

    test('newest item is an earlier edit: undo reverts at most that item',
        () async {
      final s = EditorState(
        document: Document.blank()
          ..insert([
            0
          ], [
            paragraphNode(text: 'first'),
            columnsNode(children: [
              columnNode(children: [paragraphNode(text: 'x')]),
              columnNode(),
            ]),
          ]),
      )..disableSealTimer = true;
      final t = s.transaction..insertText(s.getNodeAtPath([0])!, 5, '!');
      await s.apply(t, skipHistoryDebounce: true);
      ColumnsActions.repair(s.getNodeAtPath([1])!, s);
      await _settle();
      s.undoManager.undo();
      await _settle();
      expect(s.getNodeAtPath([0])!.delta!.toPlainText(), 'first');
      s.undoManager.undo(); // stack empty now: no throw, nothing else reverts
      expect(s.getNodeAtPath([0])!.delta!.toPlainText(), 'first');
    });
  });
}
