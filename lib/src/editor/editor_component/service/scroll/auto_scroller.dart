import 'package:prevon_quilltext_engine/src/flutter/scrollable_helpers.dart';
import 'package:flutter/material.dart' hide EdgeDraggingAutoScroller;

/// Desktop drag-select auto-scroll, in one place (px per 60 Hz frame; the scroller scales by real time).
/// The band is [kDesktopAutoScrollBand] px inside the viewport edge; speed climbs along `t^1.5` from
/// ~80 px/s at the band's inner edge to ~1200 px/s at [kDesktopAutoScrollOverDrag] px past the edge (the
/// pointer outside the window still drags on). Numbers follow the app's drag-reorder scroller
/// (72 px band, ~1080 px/s) and the reference editors (Monaco, Blink, CodeMirror: frame-driven, speed
/// grows with distance, keeps going while the pointer rests); untuned on a real mouse.
const double kDesktopAutoScrollBand = 48;
const double kDesktopAutoScrollOverDrag = kDesktopAutoScrollBand + 120;
const double kDesktopAutoScrollMinStep = 1.33;
const double kDesktopAutoScrollMaxStep = 20;
const double kDesktopAutoScrollExponent = 1.5;

abstract class AutoScrollerService {
  void startAutoScroll(
    Offset offset, {
    double edgeOffset = 200,
    AxisDirection? direction,
    Duration? duration,
  });

  void stopAutoScroll();
}

class AutoScroller extends EdgeDraggingAutoScroller
    implements AutoScrollerService {
  AutoScroller(
    super.scrollable, {
    super.onScrollViewScrolled,
    super.velocityScalar = _kDefaultAutoScrollVelocityScalar,
    super.minimumAutoScrollDelta = _kDefaultMinAutoScrollDelta,
    super.maxAutoScrollDelta = _kDefaultMaxAutoScrollDelta,
    super.animationDuration,
    super.overDragMax,
    super.frameLocked,
    super.rampExponent,
  });

  static const double _kDefaultAutoScrollVelocityScalar = 7;
  static const double _kDefaultMinAutoScrollDelta = 1.0;
  static const double _kDefaultMaxAutoScrollDelta = 20.0;

  Offset? lastOffset;
  Duration? lastDuration;
  double? lastEdgeOffset;
  AxisDirection? lastDirection;

  @override
  void startAutoScroll(
    Offset offset, {
    double edgeOffset = 200,
    AxisDirection? direction,
    Duration? duration,
  }) {
    lastOffset = offset;
    lastDuration = duration;
    lastEdgeOffset = edgeOffset;
    lastDirection = direction;
    if (direction != null && direction == AxisDirection.up) {
      return startAutoScrollIfNecessary(
        offset & Size(1, edgeOffset),
        duration: duration,
      );
    }

    final dragTarget = Rect.fromCenter(
      center: offset,
      width: edgeOffset,
      height: edgeOffset,
    );

    startAutoScrollIfNecessary(
      dragTarget,
      duration: duration,
    );
  }

  @override
  void stopAutoScroll() {
    lastOffset = null;
    lastDuration = null;
    lastEdgeOffset = null;
    lastDirection = null;
    super.stopAutoScroll();
  }

  void continueToAutoScroll() {
    if (lastOffset != null) {
      startAutoScroll(
        lastOffset!,
        edgeOffset: lastEdgeOffset ?? 200,
        direction: lastDirection,
        duration: lastDuration,
      );
    }
  }
}
