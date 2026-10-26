import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/service/selection/touch_drag_gate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as fw;
import 'package:flutter/material.dart' hide Overlay, OverlayEntry;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// PREVON PATCH 17 — hold in the page's LEFT MARGIN beside a row and drag to
/// move that row, whatever kind of block it is (paragraph, heading, quote,
/// divider, image, table, list…).
///
/// The margin is the editor's own horizontal padding (`EditorStyle.padding`):
/// empty page, outside every block's box. Nothing is drawn there and nothing in
/// it is ever a tap target, so this adds no visible grip and no hit area on top
/// of text, images or table cells. A touch only becomes a drag when it
///
///  1. lands in that margin, at the height of a row, and
///  2. stays put for a long-press.
///
/// Anything else — a tap, a scroll, a swipe (which still indents / outdents via
/// `TwoFingerIndentDetector`), a long-press on text — is untouched: outside the
/// margin this recognizer never joins the gesture arena at all, and inside it
/// it yields the moment the finger moves before the hold completes.
///
/// A nested row (inside a list / paragraph) is reachable from the margin AND
/// from the indent space to its left. A block inside a table cell is never the
/// target: holding beside a table moves the table.
///
/// Touch pointers only: a mouse or trackpad never joins its recognizer (so it
/// is mounted by both selection services, for touch-screen laptops too).
class GutterReorderDetector extends StatefulWidget {
  const GutterReorderDetector({super.key, required this.child});

  final Widget child;

  @override
  State<GutterReorderDetector> createState() => _GutterReorderDetectorState();
}

class _GutterReorderDetectorState extends State<GutterReorderDetector> {
  @override
  Widget build(BuildContext context) {
    final editorState = context.read<EditorState>();
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _GutterDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_GutterDragRecognizer>(
          () => _GutterDragRecognizer(editorState),
          (recognizer) => recognizer.onStart = _onStart,
        ),
      },
      child: widget.child,
    );
  }

  Drag? _onStart(Offset position) {
    // ignore: avoid_print
    print('GUTTERDBG onStart $position');
    final editorState = context.read<EditorState>();
    final node = gutterReorderTarget(editorState, position);
    if (node == null) return null;
    final rowBox = node.key.currentContext?.findRenderObject();
    if (rowBox is! RenderBox || !rowBox.attached || !rowBox.hasSize) {
      return null;
    }
    final session = BlockReorderSession(editorState, node)..start();
    HapticFeedback.lightImpact();

    // The lifted row, pinned over the row it came from and sliding vertically
    // only (same look as the row grip's preview).
    final rowTopLeft = rowBox.localToGlobal(Offset.zero);
    final dy = ValueNotifier<double>(0);
    final entry = fw.OverlayEntry(
      builder: (_) => ValueListenableBuilder<double>(
        valueListenable: dy,
        builder: (_, dy, __) => Positioned(
          left: rowTopLeft.dx,
          top: rowTopLeft.dy + dy,
          child: IgnorePointer(
            child: ReorderDragFeedback(node: node, editorState: editorState),
          ),
        ),
      ),
    );
    fw.Overlay.of(context, rootOverlay: true).insert(entry);

    return _GutterDrag(
      session: session,
      startY: position.dy,
      onMove: (y) => dy.value = y,
      onDone: () {
        entry.remove();
        entry.dispose();
        dy.dispose();
      },
    );
  }
}

/// The row a hold at [global] would pick up, or null when [global] is not in a
/// row's left margin.
///
/// Public for tests.
Node? gutterReorderTarget(EditorState editorState, Offset global) {
  final box = editorState.renderBox;
  if (box == null || !box.attached || !box.hasSize) return null;
  final margin = editorState.editorStyle.padding.left;
  if (margin <= 0) return null;

  // The margin is outside every block's box: look the row up at the same
  // height, mid-width. Block boxes don't touch (rows carry vertical padding),
  // so also try just above / below.
  final midX = box.localToGlobal(Offset(box.size.width / 2, 0)).dx;
  Node? row;
  for (final dy in const [0.0, -4.0, 4.0]) {
    row = blockAtGlobalOffset(editorState, Offset(midX, global.dy + dy));
    if (row != null) break;
  }
  // Climb to a block that can move: a paragraph inside a table cell resolves
  // to the table itself, one inside a column to the columns block.
  while (row != null &&
      !(gutterReorderBlockTypes.contains(row.type) &&
          row.parent?.type != TableCellBlockKeys.type &&
          row.parent?.type != ColumnBlockKeys.type)) {
    row = row.parent;
  }
  if (row == null || row.parent == null) return null;

  double? leftOf(Node n) {
    final b = n.key.currentContext?.findRenderObject();
    if (b is! RenderBox || !b.attached || !b.hasSize) return null;
    return b.localToGlobal(Offset.zero).dx;
  }

  var top = row;
  while (top.parent != null && top.parent!.parent != null) {
    top = top.parent!;
  }
  final topLeft = leftOf(top);
  final rowLeft = leftOf(row);
  if (topLeft == null || rowLeft == null) return null;
  // [top-level row's margin .. this row's left edge): the margin, plus — for a
  // nested row — the indent space beside it.
  if (global.dx < topLeft - margin || global.dx >= rowLeft) return null;
  return row;
}

/// A [DelayedMultiDragGestureRecognizer] (what `LongPressDraggable` uses) that
/// only ever joins the arena for a touch that starts in a row's left margin.
class _GutterDragRecognizer extends DelayedMultiDragGestureRecognizer {
  _GutterDragRecognizer(this.editorState)
      : super(
          supportedDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.unknown,
          },
        );

  final EditorState editorState;

  @override
  void addPointer(PointerDownEvent event) {
    // ignore: avoid_print
    print(
        'GUTTERDBG addPointer pos=${event.position} kind=${event.kind} pad=${editorState.editorStyle.padding} target=${gutterReorderTarget(editorState, event.position)?.type} box=${editorState.renderBox?.size}');
    if (gutterReorderTarget(editorState, event.position) == null) return;
    // Keep the document-wide pan / long-press recognizers (caret drag, word
    // select) out of the arena for this finger so the hold is not raced.
    TouchDragHandleGate.claim(event.pointer);
    GestureBinding.instance.pointerRouter.addRoute(event.pointer, _release);
    super.addPointer(event);
  }

  void _release(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      TouchDragHandleGate.release(event.pointer);
      GestureBinding.instance.pointerRouter.removeRoute(
        event.pointer,
        _release,
      );
    }
  }
}

class _GutterDrag extends Drag {
  _GutterDrag({
    required this.session,
    required this.startY,
    required this.onMove,
    required this.onDone,
  });

  final BlockReorderSession session;
  final double startY;
  final void Function(double dy) onMove;
  final VoidCallback onDone;
  bool _done = false;

  @override
  void update(DragUpdateDetails details) {
    if (_done) return;
    onMove(details.globalPosition.dy - startY);
    session.update(details.globalPosition);
  }

  @override
  void end(DragEndDetails details) => _finish(dropped: true);

  @override
  void cancel() => _finish(dropped: false);

  void _finish({required bool dropped}) {
    if (_done) return;
    _done = true;
    session.finish(dropped: dropped);
    onDone();
  }
}
