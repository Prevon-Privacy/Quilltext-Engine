import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// PREVON PATCH: typing a space after something that looks like a web
/// address (`https://x.y/z`, `www.x.y`, `example.org`) turns that word
/// into a link. The link is a normal `href` run, so tapping opens it and
/// "Remove link" turns it back into plain text (it is not re-linked until the
/// user types another space after it).
final CharacterShortcutEvent autoLinkOnSpace = CharacterShortcutEvent(
  key: 'auto-link a typed web address',
  character: ' ',
  handler: (editorState) async => handleAutoLinkBeforeSpace(editorState),
);

const _tlds = 'com|org|net|io|app|dev|co|ai|edu|gov|me|us|uk|de|fr|ca|au|'
    'info|xyz|tech|site|online|store|blog|cloud|privacy|so|sh|ly|to|tv|eu';

final _urlRegex = RegExp(
  r'^(?:https?://[^\s/]+\.[^\s/]+\S*|'
  r'(?:www\.)?(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+'
  '(?:$_tlds)'
  r'(?::\d+)?(?:[/?#]\S*)?)$',
  caseSensitive: false,
);

// Punctuation that ends a sentence rather than the address.
const _trailing = '.,;:!?)]}\'"';

/// Always returns false: the typed space is still inserted by the caller; this
/// only applies the link format to the word before the caret.
bool handleAutoLinkBeforeSpace(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) return false;
  final node = editorState.getNodeAtPath(selection.end.path);
  final delta = node?.delta;
  if (node == null || delta == null) return false;
  // No links inside code blocks.
  if (node.type == 'code') return false;

  final caret = selection.end.offset;
  final before = delta.slice(0, caret).toPlainText();
  var wordStart = before.length;
  while (wordStart > 0 && !RegExp(r'\s').hasMatch(before[wordStart - 1])) {
    wordStart--;
  }
  var wordEnd = before.length;
  while (wordEnd > wordStart && _trailing.contains(before[wordEnd - 1])) {
    wordEnd--;
  }
  if (wordEnd <= wordStart) return false;
  final word = before.substring(wordStart, wordEnd);
  if (!_urlRegex.hasMatch(word)) return false;

  // Leave runs that already carry a link or inline code alone.
  for (final op in delta.slice(wordStart, wordEnd)) {
    final attrs = op is TextInsert ? op.attributes : null;
    if (attrs == null) continue;
    if (attrs[AppFlowyRichTextKeys.href] != null ||
        attrs[AppFlowyRichTextKeys.noteLink] != null ||
        attrs[AppFlowyRichTextKeys.folderLink] != null ||
        attrs[AppFlowyRichTextKeys.appLink] != null ||
        attrs[AppFlowyRichTextKeys.code] == true) {
      return false;
    }
  }

  final target =
      RegExp('^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(word)
          ? word
          : 'https://$word';
  final transaction = editorState.transaction
    ..formatText(node, wordStart, wordEnd - wordStart, {
      AppFlowyRichTextKeys.href: target,
    });
  editorState.apply(transaction);
  return false;
}
