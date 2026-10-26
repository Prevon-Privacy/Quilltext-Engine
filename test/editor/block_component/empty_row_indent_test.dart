import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';

Future<EditorState> _pump(WidgetTester tester, Node empty) async {
  final state = EditorState(
    document: Document.blank()
      ..insert([0], [bulletedListNode(text: 'one'), empty]),
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
  await tester.pump(const Duration(milliseconds: 400));
  return state;
}

Future<void> _swipe(WidgetTester tester, Offset from, double dx) async {
  final g = await tester.startGesture(from);
  for (var i = 1; i <= 8; i++) {
    await g.moveBy(Offset(dx / 8, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  final kinds = <String, Node Function()>{
    'bullet': () => bulletedListNode(text: ''),
    'numbered': () => numberedListNode(delta: Delta()),
    'todo': () => todoListNode(checked: false),
    'paragraph': () => paragraphNode(text: ''),
    // Looks empty (nothing to read) but holds only blanks.
    'bullet with a space': () => bulletedListNode(text: ' '),
    'todo with zero-width': () => todoListNode(
          checked: false,
          text: '\u200B',
        ),
  };
  for (final withCaret in [true, false]) {
    for (final e in kinds.entries) {
      for (final frac in [0.1, 0.5, 0.9]) {
        testWidgets(
            '${e.key} empty-looking, caret=$withCaret, swipe at ${(frac * 100).round()}%',
            (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          PlatformExtension.debugMobileOverride = true;
          try {
            final s = await _pump(tester, e.value());
            final box0 = s.getNodeAtPath([1])!.key.currentContext!
                .findRenderObject()! as RenderBox;
            if (withCaret) {
              // A real tap, like a finger: shows the caret handle overlay.
              await tester.tapAt(box0.localToGlobal(box0.size.center(Offset.zero)));
              await tester.pump(const Duration(milliseconds: 600));
              expect(s.selection?.start.path, [1]);
            }
            final box = s.getNodeAtPath([1])!.key.currentContext!
                .findRenderObject()! as RenderBox;
            final p = box.localToGlobal(
                Offset(box.size.width * frac, box.size.height / 2));
            await _swipe(tester, p, 90);
            expect(s.document.root.children.length, 1,
                reason: 'empty row should nest under "one"');
          } finally {
            PlatformExtension.debugMobileOverride = null;
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }
    }
  }
}
