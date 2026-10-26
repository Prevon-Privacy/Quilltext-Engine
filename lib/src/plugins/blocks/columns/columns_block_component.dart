import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/plugins/blocks/columns/column_width_resizer.dart';
import 'package:prevon_quilltext_engine/src/plugins/blocks/columns/columns_block_constant.dart';
import 'package:prevon_quilltext_engine/src/plugins/blocks/columns/columns_drag.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A fresh columns block of [count] empty columns (or of [children]).
Node columnsNode({
  List<Node>? children,
  int count = 2,
}) {
  return Node(
    type: ColumnsBlockKeys.type,
    children: children ?? [for (var i = 0; i < count; i++) columnNode()],
  );
}

class ColumnsBlockKeys {
  const ColumnsBlockKeys._();

  static const String type = 'columns';

  /// Old bookkeeping attribute. No longer read or written.
  static const String columnCount = 'column_count';
}

class ColumnsBlockComponentBuilder extends BlockComponentBuilder {
  ColumnsBlockComponentBuilder({
    super.configuration,
    this.dividerColor,
    this.accentColor,
    this.gripSemanticLabel,
  });

  /// The thin line between columns, and the color it takes while dragged or
  /// hovered. Null falls back to the ambient theme.
  final Color? dividerColor;
  final Color? accentColor;

  /// Screen-reader label of the grip above each column (the host's words).
  final String? gripSemanticLabel;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return ColumnsBlockComponent(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
      dividerColor: dividerColor,
      accentColor: accentColor,
      gripSemanticLabel: gripSemanticLabel,
    );
  }

  /// Always valid: a block emptied by a deletion still has to draw so it can
  /// repair itself (see `ColumnsActions.repair`).
  @override
  BlockComponentValidate get validate => (node) => true;
}

class ColumnsBlockComponent extends BlockComponentStatefulWidget {
  const ColumnsBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.dividerColor,
    this.accentColor,
    this.gripSemanticLabel,
  });

  final Color? dividerColor;
  final Color? accentColor;
  final String? gripSemanticLabel;

  @override
  State<ColumnsBlockComponent> createState() => ColumnsBlockComponentState();
}

class ColumnsBlockComponentState extends State<ColumnsBlockComponent>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  final columnsKey = GlobalKey();

  late final EditorState editorState = context.read<EditorState>();

  int? _hoverColumn;
  bool _repairQueued = false;
  final _drag = ColumnsDragController();

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  List<Node> get _columns =>
      node.children.where((c) => c.type == ColumnBlockKeys.type).toList();

  @override
  Widget build(BuildContext context) {
    // Rebuild when a column is added/removed (the block notifies) and while a
    // divider is dragged (that edits a column's weight in memory).
    _drag.accent = widget.accentColor;
    return ColumnsDragScope(
      controller: _drag,
      child: ListenableBuilder(
        listenable: Listenable.merge([node, ...node.children]),
        builder: (context, _) => _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final columns = _columns;
    final editable = editorState.editable;
    if (editable && ColumnsActions.needsRepair(node)) _queueRepair();

    Widget child = LayoutBuilder(
      builder: (context, constraints) {
        final n = columns.length;
        if (n == 0) return const SizedBox(height: 24);
        final width = constraints.maxWidth;
        final room = width - (n - 1) * ColumnsBlockConstants.gap;
        // No width to share out (unbounded) also stacks: flexible columns
        // cannot be laid out in it.
        final stacked = !width.isFinite ||
            (n > 1 && room / n < ColumnsBlockConstants.stackBelowColumnWidth);
        return stacked
            ? _stacked(context, columns, editable)
            : _sideBySide(context, columns, width, editable);
      },
    );

    return Padding(
      key: columnsKey,
      padding: padding,
      child: child,
    );
  }

  // --- layouts -------------------------------------------------------------

  Widget _sideBySide(
    BuildContext context,
    List<Node> columns,
    double width,
    bool editable,
  ) {
    final n = columns.length;
    const gap = ColumnsBlockConstants.gap;
    final weights = [for (final c in columns) columnWeightOf(c)];
    final total = weights.sum;
    final room = width - (n - 1) * gap;
    final perWeight = width.isFinite && total > 0 ? room / total : 0.0;
    final strip = editable ? ColumnsBlockConstants.gripStrip : 0.0;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          Expanded(
            flex: (weights[i] * 1000).round().clamp(1, 1 << 30),
            child: _slot(context, columns, i, editable, stackedLayout: false),
          ),
        ],
      ],
    );
    final dividers = <Widget>[];
    var x = 0.0;
    for (var k = 0; k < n - 1; k++) {
      x += weights[k] * perWeight + (k == 0 ? 0 : gap);
      final centre = x + gap / 2;
      dividers.add(
        Positioned(
          left: centre - ColumnsBlockConstants.resizerHitWidth / 2,
          width: ColumnsBlockConstants.resizerHitWidth,
          top: strip,
          bottom: 0,
          child: ColumnWidthResizer(
            columns: node,
            left: columns[k],
            right: columns[k + 1],
            editorState: editorState,
            pixelsPerWeight: perWeight,
            editable: editable,
            lineColor: widget.dividerColor,
            activeColor: widget.accentColor,
          ),
        ),
      );
    }
    return Stack(children: [row, ...dividers]);
  }

  Widget _stacked(BuildContext context, List<Node> columns, bool editable) {
    final line =
        widget.dividerColor ?? Theme.of(context).colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: ColumnsBlockConstants.stackedGap / 2,
              ),
              child: Divider(height: 1, thickness: 1, color: line),
            ),
          _slot(context, columns, i, editable, stackedLayout: true),
        ],
      ],
    );
  }

  /// One column with the grip strip above it while editing.
  Widget _slot(
    BuildContext context,
    List<Node> columns,
    int index,
    bool editable, {
    required bool stackedLayout,
  }) {
    final column = columns[index];
    final content = editorState.renderer.build(context, column);
    if (!editable) return content;
    final drag = ColumnsDragScope.maybeOf(context);
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;
    final mark = columnsDragMarkFor(drag, index);
    final vertical = drag?.vertical ?? false;
    final bar = BorderSide(color: accent, width: 3);
    final Decoration? marking = switch (mark) {
      ColumnsDragMark.none => null,
      ColumnsDragMark.moving =>
        BoxDecoration(color: accent.withValues(alpha: 0.12)),
      ColumnsDragMark.landsBefore => BoxDecoration(
          border: vertical ? Border(top: bar) : BorderDirectional(start: bar),
        ),
      ColumnsDragMark.landsAfter => BoxDecoration(
          border: vertical ? Border(bottom: bar) : BorderDirectional(end: bar),
        ),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hoverColumn = index),
      onExit: (_) => setState(() {
        if (_hoverColumn == index) _hoverColumn = null;
      }),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: marking ?? const BoxDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: ColumnsBlockConstants.gripStrip,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _ColumnGrip(
                  columns: node,
                  column: column,
                  position: index,
                  editorState: editorState,
                  hovered: _hoverColumn == index,
                  accent: widget.accentColor,
                  semanticLabel: widget.gripSemanticLabel,
                  stacked: stackedLayout,
                ),
              ),
            ),
            content,
          ],
        ),
      ),
    );
  }

  // --- repair --------------------------------------------------------------

  void _queueRepair() {
    if (_repairQueued) return;
    _repairQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repairQueued = false;
      if (!mounted || node.parent == null || !editorState.editable) return;
      ColumnsActions.repair(node, editorState);
    });
  }

  // --- SelectableMixin -----------------------------------------------------

  @override
  Position start() => Position(path: widget.node.path);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({
    bool shiftWithBaseOffset = false,
  }) {
    return getRectsInSelection(Selection.invalid()).first;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final rects = getRectsInSelection(
      Selection.collapsed(position),
      shiftWithBaseOffset: shiftWithBaseOffset,
    );
    return rects.firstOrNull;
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) {
      return [];
    }
    final parentBox = context.findRenderObject();
    final renderBox = columnsKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && renderBox is RenderBox) {
      return [
        renderBox.localToGlobal(Offset.zero, ancestor: parentBox) &
            renderBox.size,
      ];
    }
    return [Offset.zero & _renderBox!.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: widget.node.path, startOffset: 0, endOffset: 1);

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _renderBox!.localToGlobal(offset);
}

/// The small "more" pill above a column. It shows while the mouse is over the
/// column or the caret is in it, and opens the host's columns menu.
class _ColumnGrip extends StatelessWidget {
  const _ColumnGrip({
    required this.columns,
    required this.column,
    required this.position,
    required this.editorState,
    required this.hovered,
    required this.stacked,
    this.accent,
    this.semanticLabel,
  });

  /// Whether the columns are stacked (so a drag goes up and down).
  final bool stacked;
  final Node columns;
  final Node column;
  final int position;
  final EditorState editorState;
  final bool hovered;
  final Color? accent;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: editorState.selectionNotifier,
      builder: (context, _) {
        final caretHere =
            ColumnsActions.columnAtSelection(columns, editorState) == column;
        final show = hovered || caretHere;
        final color = accent ?? Theme.of(context).colorScheme.primary;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: show ? 1 : 0,
          // A hidden grip must not catch taps meant for the text beside it.
          child: IgnorePointer(
            ignoring: !show,
            child: Semantics(
              button: true,
              label: semanticLabel,
              child: ColumnGripDragger(
                columns: columns,
                position: position,
                editorState: editorState,
                vertical: stacked,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _open(context),
                  child: Container(
                    width: 36,
                    height: ColumnsBlockConstants.gripStrip - 2,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.more_horiz, size: 16, color: color),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _open(BuildContext context) {
    ColumnsMenuActions? host;
    try {
      host = context.read<ColumnsMenuActions>();
    } on ProviderNotFoundException {
      host = null;
    }
    host?.showColumnsMenu(
      context,
      ColumnsMenuRequest(
        columns: columns,
        editorState: editorState,
        position: position,
      ),
    );
  }
}
