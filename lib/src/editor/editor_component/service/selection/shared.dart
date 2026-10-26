import 'dart:math' as math;

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../block_component/image_block_component/image_source.dart';

/// A `href` / `noteLink` / `folderLink` run under a pointer.
class _LinkHit {
  const _LinkHit({
    required this.node,
    required this.context,
    required this.start,
    required this.end,
    this.href,
    this.noteId,
    this.folderId,
    this.appTarget,
    this.attributes = const {},
  });
  final Node node;
  final BuildContext context;
  final int start;
  final int end;
  final String? href;
  final String? noteId;
  final String? folderId;
  final String? appTarget;

  /// All inline attributes of the run (bold etc. survive a rename).
  final Map<String, dynamic> attributes;
}

/// Finds the link run painted under global [offset] (already resolved to
/// [position]), or null.
///
/// Hit-testing uses the run's painted rects, not the caret offset: a caret
/// offset rounds to the nearest gap, so the outer half of the first/last
/// character would otherwise resolve to the wrong side of the link.
_LinkHit? _linkHitAt(
  EditorState editorState,
  Position position,
  Offset offset,
) {
  final node = editorState.getNodeAtPath(position.path);
  final delta = node?.delta;
  final selectable = node?.selectable;
  final box = node?.renderBox;
  if (node == null || delta == null || selectable == null || box == null) {
    return null;
  }
  final ctx = node.context;
  if (ctx == null || !ctx.mounted) return null;
  var start = 0;
  for (final op in delta) {
    final end = start + op.length;
    final attrs = op is TextInsert ? op.attributes : null;
    final noteId = attrs?[AppFlowyRichTextKeys.noteLink] as String?;
    final folderId = attrs?[AppFlowyRichTextKeys.folderLink] as String?;
    final href = attrs?[AppFlowyRichTextKeys.href] as String?;
    final appTarget = attrs?[AppFlowyRichTextKeys.appLink] as String?;
    if ((noteId != null ||
        folderId != null ||
        href != null ||
        appTarget != null)) {
      final rects = selectable.getRectsInSelection(
        Selection.single(
          path: position.path,
          startOffset: start,
          endOffset: end,
        ),
      );
      final local = box.globalToLocal(offset);
      // The painted chip is the glyph rect plus 3px x / 1.5px y padding;
      // cover all of it plus a little slack so the whole chip is tappable.
      if (rects.any(
        (r) => Rect.fromLTRB(r.left - 6, r.top - 4, r.right + 6, r.bottom + 4)
            .contains(local),
      )) {
        return _LinkHit(
          node: node,
          context: ctx,
          start: start,
          end: end,
          href: href,
          noteId: noteId,
          folderId: folderId,
          appTarget: appTarget,
          attributes: {...?attrs},
        );
      }
    }
    start = end;
  }
  return null;
}

/// PREVON PATCH: the selection gesture layer consumes taps before a text
/// span's own TapGestureRecognizer can fire, so links would never open. Call
/// this on a tap at global [offset] (already resolved to [position]); returns
/// true when the tap landed ON a link run and it was opened: a web link via
/// [editorLaunchUrl], a note/folder link via the host-provided
/// [NoteLinkNavigator].
bool openNoteLinkAtPosition(
  EditorState editorState,
  Position position,
  Offset offset,
) {
  final hit = _linkHitAt(editorState, position, offset);
  if (hit == null) return false;
  return _openLinkHit(hit);
}

bool _openLinkHit(_LinkHit hit) {
  if (hit.href != null) {
    editorLaunchUrl(hit.href, hit.context);
    return true;
  }
  NoteLinkNavigator? navigator;
  try {
    navigator = hit.context.read<NoteLinkNavigator>();
  } on ProviderNotFoundException {
    return false;
  }
  if (hit.noteId != null) {
    navigator.openNote(hit.context, hit.noteId!);
  } else if (hit.folderId != null) {
    navigator.openFolder(hit.context, hit.folderId!);
  } else if (hit.appTarget != null) {
    // A navigator that cannot open app links leaves the tap unhandled.
    if (navigator is! AppLinkNavigator) return false;
    (navigator as AppLinkNavigator).openApp(hit.context, hit.appTarget!);
  }
  return true;
}

/// PREVON PATCH: long-press (touch) / right-click (desktop) on a link run
/// shows a small menu: rename / edit it (when the host supplies a
/// [LinkEditor]) or turn it back into plain text. Returns true when [offset]
/// landed on a link and the menu was shown, so the caller skips its normal
/// selection handling.
bool showLinkRemoveMenuAtPosition(
  EditorState editorState,
  Position position,
  Offset offset,
) {
  final hit = _linkHitAt(editorState, position, offset);
  if (hit == null) return false;
  final ctx = hit.context;
  final overlay = Overlay.maybeOf(ctx)?.context.findRenderObject();
  if (overlay is! RenderBox) return false;
  final local = overlay.globalToLocal(offset);
  LinkEditor? editor;
  try {
    final navigator = ctx.read<NoteLinkNavigator>();
    if (navigator is LinkEditor) editor = navigator as LinkEditor;
  } on ProviderNotFoundException {
    editor = null;
  }
  if (editor != null) {
    final host = editor;
    host.showLinkMenu(ctx, _requestFor(hit)).then((choice) {
      switch (choice) {
        case LinkMenuChoice.open:
          _openLinkHit(hit);
        case LinkMenuChoice.edit:
          _editLinkRun(editorState, hit, host);
        case LinkMenuChoice.remove:
          _removeLinkRun(editorState, hit);
        case null:
          break;
      }
    });
    return true;
  }
  // No host menu: plain "Remove link" fallback.
  showMenu<bool>(
    context: ctx,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(local.dx, local.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem<bool>(
        value: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off_rounded, size: 18),
            const SizedBox(width: 8),
            Text(AppFlowyEditorL10n.current.removeLink),
          ],
        ),
      ),
    ],
  ).then((remove) {
    if (remove == true) _removeLinkRun(editorState, hit);
  });
  return true;
}

void _removeLinkRun(EditorState editorState, _LinkHit hit) {
  final transaction = editorState.transaction
    ..formatText(hit.node, hit.start, hit.end - hit.start, {
      AppFlowyRichTextKeys.href: null,
      AppFlowyRichTextKeys.noteLink: null,
      AppFlowyRichTextKeys.folderLink: null,
      AppFlowyRichTextKeys.appLink: null,
    });
  editorState.apply(transaction);
}

LinkEditRequest _requestFor(_LinkHit hit) {
  final delta = hit.node.delta;
  final text =
      delta == null ? '' : delta.slice(hit.start, hit.end).toPlainText();
  final kind = hit.href != null
      ? LinkEditKind.web
      : hit.noteId != null
          ? LinkEditKind.note
          : hit.folderId != null
              ? LinkEditKind.folder
              : LinkEditKind.app;
  return LinkEditRequest(
    kind: kind,
    text: text,
    url: hit.href,
    target: hit.href ?? hit.noteId ?? hit.folderId ?? hit.appTarget,
  );
}

Future<void> _editLinkRun(
  EditorState editorState,
  _LinkHit hit,
  LinkEditor editor,
) async {
  final request = _requestFor(hit);
  final text = request.text;
  final kind = request.kind;
  final result = await editor.editLink(
    hit.context,
    request,
  );
  if (result == null) return;
  final newText = result.text;
  final newUrl = kind == LinkEditKind.web ? result.url : null;
  if (newText.isEmpty) return;
  final textChanged = newText != text;
  final urlChanged = newUrl != null && newUrl.isNotEmpty && newUrl != hit.href;
  if (!textChanged && !urlChanged) return;
  // The editor may have changed while the dialog was open; re-check the run
  // still reads the same before touching it.
  final current = hit.node.delta;
  if (current == null ||
      hit.end > current.length ||
      current.slice(hit.start, hit.end).toPlainText() != text) {
    return;
  }
  final attrs = <String, dynamic>{...hit.attributes};
  if (urlChanged) attrs[AppFlowyRichTextKeys.href] = newUrl;
  final transaction = editorState.transaction;
  if (textChanged) {
    transaction.replaceText(
      hit.node,
      hit.start,
      hit.end - hit.start,
      newText,
      attributes: attrs,
    );
  } else {
    transaction.formatText(hit.node, hit.start, hit.end - hit.start, attrs);
  }
  editorState.apply(transaction);
}

/// An image block whose painted picture is under a pointer.
class _ImageHit {
  const _ImageHit(
      {required this.node, required this.state, required this.context});
  final Node node;
  final ImageBlockComponentWidgetState state;
  final BuildContext context;
}

/// Width (dp) of the band along each side of a resizable image that belongs to
/// its resize grips. A desktop click is resolved on pointer-DOWN, so a press
/// that starts a grip drag must not also count as a tap on the image.
const double _kImageGripBand = 44;

/// The image block under global [offset] (already resolved to [position]), or
/// null. Only the painted picture counts, not the empty strip beside a narrow
/// or aligned image, and not the page margin.
_ImageHit? _imageHitAt(
  EditorState editorState,
  Position position,
  Offset offset, {
  bool avoidGrips = false,
}) {
  final node = editorState.getNodeAtPath(position.path);
  if (node == null || node.type != ImageBlockKeys.type) return null;
  final state = node.selectable;
  final ctx = node.context;
  if (state is! ImageBlockComponentWidgetState || ctx == null || !ctx.mounted) {
    return null;
  }
  final rect = state.imageGlobalRect;
  if (rect == null) return null;
  var hitRect = rect;
  if (avoidGrips && editorState.editable) {
    final inset = math.min(_kImageGripBand, rect.width / 3);
    hitRect = Rect.fromLTRB(
      rect.left + inset,
      rect.top,
      rect.right - inset,
      rect.bottom,
    );
  }
  if (!hitRect.contains(offset)) return null;
  return _ImageHit(node: node, state: state, context: ctx);
}

ImageActions? _readImageActions(BuildContext context) {
  try {
    return context.read<ImageActions>();
  } on ProviderNotFoundException {
    return null;
  }
}

/// Every viewable image of the note in reading order, with [hit]'s own first
/// choice resolved through its widget (so a remote image the user just allowed
/// once is included) and the rest resolved from their `url` alone.
ImageViewRequest? _viewRequestFor(EditorState editorState, _ImageHit hit) {
  final tapped = hit.state.viewerProvider;
  if (tapped == null) return null;
  AttachmentImageLoader? loader;
  var allowRemote = false;
  try {
    loader = hit.context.read<AttachmentImageLoader>();
  } on ProviderNotFoundException {
    loader = null;
  }
  try {
    allowRemote = hit.context.read<RemoteImagePolicy>().allowed;
  } on ProviderNotFoundException {
    allowRemote = false;
  }
  final items = <ImageViewItem>[];
  var initial = 0;
  void walk(Node parent) {
    for (final child in parent.children) {
      if (child.type == ImageBlockKeys.type) {
        final src = child.attributes[ImageBlockKeys.url];
        if (identical(child, hit.node)) {
          initial = items.length;
          items.add(ImageViewItem(image: tapped, id: child.id));
        } else if (src is String) {
          final provider = resolveImageProvider(
            src,
            loader: loader,
            allowRemote: allowRemote,
          );
          if (provider != null) {
            items.add(ImageViewItem(image: provider, id: child.id));
          }
        }
      }
      walk(child);
    }
  }

  walk(editorState.document.root);
  if (items.isEmpty) return null;
  return ImageViewRequest(items: items, initialIndex: initial);
}

bool _openImageHit(EditorState editorState, _ImageHit hit) {
  final actions = _readImageActions(hit.context);
  if (actions == null) return false;
  final request = _viewRequestFor(editorState, hit);
  if (request == null) return false;
  actions.openImage(hit.context, request);
  return true;
}

/// PREVON PATCH 19: a tap on an image opens it full screen, the way a tap on a
/// link to a page opens that page. Call it on a tap at global [offset]
/// (already resolved to [position]); returns true when the tap landed on the
/// picture and the host opened it. With no host [ImageActions], a blocked
/// remote image or a tap beside the picture it returns false and the tap
/// keeps its old meaning (select).
///
/// [avoidGrips] keeps the resize grips' bands out of the target; pass it for
/// a pointer-down tap (desktop), where a grip press would otherwise count.
bool openImageAtPosition(
  EditorState editorState,
  Position position,
  Offset offset, {
  bool avoidGrips = false,
}) {
  final hit =
      _imageHitAt(editorState, position, offset, avoidGrips: avoidGrips);
  if (hit == null) return false;
  return _openImageHit(editorState, hit);
}

/// PREVON PATCH 19: right-click (desktop) on an image shows the host's menu:
/// open full screen, size, alignment, move, remove. The block is selected
/// first so its resize grips show behind the menu. Returns true when the menu
/// was shown, so the caller skips its normal selection handling.
///
/// On a phone a hold goes through [ImageHoldLift] instead (lift to move, or
/// let go in place for this same menu); this is its read-only fallback.
bool showImageMenuAtPosition(
  EditorState editorState,
  Position position,
  Offset offset,
) {
  final hit = _imageHitAt(editorState, position, offset);
  if (hit == null) return false;
  return _presentImageMenu(editorState, hit);
}

bool _presentImageMenu(EditorState editorState, _ImageHit hit) {
  final actions = _readImageActions(hit.context);
  if (actions == null) return false;
  editorState.updateSelectionWithReason(
    Selection(start: hit.state.start(), end: hit.state.end()),
    reason: SelectionUpdateReason.uiEvent,
    extraInfo: {selectionExtraInfoDisableToolbar: true},
  );
  HapticFeedback.mediumImpact();
  actions.showImageMenu(hit.context, hit.state.menuRequest()).then((choice) {
    if (choice == null) return;
    // The note may have changed while the menu was open.
    if (!hit.context.mounted ||
        editorState.getNodeAtPath(hit.node.path) != hit.node) {
      return;
    }
    _applyImageChoice(editorState, hit, choice);
  });
  return true;
}

/// PREVON PATCH 19: hold an image on a phone to pick it up. Keep the finger
/// down and drag to move it among its siblings (the same drop line, edge
/// auto-scroll and tick as the margin hold); let go without moving and the
/// image menu opens instead, so one hold covers "move" and "everything else".
class ImageHoldLift {
  ImageHoldLift._(this._editorState, this._hit, this._session, this._start,
      this._entry, this._dy);

  /// How far (dp) the finger may wander before a hold counts as a drag.
  static const double _moveSlop = 14;

  final EditorState _editorState;
  final _ImageHit _hit;
  final BlockReorderSession _session;
  final Offset _start;
  final OverlayEntry _entry;
  final ValueNotifier<double> _dy;
  double _farthest = 0;
  bool _done = false;

  /// Starts a lift when [offset] is on an editable image and the host can show
  /// its menu; null otherwise (the caller falls back to its normal hold).
  static ImageHoldLift? begin(
    EditorState editorState,
    Position position,
    Offset offset,
  ) {
    if (!editorState.editable) return null;
    // The grip bands are skipped: a hold there is a resize that waited, and
    // falls back to the menu instead of lifting the picture.
    final hit = _imageHitAt(editorState, position, offset, avoidGrips: true);
    if (hit == null || _readImageActions(hit.context) == null) return null;
    final rowBox = hit.node.key.currentContext?.findRenderObject();
    final overlay = Overlay.maybeOf(hit.context, rootOverlay: true);
    if (rowBox is! RenderBox || !rowBox.attached || !rowBox.hasSize) {
      return null;
    }
    if (overlay == null) return null;

    editorState.updateSelectionWithReason(
      Selection(start: hit.state.start(), end: hit.state.end()),
      reason: SelectionUpdateReason.uiEvent,
      extraInfo: {selectionExtraInfoDisableToolbar: true},
    );
    HapticFeedback.mediumImpact();
    final session = BlockReorderSession(editorState, hit.node)..start();
    // The row, lifted off the page and pinned over where it was.
    final top = rowBox.localToGlobal(Offset.zero);
    final dy = ValueNotifier<double>(0);
    final entry = OverlayEntry(
      builder: (_) => ValueListenableBuilder<double>(
        valueListenable: dy,
        builder: (_, dy, __) => Positioned(
          left: top.dx,
          top: top.dy + dy,
          child: IgnorePointer(
            child: ReorderDragFeedback(
              node: hit.node,
              editorState: editorState,
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    return ImageHoldLift._(editorState, hit, session, offset, entry, dy);
  }

  void update(Offset global) {
    if (_done) return;
    _farthest = math.max(_farthest, (global - _start).distance);
    if (_farthest < _moveSlop) return;
    _dy.value = global.dy - _start.dy;
    _session.update(global);
  }

  /// The finger lifted: drop the image where it is, or, if it never moved, open
  /// the menu.
  void end() {
    if (_done) return;
    final moved = _farthest >= _moveSlop;
    _finish(dropped: moved);
    if (!moved &&
        _hit.context.mounted &&
        _editorState.getNodeAtPath(_hit.node.path) == _hit.node) {
      _presentImageMenu(_editorState, _hit);
    }
  }

  /// The gesture was taken away (a call, a system gesture): put it back.
  void cancel() => _finish(dropped: false);

  void _finish({required bool dropped}) {
    if (_done) return;
    _done = true;
    _session.finish(dropped: dropped);
    _entry.remove();
    _entry.dispose();
    _dy.dispose();
    if (dropped) {
      // The block keeps its selection at its new place.
      final path = _hit.node.path;
      _editorState.selection = Selection(
        start: Position(path: path, offset: 0),
        end: Position(path: path, offset: 1),
      );
      HapticFeedback.lightImpact();
    }
  }
}

void _applyImageChoice(
  EditorState editorState,
  _ImageHit hit,
  ImageMenuChoice choice,
) {
  final node = hit.node;
  switch (choice) {
    case ImageMenuChoice.open:
      _openImageHit(editorState, hit);
    case ImageMenuChoice.alignLeft:
      setImageAlign(editorState, node, 'left');
    case ImageMenuChoice.alignCenter:
      setImageAlign(editorState, node, 'center');
    case ImageMenuChoice.alignRight:
      setImageAlign(editorState, node, 'right');
    case ImageMenuChoice.sizeSmall:
    case ImageMenuChoice.sizeMedium:
    case ImageMenuChoice.sizeLarge:
    case ImageMenuChoice.sizeFull:
      final preset = switch (choice) {
        ImageMenuChoice.sizeSmall => ImageSizePreset.small,
        ImageMenuChoice.sizeMedium => ImageSizePreset.medium,
        ImageMenuChoice.sizeLarge => ImageSizePreset.large,
        _ => ImageSizePreset.full,
      };
      setImageWidthFraction(
        editorState,
        node,
        fraction: preset.fraction,
        available: hit.state.availableWidth,
      );
    case ImageMenuChoice.moveUp:
      moveImage(editorState, node, -1);
    case ImageMenuChoice.moveDown:
      moveImage(editorState, node, 1);
    case ImageMenuChoice.remove:
      removeImage(editorState, node);
    case ImageMenuChoice.scanText:
      _scanImageText(editorState, hit);
  }
}

/// Asks the host to read the picture's words; what it returns is added under the picture, one
/// paragraph per line. Nothing is inserted when the host returns nothing (cancelled, no words).
Future<void> _scanImageText(EditorState editorState, _ImageHit hit) async {
  final node = hit.node;
  final src = node.attributes[ImageBlockKeys.url];
  if (src is! String || src.isEmpty) return;
  final ImageTextScanner scanner;
  try {
    scanner = hit.context.read<ImageTextScanner>();
  } on ProviderNotFoundException {
    return;
  }
  final text = await scanner.scanText(hit.context, src);
  if (text == null || text.trim().isEmpty) return;
  // The note may have changed while the model ran: only insert if the picture is still there.
  if (editorState.getNodeAtPath(node.path) != node) return;
  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trimRight())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return;
  final transaction = editorState.transaction
    ..insertNodes(node.path.next, [
      for (final l in lines) paragraphNode(text: l),
    ]);
  await editorState.apply(transaction);
}

extension EditorStateSelection on EditorState {
  List<Node> getVisibleNodes(EditorScrollController controller) {
    final List<Node> sortedNodes = [];
    final positions = controller.visibleRangeNotifier.value;
    // https://github.com/AppFlowy-IO/AppFlowy/issues/3651
    final min = math.max(positions.$1 - 1, 0);
    final max = positions.$2;
    if (min < 0 || max < 0) {
      return sortedNodes;
    }

    int i = -1;
    for (final child in document.root.children) {
      i++;
      if (min > i) {
        continue;
      }
      if (i > max) {
        break;
      }
      sortedNodes.add(child);
    }
    return sortedNodes;
  }

  Node? getNodeInOffset(
    List<Node> sortedNodes,
    Offset offset,
    int start,
    int end, [
    Map<String, Rect>? rectCache,
  ]) {
    // Create rect cache for this operation if not provided
    rectCache ??= {};

    if (start < 0 && end >= sortedNodes.length) {
      return null;
    }

    var min = _findCloseNode(
      sortedNodes,
      start,
      end,
      rectCache: rectCache,
      match: (index, rect) {
        final isMatch = rect.contains(offset);
        AppFlowyEditorLog.selection.debug(
          'findNodeInOffset: $index, rect: $rect, offset: $offset, isMatch: $isMatch',
        );
        return isMatch;
      },
      compare: (index, rect) => rect.bottom <= offset.dy,
    );

    final rowBottom = _getCachedRect(sortedNodes[min], rectCache).bottom;
    final filteredNodes = <Node>[];
    for (final node in sortedNodes) {
      if (_getCachedRect(node, rectCache).bottom == rowBottom) {
        filteredNodes.add(node);
      }
    }
    min = 0;
    if (filteredNodes.length > 1) {
      min = _findCloseNode(
        filteredNodes,
        0,
        filteredNodes.length - 1,
        rectCache: rectCache,
        match: (index, rect) {
          final isMatch = rect.contains(offset);
          AppFlowyEditorLog.selection.debug(
            'findNodeInOffset: $index, rect: $rect, offset: $offset, isMatch: $isMatch',
          );
          return isMatch;
        },
        compare: (index, rect) => rect.right <= offset.dx,
      );
    }

    final node = filteredNodes[min];
    // PREVON PATCH 26: a folded block's children are in the document but not
    // drawn, so their rects are empty (top 0) and the search below would walk
    // into one of them and drop the tap. The folded block itself is the answer.
    final folded = node.attributes[blockComponentCollapsed] == true;
    if (!folded &&
        node.children.isNotEmpty &&
        _getCachedRect(node.children.first, rectCache).top <= offset.dy) {
      // Side-by-side columns have different heights, so the row-by-row search
      // below cannot tell them apart: pick the column the point is in (or
      // nearest to) and search inside it, where blocks stack normally.
      if (node.type == ColumnsBlockKeys.type) {
        final column = _closestColumn(node, offset, rectCache);
        if (column != null) {
          return getNodeInOffset([column], offset, 0, 0, rectCache);
        }
      }
      final skipSortingChildren =
          node.selectable?.skipSortingChildrenWhenSelecting ?? false;

      List<Node> children;

      if (skipSortingChildren) {
        children = node.children;
      } else {
        children = node.children.toList(growable: false)
          ..sort(
            (a, b) {
              final aRect = _getCachedRect(a, rectCache!);
              final bRect = _getCachedRect(b, rectCache);
              return aRect.bottom != bRect.bottom
                  ? aRect.bottom.compareTo(bRect.bottom)
                  : aRect.left.compareTo(bRect.left);
            },
          );
      }

      // if the nodes are in the same tab view, their rect are overlaid,
      //  we need to filter out the invisible nodes
      bool hasInvisibleChildren = false;
      final visibleChildren = <Node>[];
      for (final child in children) {
        final context = child.key.currentContext;
        var isVisible = true;
        context?.visitAncestorElements((element) {
          final widget = element.widget;
          if (widget is Opacity && widget.opacity == 0) {
            isVisible = false;
            return false;
          }
          return true;
        });
        if (isVisible) {
          visibleChildren.add(child);
        } else {
          hasInvisibleChildren = true;
        }
      }
      if (hasInvisibleChildren) {
        children = visibleChildren;
      }

      if (children.isEmpty) {
        return node;
      }

      return getNodeInOffset(
        children,
        offset,
        0,
        children.length - 1,
        rectCache,
      );
    }
    return node;
  }

  /// The column of [columns] that contains [offset], else the nearest one.
  Node? _closestColumn(
    Node columns,
    Offset offset,
    Map<String, Rect> rectCache,
  ) {
    Node? best;
    var bestDistance = double.infinity;
    for (final column in columns.children) {
      if (column.type != ColumnBlockKeys.type) continue;
      final rect = _getCachedRect(column, rectCache);
      final dx = math.max(
        math.max(rect.left - offset.dx, 0.0),
        offset.dx - rect.right,
      );
      final dy = math.max(
        math.max(rect.top - offset.dy, 0.0),
        offset.dy - rect.bottom,
      );
      final double distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = column;
      }
    }
    return best;
  }

  /// Get cached rect for a node, computing and caching if not present
  Rect _getCachedRect(Node node, Map<String, Rect> cache) {
    return cache.putIfAbsent(node.id, () => node.rect);
  }

  int _findCloseNode(
    List<Node> sortedNodes,
    int start,
    int end, {
    required Map<String, Rect> rectCache,
    bool Function(int index, Rect rect)? match,
    required bool Function(int index, Rect rect) compare,
  }) {
    for (var i = start; i <= end; i++) {
      final rect = _getCachedRect(sortedNodes[i], rectCache);
      if (match != null && match(i, rect)) {
        return i;
      }
    }

    var min = start;
    var max = end;
    while (min <= max) {
      final mid = min + ((max - min) >> 1);
      final rect = _getCachedRect(sortedNodes[mid], rectCache);
      if (compare(mid, rect)) {
        min = mid + 1;
      } else {
        max = mid - 1;
      }
    }

    return min.clamp(start, end);
  }
}

/// Triple-tap selection: only the paragraph (the run between `\n` line
/// breaks) under [offset], not every paragraph of the node.
Selection tripleTapSelection(
  Node node,
  SelectableMixin selectable,
  Offset offset,
) {
  final whole = Selection(start: selectable.start(), end: selectable.end());
  final delta = node.delta;
  if (delta == null) return whole;
  final text = delta.toPlainText();
  if (!text.contains('\n')) return whole;
  final tapped = selectable.getPositionInOffset(offset).offset.clamp(
        0,
        text.length,
      );
  final before = tapped == 0 ? -1 : text.lastIndexOf('\n', tapped - 1);
  final after = text.indexOf('\n', tapped);
  final start = before + 1;
  final end = after == -1 ? text.length : after;
  return Selection(
    start: Position(path: node.path, offset: start),
    end: Position(path: node.path, offset: end),
  );
}
