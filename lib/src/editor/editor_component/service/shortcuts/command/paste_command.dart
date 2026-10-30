import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'url_phone_regex.dart';

final List<CommandShortcutEvent> pasteCommands = [
  pasteCommand,
  pasteTextWithoutFormattingCommand,
];

/// Paste.
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent pasteCommand = CommandShortcutEvent(
  key: 'paste the content',
  getDescription: () => AppFlowyEditorL10n.current.cmdPasteContent,
  command: 'ctrl+v',
  macOSCommand: 'cmd+v',
  handler: _pasteCommandHandler,
);

final CommandShortcutEvent pasteTextWithoutFormattingCommand =
    CommandShortcutEvent(
  key: 'paste the content as plain text',
  getDescription: () => AppFlowyEditorL10n.current.cmdPasteContentAsPlainText,
  command: 'ctrl+shift+v',
  macOSCommand: 'cmd+shift+v',
  handler: _pasteTextWithoutFormattingCommandHandler,
);

CommandShortcutEventHandler _pasteTextWithoutFormattingCommandHandler =
    (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }

  () async {
    final data = await AppFlowyClipboard.getData();
    final text = data.text;
    if (text != null && text.isNotEmpty) {
      await editorState.pastePlainText(text);
    }
  }();

  return KeyEventResult.handled;
};

/// Called after a paste whose whole clipboard text was ONE url and the url
/// landed as a link at [offset]..[offset]+[length] of [node]. The host app
/// uses it to offer "Paste as plain text" (see [unlinkPastedUrl]).
typedef UrlPasteListener = void Function(
  EditorState editorState,
  Node node,
  int offset,
  int length,
  String url,
);

UrlPasteListener? urlPasteListener;

/// The clipboard text when it is exactly one http(s) URL (trimmed, one
/// line, nothing else); otherwise null. Prose that merely contains a link
/// and multi-link pastes never qualify.
String? singleUrlOrNull(String? text) {
  final t = text?.trim();
  if (t == null || t.isEmpty || RegExp(r'\s').hasMatch(t)) {
    return null;
  }
  final m = kHrefRegex.firstMatch(t);
  return (m != null && m.start == 0 && m.end == t.length) ? t : null;
}

/// Removes the link from [url] at [offset] in [node] if it is still there
/// unchanged (the user may have typed since the paste). Returns whether it
/// did anything.
Future<bool> unlinkPastedUrl(
  EditorState editorState,
  Node node,
  int offset,
  int length,
  String url,
) async {
  final delta = node.delta;
  if (node.parent == null ||
      delta == null ||
      offset + length > delta.length ||
      delta.toPlainText().substring(offset, offset + length) != url) {
    return false;
  }
  final transaction = editorState.transaction
    ..formatText(node, offset, length, {AppFlowyRichTextKeys.href: null});
  await editorState.apply(transaction);
  return true;
}

/// The reverse of [unlinkPastedUrl]: makes [url] at [offset] in [node] a link
/// again if it is still there unchanged.
Future<bool> relinkPastedUrl(
  EditorState editorState,
  Node node,
  int offset,
  int length,
  String url,
) async {
  final delta = node.delta;
  if (node.parent == null ||
      delta == null ||
      offset + length > delta.length ||
      delta.toPlainText().substring(offset, offset + length) != url) {
    return false;
  }
  final transaction = editorState.transaction
    ..formatText(node, offset, length, {AppFlowyRichTextKeys.href: url});
  await editorState.apply(transaction);
  return true;
}

final RegExp _htmlPicture = RegExp(r'<img\b', caseSensitive: false);

/// Offers the clipboard to the host's [ClipboardMediaPaster] when it may hold a picture. Plain
/// text pastes never reach it (no extra platform call); an HTML copy that carries a picture does,
/// so a picture copied from a web page becomes a local attachment, not a remote `<img>` link.
/// True when the host took the clipboard. With no host bridge, or no editor context, false.
Future<bool> _pasteClipboardMedia(
  EditorState editorState,
  String? text,
  String? html,
) async {
  final hasText = text != null && text.trim().isNotEmpty;
  final htmlHasPicture = html != null && _htmlPicture.hasMatch(html);
  if (hasText && !htmlHasPicture) {
    return false;
  }
  final context = editorState.service.scrollServiceKey.currentContext;
  if (context == null || !context.mounted) {
    return false;
  }
  final ClipboardMediaPaster paster;
  try {
    paster = context.read<ClipboardMediaPaster>();
  } on ProviderNotFoundException {
    return false;
  }
  try {
    return await paster.pasteMedia();
  } catch (_) {
    return false;
  }
}

CommandShortcutEventHandler _pasteCommandHandler = (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  final start = selection.normalized.start;

  () async {
    final data = await AppFlowyClipboard.getData();
    final text = data.text;
    final html = data.html;
    if (await _pasteClipboardMedia(editorState, text, html)) {
      return;
    }
    final url = singleUrlOrNull(text);
    var pasted = false;
    if (html != null && html.isNotEmpty) {
      // if the html is pasted successfully, then return
      // otherwise, paste the plain text
      try {
        pasted = await editorState.pasteHtml(html);
      } catch (_) {
        // Catches Errors too (StackOverflowError, OOM-adjacent): a failed HTML paste must fall
        // through to the plain-text paste below, never drop the paste.
        pasted = false;
      }
    }

    if (!pasted && text != null && text.isNotEmpty) {
      await editorState.pastePlainText(text);
      pasted = true;
    }

    final listener = urlPasteListener;
    if (!pasted || url == null || listener == null) {
      return;
    }
    // Only offer the choice when the url really landed as a link.
    final node = editorState.getNodeAtPath(start.path);
    final delta = node?.delta;
    if (node == null ||
        delta == null ||
        start.offset + url.length > delta.length) {
      return;
    }
    final landed = delta.toPlainText().substring(
              start.offset,
              start.offset + url.length,
            ) ==
        url;
    final linked = delta
        .slice(start.offset, start.offset + url.length)
        .any((op) => op.attributes?[AppFlowyRichTextKeys.href] != null);
    if (landed && linked) {
      listener(editorState, node, start.offset, url.length, url);
    }
  }();

  return KeyEventResult.handled;
};

// _hrefRegex and _phoneRegex moved to `url_phone_regex.dart` so the
// save-time linkifier in `linkify_plain_text.dart` can reuse the SAME
// compiled regexes rather than fork them (drift risk). The aliases
// below keep _pasteCommandHandler readable; the shared regexes are
// `kHrefRegex` / `kPhoneRegex`.
final RegExp _hrefRegex = kHrefRegex;
final RegExp _phoneRegex = kPhoneRegex;

extension on EditorState {
  Future<bool> pasteHtml(String html) async {
    final nodes = htmlToDocument(html).root.children.toList();
    // remove the front and back empty line
    while (nodes.isNotEmpty &&
        nodes.first.delta?.isEmpty == true &&
        nodes.first.children.isEmpty) {
      nodes.removeAt(0);
    }
    while (nodes.isNotEmpty &&
        nodes.last.delta?.isEmpty == true &&
        nodes.last.children.isEmpty) {
      nodes.removeLast();
    }
    if (nodes.isEmpty) {
      return false;
    }
    if (nodes.length == 1) {
      await pasteSingleLineNode(nodes.first);
    } else {
      await pasteMultiLineNodes(nodes.toList());
    }
    return true;
  }

  Future<void> pastePlainText(String plainText) async {
    final selectionAttributes = getDeltaAttributesInSelectionStart();
    // TODO remove this deletion after refactoring pasteHtmlIfAvailable below
    final selection = await deleteSelectionIfNeeded();

    if (selection == null) {
      return;
    }

    if (await maybeConvertToUrlOrPhone(plainText)) {
      return;
    }

    final nodes = plainText
        .split('\n')
        .map(
          (paragraph) => paragraph
            ..replaceAll(r'\r', '')
            ..trimRight(),
        )
        .map((paragraph) {
          Delta delta = Delta();
          if (_hrefRegex.hasMatch(paragraph) ||
              _phoneRegex.hasMatch(paragraph)) {
            final match = _hrefRegex.firstMatch(paragraph) ??
                _phoneRegex.firstMatch(paragraph);
            if (match != null) {
              int startPos = match.start;
              int endPos = match.end;
              final String? entity = match.group(0);
              if (entity != null) {
                /// insert the text before the link or phone
                if (startPos > 0) {
                  delta.insert(paragraph.substring(0, startPos));
                }

                /// insert the link or phone
                delta.insert(
                  paragraph.substring(startPos, endPos),
                  attributes: {
                    AppFlowyRichTextKeys.href:
                        _phoneRegex.hasMatch(entity) ? 'tel:$entity' : entity,
                  },
                );

                /// insert the text after the link or phone
                if (endPos < paragraph.length) {
                  delta.insert(paragraph.substring(endPos));
                }
              }
            }
          } else {
            delta.insert(paragraph, attributes: selectionAttributes);
          }
          return delta;
        })
        .map((paragraph) => paragraphNode(delta: paragraph))
        .toList();

    if (nodes.isEmpty) {
      return;
    }
    if (nodes.length == 1) {
      await pasteSingleLineNode(nodes.first);
    } else {
      await pasteMultiLineNodes(nodes.toList());
    }
  }

  Future<bool> maybeConvertToUrlOrPhone(String plainText) async {
    final selection = this.selection;
    if (selection == null ||
        !selection.isSingle ||
        selection.isCollapsed ||
        (!_hrefRegex.hasMatch(plainText) && !_phoneRegex.hasMatch(plainText))) {
      return false;
    }

    final node = getNodeAtPath(selection.start.path);
    if (node == null) {
      return false;
    }

    final transaction = this.transaction;
    final isPhone = _phoneRegex.hasMatch(plainText);
    transaction.formatText(node, selection.startIndex, selection.length, {
      AppFlowyRichTextKeys.href: isPhone ? 'tel:$plainText' : plainText,
    });
    await apply(transaction);
    return true;
  }
}
