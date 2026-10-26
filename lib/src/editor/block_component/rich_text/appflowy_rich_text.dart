import 'dart:math';
import 'dart:ui';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

typedef TextSpanDecoratorForAttribute = InlineSpan Function(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
);

typedef AppFlowyTextSpanDecorator = TextSpan Function(TextSpan textSpan);
typedef AppFlowyAutoCompleteTextProvider = String? Function(
  BuildContext context,
  Node node,
  TextSpan? textSpan,
);

typedef AppFlowyTextSpanOverlayBuilder = List<Widget> Function(
  BuildContext context,
  Node node,
  SelectableMixin delegate,
);

class AppFlowyRichText extends StatefulWidget {
  const AppFlowyRichText({
    super.key,
    this.cursorHeight,
    this.cursorWidth = 2.0,
    this.lineHeight,
    this.textSpanDecorator,
    this.placeholderText = ' ',
    this.placeholderTextSpanDecorator,
    this.textDirection = TextDirection.ltr,
    this.textSpanDecoratorForCustomAttributes,
    this.textSpanOverlayBuilder,
    this.textAlign,
    this.cursorColor = const Color.fromARGB(255, 0, 0, 0),
    this.selectionColor = const Color.fromARGB(53, 111, 201, 231),
    this.autoCompleteTextProvider,
    required this.delegate,
    required this.node,
    required this.editorState,
  });

  /// The node of the rich text.
  final Node node;

  /// The editor state.
  final EditorState editorState;

  /// The height of the cursor.
  ///
  /// If this is null, the height of the cursor will be calculated automatically.
  final double? cursorHeight;

  /// The width of the cursor.
  final double cursorWidth;

  /// The height of each line.
  final double? lineHeight;

  /// customize the text span for rich text
  final AppFlowyTextSpanDecorator? textSpanDecorator;

  /// The placeholder text when the rich text is empty.
  final String placeholderText;

  /// customize the text span for placeholder text
  final AppFlowyTextSpanDecorator? placeholderTextSpanDecorator;

  final TextAlign? textAlign;

  // get the cursor rect, selection rects or block rect from the delegate
  final SelectableMixin delegate;

  // this span will be appended to the current text span, mostly, it is used for auto complete
  final AppFlowyAutoCompleteTextProvider? autoCompleteTextProvider;

  /// customize the text span for custom attributes
  ///
  /// You can use this to customize the text span for custom attributes
  ///   or override the existing one.
  final TextSpanDecoratorForAttribute? textSpanDecoratorForCustomAttributes;

  /// customize the text span overlay builder
  ///
  /// You can use this to customize the text span overlay, for example, a hover menu in linked text.
  final AppFlowyTextSpanOverlayBuilder? textSpanOverlayBuilder;

  final TextDirection textDirection;

  final Color cursorColor;
  final Color selectionColor;

  @override
  State<AppFlowyRichText> createState() => _AppFlowyRichTextState();
}

class _AppFlowyRichTextState extends State<AppFlowyRichText>
    with SelectableMixin {
  final textKey = GlobalKey();
  final placeholderTextKey = GlobalKey();

  RenderParagraph? get _renderParagraph =>
      textKey.currentContext?.findRenderObject() as RenderParagraph?;

  RenderParagraph? get _placeholderRenderParagraph =>
      placeholderTextKey.currentContext?.findRenderObject() as RenderParagraph?;

  TextSpanDecoratorForAttribute? get textSpanDecoratorForAttribute =>
      widget.textSpanDecoratorForCustomAttributes ??
      widget.editorState.editorStyle.textSpanDecorator;

  AppFlowyAutoCompleteTextProvider? get autoCompleteTextProvider =>
      widget.autoCompleteTextProvider ??
      widget.editorState.autoCompleteTextProvider;

  bool get enableAutoComplete =>
      widget.editorState.enableAutoComplete && autoCompleteTextProvider != null;

  TextStyleConfiguration get textStyleConfiguration =>
      widget.editorState.editorStyle.textStyleConfiguration;

  AppFlowyTextSpanOverlayBuilder? get textSpanOverlayBuilder =>
      widget.textSpanOverlayBuilder ??
      widget.editorState.editorStyle.textSpanOverlayBuilder;

  /// The host's link-target look (icon + color of what a note/folder link
  /// points at), when its navigator provides one.
  LinkTargetLook? _look;
  Listenable? _lookChanges;

  /// Icon size reserved before each note/folder link, by the link's start
  /// offset. Written while the text span is built, read when the chip paints.
  final Map<int, double> _iconSizeAt = {};

  @override
  void initState() {
    super.initState();
    confirmContextEnabled();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    LinkTargetLook? look;
    try {
      final nav = Provider.of<NoteLinkNavigator>(context, listen: false);
      if (nav is LinkTargetLook) look = nav as LinkTargetLook;
    } on ProviderNotFoundException {
      look = null;
    }
    if (!identical(look, _look)) {
      _lookChanges?.removeListener(_onLookChanged);
      _look = look;
      _lookChanges = look?.lookChanges;
      _lookChanges?.addListener(_onLookChanged);
    }
  }

  @override
  void dispose() {
    _lookChanges?.removeListener(_onLookChanged);
    super.dispose();
  }

  void _onLookChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _iconSizeAt.clear();
    Widget child = Stack(
      children: [
        _buildPlaceholderText(context),
        _buildNoteLinkBoxes(context),
        _buildRichText(context),
        ..._buildRichTextOverlay(context),
      ],
    );

    if (enableAutoComplete) {
      final autoCompleteText = _buildAutoCompleteRichText();
      child = Stack(
        children: [
          autoCompleteText,
          child,
        ],
      );
    }

    return BlockSelectionContainer(
      delegate: widget.delegate,
      listenable: widget.editorState.selectionNotifier,
      remoteSelection: widget.editorState.remoteSelections,
      node: widget.node,
      cursorColor: widget.cursorColor,
      selectionColor: widget.selectionColor,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: child,
      ),
    );
  }

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(
        path: widget.node.path,
        offset: widget.node.delta?.toPlainText().length ?? 0,
      );

  @override
  Rect getBlockRect({
    bool shiftWithBaseOffset = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    if (kDebugMode && _renderParagraph?.debugNeedsLayout == true) {
      return null;
    }

    final delta = widget.node.delta;
    if (position.offset < 0 ||
        (delta != null && position.offset > delta.length)) {
      return null;
    }

    final textPosition = TextPosition(offset: position.offset);
    double? placeholderCursorHeight =
        _placeholderRenderParagraph?.getFullHeightForCaret(textPosition);
    Offset? placeholderCursorOffset =
        _placeholderRenderParagraph?.getOffsetForCaret(
              textPosition,
              Rect.zero,
            ) ??
            Offset.zero;
    if (textDirection() == TextDirection.rtl) {
      if (widget.placeholderText.trim().isNotEmpty) {
        placeholderCursorOffset = placeholderCursorOffset.translate(
          _placeholderRenderParagraph?.size.width ?? 0,
          0,
        );
      }
    }

    double? cursorHeight =
        _renderParagraph?.getFullHeightForCaret(textPosition);
    Offset? cursorOffset =
        _renderParagraph?.getOffsetForCaret(textPosition, Rect.zero) ??
            Offset.zero;

    if (placeholderCursorHeight != null) {
      cursorHeight = max(cursorHeight ?? 0, placeholderCursorHeight);
    }

    if (delta?.isEmpty == true) {
      cursorOffset = placeholderCursorOffset;
    }

    if (widget.cursorHeight != null && cursorHeight != null) {
      cursorOffset = Offset(
        cursorOffset.dx,
        cursorOffset.dy + (cursorHeight - widget.cursorHeight!) / 2,
      );
      cursorHeight = widget.cursorHeight;
    }
    final rect = Rect.fromLTWH(
      max(0, cursorOffset.dx - (widget.cursorWidth / 2.0)),
      cursorOffset.dy,
      widget.cursorWidth,
      cursorHeight ?? 16.0,
    );
    return rect;
  }

  @override
  Position getPositionInOffset(Offset start) {
    final offset = _renderParagraph?.globalToLocal(start) ?? Offset.zero;
    final baseOffset =
        _renderParagraph?.getPositionForOffset(offset).offset ?? -1;
    return Position(path: widget.node.path, offset: baseOffset);
  }

  @override
  Selection? getWordEdgeInOffset(Offset offset) {
    final localOffset = _renderParagraph?.globalToLocal(offset) ?? Offset.zero;
    final textPosition = _renderParagraph?.getPositionForOffset(localOffset) ??
        const TextPosition(offset: 0);
    final textRange =
        _renderParagraph?.getWordBoundary(textPosition) ?? TextRange.empty;
    final wordEdgeOffset = textPosition.offset <= textRange.start
        ? textRange.start
        : textRange.end;

    return Selection.collapsed(
      Position(path: widget.node.path, offset: wordEdgeOffset),
    );
  }

  @override
  Selection? getWordBoundaryInOffset(Offset offset) {
    final localOffset = _renderParagraph?.globalToLocal(offset) ?? Offset.zero;
    final textPosition = _renderParagraph?.getPositionForOffset(localOffset) ??
        const TextPosition(offset: 0);
    final textRange =
        _renderParagraph?.getWordBoundary(textPosition) ?? TextRange.empty;
    final start = Position(path: widget.node.path, offset: textRange.start);
    final end = Position(path: widget.node.path, offset: textRange.end);
    return Selection(start: start, end: end);
  }

  @override
  Selection? getWordBoundaryInPosition(Position position) {
    final textPosition = TextPosition(offset: position.offset);
    final textRange =
        _renderParagraph?.getWordBoundary(textPosition) ?? TextRange.empty;
    final start = Position(path: widget.node.path, offset: textRange.start);
    final end = Position(path: widget.node.path, offset: textRange.end);
    return Selection(start: start, end: end);
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
    RenderParagraph? paragraph,
  }) {
    paragraph ??= _renderParagraph;
    if (kDebugMode && paragraph?.debugNeedsLayout == true) {
      return [];
    }
    final textSelection = textSelectionFromEditorSelection(selection);
    if (textSelection == null) {
      return [];
    }
    final rects = paragraph
        ?.getBoxesForSelection(
          textSelection,
          boxHeightStyle: BoxHeightStyle.max,
        )
        .map((box) => box.toRect())
        .toList(growable: false);
    if (rects == null || rects.isEmpty) {
      /// If the rich text widget does not contain any text,
      /// there will be no selection boxes,
      /// so we need to return to the default selection.
      Offset position = Offset.zero;
      double height = paragraph?.size.height ?? 0.0;
      double width = 0;
      if (!selection.isCollapsed) {
        /// while selecting for an empty character, return a selection area
        /// with width of 2
        final textPosition = TextPosition(offset: textSelection.baseOffset);
        position = paragraph?.getOffsetForCaret(
              textPosition,
              Rect.zero,
            ) ??
            position;
        height = paragraph?.getFullHeightForCaret(textPosition) ?? height;
        width = 2;
      }
      return [
        Rect.fromLTWH(position.dx, position.dy, width, height),
      ];
    }
    return rects;
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) {
    final delta = widget.node.delta;
    if (delta == null) {
      return Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 0,
      );
    }
    final localStart = _renderParagraph?.globalToLocal(start) ?? Offset.zero;
    final localEnd = _renderParagraph?.globalToLocal(end) ?? Offset.zero;
    final baseOffset =
        _renderParagraph?.getPositionForOffset(localStart).offset ?? -1;
    final extentOffset =
        _renderParagraph?.getPositionForOffset(localEnd).offset ?? -1;
    return Selection.single(
      path: widget.node.path,
      startOffset: baseOffset,
      endOffset: extentOffset,
    );
  }

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) {
    return _renderParagraph?.localToGlobal(offset) ?? Offset.zero;
  }

  @override
  TextDirection textDirection() {
    return widget.textDirection;
  }

  Widget _buildPlaceholderText(BuildContext context) {
    var textSpan = getPlaceholderTextSpan();
    if (widget.placeholderTextSpanDecorator != null) {
      textSpan = widget.placeholderTextSpanDecorator!(textSpan);
    }
    textSpan = adjustTextSpan(textSpan);
    final delta = widget.node.delta;
    if (delta != null && delta.isNotEmpty) {
      textSpan = textSpan.copyWith(text: '');
    }
    return RichText(
      key: placeholderTextKey,
      textHeightBehavior: TextHeightBehavior(
        applyHeightToFirstAscent:
            textStyleConfiguration.applyHeightToFirstAscent,
        applyHeightToLastDescent:
            textStyleConfiguration.applyHeightToLastDescent,
        leadingDistribution: textStyleConfiguration.leadingDistribution,
      ),
      text: textSpan,
      textDirection: textDirection(),
      textScaler: TextScaler.linear(
        widget.editorState.editorStyle.textScaleFactor,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Rounded, bordered box painted behind every note/folder link run. Only
  /// drawn when the host wired a [NoteLinkNavigator] (otherwise the decorator
  /// renders the link as plain text, so no box either).
  Widget _buildNoteLinkBoxes(BuildContext context) {
    final delta = widget.node.delta;
    if (delta == null) return const SizedBox.shrink();
    try {
      Provider.of<NoteLinkNavigator>(context, listen: false);
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final chips = <NoteLinkChip>[];
    var offset = 0;
    _LinkIdentity? lastIdentity;
    for (final insert in delta.whereType<TextInsert>()) {
      final attrs = insert.attributes;
      if (!isAnyLinkAttributes(attrs) || insert.length == 0) {
        lastIdentity = null;
        offset += insert.length;
        continue;
      }
      final target = noteFolderLinkTarget(attrs);
      final identity = _LinkIdentity(target?.kind, target?.target);
      final last = chips.isEmpty ? null : chips.last;
      if (last != null &&
          last.range.end == offset &&
          lastIdentity == identity) {
        chips[chips.length - 1] = last.extendedTo(offset + insert.length);
      } else {
        final look = target == null
            ? null
            : _look?.lookFor(context, target.kind, target.target);
        chips.add(
          NoteLinkChip(
            range: TextRange(start: offset, end: offset + insert.length),
            color: look?.color,
            paintIcon: look?.paintIcon,
          ),
        );
      }
      lastIdentity = identity;
      offset += insert.length;
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: NoteLinkBoxPainter(
            paragraph: () => _renderParagraph,
            chips: chips,
            color: Theme.of(context).colorScheme.primary,
            iconSizeAt: (start) => _iconSizeAt[start],
            rtl: textDirection() == TextDirection.rtl,
          ),
        ),
      ),
    );
  }

  Widget _buildRichText(BuildContext context) {
    return ValueListenableBuilder<Map<String, List<FindHighlightRange>>>(
      valueListenable: widget.editorState.findHighlights,
      builder: (context, highlights, _) =>
          _buildRichTextWith(highlights[widget.node.path.join('.')]),
    );
  }

  Widget _buildRichTextWith(List<FindHighlightRange>? highlights) {
    final textInserts = widget.node.delta!.whereType<TextInsert>();
    TextSpan textSpan = getTextSpan(textInserts: textInserts);
    if (widget.textSpanDecorator != null) {
      textSpan = widget.textSpanDecorator!(textSpan);
    }
    textSpan = adjustTextSpan(textSpan);
    if (highlights != null && highlights.isNotEmpty) {
      textSpan = _applyFindHighlights(textSpan, highlights);
    }
    return RichText(
      key: textKey,
      textAlign: widget.textAlign ?? TextAlign.start,
      textHeightBehavior: TextHeightBehavior(
        applyHeightToFirstAscent:
            textStyleConfiguration.applyHeightToFirstAscent,
        applyHeightToLastDescent:
            textStyleConfiguration.applyHeightToLastDescent,
        leadingDistribution: textStyleConfiguration.leadingDistribution,
      ),
      text: textSpan,
      textDirection: textDirection(),
      textScaler:
          TextScaler.linear(widget.editorState.editorStyle.textScaleFactor),
    );
  }

  List<Widget> _buildRichTextOverlay(BuildContext context) {
    if (textKey.currentContext == null) return [];
    return textSpanOverlayBuilder?.call(
          context,
          widget.node,
          this,
        ) ??
        [];
  }

  void confirmContextEnabled() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && textKey.currentContext == null) {
        confirmContextEnabled();
      } else if (mounted && textKey.currentContext != null) {
        setState(() {});
      }
    });
  }

  Widget _buildAutoCompleteRichText() {
    final textInserts = widget.node.delta!.whereType<TextInsert>();
    TextSpan textSpan = getTextSpan(textInserts: textInserts);
    if (widget.textSpanDecorator != null) {
      textSpan = widget.textSpanDecorator!(textSpan);
    }
    textSpan = adjustTextSpan(textSpan);
    return ValueListenableBuilder(
      valueListenable: widget.editorState.selectionNotifier,
      builder: (_, __, ___) {
        final autoCompleteText = autoCompleteTextProvider?.call(
          context,
          widget.node,
          textSpan,
        );
        if (autoCompleteText == null || autoCompleteText.isEmpty) {
          return const SizedBox.shrink();
        }
        textSpan = getTextSpan(
          textInserts: [
            ...textInserts.map(
              (e) => TextInsert(
                e.text,
                attributes: {
                  AppFlowyRichTextKeys.transparent: true,
                },
              ),
            ),
            TextInsert(
              autoCompleteText,
              attributes: {
                AppFlowyRichTextKeys.autoComplete: true,
              },
            ),
          ],
        );
        return RichText(
          textAlign: widget.textAlign ?? TextAlign.start,
          textHeightBehavior: TextHeightBehavior(
            applyHeightToFirstAscent:
                textStyleConfiguration.applyHeightToFirstAscent,
            applyHeightToLastDescent:
                textStyleConfiguration.applyHeightToLastDescent,
            leadingDistribution: textStyleConfiguration.leadingDistribution,
          ),
          text: textSpan,
          textDirection: textDirection(),
          textScaler:
              TextScaler.linear(widget.editorState.editorStyle.textScaleFactor),
        );
      },
    );
  }

  // https://github.com/flutter/flutter/pull/143954
  // https://github.com/AppFlowy-IO/appflowy-editor/issues/819#issuecomment-2177833413
  // This is a workaround for the issue that
  //  the caret height of the text is not calculated correctly if the parent style is null.
  TextSpan adjustTextSpan(TextSpan textSpan) {
    if (textSpan.style == null && textSpan.children != null) {
      double height = 0.0;
      double fontSize = 0.0;
      textSpan.visitChildren((span) {
        final style = span.style;
        if (style != null) {
          if (style.height != null) {
            height = max(height, style.height!);
          }
          if (style.fontSize != null) {
            fontSize = max(fontSize, style.fontSize!);
          }
        }
        return true;
      });
      if (height == 0.0 || fontSize == 0.0) {
        return textSpan;
      }
      textSpan = textSpan.copyWith(
        style: textStyleConfiguration.text.copyWith(
          height: height,
          fontSize: fontSize,
        ),
      );
    }
    return textSpan;
  }

  TextSpan getPlaceholderTextSpan() {
    return TextSpan(
      text: widget.placeholderText,
      style: textStyleConfiguration.text.copyWith(
        height: textStyleConfiguration.lineHeight,
      ),
    );
  }

  static const _findColor = Color(0x66FFD54F);
  static const _findCurrentColor = Color(0xCCFF9800);

  TextSpan _applyFindHighlights(
    TextSpan root,
    List<FindHighlightRange> ranges,
  ) {
    final children = root.children;
    if (children == null) return root;
    var offset = 0;
    final out = <InlineSpan>[];
    for (final child in children) {
      final text = child is TextSpan ? child.text : null;
      if (child is! TextSpan || text == null) {
        out.add(child);
        offset += 1;
        continue;
      }
      final end = offset + text.length;
      var cursor = 0;
      for (final r in ranges) {
        final a = r.start.clamp(offset, end) - offset;
        final b = r.end.clamp(offset, end) - offset;
        if (b <= a || a < cursor) continue;
        if (a > cursor) {
          out.add(
            TextSpan(text: text.substring(cursor, a), style: child.style),
          );
        }
        out.add(
          TextSpan(
            text: text.substring(a, b),
            style: (child.style ?? const TextStyle()).copyWith(
              backgroundColor: r.current ? _findCurrentColor : _findColor,
            ),
          ),
        );
        cursor = b;
      }
      if (cursor == 0) {
        out.add(child);
      } else if (cursor < text.length) {
        out.add(TextSpan(text: text.substring(cursor), style: child.style));
      }
      offset = end;
    }
    return TextSpan(style: root.style, children: out);
  }

  TextSpan getTextSpan({
    required Iterable<TextInsert> textInserts,
  }) {
    int offset = 0;
    List<InlineSpan> textSpans = [];
    final starts = <int>[];
    for (final textInsert in textInserts) {
      TextStyle textStyle = textStyleConfiguration.text.copyWith(
        height: textStyleConfiguration.lineHeight,
      );
      final attributes = textInsert.attributes;
      if (attributes != null) {
        if (attributes.bold == true) {
          textStyle = textStyle.combine(textStyleConfiguration.bold);
        }
        if (attributes.italic == true) {
          textStyle = textStyle.combine(textStyleConfiguration.italic);
        }
        if (attributes.underline == true) {
          textStyle = textStyle.combine(textStyleConfiguration.underline);
        }
        if (attributes.strikethrough == true) {
          textStyle = textStyle.combine(textStyleConfiguration.strikethrough);
        }
        if (attributes.href != null ||
            attributes[AppFlowyRichTextKeys.noteLink] != null ||
            attributes[AppFlowyRichTextKeys.folderLink] != null ||
            attributes[AppFlowyRichTextKeys.appLink] != null) {
          // PREVON PATCH: note/folder links share the href look (blue +
          // underline) so they read as links.
          textStyle = textStyle.combine(textStyleConfiguration.href);
        }
        if (attributes.code == true) {
          textStyle = textStyle.combine(textStyleConfiguration.code);
        }
        if (attributes.backgroundColor != null) {
          textStyle = textStyle.combine(
            TextStyle(backgroundColor: attributes.backgroundColor),
          );
        }
        if (attributes.findBackgroundColor != null) {
          textStyle = textStyle.combine(
            TextStyle(backgroundColor: attributes.findBackgroundColor),
          );
        }
        if (attributes.color != null) {
          textStyle = textStyle.combine(
            TextStyle(color: attributes.color),
          );
        }
        if (attributes.fontFamily != null) {
          textStyle = textStyle.combine(
            TextStyle(fontFamily: attributes.fontFamily),
          );
        }
        if (attributes.fontSize != null) {
          textStyle = textStyle.combine(
            TextStyle(fontSize: attributes.fontSize),
          );
        }
        if (attributes.autoComplete == true) {
          textStyle = textStyle.combine(textStyleConfiguration.autoComplete);
        }
        if (attributes.transparent == true) {
          textStyle = textStyle.combine(
            const TextStyle(color: Colors.transparent),
          );
        }
      }
      final textSpan = TextSpan(
        text: textInsert.text,
        style: textStyle,
      );
      textSpans.add(
        textSpanDecoratorForAttribute != null
            ? textSpanDecoratorForAttribute!(
                context,
                widget.node,
                offset,
                textInsert,
                textSpan,
                widget.textSpanDecorator?.call(textSpan) ?? textSpan,
              )
            : textSpan,
      );
      starts.add(offset);
      offset += textInsert.length;
    }
    return TextSpan(
      children: _applyLinkLook(textInserts.toList(), textSpans, starts),
    );
  }

  /// Gives every note/folder link its target's color and reserves room for
  /// its icon, WITHOUT changing a single text offset (selection, copy/paste
  /// and the markdown round-trip all index the delta):
  ///
  ///  * the link text is tinted with the target's color;
  ///  * the icon's room is letter-spacing on the character just BEFORE the
  ///    link (a split span, same characters), so the chip can paint the icon
  ///    in that gap. A link at the very start of the block has no character
  ///    before it: its chip reaches into the block's left padding instead.
  ///
  /// A link directly after another link gets no icon (its neighbour's chip
  /// owns that gap).
  List<InlineSpan> _applyLinkLook(
    List<TextInsert> inserts,
    List<InlineSpan> spans,
    List<int> starts,
  ) {
    final look = _look;
    if (look == null) return spans;
    // One list per insert: a split character stays a flat sibling span (the
    // find-highlight pass walks the root's children as a flat run).
    final out = [
      for (final s in spans) <InlineSpan>[s]
    ];
    final scale = widget.editorState.editorStyle.textScaleFactor;
    for (var i = 0; i < inserts.length; i++) {
      final target = noteFolderLinkTarget(inserts[i].attributes);
      if (target == null) continue;
      final linkLook = look.lookFor(context, target.kind, target.target);
      final own = out[i].single;
      if (linkLook == null || own is! TextSpan) continue;
      var span = own;
      final tint = linkLook.color;
      if (tint != null) {
        final base = span.style?.color ?? textStyleConfiguration.text.color;
        span = span.copyWith(
          style: (span.style ?? const TextStyle()).copyWith(
            color: base == null ? tint : Color.lerp(tint, base, 0.3),
          ),
        );
        out[i] = [span];
      }
      final iconSize =
          (span.style?.fontSize ?? textStyleConfiguration.text.fontSize ?? 16) *
              scale *
              kLinkIconScale;
      if (i == 0) {
        _iconSizeAt[starts[i]] = iconSize;
        continue;
      }
      if (isAnyLinkAttributes(inserts[i - 1].attributes)) continue;
      if (out[i - 1].length != 1) continue;
      final prev = out[i - 1].single;
      if (prev is! TextSpan || prev.children != null) continue;
      final text = prev.text;
      if (text == null || text.isEmpty) continue;
      final lastLength = text.characters.last.length;
      final head = text.substring(0, text.length - lastLength);
      final tail = text.substring(text.length - lastLength);
      final gapStyle = (prev.style ?? const TextStyle())
          .copyWith(letterSpacing: iconSize + kLinkIconGapExtra);
      out[i - 1] = head.isEmpty
          ? [prev.copyWith(style: gapStyle)]
          : [
              prev.copyWith(text: head),
              prev.copyWith(text: tail, style: gapStyle),
            ];
      _iconSizeAt[starts[i]] = iconSize;
    }
    return [for (final pieces in out) ...pieces];
  }

  TextSelection? textSelectionFromEditorSelection(Selection? selection) {
    if (selection == null) {
      return null;
    }

    final normalized = selection.normalized;
    final path = widget.node.path;
    if (path < normalized.start.path || path > normalized.end.path) {
      return null;
    }

    final length = widget.node.delta?.length;
    if (length == null) {
      return null;
    }

    TextSelection? textSelection;

    if (normalized.isSingle) {
      if (path.equals(normalized.start.path)) {
        if (normalized.isCollapsed) {
          textSelection = TextSelection.collapsed(
            offset: normalized.startIndex,
          );
        } else {
          textSelection = TextSelection(
            baseOffset: normalized.startIndex,
            extentOffset: normalized.endIndex,
          );
        }
      }
    } else {
      if (path.equals(normalized.start.path)) {
        textSelection = TextSelection(
          baseOffset: normalized.startIndex,
          extentOffset: length,
        );
      } else if (path.equals(normalized.end.path)) {
        textSelection = TextSelection(
          baseOffset: 0,
          extentOffset: normalized.endIndex,
        );
      } else {
        textSelection = TextSelection(
          baseOffset: 0,
          extentOffset: length,
        );
      }
    }
    return textSelection;
  }
}

/// Paints the "chip" box (soft fill, hairline border, rounded corners, a
/// subtle lift) behind note/folder link runs using the sibling paragraph's
/// laid-out geometry. Wrapped links get one box per line.
class NoteLinkBoxPainter extends CustomPainter {
  NoteLinkBoxPainter({
    required this.paragraph,
    required this.chips,
    required this.color,
    this.iconSizeAt,
    this.rtl = false,
  });

  final RenderParagraph? Function() paragraph;
  final List<NoteLinkChip> chips;

  /// The theme link color, used by a chip that carries no color of its own.
  final Color color;

  /// The icon size reserved before the link that starts at an offset, or null
  /// when no room was reserved there (then no icon is painted).
  final double? Function(int start)? iconSizeAt;
  final bool rtl;

  static const double _radius = 7;
  static const double _padX = 3;
  static const double _padY = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final p = paragraph();
    // debugNeedsLayout throws LateInitializationError outside debug mode.
    if (p == null || !p.hasSize || (kDebugMode && p.debugNeedsLayout)) return;
    for (final chip in chips) {
      final tint = chip.color ?? color;
      final fill = Paint()..color = tint.withValues(alpha: 0.10);
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = tint.withValues(alpha: 0.42);
      final shadow = Paint()
        ..color = tint.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      final iconSize =
          chip.paintIcon == null ? null : iconSizeAt?.call(chip.range.start);
      final boxes = p.getBoxesForSelection(
        TextSelection(
          baseOffset: chip.range.start,
          extentOffset: chip.range.end,
        ),
        boxHeightStyle: BoxHeightStyle.tight,
      );
      var first = true;
      for (final box in boxes) {
        final rect = box.toRect();
        if (rect.width <= 0) continue;
        var left = rect.left - _padX;
        var right = rect.right + _padX;
        Rect? iconRect;
        if (first && iconSize != null) {
          // The icon sits in the gap reserved before the link, at the chip's
          // starting edge (its right edge in a right-to-left paragraph).
          final room = iconSize + kLinkIconChipExtra;
          final cy = rect.center.dy;
          if (rtl) {
            iconRect = Rect.fromLTWH(
              rect.right + _padX + 3,
              cy - iconSize / 2,
              iconSize,
              iconSize,
            );
            right = rect.right + _padX + room;
          } else {
            iconRect = Rect.fromLTWH(
              rect.left - _padX - room + 3,
              cy - iconSize / 2,
              iconSize,
              iconSize,
            );
            left = rect.left - _padX - room;
          }
        }
        first = false;
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTRB(left, rect.top - _padY, right, rect.bottom + _padY),
          const Radius.circular(_radius),
        );
        canvas.drawRRect(rrect.shift(const Offset(0, 1)), shadow);
        canvas.drawRRect(rrect, fill);
        canvas.drawRRect(rrect.deflate(0.5), border);
        if (iconRect != null) chip.paintIcon!(canvas, iconRect);
      }
    }
  }

  @override
  bool shouldRepaint(NoteLinkBoxPainter old) => true;
}

/// One link chip: a run of consecutive link inserts that share a target, plus
/// the look the host gave that target (null for web/app links).
class NoteLinkChip {
  const NoteLinkChip({required this.range, this.color, this.paintIcon});
  final TextRange range;
  final Color? color;
  final LinkIconPainter? paintIcon;

  NoteLinkChip extendedTo(int end) => NoteLinkChip(
        range: TextRange(start: range.start, end: end),
        color: color,
        paintIcon: paintIcon,
      );
}

/// Icon size as a fraction of the link's font size.
const double kLinkIconScale = 0.95;

/// Chip width taken by the icon beyond its size (3 px in front, 1 px behind).
const double kLinkIconChipExtra = 4;

/// Letter-spacing added after the character before a link, on top of the icon
/// size: the chip's icon room, its side padding and 1 px clear of the glyph.
const double kLinkIconGapExtra = 8;

class _LinkIdentity {
  const _LinkIdentity(this.kind, this.target);
  final LinkEditKind? kind;
  final String? target;
  @override
  bool operator ==(Object other) =>
      other is _LinkIdentity && other.kind == kind && other.target == target;
  @override
  int get hashCode => Object.hash(kind, target);
}

/// True for a run that is drawn as a chip (note, folder or app link; a web
/// link keeps its plain underline).
bool isAnyLinkAttributes(Attributes? attrs) =>
    attrs != null &&
    (attrs[AppFlowyRichTextKeys.noteLink] != null ||
        attrs[AppFlowyRichTextKeys.folderLink] != null ||
        attrs[AppFlowyRichTextKeys.appLink] != null);

/// The note or folder a link run points at, or null for any other run.
({LinkEditKind kind, String target})? noteFolderLinkTarget(Attributes? attrs) {
  if (attrs == null) return null;
  final note = attrs[AppFlowyRichTextKeys.noteLink];
  if (note is String && note.isNotEmpty) {
    return (kind: LinkEditKind.note, target: note);
  }
  final folder = attrs[AppFlowyRichTextKeys.folderLink];
  if (folder is String && folder.isNotEmpty) {
    return (kind: LinkEditKind.folder, target: folder);
  }
  return null;
}

extension AppFlowyRichTextAttributes on Attributes {
  bool get bold => this[AppFlowyRichTextKeys.bold] == true;

  bool get italic => this[AppFlowyRichTextKeys.italic] == true;

  bool get underline => this[AppFlowyRichTextKeys.underline] == true;

  bool get code => this[AppFlowyRichTextKeys.code] == true;

  bool get strikethrough {
    return (containsKey(AppFlowyRichTextKeys.strikethrough) &&
        this[AppFlowyRichTextKeys.strikethrough] == true);
  }

  Color? get color {
    final textColor = this[AppFlowyRichTextKeys.textColor] as String?;
    return textColor?.tryToColor();
  }

  Color? get backgroundColor {
    final highlightColor =
        this[AppFlowyRichTextKeys.backgroundColor] as String?;
    return highlightColor?.tryToColor();
  }

  Color? get findBackgroundColor {
    final findBackgroundColor =
        this[AppFlowyRichTextKeys.findBackgroundColor] as String?;
    return findBackgroundColor?.tryToColor();
  }

  String? get href {
    if (this[AppFlowyRichTextKeys.href] is String) {
      return this[AppFlowyRichTextKeys.href];
    }
    return null;
  }

  String? get fontFamily {
    if (this[AppFlowyRichTextKeys.fontFamily] is String) {
      return this[AppFlowyRichTextKeys.fontFamily];
    }
    return null;
  }

  double? get fontSize {
    if (this[AppFlowyRichTextKeys.fontSize] is double) {
      return this[AppFlowyRichTextKeys.fontSize];
    }
    return null;
  }

  bool get autoComplete => this[AppFlowyRichTextKeys.autoComplete] == true;

  bool get transparent => this[AppFlowyRichTextKeys.transparent] == true;
}
