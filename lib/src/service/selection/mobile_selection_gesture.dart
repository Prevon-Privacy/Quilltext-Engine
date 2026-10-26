import 'dart:async';

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
  bool _isDoubleTap = false;
  Timer? _doubleTapTimer;
  int _tripleTapCount = 0;
  Timer? _tripleTapTimer;

  final kTripleTapTimeout = const Duration(milliseconds: 500);

  @override
  Widget build(BuildContext context) {
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
    if (_tripleTapCount == 2) {
      _tripleTapCount = 0;
      _tripleTapTimer?.cancel();
      _tripleTapTimer = null;
      if (widget.onTripleTapUp != null) {
        widget.onTripleTapUp!(tapDownDetails);
      }
    } else if (_isDoubleTap) {
      _isDoubleTap = false;
      _doubleTapTimer?.cancel();
      _doubleTapTimer = null;
      if (widget.onDoubleTapUp != null) {
        widget.onDoubleTapUp!(tapDownDetails);
      }
      _tripleTapCount++;
    } else {
      if (widget.onTapUp != null) {
        widget.onTapUp!(tapDownDetails);
      }

      _isDoubleTap = true;
      _doubleTapTimer?.cancel();
      _doubleTapTimer = Timer(kDoubleTapTimeout, () {
        _isDoubleTap = false;
        _doubleTapTimer = null;
      });

      _tripleTapCount = 1;
      _tripleTapTimer?.cancel();
      _tripleTapTimer = Timer(kTripleTapTimeout, () {
        _tripleTapCount = 0;
        _tripleTapTimer = null;
      });
    }
  }

  @override
  void dispose() {
    _doubleTapTimer?.cancel();
    _tripleTapTimer?.cancel();
    super.dispose();
  }
}
