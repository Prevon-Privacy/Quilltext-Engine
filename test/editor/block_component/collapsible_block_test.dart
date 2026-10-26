import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

EditorState _state(List<Node> nodes, {Selection? selection}) {
  final state = EditorState(
    document: Document.blank()..insert([0], nodes),
  );
  state.selection = selection;
  return state;
}

Node _folded({bool collapsed = false}) => collapsibleNode(
      text: 'Title',
      collapsed: collapsed,
      children: [
        paragraphNode(text: 'hidden one'),
        paragraphNode(text: 'hidden two'),
      ],
    );

void main() {
  group('state', () {
    test('open by default, closed only with a body', () {
      final open = _folded();
      final closed = _folded(collapsed: true);
      final emptyClosed = collapsibleNode(text: 'x', collapsed: true);
      expect(isCollapsibleClosed(open), isFalse);
      expect(isCollapsibleClosed(closed), isTrue);
      // Nothing to fold: reads as open.
      expect(isCollapsibleClosed(emptyClosed), isFalse);
    });

    test('toggle writes and clears the collapsed attribute', () {
      final state = _state([_folded()]);
      final node = state.getNodeAtPath([0])!;
      setCollapsibleCollapsed(state, node, true);
      expect(state.getNodeAtPath([0])!.attributes[blockComponentCollapsed],
          isTrue);
      setCollapsibleCollapsed(state, state.getNodeAtPath([0])!, false);
      expect(
          state
              .getNodeAtPath([0])!
              .attributes
              .containsKey(blockComponentCollapsed),
          isFalse);
      // The body is never touched.
      expect(state.getNodeAtPath([0])!.children.length, 2);
    });

    test('closing moves a caret inside the body to the end of the title', () {
      final state = _state(
        [_folded()],
        selection: Selection.collapsed(Position(path: [0, 1], offset: 3)),
      );
      setCollapsibleCollapsed(state, state.getNodeAtPath([0])!, true);
      expect(state.selection,
          Selection.collapsed(Position(path: [0], offset: 'Title'.length)));
    });

    test('collapse all / expand all handle nested ones and report states', () {
      final inner = _folded();
      final outer = collapsibleNode(text: 'Outer', children: [inner]);
      final state = _state([outer, _folded()]);
      var s = collapsibleStates(state);
      expect((s.open, s.closed), (true, false));
      expect(setAllCollapsiblesCollapsed(state, true), 3);
      s = collapsibleStates(state);
      expect((s.open, s.closed), (false, true));
      expect(setAllCollapsiblesCollapsed(state, true), 0);
      expect(setAllCollapsiblesCollapsed(state, false), 3);
      expect(collapsibleStates(state).closed, isFalse);
    });
  });

  group('fold a selection', () {
    EditorState lines() => _state([
          paragraphNode(text: 'Heading'),
          paragraphNode(text: 'one'),
          paragraphNode(text: 'two'),
          paragraphNode(text: 'outside'),
        ]);

    test('first line becomes the title, the rest move inside', () {
      final state = lines();
      final done = wrapSelectionInCollapsible(
        state,
        Selection(
          start: Position(path: [0], offset: 2),
          end: Position(path: [2], offset: 1),
        ),
      );
      expect(done, isTrue);
      expect(state.document.root.children.length, 2);
      final block = state.getNodeAtPath([0])!;
      expect(block.type, CollapsibleBlockKeys.type);
      expect(block.delta!.toPlainText(), 'Heading');
      expect(block.children.map((c) => c.delta!.toPlainText()), ['one', 'two']);
      expect(state.getNodeAtPath([1])!.delta!.toPlainText(), 'outside');
    });

    test('one line, a collapsible title or a table is left to the toggle', () {
      final state = lines();
      expect(
        wrapSelectionInCollapsible(
          state,
          Selection.collapsed(Position(path: [1], offset: 0)),
        ),
        isFalse,
      );
      final withBlock = _state([_folded(), paragraphNode(text: 'x')]);
      expect(
        wrapSelectionInCollapsible(
          withBlock,
          Selection(
            start: Position(path: [0], offset: 0),
            end: Position(path: [1], offset: 1),
          ),
        ),
        isFalse,
      );
      expect(withBlock.document.root.children.length, 2);
    });

    test('undo restores the original lines exactly', () {
      final state = lines();
      wrapSelectionInCollapsible(
        state,
        Selection(
          start: Position(path: [0], offset: 0),
          end: Position(path: [2], offset: 3),
        ),
      );
      state.undoManager.undo();
      expect(state.document.root.children.length, 4);
      expect(state.getNodeAtPath([2])!.delta!.toPlainText(), 'two');
      expect(state.getNodeAtPath([0])!.type, ParagraphBlockKeys.type);
    });
  });

  group('typing', () {
    test('">> " becomes a collapsible, ">" alone stays a quote', () async {
      final state = _state(
        [paragraphNode(text: '>>')],
        selection: Selection.collapsed(Position(path: [0], offset: 2)),
      );
      expect(await formatDoubleGreaterToCollapsible.handler(state), isTrue);
      expect(state.getNodeAtPath([0])!.type, CollapsibleBlockKeys.type);

      final single = _state(
        [paragraphNode(text: '>')],
        selection: Selection.collapsed(Position(path: [0], offset: 1)),
      );
      expect(await formatDoubleGreaterToCollapsible.handler(single), isFalse);
    });

    test('Enter in an open title starts the first line inside the body',
        () async {
      final state = _state(
        [_folded()],
        selection: Selection.collapsed(Position(path: [0], offset: 2)),
      );
      expect(await insertNewLineAfterCollapsible.handler(state), isTrue);
      final node = state.getNodeAtPath([0])!;
      expect(node.delta!.toPlainText(), 'Ti');
      expect(node.children.length, 3);
      expect(node.children.first.delta!.toPlainText(), 'tle');
      expect(node.children[1].delta!.toPlainText(), 'hidden one');
      expect(state.selection,
          Selection.collapsed(Position(path: [0, 0], offset: 0)));
    });

    test('Enter in a closed title adds a line after the block', () async {
      final state = _state(
        [_folded(collapsed: true)],
        selection: Selection.collapsed(Position(path: [0], offset: 5)),
      );
      expect(await insertNewLineAfterCollapsible.handler(state), isTrue);
      expect(state.getNodeAtPath([0])!.children.length, 2);
      expect(state.getNodeAtPath([1])!.type, ParagraphBlockKeys.type);
      expect(
          state.selection, Selection.collapsed(Position(path: [1], offset: 0)));
    });

    test('Enter at the very start adds a blank line above, block untouched',
        () async {
      final state = _state(
        [_folded(collapsed: true)],
        selection: Selection.collapsed(Position(path: [0], offset: 0)),
      );
      expect(await insertNewLineAfterCollapsible.handler(state), isTrue);
      expect(state.getNodeAtPath([0])!.type, ParagraphBlockKeys.type);
      final block = state.getNodeAtPath([1])!;
      expect(block.type, CollapsibleBlockKeys.type);
      expect(block.delta!.toPlainText(), 'Title');
      expect(block.children.length, 2);
      expect(
          state.selection, Selection.collapsed(Position(path: [1], offset: 0)));
    });

    test('Enter on an empty, childless title leaves the block', () async {
      final state = _state(
        [collapsibleNode(text: '')],
        selection: Selection.collapsed(Position(path: [0], offset: 0)),
      );
      expect(await insertNewLineAfterCollapsible.handler(state), isTrue);
      expect(state.getNodeAtPath([0])!.type, ParagraphBlockKeys.type);
    });
  });

  group('export keeps the hidden text', () {
    test('markdown', () {
      final doc = Document.blank()..insert([0], [_folded(collapsed: true)]);
      final md = documentToMarkdown(doc);
      expect(md, contains('<details>'));
      expect(md, contains('<summary>Title</summary>'));
      expect(md, contains('hidden one'));
      expect(md, contains('hidden two'));
    });

    test('markdown marks an open one with open', () {
      final doc = Document.blank()..insert([0], [_folded()]);
      expect(documentToMarkdown(doc), contains('<details open>'));
    });

    test('html', () {
      final doc = Document.blank()..insert([0], [_folded(collapsed: true)]);
      final html = documentToHTML(doc);
      expect(html, contains('<details>'));
      expect(html, contains('<summary>Title</summary>'));
      expect(html, contains('hidden two'));
    });
  });

  group('copy and paste (HTML) keep the block', () {
    Document back(List<Node> nodes) =>
        htmlToDocument(documentToHTML(Document.blank()..insert([0], nodes)));

    test('a closed block comes back closed with its whole body', () {
      final doc = back([_folded(collapsed: true)]);
      final node = doc.root.children.single;
      expect(node.type, CollapsibleBlockKeys.type);
      expect(node.delta!.toPlainText(), 'Title');
      expect(node.attributes[blockComponentCollapsed], isTrue);
      expect(node.children.map((c) => c.delta!.toPlainText()),
          ['hidden one', 'hidden two']);
    });

    test('an open block comes back open', () {
      final node = back([_folded()]).root.children.single;
      expect(node.attributes.containsKey(blockComponentCollapsed), isFalse);
      expect(node.children.length, 2);
    });

    test('nested blocks and title marks survive', () {
      final inner = collapsibleNode(
        text: 'Inner',
        collapsed: true,
        children: [paragraphNode(text: 'deep')],
      );
      final outer = collapsibleNode(
        delta: Delta()
          ..insert('Bold', attributes: {'bold': true})
          ..insert(' title'),
        children: [inner, paragraphNode(text: 'tail')],
      );
      final node = back([outer]).root.children.single;
      expect(node.delta!.toPlainText(), 'Bold title');
      expect(node.delta!.first.attributes?['bold'], isTrue);
      expect(node.children.first.type, CollapsibleBlockKeys.type);
      expect(node.children.first.children.single.delta!.toPlainText(), 'deep');
      expect(node.children.last.delta!.toPlainText(), 'tail');
    });

    test('a block with nothing inside stays open and keeps its title', () {
      final node = back([collapsibleNode(text: 'Alone')]).root.children.single;
      expect(node.type, CollapsibleBlockKeys.type);
      expect(node.delta!.toPlainText(), 'Alone');
    });

    test('details from another app (no open) arrive closed', () {
      final doc = htmlToDocument(
          '<details><summary>FAQ</summary><p>answer</p></details>');
      final node = doc.root.children.single;
      expect(node.type, CollapsibleBlockKeys.type);
      expect(node.attributes[blockComponentCollapsed], isTrue);
      expect(node.children.single.delta!.toPlainText(), 'answer');
    });
  });

  group('editing and moving with a body', () {
    test('typing in the body, folding, then Undo undoes the typing only', () {
      final state = _state([_folded()]);
      final tx = state.transaction
        ..insertText(state.getNodeAtPath([0, 0])!, 10, '!');
      state.apply(tx);
      expect(state.getNodeAtPath([0, 0])!.delta!.toPlainText(), 'hidden one!');
      setCollapsibleCollapsed(state, state.getNodeAtPath([0])!, true);
      state.undoManager.undo();
      // Folding was view state: the typing is what came off.
      expect(state.getNodeAtPath([0, 0])!.delta!.toPlainText(), 'hidden one');
      expect(isCollapsibleClosed(state.getNodeAtPath([0])!), isTrue);
    });

    test('a table inside the body keeps edits while folded and unfolded', () {
      final table = TableNode.fromList([
        ['a', 'b'],
        ['c', 'd'],
      ]).node;
      final state = _state([
        collapsibleNode(text: 'T', children: [table]),
      ]);
      final cellText = state.getNodeAtPath([0, 0, 0, 0])!;
      final tx = state.transaction..insertText(cellText, 1, 'X');
      state.apply(tx);
      setCollapsibleCollapsed(state, state.getNodeAtPath([0])!, true);
      setCollapsibleCollapsed(state, state.getNodeAtPath([0])!, false);
      expect(documentToMarkdown(state.document), contains('aX'));
    });

    test('moving a block into and out of the body keeps everything', () {
      final state = _state([
        paragraphNode(text: 'outside'),
        _folded(collapsed: true),
      ]);
      // Into the (closed) body.
      var tx = state.transaction..moveNode([1, 2], state.getNodeAtPath([0])!);
      state.apply(tx);
      expect(state.getNodeAtPath([0])!.type, CollapsibleBlockKeys.type);
      expect(state.getNodeAtPath([0])!.children.length, 3);
      expect(isCollapsibleClosed(state.getNodeAtPath([0])!), isTrue);
      // And back out below it.
      tx = state.transaction..moveNode([1], state.getNodeAtPath([0, 2])!);
      state.apply(tx);
      expect(state.getNodeAtPath([0])!.children.length, 2);
      expect(state.getNodeAtPath([1])!.delta!.toPlainText(), 'outside');
    });

    test('deleting a block with a body and Undo brings back body and state',
        () {
      final state =
          _state([_folded(collapsed: true), paragraphNode(text: 'x')]);
      final tx = state.transaction..deleteNode(state.getNodeAtPath([0])!);
      state.apply(tx);
      expect(state.document.root.children.length, 1);
      state.undoManager.undo();
      final back = state.getNodeAtPath([0])!;
      expect(back.children.length, 2);
      expect(isCollapsibleClosed(back), isTrue);
    });

    test('a deeply nested stack folds and reports counts', () {
      var inner = collapsibleNode(text: 'L0', children: [
        paragraphNode(text: 'leaf'),
      ]);
      for (var i = 1; i < 6; i++) {
        inner = collapsibleNode(text: 'L$i', children: [inner]);
      }
      final state = _state([inner]);
      expect(collapsibleHiddenCount(state.getNodeAtPath([0])!), 6);
      expect(setAllCollapsiblesCollapsed(state, true), 6);
      expect(setAllCollapsiblesCollapsed(state, false), 6);
    });
  });

  group('widget', () {
    Future<EditorState> pump(WidgetTester tester, List<Node> nodes) async {
      final state = _state(nodes);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppFlowyEditor(
              editorState: state,
              blockComponentBuilders: buildStandardBlockComponentBuilderMap()
                ..[CollapsibleBlockKeys.type] =
                    CollapsibleBlockComponentBuilder(
                  toggleDescription: (willCollapse) =>
                      willCollapse ? 'Hide contents' : 'Show contents',
                  hiddenHint: (n) => '$n hidden',
                ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('tapping the arrow hides and shows the body', (tester) async {
      final state = await pump(tester, [_folded()]);
      expect(find.text('hidden one', findRichText: true), findsOneWidget);

      Finder labelled(String label) => find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == label,
          );
      expect(labelled('Hide contents'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('hidden one', findRichText: true), findsNothing);
      expect(find.text('2 hidden'), findsOneWidget);
      expect(state.getNodeAtPath([0])!.attributes[blockComponentCollapsed],
          isTrue);

      expect(labelled('Show contents'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('hidden one', findRichText: true), findsOneWidget);
      expect(find.text('2 hidden'), findsNothing);
    });

    testWidgets('anything can live inside the body, open or closed, narrow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final everything = <Node>[
        headingNode(level: 2, text: 'A heading'),
        bulletedListNode(text: 'bullet'),
        numberedListNode(delta: Delta()..insert('number')),
        todoListNode(checked: false, text: 'todo'),
        quoteNode(delta: Delta()..insert('a quote')),
        dividerNode(),
        fileNode(
          url: 'pie-att://v1/abc',
          name: 'Report.pdf',
          mime: 'application/pdf',
          size: 2400000,
        ),
        columnsNode(children: [
          columnNode(children: [paragraphNode(text: 'left')]),
          columnNode(children: [paragraphNode(text: 'right')]),
        ]),
        TableNode.fromList([
          ['a', 'b'],
          ['c', 'd'],
        ]).node,
        collapsibleNode(text: 'inner', children: [
          collapsibleNode(
              text: 'innermost', children: [paragraphNode(text: 'deep')]),
          paragraphNode(text: 'inner body'),
        ]),
        paragraphNode(text: 'last line'),
      ];
      final state = _state([
        collapsibleNode(text: 'Everything', children: everything),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppFlowyEditor(
              editorState: state,
              blockComponentBuilders: buildStandardBlockComponentBuilderMap()
                ..[CollapsibleBlockKeys.type] =
                    CollapsibleBlockComponentBuilder(
                  hiddenHint: (n) => '$n hidden',
                ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('last line', findRichText: true), findsOneWidget);
      expect(find.text('deep', findRichText: true), findsOneWidget);

      // Fold the outer one: everything goes, nothing throws.
      setCollapsibleCollapsed(state, state.getNodeAtPath([0])!, true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('last line', findRichText: true), findsNothing);
      expect(find.text('Everything', findRichText: true), findsOneWidget);

      // Open again, then fold the inner one inside it.
      setCollapsibleCollapsed(state, state.getNodeAtPath([0])!, false);
      await tester.pumpAndSettle();
      setCollapsibleCollapsed(
          state, state.getNodeAtPath([0, everything.length - 2])!, true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('deep', findRichText: true), findsNothing);
      expect(find.text('last line', findRichText: true), findsOneWidget);

      // The text stays in the document for export, whatever the state.
      expect(documentToMarkdown(state.document), contains('deep'));
    });

    testWidgets('an image block inside the body lays out and folds',
        (tester) async {
      final state = _state([
        collapsibleNode(text: 'Pics', children: [
          paragraphNode(text: 'before'),
          imageNode(url: 'https://example.invalid/a.png', height: 120),
          paragraphNode(text: 'after'),
        ]),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppFlowyEditor(
              editorState: state,
              blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('after', findRichText: true), findsOneWidget);
      setCollapsibleCollapsed(state, state.getNodeAtPath([0])!, true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('after', findRichText: true), findsNothing);
    });

    testWidgets('every tap target plays the host tick once; none by default',
        (tester) async {
      var ticks = 0;
      Future<EditorState> mount({VoidCallback? feedback}) async {
        final state = _state([_folded()]);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppFlowyEditor(
                editorState: state,
                blockComponentBuilders: buildStandardBlockComponentBuilderMap()
                  ..[CollapsibleBlockKeys.type] =
                      CollapsibleBlockComponentBuilder(
                    hiddenHint: (n) => '$n hidden',
                    onToggleFeedback: feedback,
                  ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return state;
      }

      await mount(feedback: () => ticks++);
      await tester.tap(find.byIcon(Icons.chevron_right)); // close
      await tester.pumpAndSettle();
      expect(ticks, 1);
      await tester.tap(find.text('2 hidden')); // open via the pill
      await tester.pumpAndSettle();
      expect(ticks, 2);

      // No callback: the engine stays silent and still toggles.
      final state = await mount();
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(isCollapsibleClosed(state.getNodeAtPath([0])!), isTrue);
      expect(ticks, 2);
    });

    testWidgets('reduced motion folds with no animation to wait for',
        (tester) async {
      final state = _state([_folded()]);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: AppFlowyEditor(
                editorState: state,
                blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump(); // one frame, no settle
      await tester.pump();
      expect(find.text('hidden one', findRichText: true), findsNothing);
    });

    testWidgets('the toggle has a 40dp touch target, not just the glyph',
        (tester) async {
      final state = await pump(tester, [_folded()]);
      final glyph = tester.getCenter(find.byIcon(Icons.chevron_right));
      // 16dp left of the glyph centre is outside the 28dp pill, inside the slot.
      await tester.tapAt(glyph + const Offset(-16, 0));
      await tester.pumpAndSettle();
      expect(isCollapsibleClosed(state.getNodeAtPath([0])!), isTrue);
    });

    testWidgets('tapping the guide rail beside an open body folds it',
        (tester) async {
      final state = await pump(tester, [_folded()]);
      final glyph = tester.getCenter(find.byIcon(Icons.chevron_right));
      final body =
          tester.getTopLeft(find.text('hidden two', findRichText: true));
      // Straight below the chevron, level with the second body line.
      await tester.tapAt(Offset(glyph.dx, body.dy + 4));
      await tester.pumpAndSettle();
      expect(isCollapsibleClosed(state.getNodeAtPath([0])!), isTrue);
      expect(find.text('hidden two', findRichText: true), findsNothing);
    });

    testWidgets('tapping the hidden-lines pill opens the block',
        (tester) async {
      final state = _state([_folded(collapsed: true)]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppFlowyEditor(
              editorState: state,
              blockComponentBuilders: buildStandardBlockComponentBuilderMap()
                ..[CollapsibleBlockKeys.type] =
                    CollapsibleBlockComponentBuilder(
                  hiddenHint: (n) => '$n hidden',
                ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 hidden'));
      await tester.pumpAndSettle();
      expect(isCollapsibleClosed(state.getNodeAtPath([0])!), isFalse);
      expect(find.text('hidden one', findRichText: true), findsOneWidget);
    });

    testWidgets('the hidden-lines note drops under the title when narrow',
        (tester) async {
      Future<(Offset, Offset)> positions(double width) async {
        final state = _state([_folded(collapsed: true)]);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: AppFlowyEditor(
                    editorState: state,
                    blockComponentBuilders:
                        buildStandardBlockComponentBuilderMap()
                          ..[CollapsibleBlockKeys.type] =
                              CollapsibleBlockComponentBuilder(
                            hiddenHint: (n) => '$n lines hidden',
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return (
          tester.getTopLeft(find.text('Title', findRichText: true)),
          tester.getTopLeft(find.text('2 lines hidden')),
        );
      }

      final (wideTitle, wideHint) = await positions(700);
      expect(wideHint.dy, closeTo(wideTitle.dy, 8)); // same line
      expect(wideHint.dx, greaterThan(wideTitle.dx));

      final (narrowTitle, narrowHint) = await positions(150);
      expect(narrowHint.dy, greaterThan(narrowTitle.dy + 8)); // under it
    });

    testWidgets('tapping a folded title puts the caret in the title',
        (tester) async {
      final state = await pump(tester, [
        _folded(collapsed: true),
        paragraphNode(text: 'After the list'),
      ]);
      state.selection = Selection.collapsed(Position(path: [1], offset: 0));
      await tester.pumpAndSettle();
      await tester
          .tapAt(tester.getCenter(find.text('Title', findRichText: true)));
      await tester.pumpAndSettle();
      expect(state.selection?.start.path, [0]);
      expect(state.getNodeAtPath([0])!.attributes[blockComponentCollapsed],
          isTrue);
    });

    testWidgets('a closed block loads closed and keeps its text',
        (tester) async {
      final state = await pump(tester, [_folded(collapsed: true)]);
      expect(find.text('hidden one', findRichText: true), findsNothing);
      expect(state.getNodeAtPath([0])!.children.length, 2);
    });

    testWidgets('a caret that lands in a closed body opens the block',
        (tester) async {
      final state = await pump(tester, [_folded(collapsed: true)]);
      state.selection = Selection.collapsed(Position(path: [0, 0], offset: 0));
      await tester.pumpAndSettle();
      expect(state.getNodeAtPath([0])!.attributes[blockComponentCollapsed],
          isNot(true));
      expect(find.text('hidden one', findRichText: true), findsOneWidget);
    });
  });
}
