import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/renderer/block_component_action.dart';
import 'package:flutter/material.dart';

typedef BlockComponentActionBuilder = Widget Function(
  BuildContext context,
  BlockComponentActionState state,
);

typedef BlockComponentActionTrailingBuilder = Widget Function(
  BuildContext context,
  BlockComponentActionState state,
);

class BlockComponentActionWrapper extends StatefulWidget {
  const BlockComponentActionWrapper({
    super.key,
    required this.node,
    required this.child,
    required this.actionBuilder,
    this.actionTrailingBuilder,
  });

  final Node node;
  final Widget child;
  final BlockComponentActionBuilder actionBuilder;
  final BlockComponentActionTrailingBuilder? actionTrailingBuilder;

  @override
  State<BlockComponentActionWrapper> createState() =>
      _BlockComponentActionWrapperState();
}

class _BlockComponentActionWrapperState
    extends State<BlockComponentActionWrapper>
    implements BlockComponentActionState {
  final showActionsNotifier = ValueNotifier<bool>(false);

  bool isDisposed = false;

  /// PATCH 14: on touch (and `forceShowBlockAction`) the gutter is persistent —
  /// there is no hover to bring it back. A drag ending used to set
  /// `alwaysShowActions = false`, which hid the grip for good after the first
  /// reorder.
  bool get _persistent =>
      forceShowBlockAction || blockHoverActionsTouchEnabled();

  bool _alwaysShowActions = false;
  bool get alwaysShowActions => _alwaysShowActions;
  @override
  set alwaysShowActions(bool alwaysShowActions) {
    if (isDisposed) {
      return;
    }
    _alwaysShowActions = alwaysShowActions || _persistent;
    if (_alwaysShowActions == false && showActionsNotifier.value == true) {
      showActionsNotifier.value = false;
    }
  }

  @override
  void initState() {
    super.initState();

    // Touch has no hover to reveal the action container with, so it stays
    // shown persistently instead — matching `BlockHoverActionHandle`'s own
    // touch posture (see `blockHoverActionsTouchEnabled`).
    if (forceShowBlockAction || blockHoverActionsTouchEnabled()) {
      alwaysShowActions = true;
      showActionsNotifier.value = true;
    }
  }

  @override
  void dispose() {
    isDisposed = true;
    showActionsNotifier.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (blockHoverActionsTouchEnabled()) {
      // Touch: no gutter. The (invisible) grip overlays the row's leading
      // bullet / checkbox so the content sits as far left as it can, and a
      // fingertip that lands near the marker still grabs the row.
      return ReorderDimmed(
        node: widget.node,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned(
              left: 0,
              top: kTouchBlockTopPadding - 2,
              width: kTouchOverlayWidth,
              height: kTouchOverlayHeight,
              child: widget.actionBuilder(context, this),
            ),
          ],
        ),
      );
    }
    return ReorderDimmed(
      node: widget.node,
      child: MouseRegion(
        onEnter: (_) => showActionsNotifier.value = true,
        onExit: (_) => showActionsNotifier.value = alwaysShowActions || false,
        hitTestBehavior: HitTestBehavior.opaque,
        opaque: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: showActionsNotifier,
              builder: (context, value, child) => BlockComponentActionContainer(
                node: widget.node,
                showActions: value,
                actionBuilder: (context) => widget.actionBuilder(context, this),
              ),
            ),
            if (widget.actionTrailingBuilder != null)
              widget.actionTrailingBuilder!(
                context,
                this,
              ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}
