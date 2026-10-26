import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/table_block_component/table_action_handler.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/table_block_component/table_add_button.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/table_block_component/table_col.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/table_block_component/table_drag.dart';
import 'package:flutter/material.dart';

class TableView extends StatefulWidget {
  const TableView({
    super.key,
    required this.editorState,
    required this.tableNode,
    required this.tableStyle,
    this.menuBuilder,
  });

  final EditorState editorState;
  final TableNode tableNode;
  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  final _drag = TableDragController();

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final touch = blockHoverActionsTouchEnabled();
    _drag.accent = widget.tableStyle.borderHoverColor;
    return TableDragScope(
      controller: _drag,
      child: _grid(context, touch),
    );
  }

  Widget _grid(BuildContext context, bool touch) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (touch) _rowGutter(),
        Column(
          children: [
            Row(
              crossAxisAlignment:
                  touch ? CrossAxisAlignment.end : CrossAxisAlignment.center,
              children: [
                ..._buildColumns(context),
                if (!touch)
                  TableActionButton(
                    padding: const EdgeInsets.only(left: 0),
                    icon: widget.tableStyle.addIcon,
                    width: 28,
                    height: widget.tableNode.colsHeight,
                    onPressed: () {
                      TableActions.add(
                        widget.tableNode.node,
                        widget.tableNode.colsLen,
                        widget.editorState,
                        TableDirection.col,
                      );
                    },
                  ),
              ],
            ),
            // No "add row" strip under the grid: it reserved an invisible 28px
            // row that read as an extra blank line below the table. Rows are
            // added from the row handle's menu (before / after); the blank
            // line under a table is the real, editable guard paragraph.
          ],
        ),
      ],
    );
  }

  /// Touch: one handle slot per row, in flow, left of the grid. Its rows line
  /// up with the cells (column-strip height + top border, then row + border).
  Widget _rowGutter() {
    final node = widget.tableNode;
    return ListenableBuilder(
      listenable: node.node,
      builder: (context, _) => SizedBox(
        width: kTableTouchGutter,
        child: Column(
          children: [
            SizedBox(height: kTableTouchGutter + node.config.borderWidth),
            for (var r = 0; r < node.rowsLen; r++)
              SizedBox(
                height: node.getRowHeight(r) + node.config.borderWidth,
                child: Center(
                  child: TableTouchHandle(
                    node: node.node,
                    editorState: widget.editorState,
                    position: r,
                    dir: TableDirection.row,
                    menuBuilder: widget.menuBuilder,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildColumns(BuildContext context) {
    return List.generate(
      widget.tableNode.colsLen,
      (i) => TableCol(
        colIdx: i,
        editorState: widget.editorState,
        tableNode: widget.tableNode,
        menuBuilder: widget.menuBuilder,
        tableStyle: widget.tableStyle,
      ),
    );
  }
}
