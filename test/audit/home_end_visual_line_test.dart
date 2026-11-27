// Home/End (and Shift+Home/End) go to the edge of the wrapped visual line, a repeat press goes to the block edge.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

final _text = List.generate(40, (i) => 'word$i').join(' ');

Future<EditorState> _pump(
  WidgetTester tester,
  String text, [
  List<Node>? nodes,
]) async {
  final s = EditorState(
    document: Document.blank()
      ..insert([0], nodes ?? [paragraphNode(text: text)]),
  )..disableSealTimer = true;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
              width: 300,
              child: AppFlowyEditor(
                editorState: s,
                editorStyle: EditorStyle.desktop(padding: EdgeInsets.zero),
              )),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

void _at(EditorState s, int offset) =>
    s.selection = Selection.collapsed(Position(path: [0], offset: offset));

void main() {
  testWidgets('Home and End land on visual line edges, then block edges',
      (tester) async {
    final s = await _pump(tester, _text);
    final mid = _text.length ~/ 2 + 5;
    _at(s, mid);

    moveCursorToBeginCommand.execute(s);

    await tester.pump();
    final home = s.selection!.end.offset;
    expect(home, greaterThan(0));
    expect(home, lessThan(mid));
    expect(_text[home - 1], ' ');

    moveCursorToBeginCommand.execute(s);

    await tester.pump();
    expect(s.selection!.end.offset, 0);

    _at(s, mid);
    moveCursorToEndCommand.execute(s);
    await tester.pump();
    final end = s.selection!.end.offset;
    expect(end, greaterThan(mid));
    expect(end, lessThan(_text.length));

    moveCursorToEndCommand.execute(s);

    await tester.pump();
    expect(s.selection!.end.offset, _text.length);
  });

  testWidgets('Shift+Home and Shift+End select to the visual line edge',
      (tester) async {
    final s = await _pump(tester, _text);
    final mid = _text.length ~/ 2 + 5;
    _at(s, mid);
    moveCursorBeginSelectCommand.execute(s);
    await tester.pump();
    expect(s.selection!.start.offset, mid);
    expect(s.selection!.end.offset, inInclusiveRange(1, mid - 1));

    _at(s, mid);
    moveCursorEndSelectCommand.execute(s);
    await tester.pump();
    expect(
        s.selection!.end.offset, inInclusiveRange(mid + 1, _text.length - 1));
  });

  testWidgets('one-line block keeps block edges', (tester) async {
    final s = await _pump(tester, 'short');
    _at(s, 2);
    moveCursorToBeginCommand.execute(s);
    await tester.pump();
    expect(s.selection!.end.offset, 0);
    _at(s, 2);
    moveCursorToEndCommand.execute(s);
    await tester.pump();
    expect(s.selection!.end.offset, 5);
  });

  testWidgets('Shift+Home / Shift+End extend an existing selection',
      (tester) async {
    final s = await _pump(tester, _text);
    final mid = _text.length ~/ 2 + 5;
    s.selection = Selection(
      start: Position(path: [0], offset: mid - 3),
      end: Position(path: [0], offset: mid),
    );
    moveCursorBeginSelectCommand.execute(s);
    await tester.pump();
    expect(s.selection!.start.offset, mid - 3);
    expect(s.selection!.end.offset, inInclusiveRange(1, mid - 1));
    final lineStart = s.selection!.end.offset;
    expect(_text[lineStart - 1], ' ');

    s.selection = Selection(
      start: Position(path: [0], offset: mid - 3),
      end: Position(path: [0], offset: mid),
    );
    moveCursorEndSelectCommand.execute(s);
    await tester.pump();
    expect(s.selection!.start.offset, mid - 3);
    expect(
        s.selection!.end.offset, inInclusiveRange(mid + 1, _text.length - 1));
  });

  testWidgets('first and last visual line: edges fall back to the block edge',
      (tester) async {
    final s = await _pump(tester, _text);
    _at(s, 5); // first line, Home is already the block start
    moveCursorToBeginCommand.execute(s);
    await tester.pump();
    expect(s.selection!.end.offset, 0);
    moveCursorToEndCommand.execute(s); // End of the FIRST line
    await tester.pump();
    final firstEnd = s.selection!.end.offset;
    expect(firstEnd, inInclusiveRange(6, _text.length - 1));

    _at(s, _text.length - 3); // last line
    moveCursorToEndCommand.execute(s);
    await tester.pump();
    expect(s.selection!.end.offset, _text.length);
    _at(s, _text.length - 3);
    moveCursorToBeginCommand.execute(s);
    await tester.pump();
    final lastStart = s.selection!.end.offset;
    expect(lastStart, greaterThan(firstEnd));
    expect(lastStart, lessThan(_text.length - 3));
  });

  testWidgets('End on a line ending in a space, End again does not jump a line',
      (tester) async {
    final s = await _pump(tester, _text);
    _at(s, 5);
    moveCursorToEndCommand.execute(s);
    await tester.pump();
    final first = s.selection!.end.offset;
    expect(_text[first], ' '); // before the wrap space
    moveCursorToEndCommand.execute(s);
    await tester.pump();
    // second press: block end (documented fallback), never the next line's end
    expect(s.selection!.end.offset, _text.length);
  });

  testWidgets('hard newline inside a block', (tester) async {
    const t = 'first line\nsecond line is here';
    final s = await _pump(tester, t);
    _at(s, 18);
    moveCursorToBeginCommand.execute(s);
    await tester.pump();
    expect(s.selection!.end.offset, 11); // after the newline
    _at(s, 4);
    moveCursorToEndCommand.execute(s);
    await tester.pump();
    expect(s.selection!.end.offset, inInclusiveRange(10, 11));
  });

  testWidgets('empty block does not throw and stays at 0', (tester) async {
    final s = await _pump(tester, '');
    _at(s, 0);
    moveCursorToBeginCommand.execute(s);
    moveCursorToEndCommand.execute(s);
    moveCursorBeginSelectCommand.execute(s);
    moveCursorEndSelectCommand.execute(s);
    await tester.pump();
    expect(s.selection!.end.offset, 0);
  });

  testWidgets('list item with children: End stays in the parent text',
      (tester) async {
    final s = await _pump(tester, '', [
      bulletedListNode(
        text: _text,
        children: [bulletedListNode(text: 'child one')],
      ),
    ]);
    _at(s, 5);
    moveCursorToEndCommand.execute(s);
    await tester.pump();
    expect(s.selection!.end.path, [0]);
    expect(s.selection!.end.offset, inInclusiveRange(6, _text.length - 1));
    moveCursorToEndCommand.execute(s);
    await tester.pump();
    expect(s.selection!.end.path, [0]);
    expect(s.selection!.end.offset, _text.length);
  });

  test('no render object (editor not laid out): block edges, no throw', () {
    final s = EditorState(
      document: Document.blank()..insert([0], [paragraphNode(text: _text)]),
    )..disableSealTimer = true;
    _at(s, 50);
    moveCursorToBeginCommand.execute(s);
    expect(s.selection!.end.offset, 0);
    _at(s, 50);
    moveCursorToEndCommand.execute(s);
    expect(s.selection!.end.offset, _text.length);
    _at(s, 50);
    // Shift+End needs a selectable: unchanged and no throw (as before).
    expect(() => moveCursorEndSelectCommand.execute(s), returnsNormally);
  });
}
