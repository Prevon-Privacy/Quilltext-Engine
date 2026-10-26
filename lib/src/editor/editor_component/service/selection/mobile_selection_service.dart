import 'dart:async';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/selection/mobile_magnifier.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/selection/shared.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';
import 'package:prevon_quilltext_engine/src/render/selection/mobile_basic_handle.dart';
import 'package:prevon_quilltext_engine/src/render/selection/mobile_collapsed_handle.dart';
import 'package:prevon_quilltext_engine/src/render/selection/mobile_selection_handle.dart';
import 'package:prevon_quilltext_engine/src/service/selection/mobile_selection_gesture.dart';
import 'package:flutter/material.dart' hide Overlay, OverlayEntry;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as fw show Overlay, OverlayEntry;
import 'package:provider/provider.dart';

/// only used in mobile
///
/// this will notify the developers when the selection is not collapsed.
StreamController<int> appFlowyEditorOnTapSelectionArea =
    StreamController<int>.broadcast();

enum MobileSelectionDragMode {
  none,
  leftSelectionHandle,
  rightSelectionHandle,
  cursor;
}

enum MobileSelectionHandlerType {
  leftHandle,
  rightHandle,
  cursorHandle,
}

// the value type is MobileSelectionDragMode
const String selectionDragModeKey = 'selection_drag_mode';
bool disableIOSSelectWordEdgeOnTap = false;
bool disableMagnifier = false;

class MobileSelectionServiceWidget extends StatefulWidget {
  const MobileSelectionServiceWidget({
    super.key,
    this.cursorColor = const Color(0xFF00BCF0),
    this.selectionColor = const Color.fromARGB(53, 111, 201, 231),
    this.showMagnifier = true,
    this.magnifierSize = const Size(72, 48),
    this.dropTargetStyle = const AppFlowyDropTargetStyle(),
    required this.child,
  });

  /// Look of the line that shows where a dragged block will land.
  final AppFlowyDropTargetStyle dropTargetStyle;

  final Widget child;
  final Color cursorColor;
  final Color selectionColor;

  /// Show the magnifier or not.
  ///
  /// only works on iOS or Android.
  final bool showMagnifier;

  final Size magnifierSize;

  @override
  State<MobileSelectionServiceWidget> createState() =>
      _MobileSelectionServiceWidgetState();
}

class _MobileSelectionServiceWidgetState
    extends State<MobileSelectionServiceWidget>
    with WidgetsBindingObserver
    implements AppFlowySelectionService {
  // Expose `selectionRects` as a getter that delegates to
  // `editorState.selectionRects()` so a collapsed cursor produces a
  // collapsed-cursor rect (not an empty list). Mirrors the
  // `DesktopSelectionServiceWidgetState` shape verbatim. The internal
  // non-collapsed accumulator (`_selectionRects`) is preserved for the
  // existing write sites that build it up during drag-select.
  @override
  List<Rect> get selectionRects => editorState.selectionRects();

  final List<Rect> _selectionRects = [];

  @override
  ValueNotifier<Selection?> currentSelection = ValueNotifier(null);

  @override
  List<Node> currentSelectedNodes = [];

  final List<SelectionGestureInterceptor> _interceptors = [];
  final ValueNotifier<Offset?> _lastPanOffset = ValueNotifier(null);

  // the selection from editorState will be updated directly, but the cursor
  // or selection area depends on the layout of the text, so we need to update
  // the selection after the layout.
  final PropertyValueNotifier<Selection?> selectionNotifierAfterLayout =
      PropertyValueNotifier<Selection?>(null);

  /// Pan
  Offset? _panStartOffset;
  double? _panStartScrollDy;
  Selection? _panStartSelection;
  bool? _isPanStartHorizontal;

  MobileSelectionDragMode dragMode = MobileSelectionDragMode.none;

  bool updateSelectionByTapUp = false;

  late EditorState editorState = Provider.of<EditorState>(
    context,
    listen: false,
  );

  bool isCollapsedHandleVisible = false;

  Timer? collapsedHandleTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    editorState.selectionNotifier.addListener(_updateSelection);
    editorState.addScrollViewScrolledListener(_handleAutoScrollWhileDragging);
  }

  @override
  void dispose() {
    _imageLift?.cancel();
    _imageLift = null;
    clearSelection();
    WidgetsBinding.instance.removeObserver(this);
    selectionNotifierAfterLayout.dispose();
    editorState.selectionNotifier.removeListener(_updateSelection);
    editorState.removeScrollViewScrolledListener(
      _handleAutoScrollWhileDragging,
    );
    collapsedHandleTimer?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,

        // magnifier for zoom in the text.
        if (widget.showMagnifier) _buildMagnifier(),

        // the handles for expanding the selection area.
        _buildLeftHandle(),
        _buildRightHandle(),
        _buildCollapsedHandle(),
      ],
    );
    return PlatformExtension.isIOS
        ? MobileSelectionGestureDetector(
            onTapUp: _onTapUpIOS,
            onDoubleTapUp: _onDoubleTapUp,
            onTripleTapUp: _onTripleTapUp,
            onLongPressStart: _onLongPressStartIOS,
            onLongPressMoveUpdate: _onLongPressUpdateIOS,
            onLongPressEnd: _onLongPressEndIOS,
            onLongPressCancel: _cancelHold,
            child: stack,
          )
        : MobileSelectionGestureDetector(
            onTapUp: _onTapUpAndroid,
            onDoubleTapUp: _onDoubleTapUp,
            onTripleTapUp: _onTripleTapUp,
            onLongPressStart: _onLongPressStartAndroid,
            onLongPressMoveUpdate: _onLongPressUpdateAndroid,
            onLongPressEnd: _onLongPressEndAndroid,
            onLongPressCancel: _cancelHold,
            onPanUpdate: _onPanUpdateAndroid,
            onPanEnd: _onPanEndAndroid,
            child: stack,
          );
  }

  Widget _buildMagnifier() {
    return ValueListenableBuilder(
      valueListenable: _lastPanOffset,
      builder: (_, offset, __) {
        if (offset == null || disableMagnifier) {
          return const SizedBox.shrink();
        }
        final renderBox = context.findRenderObject() as RenderBox;
        final local = renderBox.globalToLocal(offset);
        return MobileMagnifier(
          size: widget.magnifierSize,
          offset: local,
          bounds: renderBox.size,
        );
      },
    );
  }

  Widget _buildCollapsedHandle() {
    return ValueListenableBuilder(
      valueListenable: selectionNotifierAfterLayout,
      builder: (context, selection, _) {
        if (selection == null ||
            !selection.isCollapsed ||
            editorState.selectionExtraInfo?[selectionExtraInfoDisableToolbar] ==
                true) {
          isCollapsedHandleVisible = false;
          return const SizedBox.shrink();
        }

        // on Android, the drag handle should be updated when typing text.
        if (PlatformExtension.isAndroid &&
            editorState.selectionUpdateReason !=
                SelectionUpdateReason.uiEvent) {
          isCollapsedHandleVisible = false;
          return const SizedBox.shrink();
        }

        if (selection.isCollapsed &&
            [
              MobileSelectionDragMode.leftSelectionHandle,
              MobileSelectionDragMode.rightSelectionHandle,
            ].contains(dragMode)) {
          isCollapsedHandleVisible = false;
          return const SizedBox.shrink();
        }

        selection = selection.normalized;

        final node = editorState.getNodeAtPath(selection.start.path);
        final selectable = node?.selectable;
        var rect = selectable?.getCursorRectInPosition(
          selection.start,
          shiftWithBaseOffset: true,
        );

        if (node == null || rect == null) {
          isCollapsedHandleVisible = false;
          return const SizedBox.shrink();
        }

        isCollapsedHandleVisible = true;

        _clearCollapsedHandleOnAndroid();

        final editorStyle = editorState.editorStyle;
        return MobileCollapsedHandle(
          layerLink: node.layerLink,
          rect: rect,
          handleColor: editorStyle.dragHandleColor,
          handleWidth: editorStyle.mobileDragHandleWidth,
          handleBallWidth: editorStyle.mobileDragHandleBallSize.width,
          enableHapticFeedbackOnAndroid:
              editorStyle.enableHapticFeedbackOnAndroid,
          onDragging: (isDragging) {
            if (isDragging) {
              collapsedHandleTimer?.cancel();
              collapsedHandleTimer = null;
            } else {
              _clearCollapsedHandleOnAndroid();
            }
          },
        );
      },
    );
  }

  Widget _buildLeftHandle() {
    return _buildHandle(HandleType.left);
  }

  Widget _buildRightHandle() {
    return _buildHandle(HandleType.right);
  }

  Widget _buildHandle(HandleType handleType) {
    if (![HandleType.left, HandleType.right].contains(handleType)) {
      throw ArgumentError('showLeftHandle and showRightHandle cannot be same.');
    }

    return ValueListenableBuilder(
      valueListenable: selectionNotifierAfterLayout,
      builder: (context, selection, _) {
        if (selection == null) {
          return const SizedBox.shrink();
        }
        if (editorState.selectionExtraInfo?[selectionExtraInfoDisableToolbar] ==
            true) {
          // Programmatic highlight (find-in-note): no drag handles.
          return const SizedBox.shrink();
        }

        if (selection.isCollapsed &&
            [
              MobileSelectionDragMode.none,
              MobileSelectionDragMode.cursor,
            ].contains(dragMode)) {
          return const SizedBox.shrink();
        }

        final isCollapsedWhenDraggingHandle = selection.isCollapsed &&
            [
              MobileSelectionDragMode.leftSelectionHandle,
              MobileSelectionDragMode.rightSelectionHandle,
            ].contains(dragMode);

        selection = selection.normalized;

        final node = editorState.getNodeAtPath(
          handleType == HandleType.left
              ? selection.start.path
              : selection.end.path,
        );
        final selectable = node?.selectable;

        // get the cursor rect when the selection is collapsed.
        final rects = isCollapsedWhenDraggingHandle
            ? [
                selectable?.getCursorRectInPosition(
                      selection.start,
                      shiftWithBaseOffset: true,
                    ) ??
                    Rect.zero,
              ]
            : selectable?.getRectsInSelection(
                selection,
                shiftWithBaseOffset: true,
              );

        if (node == null || rects == null || rects.isEmpty) {
          return const SizedBox.shrink();
        }

        final editorStyle = editorState.editorStyle;
        return MobileSelectionHandle(
          layerLink: node.layerLink,
          rect: handleType == HandleType.left ? rects.first : rects.last,
          handleType: handleType,
          handleColor: isCollapsedWhenDraggingHandle
              ? Colors.transparent
              : editorStyle.dragHandleColor,
          handleWidth: editorStyle.mobileDragHandleWidth,
          handleBallWidth: editorStyle.mobileDragHandleBallSize.width,
          enableHapticFeedbackOnAndroid:
              editorStyle.enableHapticFeedbackOnAndroid,
        );
      },
    );
  }

  // The collapsed handle will be dismissed when no user interaction is detected.
  void _clearCollapsedHandleOnAndroid() {
    if (!PlatformExtension.isAndroid) {
      return;
    }
    collapsedHandleTimer?.cancel();
    collapsedHandleTimer = Timer(
      editorState.editorStyle.autoDismissCollapsedHandleDuration,
      () {
        if (isCollapsedHandleVisible) {
          editorState.updateSelectionWithReason(
            editorState.selection,
            reason: SelectionUpdateReason.transaction,
          );
        }
      },
    );
  }

  @override
  void updateSelection(Selection? selection) {
    if (currentSelection.value == selection) {
      return;
    }

    _clearSelection();

    if (selection != null) {
      if (!selection.isCollapsed) {
        // updates selection area.
        AppFlowyEditorLog.selection.debug('update cursor area, $selection');
        _updateSelectionAreas(selection);
      }
    }

    currentSelection.value = selection;
    editorState.updateSelectionWithReason(
      selection,
      reason: SelectionUpdateReason.uiEvent,
      customSelectionType: SelectionType.inline,
      extraInfo: {
        selectionDragModeKey: dragMode,
        selectionExtraInfoDoNotAttachTextService:
            dragMode == MobileSelectionDragMode.cursor,
      },
    );
  }

  @override
  void clearSelection() {
    currentSelectedNodes = [];
    currentSelection.value = null;

    _clearSelection();
  }

  void _clearPanVariables() {
    _panStartOffset = null;
    _panStartSelection = null;
    _panStartScrollDy = null;
    _lastPanOffset.value = null;
    _wordDrag = false;
    _lastAppliedOffset = null;
  }

  @override
  void clearCursor() {
    _clearSelection();
  }

  void _clearSelection() {
    _selectionRects.clear();
  }

  void _handleAutoScrollWhileDragging() {
    if (!mounted || dragMode == MobileSelectionDragMode.none) {
      return;
    }
    if (_panStartOffset == null ||
        _panStartSelection == null ||
        _lastPanOffset.value == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          dragMode == MobileSelectionDragMode.none ||
          _panStartOffset == null ||
          _panStartSelection == null) {
        return;
      }
      final offset = _lastPanOffset.value;
      if (offset == null) {
        return;
      }
      if (_wordDrag) {
        // PREVON PATCH 24: a word drag keeps its word anchor; the caret
        // path below would collapse it to a single point.
        _extendWordSelectionTo(offset);
        return;
      }
      _updateSelectionDuringDrag(offset);
    });
  }

  void _updateSelectionDuringDrag(Offset panEndOffset) {
    if (_panStartOffset == null || _panStartSelection == null) {
      return;
    }

    final double? dy = editorState.service.scrollService?.dy;
    final Offset panStartOffset;
    if (dy == null || _panStartScrollDy == null) {
      panStartOffset = _panStartOffset!;
    } else {
      panStartOffset = _panStartOffset!.translate(
        0,
        _panStartScrollDy! - dy,
      );
    }

    final selectionInRange = getNodeInOffset(panEndOffset)
        ?.selectable
        ?.getSelectionInRange(panStartOffset, panEndOffset);
    final end = selectionInRange?.end;
    if (end == null) {
      return;
    }

    late final Selection newSelection;
    switch (dragMode) {
      case MobileSelectionDragMode.leftSelectionHandle:
        newSelection = Selection(
          start: _panStartSelection!.normalized.end,
          end: end,
        ).normalized;
        break;
      case MobileSelectionDragMode.rightSelectionHandle:
        newSelection = Selection(
          start: _panStartSelection!.normalized.start,
          end: end,
        ).normalized;
        break;
      case MobileSelectionDragMode.cursor:
        newSelection = Selection.collapsed(end);
        break;
      case MobileSelectionDragMode.none:
        return;
    }

    updateSelection(newSelection);
  }

  @override
  Node? getNodeInOffset(Offset offset) {
    final List<Node> sortedNodes = editorState.getVisibleNodes(
      context.read<EditorScrollController>(),
    );

    return editorState.getNodeInOffset(
      sortedNodes,
      offset,
      0,
      sortedNodes.length - 1,
    );
  }

  @override
  Position? getPositionInOffset(Offset offset) {
    final node = getNodeInOffset(offset);
    final selectable = node?.selectable;
    if (selectable == null) {
      clearSelection();
      return null;
    }
    return selectable.getPositionInOffset(offset);
  }

  @override
  void registerGestureInterceptor(SelectionGestureInterceptor interceptor) {
    _interceptors.add(interceptor);
  }

  @override
  void unregisterGestureInterceptor(String key) {
    _interceptors.removeWhere((element) => element.key == key);
  }

  void _updateSelection() {
    final selection = editorState.selection;

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (mounted) selectionNotifierAfterLayout.value = selection;
    });

    if (currentSelection.value != selection) {
      clearSelection();
      return;
    }

    if (selection != null) {
      if (!selection.isCollapsed) {
        // updates selection area.
        AppFlowyEditorLog.selection.debug('update cursor area, $selection');
        WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
          _selectionRects.clear();
          _clearSelection();
          _updateSelectionAreas(selection);
        });
      }
    }
  }

  @override
  Selection? onPanStart(
    DragStartDetails details,
    MobileSelectionDragMode mode,
  ) {
    _panStartOffset = details.globalPosition.translate(-3.0, 0);
    _panStartScrollDy = editorState.service.scrollService?.dy;

    final selection = editorState.selection;
    _panStartSelection = selection;

    dragMode = mode;

    return selection;
  }

  @override
  Selection? onPanUpdate(
    DragUpdateDetails details,
    MobileSelectionDragMode mode,
  ) {
    if (_panStartOffset == null || _panStartScrollDy == null) {
      return null;
    }

    // only support selection mode now.
    if (editorState.selection == null ||
        dragMode == MobileSelectionDragMode.none) {
      return null;
    }

    final panEndOffset = details.globalPosition;

    final dy = editorState.service.scrollService?.dy;
    final panStartOffset = dy == null
        ? _panStartOffset!
        : _panStartOffset!.translate(0, _panStartScrollDy! - dy);
    final end = getNodeInOffset(panEndOffset)
        ?.selectable
        ?.getSelectionInRange(panStartOffset, panEndOffset)
        .end;

    Selection? newSelection;

    if (end != null) {
      if (dragMode == MobileSelectionDragMode.leftSelectionHandle) {
        newSelection = Selection(
          start: _panStartSelection!.normalized.end,
          end: end,
        ).normalized;
      } else if (dragMode == MobileSelectionDragMode.rightSelectionHandle) {
        newSelection = Selection(
          start: _panStartSelection!.normalized.start,
          end: end,
        ).normalized;
      } else if (dragMode == MobileSelectionDragMode.cursor) {
        newSelection = Selection.collapsed(end);
      }
      _lastPanOffset.value = panEndOffset;
    }

    if (newSelection != null) {
      updateSelection(newSelection);
    }

    return newSelection;
  }

  @override
  void onPanEnd(DragEndDetails details, MobileSelectionDragMode mode) {
    _clearPanVariables();
    dragMode = MobileSelectionDragMode.none;

    editorState.updateSelectionWithReason(
      editorState.selection,
      reason: SelectionUpdateReason.uiEvent,
      extraInfo: {
        selectionExtraInfoDoNotAttachTextService: false,
      },
    );
  }

  void _onTapUpIOS(TapUpDetails details) {
    final offset = details.globalPosition;

    // if the tap happens on a selection area, don't change the selection
    if (_isClickOnSelectionArea(offset)) {
      appFlowyEditorOnTapSelectionArea.add(0);
      // An already-selected image is a selection area too: a tap on it still
      // opens it full screen.
      final selectedTap = getPositionInOffset(offset);
      if (selectedTap != null &&
          !openNoteLinkAtPosition(editorState, selectedTap, offset)) {
        openImageAtPosition(editorState, selectedTap, offset);
      }
      return;
    }

    clearSelection();

    final tappedPosition = getPositionInOffset(offset);
    if (tappedPosition != null &&
        openNoteLinkAtPosition(editorState, tappedPosition, offset)) {
      return;
    }

    Selection? selection;
    if (disableIOSSelectWordEdgeOnTap) {
      final position = getPositionInOffset(offset);
      if (position != null) {
        selection = Selection.collapsed(position);
      }
    } else {
      // get the word edge closest to offset
      final node = getNodeInOffset(offset);
      selection = node?.selectable?.getWordEdgeInOffset(offset);
    }

    if (selection != null) {
      editorState.updateSelectionWithReason(
        selection,
        reason: SelectionUpdateReason.uiEvent,
        customSelectionType: SelectionType.inline,
        extraInfo: null,
      );
    }
    // PREVON PATCH 19: a tap on an image opens it full screen.
    if (tappedPosition != null) {
      openImageAtPosition(editorState, tappedPosition, offset);
    }
  }

  void _onDoubleTapUp(TapUpDetails details) {
    final offset = details.globalPosition;
    final node = getNodeInOffset(offset);
    // select word boundary closest to offset
    final selection = node?.selectable?.getWordBoundaryInOffset(offset);
    if (selection == null) {
      clearSelection();
      return;
    }
    updateSelection(selection);
  }

  void _onTripleTapUp(TapUpDetails details) {
    final offset = details.globalPosition;
    final node = getNodeInOffset(offset);
    // select node closest to offset
    final selectable = node?.selectable;
    if (selectable == null) {
      clearSelection();
      return;
    }
    final selection = tripleTapSelection(node!, selectable, offset);
    updateSelection(selection);
  }

  /// Long-press on a link run opens the remove-link menu, and on an image the
  /// image menu, instead of starting a cursor drag.
  bool _showLinkMenuAt(Offset offset) {
    final position = getPositionInOffset(offset);
    if (position == null) return false;
    return showLinkRemoveMenuAtPosition(editorState, position, offset) ||
        showImageMenuAtPosition(editorState, position, offset);
  }

  /// PREVON PATCH 19: a hold on an image lifts it (see [ImageHoldLift]).
  ImageHoldLift? _imageLift;

  /// A hold that was cancelled never reports its end: put the picture back.
  void _cancelImageLift() {
    _imageLift?.cancel();
    _imageLift = null;
  }

  bool _beginImageLift(Offset offset) {
    final position = getPositionInOffset(offset);
    if (position == null) return false;
    // A previous lift whose end never arrived (cancelled touch): put it back.
    _imageLift?.cancel();
    _imageLift = ImageHoldLift.begin(editorState, position, offset);
    return _imageLift != null;
  }

  /// Routes a long-press move / end to an active lift; true when it did.
  bool _routeImageLift(Offset? update, {bool end = false}) {
    final lift = _imageLift;
    if (lift == null) return false;
    if (end) {
      _imageLift = null;
      lift.end();
    } else if (update != null) {
      lift.update(update);
    }
    return true;
  }

  void _onLongPressStartIOS(LongPressStartDetails details) {
    final offset = details.globalPosition;
    if (_beginImageLift(offset)) return;
    if (_showLinkMenuAt(offset)) return;
    _panStartOffset = offset;
    _panStartScrollDy = editorState.service.scrollService?.dy;
    dragMode = MobileSelectionDragMode.cursor;

    // make a collapsed selection at offset with magnifier
    final position = getPositionInOffset(offset);
    if (position == null) {
      return;
    }

    final selection = Selection.collapsed(position);
    _lastPanOffset.value = offset;
    _lastAppliedOffset = offset;
    updateSelection(selection);
  }

  void _onLongPressUpdateIOS(LongPressMoveUpdateDetails details) {
    if (_routeImageLift(details.globalPosition)) return;
    if (_panStartOffset == null || _panStartScrollDy == null) {
      return;
    }

    // make a collapsed selection at offset with magnifier
    final offset = details.globalPosition;
    // The magnifier tracks the raw finger; only the caret is damped.
    _lastPanOffset.value = offset;
    final last = _lastAppliedOffset;
    if (last != null && (offset - last).distance < _kHoldJitterSlop) {
      return;
    }
    final position = getPositionInOffset(offset);
    if (position == null) {
      return;
    }
    _lastAppliedOffset = offset;

    updateSelection(Selection.collapsed(position));
  }

  void _onLongPressEndIOS(LongPressEndDetails details) {
    if (_routeImageLift(null, end: true)) return;
    _clearPanVariables();
    dragMode = MobileSelectionDragMode.none;

    editorState.updateSelectionWithReason(
      editorState.selection,
      reason: SelectionUpdateReason.uiEvent,
      customSelectionType: SelectionType.inline,
      extraInfo: {
        selectionExtraInfoDoNotAttachTextService: false,
      },
    );
  }

  void _onTapUpAndroid(TapUpDetails details) {
    final offset = details.globalPosition;

    clearSelection();

    // make a collapsed selection at offset
    final position = getPositionInOffset(offset);
    if (position == null) {
      return;
    }

    editorState.updateSelectionWithReason(
      Selection.collapsed(position),
      reason: SelectionUpdateReason.uiEvent,
      customSelectionType: SelectionType.inline,
      extraInfo: null,
    );
    if (!openNoteLinkAtPosition(editorState, position, offset)) {
      // PREVON PATCH 19: a tap on an image opens it full screen.
      openImageAtPosition(editorState, position, offset);
    }
  }

  /// PREVON PATCH 24: smooth hold-to-select. While a finger is down the word
  /// drag must not touch the keyboard (every move used to re-attach the input
  /// connection and could pop the keyboard up mid-gesture, resizing the page
  /// under the finger); the keyboard attaches once, when the finger lifts.
  static const Map<String, Object> _holdExtraInfo = {
    selectionExtraInfoDisableFloatingToolbar: true,
    selectionExtraInfoDoNotAttachTextService: true,
  };

  /// A finger that moved less than this since the last applied move is sensor
  /// noise, not intent: ignoring it stops the caret flipping between two
  /// neighbours (or two lines) while the finger rests on a boundary.
  static const double _kHoldJitterSlop = 1.5;

  /// True while a long-press word-select drag is in progress (Android).
  bool _wordDrag = false;
  Offset? _lastAppliedOffset;

  void _onLongPressStartAndroid(LongPressStartDetails details) {
    final offset = details.globalPosition;
    if (_beginImageLift(offset)) return;
    if (_showLinkMenuAt(offset)) return;
    _panStartOffset = offset;
    _panStartScrollDy = editorState.service.scrollService?.dy;
    final node = getNodeInOffset(offset);
    // select word boundary closest to offset
    final selection = node?.selectable?.getWordBoundaryInOffset(offset);
    if (selection == null) {
      clearSelection();
      return;
    }

    if (editorState.editorStyle.enableHapticFeedbackOnAndroid) {
      HapticFeedback.mediumImpact();
    }

    dragMode = MobileSelectionDragMode.cursor;
    _wordDrag = true;
    _lastAppliedOffset = offset;
    _panStartSelection = selection;
    _lastPanOffset.value = offset;

    editorState.updateSelectionWithReason(
      selection,
      reason: SelectionUpdateReason.uiEvent,
      extraInfo: _holdExtraInfo,
    );
  }

  void _onLongPressUpdateAndroid(LongPressMoveUpdateDetails details) {
    if (_routeImageLift(details.globalPosition)) return;
    if (_panStartOffset == null || _panStartScrollDy == null) {
      return;
    }
    if (editorState.selection == null ||
        dragMode == MobileSelectionDragMode.none) {
      return;
    }

    final offset = details.globalPosition;
    // The magnifier tracks the raw finger; only the selection is damped.
    _lastPanOffset.value = offset;
    final last = _lastAppliedOffset;
    if (last != null && (offset - last).distance < _kHoldJitterSlop) {
      return;
    }
    _extendWordSelectionTo(offset);
  }

  /// Extends the held word out to the word under [offset]. Also called while
  /// the page auto-scrolls under a resting finger, so the selection keeps
  /// following the finger instead of freezing (or collapsing to a caret).
  void _extendWordSelectionTo(Offset offset) {
    final anchor = _panStartSelection;
    if (anchor == null) return;
    _lastAppliedOffset = offset;

    final wordBoundary =
        getNodeInOffset(offset)?.selectable?.getWordBoundaryInOffset(offset);

    Selection? newSelection;

    // extend selection from _panStartSelection to word boundary closest to offset
    if (wordBoundary != null) {
      if (wordBoundary.end.path > _panStartSelection!.end.path ||
          wordBoundary.end.path.equals(_panStartSelection!.end.path) &&
              wordBoundary.end.offset > _panStartSelection!.end.offset) {
        newSelection = Selection(
          start: _panStartSelection!.start,
          end: wordBoundary.end,
        ).normalized;
      } else if (wordBoundary.start.path < _panStartSelection!.start.path ||
          wordBoundary.start.path.equals(_panStartSelection!.start.path) &&
              wordBoundary.start.offset < _panStartSelection!.start.offset) {
        newSelection = Selection(
          start: _panStartSelection!.end,
          end: wordBoundary.start,
        ).normalized;
      } else {
        newSelection = _panStartSelection;
      }
    }

    // Only a real change reaches the editor (and the finger): a move that
    // lands on the same word is silent.
    if (newSelection != null && newSelection != editorState.selection) {
      if (editorState.editorStyle.enableHapticFeedbackOnAndroid) {
        HapticFeedback.selectionClick();
      }
      editorState.updateSelectionWithReason(
        newSelection,
        reason: SelectionUpdateReason.uiEvent,
        extraInfo: _holdExtraInfo,
      );
    }
  }

  /// The hold was taken away (pointer cancel): no End follows, so put the
  /// gesture state back or the magnifier and drag mode stay stuck.
  void _cancelHold() {
    _cancelImageLift();
    if (dragMode == MobileSelectionDragMode.none && _panStartOffset == null) {
      return;
    }
    _clearPanVariables();
    dragMode = MobileSelectionDragMode.none;
    editorState.updateSelectionWithReason(
      editorState.selection,
      reason: SelectionUpdateReason.uiEvent,
      extraInfo: {
        selectionExtraInfoDoNotAttachTextService: false,
      },
    );
  }

  void _onLongPressEndAndroid(LongPressEndDetails details) {
    if (_routeImageLift(null, end: true)) return;
    _clearPanVariables();
    dragMode = MobileSelectionDragMode.none;

    editorState.updateSelectionWithReason(
      editorState.selection,
      reason: SelectionUpdateReason.uiEvent,
      extraInfo: {
        selectionExtraInfoDoNotAttachTextService: false,
      },
    );
  }

  void _onPanUpdateAndroid(DragUpdateDetails details) {
    // if current pan gesture is not initially horizontal, return
    if (_isPanStartHorizontal == false) {
      return;
    }
    // first call to onPanUpdate to determine if current pan gesture is horizontal
    // if not, disable future calls in the guard clause above
    if (details.delta.dx.abs() < details.delta.dy.abs() &&
        (_panStartOffset == null || _panStartScrollDy == null)) {
      _isPanStartHorizontal = false;
      return;
    }
    // first successful call to onPanUpdate, initialize pan variables
    final offset = details.globalPosition;
    if (_panStartOffset == null || _panStartScrollDy == null) {
      _panStartOffset = offset;
      _panStartScrollDy = editorState.service.scrollService?.dy;
      dragMode = MobileSelectionDragMode.cursor;
    }

    final position = getPositionInOffset(offset);

    _lastPanOffset.value = offset;
    if (position == null) {
      return;
    }

    final selection = Selection.collapsed(position);

    // PREVON PATCH 24: tick only when the caret really moves; it used to
    // buzz on every pointer event.
    if (editorState.editorStyle.enableHapticFeedbackOnAndroid &&
        selection != editorState.selection) {
      HapticFeedback.selectionClick();
    }
    updateSelection(selection);
  }

  void _onPanEndAndroid(DragEndDetails details) {
    _clearPanVariables();
    dragMode = MobileSelectionDragMode.none;
    _isPanStartHorizontal = null;

    editorState.updateSelectionWithReason(
      editorState.selection,
      reason: SelectionUpdateReason.uiEvent,
      extraInfo: {
        selectionExtraInfoDoNotAttachTextService: false,
        selectionExtraInfoDisableFloatingToolbar: true,
      },
    );
  }

  // delete this function in the future.
  void _updateSelectionAreas(Selection selection) {
    final nodes = editorState.getNodesInSelection(selection);

    currentSelectedNodes = nodes;

    final backwardNodes =
        selection.isBackward ? nodes : nodes.reversed.toList(growable: false);
    final normalizedSelection = selection.normalized;
    assert(normalizedSelection.isBackward);

    AppFlowyEditorLog.selection
        .debug('update selection areas, $normalizedSelection');

    for (var i = 0; i < backwardNodes.length; i++) {
      final node = backwardNodes[i];

      final selectable = node.selectable;
      if (selectable == null) {
        continue;
      }

      var newSelection = normalizedSelection.copyWith();

      /// In the case of multiple selections,
      ///  we need to return a new selection for each selected node individually.
      ///
      /// < > means selected.
      /// text: abcd<ef
      /// text: ghijkl
      /// text: mn>opqr
      ///
      if (!normalizedSelection.isSingle) {
        if (i == 0) {
          newSelection = newSelection.copyWith(end: selectable.end());
        } else if (i == nodes.length - 1) {
          newSelection = newSelection.copyWith(start: selectable.start());
        } else {
          newSelection = Selection(
            start: selectable.start(),
            end: selectable.end(),
          );
        }
      }

      final rects = selectable.getRectsInSelection(
        newSelection,
        shiftWithBaseOffset: true,
      );
      for (final rect in rects) {
        final selectionRect = selectable.transformRectToGlobal(
          rect,
          shiftWithBaseOffset: true,
        );
        _selectionRects.add(selectionRect);
      }
    }
  }

  bool _isClickOnSelectionArea(Offset point) {
    for (final rect in _selectionRects) {
      if (rect.contains(point)) {
        return true;
      }
    }
    return false;
  }

  // PREVON PATCH 14: mobile used to stub all three drop-target methods
  // ("Do nothing on mobile" / `getDropTargetRenderData => null`), so a block
  // drag-to-reorder (checklist grip, generic block grip) could never resolve
  // a drop position on a phone: the grip dragged, showed its floating chip,
  // and then nothing moved. Same implementation as the desktop service.
  AppFlowyDropTargetStyle get _dropTargetStyle => widget.dropTargetStyle;
  fw.OverlayEntry? _dropTargetEntry;

  @override
  void removeDropTarget() {
    _dropTargetEntry?.remove();
    _dropTargetEntry = null;
  }

  @override
  void renderDropTargetForOffset(
    Offset offset, {
    DragAreaBuilder? builder,
    DragTargetNodeInterceptor? interceptor,
  }) {
    removeDropTarget();

    Node? node = getNodeInOffset(offset);
    if (node == null) {
      return;
    }

    if (interceptor != null) {
      node = interceptor(context, node);
    }

    final selectable = node.selectable;
    if (selectable == null) {
      return;
    }

    final blockRect = selectable.getBlockRect();
    final startOffset = blockRect.topLeft;
    final endOffset = blockRect.bottomLeft;

    final renderBox = selectable.context.findRenderObject() as RenderBox;
    final globalStartOffset = renderBox.localToGlobal(startOffset);
    final globalEndOffset = renderBox.localToGlobal(endOffset);

    final topDistance = (globalStartOffset - offset).distanceSquared;
    final bottomDistance = (globalEndOffset - offset).distanceSquared;

    final isCloserToStart = topDistance < bottomDistance;

    _dropTargetEntry = fw.OverlayEntry(
      builder: (context) {
        if (builder != null && node != null) {
          return builder(
            context,
            DragAreaBuilderData(
              targetNode: node,
              dragOffset: offset,
            ),
          );
        }

        final overlayRenderBox =
            fw.Overlay.of(context).context.findRenderObject() as RenderBox;
        final editorRenderBox =
            selectable.context.findRenderObject() as RenderBox;

        final editorOffset = editorRenderBox.localToGlobal(
          Offset.zero,
          ancestor: overlayRenderBox,
        );

        final indicatorTop =
            (isCloserToStart ? startOffset.dy : endOffset.dy) + editorOffset.dy;

        final width = blockRect.topRight.dx - startOffset.dx;
        return Positioned(
          top: indicatorTop,
          left: startOffset.dx + editorOffset.dx,
          child: Container(
            height: _dropTargetStyle.height,
            width: width,
            margin: _dropTargetStyle.margin,
            constraints: _dropTargetStyle.constraints,
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(_dropTargetStyle.borderRadius),
              color: _dropTargetStyle.color ??
                  Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );

    fw.Overlay.of(context).insert(_dropTargetEntry!);
  }

  @override
  DropTargetRenderData? getDropTargetRenderData(
    Offset offset, {
    DragTargetNodeInterceptor? interceptor,
  }) {
    Node? node = getNodeInOffset(offset);

    if (node == null) {
      return null;
    }

    if (interceptor != null) {
      node = interceptor(context, node);
    }

    final selectable = node.selectable;
    if (selectable == null) {
      return null;
    }

    final blockRect = selectable.getBlockRect();
    final startRect = blockRect.topLeft;
    final endRect = blockRect.bottomLeft;

    final renderBox = selectable.context.findRenderObject() as RenderBox;
    final globalStartRect = renderBox.localToGlobal(startRect);
    final globalEndRect = renderBox.localToGlobal(endRect);

    final topDistance = (globalStartRect - offset).distanceSquared;
    final bottomDistance = (globalEndRect - offset).distanceSquared;

    final isCloserToStart = topDistance < bottomDistance;

    final dropPath = isCloserToStart ? node.path : node.path.next;

    return DropTargetRenderData(
      dropPath: dropPath,
      cursorNode: node,
    );
  }
}
