import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/table_block_component/table_action_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'table_view.dart';

class TableBlockKeys {
  const TableBlockKeys._();

  static const String type = 'table';

  static const String colDefaultWidth = 'colDefaultWidth';

  static const String rowDefaultHeight = 'rowDefaultHeight';

  static const String colMinimumWidth = 'colMinimumWidth';

  static const String borderWidth = 'borderWidth';

  static const String colsLen = 'colsLen';

  static const String rowsLen = 'rowsLen';

  static const String colsHeight = 'colsHeight';

  /// `true` when row 0 is the table's header: it is tinted, pinned in place
  /// (no row can be moved above it) and is the header in a Markdown copy.
  /// Absent on tables made before this flag existed, which read as `false`.
  static const String headerRow = 'headerRow';

  /// Same for column 0.
  static const String headerCol = 'headerCol';
}

class TableStyle {
  final double colWidth;
  final double rowHeight;
  final double colMinimumWidth;
  final double borderWidth;
  final Widget addIcon;
  final Widget handlerIcon;
  final Color borderColor;
  final Color borderHoverColor;

  const TableStyle({
    this.colWidth = 160,
    this.rowHeight = 32,
    this.colMinimumWidth = 40,
    this.borderWidth = 1,
    this.addIcon = TableDefaults.addIcon,
    this.handlerIcon = TableDefaults.handlerIcon,
    this.borderColor = TableDefaults.borderColor,
    this.borderHoverColor = TableDefaults.borderHoverColor,
  });
}

class TableDefaults {
  const TableDefaults._();

  static double colWidth = 160.0;

  static double rowHeight = 32.0;

  static double colMinimumWidth = 40.0;

  static double borderWidth = 1.0;

  /// The vertical breathing room a cell adds around its (padding-free) paragraph
  /// when the row height is computed in [TableNode.updateRowHeight].
  ///
  /// Historically this was a bare `+ 8` meant to mirror the paragraph's own
  /// block padding — but that padding was ALSO already included in the
  /// paragraph's measured `rect.height`, so the cell counted it twice and every
  /// row was ~8px taller than intended. In-cell paragraphs now render with zero
  /// block padding (`noteBlockPadding` in the host app), so this value is the
  /// cell's own single vertical padding, not a duplicate.
  static double cellVerticalPadding = 6.0;

  static const Widget addIcon = Icon(Icons.add, size: 20);

  static const Widget handlerIcon = Icon(Icons.drag_indicator);

  static const Color borderColor = Colors.grey;

  static const Color borderHoverColor = Colors.blue;
}

enum TableDirection { row, col }

typedef TableBlockComponentMenuBuilder = Widget Function(
  Node,
  EditorState,
  int,
  TableDirection,
  VoidCallback?,
  VoidCallback?,
);

class TableBlockComponentBuilder extends BlockComponentBuilder {
  TableBlockComponentBuilder({
    super.configuration,
    this.tableStyle = const TableStyle(),
    this.menuBuilder,
  });

  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    TableDefaults.colWidth = tableStyle.colWidth;
    TableDefaults.rowHeight = tableStyle.rowHeight;
    TableDefaults.colMinimumWidth = tableStyle.colMinimumWidth;
    TableDefaults.borderWidth = tableStyle.borderWidth;
    return TableBlockComponentWidget(
      key: node.key,
      tableNode: TableNode(node: node),
      node: node,
      configuration: configuration,
      menuBuilder: menuBuilder,
      tableStyle: tableStyle,
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
  BlockComponentValidate get validate => (node) {
        // check the node is valid
        if (node.attributes.isEmpty) {
          AppFlowyEditorLog.editor
              .debug('TableBlockComponentBuilder: node is empty');
          return false;
        }

        // check the node has rowPosition and colPosition
        if (!node.attributes.containsKey(TableBlockKeys.colsLen) ||
            !node.attributes.containsKey(TableBlockKeys.rowsLen)) {
          AppFlowyEditorLog.editor.debug(
            'TableBlockComponentBuilder: node has no colsLen or rowsLen',
          );
          return false;
        }

        final colsLen = node.attributes[TableBlockKeys.colsLen];
        final rowsLen = node.attributes[TableBlockKeys.rowsLen];

        // check its children
        final children = node.children;
        if (children.isEmpty) {
          AppFlowyEditorLog.editor
              .debug('TableBlockComponentBuilder: children is empty');
          return false;
        }

        if (children.length != colsLen * rowsLen) {
          AppFlowyEditorLog.editor.debug(
            'TableBlockComponentBuilder: children length(${children.length}) is not equal to colsLen * rowsLen($colsLen * $rowsLen)',
          );
          return false;
        }

        // all children should contain rowPosition and colPosition
        for (var i = 0; i < colsLen; i++) {
          for (var j = 0; j < rowsLen; j++) {
            final child = children.where(
              (n) =>
                  n.attributes[TableCellBlockKeys.colPosition] == i &&
                  n.attributes[TableCellBlockKeys.rowPosition] == j,
            );
            if (child.isEmpty) {
              AppFlowyEditorLog.editor.debug(
                'TableBlockComponentBuilder: child($i, $j) is empty',
              );
              return false;
            }

            // should only contains one child
            if (child.length != 1) {
              AppFlowyEditorLog.editor.debug(
                'TableBlockComponentBuilder: child($i, $j) is not unique',
              );
              return false;
            }
          }
        }

        return true;
      };
}

/// Render-time horizontal scale applied to every column so a table fits the
/// available width. 1.0 = stored widths.
class TableFitScope extends InheritedWidget {
  const TableFitScope({super.key, required this.scale, required super.child});

  final double scale;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TableFitScope>()?.scale ?? 1.0;

  @override
  bool updateShouldNotify(TableFitScope oldWidget) => oldWidget.scale != scale;
}

class TableBlockComponentWidget extends BlockComponentStatefulWidget {
  const TableBlockComponentWidget({
    super.key,
    required this.tableNode,
    required super.node,
    this.tableStyle = const TableStyle(),
    this.menuBuilder,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  final TableNode tableNode;

  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;

  @override
  State<TableBlockComponentWidget> createState() =>
      _TableBlockComponentWidgetState();
}

class _TableBlockComponentWidgetState extends State<TableBlockComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late final editorState = Provider.of<EditorState>(context, listen: false);
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final touch = blockHoverActionsTouchEnabled();
    // Touch: the row-handle gutter and column-handle strip are in-flow inside
    // TableView, so the scroll view needs no extra top/left padding.
    final leftPad = touch ? 0.0 : 22.0;
    final topPad = touch ? 0.0 : 22.0;
    // Space the "add column" button and breathing room take next to the grid.
    // Touch has no hover "add" buttons, so the only chrome is the handle
    // gutter; the grid gets the rest of the width.
    final chromeWidth = touch ? kTableTouchGutter + 2.0 : leftPad + 28.0 + 4.0;
    Widget child = LayoutBuilder(
      builder: (context, constraints) {
        // Shrink the columns proportionally so the whole table fits the
        // available width instead of scrolling sideways. Stored widths are
        // untouched; this is a render-time scale only. If even the scaled
        // grid cannot fit (very many columns), the scroll view is the
        // fallback.
        double scale = 1.0;
        final available = constraints.maxWidth - chromeWidth;
        final natural = widget.tableNode.tableWidth;
        if (constraints.hasBoundedWidth &&
            natural > available &&
            available > 0) {
          scale = (available / natural).clamp(0.3, 1.0);
        }
        return TableFitScope(
          scale: scale,
          child: Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                top: topPad,
                left: leftPad,
                bottom: 4,
              ),
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: TableView(
                tableNode: widget.tableNode,
                editorState: editorState,
                menuBuilder: widget.menuBuilder,
                tableStyle: widget.tableStyle,
              ),
            ),
          ),
        );
      },
    );

    child = Padding(
      key: tableKey,
      padding: padding,
      child: child,
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [
        BlockSelectionType.block,
      ],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return child;
  }

  final tableKey = GlobalKey();

  RenderBox get _renderBox => context.findRenderObject() as RenderBox;

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    final parentBox = context.findRenderObject();
    final tableBox = tableKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && tableBox is RenderBox) {
      return [
        (shiftWithBaseOffset
                ? tableBox.localToGlobal(Offset.zero, ancestor: parentBox)
                : Offset.zero) &
            tableBox.size,
      ];
    }
    return [Offset.zero & _renderBox.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      _renderBox.localToGlobal(offset);

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
    final size = _renderBox.size;
    return Rect.fromLTWH(-size.width / 2.0, 0, size.width, size.height);
  }
}

SelectionMenuItem tableMenuItem = SelectionMenuItem(
  getName: () => AppFlowyEditorL10n.current.table,
  icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
    icon: Icons.table_view,
    isSelected: isSelected,
    style: style,
  ),
  keywords: ['table'],
  handler: (editorState, _, __) => insertDefaultTableAtCaret(editorState),
);

/// Default size and header tint of a freshly inserted table. The single source
/// for every entry point (`/` menu, toolbar `+` button) so they cannot drift.
const int kDefaultTableColumns = 4;
const int kDefaultTableRows = 6;

/// Identical to the "Gray background" highlight option
/// (`generateHighlightColorOptions`) so the color menu shows it as selected.
final String kDefaultTableHeaderRowColor =
    Colors.grey.withValues(alpha: 0.3).toHex();

/// Inserts the default table (see [kDefaultTableColumns], [kDefaultTableRows],
/// [kDefaultTableHeaderRowColor]) at the collapsed caret via
/// [insertTableWithSurroundingParagraphs]. No-op without a collapsed caret on
/// an existing node. Shared by [tableMenuItem] and the app toolbar.
void insertDefaultTableAtCaret(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return;
  }

  final currentNode = editorState.getNodeAtPath(selection.end.path);
  if (currentNode == null) {
    return;
  }

  final tableNode = TableNode.fromList<String>(
    [
      // Columns are the outer list.
      for (var c = 0; c < kDefaultTableColumns; c++)
        List<String>.filled(kDefaultTableRows, ''),
    ],
    headerRowColor: kDefaultTableHeaderRowColor,
  );
  tableNode.node.updateAttributes({TableBlockKeys.headerRow: true});

  insertTableWithSurroundingParagraphs(
    editorState,
    currentNode: currentNode,
    table: tableNode.node,
  );
}

/// Inserts [table] at the caret's block and guarantees an empty paragraph
/// outside the table on each open side, so the caret always has somewhere to
/// go above or below it (a table has no text position of its own). An empty
/// [currentNode] is replaced by the table; otherwise the table goes after it.
/// A leading paragraph is added only when nothing precedes the table, and a
/// trailing one only when nothing (or another table) follows it. The caret
/// lands in the table's first cell.
void insertTableWithSurroundingParagraphs(
  EditorState editorState, {
  required Node currentNode,
  required Node table,
}) {
  final path = currentNode.path;
  final replaceCurrent = currentNode.delta?.isEmpty ?? false;
  final transaction = editorState.transaction;

  final needsLeading = replaceCurrent && currentNode.previous == null;
  final tablePath =
      replaceCurrent ? (needsLeading ? path.next : path) : path.next;
  final following = currentNode.next;
  final needsTrailing =
      following == null || following.type == TableBlockKeys.type;

  if (needsLeading) {
    transaction.insertNode(path, paragraphNode());
  }
  transaction.insertNode(tablePath, table);
  if (needsTrailing) {
    transaction.insertNode(tablePath.next, paragraphNode());
  }
  if (replaceCurrent) {
    transaction.deleteNode(currentNode);
  }
  transaction.afterSelection = Selection.collapsed(
    Position(path: tablePath + [0, 0], offset: 0),
  );
  editorState.apply(transaction);
}
