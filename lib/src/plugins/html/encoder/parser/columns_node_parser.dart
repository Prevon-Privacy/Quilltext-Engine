import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:html/dom.dart' as dom;

/// A columns block exports as a row of `div`s (`display:flex`), each column
/// sized by its width share.
class HTMLColumnsNodeParser extends HTMLNodeParser {
  const HTMLColumnsNodeParser();

  @override
  String get id => ColumnsBlockKeys.type;

  @override
  String transformNodeToHTMLString(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    assert(node.type == ColumnsBlockKeys.type);

    return toHTMLString(
      transformNodeToDomNodes(node, encodeParsers: encodeParsers),
    );
  }

  @override
  List<dom.Node> transformNodeToDomNodes(
    Node node, {
    required List<HTMLNodeParser> encodeParsers,
  }) {
    final columns = [
      for (final column in node.children)
        wrapChildrenNodesWithTagName(
          'div',
          childNodes: processChildrenNodes(
            column.children,
            encodeParsers: encodeParsers,
          ),
        )..attributes['style'] = 'flex:${columnWeightOf(column)}',
    ];
    final row = wrapChildrenNodesWithTagName('div', childNodes: columns)
      ..attributes['style'] = 'display:flex;gap:16px';
    return [row];
  }
}
