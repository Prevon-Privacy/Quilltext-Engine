import 'package:flutter/material.dart' hide EdgeDraggingAutoScroller;
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/src/flutter/scrollable_helpers.dart';

/// A scroll position whose `moveTo` finishes at once and moves nothing: the
/// shape of a zero-length animation, or of a viewport that has not been laid
/// out again yet.
class _StuckPosition extends ScrollPositionWithSingleContext {
  _StuckPosition({required super.physics, required super.context});

  int moveToCalls = 0;

  @override
  Future<void> moveTo(
    double to, {
    Duration? duration,
    Curve? curve,
    bool? clamp = true,
  }) {
    moveToCalls++;
    return Future<void>.value();
  }
}

class _StuckController extends ScrollController {
  _StuckPosition? stuck;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return stuck = _StuckPosition(physics: physics, context: context);
  }
}

void main() {
  testWidgets(
    'a step that moves nothing ends the auto-scroll instead of recursing '
    'inside one microtask turn',
    (tester) async {
      final controller = _StuckController();
      await tester.pumpWidget(
        MaterialApp(
          home: ListView(
            controller: controller,
            children: [
              for (var i = 0; i < 100; i++)
                SizedBox(height: 80, child: Text('$i')),
            ],
          ),
        ),
      );
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final scroller = EdgeDraggingAutoScroller(
        scrollable,
        velocityScalar: 7,
        animationDuration: Duration.zero,
      );

      // A target far below the viewport: every step wants to scroll.
      scroller.startAutoScrollIfNecessary(const Rect.fromLTWH(0, 5000, 10, 10));

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(scroller.scrolling, isFalse);
      expect(controller.stuck!.moveToCalls, inInclusiveRange(1, 4));
    },
  );

  testWidgets('a scroll that makes progress still reaches its target',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: controller,
          children: [
            for (var i = 0; i < 100; i++)
              SizedBox(height: 80, child: Text('$i')),
          ],
        ),
      ),
    );
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final scroller = EdgeDraggingAutoScroller(
      scrollable,
      velocityScalar: 7,
      animationDuration: const Duration(milliseconds: 5),
    );

    scroller.startAutoScrollIfNecessary(const Rect.fromLTWH(0, 3000, 10, 10));
    for (var i = 0; i < 300 && scroller.scrolling; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.offset, greaterThan(0));
    expect(scroller.scrolling, isFalse);
  });
}
