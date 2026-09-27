import 'dart:async';
import 'dart:math';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract class SelectionMenuService {
  Offset get offset;

  Alignment get alignment;

  SelectionMenuStyle get style;

  Future<void> show();

  void dismiss();

  (double? left, double? top, double? right, double? bottom) getPosition();
}

class SelectionMenu extends SelectionMenuService with WidgetsBindingObserver {
  SelectionMenu({
    required this.context,
    required this.editorState,
    required this.selectionMenuItems,
    this.deleteSlashByDefault = true,
    this.deleteKeywordsByDefault = false,
    this.style = SelectionMenuStyle.light,
    this.itemCountFilter = 0,
    this.singleColumn = false,
    this.menuHeight = 300,
    this.menuWidth = 300,
    this.insertedSlashPath,
    this.insertedSlashOffset,
  });

  final BuildContext context;
  final EditorState editorState;
  final List<SelectionMenuItem> selectionMenuItems;
  final bool deleteSlashByDefault;
  final bool deleteKeywordsByDefault;
  final bool singleColumn;
  final double menuHeight;
  final double menuWidth;

  /// PREVON PATCH 12: the path of the node and the offset at which THIS menu
  /// instance inserted its trigger `/` (null when the menu was constructed by
  /// a caller that does not insert one — e.g. the image upload menu, or the
  /// `shouldInsertSlash: false` variant). When set, `dismiss()` can remove the
  /// stray `/` if the user cancels without picking an item and the document
  /// has not otherwise changed. See the Founder reason on `_showSlashMenu`.
  final Path? insertedSlashPath;
  final int? insertedSlashOffset;

  /// PREVON PATCH 12: set true the moment the user picks an item. The item's
  /// own handler deletes the `/` (see `SelectionMenuItem._deleteSlash`), so the
  /// dismiss-time cleanup must not try to delete it a second time.
  bool _slashConsumed = false;

  /// PREVON PATCH 12: the selection that triggered a selection-change dismiss
  /// (captured in `_onSelectionChange` before `dismiss()` runs). The menu's
  /// listener fires from `currentSelection.value =` BEFORE the selection
  /// service updates `editorState.selection`, so the editor state is stale at
  /// cleanup time; this field carries the *new* selection so the cleanup sees
  /// the moved caret and correctly leaves the `/` alone. Null for tap-outside
  /// / Escape / pre-show dismisses, where the editor state is authoritative.
  Selection? _dismissSelection;

  @override
  final SelectionMenuStyle style;

  OverlayEntry? _selectionMenuEntry;
  bool _selectionUpdateByInner = false;
  Offset _offset = Offset.zero;
  Alignment _alignment = Alignment.topLeft;
  int itemCountFilter;

  /// PREVON PATCH 11: the caret rect captured when `show()` is invoked, in
  /// global (screen) coordinates. Placement is recomputed from it on every
  /// overlay rebuild, so it is kept as state rather than a local.
  Rect? _caretRect;

  /// Gap between the caret and the menu (preserves the historical `Offset(0, 10)`).
  static const double _kMenuGap = 10.0;

  /// Nominal single-row height + chrome, used ONLY by the above/below fit
  /// heuristic. The ListView still measures real rows; this estimate only
  /// decides which side has room and how much to cap.
  static const double _kRowHeight = 36.0;
  static const double _kMenuPadding = 8.0;

  /// Keep the menu this far from a screen edge when clamping horizontally.
  static const double _kEdgeMargin = 8.0;

  @override
  void dismiss() {
    // PREVON PATCH 12: whether the menu was actually on screen. The internal
    // pre-show `dismiss()` at the top of `_show()` has no entry yet, so this
    // gate guarantees it never runs the slash cleanup.
    final hadEntry = _selectionMenuEntry != null;

    // PREVON PATCH 11: always detach the metrics observer first so an early
    // exit (empty selection rects, re-show, item tap) cannot leak it.
    WidgetsBinding.instance.removeObserver(this);

    if (_selectionMenuEntry != null) {
      editorState.service.keyboardService?.enable();
      editorState.service.scrollService?.enable();
    }

    _selectionMenuEntry?.remove();
    _selectionMenuEntry = null;

    // workaround: SelectionService has been released after hot reload.
    final isSelectionDisposed =
        editorState.service.selectionServiceKey.currentState == null;
    if (!isSelectionDisposed) {
      final selectionService = editorState.service.selectionService;
      // focus to reload the selection after the menu dismissed.
      editorState.selection = editorState.selection;
      selectionService.currentSelection.removeListener(_onSelectionChange);
    }

    // PREVON PATCH 12: cleanup runs LAST and only for a real dismissal, so it
    // cannot re-enter `_onSelectionChange` -> `dismiss()` (the listener was
    // just removed). It no-ops on a pre-show dismiss, an item selection, or any
    // document/caret change since the slash was inserted.
    if (hadEntry) {
      _removeInsertedSlashIfUntouched();
    }
    _dismissSelection = null;
  }

  /// PREVON PATCH 12: if this menu inserted the trigger `/` and the user
  /// dismissed without selecting an item — leaving the caret collapsed exactly
  /// after an untouched lone `/` — remove that `/` so it is not autosaved into
  /// the document. Any other state (filter text typed, caret moved, document
  /// mutated underneath, item selected) is left alone.
  ///
  /// The removal is excluded from undo/redo history.
  void _removeInsertedSlashIfUntouched() {
    try {
      if (_slashConsumed) return;
      final path = insertedSlashPath;
      final offset = insertedSlashOffset;
      if (path == null || offset == null) return;

      // A selection-change dismiss carries the new selection (see
      // `_dismissSelection`); every other dismiss uses the editor state.
      final selection = _dismissSelection ?? editorState.selection;
      if (selection == null || !selection.isCollapsed) return;
      if (!selection.start.path.equals(path)) return;
      if (selection.start.offset != offset + 1) return;

      final node = editorState.getNodeAtPath(path);
      final delta = node?.delta;
      if (node == null || delta == null) return;

      final text = delta.toPlainText();
      if (text.length != offset + 1 || text[offset] != '/') return;

      final transaction = editorState.transaction
        ..deleteText(node, offset, 1);
      editorState.apply(
        transaction,
        options: const ApplyOptions(recordUndo: false, recordRedo: false),
      );
    } catch (error) {
      // The cleanup must never throw out of `dismiss()`.
      if (kDebugMode) {
        debugPrint('SelectionMenu slash cleanup failed: $error');
      }
    }
  }

  @override
  Future<void> show() async {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _show();
      completer.complete();
    });
    return completer.future;
  }

  void _show() {
    dismiss();

    final selectionService = editorState.service.selectionService;
    final selectionRects = selectionService.selectionRects;
    if (selectionRects.isEmpty) {
      return;
    }

    // PREVON PATCH 11: capture the caret rect; placement is deferred to the
    // overlay builder so it is recomputed on every rebuild (metrics change,
    // keyboard show/hide, rotation) instead of being frozen at show-time.
    _caretRect = selectionRects.first;

    _selectionMenuEntry = OverlayEntry(
      builder: (overlayContext) {
        final placement = _computePlacement(overlayContext);
        // PREVON PATCH 11: the root overlay spans the whole screen, so the
        // host box is screen-sized and every coordinate below — the editor
        // origin (`editorOffset`) and the caret rect (selectionRects are
        // already transformed to global) — is in the same screen space. This
        // removes the old split where a screen-relative SizedBox sat at y=0
        // while the editor origin was folded into the offsets (finding D3).
        return SizedBox(
          width: placement.screenSize.width,
          height: placement.screenSize.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              dismiss();
            },
            child: Stack(
              children: [
                Positioned(
                  left: placement.left,
                  top: placement.below ? placement.anchor : null,
                  bottom: placement.below ? null : placement.anchor,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectionMenuWidget(
                      selectionMenuStyle: style,
                      singleColumn: singleColumn,
                      items: selectionMenuItems
                        ..forEach((element) {
                          element.deleteSlash = deleteSlashByDefault;
                          element.deleteKeywords = deleteKeywordsByDefault;
                          element.onSelected = () {
                            // PREVON PATCH 12: the item's own handler already
                            // deleted the `/`; mark it consumed so the dismiss
                            // cleanup cannot delete it (or a neighbouring
                            // character) a second time.
                            _slashConsumed = true;
                            dismiss();
                          };
                        }),
                      maxItemInRow: 5,
                      editorState: editorState,
                      itemCountFilter: itemCountFilter,
                      menuService: this,
                      // PREVON PATCH 11: fit the menu to the space the
                      // formula found instead of a fixed 300×300 box.
                      maxHeight: placement.maxHeight,
                      availableWidth: placement.availableWidth,
                      minRowHeight: placement.minRowHeight,
                      onExit: () {
                        dismiss();
                      },
                      onSelectionUpdate: () {
                        _selectionUpdateByInner = true;
                      },
                      deleteSlashByDefault: deleteSlashByDefault,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_selectionMenuEntry!);

    // PREVON PATCH 11: observe metrics while the menu is open so a keyboard
    // show/hide, rotation or resize triggers didChangeMetrics and rebuilds
    // the entry with fresh placement.
    WidgetsBinding.instance.addObserver(this);

    // PREVON PATCH 11 — intentionally UNCHANGED. `disable(showCursor: true)`
    // must stay as-is: it suppresses the software cursor while the menu is
    // up. Any change (e.g. passing showCursor: false) needs a live Android
    // emulator check that the keyboard stays open and the caret survives,
    // which this engine-only test pass cannot make. Do not modify here.
    editorState.service.keyboardService?.disable(showCursor: true);
    editorState.service.scrollService?.disable();
    selectionService.currentSelection.addListener(_onSelectionChange);
  }

  @override
  void didChangeMetrics() {
    // PREVON PATCH 11: the OS keyboard, rotation or a window resize changed
    // the layout while the menu is open. Force the overlay entry to rebuild
    // so `_computePlacement` re-reads MediaQuery and re-caps / re-flips the
    // menu. No-op when the menu has since been dismissed.
    _selectionMenuEntry?.markNeedsBuild();
  }

  @override
  Alignment get alignment {
    return _alignment;
  }

  @override
  Offset get offset {
    return _offset;
  }

  /// PREVON PATCH 11: touch platforms get a tappable 44px minimum row;
  /// desktop keeps the natural row height (`0` = no floor).
  double get _minRowHeight {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return 44.0;
      default:
        return 0.0;
    }
  }

  void _onSelectionChange() {
    // workaround: SelectionService has been released after hot reload.
    final isSelectionDisposed =
        editorState.service.selectionServiceKey.currentState == null;
    if (!isSelectionDisposed) {
      final selectionService = editorState.service.selectionService;
      if (selectionService.currentSelection.value == null) {
        return;
      }
    }

    if (_selectionUpdateByInner) {
      _selectionUpdateByInner = false;
      return;
    }

    // PREVON PATCH 12: capture the selection that triggered this dismiss. The
    // listener fires from `currentSelection.value =` before the selection
    // service syncs `editorState.selection`, so the editor state is still the
    // pre-move value at cleanup time; the cleanup must see this one.
    _dismissSelection = editorState.service.selectionService.currentSelection.value;
    dismiss();
  }

  @override
  (double? left, double? top, double? right, double? bottom) getPosition() {
    double? left, top, right, bottom;
    switch (alignment) {
      case Alignment.topLeft:
        left = offset.dx;
        top = offset.dy;
        break;
      case Alignment.bottomLeft:
        left = offset.dx;
        bottom = offset.dy;
        break;
      case Alignment.topRight:
        right = offset.dx;
        top = offset.dy;
        break;
      case Alignment.bottomRight:
        right = offset.dx;
        bottom = offset.dy;
        break;
    }

    return (left, top, right, bottom);
  }

  /// PREVON PATCH 11: compute the menu's placement, cap, available width and
  /// row floor from the overlay's current [MediaQuery]. Called from inside the
  /// [OverlayEntry] builder, so it recomputes on every rebuild (including the
  /// rebuilds driven by [didChangeMetrics]).
  ///
  /// All coordinates are screen coordinates: the overlay spans the screen, the
  /// editor origin is `renderBox.localToGlobal`, and the caret rect from
  /// `selectionRects()` is already transformed to global.
  _MenuPlacement _computePlacement(BuildContext overlayContext) {
    final mediaQuery = MediaQuery.of(overlayContext);
    final screenSize = mediaQuery.size;
    final viewInsets = mediaQuery.viewInsets;
    final padding = mediaQuery.padding;

    final editorBox = editorState.renderBox;
    final editorOffset = editorBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final editorHeight = editorBox?.size.height ?? screenSize.height;
    // Re-read the caret rect on every build so a metrics-driven resize keeps
    // the menu anchored to where the caret actually is; fall back to the rect
    // captured at show-time if the selection is momentarily unavailable.
    final selectionRects = editorState.service.selectionService.selectionRects;
    final caretRect = selectionRects.isNotEmpty
        ? selectionRects.first
        : (_caretRect ?? Rect.zero);

    // PREVON PATCH 11 fit formula (soft-keyboard aware):
    //   screenBottom = visible bottom of the screen (excludes the OS keyboard)
    //   editorBottom = the lower of the editor's bottom and the visible bottom
    //   availBelow   = room between the caret and editorBottom
    //   availAbove   = room between the editor top and the caret
    final screenBottom = screenSize.height - viewInsets.bottom - padding.bottom;
    final editorBottom = min(editorOffset.dy + editorHeight, screenBottom);
    final availBelow = max(0.0, editorBottom - caretRect.bottom - _kMenuGap);
    final availAbove = max(0.0, caretRect.top - editorOffset.dy - _kMenuGap);
    final needed = selectionMenuItems.length * _kRowHeight + _kMenuPadding;

    // Prefer below when it either fits outright or is at least as roomy as
    // above; otherwise flip above. Cap at the configured `menuHeight` so the
    // pre-patch 300px upper bound is preserved when there is lots of room.
    final below = availBelow >= needed || availBelow >= availAbove;
    final rawMaxHeight = below ? availBelow : availAbove;
    final maxHeight = rawMaxHeight.clamp(0.0, menuHeight).toDouble();

    // Horizontal: align the left edge with the caret, then clamp so the menu
    // never runs off a screen edge. `availableWidth` is the width left at that
    // x (never more than the configured `menuWidth`); the widget caps its own
    // 300px default to it so narrow screens do not overflow.
    final maxAvailWidth = max(0.0, screenSize.width - 2 * _kEdgeMargin);
    final availableWidth = min(menuWidth, maxAvailWidth);
    final maxLeft =
        max(_kEdgeMargin, screenSize.width - availableWidth - _kEdgeMargin);
    final left = caretRect.left.clamp(_kEdgeMargin, maxLeft).toDouble();

    // Keep `_offset` / `_alignment` in sync for the public `getPosition()` API
    // (the image upload menu consumes it downstream). The anchor is the top
    // edge for a below menu and the bottom edge for an above menu.
    if (below) {
      _alignment = Alignment.topLeft;
      _offset = Offset(left, caretRect.bottom + _kMenuGap);
    } else {
      _alignment = Alignment.bottomLeft;
      _offset = Offset(left, screenSize.height - (caretRect.top - _kMenuGap));
    }

    return _MenuPlacement(
      screenSize: screenSize,
      left: left,
      below: below,
      anchor: _offset.dy,
      maxHeight: maxHeight,
      availableWidth: availableWidth,
      minRowHeight: _minRowHeight,
    );
  }
}

/// PREVON PATCH 11: resolved placement handed from `_computePlacement` to the
/// overlay builder.
class _MenuPlacement {
  const _MenuPlacement({
    required this.screenSize,
    required this.left,
    required this.below,
    required this.anchor,
    required this.maxHeight,
    required this.availableWidth,
    required this.minRowHeight,
  });

  final Size screenSize;
  final double left;

  /// True when the menu is anchored by its top edge (below the caret); false
  /// when anchored by its bottom edge (above the caret).
  final bool below;

  /// Top edge (screen coords) when [below], bottom-inset from the screen's
  /// bottom edge when not.
  final double anchor;
  final double maxHeight;
  final double availableWidth;
  final double minRowHeight;
}

/// The fork's default "image" `/`-menu entry.
///
/// Extracted to a named top-level `final` (content byte-identical to the item
/// that previously sat inline inside [standardSelectionMenuItems]) so the host
/// app can exclude it BY IDENTITY and substitute its own app-owned image item.
/// The default handler passes no `onInsertImage` to [showImageMenu], which
/// makes the fork insert the picked src verbatim — including a raw local file
/// path. The app-owned replacement supplies `onInsertImage` to encrypt a
/// genuine local file first and insert a `pie-att://` URI instead.
final SelectionMenuItem imageSelectionMenuItem = SelectionMenuItem(
  getName: () => AppFlowyEditorL10n.current.image,
  icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
    name: 'image',
    isSelected: isSelected,
    style: style,
  ),
  keywords: ['image'],
  handler: (editorState, menuService, context) {
    final container = Overlay.of(context, rootOverlay: true);
    showImageMenu(container, editorState, menuService);
  },
);

final List<SelectionMenuItem> standardSelectionMenuItems = [
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.text,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'text',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['text'],
    handler: (editorState, _, __) {
      insertNodeAfterSelection(editorState, paragraphNode());
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading1,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h1',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 1, h1'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 1);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading2,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h2',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 2, h2'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 2);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading3,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h3',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 3, h3'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 3);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.bulletedList,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'bulleted_list',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['bulleted list', 'list', 'unordered list'],
    handler: (editorState, _, __) {
      insertBulletedListAfterSelection(editorState);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.numberedList,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'number',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['numbered list', 'list', 'ordered list'],
    handler: (editorState, _, __) {
      insertNumberedListAfterSelection(editorState);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.checkbox,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'checkbox',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['todo list', 'list', 'checkbox list'],
    handler: (editorState, _, __) {
      insertCheckboxAfterSelection(editorState);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.quote,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'quote',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['quote', 'refer'],
    handler: (editorState, _, __) {
      insertQuoteAfterSelection(editorState);
    },
  ),
  dividerMenuItem,
  tableMenuItem,
  imageSelectionMenuItem,
];

final List<SelectionMenuItem> singleColumnVisibleMenuItems = [
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.text,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'text',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['text'],
    handler: (editorState, _, __) {
      insertNodeAfterSelection(editorState, paragraphNode());
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading1,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h1',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 1, h1'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 1);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading2,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h2',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 2, h2'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 2);
    },
  ),
];
