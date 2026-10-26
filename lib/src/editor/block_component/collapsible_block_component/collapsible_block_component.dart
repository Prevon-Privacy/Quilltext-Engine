import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// PREVON PATCH 26 — the collapsible block ("toggle"): a one-line title with a
/// chevron that hides or shows everything nested under it, instantly. Same idea
/// as Telegram's expandable quote: keep a lot of text in the note, hide it all
/// with one tap.
///
/// Storage: a normal block node. The title is the node's `delta`, the hidden
/// body is its `children`, and the open/closed state is the existing
/// [blockComponentCollapsed] attribute (absent = open), so the state is saved
/// with the note and every older document is unaffected. Collapsing only skips
/// RENDERING the children (see [NestedBlockComponentStatefulWidgetMixin]); the
/// text stays in the document, so search and export still see it.
class CollapsibleBlockKeys {
  const CollapsibleBlockKeys._();

  static const String type = 'collapsible';

  static const String delta = blockComponentDelta;

  static const String backgroundColor = blockComponentBackgroundColor;

  static const String textDirection = blockComponentTextDirection;

  static const String collapsed = blockComponentCollapsed;
}

Node collapsibleNode({
  String? text,
  Delta? delta,
  String? textDirection,
  bool collapsed = false,
  Attributes? attributes,
  Iterable<Node>? children,
}) {
  return Node(
    type: CollapsibleBlockKeys.type,
    attributes: {
      CollapsibleBlockKeys.delta:
          (delta ?? (Delta()..insert(text ?? ''))).toJson(),
      if (collapsed) CollapsibleBlockKeys.collapsed: true,
      if (attributes != null) ...attributes,
      if (textDirection != null)
        CollapsibleBlockKeys.textDirection: textDirection,
    },
    children: children ?? [],
  );
}

/// Whether [node] is a collapsible that is currently shut AND has something
/// to hide. An empty collapsible always reads as open: there is nothing to
/// fold, so the chevron just shows the open state.
bool isCollapsibleClosed(Node node) =>
    node.type == CollapsibleBlockKeys.type &&
    node.attributes[CollapsibleBlockKeys.collapsed] == true &&
    node.children.isNotEmpty;

/// True when [path] points at a block inside [node]'s hidden body.
bool isInsideCollapsibleBody(Node node, Path path) {
  final own = node.path;
  if (path.length <= own.length) return false;
  for (var i = 0; i < own.length; i++) {
    if (path[i] != own[i]) return false;
  }
  return true;
}

/// Number of blocks hidden below [node] (every descendant).
int collapsibleHiddenCount(Node node) {
  var count = 0;
  for (final child in node.children) {
    count += 1 + collapsibleHiddenCount(child);
  }
  return count;
}

/// Open/closed is how the note looks, not what it says: it never enters the
/// undo history, so Undo keeps undoing typing instead of re-folding blocks.
const ApplyOptions _viewStateOptions = ApplyOptions(recordUndo: false);

/// Opens or closes [node] in one transaction.
///
/// Closing while the caret is inside the body moves the caret to the end of the
/// title, so it never points at a block that is no longer drawn.
void setCollapsibleCollapsed(
  EditorState editorState,
  Node node,
  bool collapsed,
) {
  if (node.type != CollapsibleBlockKeys.type) return;
  final current = node.attributes[CollapsibleBlockKeys.collapsed] == true;
  if (current == collapsed) return;
  final transaction = editorState.transaction
    ..updateNode(node, {
      CollapsibleBlockKeys.collapsed: collapsed ? true : null,
    });
  final selection = editorState.selection;
  if (collapsed &&
      selection != null &&
      (isInsideCollapsibleBody(node, selection.start.path) ||
          isInsideCollapsibleBody(node, selection.end.path))) {
    transaction.afterSelection = Selection.collapsed(
      Position(path: node.path, offset: node.delta?.length ?? 0),
    );
    editorState.apply(transaction, options: _viewStateOptions);
  } else {
    transaction.afterSelection = null;
    editorState.apply(
      transaction,
      options: _viewStateOptions,
      withUpdateSelection: false,
    );
  }
}

/// Folds a multi-line [selection] into ONE collapsible: the first selected
/// block becomes the title and the blocks after it (up to the last selected
/// one) move inside as its body. Returns false, touching nothing, unless the
/// selection covers two or more sibling blocks under one parent, the first
/// has text for a title, and none is already a collapsible title of its own
/// (that case is the ordinary toggle).
///
/// This is the Telegram move: select a stretch of text, fold it away. The
/// text itself is untouched (same blocks, same order, same marks), only
/// regrouped, so undo restores it exactly.
bool wrapSelectionInCollapsible(EditorState editorState, Selection selection) {
  final sel = selection.normalized;
  final startPath = sel.start.path;
  final endPath = sel.end.path;
  if (startPath.length != endPath.length || startPath.isEmpty) return false;
  if (startPath.parent.toString() != endPath.parent.toString()) return false;
  final count = endPath.last - startPath.last + 1;
  if (count < 2) return false;

  final parentPath = startPath.parent;
  final nodes = <Node>[];
  for (var i = 0; i < count; i++) {
    final node = editorState.getNodeAtPath([...parentPath, startPath.last + i]);
    if (node == null) return false;
    nodes.add(node);
  }
  final first = nodes.first;
  if (first.delta == null || first.type == CollapsibleBlockKeys.type) {
    return false;
  }
  // A table is its own structure; keep it out of a fold-by-selection.
  if (nodes.any((n) => n.type == TableBlockKeys.type)) return false;

  final title = collapsibleNode(
    delta: first.delta,
    textDirection: first.attributes[blockComponentTextDirection] as String?,
    children: [
      ...first.children.map((c) => c.copyWith()),
      ...nodes.skip(1).map((n) => n.copyWith()),
    ],
  );
  final transaction = editorState.transaction
    // The new block goes in just AFTER the lines it replaces, then the lines
    // are deleted: no step moves the path of another, so Undo (the same steps
    // run backwards) puts the lines back AND removes the new block.
    ..insertNode([...parentPath, startPath.last + count], title,
        deepCopy: false)
    ..deleteNodesAtPath(first.path, count);
  transaction.afterSelection = Selection.collapsed(
    Position(path: first.path, offset: first.delta!.length),
  );
  editorState.apply(transaction);
  return true;
}

/// Whether any collapsible with a body exists in the document, and whether any
/// of them is open / closed. Drives the "Collapse all / Expand all" tiles.
({bool open, bool closed}) collapsibleStates(EditorState editorState) {
  var open = false;
  var closed = false;
  void walk(Node node) {
    for (final child in node.children) {
      if (child.type == CollapsibleBlockKeys.type &&
          child.children.isNotEmpty) {
        if (isCollapsibleClosed(child)) {
          closed = true;
        } else {
          open = true;
        }
      }
      walk(child);
    }
  }

  walk(editorState.document.root);
  return (open: open, closed: closed);
}

/// Closes (or opens) every collapsible in the document at once, nested ones
/// included. Returns how many changed.
int setAllCollapsiblesCollapsed(EditorState editorState, bool collapsed) {
  final targets = <Node>[];
  void walk(Node node) {
    for (final child in node.children) {
      if (child.type == CollapsibleBlockKeys.type &&
          child.children.isNotEmpty &&
          (child.attributes[CollapsibleBlockKeys.collapsed] == true) !=
              collapsed) {
        targets.add(child);
      }
      walk(child);
    }
  }

  walk(editorState.document.root);
  if (targets.isEmpty) return 0;
  final transaction = editorState.transaction;
  for (final node in targets) {
    transaction.updateNode(node, {
      CollapsibleBlockKeys.collapsed: collapsed ? true : null,
    });
  }
  final selection = editorState.selection;
  if (collapsed && selection != null) {
    // Walk outward-in: the outermost closed ancestor owns the caret.
    for (final node in targets) {
      if (isInsideCollapsibleBody(node, selection.start.path) ||
          isInsideCollapsibleBody(node, selection.end.path)) {
        transaction.afterSelection = Selection.collapsed(
          Position(path: node.path, offset: node.delta?.length ?? 0),
        );
        break;
      }
    }
  }
  if (transaction.afterSelection != null) {
    editorState.apply(transaction, options: _viewStateOptions);
  } else {
    editorState.apply(
      transaction,
      options: _viewStateOptions,
      withUpdateSelection: false,
    );
  }
  return targets.length;
}

/// Text for the chevron's screen-reader label, given the state it will move to.
typedef CollapsibleToggleDescription = String Function(bool willCollapse);

/// Short text shown after a closed title, given how many blocks it hides.
typedef CollapsibleHiddenHint = String Function(int hiddenCount);

class CollapsibleBlockComponentBuilder extends BlockComponentBuilder {
  CollapsibleBlockComponentBuilder({
    super.configuration,
    this.toggleDescription,
    this.hiddenHint,
    this.chevronColor,
    this.hintColor,
    this.tint,
    this.onToggleFeedback,
  });

  final CollapsibleToggleDescription? toggleDescription;
  final CollapsibleHiddenHint? hiddenHint;
  final Color? chevronColor;
  final Color? hintColor;

  /// Played once each time the block is opened or closed by a tap (the host
  /// app's haptic tick). Null plays nothing: the engine never buzzes on its
  /// own, so the person's haptic settings stay the host's call.
  final VoidCallback? onToggleFeedback;

  /// Faint wash behind the title row, like the quote's. Null draws none.
  final Color? tint;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return CollapsibleBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      toggleDescription: toggleDescription,
      hiddenHint: hiddenHint,
      chevronColor: chevronColor,
      hintColor: hintColor,
      tint: tint,
      onToggleFeedback: onToggleFeedback,
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
  BlockComponentValidate get validate => (node) => node.delta != null;
}

class CollapsibleBlockComponentWidget extends BlockComponentStatefulWidget {
  const CollapsibleBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.toggleDescription,
    this.hiddenHint,
    this.chevronColor,
    this.hintColor,
    this.tint,
    this.onToggleFeedback,
  });

  final CollapsibleToggleDescription? toggleDescription;
  final CollapsibleHiddenHint? hiddenHint;
  final Color? chevronColor;
  final Color? hintColor;
  final Color? tint;
  final VoidCallback? onToggleFeedback;

  @override
  State<CollapsibleBlockComponentWidget> createState() =>
      _CollapsibleBlockComponentWidgetState();
}

class _CollapsibleBlockComponentWidgetState
    extends State<CollapsibleBlockComponentWidget>
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
    debugLabel: CollapsibleBlockKeys.type,
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  void initState() {
    super.initState();
    editorState.selectionNotifier.addListener(_openWhenCaretEntersBody);
  }

  @override
  void dispose() {
    editorState.selectionNotifier.removeListener(_openWhenCaretEntersBody);
    super.dispose();
  }

  /// A caret (or find hit, or an automated edit, or link jump) that lands in the hidden
  /// body would point at nothing drawn: open the block so it can be seen.
  void _openWhenCaretEntersBody() {
    if (!isCollapsibleClosed(node)) return;
    final selection = editorState.selection;
    if (selection == null) return;
    if (!isInsideCollapsibleBody(node, selection.start.path) &&
        !isInsideCollapsibleBody(node, selection.end.path)) {
      return;
    }
    // Never mutate the document from inside a selection notification.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !isCollapsibleClosed(node)) return;
      setCollapsibleCollapsed(editorState, node, false);
    });
  }

  void _toggle() {
    if (node.children.isEmpty) return;
    widget.onToggleFeedback?.call();
    setCollapsibleCollapsed(editorState, node, !isCollapsibleClosed(node));
  }

  /// Same layout as the shared nested mixin, with two differences: the body
  /// grows and shrinks (a short ease instead of a jump), and a thin guide rail
  /// runs down the body under the chevron. The rail is the second big target:
  /// a 20dp-wide strip that folds the block from anywhere along its length, so
  /// a long body never needs a scroll back up to close it.
  @override
  Widget buildComponentWithChildren(BuildContext context) {
    final closed = isCollapsibleClosed(node);
    final rtl = (Directionality.maybeOf(context) ?? TextDirection.ltr) ==
        TextDirection.rtl;
    final scale = editorState.editorStyle.textScaleFactor;
    final textColor = editorState.editorStyle.textStyleConfiguration.text.color;
    final accent = widget.chevronColor ??
        textColor?.withValues(alpha: 0.6) ??
        const Color(0x99808080);
    final railStart = (rtl ? padding.right : padding.left) + 20 * scale - 10;

    final Widget body = closed
        ? const SizedBox(width: double.infinity)
        : Stack(
            children: [
              PositionedDirectional(
                start: railStart,
                top: 2,
                bottom: 6,
                width: 20,
                // Pointer-only: the chevron already carries the screen-reader
                // action, so the rail adds no second, duplicate button.
                child: ExcludeSemantics(
                  child: _CollapsibleRail(color: accent, onToggle: _toggle),
                ),
              ),
              Padding(
                padding: indentPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: editorState.renderer.buildList(
                    context,
                    widget.node.children,
                  ),
                ),
              ),
            ],
          );

    return Stack(
      children: [
        Positioned.fill(
          left: cachedLeft,
          child: Container(decoration: decoration),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildComponent(context, withBackgroundColor: false),
            // Reduced motion: no AnimatedSize at all (a zero-length one asserts
            // when its child changes size), the body just appears or goes.
            if (MediaQuery.disableAnimationsOf(context))
              body
            else
              AnimatedSize(
                alignment: Alignment.topCenter,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: body,
              ),
          ],
        ),
      ],
    );
  }

  /// The "N lines hidden" note, drawn as a small pill that also opens the block:
  /// the second, wider target for the same action.
  Widget _hintPill(String text, TextStyle style, Color accent) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: text,
      onTap: _toggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _toggle();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: const BorderRadius.all(Radius.circular(999)),
          ),
          child: Text(
            text,
            style: style.copyWith(
              color: accent,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildComponent(
    BuildContext context, {
    bool withBackgroundColor = true,
  }) {
    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );
    final closed = isCollapsibleClosed(node);
    final scale = editorState.editorStyle.textScaleFactor;
    final textColor = editorState.editorStyle.textStyleConfiguration.text.color;
    final chevronColor = widget.chevronColor ??
        textColor?.withValues(alpha: 0.6) ??
        const Color(0x99808080);
    final hintColor = widget.hintColor ??
        textColor?.withValues(alpha: 0.5) ??
        const Color(0x80808080);
    final hint = closed ? widget.hiddenHint : null;

    final hasBody = node.children.isNotEmpty;
    final baseStyle = textStyleWithTextSpan();
    final lineHeight =
        (baseStyle.fontSize ?? 16) * (baseStyle.height ?? 1.5) * scale;
    // The toggle slot is a full 40dp touch target (the whole left gutter of the
    // row), and the title is centred against it, so the row is one calm,
    // slightly roomy header instead of a tiny glyph a thumb has to hunt for.
    final slotHeight = 40.0 * scale;
    final titleTopPad = ((slotHeight - lineHeight) / 2).clamp(0.0, 24.0);

    final chevron = _CollapsibleToggle(
      closed: closed,
      enabled: hasBody,
      rtl: textDirection == TextDirection.rtl,
      scale: scale,
      color: chevronColor,
      semanticLabel: widget.toggleDescription?.call(!closed),
      onToggle: _toggle,
    );

    Widget title = AppFlowyRichText(
      key: forwardKey,
      delegate: this,
      node: widget.node,
      editorState: editorState,
      textAlign: alignment?.toTextAlign ?? textAlign,
      placeholderText: placeholderText,
      textSpanDecorator: (textSpan) => textSpan.updateTextStyle(
        textStyleWithTextSpan(textSpan: textSpan)
            .copyWith(fontWeight: FontWeight.w600),
      ),
      placeholderTextSpanDecorator: (textSpan) => textSpan.updateTextStyle(
        placeholderTextStyleWithTextSpan(textSpan: textSpan),
      ),
      textDirection: textDirection,
      cursorColor: editorState.editorStyle.cursorColor,
      selectionColor: editorState.editorStyle.selectionColor,
      cursorWidth: editorState.editorStyle.cursorWidth,
    );

    title = Padding(
      padding: EdgeInsets.only(top: titleTopPad),
      child: title,
    );

    final hintStyle = textStyleWithTextSpan().copyWith(
      fontSize: (textStyleWithTextSpan().fontSize ?? 16) * 0.8,
      color: hintColor,
      fontWeight: FontWeight.w400,
    );
    final hintText = hint?.call(collapsibleHiddenCount(node));
    final chevronWidth = 40 * scale;

    Widget child = LayoutBuilder(
      builder: (context, constraints) {
        // The "N lines hidden" note sits beside the title only while the title
        // keeps a real line of room; at large text or on a narrow screen it
        // drops under the title instead of squeezing it to a letter per line.
        var inline = hintText != null;
        if (hintText != null && constraints.maxWidth.isFinite) {
          final painter = TextPainter(
            text: TextSpan(text: hintText, style: hintStyle),
            textDirection: textDirection,
            textScaler: TextScaler.linear(scale),
            maxLines: 1,
          )..layout();
          final room = constraints.maxWidth - chevronWidth - painter.width - 24;
          painter.dispose();
          inline = room >= (constraints.maxWidth * 0.4).clamp(0, 240);
        }
        return Container(
          width: double.infinity,
          alignment: alignment,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            textDirection: textDirection,
            children: [
              chevron,
              Flexible(
                child: hintText != null && !inline
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          title,
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _hintPill(hintText, hintStyle, chevronColor),
                          ),
                        ],
                      )
                    : title,
              ),
              if (hintText != null && inline)
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: 8,
                    top: ((slotHeight - lineHeight) / 2 - 2).clamp(0.0, 24.0),
                  ),
                  child: _hintPill(hintText, hintStyle, chevronColor),
                ),
            ],
          ),
        );
      },
    );

    // The wash sits on the TITLE row in every state, with or without a body, so
    // a block looks the same whether or not it holds anything. A colour the
    // person chose for the whole block (painted by the parent when there is a
    // body) takes its place.
    final tintDecoration = widget.tint == null
        ? null
        : BoxDecoration(
            color: widget.tint,
            borderRadius: const BorderRadius.all(Radius.circular(6)),
          );
    child = Container(
      decoration: withBackgroundColor
          ? (decoration ?? tintDecoration)
          : (decoration == null ? tintDecoration : null),
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

    return child;
  }
}

/// The chevron button: a 40dp touch slot around a 28dp round pill that tints,
/// presses in and turns with a soft spring, plus a light haptic tick.
class _CollapsibleToggle extends StatefulWidget {
  const _CollapsibleToggle({
    required this.closed,
    required this.enabled,
    required this.rtl,
    required this.scale,
    required this.color,
    required this.onToggle,
    this.semanticLabel,
  });

  final bool closed;
  final bool enabled;
  final bool rtl;
  final double scale;
  final Color color;
  final String? semanticLabel;
  final VoidCallback onToggle;

  @override
  State<_CollapsibleToggle> createState() => _CollapsibleToggleState();
}

class _CollapsibleToggleState extends State<_CollapsibleToggle> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final color = widget.color;
    final enabled = widget.enabled;
    final fill = !enabled
        ? 0.0
        : _pressed
            ? 0.26
            : widget.closed
                ? 0.16
                : 0.10;
    return Semantics(
      button: true,
      expanded: !widget.closed,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      onTap: enabled ? widget.onToggle : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: enabled
            ? () {
                widget.onToggle();
              }
            : null,
        child: SizedBox(
          width: 40 * scale,
          height: 40 * scale,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.88 : 1,
              duration: _ms(context, 90),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: _ms(context, 160),
                curve: Curves.easeOut,
                width: 28 * scale,
                height: 28 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: fill),
                ),
                child: AnimatedRotation(
                  turns: widget.closed ? 0 : (widget.rtl ? -0.25 : 0.25),
                  duration: _ms(context, 220),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    widget.rtl ? Icons.chevron_left : Icons.chevron_right,
                    size: 22 * scale,
                    color: enabled ? color : color.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The guide rail down an open body: a hairline that thickens and brightens
/// under a finger, inside a 20dp touch strip that folds the block.
class _CollapsibleRail extends StatefulWidget {
  const _CollapsibleRail({
    required this.color,
    required this.onToggle,
  });

  final Color color;
  final VoidCallback onToggle;

  @override
  State<_CollapsibleRail> createState() => _CollapsibleRailState();
}

class _CollapsibleRailState extends State<_CollapsibleRail> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: () {
        widget.onToggle();
      },
      child: Center(
        child: AnimatedContainer(
          duration: _ms(context, 120),
          curve: Curves.easeOut,
          width: _pressed ? 4 : 2,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _pressed ? 0.7 : 0.28),
            borderRadius: const BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
    );
  }
}

Duration _ms(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: ms);
