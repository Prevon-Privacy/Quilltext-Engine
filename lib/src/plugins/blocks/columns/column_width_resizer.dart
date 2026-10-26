import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/plugins/blocks/columns/columns_block_constant.dart';
import 'package:flutter/material.dart';

/// The divider between two side-by-side columns. It draws a thin line and,
/// when [editable], lets the person drag it to trade width between the column
/// on its left and the one on its right (their combined width never changes).
/// A double tap gives every column the same width again.
///
/// Widths are shares ([ColumnBlockKeys.weight]), so a drag converts pixels to
/// weight with [pixelsPerWeight] and the layout keeps following the screen.
class ColumnWidthResizer extends StatefulWidget {
  const ColumnWidthResizer({
    super.key,
    required this.columns,
    required this.left,
    required this.right,
    required this.editorState,
    required this.pixelsPerWeight,
    required this.editable,
    this.lineColor,
    this.activeColor,
  });

  final Node columns;
  final Node left;
  final Node right;
  final EditorState editorState;

  /// How many pixels one unit of weight is wide right now.
  final double pixelsPerWeight;

  /// False in read-only mode: the line is drawn but cannot be dragged.
  final bool editable;
  final Color? lineColor;
  final Color? activeColor;

  @override
  State<ColumnWidthResizer> createState() => _ColumnWidthResizerState();
}

class _ColumnWidthResizerState extends State<ColumnWidthResizer> {
  bool _hover = false;
  bool _dragging = false;

  // Captured when a drag starts.
  double _leftStart = 1;
  double _rightStart = 1;
  Object? _leftOriginal;
  Object? _rightOriginal;
  double _travel = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = widget.lineColor ?? theme.colorScheme.outlineVariant;
    final active = widget.activeColor ?? theme.colorScheme.primary;
    final lit = widget.editable && (_hover || _dragging);

    final line = Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: lit ? 3 : 1,
        decoration: BoxDecoration(
          color: lit ? active : base,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
    if (!widget.editable) return IgnorePointer(child: line);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _onStart,
        onHorizontalDragUpdate: _onUpdate,
        onHorizontalDragEnd: (_) => _finish(),
        onHorizontalDragCancel: _finish,
        onDoubleTap: _equalize,
        child: SizedBox(
          width: ColumnsBlockConstants.resizerHitWidth,
          child: line,
        ),
      ),
    );
  }

  void _onStart(DragStartDetails details) {
    _dragging = true;
    _travel = 0;
    _leftStart = columnWeightOf(widget.left);
    _rightStart = columnWeightOf(widget.right);
    _leftOriginal = widget.left.attributes[ColumnBlockKeys.weight];
    _rightOriginal = widget.right.attributes[ColumnBlockKeys.weight];
    setState(() {});
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!_dragging || widget.pixelsPerWeight <= 0) return;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _travel += rtl ? -details.delta.dx : details.delta.dx;

    final pair = _leftStart + _rightStart;
    final minWeight =
        ColumnsBlockConstants.minColumnWidth / widget.pixelsPerWeight;
    // A pair too narrow to give both columns their minimum just splits evenly.
    final lo = minWeight * 2 > pair ? pair / 2 : minWeight;
    final left = (_leftStart + _travel / widget.pixelsPerWeight)
        .clamp(lo, pair - lo)
        .toDouble();

    // In memory only while the finger is down; one real, undoable edit when it
    // lifts.
    widget.left.updateAttributes({ColumnBlockKeys.weight: left});
    widget.right.updateAttributes({ColumnBlockKeys.weight: pair - left});
  }

  void _finish() {
    if (!_dragging) return;
    _dragging = false;
    if (mounted) setState(() {});

    final left = columnWeightOf(widget.left);
    final right = columnWeightOf(widget.right);
    // Put the starting widths back, then make the final ones through a
    // transaction, so undo returns to the starting widths.
    widget.left.updateAttributes({ColumnBlockKeys.weight: _leftOriginal});
    widget.right.updateAttributes({ColumnBlockKeys.weight: _rightOriginal});
    if ((left - _leftStart).abs() < 0.001) return;
    final transaction = widget.editorState.transaction
      ..updateNode(widget.left, {ColumnBlockKeys.weight: left})
      ..updateNode(widget.right, {ColumnBlockKeys.weight: right});
    widget.editorState.apply(transaction, withUpdateSelection: false);
  }

  void _equalize() =>
      ColumnsActions.equalize(widget.columns, widget.editorState);
}
