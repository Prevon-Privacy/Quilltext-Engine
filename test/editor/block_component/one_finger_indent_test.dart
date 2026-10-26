import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';

Future<EditorState> _pump(WidgetTester tester) async {
  final state = EditorState(
    document: Document.blank()
      ..insert([
        0
      ], [
        bulletedListNode(text: 'one'),
        bulletedListNode(text: 'two'),
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

Offset _center(EditorState s, List<int> path) {
  final box = s.getNodeAtPath(path)!.key.currentContext!.findRenderObject()!
      as RenderBox;
  return box.localToGlobal(box.size.center(Offset.zero));
}

Future<void> _swipe(WidgetTester tester, Offset from, double dx) async {
  final g = await tester.startGesture(from);
  for (var i = 1; i <= 8; i++) {
    await g.moveBy(Offset(dx / 8, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  // Bounded: a blinking mobile caret never lets pumpAndSettle return.
  await tester.pump(const Duration(milliseconds: 400));
}

Future<EditorState> _pumpDoc(
  WidgetTester tester,
  List<Node> nodes, {
  bool rtl = false,
}) async {
  final state = EditorState(document: Document.blank()..insert([0], nodes));
  await tester.pumpWidget(MaterialApp(
    builder: rtl
        ? (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!)
        : null,
    home: Scaffold(
      body: AppFlowyEditor(
        editorState: state,
        blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
        editorStyle: EditorStyle.mobile(),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
  return state;
}

/// Drags through [dxs] (cumulative x offsets), [gapMs] apart, then lifts.
Future<void> _drag(
  WidgetTester tester,
  Offset from,
  List<double> dxs, {
  int gapMs = 16,
}) async {
  final g = await tester.startGesture(from);
  for (final dx in dxs) {
    await g.moveTo(from + Offset(dx, 0));
    await tester.pump(Duration(milliseconds: gapMs));
  }
  await g.up();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform: swipe on a row without the caret indents it',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final state = await _pump(tester);
        state.selection = Selection.collapsed(Position(path: [0], offset: 0));
        await tester.pumpAndSettle();

        final row = _center(state, [1]);
        await _swipe(tester, row, 90);
        expect(state.document.root.children.length, 1);
        expect(state.getNodeAtPath([0, 0])?.delta?.toPlainText(), 'two');

        state.selection = Selection.collapsed(Position(path: [0], offset: 0));
        await tester.pumpAndSettle();
        await _swipe(tester, _center(state, [0, 0]), -90);
        expect(state.document.root.children.length, 2);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('$platform: swipe mid-row on an EMPTY row with caret indents',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      // The phone's selection service (its caret-drag is gate-aware); a desktop
      // host would otherwise pick the desktop one.
      PlatformExtension.debugMobileOverride = true;
      try {
        final state = await _pump(tester);
        final tx = state.transaction
          ..insertNode([2], todoListNode(checked: false));
        await state.apply(tx);
        await tester.pump(const Duration(milliseconds: 400));
        state.selection = Selection.collapsed(Position(path: [2], offset: 0));
        await tester.pump(const Duration(milliseconds: 400));

        await _swipe(tester, _center(state, [2]), 90);
        expect(state.document.root.children.length, 2);
        expect(state.getNodeAtPath([1, 0])?.delta?.isEmpty, isTrue);
        expect(state.selection, Selection.collapsed(Position(path: [1, 0])));

        await _swipe(tester, _center(state, [1, 0]), -90);
        expect(state.document.root.children.length, 3);
        expect(state.selection, Selection.collapsed(Position(path: [2])));
      } finally {
        PlatformExtension.debugMobileOverride = null;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('$platform: a short 30px swipe already indents one level',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final state = await _pump(tester);
        state.selection = Selection.collapsed(Position(path: [0], offset: 0));
        await tester.pump(const Duration(milliseconds: 400));
        await _swipe(tester, _center(state, [1]), 30);
        expect(state.getNodeAtPath([0, 0])?.delta?.toPlainText(), 'two');
        await _swipe(tester, _center(state, [0, 0]), -30);
        expect(state.document.root.children.length, 2);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('$platform: swipe from the far edge indents even with caret',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final state = await _pump(tester);
        state.selection = Selection.collapsed(Position(path: [1], offset: 0));
        await tester.pumpAndSettle();
        final y = _center(state, [1]).dy;
        await _swipe(tester, Offset(8, y), 90);
        expect(state.getNodeAtPath([0, 0])?.delta?.toPlainText(), 'two');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  group('swipe polish', () {
    setUp(() => PlatformExtension.debugMobileOverride = true);
    tearDown(() => PlatformExtension.debugMobileOverride = null);

    testWidgets('a slow multi-level swipe is ONE undo step', (tester) async {
      final state = await _pumpDoc(tester, [
        bulletedListNode(
          text: 'a',
          children: [bulletedListNode(text: 'b')],
        ),
        bulletedListNode(text: 'c'),
      ]);
      state.selection = Selection.collapsed(Position(path: [0], offset: 0));
      await tester.pump(const Duration(milliseconds: 400));
      // 100px = 2 levels, 120 ms between moves (past the 50 ms seal, under the 500 ms long-press).
      await _drag(tester, _center(state, [1]), [30, 70, 100], gapMs: 120);
      expect(state.document.root.children.length, 1, reason: 'c nested');
      expect(state.getNodeAtPath([0, 0, 0])?.delta?.toPlainText(), 'c',
          reason: state.document.root.toJson().toString());

      state.undoManager.undo();
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.document.root.children.length, 2,
          reason: 'one undo puts c back at the root');
      expect(state.getNodeAtPath([0])?.children.length, 1);
      // Let the history item's seal timer fire (and any it arms) before the end.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });

    testWidgets('dragging back after a refused level walks back exactly',
        (tester) async {
      final state = await _pumpDoc(tester, [
        bulletedListNode(text: 'a'),
        bulletedListNode(text: 'b'),
      ]);
      state.selection = Selection.collapsed(Position(path: [0], offset: 0));
      await tester.pump(const Duration(milliseconds: 400));
      // 100px asks for 2 levels but only 1 fits; back to 30px (1 level).
      await _drag(tester, _center(state, [1]), [30, 60, 100, 70, 30]);
      expect(state.getNodeAtPath([0, 0])?.delta?.toPlainText(), 'b',
          reason: 'still one level in, not walked back to the root');
    });

    testWidgets('right-to-left: swiping LEFT nests the row', (tester) async {
      final state = await _pumpDoc(
        tester,
        [bulletedListNode(text: 'a'), bulletedListNode(text: 'b')],
        rtl: true,
      );
      state.selection = Selection.collapsed(Position(path: [0], offset: 0));
      await tester.pump(const Duration(milliseconds: 400));
      await _drag(tester, _center(state, [1]), [-30, -60, -90]);
      expect(state.getNodeAtPath([0, 0])?.delta?.toPlainText(), 'b');
    });
  });
}
