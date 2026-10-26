import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// A collapsible exports as a `<details>` block (GitHub and most markdown
/// viewers fold it), so the hidden body is never dropped from an export.
class CollapsibleNodeParser extends NodeParser {
  const CollapsibleNodeParser();

  @override
  String get id => CollapsibleBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final delta = node.delta ?? Delta()
      ..insert('');
    final title = DeltaMarkdownEncoder().convert(delta);
    final open = node.attributes[CollapsibleBlockKeys.collapsed] == true
        ? ''
        : ' open';
    final children = encoder?.convertNodes(node.children);
    final body = (children == null || children.isEmpty)
        ? ''
        : '\n${children.trimRight()}\n';
    return '<details$open>\n<summary>$title</summary>\n$body\n</details>\n';
  }
}
