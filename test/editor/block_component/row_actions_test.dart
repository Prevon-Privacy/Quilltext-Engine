import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

EditorState _state(List<Node> nodes, {bool guards = false}) {
  final s = EditorState(document: Document.blank()..insert([0], nodes));
  if (guards) s.documentRules = const [SurroundNonTextBlocksRule()];
  return s;
}

List<String?> _texts(EditorState s, [Node? of]) => [
      for (final n in (of ?? s.document.root).children)
        n.delta?.toPlainText() ?? '<${n.type}>',
    ];

Selection _at(List<int> path, [int offset = 0]) =>
    Selection.collapsed(Position(path: path, offset: offset));

/// The history seal timer (50 ms) must not outlive the test.
Future<void> _flush(WidgetTester t) =>
    t.pump(const Duration(milliseconds: 100));

void main() {
  group('move', () {
    testWidgets('one row down and up, caret follows, ends refuse',
        (tester) async {
      final s = _state([
        paragraphNode(text: 'a'),
        paragraphNode(text: 'b'),
        paragraphNode(text: 'c'),
      ]);
      s.selection = _at([0], 1);
      expect(canMoveRows(s, up: true), isFalse);
      expect(moveRows(s, up: true), isFalse);
      expect(moveRows(s, up: false), isTrue);
      expect(_texts(s), ['b', 'a', 'c']);
      expect(s.selection, _at([1], 1));
      expect(moveRows(s, up: false), isTrue);
      expect(moveRows(s, up: false), isFalse);
      expect(_texts(s), ['b', 'c', 'a']);
      expect(s.selection, _at([2], 1));
      expect(moveRows(s, up: true), isTrue);
      expect(_texts(s), ['b', 'a', 'c']);
      await _flush(tester);
    });

    testWidgets('a selected group moves together and keeps its range',
        (tester) async {
      final s = _state([
        paragraphNode(text: 'a'),
        paragraphNode(text: 'b'),
        paragraphNode(text: 'c'),
        paragraphNode(text: 'd'),
      ]);
      s.selection = Selection(
        start: Position(path: [1], offset: 0),
        end: Position(path: [2], offset: 1),
      );
      expect(moveRows(s, up: true), isTrue);
      expect(_texts(s), ['b', 'c', 'a', 'd']);
      expect(
        s.selection,
        Selection(
          start: Position(path: [0], offset: 0),
          end: Position(path: [1], offset: 1),
        ),
      );
      expect(moveRows(s, up: false), isTrue);
      expect(moveRows(s, up: false), isTrue);
      expect(moveRows(s, up: false), isFalse);
      expect(_texts(s), ['a', 'd', 'b', 'c']);
      await _flush(tester);
    });

    testWidgets(
        'a parent takes its children along; children stay among '
        'their own siblings', (tester) async {
      final s = _state([
        bulletedListNode(text: 'a', children: [
          bulletedListNode(text: 'a1'),
          bulletedListNode(text: 'a2'),
        ]),
        bulletedListNode(text: 'b'),
      ]);
      s.selection = _at([0, 0], 1);
      expect(canMoveRows(s, up: true), isFalse, reason: 'first child');
      expect(moveRows(s, up: false), isTrue);
      expect(_texts(s, s.getNodeAtPath([0])), ['a2', 'a1']);
      expect(s.selection, _at([0, 1], 1));

      s.selection = _at([0], 0);
      expect(moveRows(s, up: false), isTrue);
      expect(_texts(s), ['b', 'a']);
      expect(_texts(s, s.getNodeAtPath([1])), ['a2', 'a1']);
      await _flush(tester);
    });

    testWidgets('a backward selection (end above start) works the same',
        (tester) async {
      final s = _state([
        paragraphNode(text: 'a'),
        paragraphNode(text: 'b'),
        paragraphNode(text: 'c'),
        paragraphNode(text: 'd'),
      ]);
      s.selection = Selection(
        start: Position(path: [2], offset: 1),
        end: Position(path: [1], offset: 0),
      );
      expect(selectedRowGroup(s)!.nodes.length, 2);
      expect(moveRows(s, up: false), isTrue);
      expect(_texts(s), ['a', 'd', 'b', 'c']);
      expect(deleteRows(s), 2);
      expect(_texts(s), ['a', 'd']);
      await _flush(tester);
    });

    testWidgets('a selection over different parents has no group',
        (tester) async {
      final s = _state([
        bulletedListNode(text: 'a', children: [bulletedListNode(text: 'a1')]),
        bulletedListNode(text: 'b'),
      ]);
      s.selection = Selection(
        start: Position(path: [0, 0], offset: 0),
        end: Position(path: [1], offset: 1),
      );
      expect(selectedRowGroup(s), isNull);
      expect(moveRows(s, up: false), isFalse);
      expect(deleteRows(s), 0);
      await _flush(tester);
    });

    testWidgets('one undo step per move', (tester) async {
      final s = _state([
        paragraphNode(text: 'a'),
        paragraphNode(text: 'b'),
        paragraphNode(text: 'c'),
      ]);
      s.selection = _at([0]);
      moveRows(s, up: false);
      moveRows(s, up: false);
      expect(_texts(s), ['b', 'c', 'a']);
      s.undoManager.undo();
      expect(_texts(s), ['b', 'a', 'c']);
      s.undoManager.undo();
      expect(_texts(s), ['a', 'b', 'c']);
      await _flush(tester);
    });

    testWidgets('dividers keep their guard paragraphs through a move',
        (tester) async {
      final s = _state([
        paragraphNode(text: 'a'),
        dividerNode(),
        paragraphNode(text: 'b'),
        paragraphNode(text: 'c'),
      ], guards: true);
      s.selection = _at([3]);
      expect(moveRows(s, up: true), isTrue);
      expect(moveRows(s, up: true), isTrue);
      // Never two non-text blocks in a row, never one at an end.
      final types = [for (final n in s.document.root.children) n.delta != null];
      expect(types.first, isTrue);
      expect(types.last, isTrue);
      for (var i = 1; i < types.length; i++) {
        expect(types[i - 1] || types[i], isTrue, reason: '$types');
      }
      await _flush(tester);
    });
  });

  group('duplicate', () {
    testWidgets('copies the row below, children included, caret on the copy',
        (tester) async {
      final s = _state([
        bulletedListNode(text: 'a', children: [bulletedListNode(text: 'a1')]),
        paragraphNode(text: 'z'),
      ]);
      s.selection = _at([0], 1);
      expect(duplicateRows(s), isTrue);
      expect(_texts(s), ['a', 'a', 'z']);
      expect(_texts(s, s.getNodeAtPath([1])), ['a1']);
      expect(s.selection, _at([1], 1));
      expect(identical(s.getNodeAtPath([0]), s.getNodeAtPath([1])), isFalse);
      s.undoManager.undo();
      expect(_texts(s), ['a', 'z']);
      await _flush(tester);
    });

    testWidgets('a group is copied as a group', (tester) async {
      final s = _state([
        paragraphNode(text: 'a'),
        paragraphNode(text: 'b'),
        paragraphNode(text: 'c'),
      ]);
      s.selection = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [1], offset: 1),
      );
      expect(duplicateRows(s), isTrue);
      expect(_texts(s), ['a', 'b', 'a', 'b', 'c']);
      expect(
        s.selection,
        Selection(
          start: Position(path: [2], offset: 0),
          end: Position(path: [3], offset: 1),
        ),
      );
      await _flush(tester);
    });

    testWidgets('the app can veto blocks that must not be copied',
        (tester) async {
      final s = _state([
        paragraphNode(text: 'a'),
        Node(type: 'sketch'),
        paragraphNode(text: 'b'),
      ]);
      s.selection = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [1], offset: 0),
      );
      bool notSketch(Node n) => n.type != 'sketch';
      // 'sketch' has no grip, so the group itself is refused either way; a
      // grip-bearing block that the app vetoes is refused by the predicate.
      expect(canDuplicateRows(s, canDuplicate: notSketch), isFalse);
      s.selection = _at([0]);
      expect(canDuplicateRows(s, canDuplicate: (n) => n.type != 'paragraph'),
          isFalse);
      expect(duplicateRows(s, canDuplicate: (n) => false), isFalse);
      expect(_texts(s), ['a', '<sketch>', 'b']);
      await _flush(tester);
    });

    testWidgets('a copied divider gets its guard paragraph, one undo restores',
        (tester) async {
      final s = _state([
        paragraphNode(text: 'a'),
        dividerNode(),
        paragraphNode(text: 'b'),
      ], guards: true);
      s.selection = Selection(
        start: Position(path: [1], offset: 0),
        end: Position(path: [1], offset: 0),
      );
      final before = _texts(s);
      expect(duplicateRows(s), isTrue);
      expect(
          s.document.root.children.where((n) => n.type == 'divider').length, 2);
      final kinds = [for (final n in s.document.root.children) n.delta != null];
      for (var i = 1; i < kinds.length; i++) {
        expect(kinds[i - 1] || kinds[i], isTrue, reason: '$kinds');
      }
      s.undoManager.undo();
      expect(_texts(s), before);
      await _flush(tester);
    });
  });

  group('delete', () {
    testWidgets('caret goes to the row that slid up, else the one above',
        (tester) async {
      final s = _state([
        paragraphNode(text: 'a'),
        paragraphNode(text: 'b'),
        paragraphNode(text: 'c'),
      ]);
      s.selection = _at([1]);
      expect(deleteRows(s), 1);
      expect(_texts(s), ['a', 'c']);
      expect(s.selection, _at([1]));
      expect(deleteRows(s), 1);
      expect(_texts(s), ['a']);
      expect(s.selection, _at([0], 1), reason: 'end of the row above');
      await _flush(tester);
    });

    testWidgets('the last row left is replaced by an empty paragraph',
        (tester) async {
      final s = _state([bulletedListNode(text: 'only')]);
      s.selection = _at([0], 2);
      expect(deleteRows(s), 1);
      expect(_texts(s), ['']);
      expect(s.getNodeAtPath([0])!.type, 'paragraph');
      expect(s.selection, _at([0]));
      await _flush(tester);
    });

    testWidgets('a group goes at once, children with it, one undo',
        (tester) async {
      final s = _state([
        paragraphNode(text: 'a'),
        bulletedListNode(text: 'b', children: [bulletedListNode(text: 'b1')]),
        paragraphNode(text: 'c'),
        paragraphNode(text: 'd'),
      ]);
      s.selection = Selection(
        start: Position(path: [1], offset: 0),
        end: Position(path: [2], offset: 1),
      );
      expect(deleteRows(s), 2);
      expect(_texts(s), ['a', 'd']);
      s.undoManager.undo();
      expect(_texts(s), ['a', 'b', 'c', 'd']);
      expect(_texts(s, s.getNodeAtPath([1])), ['b1']);
      await _flush(tester);
    });

    testWidgets('undoIfLatest only undoes the newest action', (tester) async {
      final s = _state([
        paragraphNode(text: 'a'),
        paragraphNode(text: 'b'),
        paragraphNode(text: 'c'),
      ]);
      s.selection = _at([1]);
      deleteRows(s);
      final item = latestHistoryItem(s);
      expect(item, isNotNull);
      // Something newer lands after the delete.
      s.selection = _at([0]);
      moveRows(s, up: false);
      expect(undoIfLatest(s, item), isFalse);
      expect(_texts(s), ['c', 'a']);
      s.undoManager.undo();
      final item2 = latestHistoryItem(s);
      expect(undoIfLatest(s, item2), isTrue);
      expect(_texts(s), ['a', 'b', 'c']);
      await _flush(tester);
    });
  });

  group('lift hidden children', () {
    testWidgets('a quote lets its nested rows out, in order, subtrees intact',
        (tester) async {
      final s = _state([
        bulletedListNode(text: 'a', children: [
          bulletedListNode(text: 'a1', children: [
            bulletedListNode(text: 'a1x'),
          ]),
          bulletedListNode(text: 'a2'),
        ]),
        paragraphNode(text: 'z'),
      ]);
      // What the Quote button does: same node, new type, children kept.
      final old = s.getNodeAtPath([0])!;
      final tx = s.transaction
        ..deleteNode(old)
        ..insertNode([0], old.copyWith(type: 'quote'));
      await s.apply(tx);
      expect(liftHiddenChildren(s, _at([0])), 2);
      expect(_texts(s), ['a', 'a1', 'a2', 'z']);
      expect(s.getNodeAtPath([0])!.children, isEmpty);
      expect(_texts(s, s.getNodeAtPath([1])), ['a1x']);
      await _flush(tester);
    });

    testWidgets('blocks that can draw children are left alone', (tester) async {
      final s = _state([
        bulletedListNode(text: 'a', children: [bulletedListNode(text: 'a1')]),
      ]);
      expect(liftHiddenChildren(s, _at([0])), 0);
      expect(_texts(s, s.getNodeAtPath([0])), ['a1']);
    });

    testWidgets('two converted rows lift independently', (tester) async {
      final s = _state([
        Node(
          type: 'quote',
          attributes: {'delta': (Delta()..insert('p')).toJson()},
          children: [paragraphNode(text: 'p1')],
        ),
        Node(
          type: 'quote',
          attributes: {'delta': (Delta()..insert('q')).toJson()},
          children: [paragraphNode(text: 'q1')],
        ),
      ]);
      final sel = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [1], offset: 0),
      );
      expect(liftHiddenChildren(s, sel), 2);
      expect(_texts(s), ['p', 'p1', 'q', 'q1']);
      s.undoManager.undo();
      expect(_texts(s), ['p', 'q']);
      await _flush(tester);
    });
  });

  group('slash conversion of an empty line keeps its nested rows', () {
    EditorState emptyWithKids(Node empty) =>
        _state([empty, paragraphNode(text: 'z')]);

    testWidgets('into a heading: the rows come out below it', (tester) async {
      final s = emptyWithKids(bulletedListNode(
        text: '',
        children: [
          bulletedListNode(
              text: 'k1', children: [bulletedListNode(text: 'k1x')]),
          bulletedListNode(text: 'k2'),
        ],
      ));
      s.selection = _at([0]);
      insertHeadingAfterSelection(s, 1);
      expect(s.getNodeAtPath([0])!.type, 'heading');
      expect(s.getNodeAtPath([0])!.children, isEmpty);
      expect(_texts(s), ['', 'k1', 'k2', 'z']);
      expect(_texts(s, s.getNodeAtPath([1])), ['k1x']);
      s.undoManager.undo();
      expect(s.getNodeAtPath([0])!.type, 'bulleted_list');
      expect(s.getNodeAtPath([0])!.children.length, 2);
      await _flush(tester);
    });

    testWidgets('into a bullet: the rows stay nested under it', (tester) async {
      final s = emptyWithKids(paragraphNode(
        text: '',
        children: [paragraphNode(text: 'k1'), paragraphNode(text: 'k2')],
      ));
      s.selection = _at([0]);
      insertBulletedListAfterSelection(s);
      expect(s.getNodeAtPath([0])!.type, 'bulleted_list');
      expect(_texts(s, s.getNodeAtPath([0])), ['k1', 'k2']);
      expect(_texts(s), ['', 'z']);
      await _flush(tester);
    });
  });

  testWidgets('no selection, no action', (tester) async {
    final s = _state([paragraphNode(text: 'a'), paragraphNode(text: 'b')]);
    expect(selectedRowGroup(s), isNull);
    expect(moveRows(s, up: false), isFalse);
    expect(duplicateRows(s), isFalse);
    expect(deleteRows(s), 0);
    await _flush(tester);
  });
}
