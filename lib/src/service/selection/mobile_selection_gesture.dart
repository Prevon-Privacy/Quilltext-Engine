import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'touch_drag_gate.dart'; // PREVON PATCH 11

/// Because the flutter's [DoubleTapGestureRecognizer] will block the [TapGestureRecognizer]
/// for a while. So we need to implement our own GestureDetector.
class MobileSelectionGestureDetector extends StatefulWidget {
  const MobileSelectionGestureDetector({
    super.key,
    this.child,
    this.onTapUp,
    this.onDoubleTapUp,
    this.onTripleTapUp,
    this.onSecondaryTapUp,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.onLongPressMoveUpdate,
    this.onLongPressCancel,
  });

  @override
  State<MobileSelectionGestureDetector> createState() =>
      MobileSelectionGestureDetectorState();

  final Widget? child;

  final GestureTapUpCallback? onTapUp;
  final GestureTapUpCallback? onDoubleTapUp;
  final GestureTapUpCallback? onTripleTapUp;
  final GestureTapUpCallback? onSecondaryTapUp;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;

  /// The hold was taken away (system gesture, scroll takeover): no End follows.
  final GestureLongPressCancelCallback? onLongPressCancel;
}

class MobileSelectionGestureDetectorState
    extends State<MobileSelectionGestureDetector> {
  /// 1 after a single tap, 2 after a double tap; a third completes a triple.
  int _tapCount = 0;

  /// PREVON PATCH 25: where the previous tap lifted. A second tap far from it
  /// is a new tap elsewhere, not a double tap: two quick taps on different
  /// words used to select the second word instead of just placing the caret.
  Offset? _lastTapAt;

  /// PREVON PATCH 25: taps are timed by the clock the touch events carry, never
  /// by a Timer. A Timer keeps ticking while the UI thread is busy, and the
  /// first tap of a double tap is exactly when it is: it opens the keyboard,
  /// which resizes the page for 100 ms or more. The second tap's event then sat
  /// in the queue until the Timer had already ended the double-tap window, so
  /// the double tap was lost and read as two single taps. Event timestamps are
  /// stamped when the finger touches the glass, so a busy frame cannot change
  /// the gap.
  Duration? _lastUpAt; // when the previous tap lifted
  Duration? _thisUpAt; // when the tap being delivered lifted

  /// Synthetic events (tests, injected input) carry no stamp: a real monotonic
  /// clock stands in for them.
  final Stopwatch _fallbackClock = Stopwatch()..start();

  Duration _stampOf(PointerEvent e) =>
      e.timeStamp == Duration.zero ? _fallbackClock.elapsed : e.timeStamp;

  /// A deliberate double tap lands within a fingertip of the first tap.
  static const double kMobileDoubleTapSlop = 48;

  /// A touch double tap is allowed a little longer than the platform's 300 ms:
  /// the first tap's own work (keyboard, handles) delays the finger's second
  /// tap more than it does a mouse click.
  static const Duration kMobileDoubleTapTimeout = Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      // Runs before the recognizers see the same event (child-to-root order).
      onPointerUp: (e) => _thisUpAt = _stampOf(e),
      child: _gestures(),
    );
  }

  Widget _gestures() {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        GateAwarePanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<GateAwarePanGestureRecognizer>(
          // PREVON PATCH 11: gate-aware so a block-level touch drag handle
          // (e.g. the checklist reorder handle) can claim a pointer and keep
          // this whole-document recognizer out of the arena for it — see
          // touch_drag_gate.dart for why this is needed on Android.
          () => GateAwarePanGestureRecognizer(
            supportedDevices: {
              //   // https://docs.flutter.dev/release/breaking-changes/trackpad-gestures#for-gesture-interactions-not-suitable-for-trackpad-usage
              //   PointerDeviceKind.trackpad,
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
            },
          ),
          (recognizer) {
            recognizer
              ..dragStartBehavior = DragStartBehavior.down
              ..onStart = widget.onPanStart
              ..onUpdate = widget.onPanUpdate
              ..onEnd = widget.onPanEnd;
          },
        ),
        GateAwareLongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
                GateAwareLongPressGestureRecognizer>(
          () => GateAwareLongPressGestureRecognizer(), // PREVON PATCH 11
          (recognizer) {
            recognizer
              ..onLongPressStart = widget.onLongPressStart
              ..onLongPressEnd = widget.onLongPressEnd
              ..onLongPressMoveUpdate = widget.onLongPressMoveUpdate
              ..onLongPressCancel = widget.onLongPressCancel;
          },
        ),
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(),
          (recognizer) {
            // use tap up instead of tap down to avoid this gesture detector
            //  being responded before the pan gesture detector.
            recognizer.onTapUp = _tapDownDelegate;
            recognizer.onSecondaryTapUp = widget.onSecondaryTapUp;
          },
        ),
      },
      child: widget.child,
    );
  }

  void _tapDownDelegate(TapUpDetails tapDownDetails) {
    final now = _thisUpAt ?? _fallbackClock.elapsed;
    _thisUpAt = null;
    final lastAt = _lastUpAt;
    final lastPos = _lastTapAt;
    _lastUpAt = now;
    _lastTapAt = tapDownDetails.globalPosition;

    // Only a tap soon enough after, and near enough to, the previous one
    // continues a multi-tap; anything else starts over as a single tap.
    // (`now >= lastAt`: stamps from two clocks never mix into a false multi-tap.)
    final continues = lastAt != null &&
        lastPos != null &&
        now >= lastAt &&
        now - lastAt <= kMobileDoubleTapTimeout &&
        (tapDownDetails.globalPosition - lastPos).distance <=
            kMobileDoubleTapSlop;
    if (!continues) _tapCount = 0;
    _tapCount++;

    if (_tapCount == 2) {
      widget.onDoubleTapUp?.call(tapDownDetails);
    } else if (_tapCount == 3) {
      _tapCount = 0;
      widget.onTripleTapUp?.call(tapDownDetails);
    } else {
      widget.onTapUp?.call(tapDownDetails);
    }
  }
}
