import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:html/dom.dart' as dom;

class HTMLDividerNodeParser extends HTMLNodeParser {
  const HTMLDividerNodeParser();

  @override
  String get id => DividerBlockKeys.type;

  @override
  String transformNodeToHTMLString(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return toHTMLString(
      transformNodeToDomNodes(node, encodeParsers: encodeParsers),
    );
  }

  @override
  List<dom.Node> transformNodeToDomNodes(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    return [dom.Element.tag(HTMLTags.divider)];
  }
}
