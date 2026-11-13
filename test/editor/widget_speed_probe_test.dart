// What the editor costs on the UI thread, with widgets: open a long note, type a
// key, scroll. Times `tester.pump` (build + layout + paint, no GPU raster), so it
// is a floor for a frame, not the frame itself. It prints WIDGET_SPEED lines to
// compare a change before and after; the asserts are loose ceilings against an
// order-of-magnitude regression, never a tight budget (machines differ).
// test-shape-ok: one probe per scenario, each loop is a frame sample for a timing, not a repeated case
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

EditorState _note(int blocks, {bool rich = false}) => EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          for (var i = 0; i < blocks; i++)
            if (rich && i % 3 == 0)
              headingNode(level: 2, text: 'Heading $i')
            else if (rich && i % 3 == 1)
              todoListNode(checked: i % 2 == 0, text: 'Task $i with words')
            else
              paragraphNode(
                  text: 'Paragraph $i with some words to lay out in a line '
                      'that is long enough to wrap onto a second line here.'),
        ]),
    )..disableSealTimer = true;

Future<void> _show(WidgetTester tester, EditorState state) async {
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: AppFlowyEditor(editorState: state)),
  ));
}

double _ms(Stopwatch sw, int n) => sw.elapsedMicroseconds / n / 1000;

void main() {
  for (final blocks in [300, 2000]) {
    testWidgets('open a $blocks-block note, then type and scroll',
        (tester) async {
      final state = _note(blocks, rich: true);
      final open = Stopwatch()..start();
      await _show(tester, state);
      await tester.pumpAndSettle();
      open.stop();
      // ignore: avoid_print
      print('WIDGET_SPEED open $blocks blocks: ${open.elapsedMilliseconds} ms');

      state.selection = Selection.collapsed(Position(path: [5], offset: 5));
      await tester.pump();
      final node = state.getNodeAtPath([5])!;
      for (var i = 0; i < 10; i++) {
        await state.apply(state.transaction
          ..insertText(node, 5 + i, 'x')
          ..afterSelection =
              Selection.collapsed(Position(path: [5], offset: 6 + i)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      const keys = 40;
      final typing = Stopwatch();
      for (var i = 0; i < keys; i++) {
        typing.start();
        await state.apply(state.transaction
          ..insertText(node, 15 + i, 'y')
          ..afterSelection =
              Selection.collapsed(Position(path: [5], offset: 16 + i)));
        await tester.pump(const Duration(milliseconds: 16));
        typing.stop();
      }
      final perKey = _ms(typing, keys);
      // ignore: avoid_print
      print(
          'WIDGET_SPEED key in $blocks blocks: ${perKey.toStringAsFixed(2)} ms/key');

      final scroll = Stopwatch();
      const frames = 40;
      final listFinder = find.byType(AppFlowyEditor);
      for (var i = 0; i < frames; i++) {
        scroll.start();
        await tester.drag(listFinder, const Offset(0, -150),
            warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 16));
        scroll.stop();
      }
      final perFrame = _ms(scroll, frames);
      // ignore: avoid_print
      print(
          'WIDGET_SPEED scroll in $blocks blocks: ${perFrame.toStringAsFixed(2)} ms/frame');

      expect(perKey, lessThan(60));
      expect(perFrame, lessThan(120));
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
