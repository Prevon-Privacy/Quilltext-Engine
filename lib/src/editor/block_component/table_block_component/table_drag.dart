// Drag a table row or column by its handle to move it.
//
// Three small pieces:
//  * [TableDragController] - what is being dragged and where it would land;
//  * [TableDragScope] - hands the controller to the cells, which draw the
//    "this is moving" tint and the "it lands here" bar;
//  * [TableHandleDragger] - wraps a row/column handle, turns the finger or
//    mouse movement into a landing index and, on release, calls
//    [TableActions.move] (one undo step).
//
// Touch uses press-and-hold then drag (a plain drag on the handle would fight
// the table's sideways scroll); a mouse drags straight away. The same move is
// also in the handle's menu ("Move up/down/left/right"), so nothing depends on
// a gesture.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// What is being dragged: [dir] says row or column, [from] is where it started
/// and [to] is where it would land if released now.
class TableDragController extends ChangeNotifier {
  /// The color of the moving tint and the landing bar (the table style's hover
  /// color); null falls back to the ambient theme.
  Color? accent;

  TableDirection? _dir;
  int _from = 0;
  int _to = 0;

  bool get active => _dir != null;
  TableDirection? get dir => _dir;
  int get from => _from;
  int get to => _to;

  void start(TableDirection dir, int from) {
    _dir = dir;
    _from = from;
    _to = from;
    notifyListeners();
  }

  void update(int to) {
    if (_dir == null || to == _to) return;
    _to = to;
    notifyListeners();
  }

  void end() {
    if (_dir == null) return;
    _dir = null;
    notifyListeners();
  }
}

/// Gives the cells of one table its [TableDragController].
class TableDragScope extends InheritedNotifier<TableDragController> {
  const TableDragScope({
    super.key,
    required TableDragController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, rebuilding the caller when it changes; null outside a
  /// table.
  static TableDragController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TableDragScope>()?.notifier;

  /// The controller without listening (for gesture handlers).
  static TableDragController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TableDragScope>()?.notifier;
}

/// What a cell should draw while a drag is on.
enum TableDragMark { none, moving, landsBefore, landsAfter }

/// How the cell at ([col], [row]) is marked by [drag].
TableDragMark tableDragMarkFor(
  TableDragController? drag, {
  required int col,
  required int row,
}) {
  if (drag == null || !drag.active) return TableDragMark.none;
  final index = drag.dir == TableDirection.col ? col : row;
  if (index == drag.from) return TableDragMark.moving;
  if (index == drag.to) {
    return drag.to > drag.from
        ? TableDragMark.landsAfter
        : TableDragMark.landsBefore;
  }
  return TableDragMark.none;
}

/// The landing index for a drag: [sizes] are the lines' extents along the drag
/// axis (border included), [from] the line grabbed, [delta] how far the finger
/// moved along that axis. [first] is the lowest index that may be dropped on
/// (1 when a pinned header holds index 0).
int tableDragTarget({
  required List<double> sizes,
  required int from,
  required double delta,
  int first = 0,
}) {
  if (sizes.isEmpty) return from;
  var start = 0.0;
  for (var i = 0; i < from; i++) {
    start += sizes[i];
  }
  final centre = start + sizes[from] / 2 + delta;
  var edge = 0.0;
  var target = sizes.length - 1;
  for (var i = 0; i < sizes.length; i++) {
    edge += sizes[i];
    if (centre < edge) {
      target = i;
      break;
    }
  }
  return target.clamp(first, sizes.length - 1);
}

/// Makes a row/column handle draggable. [child] is the handle itself (its tap,
/// which opens the menu, keeps working).
class TableHandleDragger extends StatefulWidget {
  const TableHandleDragger({
    super.key,
    required this.node,
    required this.editorState,
    required this.position,
    required this.dir,
    required this.child,
  });

  final Node node;
  final EditorState editorState;
  final int position;
  final TableDirection dir;
  final Widget child;

  @override
  State<TableHandleDragger> createState() => _TableHandleDraggerState();
}

class _TableHandleDraggerState extends State<TableHandleDragger> {
  List<double> _sizes = const [];
  int _first = 0;
  TableDragController? _drag;
  bool _live = false;

  bool get _enabled =>
      widget.editorState.editable &&
      TableActions.canMove(widget.node, widget.position, widget.dir);

  void _begin() {
    if (!_enabled) return;
    final drag = TableDragScope.read(context);
    if (drag == null) return;
    final table = TableNode(node: widget.node);
    final fit = TableFitScope.of(context);
    final border = table.config.borderWidth;
    _sizes = widget.dir == TableDirection.col
        ? [
            for (var c = 0; c < table.colsLen; c++)
              table.getColWidth(c) * fit + border,
          ]
        : [
            for (var r = 0; r < table.rowsLen; r++)
              table.getRowHeight(r) + border,
          ];
    _first = TableActions.isHeader(widget.node, widget.dir) ? 1 : 0;
    _drag = drag..start(widget.dir, widget.position);
    _live = true;
    _acc = 0;
    HapticFeedback.mediumImpact();
  }

  void _move(double delta) {
    if (!_live) return;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final signed = widget.dir == TableDirection.col && rtl ? -delta : delta;
    final before = _drag!.to;
    _drag!.update(
      tableDragTarget(
        sizes: _sizes,
        from: widget.position,
        delta: signed,
        first: _first,
      ),
    );
    if (_drag!.to != before) HapticFeedback.selectionClick();
  }

  void _finish({required bool apply}) {
    if (!_live) return;
    _live = false;
    final to = _drag!.to;
    _drag!.end();
    _drag = null;
    if (apply && to != widget.position && widget.node.parent != null) {
      TableActions.move(
        widget.node,
        widget.position,
        to,
        widget.editorState,
        widget.dir,
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
    final col = widget.dir == TableDirection.col;
    if (blockHoverActionsTouchEnabled()) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (_) => _begin(),
        onLongPressMoveUpdate: (d) =>
            _move(col ? d.offsetFromOrigin.dx : d.offsetFromOrigin.dy),
        onLongPressEnd: (_) => _finish(apply: true),
        onLongPressCancel: () => _finish(apply: false),
        child: widget.child,
      );
    }
    // A mouse drags straight away. Only the axis the line moves along is
    // claimed, so the other axis still scrolls the page.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: col ? (_) => _begin() : null,
      onHorizontalDragUpdate: col ? (d) => _move(_total(d.primaryDelta)) : null,
      onHorizontalDragEnd: col ? (_) => _finish(apply: true) : null,
      onHorizontalDragCancel: col ? () => _finish(apply: false) : null,
      onVerticalDragStart: col ? null : (_) => _begin(),
      onVerticalDragUpdate: col ? null : (d) => _move(_total(d.primaryDelta)),
      onVerticalDragEnd: col ? null : (_) => _finish(apply: true),
      onVerticalDragCancel: col ? null : () => _finish(apply: false),
      child: widget.child,
    );
  }

  double _acc = 0;

  /// Pan updates arrive as per-event deltas; the landing math wants the total
  /// since the drag began.
  double _total(double? step) {
    if (!_live) {
      _acc = 0;
      return 0;
    }
    _acc += step ?? 0;
    return _acc;
  }
}
