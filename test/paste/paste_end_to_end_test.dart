import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Future<EditorState> _pump(WidgetTester tester, List<Node> start) async {
  final state = EditorState(document: Document.blank()..insert([0], start));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: state,
          editorStyle: EditorStyle.desktop(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Future<void> _paste(
  WidgetTester tester,
  EditorState state, {
  String? text,
  String? html,
}) async {
  AppFlowyClipboard.mockSetData(AppFlowyClipboardData(text: text, html: html));
  addTearDown(() => AppFlowyClipboard.mockSetData(null));
  pasteCommand.handler(state);
  await tester.pumpAndSettle();
}

List<String> _texts(EditorState s) =>
    s.document.root.children.map((n) => n.delta?.toPlainText() ?? '').toList();

List<String> _types(EditorState s) =>
    s.document.root.children.map((n) => n.type).toList();

void main() {
  for (final sep in ['\n', '\r\n', '\r', ' ']) {
    testWidgets('plain paste ${sep.codeUnits}: a row per line, then checklist',
        (tester) async {
      final state = await _pump(tester, [paragraphNode(text: '')]);
      state.selection = Selection.collapsed(Position(path: [0]));
      await _paste(tester, state, text: 'one${sep}two${sep}three');
      expect(_texts(state), ['one', 'two', 'three']);

      // Select all pasted lines and turn them into a checklist, as the toolbar does.
      state.selection = Selection(
        start: Position(path: [0]),
        end: Position(path: [2], offset: 5),
      );
      await state.formatNode(
        state.selection,
        (node) => node.copyWith(
          type: TodoListBlockKeys.type,
          attributes: {
            TodoListBlockKeys.checked: false,
            blockComponentDelta: (node.delta ?? Delta()).toJson(),
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(_types(state), everyElement(TodoListBlockKeys.type));
      expect(_texts(state), ['one', 'two', 'three']);
    });
  }

  testWidgets('html paste with <br> lines: a row per line', (tester) async {
    final state = await _pump(tester, [paragraphNode(text: '')]);
    state.selection = Selection.collapsed(Position(path: [0]));
    await _paste(tester, state, text: 'a\nb\nc', html: '<p>a<br>b<br>c</p>');
    expect(_texts(state), ['a', 'b', 'c']);
  });

  testWidgets('paste into an empty checkbox row: all rows are checkboxes',
      (tester) async {
    final state = await _pump(tester, [todoListNode(checked: true, text: '')]);
    state.selection = Selection.collapsed(Position(path: [0]));
    await _paste(tester, state, text: 'x\ny\nz');
    expect(_texts(state), ['x', 'y', 'z']);
    expect(_types(state), everyElement(TodoListBlockKeys.type));
  });

  testWidgets('paste into the end of a typed bullet row keeps bullets',
      (tester) async {
    final state = await _pump(tester, [bulletedListNode(text: 'hi ')]);
    state.selection = Selection.collapsed(Position(path: [0], offset: 3));
    await _paste(tester, state, text: 'x\ny');
    expect(_texts(state), ['hi x', 'y']);
    expect(_types(state), everyElement(BulletedListBlockKeys.type));
  });
}
