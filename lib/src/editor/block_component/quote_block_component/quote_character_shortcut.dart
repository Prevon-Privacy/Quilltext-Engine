import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

const _doubleQuotes = ['"', '“'];

/// Convert '" ' to quote
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
