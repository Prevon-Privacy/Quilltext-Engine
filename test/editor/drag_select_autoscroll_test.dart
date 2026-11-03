// Dragging a selection to the edge of the page scrolls it smoothly: a step every frame (it used to be 3 px,
// nothing, 3 px, nothing: a judder), faster the deeper the pointer goes into the edge band, and the
// selection follows without ever jumping back or moving its anchor.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

void main() {
  testWidgets(
      'drag-selecting at the bottom edge scrolls every frame and ramps with depth',
      (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          for (var i = 0; i < 200; i++)
            paragraphNode(
                text: 'Paragraph $i with some words to lay out and select.')
        ]),
    )..disableSealTimer = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AppFlowyEditor(
              editorState: s, editorStyle: EditorStyle.desktop())),
    ));
    await tester.pumpAndSettle();
    double dy() => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    final start =
        s.getNodeAtPath([2])!.renderBox!.localToGlobal(const Offset(40, 10));
    final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    final anchor = Position(path: [2], offset: s.selection?.start.offset ?? 0);
    var prevEnd = 0;
    Future<List<double>> hold(double y, int frames) async {
      await g.moveTo(Offset(start.dx + 200, y));
      await tester.pump(const Duration(milliseconds: 16));
      final steps = <double>[];
      var last = dy();
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        steps.add(dy() - last);
        last = dy();
        final sel = s.selection!;
        expect(sel.start.path, anchor.path, reason: 'the anchor stays put');
        final end = sel.end.path.first;
        expect(end, greaterThanOrEqualTo(prevEnd),
            reason: 'the selection never jumps back');
        prevEnd = end;
      }
      return steps;
    }

    // A real drag: the pointer travels, it does not teleport.
    for (var y = start.dy; y < 600; y += 40) {
      await g.moveTo(Offset(start.dx + 200, y));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Outside the 48 px band the pointer is the only thing that could scroll, and it must not: the caret
    // sitting near the edge (the old second scroll authority) used to creep the page here.
    final outside = await hold(620, 20);
    expect(outside.every((d) => d == 0), isTrue,
        reason: 'no scrolling outside the band: $outside');
    final shallow = await hold(672, 30);
    final deep =
        await hold(740, 30); // past the window edge keeps going, faster
    // Settled steps (skip the first frames while the speed eases in).
    expect(shallow.skip(3).every((d) => d > 0), isTrue,
        reason: 'a step on every frame, no dead frames: $shallow');
    expect(deep.skip(3).every((d) => d > 0), isTrue,
        reason: 'a step on every frame, no dead frames: $deep');
    double avg(List<double> v) =>
        v.skip(3).reduce((a, b) => a + b) / (v.length - 3);
    expect(avg(deep), greaterThan(avg(shallow) * 2),
        reason: 'deeper in the band (and past the edge) scrolls faster');

    await g.up();
    await tester.pump(const Duration(milliseconds: 100));
    final stopped = dy();
    await tester.pump(const Duration(milliseconds: 200));
    expect(dy(), stopped, reason: 'releasing the mouse stops the scroll');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
