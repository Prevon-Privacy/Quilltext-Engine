import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/foundation.dart'; // PREVON PATCH 9: kIsWeb / defaultTargetPlatform
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class TodoListBlockKeys {
  const TodoListBlockKeys._();

  static const String type = 'todo_list';

  /// The checked data of a todo list block.
  ///
  /// The value is a boolean.
  static const String checked = 'checked';

  /// What happens to the row when it is checked. One of [todoCompletionStrike],
  /// [todoCompletionSink], [todoCompletionDelete]. Absent → [kTodoDefaultCompletionStyle].
  ///
  /// PREVON PATCH 6 — see VENDOR_NOTES.md.
  static const String completionStyle = 'completion_style';

  /// Whether the "completed" section of a sink-style checklist run is collapsed
  /// (checked rows hidden behind a "N done" divider). Written across the whole
  /// run. Absent → collapsed (the default). PREVON PATCH 10 — see VENDOR_NOTES.md.
  static const String completedCollapsed = 'completed_collapsed';

  static const String delta = blockComponentDelta;

  static const String backgroundColor = blockComponentBackgroundColor;

  static const String textDirection = blockComponentTextDirection;
}

// ── PREVON PATCH 6: checkbox completion styles ──────────────────────────────
/// Grey + strikethrough, stays in place (the upstream behavior).
const String todoCompletionStrike = 'strike';

/// Grey + strikethrough, and the row reorders to the bottom of its contiguous
/// checklist run (Google-Keep style). Unchecking floats it back up.
const String todoCompletionSink = 'sink';

/// Checking removes the row from the document (with an Undo SnackBar).
const String todoCompletionDelete = 'delete';

/// The style a checklist uses when it carries no explicit
/// [TodoListBlockKeys.completionStyle] attribute.
const String kTodoDefaultCompletionStyle = todoCompletionSink;

/// Host-injected strings for the delete-style Undo SnackBar, so this vendored
/// widget stays free of the app's l10n layer. Pie Notes sets these at startup.
class TodoListStrings {
  TodoListStrings._();

  static String itemDeleted = 'Checklist item deleted';
  static String undo = 'Undo';

  /// PREVON PATCH 10 — label on the collapsible "completed" divider, e.g. "3 done".
  static String Function(int count) completedCount = (count) => '$count done';

  /// PREVON PATCH 10 — a11y label for the divider's expand/collapse control.
  static String completedSectionToggle = 'Show or hide completed items';
}

// ── PREVON PATCH 9: drag-to-reorder checklist rows ─────────────────────────
// A checklist row can be dragged (desktop) or moved with a host keyboard
// shortcut to a new position *within its own contiguous `todo_list` run*. It can
// never leave that run — not into a table, a heading, or another list. Indented
// sub-items ride along because they are already `row.children`.

/// The `[lo, hi]` sibling-index bounds (inclusive) of the contiguous run of
/// `todo_list` nodes that [row] belongs to, or null when [row] is not a
/// `todo_list` or has no parent.
({int lo, int hi})? todoRunBoundsOf(Node row) {
  if (row.type != TodoListBlockKeys.type) return null;
  final parent = row.parent;
  if (parent == null) return null;
  final siblings = parent.children;
  final idx = siblings.indexOf(row);
  if (idx < 0) return null;
  var lo = idx;
  var hi = idx;
  while (lo - 1 >= 0 && siblings[lo - 1].type == TodoListBlockKeys.type) {
    lo--;
  }
  while (hi + 1 < siblings.length &&
      siblings[hi + 1].type == TodoListBlockKeys.type) {
    hi++;
  }
  return (lo: lo, hi: hi);
}

/// Moves [row] so it sits at sibling index [targetIndex] — an index in the
/// *current* document, before the move. The index is clamped to [row]'s
/// checklist run, so this can only ever reorder within that run. No-ops when the
/// move changes nothing or the run has a single row. The row's children move
/// with it. Returns true when a transaction was applied.
bool moveTodoRowWithinRun(EditorState editorState, Node row, int targetIndex) {
  final bounds = todoRunBoundsOf(row);
  if (bounds == null || bounds.lo == bounds.hi) return false;
  final current = row.path.last;
  final target = targetIndex.clamp(bounds.lo, bounds.hi + 1);
  // Dropping onto your own slot (or the gap immediately after it) is a no-op.
  if (target == current || target == current + 1) return false;
  final transaction = editorState.transaction
    ..moveNode([...row.path.parent, target], row);
  transaction.afterSelection = null;
  editorState.apply(transaction, withUpdateSelection: false);
  return true;
}

// ── PREVON PATCH 10: collapsible "completed" section ───────────────────────
/// The resolved [TodoListBlockKeys.completionStyle] of [row] (never null).
String resolvedTodoCompletionStyle(Node row) {
  final raw = row.attributes[TodoListBlockKeys.completionStyle];
  if (raw == todoCompletionStrike ||
      raw == todoCompletionSink ||
      raw == todoCompletionDelete) {
    return raw as String;
  }
  return kTodoDefaultCompletionStyle;
}

/// Aggregate view of the contiguous `todo_list` run [row] belongs to, for the
/// sink-style "completed" section. Null when [row] is not sink-style or has no
/// parent.
///
/// The "completed" pile is the **maximal contiguous run of checked rows at the
/// bottom** of the checklist run — that is what sink maintains and what the
/// divider collapses. A checked row that was dragged (PATCH 9) above an unchecked
/// row is *not* part of the pile; it renders inline (greyed). `completedStart` is
/// the pile's first sibling index, or -1 when the last row isn't checked.
/// `completedCount` counts only the pile. `collapsed` defaults to true when no
/// row in the run carries an explicit [TodoListBlockKeys.completedCollapsed].
({int lo, int hi, int completedStart, int completedCount, bool collapsed})?
    todoSinkRunView(Node row) {
  if (resolvedTodoCompletionStyle(row) != todoCompletionSink) return null;
  final parent = row.parent;
  final bounds = todoRunBoundsOf(row);
  if (parent == null || bounds == null) return null;
  final children = parent.children;

  var completedStart = -1;
  var completedCount = 0;
  for (var i = bounds.hi; i >= bounds.lo; i--) {
    if (children[i].attributes[TodoListBlockKeys.checked] == true) {
      completedStart = i;
      completedCount++;
    } else {
      break;
    }
  }

  bool? collapsed;
  for (var i = bounds.lo; i <= bounds.hi; i++) {
    final raw = children[i].attributes[TodoListBlockKeys.completedCollapsed];
    if (raw is bool) collapsed ??= raw;
  }

  return (
    lo: bounds.lo,
    hi: bounds.hi,
    completedStart: completedStart,
    completedCount: completedCount,
    collapsed: collapsed ?? true,
  );
}

/// Flip `completed_collapsed` across [row]'s whole checklist run. Returns the new
/// value, or null when [row] is not a sink-style checklist.
bool? toggleTodoRunCompletedCollapsed(EditorState editorState, Node row) {
  final info = todoSinkRunView(row);
  final parent = row.parent;
  if (info == null || parent == null) return null;
  final next = !info.collapsed;
  final transaction = editorState.transaction;
  for (var i = info.lo; i <= info.hi; i++) {
    transaction.updateNode(parent.children[i], {
      TodoListBlockKeys.completedCollapsed: next,
    });
  }
  transaction.afterSelection = null;
  editorState.apply(transaction, withUpdateSelection: false);
  return next;
}

/// PREVON PATCH 6 — set `checked` on [row] to [willCheck] and reorder it to the
/// unchecked/checked boundary of its contiguous `todo_list` run, so checked rows
/// collect at the bottom (Google-Keep "sink" style). The row's attributes
/// (including `completed_collapsed`) travel with it. Extracted from the block
/// widget so the reorder is unit-testable.
void toggleTodoRowAndSink(EditorState editorState, Node row, bool willCheck) {
  final parent = row.parent;
  final path = row.path;
  if (parent == null || path.isEmpty) {
    editorState.apply(
      editorState.transaction
        ..updateNode(row, {TodoListBlockKeys.checked: willCheck}),
      withUpdateSelection: false,
    );
    return;
  }

  final siblings = parent.children;
  final idx = path.last;
  var lo = idx;
  var hi = idx;
  while (lo - 1 >= 0 && siblings[lo - 1].type == TodoListBlockKeys.type) {
    lo--;
  }
  while (hi + 1 < siblings.length &&
      siblings[hi + 1].type == TodoListBlockKeys.type) {
    hi++;
  }

  var otherUnchecked = 0;
  for (var j = lo; j <= hi; j++) {
    if (j == idx) continue;
    if (siblings[j].attributes[TodoListBlockKeys.checked] != true) {
      otherUnchecked++;
    }
  }
  final target = lo + otherUnchecked;

  final transaction = editorState.transaction;
  if (target == idx) {
    transaction.updateNode(row, {TodoListBlockKeys.checked: willCheck});
  } else {
    final moved = row.copyWith(
      attributes: {
        ...row.attributes,
        TodoListBlockKeys.checked: willCheck,
      },
    );
    final insertIndex = idx < target ? target + 1 : target;
    transaction
      ..deleteNode(row)
      ..insertNode([...path.parent, insertIndex], moved, deepCopy: false);
    transaction.afterSelection = null;
  }
  editorState.apply(transaction, withUpdateSelection: false);
}

Node todoListNode({
  required bool checked,
  String? text,
  Delta? delta,
  String? textDirection,
  Attributes? attributes,
  Iterable<Node>? children,
}) {
  return Node(
    type: TodoListBlockKeys.type,
    attributes: {
      TodoListBlockKeys.checked: checked,
      TodoListBlockKeys.delta:
          (delta ?? (Delta()..insert(text ?? ''))).toJson(),
      if (attributes != null) ...attributes,
      if (textDirection != null) TodoListBlockKeys.textDirection: textDirection,
    },
    children: children ?? [],
  );
}

typedef TodoListIconBuilder = Widget Function(
  BuildContext context,
  Node node,
  VoidCallback onCheck,
);

class TodoListBlockComponentBuilder extends BlockComponentBuilder {
  TodoListBlockComponentBuilder({
    super.configuration,
    this.textStyleBuilder,
    this.iconBuilder,
    this.toggleChildrenTriggers,
  });

  /// The text style of the todo list block.
  final TextStyle Function(bool checked)? textStyleBuilder;

  final TodoListIconBuilder? iconBuilder;

  final List<LogicalKeyboardKey>? toggleChildrenTriggers;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return TodoListBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      textStyleBuilder: textStyleBuilder,
      iconBuilder: iconBuilder,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
      toggleChildrenTriggers: toggleChildrenTriggers,
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.delta != null;
}

class TodoListBlockComponentWidget extends BlockComponentStatefulWidget {
  const TodoListBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.textStyleBuilder,
    this.iconBuilder,
    this.toggleChildrenTriggers,
  });

  final TextStyle Function(bool checked)? textStyleBuilder;
  final TodoListIconBuilder? iconBuilder;
  final List<LogicalKeyboardKey>? toggleChildrenTriggers;

  @override
  State<TodoListBlockComponentWidget> createState() =>
      _TodoListBlockComponentWidgetState();
}

class _TodoListBlockComponentWidgetState
    extends State<TodoListBlockComponentWidget>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        NestedBlockComponentStatefulWidgetMixin,
        BlockComponentTextDirectionMixin,
        BlockComponentAlignMixin {
  @override
  final forwardKey = GlobalKey(debugLabel: 'flowy_rich_text');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: TodoListBlockKeys.type,
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  bool get checked =>
      widget.node.attributes[TodoListBlockKeys.checked] ?? false;

  // ── PREVON PATCH 9: drag-to-reorder state ───────────────────────────────
  final ValueNotifier<bool> _rowHovered = ValueNotifier<bool>(false);
  bool _todoDragActive = false;
  Offset? _lastDragGlobal;

  /// Drag-to-reorder is a desktop pointer affordance only. On web / touch the
  /// row renders exactly as upstream.
  bool get _todoReorderEnabled {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  @override
  void dispose() {
    _rowHovered.dispose();
    if (_todoDragActive) {
      editorState.selectionService.removeDropTarget();
      editorState.scrollService?.stopAutoScroll();
    }
    super.dispose();
  }

  // ── PREVON PATCH 6 ──────────────────────────────────────────────────────
  /// The resolved completion style for this row (never null).
  String get completionStyle => resolvedTodoCompletionStyle(widget.node);

  // ── PREVON PATCH 10: collapsible "completed" section (sink style only) ────
  Widget _buildCompletedDivider(BuildContext context) {
    final info = todoSinkRunView(node);
    final count = info?.completedCount ?? 0;
    final collapsed = info?.collapsed ?? true;
    final base = editorState.editorStyle.textStyleConfiguration.text.color
            ?.withValues(alpha: 0.55) ??
        const Color(0xFF808080);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => toggleTodoRunCompletedCollapsed(editorState, node),
        child: Semantics(
          button: true,
          label: TodoListStrings.completedSectionToggle,
          child: Row(
            children: [
              Icon(
                collapsed ? Icons.expand_more : Icons.expand_less,
                size: 16,
                color: base,
              ),
              const SizedBox(width: 4),
              Text(
                TodoListStrings.completedCount(count),
                style: TextStyle(fontSize: 12, color: base),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 1,
                  color: base.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = todoSinkRunView(node);
    if (info == null || info.completedStart < 0) return super.build(context);

    final idx = node.path.last;
    // Rows in the completed pile stay mounted even when collapsed — AppFlowy's
    // selection layer hard-casts every node's SelectableMixin (getBlockRect,
    // `forward`), so an unmounted node crashes the editor. `Offstage` keeps the
    // element + its GlobalKeys alive while giving it zero height and no paint /
    // hit-test.
    if (idx == info.completedStart) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCompletedDivider(context),
          Offstage(offstage: info.collapsed, child: super.build(context)),
        ],
      );
    }
    if (idx > info.completedStart && idx <= info.hi) {
      return Offstage(offstage: info.collapsed, child: super.build(context));
    }
    return super.build(context);
  }

  @override
  Widget buildComponent(
    BuildContext context, {
    bool withBackgroundColor = true,
  }) {
    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );

    Widget child = Container(
      width: double.infinity,
      alignment: alignment,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        textDirection: textDirection,
        children: [
          if (_todoReorderEnabled) _buildTodoDragHandle(context), // PREVON PATCH 9
          widget.iconBuilder != null
              ? widget.iconBuilder!(
                  context,
                  node,
                  checkOrUncheck,
                )
              : _TodoListIcon(
                  checked: checked,
                  onTap: checkOrUncheck,
                ),
          Flexible(
            child: AppFlowyRichText(
              key: forwardKey,
              delegate: this,
              node: widget.node,
              editorState: editorState,
              textAlign: alignment?.toTextAlign ?? textAlign,
              placeholderText: placeholderText,
              textDirection: textDirection,
              textSpanDecorator: (textSpan) => textSpan
                  .updateTextStyle(textStyleWithTextSpan())
                  .updateTextStyle(
                    widget.textStyleBuilder?.call(checked) ??
                        defaultTextStyle(),
                  ),
              placeholderTextSpanDecorator: (textSpan) =>
                  textSpan.updateTextStyle(
                placeholderTextStyleWithTextSpan(textSpan: textSpan),
              ),
              cursorColor: editorState.editorStyle.cursorColor,
              selectionColor: editorState.editorStyle.selectionColor,
              cursorWidth: editorState.editorStyle.cursorWidth,
            ),
          ),
        ],
      ),
    );

    child = Container(
      decoration: withBackgroundColor ? decoration : null,
      key: blockComponentKey,
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

    // PREVON PATCH 9: reveal the drag handle while the pointer is over the row.
    if (_todoReorderEnabled) {
      child = MouseRegion(
        onEnter: (_) => _rowHovered.value = true,
        onExit: (_) => _rowHovered.value = false,
        child: child,
      );
    }

    return child;
  }

  // ── PREVON PATCH 9: drag handle + drag lifecycle ───────────────────────
  Widget _buildTodoDragHandle(BuildContext context) {
    final baseColor = editorState.editorStyle.textStyleConfiguration.text.color ??
        Theme.of(context).iconTheme.color ??
        const Color(0xFF808080);
    final handle = ValueListenableBuilder<bool>(
      valueListenable: _rowHovered,
      builder: (context, hovered, _) => AnimatedOpacity(
        opacity: hovered ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 120),
        child: Icon(
          Icons.drag_indicator,
          size: 18,
          color: baseColor.withValues(alpha: hovered ? 0.55 : 0.0),
        ),
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: SizedBox(
        width: 20,
        child: Draggable<Node>(
          data: node,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () => _todoDragActive = true,
          onDragUpdate: _onTodoDragUpdate,
          onDragEnd: (_) => _finishTodoDrag(dropped: true),
          onDraggableCanceled: (_, __) => _finishTodoDrag(dropped: false),
          feedback: _buildTodoDragFeedback(context),
          childWhenDragging: Opacity(opacity: 0.3, child: handle),
          child: handle,
        ),
      ),
    );
  }

  Widget _buildTodoDragFeedback(BuildContext context) {
    final theme = Theme.of(context);
    final style = editorState.editorStyle.textStyleConfiguration.text;
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.9,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                blurRadius: 8,
                color: Colors.black.withValues(alpha: 0.15),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.drag_indicator,
                size: 16,
                color: style.color?.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  node.delta?.toPlainText() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTodoDragUpdate(DragUpdateDetails details) {
    _lastDragGlobal = details.globalPosition;
    editorState.selectionService.renderDropTargetForOffset(
      details.globalPosition,
      interceptor: _clampDropToRun,
    );
    editorState.scrollService?.startAutoScroll(details.globalPosition);
  }

  void _finishTodoDrag({required bool dropped}) {
    editorState.selectionService.removeDropTarget();
    editorState.scrollService?.stopAutoScroll();
    final wasActive = _todoDragActive;
    _todoDragActive = false;
    final global = _lastDragGlobal;
    _lastDragGlobal = null;
    if (!dropped || !wasActive || global == null) return;

    final data = editorState.selectionService.getDropTargetRenderData(
      global,
      interceptor: _clampDropToRun,
    );
    final dropPath = data?.dropPath;
    if (dropPath == null) return;
    // Never reorder across parents — the clamp keeps us in the run, this keeps
    // us in the same list level.
    if (!dropPath.parent.equals(node.path.parent)) return;
    moveTodoRowWithinRun(editorState, node, dropPath.last);
  }

  /// Forces the drop indicator / drop path to stay inside the dragged row's
  /// checklist run: any hovered node outside the run resolves to the run's
  /// nearest boundary row.
  Node _clampDropToRun(BuildContext context, Node candidate) {
    final parent = node.parent;
    final bounds = todoRunBoundsOf(node);
    if (parent == null || bounds == null) return candidate;

    Node? c = candidate;
    while (c != null && c.parent != parent) {
      c = c.parent;
    }
    if (c == null) return parent.children[bounds.lo];

    final ci = parent.children.indexOf(c);
    if (ci < bounds.lo) return parent.children[bounds.lo];
    if (ci > bounds.hi) return parent.children[bounds.hi];
    return c;
  }

  void checkOrUncheck() {
    final willCheck = !checked;
    final style = completionStyle;

    if (style == todoCompletionDelete && willCheck) {
      _deleteSelfOnCheck();
      return;
    }

    if (style == todoCompletionSink) {
      _toggleAndSink(willCheck);
      return;
    }

    // strike — and delete-style on an *uncheck* — toggle in place.
    final transaction = editorState.transaction
      ..updateNode(widget.node, {
        TodoListBlockKeys.checked: willCheck,
      });

    if (widget.toggleChildrenTriggers != null &&
        HardwareKeyboard.instance.logicalKeysPressed.any(
          (element) => widget.toggleChildrenTriggers!.contains(element),
        )) {
      checkOrUncheckChildren(willCheck, widget.node);
    }

    editorState.apply(transaction, withUpdateSelection: false);
  }

  /// Toggle `checked`, and reorder this row to the unchecked/checked boundary
  /// of its contiguous `todo_list` run so checked rows collect at the bottom.
  void _toggleAndSink(bool willCheck) =>
      toggleTodoRowAndSink(editorState, widget.node, willCheck);

  /// Delete this row (delete-style) and offer an Undo SnackBar.
  void _deleteSelfOnCheck() {
    final node = widget.node;
    final parent = node.parent;
    final path = node.path;

    if (parent == null || path.isEmpty) {
      editorState.apply(
        editorState.transaction
          ..updateNode(node, {TodoListBlockKeys.checked: true}),
        withUpdateSelection: false,
      );
      return;
    }

    final transaction = editorState.transaction;
    // Never let the document become empty: insert the replacement paragraph
    // first (at the row's path), then delete the row — the insert shifts the
    // delete target for us.
    if (parent.children.length == 1) {
      transaction.insertNode(path, paragraphNode());
    }
    transaction.deleteNode(node);
    transaction.afterSelection = null;
    editorState.apply(transaction, withUpdateSelection: false);

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(TodoListStrings.itemDeleted),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: TodoListStrings.undo,
            onPressed: editorState.undoManager.undo,
          ),
        ),
      );
  }

  void checkOrUncheckChildren(
    bool checked,
    Node node,
  ) {
    for (final child in node.children) {
      if (child.children.isNotEmpty) {
        checkOrUncheckChildren(checked, child);
      }

      if (child.type == TodoListBlockKeys.type) {
        final transaction = editorState.transaction
          ..updateNode(child, {
            TodoListBlockKeys.checked: checked,
          });

        editorState.apply(transaction);
      }
    }
  }

  TextStyle? defaultTextStyle() {
    if (!checked) {
      return null;
    }
    return TextStyle(
      decoration: TextDecoration.lineThrough,
      color: Colors.grey.shade400,
    );
  }
}

class _TodoListIcon extends StatelessWidget {
  const _TodoListIcon({
    required this.onTap,
    required this.checked,
  });

  final VoidCallback onTap;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final textScaleFactor =
        context.read<EditorState>().editorStyle.textScaleFactor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 26, minHeight: 22) *
              textScaleFactor,
          padding: const EdgeInsets.only(right: 4.0),
          child: EditorSvg(
            width: 22,
            height: 22,
            name: checked ? 'check' : 'uncheck',
          ),
        ),
      ),
    );
  }
}
