import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/file_block_component/file_card.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/file_block_component/file_card_status.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/file_block_component/file_lift.dart';
import 'package:prevon_quilltext_engine/src/service/selection/touch_drag_gate.dart';
import 'package:provider/provider.dart';

/// A file attached to the note: shown as a card (icon, name, size). The bytes
/// live in the host's attachment store; the block only holds an
/// opaque reference plus the name the person sees.
class FileBlockKeys {
  const FileBlockKeys._();

  static const String type = 'file';

  /// Opaque reference to the stored bytes (the host's `pie-att://` URI).
  static const String url = 'url';

  /// The file name shown on the card. Lives in the saved note body.
  static const String name = 'name';

  /// MIME type, `''` when unknown.
  static const String mime = 'mime';

  /// Plaintext size in bytes (int), 0 when unknown.
  static const String size = 'size';

  /// True when the person hid this file from the host's features. Absent means visible. A person's
  /// decision, so it lives here in the saved note body, never in the rebuildable text index.
  static const String hiddenFromAi = 'hiddenFromAi';
}

Node fileNode({
  required String url,
  required String name,
  String mime = '',
  int size = 0,
}) =>
    Node(
      type: FileBlockKeys.type,
      attributes: {
        FileBlockKeys.url: url,
        FileBlockKeys.name: name,
        FileBlockKeys.mime: mime,
        FileBlockKeys.size: size,
      },
    );

/// Every file block under [root], in document order.
List<FileViewRequest> collectFileRequests(Node root) {
  final out = <FileViewRequest>[];
  void walk(Node n) {
    if (n.type == FileBlockKeys.type) out.add(fileRequestOf(n));
    for (final c in n.children) {
      walk(c);
    }
  }

  walk(root);
  return out;
}

FileViewRequest fileRequestOf(Node node) {
  final a = node.attributes;
  final size = a[FileBlockKeys.size];
  return FileViewRequest(
    src: (a[FileBlockKeys.url] as String?) ?? '',
    name: (a[FileBlockKeys.name] as String?) ?? '',
    mime: (a[FileBlockKeys.mime] as String?) ?? '',
    sizeBytes: size is num ? size.toInt() : 0,
    hiddenFromAi: a[FileBlockKeys.hiddenFromAi] == true,
  );
}

class FileBlockComponentBuilder extends BlockComponentBuilder {
  FileBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return FileBlockComponentWidget(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.delta == null && node.children.isEmpty;
}

class FileBlockComponentWidget extends BlockComponentStatefulWidget {
  const FileBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<FileBlockComponentWidget> createState() =>
      FileBlockComponentWidgetState();
}

class FileBlockComponentWidgetState extends State<FileBlockComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final cardKey = GlobalKey();
  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  late final editorState = Provider.of<EditorState>(context, listen: false);

  FileActions? _actions() {
    try {
      return context.read<FileActions>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  BlockHoldLift? _lift;

  @override
  void dispose() {
    _lift?.cancel();
    super.dispose();
  }

  void _liftStart(LongPressStartDetails d) {
    _lift?.cancel();
    _lift = BlockHoldLift.begin(context, editorState, node, d.globalPosition);
    // Nothing to lift (read-only note): behave as the old hold, the menu.
    if (_lift == null) _menu();
  }

  void _liftEnd() {
    final lift = _lift;
    _lift = null;
    if (lift == null) return;
    if (!lift.end()) _menu();
  }

  FileAiHideHost? _hideHost() {
    try {
      return context.read<FileAiHideHost>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Flips "Hide" as one editor transaction (so the editor's own undo reverts it
  /// too) and tells the host, which offers an Undo.
  void _toggleAiHidden() {
    if (!editorState.editable) return;
    final next = !fileRequestOf(node).hiddenFromAi;
    setFileHiddenFromAi(editorState, node, next);
    _hideHost()?.aiHiddenChanged(
      context,
      hidden: next,
      undo: () => setFileHiddenFromAi(editorState, node, !next),
    );
  }

  void _open() {
    _actions()?.openFile(context, fileRequestOf(node));
  }

  Future<void> _menu() async {
    final actions = _actions();
    if (actions == null) return;
    final parent = node.parent;
    final index = node.path.last;
    final choice = await actions.showFileMenu(
      context,
      FileMenuRequest(
        file: fileRequestOf(node),
        editable: editorState.editable,
        canMoveUp: index > 0,
        canMoveDown: parent != null && index < parent.children.length - 1,
        allFiles: collectFileRequests(editorState.document.root),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case FileMenuChoice.open:
        _open();
      case FileMenuChoice.listAll:
        break; // the host handled it inside showFileMenu
      case FileMenuChoice.view:
        break; // the host handled it inside showFileMenu
      case FileMenuChoice.save:
        await actions.saveFile(context, fileRequestOf(node));
      case FileMenuChoice.moveUp:
        moveFile(editorState, node, -1);
      case FileMenuChoice.moveDown:
        moveFile(editorState, node, 1);
      case FileMenuChoice.remove:
        final req = fileRequestOf(node);
        removeFile(editorState, node);
        _statusSource()?.onRemoved(req, () => editorState.undoManager.undo());
      case FileMenuChoice.toggleAiHidden:
        _toggleAiHidden();
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = fileRequestOf(widget.node);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = req.name.isEmpty ? '—' : req.name;
    final detail = fileDetailLine(req);

    Widget child = Listener(
      // Keep the page's own pan / long-press recognizers out of the arena for
      // this finger so the hold is not raced (same gate the other grips use).
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => TouchDragHandleGate.claim(e.pointer),
      onPointerUp: (e) => TouchDragHandleGate.release(e.pointer),
      onPointerCancel: (e) => TouchDragHandleGate.release(e.pointer),
      child: ReorderDimmed(
        node: node,
        child: _card(req, name, detail, theme, scheme),
      ),
    );
    return _wrap(child);
  }

  FileStatusSource? _statusSource() {
    try {
      return context.read<FileStatusSource>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  bool _pressed = false;
  void _press(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  Widget _card(FileViewRequest req, String name, String detail, ThemeData theme,
      ColorScheme scheme) {
    final source = _statusSource();
    final words = source?.words ?? const FileCardWords();
    Widget body(FileCardStatus status) => Stack(
          children: [
            FileCard(
              file: req,
              status: status,
              words: words,
              pressed: _pressed,
              onMore: _menu,
            ),
            // HAND-MERGE: the shared tree's "hidden" badge, over the new card.
            if (req.hiddenFromAi)
              PositionedDirectional(
                top: 6,
                end: 6,
                child: _hideHost()?.hiddenBadge(context) ??
                    Icon(Icons.visibility_off_outlined,
                        size: 18, color: scheme.onSurfaceVariant),
              ),
          ],
        );

    final live = source?.statusOf(req);
    return Padding(
      key: cardKey,
      padding: padding,
      child: Semantics(
        button: true,
        label: detail.isEmpty ? name : '$name, $detail',
        customSemanticsActions: {
          CustomSemanticsAction(label: words.moreActions): _menu,
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          onTapDown: (_) => _press(true),
          onTapUp: (_) => _press(false),
          onTapCancel: () => _press(false),
          onLongPressStart: _liftStart,
          onLongPressMoveUpdate: (d) => _lift?.update(d.globalPosition),
          onLongPressEnd: (_) => _liftEnd(),
          onLongPressCancel: () {
            _press(false);
            _lift?.cancel();
            _lift = null;
          },
          onSecondaryTap: _menu,
          child: live == null
              ? body(const FileCardStatus.ready())
              : ValueListenableBuilder<FileCardStatus>(
                  valueListenable: live,
                  builder: (_, status, __) => body(status),
                ),
        ),
      ),
    );
  }

  Widget _wrap(Widget card) {
    Widget child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: card,
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
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final box = cardKey.currentContext?.findRenderObject();
    return box is RenderBox ? Offset.zero & box.size : Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final box = _renderBox;
    if (box == null) return null;
    return Rect.fromLTWH(
      -box.size.width / 2.0,
      0,
      box.size.width,
      box.size.height,
    );
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    final box = _renderBox;
    if (box == null) return [];
    final parentBox = context.findRenderObject();
    final cardBox = cardKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && cardBox is RenderBox) {
      return [
        cardBox.localToGlobal(Offset.zero, ancestor: parentBox) & cardBox.size,
      ];
    }
    return [Offset.zero & box.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _renderBox!.localToGlobal(offset);
}

/// "2.4 MB" style size plus the upper-case extension, e.g. "PDF · 2.4 MB".
String fileDetailLine(FileViewRequest r) {
  final parts = <String>[];
  final dot = r.name.lastIndexOf('.');
  if (dot > 0 && dot < r.name.length - 1 && r.name.length - dot <= 6) {
    parts.add(r.name.substring(dot + 1).toUpperCase());
  }
  if (r.sizeBytes > 0) parts.add(formatFileSize(r.sizeBytes));
  return parts.join(' · ');
}

/// Human size with one decimal above 1 KB (decimal units, like the OS shows).
String formatFileSize(int bytes) {
  if (bytes < 1000) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1000.0;
  var i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

IconData fileIconFor(String mime, String name) {
  final m = mime.toLowerCase();
  final n = name.toLowerCase();
  bool ext(List<String> exts) => exts.any((e) => n.endsWith('.$e'));
  if (m == 'application/pdf' || n.endsWith('.pdf')) {
    return Icons.picture_as_pdf_outlined;
  }
  if (m.startsWith('image/')) return Icons.image_outlined;
  if (m.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (m.startsWith('video/')) return Icons.videocam_outlined;
  if (m.contains('presentation') || ext(['ppt', 'pptx', 'odp', 'key'])) {
    return Icons.slideshow_outlined;
  }
  if (m.contains('spreadsheet') ||
      m.contains('ms-excel') ||
      m == 'text/csv' ||
      m == 'text/tab-separated-values' ||
      ext(['csv', 'tsv', 'xls', 'xlsx', 'ods', 'numbers'])) {
    return Icons.table_chart_outlined;
  }
  if (m.contains('wordprocessing') ||
      m.contains('msword') ||
      m.contains('opendocument.text') ||
      m == 'application/rtf' ||
      ext(['doc', 'docx', 'odt', 'rtf', 'pages'])) {
    return Icons.description_outlined;
  }
  if (m == 'application/epub+zip' || n.endsWith('.epub')) {
    return Icons.menu_book_outlined;
  }
  if (m.contains('zip') ||
      m.contains('x-tar') ||
      m.contains('gzip') ||
      m.contains('7z') ||
      m.contains('rar') ||
      ext(['zip', 'tar', 'gz', 'tgz', '7z', 'rar'])) {
    return Icons.folder_zip_outlined;
  }
  if (m.startsWith('text/') || m.contains('json') || m.contains('xml')) {
    return Icons.article_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

extension InsertFile on EditorState {
  /// Inserts a file block at the caret (replacing an empty paragraph), the
  /// same rules as [InsertImage.insertImageNode]. Returns false when there was no caret to insert
  /// at (nothing was inserted).
  Future<bool> insertFileNode({
    required String url,
    required String name,
    String mime = '',
    int size = 0,
  }) async {
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) return false;
    final node = getNodeAtPath(selection.end.path);
    if (node == null) return false;
    final block = fileNode(url: url, name: name, mime: mime, size: size);
    final transaction = this.transaction;
    if (node.type == ParagraphBlockKeys.type &&
        (node.delta?.isEmpty ?? false)) {
      transaction
        ..insertNode(node.path, block)
        ..deleteNode(node);
    } else {
      transaction.insertNode(node.path.next, block);
    }
    transaction.afterSelection = Selection.collapsed(
      Position(path: node.path.next, offset: 0),
    );
    await apply(transaction);
    return true;
  }
}

Color fileTintFor(FileFamily f, ColorScheme s) => switch (f) {
      FileFamily.pdf => s.error,
      FileFamily.image => s.tertiary,
      FileFamily.audio || FileFamily.video => s.secondary,
      FileFamily.slides => s.error,
      FileFamily.sheet => s.primary,
      FileFamily.doc => s.primary,
      FileFamily.archive => s.secondary,
      FileFamily.text => s.onSurfaceVariant,
      FileFamily.other => s.onSurfaceVariant,
    };

class FileStatusChip extends StatelessWidget {
  const FileStatusChip({required this.status, required this.words});

  final FileCardStatus status;
  final FileCardWords words;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall;
    final (IconData?, Color) look = switch (status.phase) {
      FileCardPhase.searchable => (Icons.manage_search_rounded, scheme.primary),
      FileCardPhase.localOnly => (
          Icons.smartphone_rounded,
          scheme.onSurfaceVariant
        ),
      FileCardPhase.failed => (Icons.error_outline_rounded, scheme.error),
      _ => (null, scheme.onSurfaceVariant),
    };
    final working = status.phase == FileCardPhase.working;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (working)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: status.progress,
              color: look.$2,
            ),
          )
        else if (look.$1 != null)
          Icon(look.$1, size: 14, color: look.$2),
        if (status.label.isNotEmpty) ...[
          const SizedBox(width: 4),
          Flexible(
            child: Text(status.label, style: style?.copyWith(color: look.$2)),
          ),
        ],
        if (status.phase == FileCardPhase.failed && status.onRetry != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: GestureDetector(
              onTap: status.onRetry,
              child: Text(
                words.retry,
                style: style?.copyWith(
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
