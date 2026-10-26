import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/service/selection/touch_drag_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PREVON PATCH 14 — the ONE touch drag-to-reorder grip shared by the checklist
/// row (`todo_list_block_component.dart`) and the generic block handle
/// (`block_hover_action.dart`).
///
/// Two defects it replaces (both were copy-pasted into the two handles):
///
///  * **Dead hit area.** The old handle was a `SizedBox(18)` around an
///    `OverflowBox(44)`. Flutter only hit-tests a child inside its PARENT's
///    bounds, so the 44px overflow never received a touch — the real target
///    was the 18px glyph, which a fingertip misses.
///  * **Row inflation / misalignment.** Making the target 44px tall for real
///    would grow every row by ~20px, so the grip sat on a different vertical
///    centre from the checkbox and the first line of text.
///
/// Instead this is a REAL box — [kTouchHandleWidth] × [kTouchHandleHeight] —
/// sized to the first line of body text (the 1.6 line height of the note body
/// is ~24–26px), so it never makes a row taller and its centre is the line's
/// centre. The glyph is placed at [kTouchHandleGlyphTop] so it shares a centre
/// with the app's checklist checkbox (18px box centred in a 24px hit box + 3px
/// `checkboxTopOffset`, see `NoteChecklistBox`).
const double kTouchHandleWidth = 20;
const double kTouchHandleHeight = 24;
const double kTouchHandleGlyphSize = 16;

/// Top offset of the 18px glyph inside the [kTouchHandleHeight] box:
/// (24 - 18) / 2 + 1.5, i.e. the same optical centre as the checklist
/// checkbox, which is nudged 3px down inside a 24px hit box.
const double kTouchHandleGlyphTop = 4;

/// The engine's default block `padding` (4px top/bottom) that the action
/// wrapper sits outside of.
const double kTouchBlockTopPadding = 4;

/// Invisible overlay grip box laid over a row's leading bullet / checkbox.
const double kTouchOverlayWidth = 36;
const double kTouchOverlayHeight = 30;

/// A persistent, long-press-activated drag grip (no hover on touch; a plain
/// tap must still place the caret and a scroll must still scroll).
class TouchReorderHandle extends StatelessWidget {
  const TouchReorderHandle({
    super.key,
    required this.data,
    required this.color,
    required this.feedback,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.onIndent,
    this.onOutdent,
    this.invisible = false,
  });

  /// Invisible overlay mode: no glyph, fills whatever box it is given, and is
  /// hit-test translucent so a tap still reaches the checkbox / bullet under
  /// it while a long-press or swipe on it drags / indents the row.
  final bool invisible;

  /// Payload of the drag (the dragged node).
  final Node data;

  /// Glyph color.
  final Color color;

  final Widget feedback;
  final VoidCallback onDragStarted;
  final DragUpdateCallback onDragUpdate;

  /// Called when the gesture ends (possibly twice — must be idempotent).
  final void Function({required bool dropped}) onDragEnd;

  /// Optional: a quick horizontal swipe on the grip (right = indent, left =
  /// outdent). The touch editor leaves these null: `TwoFingerIndentDetector`
  /// owns swipes everywhere, grip included, and a second recognizer here would
  /// compete with it. When set:
  /// (A long-press-and-hold still reorders; the two never overlap because the
  /// swipe wins as soon as the finger travels before the hold completes.)
  ///
  /// Return true when the document changed; a refused swipe (nothing above to
  /// nest under, already at the deepest level that fits the screen, already at
  /// the top level) gives a firm haptic bump instead of silently doing nothing.
  final bool Function()? onIndent;
  final bool Function()? onOutdent;

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(
      Icons.drag_indicator,
      size: kTouchHandleGlyphSize,
      color: color,
    );
    final grip = invisible
        ? const SizedBox.expand()
        : SizedBox(
            width: kTouchHandleWidth,
            height: kTouchHandleHeight,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: kTouchHandleGlyphTop),
                child: glyph,
              ),
            ),
          );
    // PATCH 11: claim the pointer before the editor's document-wide mobile
    // selection recognizers see it (see touch_drag_gate.dart). Without this,
    // Android's whole-document pan recognizer wins the arena on the slightest
    // tremor during the long-press hold and the handle never drags.
    if (onIndent == null && onOutdent == null) return _reorderable(grip);
    return GestureDetector(
      behavior:
          invisible ? HitTestBehavior.translucent : HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        final bool? changed;
        if (v > 200) {
          changed = onIndent?.call();
        } else if (v < -200) {
          changed = onOutdent?.call();
        } else {
          return;
        }
        if (changed == false) HapticFeedback.mediumImpact();
      },
      child: _reorderable(grip),
    );
  }

  Widget _reorderable(Widget grip) {
    return Listener(
      behavior:
          invisible ? HitTestBehavior.translucent : HitTestBehavior.opaque,
      onPointerDown: (event) => TouchDragHandleGate.claim(event.pointer),
      onPointerUp: (event) => TouchDragHandleGate.release(event.pointer),
      onPointerCancel: (event) => TouchDragHandleGate.release(event.pointer),
      child: LongPressDraggable<Node>(
        data: data,
        // The whole 28x24 box is the target, not just the painted glyph.
        hitTestBehavior:
            invisible ? HitTestBehavior.translucent : HitTestBehavior.opaque,
        // Preview starts exactly over the source row (no jump) and slides
        // vertically only, like a list reorder.
        dragAnchorStrategy: rowAnchoredDragAnchor(data),
        axis: Axis.vertical,
        hapticFeedbackOnStart: true,
        onDragStarted: onDragStarted,
        onDragUpdate: onDragUpdate,
        onDragEnd: (_) => onDragEnd(dropped: true),
        // There is no DragTarget, so Flutter reports EVERY drop as "cancelled",
        // and it only calls `onDragEnd` while this State is still mounted. If
        // the row rebuilds mid-drag (a selection change does that), `onDragEnd`
        // is skipped and the reorder was lost. Treat this as the drop too; the
        // callers' finish handlers are idempotent (guarded by `wasActive`).
        onDraggableCanceled: (_, __) => onDragEnd(dropped: true),
        feedback: feedback,
        childWhenDragging: Opacity(opacity: 0.3, child: grip),
        child: grip,
      ),
    );
  }
}
