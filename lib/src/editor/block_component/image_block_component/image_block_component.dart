import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ImageBlockKeys {
  const ImageBlockKeys._();

  static const String type = 'image';

  /// The align data of a image block.
  ///
  /// The value is a String.
  /// left, center, right
  static const String align = 'align';

  /// The image src of a image block.
  ///
  /// The value is a String.
  /// It can be a url or a base64 string(web).
  static const String url = 'url';

  /// The height of a image block.
  ///
  /// The value is a double.
  static const String width = 'width';

  /// The width of a image block.
  ///
  /// The value is a double.
  static const String height = 'height';
}

Node imageNode({
  required String url,
  String align = 'center',
  double? height,
  double? width,
}) {
  return Node(
    type: ImageBlockKeys.type,
    attributes: {
      ImageBlockKeys.url: url,
      ImageBlockKeys.align: align,
      ImageBlockKeys.height: height,
      ImageBlockKeys.width: width,
    },
  );
}

typedef ImageBlockComponentMenuBuilder = Widget Function(
  Node node,
  ImageBlockComponentWidgetState state,
);

class ImageBlockComponentBuilder extends BlockComponentBuilder {
  ImageBlockComponentBuilder({
    super.configuration,
    this.showMenu = false,
    this.menuBuilder,
  });

  /// Whether to show the menu of this block component.
  final bool showMenu;

  ///
  final ImageBlockComponentMenuBuilder? menuBuilder;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return ImageBlockComponentWidget(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
      showMenu: showMenu,
      menuBuilder: menuBuilder,
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.delta == null && node.children.isEmpty;
}

class ImageBlockComponentWidget extends BlockComponentStatefulWidget {
  const ImageBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.showMenu = false,
    this.menuBuilder,
  });

  /// Whether to show the menu of this block component.
  final bool showMenu;

  final ImageBlockComponentMenuBuilder? menuBuilder;

  @override
  State<ImageBlockComponentWidget> createState() =>
      ImageBlockComponentWidgetState();
}

class ImageBlockComponentWidgetState extends State<ImageBlockComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final imageKey = GlobalKey();

  /// The picture itself: lets the selection layer ask where it is painted and
  /// what to open full screen.
  final resizableKey = GlobalKey<ResizableImageState>();
  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  late final editorState = Provider.of<EditorState>(context, listen: false);

  final showActionsNotifier = ValueNotifier<bool>(false);

  bool alwaysShowMenu = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final attributes = node.attributes;
    final src = attributes[ImageBlockKeys.url];

    final alignment = AlignmentExtension.fromString(
      attributes[ImageBlockKeys.align] ?? 'center',
    );
    final width = attributes[ImageBlockKeys.width]?.toDouble() ??
        MediaQuery.of(context).size.width;
    final height = attributes[ImageBlockKeys.height]?.toDouble();

    // Grips show while this block alone is the selection (a tap or hold on
    // it); a select-all must not light up every image on the page.
    Widget child = ValueListenableBuilder<Selection?>(
      valueListenable: editorState.selectionNotifier,
      builder: (context, selection, _) => ResizableImage(
        key: resizableKey,
        src: src,
        width: width,
        height: height,
        editable: editorState.editable,
        selected: _isOnlySelected(selection),
        alignment: alignment,
        onResize: (width) {
          // Dragged to the full page width means "fill the page", which keeps
          // following the window when it changes (rotation, desktop resize).
          final available = availableWidth;
          final fill = available > 0 && width >= available - 0.5;
          setImageWidth(editorState, node, fill ? null : width.roundToDouble());
        },
      ),
    );

    child = Padding(
      key: imageKey,
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

    if (widget.showMenu && widget.menuBuilder != null) {
      child = MouseRegion(
        onEnter: (_) => showActionsNotifier.value = true,
        onExit: (_) {
          if (!alwaysShowMenu) {
            showActionsNotifier.value = false;
          }
        },
        hitTestBehavior: HitTestBehavior.opaque,
        opaque: false,
        child: ValueListenableBuilder<bool>(
          valueListenable: showActionsNotifier,
          builder: (context, value, child) {
            return Stack(
              children: [
                BlockSelectionContainer(
                  node: node,
                  delegate: this,
                  listenable: editorState.selectionNotifier,
                  remoteSelection: editorState.remoteSelections,
                  cursorColor: editorState.editorStyle.cursorColor,
                  selectionColor: editorState.editorStyle.selectionColor,
                  child: child!,
                ),
                if (value) widget.menuBuilder!(widget.node, this),
              ],
            );
          },
          child: child,
        ),
      );
    }

    return child;
  }

  bool _isOnlySelected(Selection? selection) =>
      selection != null &&
      selection.start.path.equals(node.path) &&
      selection.end.path.equals(node.path);

  /// The page width this image can fill, in dp (0 before the first layout).
  double get availableWidth => resizableKey.currentState?.availableWidth ?? 0;

  /// Where the picture is painted, in global coordinates, or null when it is
  /// not laid out. A tap or hold counts as "on the image" only inside this.
  Rect? get imageGlobalRect => resizableKey.currentState?.globalRect;

  /// What to open full screen for this block, or null when there is nothing to
  /// show (a remote image the user has not let load).
  ImageProvider? get viewerProvider =>
      resizableKey.currentState?.viewerProvider;

  bool _hasScanner() {
    try {
      context.read<ImageTextScanner>();
      return true;
    } on ProviderNotFoundException {
      return false;
    }
  }

  /// The current look of the image, for the hold menu.
  ImageMenuRequest menuRequest() {
    final state = resizableKey.currentState;
    final available = availableWidth;
    final width = state?.currentWidth ?? available;
    final parent = widget.node.parent;
    final index = widget.node.path.last;
    return ImageMenuRequest(
      editable: editorState.editable,
      align:
          (widget.node.attributes[ImageBlockKeys.align] as String?) ?? 'center',
      size: widget.node.attributes[ImageBlockKeys.width] == null
          ? ImageSizePreset.full
          : ImageSizePreset.match(width, available),
      canMoveUp: index > 0,
      canMoveDown: parent != null && index < parent.children.length - 1,
      canOpen: viewerProvider != null,
      canScanText: _hasScanner(),
    );
  }

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({
    bool shiftWithBaseOffset = false,
  }) {
    final imageBox = imageKey.currentContext?.findRenderObject();
    if (imageBox is RenderBox) {
      return Offset.zero & imageBox.size;
    }
    return Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) {
      return null;
    }
    final size = _renderBox!.size;
    return Rect.fromLTWH(-size.width / 2.0, 0, size.width, size.height);
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) {
      return [];
    }
    final parentBox = context.findRenderObject();
    final imageBox = imageKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && imageBox is RenderBox) {
      return [
        imageBox.localToGlobal(Offset.zero, ancestor: parentBox) &
            imageBox.size,
      ];
    }
    return [Offset.zero & _renderBox!.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      _renderBox!.localToGlobal(offset);
}

extension AlignmentExtension on Alignment {
  static Alignment fromString(String name) {
    switch (name) {
      case 'left':
        return Alignment.centerLeft;
      case 'right':
        return Alignment.centerRight;
      default:
        return Alignment.center;
    }
  }
}
