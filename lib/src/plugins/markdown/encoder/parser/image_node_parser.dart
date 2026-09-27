import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

class ImageNodeParser extends NodeParser {
  const ImageNodeParser();

  @override
  String get id => ImageBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    return '![](${node.attributes[ImageBlockKeys.url]})';
  }
}
