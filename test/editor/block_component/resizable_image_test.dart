import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

// A 1x1 PNG, so the source is a valid base64 image without any network.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

Widget _host({
  double width = 200,
  bool editable = true,
  bool selected = true,
  Alignment alignment = Alignment.center,
  double boxWidth = 400,
  ValueChanged<double>? onResize,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: boxWidth,
          child: ResizableImage(
            src: _png,
            width: width,
            editable: editable,
            selected: selected,
            alignment: alignment,
            onResize: onResize ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

double _imageBoxWidth(WidgetTester tester) {
  final state = tester.state<ResizableImageState>(find.byType(ResizableImage));
  return state.currentWidth;
}

void main() {
  group('grips', () {
    testWidgets('show while selected and editable', (tester) async {
      await tester.pumpWidget(_host());
      expect(find.byKey(const Key('image_grip_left')), findsOneWidget);
      expect(find.byKey(const Key('image_grip_right')), findsOneWidget);
    });

    testWidgets('only the free side shows for an aligned image',
        (tester) async {
      await tester.pumpWidget(_host(alignment: Alignment.centerLeft));
      expect(find.byKey(const Key('image_grip_left')), findsNothing);
      expect(find.byKey(const Key('image_grip_right')), findsOneWidget);
      await tester.pumpWidget(_host(alignment: Alignment.centerRight));
      expect(find.byKey(const Key('image_grip_left')), findsOneWidget);
      expect(find.byKey(const Key('image_grip_right')), findsNothing);
    });

    testWidgets('are absent when not selected', (tester) async {
      await tester.pumpWidget(_host(selected: false));
      expect(find.byKey(const Key('image_grip_left')), findsNothing);
      expect(find.byKey(const Key('image_grip_right')), findsNothing);
    });

    testWidgets('are absent in a read-only note', (tester) async {
      await tester.pumpWidget(_host(editable: false));
      expect(find.byKey(const Key('image_grip_left')), findsNothing);
    });
  });

  group('width', () {
    testWidgets('is capped by the block, never overflows', (tester) async {
      await tester.pumpWidget(_host(width: 1000, boxWidth: 300));
      expect(_imageBoxWidth(tester), 300);
      expect(tester.takeException(), isNull);
    });

    testWidgets('follows the width attribute when it changes', (tester) async {
      await tester.pumpWidget(_host(width: 200));
      expect(_imageBoxWidth(tester), 200);
      await tester.pumpWidget(_host(width: 120));
      expect(_imageBoxWidth(tester), 120);
    });

    testWidgets('has a floor', (tester) async {
      await tester.pumpWidget(_host(width: 4));
      expect(_imageBoxWidth(tester), 30);
    });
  });

  group('resize drag', () {
    testWidgets('right grip grows a left-aligned image and commits once',
        (tester) async {
      final committed = <double>[];
      await tester.pumpWidget(_host(alignment: Alignment.centerLeft, onResize: committed.add));
      final grip = tester.getCenter(find.byKey(const Key('image_grip_right')));
      final g = await tester.startGesture(grip);
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(committed, isEmpty, reason: 'commit only when the finger lifts');
      // Live: 200 + 80 = 280 of 400 (70%): no snap point within 8dp.
      expect(_imageBoxWidth(tester), 280);
      expect(find.text('70%'), findsOneWidget);
      await g.up();
      await tester.pump();
      expect(committed, [280]);
      expect(find.text('70%'), findsNothing);
    });

    testWidgets('left grip shrinks a right-aligned image', (tester) async {
      final committed = <double>[];
      await tester.pumpWidget(
        _host(alignment: Alignment.centerRight, onResize: committed.add),
      );
      final grip = tester.getCenter(find.byKey(const Key('image_grip_left')));
      final g = await tester.startGesture(grip);
      await g.moveBy(const Offset(60, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(committed, [140]);
    });

    testWidgets('a centred image follows the finger at twice the rate',
        (tester) async {
      final committed = <double>[];
      await tester.pumpWidget(
        _host(alignment: Alignment.center, onResize: committed.add),
      );
      final grip = tester.getCenter(find.byKey(const Key('image_grip_right')));
      final g = await tester.startGesture(grip);
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(committed, [260]);
    });

    testWidgets('snaps to half, three quarters and full width',
        (tester) async {
      final committed = <double>[];
      await tester.pumpWidget(_host(alignment: Alignment.centerLeft, onResize: committed.add));
      final grip = tester.getCenter(find.byKey(const Key('image_grip_right')));
      // 200 + 104 = 304: within 8 of 300 (75% of 400).
      var g = await tester.startGesture(grip);
      await g.moveBy(const Offset(104, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(committed.last, 300);
    });

    testWidgets('cannot grow past the page or shrink below the floor',
        (tester) async {
      final committed = <double>[];
      await tester.pumpWidget(_host(alignment: Alignment.centerLeft, onResize: committed.add));
      final grip = tester.getCenter(find.byKey(const Key('image_grip_right')));
      var g = await tester.startGesture(grip);
      await g.moveBy(const Offset(900, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(committed.last, 400);

      await tester.pumpWidget(_host(width: 400, alignment: Alignment.centerLeft, onResize: committed.add));
      final grip2 = tester.getCenter(find.byKey(const Key('image_grip_right')));
      g = await tester.startGesture(grip2);
      await g.moveBy(const Offset(-900, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(committed.last, 30);
    });

    testWidgets('letting go where it started writes nothing', (tester) async {
      final committed = <double>[];
      await tester.pumpWidget(
        _host(alignment: Alignment.centerLeft, onResize: committed.add),
      );
      final grip = tester.getCenter(find.byKey(const Key('image_grip_right')));
      final g = await tester.startGesture(grip);
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.moveBy(const Offset(-40, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(committed, isEmpty);
    });
  });
}
