import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

abstract class NodeParser {
  const NodeParser();

  String get id;
  String transform(Node node, DocumentMarkdownEncoder? encoder);
}
