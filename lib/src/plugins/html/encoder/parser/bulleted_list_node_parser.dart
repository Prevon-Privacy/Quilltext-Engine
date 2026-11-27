import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:html/dom.dart' as dom;

class HTMLBulletedListNodeParser extends HTMLNodeParser {
  const HTMLBulletedListNodeParser();

  @override
  String get id => BulletedListBlockKeys.type;

  @override
  String transformNodeToHTMLString(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    assert(node.type == BulletedListBlockKeys.type);

    final html = toHTMLString(
      transformNodeToDomNodes(node, encodeParsers: encodeParsers),
    );

    const start = '<ul>';
    const end = '</ul>';
    if (node.previous?.type != BulletedListBlockKeys.type &&
        node.next?.type != BulletedListBlockKeys.type) {
      return '$start$html$end';
    } else if (node.previous?.type != BulletedListBlockKeys.type) {
      return '$start$html';
    } else if (node.next?.type != BulletedListBlockKeys.type) {
      return '$html$end';
    } else {
      return html;
    }
  }

  @override
  List<dom.Node> transformNodeToDomNodes(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    final delta = node.delta ?? Delta();
    final domNodes = deltaHTMLEncoder.convert(delta);
    domNodes.addAll(
      processListChildrenNodes(
        this,
        node.children,
        encodeParsers: encodeParsers,
      ),
    );
    final element = wrapChildrenNodesWithTagName(
      HTMLTags.list,
      childNodes: domNodes,
    );
    return [element];
  }
}

/// The children of a list item as DOM nodes. A run of child list items gets its own `<ul>` / `<ol>`: a bare `<li>`
/// inside an `<li>` is closed by an HTML parser and the child comes back one level too shallow.
List<dom.Node> processListChildrenNodes(
  HTMLNodeParser parser,
  Iterable<Node> children, {
  required List<HTMLNodeParser> encodeParsers,
}) {
  final result = <dom.Node>[];
  dom.Element? run;
  String? runType;
  for (final child in children) {
    final isBullet = child.type == BulletedListBlockKeys.type;
    final isNumbered = child.type == NumberedListBlockKeys.type;
    final items = parser.processChildrenNodes([child], encodeParsers: encodeParsers);
    if (!isBullet && !isNumbered) {
      run = null;
      runType = null;
      result.addAll(items);
      continue;
    }
    if (run == null || runType != child.type) {
      final number = child.attributes[NumberedListBlockKeys.number];
      run = dom.Element.tag(isBullet ? HTMLTags.unorderedList : HTMLTags.orderedList);
      if (isNumbered && number != null) run.attributes['start'] = '$number';
      runType = child.type;
      result.add(run);
    }
    items.forEach(run.append);
  }
  return result;
}
