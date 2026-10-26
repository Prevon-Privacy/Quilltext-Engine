import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/table_block_component/table_action_handler.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/table_block_component/table_drag.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/table_block_component/util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TableCellBlockKeys {
  const TableCellBlockKeys._();

  static const String type = 'table/cell';

  static const String rowPosition = 'rowPosition';

  static const String colPosition = 'colPosition';

  static const String height = 'height';

  static const String width = 'width';

  static const String rowBackgroundColor = 'rowBackgroundColor';

  static const String colBackgroundColor = 'colBackgroundColor';

  /// One cell's own fill. Wins over the column and row fills.
  static const String cellBackgroundColor = 'cellBackgroundColor';
}

typedef TableBlockCellComponentColorBuilder = Color? Function(
  BuildContext context,
  Node node,
);

Node tableCellNode(String text, int rowPosition, int colPosition) {
  return Node(
    type: TableCellBlockKeys.type,
    attributes: {
      TableCellBlockKeys.rowPosition: rowPosition,
      TableCellBlockKeys.colPosition: colPosition,
    },
    children: [
      paragraphNode(text: text),
    ],
  );
}

class TableCellBlockComponentBuilder extends BlockComponentBuilder {
  TableCellBlockComponentBuilder({
    super.configuration,
    this.menuBuilder,
    this.colorBuilder,
  });

  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableBlockCellComponentColorBuilder? colorBuilder;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return TableCelBlockWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      menuBuilder: menuBuilder,
      colorBuilder: colorBuilder,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) =>
      node.attributes.isNotEmpty &&
      node.attributes.containsKey(TableCellBlockKeys.rowPosition) &&
      node.attributes.containsKey(TableCellBlockKeys.colPosition);
}

class TableCelBlockWidget extends BlockComponentStatefulWidget {
  const TableCelBlockWidget({
    super.key,
    required super.node,
    this.menuBuilder,
    this.colorBuilder,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableBlockCellComponentColorBuilder? colorBuilder;

  @override
  State<TableCelBlockWidget> createState() => _TableCeBlockWidgetState();
}

class _TableCeBlockWidgetState extends State<TableCelBlockWidget> {
  late final editorState = Provider.of<EditorState>(context, listen: false);
  bool _rowActionVisibility = false;

  /// While a row or column is being dragged: a tint on the line that moves and
  /// a bar on the edge where it would land. Null when nothing is dragged.
  Decoration? _dragDecoration(BuildContext context) {
    final drag = TableDragScope.maybeOf(context);
    if (drag == null || !drag.active) return null;
    final col = widget.node.attributes[TableCellBlockKeys.colPosition];
    final row = widget.node.attributes[TableCellBlockKeys.rowPosition];
    if (col is! int || row is! int) return null;
    final accent = drag.accent ?? Theme.of(context).colorScheme.primary;
    final isCol = drag.dir == TableDirection.col;
    final bar = BorderSide(color: accent, width: 3);
    switch (tableDragMarkFor(drag, col: col, row: row)) {
      case TableDragMark.none:
        return null;
      case TableDragMark.moving:
        return BoxDecoration(color: accent.withValues(alpha: 0.16));
      case TableDragMark.landsBefore:
        return BoxDecoration(
          border: isCol ? BorderDirectional(start: bar) : Border(top: bar),
        );
      case TableDragMark.landsAfter:
        return BoxDecoration(
          border: isCol ? BorderDirectional(end: bar) : Border(bottom: bar),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _rowActionVisibility = true),
          onExit: (_) => setState(() => _rowActionVisibility = false),
          child: Container(
            foregroundDecoration: _dragDecoration(context),
            constraints: BoxConstraints(
              minHeight: context.select((Node n) => n.cellHeight),
            ),
            color: context.select(
              (Node n) =>
                  widget.colorBuilder?.call(context, n) ??
                  (n.attributes[TableCellBlockKeys.cellBackgroundColor]
                          as String?)
                      ?.tryToColor() ??
                  (n.attributes[TableCellBlockKeys.colBackgroundColor]
                          as String?)
                      ?.tryToColor() ??
                  (n.attributes[TableCellBlockKeys.rowBackgroundColor]
                          as String?)
                      ?.tryToColor(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  // Half of the row's vertical breathing room on each side, so
                  // the text sits centered in its row (it used to sit at the
                  // top with all the spare height piled up underneath).
                  padding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: TableDefaults.cellVerticalPadding / 2,
                  ),
                  child: editorState.renderer.build(
                    context,
                    widget.node.children.first,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!blockHoverActionsTouchEnabled())
          TableActionHandler(
            visible: _rowActionVisibility,
            node: widget.node.parent!,
            editorState: editorState,
            position: widget.node.attributes[TableCellBlockKeys.rowPosition],
            transform: context.select((Node n) {
              final fit = TableFitScope.of(context);
              final int col = n.attributes[TableCellBlockKeys.colPosition];
              double left = -12;
              for (var i = 0; i < col; i++) {
                left -= (getCellNode(n.parent!, i, 0)?.cellWidth ??
                        TableDefaults.colWidth) *
                    fit;
                left -= n.parent!.attributes['borderWidth'] ??
                    TableDefaults.borderWidth;
              }

              return Matrix4.translationValues(left, 0.0, 0.0);
            }),
            alignment: Alignment.centerLeft,
            height: context.select((Node n) => n.cellHeight),
            menuBuilder: widget.menuBuilder,
            dir: TableDirection.row,
          ),
      ],
    );
  }
}
