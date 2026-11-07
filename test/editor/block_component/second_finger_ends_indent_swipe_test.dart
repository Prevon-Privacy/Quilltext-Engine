import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';

// A one-finger indent swipe that is already going ENDS when a second finger lands: a pinch or a second touch must not keep moving the
// row (the two-finger path never checked the direction of a swipe that began with one finger).

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

void main() {
  testWidgets(
      'a second finger landing ends the one-finger swipe: the row stays where it was',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    PlatformExtension.debugMobileOverride = true;
    try {
      final state = await _pump(tester);
      state.selection = Selection.collapsed(Position(path: [0], offset: 0));
      await tester.pumpAndSettle();

      final from = _center(state, [1]);
      final first = await tester.startGesture(from, pointer: 1);
      for (var i = 1; i <= 5; i++) {
        await first.moveBy(const Offset(9, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // 45 px right: "two" is now a child of "one".
      expect(state.document.root.children.length, 1);

      final second =
          await tester.startGesture(from + const Offset(60, 0), pointer: 2);
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 1; i <= 8; i++) {
        await first
            .moveBy(const Offset(-14, 0)); // back left, past where it began
        await tester.pump(const Duration(milliseconds: 16));
      }
      await first.up();
      await second.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.document.root.children.length, 1,
          reason:
              'the second finger must stop the swipe, not let it keep outdenting');
      expect(state.getNodeAtPath([0, 0])?.delta?.toPlainText(), 'two');
      await tester
          .pump(const Duration(seconds: 2)); // let the selection timers run out
    } finally {
      PlatformExtension.debugMobileOverride = null;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
