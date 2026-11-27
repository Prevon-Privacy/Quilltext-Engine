// Audit of selection and word keys: delete over a range ending in a nested row, Ctrl/Alt+Backspace on
// spaces, word-jump at block edges, Shift+Left/Right through nested rows, arrows on an image or divider.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Node _b(String t, [List<Node> kids = const []]) =>
    bulletedListNode(text: t, children: kids);

EditorState _doc(List<Node> top) =>
    EditorState(document: Document.blank()..insert([0], top))
      ..disableSealTimer = true;

List<String> _read(EditorState s) {
  final out = <String>[];
  void walk(Node x, int d) {
    out.add('${x.delta?.toPlainText() ?? x.type}@$d');
    x.children.forEach((c) => walk(c, d + 1));
  }

  s.document.root.children.forEach((x) => walk(x, 0));
  return out;
}

Future<EditorState> _pump(WidgetTester tester, List<Node> top) async {
  final s = _doc(top);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AppFlowyEditor(editorState: s)),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

void main() {
  test('deleteSelection ending inside a nested row keeps the unselected sibling',
      () async {
    final s = _doc([
      paragraphNode(text: 'start'),
      _b('B', [_b('B1 tail'), _b('B2 keep')]),
    ]);
    final before = _read(s);
    await s.deleteSelection(
      Selection(
        start: Position(path: [0], offset: 2),
        end: Position(path: [1, 0], offset: 3),
      ),
    );
    expect(_read(s), ['sttail@0', 'B2 keep@1']);
    expect(s.selection, Selection.collapsed(Position(path: [0], offset: 2)));
    s.undoManager.undo();
    expect(_read(s), before);
  });

  test('range ending two levels deep keeps B12 and B2 in reading order', () async {
    final s = _doc([
      paragraphNode(text: 'start'),
      _b('B', [
        _b('B1', [_b('B11 tail'), _b('B12 keep')]),
        _b('B2 keep'),
      ]),
    ]);
    final before = _read(s);
    await s.deleteSelection(
      Selection(
        start: Position(path: [0], offset: 2),
        end: Position(path: [1, 0, 0], offset: 4),
      ),
    );
    expect(_read(s), ['sttail@0', 'B12 keep@1', 'B2 keep@1']);
    s.undoManager.undo();
    expect(_read(s), before);
  });

  for (final backward in [false, true]) {
    test('first selected row is the parent of the last: no duplicate sibling '
        '(${backward ? 'backward' : 'forward'})', () async {
      final s = _doc([
        _b('Alpha', [_b('Bravo'), _b('Charlie')]),
      ]);
      final before = _read(s);
      final a = Position(path: [0], offset: 1);
      final z = Position(path: [0, 0], offset: 2);
      await s.deleteSelection(
        backward ? Selection(start: z, end: a) : Selection(start: a, end: z),
      );
      expect(_read(s), ['Aavo@0', 'Charlie@1']);
      s.undoManager.undo();
      expect(_read(s), before);
    });
  }

  test('backward selection behaves like the forward one', () async {
    final s = _doc([
      paragraphNode(text: 'start'),
      _b('B', [_b('B1 tail'), _b('B2 keep')]),
    ]);
    await s.deleteSelection(
      Selection(
        start: Position(path: [1, 0], offset: 3),
        end: Position(path: [0], offset: 2),
      ),
    );
    expect(_read(s), ['sttail@0', 'B2 keep@1']);
  });

  testWidgets('Ctrl+Backspace on leading spaces deletes only the spaces',
      (tester) async {
    final s = await _pump(
        tester, [paragraphNode(text: 'prev'), paragraphNode(text: '   ')]);
    s.selection = Selection.collapsed(Position(path: [1], offset: 3));
    await tester.pump();
    deleteLeftWordCommand.execute(s);
    await tester.pump();
    expect(_read(s), ['prev@0', '@0']);
  });

  testWidgets('Ctrl+Delete on trailing spaces deletes only the spaces',
      (tester) async {
    final s = await _pump(
        tester, [paragraphNode(text: '   '), paragraphNode(text: 'next')]);
    s.selection = Selection.collapsed(Position(path: [0], offset: 1));
    await tester.pump();
    deleteRightWordCommand.execute(s);
    await tester.pump();
    expect(_read(s), [' @0', 'next@0']);
  });

  testWidgets('word-jump at block edges moves to the neighbour block',
      (tester) async {
    final s = await _pump(tester,
        [paragraphNode(text: 'one two'), paragraphNode(text: 'three')]);
    s.selection = Selection.collapsed(Position(path: [1], offset: 0));
    await tester.pump();
    moveCursorToLeftWordCommand.execute(s);
    expect(s.selection!.start.path, [0]);
    s.selection = Selection.collapsed(Position(path: [0], offset: 7));
    await tester.pump();
    moveCursorToRightWordCommand.execute(s);
    expect(s.selection!.start.path, [1]);
  });

  test('Shift+Right goes into the child and out of the last child', () {
    final s = _doc([
      _b('A', [_b('A1')]),
      paragraphNode(text: 'next'),
    ]);
    s.selection = Selection.collapsed(Position(path: [0], offset: 1));
    moveCursorRightSelectCommand.execute(s);
    expect(s.selection!.end, Position(path: [0, 0], offset: 0));
    s.selection = Selection.collapsed(Position(path: [0, 0], offset: 2));
    moveCursorRightSelectCommand.execute(s);
    expect(s.selection!.end, Position(path: [1], offset: 0));
  });

  test('Shift+Left goes out of a child into its parent and into the last child',
      () {
    final s = _doc([
      _b('A', [_b('A1')]),
      paragraphNode(text: 'next'),
    ]);
    s.selection = Selection.collapsed(Position(path: [1], offset: 0));
    moveCursorLeftSelectCommand.execute(s);
    expect(s.selection!.end, Position(path: [0, 0], offset: 2));
    s.selection = Selection.collapsed(Position(path: [0, 0], offset: 0));
    moveCursorLeftSelectCommand.execute(s);
    expect(s.selection!.end, Position(path: [0], offset: 1));
  });

  test('arrows on a divider do not throw', () {
    final s = _doc([
      paragraphNode(text: 'a'),
      dividerNode(),
      paragraphNode(text: 'b'),
    ]);
    s.selection = Selection.collapsed(Position(path: [1], offset: 0));
    expect(() => moveCursorLeftCommand.execute(s), returnsNormally);
    s.selection = Selection.collapsed(Position(path: [1], offset: 0));
    expect(() => moveCursorRightCommand.execute(s), returnsNormally);
    expect(() => moveCursorToBeginCommand.execute(s), returnsNormally);
  });
}
