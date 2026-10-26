import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Node columnNode({
  List<Node>? children,
  double? weight,
}) {
  return Node(
    type: ColumnBlockKeys.type,
    children: children ?? [paragraphNode()],
    attributes: {
      if (weight != null) ColumnBlockKeys.weight: weight,
    },
  );
}

class ColumnBlockKeys {
  const ColumnBlockKeys._();

  static const String type = 'column';

  /// Old fixed pixel width. No longer read or written (it cannot follow the
  /// screen); kept so the key is not reused.
  static const String width = 'width';

  /// This column's share of the row: a column with weight 2 is twice as wide
  /// as one with weight 1. Absent means 1.
  static const String weight = 'weight';
}

/// The share of the row [column] takes (1 when unset or nonsense).
double columnWeightOf(Node column) {
  final w = column.attributes[ColumnBlockKeys.weight];
  return w is num && w.isFinite && w > 0 ? w.toDouble() : 1.0;
}

class ColumnBlockComponentBuilder extends BlockComponentBuilder {
  ColumnBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return ColumnBlockComponent(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
    );
  }

  /// Always valid: a column emptied by a deletion still has to draw, so the
  /// columns block can repair it (see `ColumnsActions.repair`) instead of the
  /// renderer swapping in an "unknown block" box.
  @override
  BlockComponentValidate get validate => (node) => true;
}

class ColumnBlockComponent extends BlockComponentStatefulWidget {
  const ColumnBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<ColumnBlockComponent> createState() => ColumnBlockComponentState();
}

class ColumnBlockComponentState extends State<ColumnBlockComponent>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  final columnKey = GlobalKey();

  late final EditorState editorState = context.read<EditorState>();

  @override
  Widget build(BuildContext context) {
    final children = node.children.toList();
    Widget child = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children.isEmpty
          // Only for the frame before the columns block repairs this column.
          ? const [SizedBox(height: 24)]
          : [
              for (final e in children) editorState.renderer.build(context, e),
            ],
    );

    child = Padding(
      key: columnKey,
      padding: padding,
      child: child,
    );

    return child;
  }

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
    final renderBox = columnKey.currentContext?.findRenderObject();
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
