import 'dart:math';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';
import 'package:prevon_quilltext_engine/src/flutter/overlay.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart' hide Overlay, OverlayEntry;
import 'package:provider/provider.dart';

// workaround for the issue:
// the popover will grab the focus even if it's inside the editor
// setup a global value to indicate whether the focus should be grabbed
// increase the value when the popover is opened
// decrease the value when the popover is closed
// only grab the focus when the value is 0
// the operation must be paired
KeepEditorFocusNotifier keepEditorFocusNotifier = KeepEditorFocusNotifier();

/// The default value of the auto scroll edge offset on mobile
/// The editor will scroll when the cursor is close to the edge of the screen
const double appFlowyEditorAutoScrollEdgeOffset = 220.0;

/// PREVON PATCH — debug-only instrumentation for the service-graph cache.
///
/// Incremented every time [_AppFlowyEditorState._buildServices] actually runs.
/// A debug build that reuses the cached service subtree does NOT advance it.
/// Tests use it to prove a no-op rebuild (one where [AppFlowyEditor
/// .serviceConfigKey] did not change) does not rebuild the service graph.
///
/// Guarded by [kDebugMode], so release/profile builds tree-shake the
/// increment and this is a no-op in production. Mirrors the existing
/// `kDebugMode`-gated instrumentation convention in this fork.
@visibleForTesting
int debugAppFlowyEditorServiceBuildCount = 0;

class AppFlowyEditor extends StatefulWidget {
  AppFlowyEditor({
    super.key,
    required this.editorState,
    Map<String, BlockComponentBuilder>? blockComponentBuilders,
    List<CharacterShortcutEvent>? characterShortcutEvents,
    List<CommandShortcutEvent>? commandShortcutEvents,
    this.contextMenuBuilder,
    this.contentInsertionConfiguration,
    this.editable = true,
    this.autoFocus = false,
    this.focusedSelection,
    this.shrinkWrap = false,
    this.showMagnifier = true,
    this.editorScrollController,
    this.mobileFloatingToolbarBuilder,
    this.editorStyle = const EditorStyle.desktop(),
    this.header,
    this.footer,
    this.focusNode,
    this.enableAutoComplete = false,
    this.autoCompleteTextProvider,
    this.dropTargetStyle,
    this.disableSelectionService = false,
    this.disableKeyboardService = false,
    this.disableScrollService = false,
    this.disableAutoScroll = false,
    this.autoScrollEdgeOffset = appFlowyEditorAutoScrollEdgeOffset,
    this.documentRules = const [],
    this.blockWrapper,
    this.serviceConfigKey,
  })  : blockComponentBuilders =
            blockComponentBuilders ?? standardBlockComponentBuilderMap,
        characterShortcutEvents =
            characterShortcutEvents ?? standardCharacterShortcutEvents,
        commandShortcutEvents =
            commandShortcutEvents ?? standardCommandShortcutEvents;

  final EditorState editorState;

  final EditorStyle editorStyle;

  /// Block component builders
  ///
  /// Pass the [standardBlockComponentBuilderMap] as well
  ///   if you simply want to extend it with a new one.
  ///
  /// For example, if you want to add a new block component:
  ///
  /// ```dart
  /// AppFlowyEditor(
  ///   blockComponentBuilders: {
  ///     ...standardBlockComponentBuilderMap,
  ///     'my_block_component': MyBlockComponentBuilder(),
  ///   },
  /// );
  /// ```
  ///
  /// Also, you can override the standard block component:
  ///
  /// ```dart
  /// AppFlowyEditor(
  ///   blockComponentBuilders: {
  ///     ...standardBlockComponentBuilderMap,
  ///     'paragraph': MyParagraphBlockComponentBuilder(),
  ///   },
  /// );
  /// ```
  final Map<String, BlockComponentBuilder> blockComponentBuilders;

  /// Character event handlers
  ///
  /// Pass the [standardCharacterShortcutEvents] as well
  ///   if you simply want to extend it with a new one.
  ///
  /// For example, if you want to add a new character shortcut event:
  ///
  /// ```dart
  /// AppFlowyEditor(
  ///  characterShortcutEvents: [
  ///   ...standardCharacterShortcutEvents,
  ///   [YOUR_SHORTCUT_EVENT],
  ///  ],
  /// );
  /// ```
  final List<CharacterShortcutEvent> characterShortcutEvents;

  /// Command event handlers
  ///
  /// Pass the [standardCommandShortcutEvents] as well
  ///   if you simply want to extend it with a new one.
  ///
  /// For example, if you want to add a new command shortcut event:
  ///
  /// ```dart
  /// AppFlowyEditor(
  ///   commandShortcutEvents: [
  ///     ...standardCommandShortcutEvents,
  ///     [YOUR_SHORTCUT_EVENT],
  ///   ],
  /// );
  /// ```
  final List<CommandShortcutEvent> commandShortcutEvents;

  /// The context menu builder.
  ///
  /// It will be shown when the user right click on the editor.
  ///
  /// See the built-in [ContextMenu] implementation.
  ///
  final ContextMenuWidgetBuilder? contextMenuBuilder;

  /// Provide a editorScrollController to control the scroll behavior
  ///
  /// Notes: the shrinkWrap will affect the layout behavior of the editor.
  /// Be carefully to set it as true, it will perform poorly.
  ///
  /// shrinkWrap == true: will use SingleChildView + Column to layout the editor.
  /// shrinkWrap == false: will use ListView to layout the editor.
  final EditorScrollController? editorScrollController;

  /// Builds the floating cut/copy/paste toolbar shown on iOS/Android when text
  /// is selected. Ignored on desktop. When null, no toolbar is shown.
  final Widget Function(
    BuildContext context,
    Offset anchor,
    VoidCallback closeToolbar,
  )? mobileFloatingToolbarBuilder;

  /// Set the value to false to disable editing.
  ///
  /// If it's false, the transaction will be ignored in the apply function, and
  ///   you can still use keyboard shortcuts to navigate the editor or select the text.
  ///
  /// If you want to disable the keyboard service, you can set [disableKeyboardService] to true.
  /// If you want to disable the selection service, you can set [disableSelectionService] to true.
  /// If you want to disable the scroll service, you can set [disableScrollService] to true.
  final bool editable;

  /// Set the value to true to focus the editor on the start of the document.
  final bool autoFocus;

  /// Set the value to focus the editor on the specified selection.
  ///
  /// only works when [autoFocus] is true.
  final Selection? focusedSelection;

  final FocusNode? focusNode;

  /// AppFlowy Editor use column as the root widget.
  ///
  /// You can provide a header and/or a footer to the editor.
  final Widget? header;
  final Widget? footer;

  /// if true, the editor will be sized to its contents.
  ///
  /// You should wrap the editor with a sized widget if you set this value to true.
  ///
  /// Notes: Must provide a scrollController when shrinkWrap is true.
  final bool shrinkWrap;

  /// Show the magnifier or not.
  ///
  /// only works on iOS or Android.
  final bool showMagnifier;

  /// If you want to enable the auto complete feature, you must set this value to true
  ///   and provide the [autoCompleteTextProvider].
  final bool enableAutoComplete;

  final AppFlowyAutoCompleteTextProvider? autoCompleteTextProvider;

  /// {@macro flutter.widgets.editableText.contentInsertionConfiguration}
  final ContentInsertionConfiguration? contentInsertionConfiguration;

  /// The style of the drop target.
  ///
  /// Defaults to [AppFlowyDropTargetStyle].
  ///
  /// The drop target is rendered in the [AppFlowyEditor] using the [DesktopSelectionService]
  /// specifically the [renderDropTargetForOffset] method.
  ///
  /// The drop target is a horizontal line that is drawn between the nearest nodes to the [offset].
  ///
  /// Should call [removeDropTarget] to remove the line once the drop action is done.
  ///
  /// only works on desktop.
  ///
  final AppFlowyDropTargetStyle? dropTargetStyle;

  /// Disable the selection gesture
  ///
  /// It will disable the selection service and the context menu.
  final bool disableSelectionService;

  /// Disable the keyboard service
  ///
  /// It will disable all the keyboard shortcuts and the text input.
  final bool disableKeyboardService;

  /// Disable the scroll service
  ///
  /// It will disable the auto scroll feature.
  final bool disableScrollService;

  /// Disable auto scroll
  ///
  final bool disableAutoScroll;

  /// The edge offset of the auto scroll.
  ///
  final double autoScrollEdgeOffset;

  /// The rules to apply to the document.
  ///
  final List<DocumentRule> documentRules;

  /// Block wrapper
  ///
  /// Wrap the block component with a widget.
  final BlockComponentWrapper? blockWrapper;

  /// PREVON PATCH — opt-in invalidation token for the cached service graph.
  ///
  /// The editor caches its internal service-widget subtree in
  /// [_AppFlowyEditorState.services] (built once by `_buildServices` and only
  /// reused on subsequent builds). A widget rebuild that does not actually
  /// change anything the service graph renders should NOT throw that cache
  /// away — but the upstream `didUpdateWidget` unconditionally nulls it, so
  /// every rebuild (word-count ticks, focus changes, unrelated ancestor
  /// `setState`s, …) rebuilds the whole service subtree.
  ///
  /// When non-null, this key is treated as an identity token: the cached
  /// service graph is invalidated only when its identity changes between
  /// builds (in addition to the existing editorState-identity invalidation,
  /// which is always honoured). Callers should pass a value whose identity
  /// changes if and only if one of the props baked into the rendered service
  /// graph changes.
  ///
  /// When null (the default), the legacy behaviour is preserved: the service
  /// graph is rebuilt on every `didUpdateWidget`. This keeps the fork's
  /// behaviour unchanged for any caller that has not opted in.
  final Object? serviceConfigKey;

  @override
  State<AppFlowyEditor> createState() => _AppFlowyEditorState();
}

class _AppFlowyEditorState extends State<AppFlowyEditor> {
  Widget? services;

  EditorState get editorState => widget.editorState;

  late EditorScrollController editorScrollController;

  @override
  void initState() {
    super.initState();

    editorScrollController = widget.editorScrollController ??
        EditorScrollController(
          editorState: editorState,
          shrinkWrap: widget.shrinkWrap,
        );

    _updateValues();
    editorState.renderer = _renderer;

    // auto focus
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _autoFocusIfNeeded();
    });
  }

  @override
  void dispose() {
    // dispose the scroll controller if it's created by the editor
    if (widget.editorScrollController == null) {
      editorScrollController.dispose();
    }

    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppFlowyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    _updateValues();

    if (editorState.service != oldWidget.editorState.service) {
      editorState.renderer = _renderer;
    }

    if (widget.editorScrollController != oldWidget.editorScrollController) {
      editorScrollController = widget.editorScrollController ??
          EditorScrollController(
            editorState: editorState,
            shrinkWrap: widget.shrinkWrap,
          );
    }

    // PREVON PATCH — the service graph embeds props (header/footer, editor
    // style, context menu, etc.) that are captured when it is built. It must
    // be rebuilt when the editorState identity changes (the renderer and the
    // document it renders are new), and — for callers that opted in via
    // [AppFlowyEditor.serviceConfigKey] — when that token's identity changes.
    // A null token preserves the legacy always-rebuild behaviour.
    final editorStateChanged =
        !identical(widget.editorState, oldWidget.editorState);
    if (editorStateChanged ||
        widget.serviceConfigKey == null ||
        widget.serviceConfigKey != oldWidget.serviceConfigKey) {
      services = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    services ??= _buildServices(context);

    return Provider.value(
      value: editorState,
      child: FocusScope(
        child: Overlay(
          clipBehavior: Clip.none,
          initialEntries: [
            OverlayEntry(
              builder: (context) => services!,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServices(BuildContext context) {
    if (kDebugMode) {
      debugAppFlowyEditorServiceBuildCount++;
    }
    Widget child = editorState.renderer.build(
      context,
      editorState.document.root,
      header: widget.header,
      footer: widget.footer,
      wrapper: widget.blockWrapper,
    );

    if (!widget.disableKeyboardService) {
      child = KeyboardServiceWidget(
        key: editorState.service.keyboardServiceKey,
        // disable all the shortcuts when the editor is not editable
        characterShortcutEvents:
            widget.editable ? widget.characterShortcutEvents : [],
        // only allow copy and select all when the editor is not editable
        commandShortcutEvents: widget.commandShortcutEvents,
        focusNode: widget.focusNode,
        contentInsertionConfiguration: widget.contentInsertionConfiguration,
        child: child,
      );
    }

    if (!widget.disableSelectionService) {
      child = SelectionServiceWidget(
        key: editorState.service.selectionServiceKey,
        cursorColor: widget.editorStyle.cursorColor,
        selectionColor: widget.editorStyle.selectionColor,
        showMagnifier: widget.showMagnifier,
        contextMenuBuilder: widget.contextMenuBuilder,
        dropTargetStyle: widget.dropTargetStyle,
        child: child,
      );
    }

    final toolbarBuilder = widget.mobileFloatingToolbarBuilder;
    if (toolbarBuilder != null &&
        PlatformExtension.isMobile &&
        !widget.disableSelectionService) {
      child = MobileFloatingToolbar(
        editorState: editorState,
        editorScrollController: editorScrollController,
        floatingToolbarHeight: 48,
        toolbarBuilder: toolbarBuilder,
        child: child,
      );
    }

    if (!widget.disableScrollService) {
      child = ScrollServiceWidget(
        key: editorState.service.scrollServiceKey,
        editorScrollController: editorScrollController,
        child: child,
      );
    }

    return child;
  }

  void _autoFocusIfNeeded() {
    if (widget.editable && widget.autoFocus) {
      editorState.updateSelectionWithReason(
        widget.focusedSelection ??
            Selection.single(
              path: [0],
              startOffset: 0,
            ),
        reason: SelectionUpdateReason.uiEvent,
      );
    }
  }

  void _updateValues() {
    editorState.editorStyle = widget.editorStyle;
    editorState.editable = widget.editable;
    editorState.showHeader = widget.header != null;
    editorState.showFooter = widget.footer != null;
    editorState.enableAutoComplete = widget.enableAutoComplete;
    editorState.autoCompleteTextProvider = widget.autoCompleteTextProvider;
    editorState.disableAutoScroll = widget.disableAutoScroll;
    editorState.autoScrollEdgeOffset = widget.autoScrollEdgeOffset;
    editorState.documentRules = widget.documentRules;
  }

  BlockComponentRendererService get _renderer => BlockComponentRenderer(
        builders: {...widget.blockComponentBuilders},
      );
}

class KeepEditorFocusNotifier extends ValueNotifier<int> {
  KeepEditorFocusNotifier() : super(0);

  bool get shouldKeepFocus => value > 0;

  @override
  set value(int v) {
    super.value = max(0, v);
  }

  void increase() {
    value++;
  }

  void decrease() {
    value--;
  }

  void reset() {
    value = 0;
  }
}
