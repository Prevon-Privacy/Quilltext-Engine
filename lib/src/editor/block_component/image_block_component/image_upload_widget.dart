import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:string_validator/string_validator.dart';

import '../../util/file_picker/file_picker_impl.dart';
import 'base64_image.dart';

typedef OnInsertImage = void Function(String url);

const _imageExtensions = ['jpg', 'png', 'jpeg', 'gif', 'webp'];

/// Opens the platform's native image picker directly (no intermediate panel)
/// and inserts the chosen image. On web the src is base64 content; elsewhere
/// it is the picked file's path.
Future<void> showImageMenu(
  OverlayState container,
  EditorState editorState,
  SelectionMenuService menuService, {
  OnInsertImage? onInsertImage,
}) async {
  menuService.dismiss();
  // Opening the native dialog steals focus, which can null the editor
  // selection — remember it so the image lands where the slash was typed.
  final selection = editorState.selection;

  keepEditorFocusNotifier.increase();
  String? src;
  try {
    final result = await FilePicker().pickFiles(
      dialogTitle: '',
      allowMultiple: false,
      type: kIsWeb ? fp.FileType.custom : fp.FileType.image,
      allowedExtensions: kIsWeb ? _imageExtensions : null,
      withData: kIsWeb,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      src = kIsWeb ? base64String(await file.readAsBytes()) : file.path;
    }
  } finally {
    keepEditorFocusNotifier.decrease();
  }
  if (src == null || src.isEmpty) return;

  if (selection != null) {
    await editorState.updateSelectionWithReason(
      selection,
      reason: SelectionUpdateReason.uiEvent,
    );
  }
  if (onInsertImage != null) {
    onInsertImage(src);
  } else {
    await editorState.insertImageNode(src);
  }
}

/// Small popup with a single URL field for inserting a remote image.
void showImageUrlMenu(
  OverlayState container,
  EditorState editorState,
  SelectionMenuService menuService, {
  OnInsertImage? onInsertImage,
}) {
  menuService.dismiss();

  final (menuLeft, top, right, bottom) = menuService.getPosition();

  // Phone-safe sizing: a comfortable fixed width capped to the screen, with
  // the left edge pulled in so the box never runs off the right side.
  final screenWidth = MediaQuery.of(container.context).size.width;
  final width = screenWidth - 32 < 340.0 ? screenWidth - 32 : 340.0;
  final left = menuLeft?.clamp(16.0, screenWidth - width - 16).toDouble();

  late final OverlayEntry entry;

  void insertImage(String url) {
    if (onInsertImage != null) {
      onInsertImage(url);
    } else {
      editorState.insertImageNode(url);
    }
    menuService.dismiss();
    entry.remove();
    keepEditorFocusNotifier.decrease();
  }

  keepEditorFocusNotifier.increase();
  entry = FullScreenOverlayEntry(
    left: left,
    right: right,
    top: top,
    bottom: bottom,
    dismissCallback: () => keepEditorFocusNotifier.decrease(),
    builder: (context) => ImageUrlMenu(
      backgroundColor: menuService.style.selectionMenuBackgroundColor,
      urlInputBorderColor: menuService.style.selectionMenuLinkBorderColor,
      urlInvalidLinkColor: menuService.style.selectionMenuInvalidLinkColor,
      textColor: menuService.style.selectionMenuItemTextColor,
      width: width,
      onSubmitted: insertImage,
    ),
  ).build();
  container.insert(entry);
}

class ImageUrlMenu extends StatefulWidget {
  const ImageUrlMenu({
    super.key,
    this.backgroundColor = Colors.white,
    this.urlInputBorderColor = const Color(0xFFBDBDBD),
    this.urlInvalidLinkColor = Colors.red,
    this.textColor = Colors.black,
    this.width = 300,
    required this.onSubmitted,
  });

  final Color backgroundColor;
  final Color urlInputBorderColor;
  final Color urlInvalidLinkColor;
  final Color textColor;
  final double width;
  final void Function(String url) onSubmitted;

  @override
  State<ImageUrlMenu> createState() => _ImageUrlMenuState();
}

class _ImageUrlMenuState extends State<ImageUrlMenu> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isUrlValid = true;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final url = text.trim();
    if (url.isNotEmpty && isURL(url)) {
      widget.onSubmitted(url);
    } else {
      setState(() => _isUrlValid = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(12.0)),
      borderSide: BorderSide(color: widget.urlInputBorderColor),
    );
    return Container(
      width: widget.width,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        boxShadow: [
          BoxShadow(
            blurRadius: 5,
            spreadRadius: 1,
            color: Colors.black.withValues(alpha: 0.1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            enableIMEPersonalizedLearning: false,
            focusNode: _focusNode,
            controller: _controller,
            style: TextStyle(fontSize: 14.0, color: widget.textColor),
            cursorColor: widget.urlInputBorderColor,
            onChanged: (_) {
              if (!_isUrlValid) setState(() => _isUrlValid = true);
            },
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'https://…',
              hintStyle: TextStyle(fontSize: 14.0, color: widget.textColor),
              contentPadding: const EdgeInsets.all(16.0),
              isDense: true,
              focusedBorder: border,
              enabledBorder: border,
              border: border,
            ),
          ),
          if (!_isUrlValid) ...[
            const SizedBox(height: 8.0),
            Text(
              AppFlowyEditorL10n.current.incorrectLink,
              style: TextStyle(color: widget.urlInvalidLinkColor, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

extension InsertImage on EditorState {
  Future<void> insertImageNode(
    String src,
  ) async {
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final node = getNodeAtPath(selection.end.path);
    if (node == null) {
      return;
    }
    final transaction = this.transaction;
    // if the current node is empty paragraph, replace it with image node
    if (node.type == ParagraphBlockKeys.type &&
        (node.delta?.isEmpty ?? false)) {
      transaction
        ..insertNode(
          node.path,
          imageNode(
            url: src,
          ),
        )
        ..deleteNode(node);
    } else {
      transaction.insertNode(
        node.path.next,
        imageNode(
          url: src,
        ),
      );
    }

    transaction.afterSelection = Selection.collapsed(
      Position(
        path: node.path.next,
        offset: 0,
      ),
    );

    return apply(transaction);
  }
}
