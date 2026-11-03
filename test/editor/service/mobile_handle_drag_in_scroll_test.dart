import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';
import 'package:prevon_quilltext_engine/src/render/selection/mobile_basic_handle.dart';

// PREVON PATCH 32: a selection handle dragged inside a scrolling page (the Home Scratchpad) must move the handle, not
// scroll the page, even when the slide drifts up or down; a drag that starts elsewhere must still scroll the page.

const _text = 'alpha bravo charlie delta echo foxtrot golf hotel india';

void main() {
  testWidgets('a drifting handle drag moves the selection and not the page',
      (tester) async {
    PlatformExtension.debugMobileOverride = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = EditorState(
        document: Document.blank()
          ..insert([
            0
          ,], [
            Node(type: 'paragraph', attributes: {
              'delta': (Delta()..insert(_text)).toJson(),
            },),
          ]),
      );
      final page = ScrollController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: page,
            child: Column(children: [
              const SizedBox(height: 40),
              SizedBox(
                height: 300,
                child: AppFlowyEditor(
                  editorState: state,
                  editorStyle: EditorStyle.mobile(),
                ),
              ),
              const SizedBox(height: 1500),
            ],),
          ),
        ),
      ),);
      await tester.pumpAndSettle();

      // Hold on "bravo" to select it, then let go.
      final selectable = state.document.root.children.first.selectable!;
      Offset at(int offset) => selectable
          .transformRectToGlobal(selectable
              .getCursorRectInPosition(Position(path: [0], offset: offset))!,)
          .center;
      await tester.longPressAt(at(8));
      await tester.pumpAndSettle();
      final before = state.selection!.normalized;
      expect(before.isCollapsed, isFalse);

      final handle = find.byType(HandleDragDetector).last;
      final start = tester.getCenter(handle);
      final pageBefore = page.offset;
      // Mostly sideways, but 25 px down on the way: past the page's own 18 px scroll slop.
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(6, 25));
      await gesture.moveBy(const Offset(60, 0));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(page.offset, pageBefore, reason: 'the page must not scroll');
      expect(state.selection!.normalized.end.offset,
          greaterThan(before.end.offset),
          reason: 'the handle must have moved the end of the selection',);

      // A drag that starts on the page still scrolls it.
      await tester.dragFrom(const Offset(200, 650), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(page.offset, greaterThan(pageBefore));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    } finally {
      PlatformExtension.debugMobileOverride = null;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
