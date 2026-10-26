import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

class DividerNodeParser extends NodeParser {
  const DividerNodeParser();

  @override
  String get id => DividerBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    return '---\n';
  }
}
