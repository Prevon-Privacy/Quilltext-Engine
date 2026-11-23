// Other structural edits on nested rows: Enter on an empty nested row, backspace
// at the start of a nested row, multi-row outdent across levels, swipe outdent.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Node b(String t, [List<Node> k = const []]) => bulletedListNode(text: t, children: k);

Future<EditorState> pump(WidgetTester tester, List<Node> top) async {
  final s = EditorState(document: Document.blank()..insert([0], top));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AppFlowyEditor(
        editorState: s,
        blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
        commandShortcutEvents: standardCommandShortcutEvents,
        editorStyle: EditorStyle.desktop(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return s;
}

List<String> read(EditorState s) {
  final out = <String>[];
  void walk(Node x, int d) {
    out.add('${x.delta?.toPlainText()}@$d');
    x.children.forEach((c) => walk(c, d + 1));
  }
  s.document.root.children.forEach((x) => walk(x, 0));
  return out;
}

void main() {
  testWidgets('Enter on an EMPTY nested row with children and later siblings', (tester) async {
    final s = await pump(tester, [
      b('A', [b('B'), b('', [b('e1')]), b('C')]),
    ]);
    s.selection = Selection.collapsed(Position(path: [0, 1]));
    await insertNewLineInType(s, 'bulleted_list');
    await tester.pumpAndSettle();
    expect(read(s), ['A@0', 'B@1', '@0', 'e1@1', 'C@1']);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Backspace at start of a nested row with children', (tester) async {
    final s = await pump(tester, [
      b('A', [b('B'), b('X', [b('x1')]), b('C')]),
    ]);
    s.selection = Selection.collapsed(Position(path: [0, 1], offset: 0));
    backspaceCommand.execute(s);
    await tester.pumpAndSettle();
    expect(read(s), ['A@0', 'BX@1', 'x1@2', 'C@1']);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('multi-row selection parent+child outdent', (tester) async {
    final s = await pump(tester, [
      b('A', [b('B', [b('b1')]), b('C')]),
    ]);
    s.selection = Selection(
        start: Position(path: [0, 0], offset: 0), end: Position(path: [0, 0, 0], offset: 1));
    outdentCommand.execute(s);
    await tester.pumpAndSettle();
    expect(read(s), ['A@0', 'B@0', 'b1@1', 'C@1']);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('swipe outdent (mobile) of a row with children and later siblings', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final s = await pump(tester, [
        b('A', [b('B', [b('b1')]), b('C')]),
      ]);
      final out = tryOutdentBlockNode(s, s.getNodeAtPath([0, 0])!);
      await tester.pumpAndSettle();
      expect(read(s), ['A@0', 'B@0', 'b1@1', 'C@1']);
      expect(out?.path, [1]);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Backspace at the start of a FIRST child keeps its children in place',
      (tester) async {
    final s = await pump(tester, [
      b('A', [b('X', [b('x1')]), b('C')]),
    ]);
    s.selection = Selection.collapsed(Position(path: [0, 0], offset: 0));
    backspaceCommand.execute(s);
    await tester.pumpAndSettle();
    expect(read(s), ['AX@0', 'x1@1', 'C@1']);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Delete at the end of a row whose first child has children',
      (tester) async {
    final s = await pump(tester, [
      b('A', [b('X', [b('x1')]), b('C')]),
    ]);
    s.selection = Selection.collapsed(Position(path: [0], offset: 1));
    deleteCommand.execute(s);
    await tester.pumpAndSettle();
    expect(read(s), ['AX@0', 'x1@1', 'C@1']);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Delete at the end of a leaf pulls the next row children under it',
      (tester) async {
    final s = await pump(tester, [
      b('A'),
      b('X', [b('x1')]),
    ]);
    s.selection = Selection.collapsed(Position(path: [0], offset: 1));
    deleteCommand.execute(s);
    await tester.pumpAndSettle();
    expect(read(s), ['AX@0', 'x1@1']);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Tab over rows of two parents indents only the first parent group',
      (tester) async {
    final s = await pump(tester, [
      b('P'),
      b('A', [b('a1'), b('a2')]),
      b('B', [b('b1')]),
    ]);
    s.selection = Selection(
        start: Position(path: [1, 1], offset: 0),
        end: Position(path: [2, 0], offset: 1));
    indentCommand.execute(s);
    await tester.pumpAndSettle();
    expect(read(s), ['P@0', 'A@0', 'a1@1', 'a2@2', 'B@0', 'b1@1']);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Tab keeps the caret on its text inside a nested child',
      (tester) async {
    final s = await pump(tester, [
      b('A'),
      b('B', [b('b1')]),
    ]);
    s.selection = Selection(
        start: Position(path: [1], offset: 0),
        end: Position(path: [1, 0], offset: 1));
    indentCommand.execute(s);
    await tester.pumpAndSettle();
    expect(read(s), ['A@0', 'B@1', 'b1@2']);
    expect(s.selection!.end.path, [0, 0, 0]);
    expect(s.selection!.end.offset, 1);
    await tester.pump(const Duration(milliseconds: 100));
  });
}
