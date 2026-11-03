import 'dart:math';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/selection/mobile_selection_service.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

GlobalKey _leftHandleKey = GlobalKey();
GlobalKey _rightHandleKey = GlobalKey();
GlobalKey _collapsedHandleKey = GlobalKey();

enum HandleType {
  none,
  left,
  right,
  collapsed;

  MobileSelectionDragMode get dragMode {
    switch (this) {
      case HandleType.none:
        throw UnsupportedError('Unsupported handle type');
      case HandleType.left:
        return MobileSelectionDragMode.leftSelectionHandle;
      case HandleType.right:
        return MobileSelectionDragMode.rightSelectionHandle;
      case HandleType.collapsed:
        return MobileSelectionDragMode.cursor;
    }
  }

  CrossAxisAlignment get crossAxisAlignment {
    switch (this) {
      case HandleType.none:
        throw UnsupportedError('Unsupported handle type');
      case HandleType.left:
        return CrossAxisAlignment.end;
      case HandleType.right:
        return CrossAxisAlignment.start;
      case HandleType.collapsed:
        return CrossAxisAlignment.center;
    }
  }

  GlobalKey get key {
    switch (this) {
      case HandleType.none:
        throw UnsupportedError('Unsupported handle type');
      case HandleType.left:
        return _leftHandleKey;
      case HandleType.right:
        return _rightHandleKey;
      case HandleType.collapsed:
        return _collapsedHandleKey;
    }
  }
}

/// PREVON PATCH 32: a pan recognizer that wins the gesture arena the moment a finger lands on it.
///
/// A selection handle sits inside the document, which sits inside whatever scrolls (the note's own list, a Home
/// page) or pages (the Scratchpad's tabs). A plain [PanGestureRecognizer] waits for 36 px of travel while a
/// vertical scroll takes the pointer at 18 px, so a slide that drifted a little up or down was lost to the page
/// and the handle never moved. The handle is a small target the finger chose on purpose, so there is nothing
/// to wait for: it takes the pointer on touch-down and every drag that starts on it is the handle's. Drags that
/// start anywhere else are untouched (the page still scrolls and swipes).
class EagerPanGestureRecognizer extends PanGestureRecognizer {
  EagerPanGestureRecognizer({super.debugOwner, super.supportedDevices});

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// Drop-in for the handles' `GestureDetector(onPan...)`, built on [EagerPanGestureRecognizer].
class HandleDragDetector extends StatelessWidget {
  const HandleDragDetector({
    super.key,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.child,
  });

  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        EagerPanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerPanGestureRecognizer>(
          () => EagerPanGestureRecognizer(),
          (recognizer) {
            recognizer
              ..dragStartBehavior = DragStartBehavior.down
              ..onStart = onPanStart
              ..onUpdate = onPanUpdate
              ..onEnd = onPanEnd;
          },
        ),
      },
      child: child,
    );
  }
}

abstract class _IDragHandle extends StatelessWidget {
  const _IDragHandle({
    super.key,
    required this.handleHeight,
    this.handleColor = Colors.black,
    this.handleWidth = 2.0,
    this.handleBallWidth = 6.0,
    this.debugPaintSizeEnabled = false,
    this.onDragging,
    required this.handleType,
  });

  final Color handleColor;
  final double handleWidth;
  final double handleHeight;
  final double handleBallWidth;
  final HandleType handleType;
  final bool debugPaintSizeEnabled;
  final ValueChanged<bool>? onDragging;
}

class DragHandle extends _IDragHandle {
  const DragHandle({
    super.key,
    required super.handleHeight,
    super.handleColor,
    super.handleWidth,
    super.handleBallWidth,
    required super.handleType,
    super.debugPaintSizeEnabled,
    super.onDragging,
  });

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (PlatformExtension.isIOS) {
      child = _IOSDragHandle(
        handleHeight: handleHeight,
        handleColor: handleColor,
        handleWidth: handleWidth,
        handleBallWidth: handleBallWidth,
        handleType: handleType,
        debugPaintSizeEnabled: debugPaintSizeEnabled,
        onDragging: onDragging,
      );
    } else if (PlatformExtension.isAndroid) {
      child = _AndroidDragHandle(
        handleHeight: handleHeight,
        handleColor: handleColor,
        handleWidth: handleWidth,
        handleBallWidth: handleBallWidth,
        handleType: handleType,
        debugPaintSizeEnabled: debugPaintSizeEnabled,
        onDragging: onDragging,
      );
    } else {
      throw UnsupportedError('Unsupported platform');
    }

    if (debugPaintSizeEnabled) {
      child = ColoredBox(
        color: Colors.red.withValues(alpha: 0.5),
        child: child,
      );
    }

    if (handleType != HandleType.none && handleType != HandleType.collapsed) {
      final offset = PlatformExtension.isIOS ? -handleWidth : 0.0;
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          if (handleType == HandleType.left)
            Positioned(
              left: offset,
              child: child,
            ),
          if (handleType == HandleType.right)
            Positioned(
              right: offset,
              child: child,
            ),
        ],
      );
    }

    return child;
  }
}

class _IOSDragHandle extends _IDragHandle {
  const _IOSDragHandle({
    required super.handleHeight,
    super.handleColor,
    super.handleWidth,
    super.handleBallWidth,
    required super.handleType,
    super.debugPaintSizeEnabled,
    super.onDragging,
  });

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (handleType == HandleType.collapsed) {
      child = Container(
        key: handleType.key,
        width: handleWidth,
        color: handleColor,
        height: handleHeight,
      );
    } else {
      child = Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          if (handleType == HandleType.left)
            Container(
              width: handleBallWidth,
              height: handleBallWidth,
              decoration: BoxDecoration(
                color: handleColor,
                shape: BoxShape.circle,
              ),
            ),
          if (handleType == HandleType.right)
            SizedBox(
              width: handleBallWidth,
              height: handleBallWidth,
            ),
          Container(
            width: handleWidth,
            color: handleColor,
            height: handleHeight - 2.0 * handleBallWidth,
          ),
          if (handleType == HandleType.right)
            Container(
              width: handleBallWidth,
              height: handleBallWidth,
              decoration: BoxDecoration(
                color: handleColor,
                shape: BoxShape.circle,
              ),
            ),
          if (handleType == HandleType.left)
            SizedBox(
              width: handleBallWidth,
              height: handleBallWidth,
            ),
        ],
      );
    }

    final editorState = context.read<EditorState>();
    final ballWidth = handleBallWidth;
    double offset = 0.0;
    if (handleType == HandleType.left) {
      offset = ballWidth;
    } else if (handleType == HandleType.right) {
      offset = -ballWidth;
    }

    child = HandleDragDetector(
      onPanStart: (details) {
        editorState.service.selectionService.onPanStart(
          details.translate(0, offset),
          handleType.dragMode,
        );
        onDragging?.call(true);
      },
      onPanUpdate: (details) {
        editorState.service.selectionService.onPanUpdate(
          details.translate(0, offset),
          handleType.dragMode,
        );
        onDragging?.call(true);
      },
      onPanEnd: (details) {
        editorState.service.selectionService.onPanEnd(
          details,
          handleType.dragMode,
        );
        onDragging?.call(false);
      },
      child: child,
    );

    return child;
  }
}

// ignore: must_be_immutable
class _AndroidDragHandle extends _IDragHandle {
  _AndroidDragHandle({
    required super.handleHeight,
    super.handleColor,
    super.handleWidth,
    super.handleBallWidth,
    required super.handleType,
    super.debugPaintSizeEnabled,
    super.onDragging,
  });

  Selection? selection;

  @override
  Widget build(BuildContext context) {
    final editorState = context.read<EditorState>();
    Widget child = SizedBox(
      width: handleWidth,
      height: handleHeight - 2.0 * handleBallWidth,
    );

    if (handleType == HandleType.none) {
      return child;
    }

    final ballWidth = handleBallWidth * 2.0;

    child = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: handleType.crossAxisAlignment,
      children: [
        child,
        if (handleType == HandleType.collapsed)
          Transform.rotate(
            angle: pi / 4.0,
            child: Container(
              width: ballWidth,
              height: ballWidth,
              // Outline only: a hollow drop, so the text under it stays visible.
              decoration: BoxDecoration(
                border: Border.all(color: handleColor, width: 1.5),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(handleBallWidth),
                  bottomLeft: Radius.circular(handleBallWidth),
                  bottomRight: Radius.circular(handleBallWidth),
                ),
              ),
            ),
          ),
        if (handleType == HandleType.left)
          Container(
            width: ballWidth,
            height: ballWidth,
            decoration: BoxDecoration(
              color: handleColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(handleBallWidth),
                bottomLeft: Radius.circular(handleBallWidth),
                bottomRight: Radius.circular(handleBallWidth),
              ),
            ),
          ),
        if (handleType == HandleType.right)
          Container(
            width: ballWidth,
            height: ballWidth,
            decoration: BoxDecoration(
              color: handleColor,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(handleBallWidth),
                bottomLeft: Radius.circular(handleBallWidth),
                bottomRight: Radius.circular(handleBallWidth),
              ),
            ),
          ),
      ],
    );

    child = HandleDragDetector(
      onPanStart: (details) {
        selection = editorState.service.selectionService.onPanStart(
          details.translate(0, -ballWidth),
          handleType.dragMode,
        );
        onDragging?.call(true);
      },
      onPanUpdate: (details) {
        final selection = editorState.service.selectionService.onPanUpdate(
          details.translate(0, -ballWidth),
          handleType.dragMode,
        );
        if (this.selection != selection) {
          HapticFeedback.selectionClick();
        }
        this.selection = selection;
        onDragging?.call(true);
      },
      onPanEnd: (details) {
        editorState.service.selectionService.onPanEnd(
          details,
          handleType.dragMode,
        );
        onDragging?.call(false);
      },
      child: child,
    );

    return child;
  }
}

extension on DragStartDetails {
  DragStartDetails translate(double dx, double dy) {
    return DragStartDetails(
      sourceTimeStamp: sourceTimeStamp,
      globalPosition: Offset(globalPosition.dx + dx, globalPosition.dy + dy),
      localPosition: Offset(localPosition.dx + dx, localPosition.dy + dy),
    );
  }
}

extension on DragUpdateDetails {
  DragUpdateDetails translate(double dx, double dy) {
    return DragUpdateDetails(
      sourceTimeStamp: sourceTimeStamp,
      globalPosition: Offset(globalPosition.dx + dx, globalPosition.dy + dy),
      localPosition: Offset(localPosition.dx + dx, localPosition.dy + dy),
      delta: Offset(delta.dx + dx, delta.dy + dy),
      primaryDelta: primaryDelta,
    );
  }
}
