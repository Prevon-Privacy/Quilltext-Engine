import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Future<EditorState> _pump(WidgetTester tester, int rows) async {
  final state = EditorState(
    document: Document.blank()
      ..insert([0], [
        for (var i = 0; i < rows; i++)
          todoListNode(checked: false, text: 'item $i'),
      ]),
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AppFlowyEditor(
        editorState: state,
        blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
        editorStyle: EditorStyle.mobile(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('checking rows bottom-up shows one done divider', (tester) async {
    final state = await _pump(tester, 4);
    for (var i = 3; i >= 0; i--) {
      toggleTodoRowAndSink(state, state.document.root.children[i], true);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.replay), findsOneWidget, reason: 'after row $i');
    }
  });

  testWidgets('delete button removes the completed rows in one undo step',
      (tester) async {
    final state = await _pump(tester, 3);
    toggleTodoRowAndSink(state, state.document.root.children[2], true);
    toggleTodoRowAndSink(state, state.document.root.children[1], true);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(state.document.root.children.length, 1);
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    state.undoManager.undo();
    await tester.pumpAndSettle();
    expect(state.document.root.children.length, 3);
  });

  testWidgets('a gap (paragraph) splits runs; each run keeps one divider',
      (tester) async {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [
          todoListNode(checked: false, text: 'a0'),
          todoListNode(checked: false, text: 'a1'),
          for (var i = 0; i < 6; i++) paragraphNode(text: 'gap $i'),
          todoListNode(checked: false, text: 'b0'),
          todoListNode(checked: false, text: 'b1'),
        ]),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: state,
          blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
          editorStyle: EditorStyle.mobile(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final kids = state.document.root.children;
    // Alternate between the two runs, bottom-up in each.
    for (final i in [9, 1, 8, 0]) {
      toggleTodoRowAndSink(state, kids[i], true);
      await tester.pumpAndSettle();
    }
    expect(find.byIcon(Icons.replay), findsNWidgets(2));
  });

  testWidgets('moveTodoCompletedGroup moves the done rows as one undo step',
      (tester) async {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [
          todoListNode(checked: false, text: 'a'),
          todoListNode(checked: false, text: 'b'),
          todoListNode(checked: false, text: 'c'),
          paragraphNode(text: 'p'),
        ]),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: state,
          blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
          editorStyle: EditorStyle.mobile(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    toggleTodoRowAndSink(state, state.document.root.children[2], true);
    toggleTodoRowAndSink(state, state.document.root.children[0], true);
    await tester.pumpAndSettle();
    List<String> texts() => state.document.root.children
        .map((n) => n.delta!.toPlainText())
        .toList();
    expect(texts(), ['b', 'a', 'c', 'p']);

    // Drop inside the group itself is a no-op.
    expect(moveTodoCompletedGroup(state, state.document.root.children[1], 2),
        isFalse);
    // Move to the very end (below the paragraph).
    expect(moveTodoCompletedGroup(state, state.document.root.children[1], 4),
        isTrue);
    await tester.pumpAndSettle();
    expect(texts(), ['b', 'p', 'a', 'c']);

    state.undoManager.undo();
    await tester.pumpAndSettle();
    expect(texts(), ['b', 'a', 'c', 'p']);
    // Move to the top.
    expect(moveTodoCompletedGroup(state, state.document.root.children[1], 0),
        isTrue);
    await tester.pumpAndSettle();
    expect(texts(), ['a', 'c', 'b', 'p']);
  });

  testWidgets('a moved completed group stays checked and keeps its divider',
      (tester) async {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [
          todoListNode(checked: false, text: 'a'),
          todoListNode(checked: false, text: 'b'),
          todoListNode(checked: false, text: 'c'),
        ]),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: state,
          blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
          editorStyle: EditorStyle.mobile(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    toggleTodoRowAndSink(state, state.document.root.children[2], true);
    await tester.pumpAndSettle();
    expect(moveTodoCompletedGroup(state, state.document.root.children[2], 0),
        isTrue);
    await tester.pumpAndSettle();
    final kids = state.document.root.children;
    expect(kids.map((n) => n.delta!.toPlainText()).toList(), ['c', 'a', 'b']);
    expect(kids[0].attributes[TodoListBlockKeys.checked], isTrue);
    final v = todoCompletedGroupView(kids[0])!;
    expect(v.completedStart, 0);
    expect(v.completedCount, 1);
    expect(find.byIcon(Icons.replay), findsOneWidget);
  });
}
