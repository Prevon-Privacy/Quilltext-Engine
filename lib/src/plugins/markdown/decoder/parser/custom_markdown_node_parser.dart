import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:markdown/markdown.dart' as md;

abstract class CustomMarkdownParser {
  const CustomMarkdownParser();

  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  });
}
