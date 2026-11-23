// A double tap on a phone selects the word the person meant: not only when the two taps land on the exact
// same pixel, not when the finger drifts, and not when opening the keyboard scrolls the page in between.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';

// Every paragraph's words are different, so a tap that lands in the wrong paragraph is visible.
String _text(int i) => 'a$i  beta$i, gamma$i delta$i';

String? _selected(EditorState s) {
  final sel = s.selection;
  if (sel == null || sel.isCollapsed) return null;
  final n = sel.normalized;
  return s.getNodeAtPath(n.start.path)!.delta!.toPlainText().substring(
        n.start.offset,
        n.end.offset,
      );
}

Future<EditorState> _pump(WidgetTester tester) async {
  PlatformExtension.debugMobileOverride = true; // the phone selection service
  tester.view.physicalSize = const Size(400, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = EditorState(
    document: Document.blank()
      ..insert([
        0,
      ], [
        for (var i = 0; i < 60; i++) paragraphNode(text: _text(i)),
      ]),
  )..disableSealTimer = true;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: s,
          editorStyle: EditorStyle.mobile(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

/// Screen point over character [index] of paragraph [para].
Offset _at(EditorState s, int para, int index) {
  final n = s.getNodeAtPath([para])!;
  final r = n.selectable!
      .getRectsInSelection(
        Selection.single(
            path: [para], startOffset: index, endOffset: index + 1),
      )
      .first;
  return n.selectable!.localToGlobal(r.center);
}

void _case(String name, Future<void> Function(WidgetTester, EditorState) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester, await _pump(tester));
      await tester.pump(const Duration(seconds: 2)); // let the timers end
    } finally {
      PlatformExtension.debugMobileOverride = null;
    }
  });
}

void main() {
  _case('two taps 14 px apart on one word select that word', (tester, s) async {
    final a = _at(s, 3, 7); // inside "beta3"
    await tester.tapAt(a);
    await tester.pump(const Duration(milliseconds: 90));
    await tester.tapAt(a + const Offset(14, 3));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_selected(s), 'beta3');
  });

  _case('a slow, sloppy double tap (230 ms, 30 px off) still selects the word',
      (tester, s) async {
    final a = _at(s, 3, 7); // inside "beta3"
    await tester.tapAt(a);
    await tester.pump(const Duration(milliseconds: 230));
    await tester.tapAt(a + const Offset(-22, 20));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_selected(s), 'beta3');
  });

  _case('a double tap in the gap between words picks a neighbouring word',
      (tester, s) async {
    final a = _at(s, 3, 3); // second of the two spaces after "a3"
    await tester.tapAt(a);
    await tester.pump(const Duration(milliseconds: 90));
    await tester.tapAt(a);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_selected(s), anyOf('a3', 'beta3'));
  });

  _case('the page scrolling between the taps does not change the word',
      (tester, s) async {
    final a = _at(s, 3, 7); // "beta3"
    await tester.tapAt(a);
    // The keyboard opening resizes / scrolls the page under the finger.
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(scroll.position.pixels + 40);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(a);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_selected(s), 'beta3');
  });

  _case('a stalled UI thread between the taps does not lose the double tap',
      (tester, s) async {
    // The finger lifted 250 ms apart, but the second tap's events were only
    // delivered after the app stalled for a full second (keyboard opening).
    final a = _at(s, 3, 7); // "beta3"
    final p = TestPointer(1, PointerDeviceKind.touch);
    await tester
        .sendEventToBinding(p.down(a, timeStamp: const Duration(seconds: 10)));
    await tester.sendEventToBinding(
        p.up(timeStamp: const Duration(milliseconds: 10060)));
    await tester.pump(const Duration(seconds: 1)); // the stall
    await tester.sendEventToBinding(
        p.down(a, timeStamp: const Duration(milliseconds: 10250)));
    await tester.sendEventToBinding(
        p.up(timeStamp: const Duration(milliseconds: 10310)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_selected(s), 'beta3');
  });

  _case('two taps whose fingers lifted 700 ms apart are two single taps',
      (tester, s) async {
    final a = _at(s, 3, 7);
    final p = TestPointer(1, PointerDeviceKind.touch);
    await tester
        .sendEventToBinding(p.down(a, timeStamp: const Duration(seconds: 10)));
    await tester.sendEventToBinding(
        p.up(timeStamp: const Duration(milliseconds: 10060)));
    await tester.sendEventToBinding(
        p.down(a, timeStamp: const Duration(milliseconds: 10700)));
    await tester.sendEventToBinding(
        p.up(timeStamp: const Duration(milliseconds: 10760)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_selected(s), isNull);
  });

  _case('two quick taps on different words do not select a word',
      (tester, s) async {
    await tester.tapAt(_at(s, 3, 1));
    await tester.pump(const Duration(milliseconds: 90));
    await tester.tapAt(_at(s, 8, 18));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_selected(s), isNull);
  });
}
