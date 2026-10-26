// Drag a column by the grip above it to move it.
//
// Same idea as dragging a table row or column (`table_drag.dart`): a small
// controller says what is moving and where it would land, the columns block
// draws a tint on the moving column and a bar where it lands, and on release
// [ColumnsActions.moveColumn] makes ONE undoable edit. Touch uses press-and-hold
// then drag (a plain drag would fight the page's scroll); a mouse drags straight
// away. The grip's menu also has Move left / Move right, so nothing depends on
// the gesture.
//
// The landing column is found from where the pointer is on screen, against the
// columns' real rectangles, so it is right side by side, stacked, and in a
// right-to-left note without any special case.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// What is being dragged: [from] is the column grabbed, [to] where it would
/// land if released now. [vertical] is true when the columns are stacked.
class ColumnsDragController extends ChangeNotifier {
  Color? accent;

  bool _active = false;
  bool _vertical = false;
  int _from = 0;
  int _to = 0;

  bool get active => _active;
  bool get vertical => _vertical;
  int get from => _from;
  int get to => _to;

  void start(int from, {required bool vertical}) {
    _active = true;
    _vertical = vertical;
    _from = from;
    _to = from;
    notifyListeners();
  }

  void update(int to) {
    if (!_active || to == _to) return;
    _to = to;
    notifyListeners();
  }

  void end() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }
}

/// Gives the columns of one block its [ColumnsDragController].
class ColumnsDragScope extends InheritedNotifier<ColumnsDragController> {
  const ColumnsDragScope({
    super.key,
    required ColumnsDragController controller,
    required super.child,
  }) : super(notifier: controller);

  static ColumnsDragController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ColumnsDragScope>()?.notifier;

  static ColumnsDragController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ColumnsDragScope>()?.notifier;
}

/// What a column should draw while a drag is on.
enum ColumnsDragMark { none, moving, landsBefore, landsAfter }

/// How column [index] is marked by [drag].
ColumnsDragMark columnsDragMarkFor(ColumnsDragController? drag, int index) {
  if (drag == null || !drag.active) return ColumnsDragMark.none;
  if (index == drag.from) return ColumnsDragMark.moving;
  if (index == drag.to) {
    return drag.to > drag.from
        ? ColumnsDragMark.landsAfter
        : ColumnsDragMark.landsBefore;
  }
  return ColumnsDragMark.none;
}

/// The column the pointer at [point] is over (or nearest to), given the
/// columns' on-screen [rects] in order. Ties go to the earlier column.
int columnsDragTarget(List<Rect> rects, Offset point) {
  var best = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < rects.length; i++) {
    final r = rects[i];
    final dx = [r.left - point.dx, 0.0, point.dx - r.right]
        .reduce((a, b) => a > b ? a : b);
    final dy = [r.top - point.dy, 0.0, point.dy - r.bottom]
        .reduce((a, b) => a > b ? a : b);
    final d = dx * dx + dy * dy;
    if (d < bestDistance) {
      bestDistance = d;
      best = i;
    }
  }
  return best;
}

/// Makes the grip above a column draggable. [child] is the grip (its tap, which
/// opens the menu, keeps working).
class ColumnGripDragger extends StatefulWidget {
  const ColumnGripDragger({
    super.key,
    required this.columns,
    required this.position,
    required this.editorState,
    required this.vertical,
    required this.child,
  });

  final Node columns;
  final int position;
  final EditorState editorState;

  /// Whether the columns are stacked (drag up and down) or side by side.
  final bool vertical;
  final Widget child;

  @override
  State<ColumnGripDragger> createState() => _ColumnGripDraggerState();
}

class _ColumnGripDraggerState extends State<ColumnGripDragger> {
  ColumnsDragController? _drag;
  bool _live = false;

  List<Node> get _columns => widget.columns.children
      .where((c) => c.type == ColumnBlockKeys.type)
      .toList();

  bool get _enabled => widget.editorState.editable && _columns.length > 1;

  void _begin() {
    if (!_enabled) return;
    final drag = ColumnsDragScope.read(context);
    if (drag == null) return;
    _drag = drag..start(widget.position, vertical: widget.vertical);
    _live = true;
    HapticFeedback.mediumImpact();
  }

  void _move(Offset global) {
    if (!_live) return;
    final rects = [for (final c in _columns) c.rect];
    if (rects.isEmpty) return;
    final before = _drag!.to;
    _drag!.update(columnsDragTarget(rects, global));
    if (_drag!.to != before) HapticFeedback.selectionClick();
  }

  void _finish({required bool apply}) {
    if (!_live) return;
    _live = false;
    final to = _drag!.to;
    _drag!.end();
    _drag = null;
    if (apply && to != widget.position && widget.columns.parent != null) {
      ColumnsActions.moveColumn(
        widget.columns,
        widget.position,
        to,
        widget.editorState,
      );
    }
  }

  @override
  void dispose() {
    _drag?.end();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (blockHoverActionsTouchEnabled()) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (d) {
          _begin();
          _move(d.globalPosition);
        },
        onLongPressMoveUpdate: (d) => _move(d.globalPosition),
        onLongPressEnd: (_) => _finish(apply: true),
        onLongPressCancel: () => _finish(apply: false),
        child: widget.child,
      );
    }
    // A mouse drags straight away, along the axis the columns are laid out on.
    final vertical = widget.vertical;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: vertical ? null : (_) => _begin(),
      onHorizontalDragUpdate: vertical ? null : (d) => _move(d.globalPosition),
      onHorizontalDragEnd: vertical ? null : (_) => _finish(apply: true),
      onHorizontalDragCancel: vertical ? null : () => _finish(apply: false),
      onVerticalDragStart: vertical ? (_) => _begin() : null,
      onVerticalDragUpdate: vertical ? (d) => _move(d.globalPosition) : null,
      onVerticalDragEnd: vertical ? (_) => _finish(apply: true) : null,
      onVerticalDragCancel: vertical ? () => _finish(apply: false) : null,
      child: widget.child,
    );
  }
}
