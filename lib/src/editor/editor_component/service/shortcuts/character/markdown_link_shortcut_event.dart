import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// format the markdown link syntax to hyperlink
final CharacterShortcutEvent formatMarkdownLinkToLink = CharacterShortcutEvent(
  key: 'format the text surrounded by double asterisks to bold',
  character: ')',
  handler: (editorState) async => handleFormatMarkdownLinkToLink(
    editorState: editorState,
  ),
);

final _linkRegex = RegExp(r'\[([^\]]*)\]\((.*?)\)');

bool handleFormatMarkdownLinkToLink({
  required EditorState editorState,
}) {
  final selection = editorState.selection;
  // if the selection is not collapsed or the cursor is at the first 5 index range, we don't need to format it.
  // we should return false to let the IME handle it.
  if (selection == null || !selection.isCollapsed || selection.end.offset < 6) {
    return false;
  }

  final path = selection.end.path;
  final node = editorState.getNodeAtPath(path);
  final delta = node?.delta;
  // if the node doesn't contain the delta(which means it isn't a text)
  // we don't need to format it.
  if (node == null || delta == null) {
    return false;
  }

  final slicedDelta = delta.slice(0, selection.end.offset);
  final plainText = '${slicedDelta.toPlainText()})';

  // Determine if regex matches the plainText.
  if (!_linkRegex.hasMatch(plainText)) {
    return false;
  }

  // Only a link that ends exactly at the caret (with the typed ")") counts;
  // an earlier finished link in the block is left alone.
  RegExpMatch? lastMatch;
  for (final m in _linkRegex.allMatches(plainText)) {
    if (m.end == plainText.length) lastMatch = m;
  }
  if (lastMatch == null) return false;
  final title = lastMatch.group(1);
  final link = lastMatch.group(2);
  // Keep the title's own formatting (bold etc.) next to the new href.
  final titleOps = delta
      .slice(lastMatch.start + 1, lastMatch.start + 1 + title!.length)
      .whereType<TextInsert>();
  final titleAttrs = <String, dynamic>{
    ...?(titleOps.isEmpty ? null : titleOps.first.attributes),
  };

  // if all the conditions are met, we should format the text to a link.
  final transaction = editorState.transaction
    ..deleteText(
      node,
      lastMatch.start,
      lastMatch.end - lastMatch.start - 1,
    )
    ..insertText(
      node,
      lastMatch.start,
      title,
      attributes: {
        ...titleAttrs,
        AppFlowyRichTextKeys.href: link,
      },
    );
  editorState.apply(transaction);

  return true;
}
