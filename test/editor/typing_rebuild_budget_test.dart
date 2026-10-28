// One keystroke in a long note must rebuild a handful of widgets, not one per block.
//
// Two listeners used to fan out to every visible block on each selection change
// (a keystroke moves the caret): the paragraph's placeholder `setState` when the
// host wires `showPlaceholder`, and every `BlockSelectionArea` builder. Measured
// on 300 paragraphs: 1902 rebuilt widgets (30 ms) per key before, 24 (3 ms) after.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

void main() {
  testWidgets('typing in a 300-block note rebuilds a few widgets per key',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          for (var i = 0; i < 300; i++)
            paragraphNode(text: 'Paragraph $i with some words to lay out.'),
        ]),
    )..disableSealTimer = true;
    final builders = {...standardBlockComponentBuilderMap};
    // The app's wiring: a host `showPlaceholder` hook on every paragraph.
    builders[ParagraphBlockKeys.type] = ParagraphBlockComponentBuilder(
      configuration: const BlockComponentConfiguration(),
      showPlaceholder: (editorState, node) => false,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
            editorState: state, blockComponentBuilders: builders),
      ),
    ));
    await tester.pumpAndSettle();
    state.selection = Selection.collapsed(Position(path: [3], offset: 5));
    await tester.pump();

    var rebuilt = 0;
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => rebuilt++;
    debugPrintRebuildDirtyWidgets = true;
    const keys = 20;
    for (var i = 0; i < keys; i++) {
      await state.apply(state.transaction
        ..insertText(state.getNodeAtPath([3])!, 5 + i, 'x')
        ..afterSelection =
            Selection.collapsed(Position(path: [3], offset: 6 + i)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = previous;

    expect(rebuilt / keys, lessThan(60),
        reason: 'rebuilt widgets per keystroke; it scales with the number of '
            'visible blocks if a selection listener fans out again');
  });

  testWidgets('adding a block in a 300-block note keeps the other blocks',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          for (var i = 0; i < 300; i++)
            paragraphNode(text: 'Paragraph $i with some words to lay out.'),
        ]),
    )..disableSealTimer = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppFlowyEditor(editorState: state)),
    ));
    await tester.pumpAndSettle();
    state.selection = Selection.collapsed(Position(path: [3], offset: 5));
    await tester.pump();

    var rebuilt = 0;
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => rebuilt++;
    debugPrintRebuildDirtyWidgets = true;
    const adds = 5;
    for (var i = 0; i < adds; i++) {
      await state.apply(state.transaction
        ..insertNode([4 + i], paragraphNode(text: 'new $i'))
        ..afterSelection =
            Selection.collapsed(Position(path: [4 + i], offset: 0)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = previous;

    // Was about 6400 per insert: every block below the new one rebuilt.
    expect(rebuilt / adds, lessThan(3000));
    expect(find.textContaining('Paragraph 2 ', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('new 4', findRichText: true), findsOneWidget);
    expect(find.textContaining('Paragraph 7 ', findRichText: true),
        findsOneWidget);
  });

  testWidgets('a numbered list renumbers when a block is added above it',
      (tester) async {
    final state = EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          paragraphNode(text: 'intro'),
          numberedListNode(delta: Delta()..insert('first')),
          numberedListNode(delta: Delta()..insert('second')),
        ]),
    )..disableSealTimer = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppFlowyEditor(editorState: state)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2.'), findsOneWidget);

    // Another numbered item at the head of the run: "first" becomes 2.
    await state.apply(state.transaction
      ..insertNode([1], numberedListNode(delta: Delta()..insert('zero'))));
    await tester.pumpAndSettle();
    expect(find.text('3.'), findsOneWidget);
  });

  testWidgets('Enter in a long bulleted list does not rebuild every bullet',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Node bullet(String text) => bulletedListNode(delta: Delta()..insert(text));
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [for (var i = 0; i < 300; i++) bullet('Bullet $i')]),
    )..disableSealTimer = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppFlowyEditor(editorState: state)),
    ));
    await tester.pumpAndSettle();
    state.selection = Selection.collapsed(Position(path: [3], offset: 5));
    await tester.pump();

    var rebuilt = 0;
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => rebuilt++;
    debugPrintRebuildDirtyWidgets = true;
    const adds = 5;
    for (var i = 0; i < adds; i++) {
      await state.apply(state.transaction
        ..insertNode([4 + i], bullet('new $i'))
        ..afterSelection =
            Selection.collapsed(Position(path: [4 + i], offset: 0)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = previous;

    expect(rebuilt / adds, lessThan(3000)); // was about 6000
    expect(find.textContaining('Bullet 9', findRichText: true), findsOneWidget);
    expect(find.text('●'), findsWidgets);
  });

  testWidgets('deleting blocks and jumping still land on the right block',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          for (var i = 0; i < 300; i++) paragraphNode(text: 'Line number $i.'),
        ]),
    )..disableSealTimer = true;
    final scroll = EditorScrollController(editorState: state);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body:
            AppFlowyEditor(editorState: state, editorScrollController: scroll),
      ),
    ));
    await tester.pumpAndSettle();

    // Remove blocks above the viewport's start and in the middle.
    await state.apply(state.transaction..deleteNodesAtPath([1], 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('Line number 0.', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Line number 1.', findRichText: true),
        findsNothing);
    expect(find.textContaining('Line number 4.', findRichText: true),
        findsOneWidget);

    // 300 - 3 = 297 blocks; jump to the last one.
    scroll.itemScrollController.jumpTo(index: 296);
    await tester.pumpAndSettle();
    expect(find.textContaining('Line number 299.', findRichText: true),
        findsOneWidget);

    // Add a block while scrolled down: it shows up where it was put.
    await state.apply(state.transaction
      ..insertNode([295], paragraphNode(text: 'Inserted far down')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Inserted far down', findRichText: true),
        findsOneWidget);
  });

  testWidgets('Enter in a long numbered list renumbers and stays cheap',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Node item(String text) => numberedListNode(delta: Delta()..insert(text));
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [for (var i = 0; i < 300; i++) item('Step $i')]),
    )..disableSealTimer = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppFlowyEditor(editorState: state)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('7.'), findsOneWidget); // "Step 6"

    var rebuilt = 0;
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => rebuilt++;
    debugPrintRebuildDirtyWidgets = true;
    await state.apply(state.transaction..insertNode([2], item('inserted')));
    await tester.pump(const Duration(milliseconds: 16));
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = previous;
    await tester.pumpAndSettle();

    // Every item below the new one moved down a number; the ones above did not.
    expect(find.text('3.'), findsOneWidget); // the inserted item
    expect(find.text('7.'), findsOneWidget); // now "Step 5"
    expect(find.text('8.'), findsOneWidget); // now "Step 6"
    expect(find.text('2.'), findsOneWidget); // "Step 1"
    // Items below the new one must rebuild to show their new number, so this
    // insert at the top of the run is the costly case (about 5900).
    expect(rebuilt, lessThan(9000));

    // An insert further down leaves the items above it, the ones on screen,
    // untouched: that is the cheap case, the common one when typing at the end.
    rebuilt = 0;
    debugPrint = (String? message, {int? wrapWidth}) => rebuilt++;
    debugPrintRebuildDirtyWidgets = true;
    await state.apply(state.transaction..insertNode([250], item('late')));
    await tester.pump(const Duration(milliseconds: 16));
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = previous;
    expect(rebuilt, lessThan(3000)); // was about 6000
    expect(find.text('7.'), findsOneWidget);
  });

  testWidgets('a long checklist: cheap inserts, and the done divider follows',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          for (var i = 0; i < 300; i++)
            todoListNode(checked: false, text: 'task $i'),
        ]),
    )..disableSealTimer = true;
    final scroll = EditorScrollController(editorState: state);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: state,
          editorScrollController: scroll,
          blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
          editorStyle: EditorStyle.mobile(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Ticking a row sinks it into the pile at the bottom of the run; the
    // divider is drawn there, not on every row.
    toggleTodoRowAndSink(state, state.document.root.children[1], true);
    await tester.pumpAndSettle();
    expect(state.document.root.children.last.attributes['checked'], isTrue);

    // An insert far below the visible rows rebuilds none of them.
    var rebuilt = 0;
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => rebuilt++;
    debugPrintRebuildDirtyWidgets = true;
    await state.apply(state.transaction
      ..insertNode([250], todoListNode(checked: false, text: 'late task')));
    await tester.pump(const Duration(milliseconds: 16));
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = previous;
    expect(rebuilt, lessThan(3000)); // was about 7000

    // The pile's divider survives an insert above it and a tick of another row.
    await state.apply(state.transaction
      ..insertNode([2], todoListNode(checked: false, text: 'early task')));
    await tester.pumpAndSettle();
    toggleTodoRowAndSink(state, state.document.root.children[3], true);
    await tester.pumpAndSettle();
    final pile = state.document.root.children
        .where((n) => n.attributes['checked'] == true)
        .length;
    expect(pile, 2);
    // Scroll to the pile: exactly one divider for the run.
    scroll.itemScrollController
        .jumpTo(index: state.document.root.children.length - 1);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.replay), findsOneWidget);
  });
}
