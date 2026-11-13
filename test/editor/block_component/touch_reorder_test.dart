import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Document _doc(String type, List<String> texts) => Document.blank()
  ..insert([0], [
    for (final t in texts)
      Node(type: type, attributes: {
        'delta': (Delta()..insert(t)).toJson(),
        if (type == 'todo_list') 'checked': false,
      }),
  ]);

Future<EditorState> _pump(
  WidgetTester tester,
  String type,
  List<String> texts,
) async {
  final state = EditorState(document: _doc(type, texts));
  final builders = buildStandardBlockComponentBuilderMap();
  for (final b in builders.values) {
    b.showActions = (_) => true;
    b.actionBuilder =
        (ctx, s) => BlockHoverActionHandle(node: ctx.node, state: s);
  }
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AppFlowyEditor(
        editorState: state,
        blockComponentBuilders: builders,
        editorStyle: EditorStyle.mobile(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return state;
}

List<String> _texts(EditorState s) =>
    s.document.root.children.map((n) => n.delta!.toPlainText()).toList();

Future<void> _longPressDrag(
  WidgetTester tester,
  Offset from,
  Offset to,
) async {
  final g = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 700));
  const steps = 8;
  for (var i = 1; i <= steps; i++) {
    await g.moveTo(Offset.lerp(from, to, i / steps)!);
    await tester.pump(const Duration(milliseconds: 30));
  }
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final type in ['todo_list', 'bulleted_list']) {
      testWidgets('$platform $type: long-press drag handle reorders',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final s = await _pump(tester, type, ['A', 'B', 'C']);
          final handles = find.byType(TouchReorderHandle);
          expect(handles, findsNWidgets(3));
          final from = tester.getCenter(handles.first);
          final to = tester.getCenter(handles.last) + const Offset(0, 30);
          await _longPressDrag(tester, from, to);
          expect(_texts(s), ['B', 'C', 'A']);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  testWidgets('android: bullet in a mixed note reorders and keeps its grip',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      Node n(String type, String t) => Node(type: type, attributes: {
            'delta': (Delta()..insert(t)).toJson(),
            if (type == 'todo_list') 'checked': false,
          });
      final state = EditorState(
        document: Document.blank()
          ..insert([0], [
            n('bulleted_list', 'Three'),
            n('paragraph', 'bulA'),
            n('todo_list', 'bulB'),
            n('paragraph', ''),
            n('paragraph', 'rowTwo'),
            n('paragraph', 'rowThree'),
          ]),
      );
      final builders = buildStandardBlockComponentBuilderMap();
      for (final b in builders.values) {
        b.showActions = (_) => true;
        b.actionBuilder =
            (ctx, s) => BlockHoverActionHandle(node: ctx.node, state: s);
      }
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: state,
            blockComponentBuilders: builders,
            editorStyle: EditorStyle.mobile(),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final grips = find.byType(TouchReorderHandle);
      final from = tester.getCenter(grips.first);
      final rowTwo = tester.getCenter(find.byType(AppFlowyRichText).at(4));
      await _longPressDrag(tester, from, Offset(from.dx, rowTwo.dy));
      expect(_texts(state).first, isNot('Three'),
          reason: 'bullet should have moved down');
      expect(find.byType(TouchReorderHandle), findsWidgets,
          reason: 'grips must stay visible after a drag on touch');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('android: swiping the grip right indents, left outdents',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final s = await _pump(tester, 'bulleted_list', ['A', 'B', 'C']);

      // Indent B under A, then C under B (unlimited depth).
      await tester.fling(find.byType(TouchReorderHandle).at(1),
          const Offset(50, 0), 800);
      await tester.pumpAndSettle();
      expect(s.document.root.children.length, 2);
      expect(s.document.root.children.first.children.length, 1);

      // C becomes a sibling of B under A; a second swipe nests it under B.
      await tester.fling(find.byType(TouchReorderHandle).at(2),
          const Offset(50, 0), 800);
      await tester.pumpAndSettle();
      expect(s.document.root.children.length, 1);
      final a0 = s.document.root.children.first;
      expect(a0.children.length, 2);

      await tester.fling(find.byType(TouchReorderHandle).at(2),
          const Offset(50, 0), 800);
      await tester.pumpAndSettle();
      expect(a0.children.length, 1);
      expect(a0.children.first.children.length, 1,
          reason: 'C nests two levels deep (no depth cap)');

      // Outdent C one level.
      await tester.fling(find.byType(TouchReorderHandle).at(2),
          const Offset(-50, 0), 800);
      await tester.pumpAndSettle();
      expect(s.document.root.children.first.children.length, 2);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a checklist row can be dragged past non-checklist blocks',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      Node n(String type, String t) => Node(type: type, attributes: {
            'delta': (Delta()..insert(t)).toJson(),
            if (type == 'todo_list') 'checked': false,
          });
      final state = EditorState(
        document: Document.blank()
          ..insert([0], [
            n('todo_list', 'T1'),
            n('paragraph', 'P1'),
            n('bulleted_list', 'B1'),
            n('paragraph', 'P2'),
          ]),
      );
      final builders = buildStandardBlockComponentBuilderMap();
      for (final b in builders.values) {
        b.showActions = (_) => true;
        b.actionBuilder =
            (ctx, s) => BlockHoverActionHandle(node: ctx.node, state: s);
      }
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: state,
            blockComponentBuilders: builders,
            editorStyle: EditorStyle.mobile(),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final from = tester.getCenter(find.byType(TouchReorderHandle).first);
      final p2 = tester.getCenter(find.byType(AppFlowyRichText).at(3));
      await _longPressDrag(tester, from, Offset(from.dx, p2.dy + 8));
      expect(_texts(state).first, isNot('T1'),
          reason: 'checklist row should leave the top, past P1/B1');
      expect(_texts(state).last, 'T1');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final type in ['todo_list', 'bulleted_list']) {
    testWidgets('$type: drag preview starts exactly over its row (no jump)',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final s = await _pump(tester, type, ['A', 'B', 'C']);
        final row = tester.getRect(find.byType(AppFlowyRichText).at(1));
        final grip = tester.getCenter(find.byType(TouchReorderHandle).at(1));
        final g = await tester.startGesture(grip);
        await tester.pump(const Duration(milliseconds: 700));
        // A small first move so the drag has started and the preview is laid out.
        await g.moveBy(const Offset(0, 4));
        await tester.pump(const Duration(milliseconds: 50));

        final preview = tester.getRect(find.byType(ReorderDragFeedback));
        expect(preview.top, closeTo(tester.getTopLeft(find.byKey(s.document.root.children[1].key)).dy + 4, 3),
            reason: 'preview must sit on its row, not jump below the finger');
        expect(preview.left,
            closeTo(tester.getTopLeft(find.byKey(s.document.root.children[1].key)).dx, 1),
            reason: 'axis is locked vertical, so x stays on the row');
        expect(row.top, isNonNegative);
        await g.up();
        await tester.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  group('indent', () {
    Node n(String type, String t) => Node(type: type, attributes: {
          'delta': (Delta()..insert(t)).toJson(),
          if (type == 'todo_list') 'checked': false,
        });

    Future<EditorState> pumpNarrow(
      WidgetTester tester,
      List<Node> nodes, {
      double width = 393,
    }) async {
      final state = EditorState(document: Document.blank()..insert([0], nodes));
      final builders = buildStandardBlockComponentBuilderMap();
      for (final b in builders.values) {
        b.showActions = (_) => true;
        b.actionBuilder =
            (ctx, s) => BlockHoverActionHandle(node: ctx.node, state: s);
      }
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: state,
            blockComponentBuilders: builders,
            editorStyle: EditorStyle.mobile(
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('depth stops where the row would get too narrow',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // A chain of bullets: each swipe nests the LAST one deeper.
        final state = await pumpNarrow(tester, [
          for (var i = 0; i < 14; i++) n('bulleted_list', 'item $i'),
        ]);
        var refused = 0;
        var depth = 0;
        for (var i = 1; i < 14; i++) {
          // Indent item i as deep as the screen allows.
          final node = state.getNodeAtPath(_pathOf(state, 'item $i'))!;
          while (indentBlockNode(state, state.getNodeAtPath(_pathOf(state, 'item $i'))!)) {
            await tester.pumpAndSettle();
          }
          refused++;
          expect(node, isNotNull);
        }
        // Measure the deepest row that exists.
        var maxDepth = 0;
        void walk(Node x, int d) {
          if (d > maxDepth) maxDepth = d;
          for (final c in x.children) {
            walk(c, d + 1);
          }
        }
        for (final c in state.document.root.children) {
          walk(c, 0);
        }
        depth = maxDepth;
        expect(depth, greaterThanOrEqualTo(3),
            reason: 'a phone must fit several levels');
        expect(depth, lessThanOrEqualTo(8),
            reason: 'but not so many that rows collapse to a sliver');
        // Every rendered text row still has a usable width.
        for (final r in tester.widgetList<AppFlowyRichText>(find.byType(AppFlowyRichText))) {
          expect(r, isNotNull);
        }
        for (final e in find.byType(AppFlowyRichText).evaluate()) {
          final w = (e.renderObject as RenderBox).size.width;
          expect(w, greaterThanOrEqualTo(kMinIndentedRowWidth - 80),
              reason: 'text column must never collapse');
        }
        expect(refused, greaterThan(0));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('long text wraps INSIDE the indent (hanging indent)',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final state = await pumpNarrow(tester, [
          n('bulleted_list', 'parent'),
          n('todo_list',
              'this is a much longer checklist item that has to wrap onto several lines'),
        ]);
        final before = tester.getRect(find.byType(AppFlowyRichText).at(1));
        expect(indentBlockNode(state, state.document.root.children[1]), isTrue);
        await tester.pumpAndSettle();
        final after = tester.getRect(find.byType(AppFlowyRichText).at(1));
        expect(after.left, greaterThan(before.left + 20),
            reason: 'text column moves right by the indent');
        expect(after.right, closeTo(before.right, 1),
            reason: 'and the right edge stays put, so text re-wraps narrower');
        expect(after.width, lessThan(before.width - 20),
            reason: 'the wrapping column itself is narrower by the indent, so '
                'every wrapped line stays inside it');
        // The grip and checkbox are still on the FIRST line, not the last.
        final grip = tester.getCenter(find.byType(TouchReorderHandle).at(1));
        expect(grip.dy, lessThan(after.top + 30));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('every grip block type can be indented and outdented',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        for (final type in [
          'paragraph',
          'bulleted_list',
          'numbered_list',
          'todo_list',
          'heading',
          'quote',
        ]) {
          final state = await pumpNarrow(tester, [
            n('bulleted_list', 'parent'),
            n(type, 'child'),
          ]);
          expect(indentBlockNode(state, state.document.root.children[1]), isTrue,
              reason: '$type should indent');
          await tester.pumpAndSettle();
          expect(state.document.root.children.length, 1);
          expect(state.document.root.children.first.children.first.type, type);
          expect(outdentBlockNode(state, state.document.root.children.first.children.first), isTrue,
              reason: '$type should outdent');
          await tester.pumpAndSettle();
          expect(state.document.root.children.length, 2);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('two-finger swipe on a row indents / outdents it',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final state = await pumpNarrow(tester, [
          n('bulleted_list', 'one'),
          n('bulleted_list', 'two'),
          n('todo_list', 'three'),
        ]);
        Future<void> twoFinger(Offset at, double dx) async {
          final a = await tester.startGesture(at + const Offset(-20, 0), pointer: 11);
          final b = await tester.startGesture(at + const Offset(20, 0), pointer: 12);
          for (var i = 1; i <= 10; i++) {
            await a.moveBy(Offset(dx / 10, 0));
            await b.moveBy(Offset(dx / 10, 0));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await a.up();
          await b.up();
          await tester.pumpAndSettle();
        }

        // swipe right over "two" (1 level)
        await twoFinger(tester.getCenter(find.byType(AppFlowyRichText).at(1)), 50);
        expect(state.document.root.children.length, 2, reason: 'two nests under one');
        expect(state.document.root.children.first.children.length, 1);

        // swipe LEFT over the nested row -> back out
        await twoFinger(tester.getCenter(find.byType(AppFlowyRichText).at(1)), -50);
        expect(state.document.root.children.length, 3);

        // a long swipe right over "three" (a checklist) nests it 1 level under
        // "two"; the second level is refused (nothing above it to nest under).
        await twoFinger(tester.getCenter(find.byType(AppFlowyRichText).at(2)), 130);
        expect(state.document.root.children.length, 2);
        expect(state.document.root.children[1].children.single.type, 'todo_list');

        // swiping left at top level is a refused no-op, not a crash
        await twoFinger(tester.getCenter(find.byType(AppFlowyRichText).at(0)), -60);
        expect(state.document.root.children.length, 2);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a ONE-finger horizontal drag on the caret row never indents',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final state = await pumpNarrow(tester, [
          n('bulleted_list', 'one'),
          n('bulleted_list', 'two'),
        ]);
        // Caret in the row being dragged: the drag belongs to the caret.
        state.selection =
            Selection.collapsed(Position(path: [1], offset: 0));
        await tester.pumpAndSettle();
        final at = tester.getCenter(find.byType(AppFlowyRichText).at(1));
        final g = await tester.startGesture(at);
        for (var i = 0; i < 10; i++) {
          await g.moveBy(const Offset(8, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await tester.pumpAndSettle();
        expect(state.document.root.children.length, 2);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('keyboard: Tab / Shift+Tab and Ctrl+] / Ctrl+[', (tester) async {
      final state = await pumpNarrow(tester, [
        n('bulleted_list', 'a'),
        n('bulleted_list', 'b'),
        n('bulleted_list', 'c'),
      ], width: 900);
      Future<void> run(CommandShortcutEvent e) async {
        final r = e.handler(state);
        expect(r, KeyEventResult.handled);
        await tester.pumpAndSettle();
      }

      state.selection = Selection.collapsed(Position(path: [1]));
      await run(indentCommand);
      expect(state.document.root.children.length, 2, reason: 'Tab indents b under a');

      state.selection = Selection.collapsed(Position(path: [1]));
      await run(indentBracketCommand);
      expect(state.document.root.children.length, 1, reason: 'Ctrl+] indents c too');

      state.selection = Selection.collapsed(Position(path: [0, 1]));
      await run(outdentBracketCommand);
      expect(state.document.root.children.length, 2, reason: 'Ctrl+[ outdents');

      state.selection = Selection.collapsed(Position(path: [0, 0]));
      await run(outdentCommand);
      expect(state.document.root.children.length, 3, reason: 'Shift+Tab outdents');
    });
  });

  _gutterReorderTests();
}

/// Every row type can be picked up by HOLDING the page's left margin beside it
/// (no visible grip, no hit area over the row itself).
void _gutterReorderTests() {
  Node text(String type, String t, [Map<String, Object> extra = const {}]) =>
      Node(type: type, attributes: {
        'delta': (Delta()..insert(t)).toJson(),
        ...extra,
      });

  Future<EditorState> pump(
    WidgetTester tester,
    List<Node> nodes, {
    double margin = 24,
  }) async {
    final state = EditorState(
      document: Document.blank()..insert([0], nodes),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: state,
          editorStyle: EditorStyle.mobile(
            padding: EdgeInsets.symmetric(horizontal: margin),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return state;
  }

  /// A point in the margin, level with the middle of [block].
  Offset gutterOf(WidgetTester tester, Node block) {
    final rect = tester.getRect(find.byKey(block.key));
    return Offset(rect.left - 12, rect.center.dy);
  }

  List<String> types(EditorState s) =>
      s.document.root.children.map((n) => n.type).toList();

  group('hold the left margin to drag any block (touch)', () {
    for (final type in ['paragraph', 'heading', 'quote']) {
      testWidgets('$type: hold beside it and drag reorders', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final s = await pump(tester, [
            text(type, 'A', type == 'heading' ? {'level': 1} : const {}),
            text('paragraph', 'B'),
            text('paragraph', 'C'),
          ]);
          final from = gutterOf(tester, s.document.root.children.first);
          final last = gutterOf(tester, s.document.root.children.last);
          await _longPressDrag(tester, from, last + const Offset(0, 30));
          expect(_texts(s), ['B', 'C', 'A']);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('nothing is drawn: no grip widget, no drag icon',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pump(tester, [text('paragraph', 'A'), text('paragraph', 'B')]);
        expect(find.byType(TouchReorderHandle), findsNothing);
        expect(find.byIcon(Icons.drag_indicator), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('holding ON the text does not move the row', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final s = await pump(tester, [
          text('paragraph', 'Alpha'),
          text('paragraph', 'Bravo'),
          text('paragraph', 'Charlie'),
        ]);
        final rect = tester.getRect(find.byType(AppFlowyRichText).first);
        final onText = Offset(rect.left + 6, rect.center.dy);
        final last = tester.getCenter(find.byType(AppFlowyRichText).last);
        await _longPressDrag(tester, onText, last + const Offset(0, 30));
        expect(_texts(s), ['Alpha', 'Bravo', 'Charlie']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a tap in the margin, and a quick swipe, move nothing',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final s = await pump(tester, [
          text('paragraph', 'A'),
          text('paragraph', 'B'),
          text('paragraph', 'C'),
        ]);
        final from = gutterOf(tester, s.document.root.children.first);
        await tester.tapAt(from);
        await tester.pumpAndSettle();
        // Moves before the hold completes: a scroll / swipe, not a pick-up.
        final g = await tester.startGesture(from);
        await g.moveTo(from + const Offset(0, 80));
        await tester.pump(const Duration(milliseconds: 700));
        await g.up();
        await tester.pumpAndSettle();
        expect(_texts(s), ['A', 'B', 'C']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('no margin (zero padding) means no gutter', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final s = await pump(tester, [text('paragraph', 'A')], margin: 0);
        expect(
          gutterReorderTarget(
            s,
            tester.getTopLeft(find.byType(AppFlowyRichText)) +
                const Offset(-1, 8),
          ),
          isNull,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a columns block is picked up whole, its blocks are not',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final columns = columnsNode(children: [
          columnNode(children: [paragraphNode(text: 'L')]),
          columnNode(children: [paragraphNode(text: 'R')]),
        ]);
        final s = await pump(tester, [
          text('paragraph', 'A'),
          columns,
          text('paragraph', 'Z'),
        ]);
        final kids = s.document.root.children;
        final rect = tester.getRect(find.byKey(kids[1].key));
        final beside = Offset(rect.left - 12, rect.center.dy);
        expect(gutterReorderTarget(s, beside)?.type, ColumnsBlockKeys.type);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('divider and table can be picked up; cells are not targets',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final table = TableNode.fromList<String>([
          ['a', 'b'],
          ['c', 'd'],
        ]).node;
        final s = await pump(tester, [
          Node(type: DividerBlockKeys.type),
          table,
          text('paragraph', 'Z'),
        ]);
        final kids = s.document.root.children;
        // Beside a table cell's row the TABLE is the target.
        final tableRect = tester.getRect(find.byKey(kids[1].key));
        final besideTable = Offset(tableRect.left - 12, tableRect.center.dy);
        expect(gutterReorderTarget(s, besideTable)?.type, TableBlockKeys.type);
        expect(
          gutterReorderTarget(s, gutterOf(tester, kids[0]))?.type,
          DividerBlockKeys.type,
        );

        await _longPressDrag(
          tester,
          gutterOf(tester, kids[0]),
          gutterOf(tester, kids[2]) + const Offset(0, 30),
        );
        expect(types(s), [TableBlockKeys.type, 'paragraph', DividerBlockKeys.type]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

Path _pathOf(EditorState s, String text) {
  Path? found;
  void walk(Node x) {
    if (x.delta?.toPlainText() == text) found = x.path;
    for (final c in x.children) {
      walk(c);
    }
  }
  walk(s.document.root);
  return found!;
}
