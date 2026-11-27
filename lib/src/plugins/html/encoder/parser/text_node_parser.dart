import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:html/dom.dart' as dom;

class HTMLTextNodeParser extends HTMLNodeParser {
  const HTMLTextNodeParser();

  @override
  String get id => ParagraphBlockKeys.type;

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
    final delta = node.delta ?? Delta();
    final domNodes = deltaHTMLEncoder.convert(delta);
    final children = processChildrenNodes(
      node.children.toList(),
      encodeParsers: encodeParsers,
    );
    if (children.isNotEmpty) {
      // `<p>` cannot hold blocks (the parser closes it), so a paragraph with children is a marked section:
      // the paragraph first, then its children. The decoder reads it back as a nested paragraph.
      final section = dom.Element.tag(HTMLTags.section)
        ..attributes[kNestedParagraphAttr] = '1'
        ..append(
          wrapChildrenNodesWithTagName(
            HTMLTags.paragraph,
            childNodes: domNodes.isEmpty ? [dom.Element.tag(HTMLTags.br)] : domNodes,
          ),
        );
      children.forEach(section.append);
      return [section];
    }
    if (domNodes.isEmpty) {
      return [dom.Element.tag(HTMLTags.br)];
    }
    final element =
        wrapChildrenNodesWithTagName(HTMLTags.paragraph, childNodes: domNodes);
    return [element];
  }
}
