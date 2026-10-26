import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

// PATCH 21: '>' is the markdown quote marker, so it works too.
const _doubleQuotes = ['"', '“', '>'];

/// Convert '" ' (or the markdown '> ') to quote
///
/// - support
///   - desktop
///   - mobile
///   - web
///
CharacterShortcutEvent formatDoubleQuoteToQuote = CharacterShortcutEvent(
  key: 'format greater to quote',
  character: ' ',
  handler: (editorState) async => await formatMarkdownSymbol(
    editorState,
    (node) => node.type != QuoteBlockKeys.type,
    (_, text, __) => _doubleQuotes.any((element) => element == text),
    (_, node, delta) => [
      quoteNode(
        attributes: {
          QuoteBlockKeys.delta: delta.compose(Delta()..delete(1)).toJson(),
        },
      ),
      if (node.children.isNotEmpty) ...node.children,
    ],
  ),
);
