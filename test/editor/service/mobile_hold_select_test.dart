import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/selection/mobile_magnifier.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';

// PREVON PATCH 24: hold-to-select must be smooth. These pin the behaviour the
// phone path depends on: the keyboard is left alone while the finger is down,
// a resting finger does not churn the selection, the held word stays the
// anchor, and a cancelled hold does not leave the drag stuck.

const _text = 'alpha bravo charlie delta echo foxtrot golf hotel india';

Future<EditorState> _pump(WidgetTester tester) async {
  final state = EditorState(
    document: Document.blank()
      ..insert([
        0,
      ], [
        Node(
          type: 'paragraph',
          attributes: {
            'delta': (Delta()..insert(_text)).toJson(),
          },
        ),
      ]),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: state,
          editorStyle: EditorStyle.mobile(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

/// Global centre of the character at [offset] in the first paragraph.
Offset _at(EditorState state, int offset) {
  final selectable = state.document.root.children.first.selectable!;
  final local = selectable.getCursorRectInPosition(
    Position(path: [0], offset: offset),
  )!;
  return selectable.transformRectToGlobal(local).center;
}

String _selected(EditorState state) {
  final s = state.selection!.normalized;
  return _text.substring(s.start.offset, s.end.offset);
}

bool? _doNotAttach(EditorState state) =>
    state.selectionExtraInfo?[selectionExtraInfoDoNotAttachTextService]
        as bool?;

/// Android path under test; the override must be cleared inside the test body
/// (the binding checks foundation debug vars before tearDown runs).
void androidTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    PlatformExtension.debugMobileOverride = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(tester);
      // Let the handle auto-dismiss and double-tap timers run out.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    } finally {
      PlatformExtension.debugMobileOverride = null;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  androidTest(
      'a word drag held at the bottom edge scrolls on and stays a range',
      (tester) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = EditorState(
      document: Document.blank()
        ..insert([
          0,
        ], [
          for (var i = 0; i < 80; i++)
            Node(
              type: 'paragraph',
              attributes: {
                'delta':
                    (Delta()..insert('line $i alpha bravo charlie')).toJson(),
              },
            ),
        ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: state,
            editorStyle: EditorStyle.mobile(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final first = state.document.root.children.first.selectable!;
    final start = first
        .transformRectToGlobal(
          first.getCursorRectInPosition(Position(path: [0], offset: 8))!,
        )
        .center;
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    // Drag to the bottom edge and rest there while the page scrolls.
    await g.moveTo(const Offset(120, 480));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final selection = state.selection!.normalized;
    expect(
      selection.isCollapsed,
      false,
      reason: 'scrolling under the finger must not collapse the word range',
    );
    expect(selection.start.path, [0], reason: 'the held word stays the anchor');
    expect(
      selection.end.path.first,
      greaterThan(3),
      reason: 'the selection follows the finger down the scrolled page',
    );
    expect(state.service.scrollService!.dy, greaterThan(0));
    await g.up();
    await tester.pumpAndSettle();
  });

  androidTest('hold selects the word, drag extends by whole words',
      (tester) async {
    final state = await _pump(tester);
    final g = await tester.startGesture(_at(state, 8)); // inside "bravo"
    await tester.pump(const Duration(milliseconds: 700));
    expect(_selected(state).trim(), 'bravo');

    await g.moveTo(_at(state, 22)); // inside "delta"
    await tester.pump(const Duration(milliseconds: 30));
    expect(_selected(state).trim(), 'bravo charlie delta');

    await g.moveTo(_at(state, 8)); // back to the held word
    await tester.pump(const Duration(milliseconds: 30));
    expect(_selected(state).trim(), 'bravo');

    await g.moveTo(_at(state, 2)); // before it: extends backwards
    await tester.pump(const Duration(milliseconds: 30));
    expect(_selected(state).trim(), 'alpha bravo');
    await g.up();
    await tester.pumpAndSettle();
  });

  androidTest('the keyboard stays detached while the finger is down',
      (tester) async {
    final state = await _pump(tester);
    final g = await tester.startGesture(_at(state, 8));
    await tester.pump(const Duration(milliseconds: 700));
    expect(_doNotAttach(state), true, reason: 'on hold start');

    await g.moveTo(_at(state, 22));
    await tester.pump(const Duration(milliseconds: 30));
    expect(_doNotAttach(state), true, reason: 'while dragging');

    await g.up();
    await tester.pumpAndSettle();
    expect(_doNotAttach(state), false, reason: 'attaches once, on release');
  });

  androidTest('a resting finger (sub-slop jitter) does not touch the selection',
      (tester) async {
    final state = await _pump(tester);
    final start = _at(state, 8);
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    // Rest on the left edge of "charlie" (offset 12), where the held word and
    // the next word meet, then wobble by less than the slop across it.
    final rest = _at(state, 12);
    await g.moveTo(rest);
    await tester.pump(const Duration(milliseconds: 30));

    var changes = 0;
    void count() => changes++;
    state.selectionNotifier.addListener(count);
    for (var i = 0; i < 40; i++) {
      await g.moveTo(rest + Offset(i.isEven ? 0.7 : -0.7, 0));
      await tester.pump(const Duration(milliseconds: 8));
    }
    state.selectionNotifier.removeListener(count);
    expect(changes, 0);
    await g.up();
    await tester.pumpAndSettle();
  });

  androidTest('a cancelled hold puts the gesture state back', (tester) async {
    final state = await _pump(tester);
    final g = await tester.startGesture(_at(state, 8));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(MobileMagnifier), findsOneWidget);

    await g.cancel();
    await tester.pumpAndSettle();
    expect(find.byType(MobileMagnifier), findsNothing);
    expect(_doNotAttach(state), false);
  });

  androidTest('the magnifier is pinned inside its area, aimed at the finger',
      (tester) async {
    const size = Size(72, 48);
    Future<void> pump(Offset offset) => tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              children: [
                MobileMagnifier(
                  size: size,
                  offset: offset,
                  bounds: const Size(400, 600),
                ),
              ],
            ),
          ),
        );

    // Finger at the very top-left corner: the lens must not leave the area.
    await pump(const Offset(2, 2));
    var rect = tester.getRect(find.byType(RawMagnifier));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));

    // Finger at the far right edge.
    await pump(const Offset(399, 300));
    rect = tester.getRect(find.byType(RawMagnifier));
    expect(rect.right, lessThanOrEqualTo(400));

    // Mid-screen: unchanged behaviour, lens sits above the finger.
    await pump(const Offset(200, 300));
    rect = tester.getRect(find.byType(RawMagnifier));
    expect(rect.center.dx, closeTo(200, 0.01));
    expect(rect.bottom, lessThan(300));
  });
}
