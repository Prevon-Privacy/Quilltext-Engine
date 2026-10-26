import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/plugins/blocks/columns/column_width_resizer.dart';

Node _col(List<String> lines, {double? weight}) => columnNode(
      children: [for (final l in lines) paragraphNode(text: l)],
      weight: weight,
    );

/// before / [columns of the given lines] / after
EditorState _state(
  List<List<String>> cols, {
  List<double?>? weights,
  Selection? selection,
}) {
  final columns = columnsNode(
    children: [
      for (var i = 0; i < cols.length; i++) _col(cols[i], weight: weights?[i]),
    ],
  );
  final state = EditorState(
    document: Document.blank()
      ..insert([
        0
      ], [
        paragraphNode(text: 'before'),
        columns,
        paragraphNode(text: 'after'),
      ]),
  );
  state.selection = selection;
  return state;
}

Node _columns(EditorState s) => s.getNodeAtPath([1])!;

List<List<String>> _text(EditorState s) => [
      for (final c in _columns(s).children)
        [for (final b in c.children) b.delta?.toPlainText() ?? ''],
    ];

void main() {
  group('insert', () {
    test('replaces an empty line and keeps a paragraph on each side', () {
      final state = EditorState(
        document: Document.blank()..insert([0], [paragraphNode()]),
      );
      final ok = ColumnsActions.insert(
        state,
        currentNode: state.getNodeAtPath([0])!,
        count: 3,
      );
      expect(ok, isTrue);
      expect(state.document.root.children.map((n) => n.type).toList(), [
        ParagraphBlockKeys.type,
        ColumnsBlockKeys.type,
        ParagraphBlockKeys.type,
      ]);
      expect(state.getNodeAtPath([1])!.children.length, 3);
      expect(state.selection,
          Selection.collapsed(Position(path: [1, 0, 0], offset: 0)));
    });

    test('goes after a line that has text, and adds only a trailing line', () {
      final state = EditorState(
        document: Document.blank()
          ..insert([
            0
          ], [
            paragraphNode(text: 'hello'),
            paragraphNode(text: 'next'),
          ]),
      );
      ColumnsActions.insert(state, currentNode: state.getNodeAtPath([0])!);
      expect(state.document.root.children.map((n) => n.type).toList(), [
        ParagraphBlockKeys.type,
        ColumnsBlockKeys.type,
        ParagraphBlockKeys.type,
      ]);
      expect(state.getNodeAtPath([1])!.children.length, 2);
    });

    test('refuses inside another columns block', () {
      final state = _state([
        ['a'],
        ['b'],
      ]);
      final inner = state.getNodeAtPath([1, 0, 0])!;
      expect(ColumnsActions.insert(state, currentNode: inner), isFalse);
      expect(_text(state), [
        ['a'],
        ['b'],
      ]);
    });
  });

  group('add and remove', () {
    test('adds a column at a position, up to the limit', () {
      final state = _state([
        ['a'],
        ['b'],
      ]);
      expect(ColumnsActions.addColumn(_columns(state), 1, state), isTrue);
      expect(_text(state), [
        ['a'],
        [''],
        ['b'],
      ]);
      ColumnsActions.addColumn(_columns(state), 3, state);
      ColumnsActions.addColumn(_columns(state), 4, state);
      expect(_columns(state).children.length, 5);
      expect(ColumnsActions.addColumn(_columns(state), 5, state), isFalse);
    });

    test('a new column takes the average width', () {
      final state = _state(
        [
          ['a'],
          ['b'],
        ],
        weights: [1, 3],
      );
      ColumnsActions.addColumn(_columns(state), 2, state);
      expect(columnWeightOf(_columns(state).children.last), 2);
    });

    test('removing one of three leaves two, caret in the left neighbour', () {
      final state = _state([
        ['a'],
        ['b'],
        ['c'],
      ]);
      expect(ColumnsActions.removeColumn(_columns(state), 1, state), isTrue);
      expect(_text(state), [
        ['a'],
        ['c'],
      ]);
      expect(state.selection,
          Selection.collapsed(Position(path: [1, 0, 0], offset: 1)));
    });

    test('removing one of two dissolves the block into the other column', () {
      final state = _state([
        ['a1', 'a2'],
        ['b1'],
      ]);
      ColumnsActions.removeColumn(_columns(state), 1, state);
      expect(
        state.document.root.children.map((n) => n.type).toList(),
        [
          ParagraphBlockKeys.type,
          ParagraphBlockKeys.type,
          ParagraphBlockKeys.type,
          ParagraphBlockKeys.type
        ],
      );
      expect(
        state.document.root.children.map((n) => n.delta!.toPlainText()),
        ['before', 'a1', 'a2', 'after'],
      );
      // Caret at the end of the last block that came out.
      expect(
          state.selection, Selection.collapsed(Position(path: [2], offset: 2)));
    });

    test('is one undo step', () {
      final state = _state([
        ['a'],
        ['b'],
        ['c'],
      ]);
      ColumnsActions.removeColumn(_columns(state), 0, state);
      state.undoManager.undo();
      expect(_text(state), [
        ['a'],
        ['b'],
        ['c'],
      ]);
    });
  });

  group('unwrap, move, equalize', () {
    test('unwrap puts every column\'s blocks in the page, left to right', () {
      final state = _state([
        ['a1', 'a2'],
        ['b1'],
      ]);
      expect(ColumnsActions.unwrap(_columns(state), state), isTrue);
      expect(
        state.document.root.children.map((n) => n.delta!.toPlainText()),
        ['before', 'a1', 'a2', 'b1', 'after'],
      );
    });

    test('move swaps neighbours and the caret follows its block', () {
      final state = _state(
        [
          ['a'],
          ['b'],
          ['c'],
        ],
        selection: Selection.collapsed(Position(path: [1, 0, 0], offset: 1)),
      );
      expect(ColumnsActions.moveColumn(_columns(state), 0, 2, state), isTrue);
      expect(_text(state), [
        ['b'],
        ['c'],
        ['a'],
      ]);
      expect(state.selection,
          Selection.collapsed(Position(path: [1, 2, 0], offset: 1)));
      ColumnsActions.moveColumn(_columns(state), 2, 0, state);
      expect(_text(state), [
        ['a'],
        ['b'],
        ['c'],
      ]);
    });

    test('move keeps each column\'s width with it', () {
      final state = _state(
        [
          ['a'],
          ['b'],
        ],
        weights: [1, 3],
      );
      ColumnsActions.moveColumn(_columns(state), 1, 0, state);
      expect(
        _columns(state).children.map(columnWeightOf).toList(),
        [3.0, 1.0],
      );
    });

    test('equalize resets the widths and says when there is nothing to do', () {
      final state = _state(
        [
          ['a'],
          ['b'],
        ],
        weights: [1, 3],
      );
      expect(ColumnsActions.isEqual(_columns(state)), isFalse);
      expect(ColumnsActions.equalize(_columns(state), state), isTrue);
      expect(ColumnsActions.isEqual(_columns(state)), isTrue);
      expect(ColumnsActions.equalize(_columns(state), state), isFalse);
    });
  });

  group('delete the block', () {
    test('removes it with its text and puts the caret on the next line', () {
      final state = _state([
        ['a'],
        ['b'],
      ]);
      expect(ColumnsActions.deleteBlock(_columns(state), state), isTrue);
      expect(
        state.document.root.children.map((n) => n.delta!.toPlainText()),
        ['before', 'after'],
      );
      expect(state.selection, Selection.collapsed(Position(path: [1])));
      state.undoManager.undo();
      expect(_text(state), [
        ['a'],
        ['b'],
      ]);
    });

    test('a page that held only the block keeps one empty line', () {
      final state = EditorState(
        document: Document.blank()
          ..insert([
            0
          ], [
            columnsNode(children: [
              _col(['a']),
              _col(['b'])
            ])
          ]),
      );
      ColumnsActions.deleteBlock(state.getNodeAtPath([0])!, state);
      expect(state.document.root.children.length, 1);
      expect(state.getNodeAtPath([0])!.type, ParagraphBlockKeys.type);
    });
  });

  group('repair', () {
    test('an empty column gets an empty paragraph', () {
      final state = EditorState(
        document: Document.blank()
          ..insert([
            0
          ], [
            columnsNode(children: [
              columnNode(children: []),
              _col(['b']),
            ]),
          ]),
      );
      final columns = state.getNodeAtPath([0])!;
      expect(ColumnsActions.needsRepair(columns), isTrue);
      expect(ColumnsActions.repair(columns, state), isTrue);
      expect(state.getNodeAtPath([0, 0, 0])!.type, ParagraphBlockKeys.type);
      expect(ColumnsActions.needsRepair(state.getNodeAtPath([0])!), isFalse);
    });

    test('a block with one column left dissolves', () {
      final state = EditorState(
        document: Document.blank()
          ..insert([
            0
          ], [
            columnsNode(children: [
              _col(['x', 'y'])
            ]),
          ]),
      );
      ColumnsActions.repair(state.getNodeAtPath([0])!, state);
      expect(
        state.document.root.children.map((n) => n.delta!.toPlainText()),
        ['x', 'y'],
      );
    });

    test('a block with no column left is removed, never the last block', () {
      final state = EditorState(
        document: Document.blank()..insert([0], [columnsNode(children: [])]),
      );
      ColumnsActions.repair(state.getNodeAtPath([0])!, state);
      expect(state.document.root.children.length, 1);
      expect(state.getNodeAtPath([0])!.type, ParagraphBlockKeys.type);
    });

    test('a healthy block is left alone', () {
      final state = _state([
        ['a'],
        ['b'],
      ]);
      expect(ColumnsActions.repair(_columns(state), state), isFalse);
    });
  });

  group('keys', () {
    test('backspace in an emptied column removes the column', () {
      final state = _state(
        [
          ['a'],
          [''],
          ['c'],
        ],
        selection: Selection.collapsed(Position(path: [1, 1, 0])),
      );
      final result = backspaceCommand.handler(state);
      expect(result, KeyEventResult.handled);
      expect(_text(state), [
        ['a'],
        ['c'],
      ]);
    });

    test('backspace at the start of a column\'s text moves nothing', () {
      final state = _state(
        [
          ['a'],
          ['text'],
        ],
        selection: Selection.collapsed(Position(path: [1, 1, 0])),
      );
      final result = backspaceCommand.handler(state);
      expect(result, KeyEventResult.handled);
      expect(_text(state), [
        ['a'],
        ['text'],
      ]);
    });

    test('backspace inside a column still merges its own lines', () {
      final state = _state(
        [
          ['one', 'two'],
          ['x'],
        ],
        selection: Selection.collapsed(Position(path: [1, 0, 1])),
      );
      backspaceCommand.handler(state);
      expect(_text(state), [
        ['onetwo'],
        ['x'],
      ]);
    });

    test('backspace on an empty line after the block removes just that line',
        () {
      final state = EditorState(
        document: Document.blank()
          ..insert([
            0
          ], [
            columnsNode(children: [
              _col(['a']),
              _col(['bcd'])
            ]),
            paragraphNode(),
          ]),
      );
      state.selection = Selection.collapsed(Position(path: [1]));
      final result = backspaceCommand.handler(state);
      expect(result, KeyEventResult.handled);
      expect(state.document.root.children.length, 1);
      expect(state.selection,
          Selection.collapsed(Position(path: [0, 1, 0], offset: 3)));
    });

    test(
        'backspace on a line with text after the block does not eat the '
        'columns', () {
      final state = EditorState(
        document: Document.blank()
          ..insert([
            0
          ], [
            columnsNode(children: [
              _col(['a']),
              _col(['b'])
            ]),
            paragraphNode(text: 'after'),
          ]),
      );
      state.selection = Selection.collapsed(Position(path: [1]));
      backspaceCommand.handler(state);
      expect(state.document.root.children.length, 2);
      expect(state.getNodeAtPath([0])!.children.length, 2);
    });

    test('delete at the end of a column\'s text moves nothing', () {
      final state = _state(
        [
          ['a'],
          ['b'],
        ],
        selection: Selection.collapsed(Position(path: [1, 0, 0], offset: 1)),
      );
      deleteCommand.handler(state);
      expect(_text(state), [
        ['a'],
        ['b'],
      ]);
    });
  });

  group('export', () {
    test('markdown keeps every column\'s text, left to right', () {
      final state = _state([
        ['a1'],
        ['b1', 'b2'],
      ]);
      final md = documentToMarkdown(state.document);
      expect(md.indexOf('a1'), lessThan(md.indexOf('b1')));
      expect(md, contains('b2'));
    });

    test('html lays the columns out in a flex row', () {
      final state = _state(
        [
          ['a1'],
          ['b1'],
        ],
        weights: [1, 2],
      );
      final html = documentToHTML(state.document);
      expect(html, contains('display:flex'));
      expect(html, contains('flex:2'));
      expect(html, contains('a1'));
      expect(html, contains('b1'));
    });
  });

  group('drag a column by its grip', () {
    test('the landing column is the one the pointer is over, or nearest', () {
      const rects = [
        Rect.fromLTWH(0, 0, 100, 50),
        Rect.fromLTWH(116, 0, 100, 50),
        Rect.fromLTWH(232, 0, 100, 50),
      ];
      expect(columnsDragTarget(rects, const Offset(50, 20)), 0);
      expect(columnsDragTarget(rects, const Offset(170, 20)), 1);
      expect(columnsDragTarget(rects, const Offset(300, 20)), 2);
      // In the gap, below, or far outside: the nearest.
      expect(columnsDragTarget(rects, const Offset(108, 20)), 0);
      expect(columnsDragTarget(rects, const Offset(180, 400)), 1);
      expect(columnsDragTarget(rects, const Offset(2000, 20)), 2);
      expect(columnsDragTarget(rects, const Offset(-500, 20)), 0);
    });

    test('stacked columns are told apart by height', () {
      const rects = [
        Rect.fromLTWH(0, 0, 300, 40),
        Rect.fromLTWH(0, 60, 300, 40),
        Rect.fromLTWH(0, 120, 300, 40),
      ];
      expect(columnsDragTarget(rects, const Offset(150, 70)), 1);
      expect(columnsDragTarget(rects, const Offset(150, 150)), 2);
    });

    testWidgets('press and hold the grip, slide over, release: it moves',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        t.view.physicalSize = const Size(900, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final state = _state(
          [
            ['one'],
            ['two'],
            ['three'],
          ],
          selection: Selection.collapsed(Position(path: [1, 0, 0])),
        );
        await t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: AppFlowyEditor(
              editorState: state,
              blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
              editorStyle: EditorStyle.mobile(),
            ),
          ),
        ));
        await t.pump(const Duration(milliseconds: 300));
        // The grip of the first column shows because the caret is in it.
        final grip = find.byIcon(Icons.more_horiz).first;
        final from = t.getCenter(grip);
        final target = t.getCenter(find.text('three', findRichText: true));
        final g = await t.startGesture(from);
        await t.pump(const Duration(milliseconds: 700));
        await g.moveTo(from + const Offset(150, 0));
        await t.pump(const Duration(milliseconds: 100));
        await g.moveTo(target);
        await t.pump(const Duration(milliseconds: 100));
        await g.up();
        await t.pump(const Duration(milliseconds: 400));
        expect(_text(state), [
          ['two'],
          ['three'],
          ['one'],
        ]);
        state.undoManager.undo();
        await t.pump(const Duration(milliseconds: 400));
        expect(_text(state), [
          ['one'],
          ['two'],
          ['three'],
        ]);
        await t.pump(const Duration(seconds: 3));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a short tap on the grip still opens the menu, not a drag',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        t.view.physicalSize = const Size(900, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final state = _state(
          [
            ['one'],
            ['two'],
          ],
          selection: Selection.collapsed(Position(path: [1, 0, 0])),
        );
        var opened = 0;
        await t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Provider<ColumnsMenuActions>.value(
              value: _CountingMenu(() => opened++),
              child: AppFlowyEditor(
                editorState: state,
                blockComponentBuilders:
                    buildStandardBlockComponentBuilderMap(),
                editorStyle: EditorStyle.mobile(),
              ),
            ),
          ),
        ));
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.byIcon(Icons.more_horiz).first);
        await t.pump(const Duration(milliseconds: 400));
        expect(opened, 1);
        expect(_text(state), [
          ['one'],
          ['two'],
        ]);
        await t.pump(const Duration(seconds: 3));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('layout', () {
    Future<EditorState> mount(
      WidgetTester tester,
      Size size,
      List<List<String>> cols, {
      List<double?>? weights,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = _state(cols, weights: weights);
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

    testWidgets('two columns sit side by side on a wide screen', (t) async {
      await mount(t, const Size(900, 800), [
        ['left text'],
        ['right text'],
      ]);
      final left = t.getTopLeft(find.text('left text', findRichText: true));
      final right = t.getTopLeft(find.text('right text', findRichText: true));
      expect((left.dy - right.dy).abs(), lessThan(2));
      expect(right.dx, greaterThan(left.dx + 100));
    });

    testWidgets('three columns stack on a phone', (t) async {
      await mount(t, const Size(360, 800), [
        ['one'],
        ['two'],
        ['three'],
      ]);
      final a = t.getTopLeft(find.text('one', findRichText: true));
      final b = t.getTopLeft(find.text('two', findRichText: true));
      final c = t.getTopLeft(find.text('three', findRichText: true));
      expect(b.dy, greaterThan(a.dy));
      expect(c.dy, greaterThan(b.dy));
      expect((a.dx - b.dx).abs(), lessThan(2));
    });

    testWidgets('widths follow the weights', (t) async {
      await mount(
        t,
        const Size(900, 800),
        [
          ['a'],
          ['b'],
        ],
        weights: [1, 3],
      );
      final cols = t.widgetList<ColumnBlockComponent>(
        find.byType(ColumnBlockComponent),
      );
      expect(cols.length, 2);
      final w0 = t.getSize(find.byType(ColumnBlockComponent).at(0)).width;
      final w1 = t.getSize(find.byType(ColumnBlockComponent).at(1)).width;
      expect(w1 / w0, closeTo(3, 0.05));
    });

    testWidgets('dragging a divider trades width, and undo restores it',
        (t) async {
      final state = await mount(t, const Size(900, 800), [
        ['a'],
        ['b'],
      ]);
      final before = t.getSize(find.byType(ColumnBlockComponent).at(0)).width;
      final divider = find.byType(ColumnWidthResizer);
      expect(divider, findsOneWidget);
      await t.drag(divider, const Offset(120, 0));
      await t.pumpAndSettle();
      final after = t.getSize(find.byType(ColumnBlockComponent).at(0)).width;
      expect(after, greaterThan(before + 80));
      final cols = _columns(state).children.toList();
      expect(
          columnWeightOf(cols[0]) + columnWeightOf(cols[1]), closeTo(2, 0.001));

      state.undoManager.undo();
      await t.pumpAndSettle();
      final undone = t.getSize(find.byType(ColumnBlockComponent).at(0)).width;
      expect(undone, closeTo(before, 1));
    });

    testWidgets('on a phone (mobile selection) a touch drag moves the divider',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final state = await mount(t, const Size(400, 800), [
          ['a'],
          ['b'],
        ]);
        await t.tapAt(t.getCenter(find.text('a', findRichText: true)));
        await t.pump(const Duration(milliseconds: 400));
        final before =
            t.getSize(find.byType(ColumnBlockComponent).at(0)).width;
        final divider = t.getCenter(find.byType(ColumnWidthResizer));
        final g = await t.startGesture(divider);
        for (var i = 1; i <= 8; i++) {
          await g.moveBy(const Offset(8, 0));
          await t.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await t.pump(const Duration(milliseconds: 400));
        final after = t.getSize(find.byType(ColumnBlockComponent).at(0)).width;
        expect(after, greaterThan(before + 40));
        final cols = _columns(state).children.toList();
        expect(columnWeightOf(cols[0]), greaterThan(columnWeightOf(cols[1])));
        await t.pump(const Duration(seconds: 3));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a divider never squeezes a column below its minimum',
        (t) async {
      await mount(t, const Size(900, 800), [
        ['a'],
        ['b'],
      ]);
      await t.drag(find.byType(ColumnWidthResizer), const Offset(2000, 0));
      await t.pumpAndSettle();
      final right = t.getSize(find.byType(ColumnBlockComponent).at(1)).width;
      expect(right, greaterThanOrEqualTo(70));
    });

    testWidgets('tapping the short column puts the caret in it', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        t.view.physicalSize = const Size(900, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final state = _state([
          [
            'a long first column that wraps onto many lines '
                'so it is much taller than the second one, and keeps going '
                'with more and more words until it has to wrap a good few '
                'times inside its narrow half of the page',
          ],
          ['short'],
        ]);
        await t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 560,
              child: AppFlowyEditor(
                editorState: state,
                blockComponentBuilders:
                    buildStandardBlockComponentBuilderMap(),
                editorStyle: EditorStyle.mobile(),
              ),
            ),
          ),
        ));
        await t.pumpAndSettle();
        final right = t.getCenter(find.text('short', findRichText: true));
        await t.tapAt(right);
        await t.pump(const Duration(milliseconds: 400));
        expect(state.selection?.start.path.take(2).toList(), [1, 1]);
        // Below the short column's text, beside the tall one: still column 2.
        await t.tapAt(right + const Offset(0, 70));
        await t.pump(const Duration(milliseconds: 400));
        expect(state.selection?.start.path.take(2).toList(), [1, 1]);
        final left = t.getTopLeft(
          find.textContaining('long first', findRichText: true),
        );
        await t.tapAt(left + const Offset(10, 8));
        await t.pump(const Duration(milliseconds: 400));
        expect(state.selection?.start.path.take(2).toList(), [1, 0]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a read-only note shows the columns without grips', (t) async {
      t.view.physicalSize = const Size(900, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final state = _state([
        ['a'],
        ['b'],
      ]);
      state.editable = false;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: state,
            editable: false,
            blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
            editorStyle: EditorStyle.mobile(),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      expect(find.text('a', findRichText: true), findsOneWidget);
      expect(find.text('b', findRichText: true), findsOneWidget);
    });

    testWidgets('a broken block repairs itself on screen', (t) async {
      t.view.physicalSize = const Size(900, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final state = EditorState(
        document: Document.blank()
          ..insert([
            0
          ], [
            columnsNode(children: [
              columnNode(children: []),
              _col(['b'])
            ]),
          ]),
      );
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: state,
            blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
            editorStyle: EditorStyle.mobile(),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(state.getNodeAtPath([0, 0, 0])?.type, ParagraphBlockKeys.type);
    });
  });
}

class _CountingMenu implements ColumnsMenuActions {
  _CountingMenu(this.onOpen);
  final VoidCallback onOpen;

  @override
  Future<void> showColumnsMenu(
    BuildContext context,
    ColumnsMenuRequest request,
  ) async => onOpen();
}
