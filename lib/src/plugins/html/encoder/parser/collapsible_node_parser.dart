import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:html/dom.dart' as dom;

class HTMLCollapsibleNodeParser extends HTMLNodeParser {
  const HTMLCollapsibleNodeParser();

  @override
  String get id => CollapsibleBlockKeys.type;

  @override
  String transformNodeToHTMLString(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    assert(node.type == CollapsibleBlockKeys.type);

    return toHTMLString(
      transformNodeToDomNodes(node, encodeParsers: encodeParsers),
    );
  }

  @override
  List<dom.Node> transformNodeToDomNodes(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    final delta = node.delta ?? Delta();
    final summary = wrapChildrenNodesWithTagName(
      'summary',
      childNodes: deltaHTMLEncoder.convert(delta),
    );
    final details = wrapChildrenNodesWithTagName(
      'details',
      childNodes: [
        summary,
        ...processChildrenNodes(node.children, encodeParsers: encodeParsers),
      ],
    );
    if (node.attributes[CollapsibleBlockKeys.collapsed] != true) {
      details.attributes['open'] = '';
    }
    return [details];
  }
}
