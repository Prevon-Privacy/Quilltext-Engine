import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:prevon_quilltext_engine/src/service/selection/touch_drag_gate.dart';

/// PREVON PATCH 14 — swipe sideways across a row to indent / outdent it.
///
/// Two ways in, chosen so neither fights the editor's caret drag (on Android a
/// one-finger horizontal drag over text moves the caret):
///
///  * **Two fingers, anywhere on a row.** Unambiguous: the pan recognizer
///    rejects itself as soon as a second finger is down
///    (`GateAwarePanGestureRecognizer`, which counts fingers through
///    `TouchDragHandleGate` so a finger the one-finger mode claimed still
///    counts), so no finger moves the caret.
///  * **One finger, on a row the caret is NOT in**, an EMPTY row (even with
///    the caret in it: no text to drag a caret through), or from the 32px edge
///    zone: a horizontal swipe indents. A non-empty caret row keeps
///    caret-drag. The caret follows a moved row (`indent_block_node.dart`).
///
/// Behaviour:
///  * The row is the innermost block under the finger (or the midpoint of the
///    two fingers) when the gesture starts.
///  * Swipe right = indent, left = outdent. The first level comes after 24px
///    ([_leadIn]), then every [_stepDistance] of travel is one more level, so a longer swipe nests several levels; reversing direction
///    walks back. A light haptic tick marks each level.
///  * A swipe that can't go further (nothing above to nest under, already the
///    deepest level that fits the screen, already top level) gives one firm
///    bump instead of silently doing nothing.
///  * Only touch pointers count (real fingers, plus `unknown`-kind injected
///    input), so mouse / stylus / trackpad are untouched.
class TwoFingerIndentDetector extends StatefulWidget {
  const TwoFingerIndentDetector({super.key, required this.child});

  final Widget child;

  @override
  State<TwoFingerIndentDetector> createState() =>
      _TwoFingerIndentDetectorState();
}

/// Whether [block] shows no text: empty, or only whitespace and zero-width
/// characters. A block with no text delta (divider, image, table) is not blank.
bool _isBlankRow(Node block) {
  final delta = block.delta;
  if (delta == null) return false;
  return delta
      .toPlainText()
      .replaceAll(RegExp(r'[\s\u200B-\u200D\u2060\uFEFF]'), '')
      .isEmpty;
}

class _TwoFingerIndentDetectorState extends State<TwoFingerIndentDetector> {
  /// Travel (logical px) that is worth one indent level.
  static const double _stepDistance = 40;

  /// Head start on the FIRST level so a short, easy swipe (>= 24px) already
  /// moves the row; later levels still come every [_stepDistance].
  static const double _leadIn = 16;

  /// Travel before a two-finger touch is treated as an indent swipe at all.
  static const double _activateDistance = 18;

  final Map<int, Offset> _start = {};
  final Map<int, Offset> _now = {};

  bool _armed = false;
  bool _active = false;
  bool _ignore = false;
  Node? _target;
  int _appliedLevels = 0;
  bool _bumped = false;

  /// The wanted level count a step was refused at (nothing to nest under, too
  /// narrow...): not retried every move, and [_appliedLevels] only ever counts
  /// levels that really happened, so dragging back walks back exactly those.
  int? _refusedAt;

  /// One swipe = ONE undo step: while a gesture applies levels the history
  /// timer is held off and the item is sealed when the finger lifts.
  EditorState? _historyHeld;

  /// One-finger mode: the block under a single touch that started on a row
  /// the caret is NOT in (or in the far-edge zone). A horizontal swipe there
  /// indents / outdents instead of dragging the caret.
  bool _single = false;
  int? _singlePointer;

  /// Touches this close to the editor's left/right edge always swipe-indent,
  /// even on the row the caret is in.
  static const double _edgeZone = 32;

  void _reset() {
    final p = _singlePointer;
    if (p != null) TouchDragHandleGate.releasePan(p);
    _single = false;
    _singlePointer = null;
    _start.clear();
    _now.clear();
    _armed = false;
    _active = false;
    _ignore = false;
    _target = null;
    _appliedLevels = 0;
    _bumped = false;
    _refusedAt = null;
    _releaseHistory();
  }

  void _holdHistory(EditorState editorState) {
    if (_historyHeld != null) return;
    final stack = editorState.undoManager.undoStack;
    if (stack.isNonEmpty) stack.last.seal(); // start a fresh item
    editorState.disableSealTimer = true;
    _historyHeld = editorState;
  }

  void _releaseHistory() {
    final held = _historyHeld;
    if (held == null) return;
    _historyHeld = null;
    held.disableSealTimer = false;
    final stack = held.undoManager.undoStack;
    if (stack.isNonEmpty) stack.last.seal();
  }

  @override
  void dispose() {
    _releaseHistory();
    super.dispose();
  }

  void _onDown(PointerDownEvent e) {
    // A real finger is `touch`. Injected input (adb / scrcpy-style remote
    // control) and some vendor touch drivers report `unknown`; treat it as
    // touch too. Mouse, stylus and trackpad stay excluded.
    if (e.kind != PointerDeviceKind.touch &&
        e.kind != PointerDeviceKind.unknown) {
      return;
    }
    _start[e.pointer] = e.position;
    _now[e.pointer] = e.position;
    if (_start.length == 1) {
      _beginSingle(e);
    } else if (_start.length == 2) {
      _single = false;
      _armed = true;
      final a = _start.values.first;
      final b = _start.values.last;
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      _target = blockAtGlobalOffset(context.read<EditorState>(), mid);
    } else if (_start.length > 2) {
      _ignore = true; // three fingers: not ours
    }
  }

  void _beginSingle(PointerDownEvent e) {
    final editorState = context.read<EditorState>();
    final box = editorState.renderBox;
    // A touch that starts on a row's drag grip (the marker) swipes like the
    // edge does, caret or not: the grip only owns the long-press drag, its own
    // swipe never won the arena.
    var atEdge = TouchDragHandleGate.isClaimed(e.pointer);
    var probe = e.position;
    if (box != null && box.hasSize) {
      final x = box.globalToLocal(e.position).dx;
      atEdge = atEdge || x < _edgeZone || x > box.size.width - _edgeZone;
      // The edge zone is the page margin, outside every block's box: look the
      // row up at the same height, mid-width.
      if (atEdge) {
        probe = box.localToGlobal(
          Offset(box.size.width / 2, box.globalToLocal(e.position).dy),
        );
      }
    }
    final block = blockAtGlobalOffset(editorState, probe);
    if (block == null || !movableBlockTypes.contains(block.type)) return;
    // Only top-level rows and rows nested in a list / paragraph can indent;
    // e.g. a paragraph inside a table cell never can, so leave its caret drag.
    final parent = block.parent;
    if (parent != null &&
        parent.parent != null &&
        !indentableBlockTypes.contains(parent.type)) {
      return;
    }

    final sel = editorState.selection;
    final caretInRow = sel != null &&
        sel.start.path.length >= block.path.length &&
        sel.start.path.sublist(0, block.path.length).equals(block.path);

    // A blank row has no text to place a caret in, so a swipe anywhere on it
    // indents/outdents even with the caret there. Blank means nothing to read:
    // empty, or only spaces / zero-width marks (a row left with a stray space
    // looks empty and must swipe like one).
    final isEmptyRow = _isBlankRow(block);
    if (caretInRow && !atEdge && !isEmptyRow) return;

    _single = true;
    _singlePointer = e.pointer;
    _target = block;
    // Keep only the caret-dragging pan recognizer out of the arena; taps and
    // long-press (word select) still work, and vertical scrolling is a
    // separate Scrollable.
    TouchDragHandleGate.claimPan(e.pointer);
  }

  void _onSingleMove(PointerMoveEvent e) {
    final d = _now[e.pointer]! - _start[e.pointer]!;
    if (!_active) {
      if (d.dx.abs() >= _activateDistance && d.dx.abs() > 1.5 * d.dy.abs()) {
        _active = true;
      } else {
        return;
      }
    }
    _applyLevels(d.dx);
  }

  void _onMove(PointerMoveEvent e) {
    if (!_now.containsKey(e.pointer)) return;
    _now[e.pointer] = e.position;
    // A row is being picked up and dragged: sideways drift is not a swipe.
    if (reorderDraggingNode.value != null) return;
    if (_single && e.pointer == _singlePointer && _start.length == 1) {
      _onSingleMove(e);
      return;
    }
    if (!_armed || _ignore || _target == null || _start.length != 2) return;

    final ids = _start.keys.toList();
    final d0 = _now[ids[0]]! - _start[ids[0]]!;
    final d1 = _now[ids[1]]! - _start[ids[1]]!;
    final dx = (d0.dx + d1.dx) / 2;
    final dy = (d0.dy + d1.dy) / 2;
    final sameDirection = d0.dx * d1.dx > 0;

    if (!_active) {
      if (sameDirection &&
          dx.abs() >= _activateDistance &&
          dx.abs() > 2 * dy.abs()) {
        _active = true;
      } else {
        return;
      }
    }

    _applyLevels(dx);
  }

  void _applyLevels(double dx) {
    // Nesting moves a row toward the reading end: left in a right-to-left
    // layout, so mirror the swipe there.
    if (Directionality.of(context) == TextDirection.rtl) dx = -dx;
    final levels =
        ((dx.abs() + _leadIn) / _stepDistance).truncate() * (dx < 0 ? -1 : 1);
    if (levels == _refusedAt) return;
    _refusedAt = null;
    while (_appliedLevels != levels) {
      final indenting = levels > _appliedLevels;
      final editorState = context.read<EditorState>();
      final target = _target;
      if (target == null) return;
      _holdHistory(editorState);
      final moved = indenting
          ? tryIndentBlockNode(editorState, target)
          : tryOutdentBlockNode(editorState, target);
      if (moved == null) {
        if (!_bumped) {
          _bumped = true;
          HapticFeedback.mediumImpact();
        }
        // Don't retry this step every move.
        _refusedAt = levels;
        return;
      }
      _target = moved;
      _bumped = false;
      _appliedLevels += indenting ? 1 : -1;
      HapticFeedback.selectionClick();
    }
  }

  void _onUp(PointerEvent e) {
    TouchDragHandleGate.noteFingerUp(e.pointer);
    if (!_start.containsKey(e.pointer) && _start.isEmpty) return;
    _start.remove(e.pointer);
    _now.remove(e.pointer);
    if (_start.isEmpty) _reset();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: widget.child,
    );
  }
}
