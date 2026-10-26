import 'package:flutter/gestures.dart';

/// PREVON PATCH 11 — lets a block-level touch drag handle (e.g. the
/// checklist reorder handle) win the gesture arena against the editor's own
/// document-wide [MobileSelectionGestureDetector] instead of losing to it.
///
/// On Android, [MobileSelectionGestureDetector] registers a whole-document
/// `PanGestureRecognizer` (used to extend a text selection by dragging) that
/// claims the arena the instant a touch travels past its slop distance —
/// well before a competing `LongPressGestureRecognizer` 500ms timer can fire.
/// Any natural hand tremor while holding a drag handle is enough for the
/// document's pan recognizer to win outright, so a plain `LongPressDraggable`
/// nested anywhere under it never gets a chance to start (the handle simply
/// never drags). This is invisible on iOS, where the document only competes
/// with a same-type `LongPressGestureRecognizer` and Flutter's arena default
/// (first entrant wins a sweep) happens to favour the deeper, earlier-added
/// recognizer — so the bug is Android-only but the guard is applied on both
/// platforms for robustness.
///
/// A drag handle marks the pointer it received via [claim] the instant its
/// own `Listener.onPointerDown` fires; because pointer-down dispatch visits
/// the deepest hit-test entry first, that happens strictly before the
/// document-wide recognizers (further up the tree) get the same event. Their
/// gesture-recognizer subclasses below check [isClaimed] in `addPointer` and
/// simply refuse to join the arena for that pointer, leaving the handle's own
/// recognizer uncontested.
class TouchDragHandleGate {
  TouchDragHandleGate._();

  static final Set<int> _claimedPointers = <int>{};

  static void claim(int pointer) => _claimedPointers.add(pointer);

  static void release(int pointer) => _claimedPointers.remove(pointer);

  static bool isClaimed(int pointer) => _claimedPointers.contains(pointer);

  /// Pointers that only the document-wide PAN recognizer must ignore (caret
  /// dragging / selection extending), leaving tap and long-press intact. Used
  /// by the one-finger indent swipe.
  static final Set<int> _panClaimed = <int>{};

  static void claimPan(int pointer) => _panClaimed.add(pointer);

  static void releasePan(int pointer) => _panClaimed.remove(pointer);

  static bool isPanClaimed(int pointer) => _panClaimed.contains(pointer);

  // ── finger counting (PATCH 14) ───────────────────────────────────────────
  // How many touches are currently down, INCLUDING pointers a claim keeps out
  // of the pan recognizer's arena (the one-finger indent swipe claims its
  // finger, so the recognizer alone would never see it and could not tell that
  // a second finger makes this a two-finger gesture). Entries expire so a
  // missed pointer-up can never leave the caret drag permanently disabled.
  static final Stopwatch _clock = Stopwatch()..start();
  static final Map<int, int> _fingersDownAt = <int, int>{};
  static const int _staleMs = 15000;

  static void noteFingerDown(int pointer) {
    _pruneStale();
    _fingersDownAt[pointer] = _clock.elapsedMilliseconds;
  }

  static void noteFingerUp(int pointer) => _fingersDownAt.remove(pointer);

  static int get fingersDown {
    _pruneStale();
    return _fingersDownAt.length;
  }

  static void _pruneStale() {
    final now = _clock.elapsedMilliseconds;
    _fingersDownAt.removeWhere((_, at) => now - at > _staleMs);
  }
}

/// Drop-in [PanGestureRecognizer] that stays out of the arena for any pointer
/// [TouchDragHandleGate] has claimed.
class GateAwarePanGestureRecognizer extends PanGestureRecognizer {
  GateAwarePanGestureRecognizer({super.supportedDevices});

  @override
  void addPointer(PointerDownEvent event) {
    // Every finger counts toward "two-finger gesture", even one a claim keeps
    // out of this arena.
    TouchDragHandleGate.noteFingerDown(event.pointer);
    if (TouchDragHandleGate.isClaimed(event.pointer) ||
        TouchDragHandleGate.isPanClaimed(event.pointer)) {
      return;
    }
    super.addPointer(event);
  }

  /// PREVON PATCH 14 — a one-finger horizontal drag on text is the editor's
  /// "drag the caret" gesture, so it can never also mean "indent". A SECOND
  /// finger landing turns the touch into a two-finger gesture, which belongs to
  /// `TwoFingerIndentDetector`: reject this recognizer so no finger moves the
  /// caret (or extends a selection) under a two-finger swipe.
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (TouchDragHandleGate.fingersDown >= 2) {
      resolve(GestureDisposition.rejected);
    }
  }

  @override
  void stopTrackingPointer(int pointer) {
    TouchDragHandleGate.noteFingerUp(pointer);
    super.stopTrackingPointer(pointer);
  }
}

/// Drop-in [LongPressGestureRecognizer] that stays out of the arena for any
/// pointer [TouchDragHandleGate] has claimed.
class GateAwareLongPressGestureRecognizer extends LongPressGestureRecognizer {
  @override
  void addPointer(PointerDownEvent event) {
    if (TouchDragHandleGate.isClaimed(event.pointer)) return;
    super.addPointer(event);
  }
}
