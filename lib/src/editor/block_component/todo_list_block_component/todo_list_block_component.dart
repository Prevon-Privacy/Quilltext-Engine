import 'dart:async';

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

  /// Set on the rows of a completed group that was dragged away from the
  /// bottom of its run, so the group keeps its "N done" divider (and stays
  /// checked) wherever it lands. Cleared when a row is (re)checked.
  static const String completedGroup = 'completed_group';

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
/// widget stays free of the app's l10n layer. The host app sets these at startup.
class TodoListStrings {
  TodoListStrings._();

  static String itemDeleted = 'Checklist item deleted';
  static String undo = 'Undo';

  /// Host hook: announce a delete-style removal. [undo] restores the row. When
  /// null, the widget falls back to a plain SnackBar. The host app routes this to
  /// its top-of-screen toaster so the notice matches every other app toast.
  static void Function(VoidCallback undo)? onItemDeleted;

  /// Host hook: announce that the divider's "delete completed" control removed
  /// [count] rows in one transaction. [undo] restores them all. No fallback:
  /// when null the delete stays silent (the host owns how it is announced).
  static void Function(int count, VoidCallback undo)? onCompletedDeleted;

  /// PREVON PATCH 10 — label on the collapsible "completed" divider, e.g. "3 done".
  static String Function(int count) completedCount = (count) => '$count done';

  /// PREVON PATCH 10 — a11y label for the divider's expand/collapse control.
  static String completedSectionToggle = 'Show or hide completed items';

  /// PREVON PATCH 10 — label/a11y text for the divider's "uncheck all" control.
  static String uncheckAll = 'Uncheck all';

  /// PREVON PATCH 10 — label/a11y text for the divider's "delete completed" control.
  static String deleteCompleted = 'Delete completed items';
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

/// Like [todoSinkRunView] but resolved for the completed group that contains
/// [row]: the bottom pile, or a group dragged elsewhere (rows both checked and
/// flagged [TodoListBlockKeys.completedGroup]). `completedStart` is -1 when
/// [row] belongs to neither; `end` is the group's last sibling index.
({
  int lo,
  int hi,
  int completedStart,
  int completedCount,
  int end,
  bool collapsed
})? todoCompletedGroupView(Node row) {
  final base = todoSinkRunView(row);
  final parent = row.parent;
  if (base == null || parent == null) return null;
  final children = parent.children;
  final idx = children.indexOf(row);
  if (base.completedStart >= 0 && idx >= base.completedStart) {
    return (
      lo: base.lo,
      hi: base.hi,
      completedStart: base.completedStart,
      completedCount: base.completedCount,
      end: base.hi,
      collapsed: base.collapsed,
    );
  }
  bool inGroup(int i) =>
      children[i].attributes[TodoListBlockKeys.checked] == true &&
      children[i].attributes[TodoListBlockKeys.completedGroup] == true;
  if (idx < 0 || !inGroup(idx)) {
    return (
      lo: base.lo,
      hi: base.hi,
      completedStart: -1,
      completedCount: 0,
      end: -1,
      collapsed: base.collapsed,
    );
  }
  var start = idx;
  var end = idx;
  while (start - 1 >= base.lo && inGroup(start - 1)) {
    start--;
  }
  while (end + 1 <= base.hi && inGroup(end + 1)) {
    end++;
  }
  return (
    lo: base.lo,
    hi: base.hi,
    completedStart: start,
    completedCount: end - start + 1,
    end: end,
    collapsed: base.collapsed,
  );
}

/// Uncheck every row in the completed pile of [row]'s checklist run. The rows
/// keep their current position — with none of them checked, the sink
/// invariant (checked rows collect at the bottom) has nothing left to
/// maintain, so no reordering is needed. No-op when [row] is not sink-style
/// or has no completed pile.
void uncheckAllInTodoRun(EditorState editorState, Node row) {
  final info = todoCompletedGroupView(row);
  final parent = row.parent;
  if (info == null || parent == null || info.completedStart < 0) return;
  final transaction = editorState.transaction;
  for (var i = info.completedStart; i <= info.end; i++) {
    transaction.updateNode(parent.children[i], {
      TodoListBlockKeys.checked: false,
      TodoListBlockKeys.completedGroup: false,
    });
  }
  transaction.afterSelection = null;
  editorState.apply(transaction, withUpdateSelection: false);
}

/// Applies a delete that the host announces with an Undo button, as its own
/// history item. The previous item is sealed first and this one right after, so
/// the toast's Undo reverts exactly this delete and never a just-typed edit.
void _applyAsOwnHistoryItem(EditorState editorState, Transaction transaction) {
  final stack = editorState.undoManager.undoStack;
  if (stack.isNonEmpty) stack.last.seal();
  editorState.apply(
    transaction,
    withUpdateSelection: false,
    skipHistoryDebounce: true,
  );
}

/// Delete every row in the completed pile of [row]'s checklist run (children
/// go with their row). One transaction, so a single undo restores them all.
/// Never leaves the parent empty. No-op when there is no completed pile.
/// Returns how many rows were deleted (0 for the no-op).
int deleteCompletedInTodoRun(EditorState editorState, Node row) {
  final info = todoCompletedGroupView(row);
  final parent = row.parent;
  if (info == null || parent == null || info.completedStart < 0) return 0;
  final doomed = [
    for (var i = info.completedStart; i <= info.end; i++) parent.children[i],
  ];
  final transaction = editorState.transaction;
  if (doomed.length == parent.children.length) {
    transaction.insertNode(doomed.first.path, paragraphNode());
  }
  transaction.deleteNodesAtPath(doomed.first.path, doomed.length);
  transaction.afterSelection = null;
  _applyAsOwnHistoryItem(editorState, transaction);
  return doomed.length;
}

/// Moves the whole completed group (the divider and its rows) of [row]'s
/// checklist run to sibling index [targetIndex] — an index in the *current*
/// document, before the move — among the same parent's children. Dropping
/// inside or right next to the group itself is a no-op. One transaction, so
/// one undo. Returns true when a transaction was applied.
bool moveTodoCompletedGroup(
    EditorState editorState, Node row, int targetIndex) {
  final info = todoCompletedGroupView(row);
  final parent = row.parent;
  if (info == null || parent == null || info.completedStart < 0) return false;
  final start = info.completedStart;
  final count = info.completedCount;
  final target = targetIndex.clamp(0, parent.children.length);
  if (target >= start && target <= start + count) return false;
  final rows = parent.children.sublist(start, start + count);
  // Flag the rows so the group keeps its divider (and stays checked) even when
  // it no longer sits at the bottom of the run.
  final transaction = editorState.transaction;
  for (final r in rows) {
    transaction.updateNode(r, {TodoListBlockKeys.completedGroup: true});
  }
  transaction
    ..deleteNodesAtPath([...parent.path, start], count)
    ..insertNodes([...parent.path, target], rows,
        deepCopy: false); // transaction.add re-bases it past the delete
  transaction.afterSelection = null;
  editorState.apply(transaction, withUpdateSelection: false);
  return true;
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

  // Update in place, then relocate the SAME node object via `moveNode` — the
  // identical mechanism `moveTodoRowWithinRun` (drag-to-reorder) already uses.
  // This previously built a brand-new `Node` with `row.copyWith(...)` and
  // deleted/inserted that copy instead of `row` itself, which breaks the
  // node's identity (a fresh id + GlobalKey). The old widget briefly stayed
  // mounted while its replacement mounted at the new position, which is what
  // showed up as the "done" indicator/divider rendering twice on check.
  final transaction = editorState.transaction
    ..updateNode(row, {
      TodoListBlockKeys.checked: willCheck,
      if (willCheck) TodoListBlockKeys.completedGroup: false,
    });
  if (target != idx) {
    // `moveNode` is `deleteNode` + `insertNode`, same as the old manual pair
    // below did — so the insert index still needs the same +1 correction when
    // moving down past its own deleted slot.
    final insertIndex = idx < target ? target + 1 : target;
    transaction.moveNode([...path.parent, insertIndex], row);
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

/// PREVON PATCH 23 — wraps the whole rendered block (the row plus its nested
/// rows) of a TOP-LEVEL checklist row that has children, so the host can draw
/// connector rails over the nest. Never called for a row inside another
/// checklist row, nor for a row with no children.
typedef TodoChildrenDecorator = Widget Function(
  BuildContext context,
  Node root,
  Widget content,
);

class TodoListBlockComponentBuilder extends BlockComponentBuilder {
  TodoListBlockComponentBuilder({
    super.configuration,
    this.textStyleBuilder,
    this.iconBuilder,
    this.toggleChildrenTriggers,
    this.childrenDecorator,
    this.labelVerticalInset,
  });

  /// PATCH 23: see [TodoChildrenDecorator].
  final TodoChildrenDecorator? childrenDecorator;

  /// PREVON PATCH 25 — vertical space (above and below) reserved around the
  /// label INSIDE the row instead of in the block padding, so a host's icon slot
  /// can be taller than the label's first line and still be a real hit target
  /// (a child is only hit-tested inside its parent's bounds, so a slot cannot
  /// reach into the block padding). The host gives the block zero vertical
  /// padding and returns the same inset here; the row's total height is
  /// unchanged. Null (the upstream behaviour) adds no inset.
  final double Function(Node node)? labelVerticalInset;

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
      childrenDecorator: childrenDecorator,
      labelVerticalInset: labelVerticalInset,
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
    this.childrenDecorator,
    this.labelVerticalInset,
  });

  final TextStyle Function(bool checked)? textStyleBuilder;
  final TodoListIconBuilder? iconBuilder;
  final List<LogicalKeyboardKey>? toggleChildrenTriggers;
  final TodoChildrenDecorator? childrenDecorator;
  final double Function(Node node)? labelVerticalInset; // PATCH 25

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

  /// Desktop-pointer drag-to-reorder: a hover-revealed handle, dragged with
  /// an immediate mouse-down. On web / touch the row renders exactly as
  /// upstream — [_todoTouchReorderEnabled] covers touch instead.
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

  // The divider and the Offstage state of a row depend on its SIBLINGS (which
  // row starts the completed pile, how many are done), but a row is only told to
  // rebuild when its own node changes. Checking bottom-up moves the pile's start
  // to a new row and leaves the old start row untouched, so it kept drawing its
  // own divider — one "done" line per check. Rebuild whenever the run's view
  // changes.
  BlockReorderSession? _groupSession;
  StreamSubscription<EditorTransactionValue>? _runViewSub;
  Object? _runViewSig;

  Object? _runViewSignature() {
    final v = todoCompletedGroupView(node);
    if (v == null) return null;
    return (
      node.path.last,
      v.completedStart,
      v.completedCount,
      v.collapsed,
      v.end
    );
  }

  @override
  void initState() {
    super.initState();
    _runViewSig = _runViewSignature();
    _runViewSub = editorState.transactionStream.listen((_) {
      if (!mounted) return;
      final sig = _runViewSignature();
      if (sig != _runViewSig) {
        _runViewSig = sig;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _runViewSub?.cancel();
    _groupSession?.dispose();
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
    final info = todoCompletedGroupView(node);
    final count = info?.completedCount ?? 0;
    final collapsed = info?.collapsed ?? true;
    final base = editorState.editorStyle.textStyleConfiguration.text.color
            ?.withValues(alpha: 0.55) ??
        const Color(0xFF808080);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => toggleTodoRunCompletedCollapsed(editorState, node),
        child: Semantics(
          button: true,
          label: TodoListStrings.completedSectionToggle,
          child: Row(
            children: [
              // Hold the label area to move the whole completed group, like a
              // bullet. A plain tap still reaches the expand/collapse toggle
              // underneath (the overlay is hit-test translucent).
              Expanded(
                child: Stack(
                  children: [
                    Row(
                      children: [
                        Icon(
                          collapsed ? Icons.expand_more : Icons.expand_less,
                          size: 22,
                          color: base,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          TodoListStrings.completedCount(count),
                          style:
                              TextStyle(fontSize: 16, height: 1.0, color: base),
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
                    Positioned.fill(
                      child: TouchReorderHandle(
                        data: node,
                        color: base,
                        invisible: true,
                        feedback: _buildGroupDragFeedback(base, count),
                        onDragStarted: () {
                          _groupSession?.dispose();
                          _groupSession = BlockReorderSession(
                            editorState,
                            node,
                            onDrop: (t) =>
                                moveTodoCompletedGroup(editorState, node, t),
                          )..start();
                        },
                        onDragUpdate: (d) =>
                            _groupSession?.update(d.globalPosition),
                        onDragEnd: ({required bool dropped}) =>
                            _groupSession?.finish(dropped: dropped),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: TodoListStrings.uncheckAll,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => uncheckAllInTodoRun(editorState, node),
                  child: Icon(Icons.replay, size: 22, color: base),
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                button: true,
                label: TodoListStrings.deleteCompleted,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final removed = deleteCompletedInTodoRun(editorState, node);
                    if (removed > 0) {
                      TodoListStrings.onCompletedDeleted
                          ?.call(removed, editorState.undoManager.undo);
                    }
                  },
                  child: Icon(Icons.delete_outline, size: 22, color: base),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupDragFeedback(Color base, int count) => Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 8),
            ],
          ),
          child: Text(
            TodoListStrings.completedCount(count),
            style: TextStyle(fontSize: 16, color: base),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final info = todoCompletedGroupView(node);
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
    if (idx > info.completedStart && idx <= info.end) {
      return Offstage(offstage: info.collapsed, child: super.build(context));
    }
    return super.build(context);
  }

  // PREVON PATCH 23: let the host decorate a top-level row's whole nest.
  @override
  Widget buildComponentWithChildren(BuildContext context) {
    final content = super.buildComponentWithChildren(context);
    final decorate = widget.childrenDecorator;
    if (decorate == null || node.parent?.type == TodoListBlockKeys.type) {
      return content;
    }
    return decorate(context, node, content);
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
          if (_todoReorderEnabled)
            _buildTodoDragHandle(context), // PREVON PATCH 9
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
            child: Padding(
              // PREVON PATCH 25: see [TodoListBlockComponentBuilder.labelVerticalInset].
              padding: EdgeInsets.symmetric(
                vertical: widget.labelVerticalInset?.call(node) ?? 0,
              ),
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

    // PATCH 14: fade the row while it is being dragged.
    child = ReorderDimmed(node: node, child: child);

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
    final baseColor =
        editorState.editorStyle.textStyleConfiguration.text.color ??
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

    // PATCH 25: the label now sits `inset` below the row's top, so the grip is a
    // box as tall as the label's first line plus that inset on both sides, with
    // the glyph centred in it — the same centre as the host's checkbox slot.
    final inset = widget.labelVerticalInset?.call(node) ?? 0;
    final config = editorState.editorStyle.textStyleConfiguration;
    final painter = TextPainter(
      text: TextSpan(text: 'Hg', style: config.text),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(editorState.editorStyle.textScaleFactor),
      textHeightBehavior: TextHeightBehavior(
        applyHeightToFirstAscent: config.applyHeightToFirstAscent,
        applyHeightToLastDescent: config.applyHeightToLastDescent,
        leadingDistribution: config.leadingDistribution,
      ),
      maxLines: 1,
    )..layout();
    final slotHeight = painter.height + 2 * inset;
    painter.dispose();
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: SizedBox(
        width: 20,
        height: inset == 0 ? null : slotHeight,
        child: Draggable<Node>(
          data: node,
          dragAnchorStrategy: rowAnchoredDragAnchor(node),
          axis: Axis.vertical,
          onDragStarted: _startTodoDrag,
          onDragUpdate: _onTodoDragUpdate,
          onDragEnd: (_) => _finishTodoDrag(dropped: true),
          onDraggableCanceled: (_, __) => _finishTodoDrag(dropped: false),
          feedback: ReorderDragFeedback(node: node, editorState: editorState),
          childWhenDragging: Opacity(opacity: 0.3, child: handle),
          child: handle,
        ),
      ),
    );
  }

  Path? _lastTickPath;

  void _startTodoDrag() {
    _todoDragActive = true;
    reorderDraggingNode.value = node;
  }

  void _onTodoDragUpdate(DragUpdateDetails details) {
    _lastDragGlobal = details.globalPosition;
    editorState.selectionService.renderDropTargetForOffset(
      details.globalPosition,
      interceptor: _clampDropToParent,
    );
    editorState.scrollService?.startAutoScroll(details.globalPosition);
    final slot = editorState.selectionService
        .getDropTargetRenderData(
          details.globalPosition,
          interceptor: _clampDropToParent,
        )
        ?.dropPath;
    if (slot != null &&
        (_lastTickPath == null || !slot.equals(_lastTickPath!))) {
      if (_lastTickPath != null) reorderDropTick();
      _lastTickPath = slot;
    }
  }

  void _finishTodoDrag({required bool dropped}) {
    reorderDraggingNode.value = null;
    _lastTickPath = null;
    editorState.selectionService.removeDropTarget();
    editorState.scrollService?.stopAutoScroll();
    final wasActive = _todoDragActive;
    _todoDragActive = false;
    final global = _lastDragGlobal;
    _lastDragGlobal = null;
    if (!dropped || !wasActive || global == null) return;

    final data = editorState.selectionService.getDropTargetRenderData(
      global,
      interceptor: _clampDropToParent,
    );
    final dropPath = data?.dropPath;
    if (dropPath == null) return;
    // A checklist row can go anywhere among its siblings — above/below other
    // checklist rows, paragraphs, bullets, headings — exactly like every other
    // block. It never changes nesting level (same parent only).
    if (!dropPath.parent.equals(node.path.parent)) return;
    moveNodeAmongSiblings(editorState, node, dropPath.last);
  }

  /// Keeps the drop indicator / drop path among the dragged row's own
  /// siblings: any hovered node outside that set resolves to the nearest
  /// boundary sibling.
  Node _clampDropToParent(BuildContext context, Node candidate) {
    final parent = node.parent;
    if (parent == null) return candidate;

    Node? c = candidate;
    while (c != null && c.parent != parent) {
      c = c.parent;
    }
    return c ?? parent.children.first;
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
    _applyAsOwnHistoryItem(editorState, transaction);

    final hook = TodoListStrings.onItemDeleted;
    if (hook != null) {
      hook(editorState.undoManager.undo);
      return;
    }

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
