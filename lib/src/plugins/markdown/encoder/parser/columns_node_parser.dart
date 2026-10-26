import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// Markdown has no columns, so a columns block exports as its columns one after
/// the other, left to right, each separated by a blank line. No text is lost;
/// only the side-by-side layout is.
class ColumnsNodeParser extends NodeParser {
  const ColumnsNodeParser();

  @override
  String get id => ColumnsBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final parts = <String>[];
    for (final column in node.children) {
      final text = encoder?.convertNodes(column.children).trimRight() ?? '';
      if (text.isNotEmpty) parts.add(text);
    }
    return parts.isEmpty ? '' : '${parts.join('\n\n')}\n';
  }
}
