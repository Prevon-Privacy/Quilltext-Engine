import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/base_component/selection/selection_area_painter.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/selection/mobile_selection_service.dart';
import 'package:prevon_quilltext_engine/src/render/selection/cursor.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

final _deepEqual = const DeepCollectionEquality().equals;

enum BlockSelectionType {
  cursor,
  selection,
  block,
}

/// [BlockSelectionArea] is a widget that renders the selection area or the cursor of a block.
class BlockSelectionArea extends StatefulWidget {
  const BlockSelectionArea({
    super.key,
    required this.node,
    required this.delegate,
    required this.listenable,
    required this.cursorColor,
    required this.selectionColor,
    required this.blockColor,
    this.supportTypes = const [
      BlockSelectionType.cursor,
      BlockSelectionType.selection,
    ],
  });

  // get the cursor rect or selection rects from the delegate
  final SelectableMixin delegate;

  // get the selection from the listenable
  final ValueListenable<Selection?> listenable;

  // the color of the cursor
  final Color cursorColor;

  // the color of the selection
  final Color selectionColor;

  final Color blockColor;

  // the node of the block
  final Node node;

  final List<BlockSelectionType> supportTypes;

  @override
  State<BlockSelectionArea> createState() => _BlockSelectionAreaState();
}

class _BlockSelectionAreaState extends State<BlockSelectionArea> {
  // We need to keep the key to refresh the cursor status when typing continuously.
  late GlobalKey cursorKey = GlobalKey(
    debugLabel: 'cursor_${widget.node.path}',
  );

  // keep the previous cursor rect to avoid unnecessary rebuild
  Rect? prevCursorRect;
  // keep the previous selection rects to avoid unnecessary rebuild
  List<Rect>? prevSelectionRects;
  // keep the block selection rect to avoid unnecessary rebuild
  Rect? prevBlockRect;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSelectionIfNeeded();
    });
    _wasInSelection = _isInSelection();
    widget.listenable.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onSelectionChanged);

    super.dispose();
  }

  // PREVON PATCH: every visible block holds one or more of these, and the
  // selection notifier fires on every keystroke. Upstream rebuilt all of them
  // each time (hundreds of builders per key in a long note) although only the
  // blocks the selection touches can draw anything. A block now rebuilds only
  // when it was in the selection or is in it now.
  bool _wasInSelection = false;

  bool _isInSelection() {
    final selection = widget.listenable.value?.normalized;
    return selection != null && widget.node.path.inSelection(selection);
  }

  void _onSelectionChanged() {
    _clearCursorRect();
    final nowIn = _isInSelection();
    final relevant = nowIn || _wasInSelection;
    _wasInSelection = nowIn;
    if (relevant && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey(widget.node.id + widget.supportTypes.toString()),
      child: Builder(builder: (context) {
        const sizedBox = SizedBox.shrink();
        final selection = widget.listenable.value?.normalized;

        if (selection == null) {
          return sizedBox;
        }

        final path = widget.node.path;
        if (!path.inSelection(selection)) {
          return sizedBox;
        }

        final editorState = context.read<EditorState>();
        if (editorState.selectionType == SelectionType.block) {
          if (!widget.supportTypes.contains(BlockSelectionType.block) ||
              !path.inSelection(selection, isSameDepth: true) ||
              prevBlockRect == null) {
            return sizedBox;
          }
          final builder = editorState.service.rendererService
              .blockComponentBuilder(widget.node.type);
          final padding = builder?.configuration.blockSelectionAreaMargin(
            widget.node,
          );
          return Positioned.fromRect(
            rect: prevBlockRect!,
            child: Container(
              margin: padding,
              decoration: BoxDecoration(
                color: widget.blockColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }
        // show the cursor when the selection is collapsed
        else if (selection.isCollapsed) {
          if (!widget.supportTypes.contains(BlockSelectionType.cursor) ||
              prevCursorRect == null) {
            return sizedBox;
          }
          final editorState = context.read<EditorState>();
          final dragMode =
              editorState.selectionExtraInfo?[selectionDragModeKey];
          final shouldBlink = widget.delegate.shouldCursorBlink &&
              dragMode != MobileSelectionDragMode.cursor;
          final cursor = Cursor(
            key: cursorKey,
            rect: prevCursorRect!,
            shouldBlink: shouldBlink,
            cursorStyle: widget.delegate.cursorStyle,
            color: widget.cursorColor,
          );
          // force to show the cursor
          cursorKey.currentState?.unwrapOrNull<CursorState>()?.show();
          return cursor;
        } else {
          // show the selection area when the selection is not collapsed
          if (!widget.supportTypes.contains(BlockSelectionType.selection) ||
              prevSelectionRects == null ||
              prevSelectionRects!.isEmpty ||
              (prevSelectionRects!.length == 1 &&
                  prevSelectionRects!.first.width == 0)) {
            return sizedBox;
          }
          return SelectionAreaPaint(
            rects: prevSelectionRects!,
            selectionColor: widget.selectionColor,
          );
        }
      }),
    );
  }

  void _updateSelectionIfNeeded() {
    if (!mounted) {
      return;
    }

    final selection = widget.listenable.value?.normalized;
    final path = widget.node.path;

    // the current path is in the selection
    if (selection != null && path.inSelection(selection)) {
      if (widget.supportTypes.contains(BlockSelectionType.block) &&
          context.read<EditorState>().selectionType == SelectionType.block) {
        if (!path.inSelection(selection, isSameDepth: true)) {
          if (prevBlockRect != null) {
            setState(() {
              prevBlockRect = null;
              prevCursorRect = null;
              prevSelectionRects = null;
            });
          }
        } else {
          final rect = widget.delegate.getBlockRect();
          if (prevBlockRect != rect) {
            setState(() {
              prevBlockRect = rect;
              prevCursorRect = null;
              prevSelectionRects = null;
            });
          }
        }
      } else if (widget.supportTypes.contains(BlockSelectionType.cursor) &&
          selection.isCollapsed) {
        final rect = widget.delegate.getCursorRectInPosition(selection.start);
        if (rect != prevCursorRect) {
          setState(() {
            prevCursorRect = rect;
            prevBlockRect = null;
            prevSelectionRects = null;
          });
        }
      } else if (widget.supportTypes.contains(BlockSelectionType.selection)) {
        final rects = widget.delegate.getRectsInSelection(selection);
        if (!_deepEqual(rects, prevSelectionRects)) {
          setState(() {
            prevSelectionRects = rects;
            prevCursorRect = null;
            prevBlockRect = null;
          });
        }
      }
    } else if (prevBlockRect != null ||
        prevSelectionRects != null ||
        prevCursorRect != null) {
      setState(() {
        prevBlockRect = null;
        prevSelectionRects = null;
        prevCursorRect = null;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _updateSelectionIfNeeded();
    });
  }

  void _clearCursorRect() {
    prevCursorRect = null;
  }
}
