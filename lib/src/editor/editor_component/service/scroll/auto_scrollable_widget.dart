import 'package:prevon_quilltext_engine/src/editor/editor_component/service/scroll/auto_scroller.dart';
import 'package:prevon_quilltext_engine/src/editor_state.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _selectionDragModeKey = 'selection_drag_mode';

class AutoScrollableWidget extends StatefulWidget {
  const AutoScrollableWidget({
    super.key,
    this.shrinkWrap = false,
    required this.scrollController,
    required this.builder,
  });

  final bool shrinkWrap;
  final ScrollController scrollController;
  final Widget Function(
    BuildContext context,
    AutoScroller autoScroller,
  ) builder;

  @override
  State<AutoScrollableWidget> createState() => _AutoScrollableWidgetState();
}

class _AutoScrollableWidgetState extends State<AutoScrollableWidget> {
  late AutoScroller _autoScroller;
  late ScrollableState _scrollableState;

  @override
  void dispose() {
    // ignore: invalid_use_of_protected_member
    _scrollableState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget builder(context) {
      return widget.builder(context, _autoScroller);
    }

    _scrollableState = ScrollableState();
    _initAutoScroller();

    if (widget.shrinkWrap) {
      return widget.builder(context, _autoScroller);
    } else {
      return Builder(
        builder: builder,
      );
    }
  }

  void _initAutoScroller() {
    final bool isDesktopOrWeb = PlatformExtension.isDesktopOrWeb;
    _autoScroller = AutoScroller(
      _scrollableState,
      // Desktop (see `desktopAutoScroll*` in auto_scroller.dart): one step per frame, speed eased along a
      // curve from the edge band to past the window edge. Phones keep their own tuned values.
      velocityScalar: isDesktopOrWeb ? 1 : 0.02,
      minimumAutoScrollDelta: isDesktopOrWeb ? kDesktopAutoScrollMinStep : 0.004,
      maxAutoScrollDelta: isDesktopOrWeb ? kDesktopAutoScrollMaxStep : 0.053,
      overDragMax: isDesktopOrWeb ? kDesktopAutoScrollOverDrag : 20,
      frameLocked: isDesktopOrWeb,
      rampExponent: kDesktopAutoScrollExponent,
      onScrollViewScrolled: () {
        if (!isDesktopOrWeb) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final editorState = context.read<EditorState?>();
              final dynamic dragMode =
                  editorState?.selectionExtraInfo?[_selectionDragModeKey];
              final bool isDraggingSelection = dragMode != null &&
                  dragMode.toString() != 'MobileSelectionDragMode.none';
              if (!isDraggingSelection) {
                return;
              }
              _autoScroller.continueToAutoScroll();
            }
          });
        }
      },
    );
  }
}
