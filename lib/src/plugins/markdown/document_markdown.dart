library;

import 'dart:convert';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:markdown/markdown.dart' as md;

import 'markdown_input_guard.dart';

/// Converts a markdown to [Document].
///
/// [customParsers] is a list of custom parsers that will be used to parse the markdown.
///
/// Blocks that would make package:markdown go quadratic (see
/// `markdown_input_guard.dart` for the limits) are not parsed: they become
/// one plain paragraph holding their text literally. All other input takes
/// the normal path unchanged.
Document markdownToDocument(
  String markdown, {
  List<CustomMarkdownParser> markdownParsers = const [],
  List<md.InlineSyntax> inlineSyntaxes = const [],
}) {
  final segments = scanMarkdownForHostileBlocks(markdown);
  if (segments.isEmpty) {
    return markdownToDocumentUnguarded(
      markdown,
      markdownParsers: markdownParsers,
      inlineSyntaxes: inlineSyntaxes,
    );
  }
  final nodes = <Node>[];
  for (final seg in segments) {
    var text = markdown.substring(seg.start, seg.end);
    if (seg.hostile) {
      if (text.endsWith('\r')) text = text.substring(0, text.length - 1);
      nodes.add(paragraphNode(text: text));
    } else {
      final doc = markdownToDocumentUnguarded(
        text,
        markdownParsers: markdownParsers,
        inlineSyntaxes: inlineSyntaxes,
      );
      nodes.addAll(doc.root.children.map((e) => e.copyWith()));
    }
  }
  final document = Document.blank();
  if (nodes.isNotEmpty) {
    document.insert([0], nodes);
  }
  return document;
}

/// The raw conversion with no guard. Test seam for the equivalence corpus.
Document markdownToDocumentUnguarded(
  String markdown, {
  List<CustomMarkdownParser> markdownParsers = const [],
  List<md.InlineSyntax> inlineSyntaxes = const [],
}) {
  return AppFlowyEditorMarkdownCodec(
    markdownInlineSyntaxes: inlineSyntaxes,
    markdownParsers: [
      ...markdownParsers,
      const MarkdownParagraphParserV2(),
      const MarkdownHeadingParserV2(),
      const MarkdownTodoListParserV2(),
      const MarkdownUnorderedListParserV2(),
      const MarkdownOrderedListParserV2(),
      const MarkdownUnorderedListItemParserV2(),
      const MarkdownOrderedListItemParserV2(),
      const MarkdownBlockQuoteParserV2(),
      const MarkdownTableListParserV2(),
      const MarkdownDividerParserV2(),
      const MarkdownImageParserV2(),
    ],
  ).decode(markdown);
}

/// Converts a [Document] to markdown.
///
/// [customParsers] is a list of custom parsers that will be used to parse the markdown.
String documentToMarkdown(
  Document document, {
  List<NodeParser> customParsers = const [],
  String lineBreak = '',
}) {
  return AppFlowyEditorMarkdownCodec(
    encodeParsers: [
      ...customParsers,
      const TextNodeParser(),
      const BulletedListNodeParser(),
      const NumberedListNodeParser(),
      const TodoListNodeParser(),
      const QuoteNodeParser(),
      const CollapsibleNodeParser(),
      const ColumnsNodeParser(),
      const CodeBlockNodeParser(),
      const HeadingNodeParser(),
      const ImageNodeParser(),
      const TableNodeParser(),
      const DividerNodeParser(),
    ],
    lineBreak: lineBreak,
  ).encode(document);
}

class AppFlowyEditorMarkdownCodec extends Codec<Document, String> {
  const AppFlowyEditorMarkdownCodec({
    this.markdownInlineSyntaxes = const [],
    this.markdownParsers = const [],
    this.encodeParsers = const [],
    this.lineBreak = '',
  });

  final List<NodeParser> encodeParsers;
  final List<CustomMarkdownParser> markdownParsers;
  final List<md.InlineSyntax> markdownInlineSyntaxes;
  final String lineBreak;

  @override
  Converter<String, Document> get decoder => DocumentMarkdownDecoder(
        markdownElementParsers: markdownParsers,
        inlineSyntaxes: markdownInlineSyntaxes,
      );

  @override
  Converter<Document, String> get encoder => DocumentMarkdownEncoder(
        parsers: encodeParsers,
        lineBreak: lineBreak,
      );
}
