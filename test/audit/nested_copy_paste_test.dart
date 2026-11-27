// Copy of part of a nested row and paste into a row that has children (VENDOR_NOTES Patch 39 "open" list).
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Node _b(String t, [List<Node> kids = const []]) =>
    bulletedListNode(text: t, children: kids);

EditorState _state(List<Node> rows) {
  final s = EditorState.blank(withInitialText: false);
  s.apply(s.transaction..insertNodes([0], rows));
  s.undoManager.undoStack.last.seal();
  return s;
}

String _shape(Iterable<Node> nodes, [String pad = '']) => nodes
    .map((n) =>
        '$pad${n.delta?.toPlainText()}\n${_shape(n.children, '$pad  ')}')
    .join();

List<Node> _hello() => [
      _b('Hello World', [_b('k1'), _b('k2')]),
    ];

void main() {
  test('1 part of a parent row copies only that text, not its children', () {
    final s = _state([
      _b('Alpha', [_b('B'), _b('C')]),
    ]);
    final out = s.getSelectedNodes(
      selection: Selection(
        start: Position(path: [0], offset: 1),
        end: Position(path: [0], offset: 4),
      ),
    );
    expect(_shape(out), 'lph\n');
  });

  test('2 parent start to the middle of a child: later siblings absent', () {
    final s = _state([
      _b('Alpha', [_b('Bravo'), _b('Charlie')]),
    ]);
    final out = s.getSelectedNodes(
      selection: Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [0, 0], offset: 2),
      ),
    );
    expect(_shape(out), 'Alpha\n  Br\n');
  });

  test('3 nested rows then a later top-level row keep relative depth', () {
    final s = _state([
      _b('A', [
        _b('B', [_b('B2')]),
        _b('C'),
      ]),
      _b('X'),
    ]);
    final out = s.getSelectedNodes(
      selection: Selection(
        start: Position(path: [0, 0], offset: 0),
        end: Position(path: [1], offset: 1),
      ),
    );
    expect(_shape(out), 'B\n  B2\nC\nX\n');
  });

  test('4 multi-line paste into a row with children: caret and children',
      () async {
    final s = _state(_hello());
    s.selection = Selection.collapsed(Position(path: [0], offset: 5));
    await s.pasteMultiLineNodes(
      [paragraphNode(text: 'one'), paragraphNode(text: 'two')],
    );
    expect(
      s.document.root.children.map((n) => n.delta!.toPlainText()),
      ['Helloone', 'two World'],
    );
    expect(_shape(s.document.root.children[1].children), 'k1\nk2\n');
    expect(s.selection!.end.path, [1]);
    expect(s.selection!.end.offset, 3);
  });

  test('5 single pasted row with children into a paragraph keeps them',
      () async {
    final s = _state([paragraphNode(text: 'abc')]);
    s.selection = Selection.collapsed(Position(path: [0], offset: 3));
    await s.pasteSingleLineNode(_b('X', [_b('c1')]));
    expect(_shape(s.document.root.children), 'abcX\nc1\n');
  });

  test('6 undo-all after a nested paste restores the exact start', () async {
    final s = _state(_hello());
    final base = s.undoManager.undoStack.toList().length;
    s.selection = Selection.collapsed(Position(path: [0], offset: 5));
    await s.pasteMultiLineNodes(
      [paragraphNode(text: 'one'), paragraphNode(text: 'two')],
    );
    var guard = 0;
    while (s.undoManager.undoStack.toList().length > base && guard++ < 20) {
      s.undoManager.undo();
    }
    expect(_shape(s.document.root.children), 'Hello World\n  k1\n  k2\n');
  });

  test('6b undo-all restores the document including block ids', () async {
    final s = _state(_hello());
    final start = s.document.toJson().toString();
    final base = s.undoManager.undoStack.toList().length;
    s.selection = Selection.collapsed(Position(path: [0], offset: 5));
    await s.pasteMultiLineNodes(
      [paragraphNode(text: 'one'), paragraphNode(text: 'two')],
    );
    var guard = 0;
    while (s.undoManager.undoStack.toList().length > base && guard++ < 20) {
      s.undoManager.undo();
    }
    expect(s.document.toJson().toString(), start);
  });

  test('7 cut of a nested selection: copy text matches what delete removes', () async {
    final s = _state([
      _b('Alpha', [_b('Bravo'), _b('Charlie')]),
    ]);
    final sel = Selection(
      start: Position(path: [0], offset: 1),
      end: Position(path: [0, 0], offset: 2),
    );
    final copied = _shape(s.getSelectedNodes(selection: sel));
    s.selection = sel;
    await s.deleteSelection(sel);
    expect(copied, 'lpha\n  Br\n');
    // deleteSelection (selection_commands.dart, other owner) leaves the merged row 'Aavo'; it also duplicates the child
    // 'Charlie' today, reported separately, so only the merged text is pinned here.
    expect(s.document.root.children.first.delta!.toPlainText(), 'Aavo');
  });

  test('8 pasted last row with children: text after the caret and old children follow its deepest row',
      () async {
    final s = _state(_hello());
    s.selection = Selection.collapsed(Position(path: [0], offset: 5));
    await s.pasteMultiLineNodes([
      paragraphNode(text: 'one'),
      paragraphNode(text: 'two', children: [paragraphNode(text: 'p1')]),
    ]);
    expect(
      _shape(s.document.root.children),
      'Helloone\ntwo\n  p1 World\n    k1\n    k2\n',
    );
    expect(s.selection!.end.path, [1, 0]);
    expect(s.selection!.end.offset, 2);
  });
}
