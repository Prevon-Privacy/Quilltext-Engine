import 'dart:math' as math;

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PREVON PATCH 14 — the look of a block being drag-reordered, shared by the
/// checklist grip and the generic block grip (touch and desktop):
///
///  * [rowAnchoredDragAnchor] pins the floating preview EXACTLY over the row
///    it came from, so nothing jumps when the drag starts. (The default
///    `pointerDragAnchorStrategy` puts the preview's top-left corner under the
///    finger, which shifted it down-right of the row the instant the hold
///    completed.)
///  * [ReorderDragFeedback] is that preview: the row lifted off the page as a
///    rounded, shadowed card with its marker (checkbox / bullet) and text.
///  * [reorderDraggingNode] + [ReorderDimmed] fade the source row while it is
///    in flight, so the row reads as "picked up".
///  * [reorderDropTick] gives a light haptic tick each time the drop slot
///    changes.

/// The node currently being drag-reordered, or null.
final ValueNotifier<Node?> reorderDraggingNode = ValueNotifier<Node?>(null);

/// Anchor so the drag preview's top-left sits on [node]'s row top-left.
DragAnchorStrategy rowAnchoredDragAnchor(Node node) {
  return (Draggable<Object> draggable, BuildContext context, Offset position) {
    final box = node.key.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      return position - box.localToGlobal(Offset.zero);
    }
    return pointerDragAnchorStrategy(draggable, context, position);
  };
}

/// Fades [child] while [node] is the block being dragged.
class ReorderDimmed extends StatelessWidget {
  const ReorderDimmed({super.key, required this.node, required this.child});

  final Node node;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Node?>(
      valueListenable: reorderDraggingNode,
      child: child,
      builder: (context, dragging, child) => AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: identical(dragging, node) ? 0.35 : 1.0,
        child: child,
      ),
    );
  }
}

/// A light tick when the drop slot under the finger changes.
void reorderDropTick() => HapticFeedback.selectionClick();

/// The floating "picked up" row.
class ReorderDragFeedback extends StatelessWidget {
  const ReorderDragFeedback({
    super.key,
    required this.node,
    required this.editorState,
    this.glyph,
  });

  final Node node;
  final EditorState editorState;

  /// What a block this file does not know (a block the host app registered) shows while lifted. Null: the built-in
  /// glyph for the type, or the block's text.
  final IconData? glyph;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = editorState.editorStyle.textStyleConfiguration.text;
    final color = textStyle.color ?? scheme.onSurface;

    // Read at drag start, when this widget is inserted, so it matches the
    // row's current width and height.
    final box = node.key.currentContext?.findRenderObject();
    final size = (box is RenderBox && box.hasSize) ? box.size : null;

    Widget? marker;
    switch (node.type) {
      case TodoListBlockKeys.type:
        marker = Icon(
          node.attributes[TodoListBlockKeys.checked] == true
              ? Icons.check_box
              : Icons.check_box_outline_blank,
          size: 20,
          color: color.withValues(alpha: 0.7),
        );
      case BulletedListBlockKeys.type:
        marker = Text('•', style: textStyle);
      case NumberedListBlockKeys.type:
        marker = Text('${node.path.last + 1}.', style: textStyle);
      case CollapsibleBlockKeys.type:
        marker = Icon(
          Icons.chevron_right,
          size: 20,
          color: color.withValues(alpha: 0.7),
        );
    }

    // Blocks that carry no text (divider, image, table) would otherwise lift
    // off as an empty card: show what they are instead. They can also be very
    // tall, so the preview is capped and the drag anchor (finger near the row's
    // top-left) stays inside it.
    final IconData? shown;
    switch (node.type) {
      case DividerBlockKeys.type:
        shown = Icons.horizontal_rule;
      case ImageBlockKeys.type:
        shown = Icons.image_outlined;
      case TableBlockKeys.type:
        shown = Icons.table_chart_outlined;
      case ColumnsBlockKeys.type:
        shown = Icons.view_column_outlined;
      case FileBlockKeys.type:
        shown = Icons.insert_drive_file_outlined;
      default:
        shown = glyph;
    }
    const maxPreviewHeight = 96.0;

    return Material(
      elevation: 10,
      shadowColor: Colors.black,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: size?.width ?? 0,
          maxWidth: size?.width ?? 360,
          minHeight: math.min(size?.height ?? 0, maxPreviewHeight),
          maxHeight: maxPreviewHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (marker != null) ...[
                marker,
                const SizedBox(width: 10),
              ],
              if (shown != null)
                Icon(shown, size: 24, color: color.withValues(alpha: 0.7))
              else
                Flexible(
                  child: Text(
                    node.delta?.toPlainText() ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
