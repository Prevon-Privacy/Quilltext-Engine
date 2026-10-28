import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/base_component/widget/ignore_parent_gesture.dart';
import 'package:prevon_quilltext_engine/src/flutter/scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PageBlockKeys {
  static const String type = 'page';
}

Node pageNode({
  required Iterable<Node> children,
  Attributes attributes = const {},
}) {
  return Node(
    type: PageBlockKeys.type,
    children: children,
    attributes: attributes,
  );
}

class PageBlockComponentBuilder extends BlockComponentBuilder {
  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    return PageBlockComponent(
      key: blockComponentContext.node.key,
      node: blockComponentContext.node,
      header: blockComponentContext.header,
      footer: blockComponentContext.footer,
      wrapper: blockComponentContext.wrapper,
    );
  }
}

class PageBlockComponent extends BlockComponentStatelessWidget {
  const PageBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.header,
    this.footer,
    this.wrapper,
  });

  final Widget? header;
  final Widget? footer;
  final BlockComponentWrapper? wrapper;

  @override
  Widget build(BuildContext context) {
    final editorState = context.read<EditorState>();
    final scrollController = context.read<EditorScrollController?>();
    final items = node.children;

    if (scrollController == null || scrollController.shrinkWrap) {
      return SingleChildScrollView(
        child: Builder(
          builder: (context) {
            final scroller = Scrollable.maybeOf(context);
            if (scroller != null) {
              editorState.updateAutoScroller(scroller);
            }
            return Column(
              children: [
                if (header != null) header!,
                ...items.map(
                  (e) {
                    Widget child = editorState.renderer.build(context, e);
                    if (wrapper != null) {
                      child = wrapper!(context, node: e, child: child);
                    }
                    return Container(
                      constraints: BoxConstraints(
                        maxWidth:
                            editorState.editorStyle.maxWidth ?? double.infinity,
                      ),
                      padding: editorState.editorStyle.padding,
                      child: child,
                    );
                  },
                ),
                if (footer != null) footer!,
              ],
            );
          },
        ),
      );
    } else {
      int extentCount = 0;
      if (header != null) extentCount++;
      if (footer != null) extentCount++;
      final firstBlockIndex = header != null ? 1 : 0;
      final itemCount = items.length + extentCount;
      // PREVON PATCH 29b: each list slot is keyed by its block, not its index,
      // so inserting or removing a block moves the blocks below it instead of
      // rebuilding them (see PositionedList.itemId).
      Map<Node, int>? blockIndexes;

      return ScrollablePositionedList.builder(
        shrinkWrap: scrollController.shrinkWrap,
        scrollDirection: Axis.vertical,
        itemCount: itemCount,
        itemId: (index) {
          if (header != null && index == 0) return _headerSlot;
          if (footer != null && index == itemCount - 1) return _footerSlot;
          return items[index - firstBlockIndex];
        },
        indexOfItemId: (id) {
          if (identical(id, _headerSlot)) return header != null ? 0 : null;
          if (identical(id, _footerSlot)) {
            return footer != null ? itemCount - 1 : null;
          }
          blockIndexes ??= {
            for (var i = 0; i < items.length; i++)
              items[i]: i + firstBlockIndex,
          };
          return blockIndexes![id];
        },
        itemBuilder: (context, index) {
          editorState.updateAutoScroller(Scrollable.of(context));
          if (header != null && index == 0) {
            return IgnoreEditorSelectionGesture(
              child: header!,
            );
          }

          if (footer != null && index == (items.length - 1) + extentCount) {
            return IgnoreEditorSelectionGesture(
              child: footer!,
            );
          }

          final node = items[index - (header != null ? 1 : 0)];
          final cached = _stableItems[node];
          if (cached != null &&
              cached.isValidFor(editorState, wrapper, _followed(node))) {
            return cached.widget;
          }
          Widget child = editorState.renderer.build(
            context,
            node,
          );
          if (wrapper != null) {
            child = wrapper!(context, node: node, child: child);
          }

          final blockContainer = Container(
            constraints: BoxConstraints(
              maxWidth: editorState.editorStyle.maxWidth ?? double.infinity,
            ),
            padding: editorState.editorStyle.padding,
            child: child,
          );

          // PREVON PATCH 7: only centre the block column when the editor has a
          // fixed `maxWidth` (the "page" look). With no maxWidth, `Center` +
          // an infinity-width Container shrink-wraps narrow blocks (a table,
          // a divider) and floats them in the middle of the editor while text
          // blocks fill the width and read as left-aligned. The shrinkWrap
          // code path above never wrapped in `Center`; this makes both paths
          // consistent so a table sits in the normal left-aligned flow.
          final item = editorState.editorStyle.maxWidth != null
              ? Center(child: blockContainer)
              : blockContainer;
          if (_stableItemTypes.contains(node.type)) {
            _stableItems[node] =
                _StableItem(editorState, wrapper, item, _followed(node));
          }
          return item;
        },
        itemScrollController: scrollController.itemScrollController,
        scrollOffsetController: scrollController.scrollOffsetController,
        itemPositionsListener: scrollController.itemPositionsListener,
        scrollOffsetListener: scrollController.scrollOffsetListener,
      );
    }
  }
}

const Object _headerSlot = 'page header';
const Object _footerSlot = 'page footer';

/// PREVON PATCH 29b: block types whose rendering depends only on their own
/// node (text and attributes, which the block's own `Consumer<Node>` follows),
/// plus what [_followed] names: a bullet follows its ancestors (a page-level one
/// has none), a numbered item its marker, and a checklist row follows its
/// completed pile through its own transaction listener (PATCH 30).
const _stableItemTypes = {
  ParagraphBlockKeys.type,
  HeadingBlockKeys.type,
  QuoteBlockKeys.type,
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
  TodoListBlockKeys.type,
};

/// What, besides the node itself, a reusable item's rendering follows: a numbered
/// item shows its place in the run, so it is rebuilt when that marker changes.
Object? _followed(Node node) =>
    node.type == NumberedListBlockKeys.type ? numberedListLabel(node) : null;

/// The last widget built for a block in [_stableItemTypes]. Inserting or
/// removing a block notifies the page, which used to rebuild every visible
/// block (Enter in a long note rebuilt thousands of widgets). Handing the list
/// the SAME widget instance lets Flutter skip the block entirely, also when it
/// only moved to another index (its GlobalKey carries the element along).
final Expando<_StableItem> _stableItems = Expando<_StableItem>('page item');

class _StableItem {
  _StableItem(this.editorState, this.wrapper, this.widget, this.followed)
      : style = editorState.editorStyle,
        renderer = editorState.renderer;

  final EditorState editorState;
  final BlockComponentWrapper? wrapper;
  final Widget widget;
  final EditorStyle style;
  final BlockComponentRendererService renderer;
  final Object? followed;

  /// The item bakes in the style, the renderer and the wrapper: a change in any
  /// of them (a text-size or theme change replaces the style) builds it again.
  bool isValidFor(
    EditorState state,
    BlockComponentWrapper? currentWrapper,
    Object? currentFollowed,
  ) =>
      identical(editorState, state) &&
      identical(wrapper, currentWrapper) &&
      identical(style, state.editorStyle) &&
      identical(renderer, state.renderer) &&
      followed == currentFollowed;
}
