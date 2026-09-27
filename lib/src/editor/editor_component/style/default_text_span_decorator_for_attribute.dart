import 'dart:async';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Support Desktop and Web platform
///   - customize the href text span
TextSpan defaultTextSpanDecoratorForAttribute(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
) {
  final attributes = text.attributes;
  if (attributes == null) {
    return before;
  }
  final editorState = context.read<EditorState>();
  // In-note note/folder link (the [[ … ]] picker, or "Link to note" toolbar
  // action) — independent of the existing href branch below. Resolved via an
  // abstract NoteLinkNavigator that the host app (Pie Notes) provides via
  // Provider<NoteLinkNavigator> above the AppFlowyEditor, so this fork stays
  // app-layer-clean (no waterfall_direction_enforcement import).
  final noteLinkId = attributes[AppFlowyRichTextKeys.noteLink] as String?;
  final folderLinkId = attributes[AppFlowyRichTextKeys.folderLink] as String?;
  if (noteLinkId != null || folderLinkId != null) {
    // Not every AppFlowyEditor host wires Provider<NoteLinkNavigator> (e.g.
    // a surface that only reads/displays notes rather than editing them with
    // the [[ picker enabled). Degrade to plain, non-interactive text instead
    // of throwing ProviderNotFoundException on render.
    NoteLinkNavigator? navigator;
    try {
      navigator = context.read<NoteLinkNavigator>();
    } on ProviderNotFoundException {
      navigator = null;
    }
    if (navigator == null) {
      return before;
    }
    final resolvedNavigator = navigator;
    final tapGestureRecognizer = TapGestureRecognizer()
      ..onTap = () => noteLinkId != null
          ? resolvedNavigator.openNote(context, noteLinkId)
          : resolvedNavigator.openFolder(context, folderLinkId!);
    return TextSpan(
      style: before.style,
      text: text.text,
      recognizer: tapGestureRecognizer,
      mouseCursor: SystemMouseCursors.click,
    );
  }
  final href = attributes[AppFlowyRichTextKeys.href] as String?;
  if (href != null) {
    // add a tap gesture recognizer to the text span
    Timer? timer;
    int tapCount = 0;

    final tapGestureRecognizer = TapGestureRecognizer()
      ..onTap = () async {
        // implement a simple double tap logic
        tapCount += 1;
        timer?.cancel();
        // meta / ctrl + click to open the link
        if (tapCount == 2 ||
            !editorState.editable ||
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) {
          tapCount = 0;
          editorLaunchUrl(href);
          return;
        }
        timer = Timer(const Duration(milliseconds: 200), () {
          tapCount = 0;
          final selection = Selection.single(
            path: node.path,
            startOffset: index,
            endOffset: index + text.text.length,
          );
          editorState.updateSelectionWithReason(
            selection,
            reason: SelectionUpdateReason.uiEvent,
          );
          WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
            showLinkMenu(context, editorState, selection, true);
          });
        });
      };

    return TextSpan(
      style: before.style,
      text: text.text,
      recognizer: tapGestureRecognizer,
      mouseCursor: SystemMouseCursors.click,
    );
  }
  return before;
}
