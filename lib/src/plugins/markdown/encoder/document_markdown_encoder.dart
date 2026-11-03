import 'dart:convert';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:collection/collection.dart';

class DocumentMarkdownEncoder extends Converter<Document, String> {
  DocumentMarkdownEncoder({
    this.parsers = const [],
    this.lineBreak = '',
  });

  final List<NodeParser> parsers;
  final String lineBreak;

  @override
  String convert(Document input) {
    final buffer = StringBuffer();
    Node? previous;
    for (final node in input.root.children) {
      NodeParser? parser = parsers.firstWhereOrNull(
        (element) => element.id == node.type,
      );
      if (parser != null) {
        final text = parser.transform(node, this);
        // Markdown ends a paragraph, a quote or a list item only at a blank line: without one, a
        // paragraph under a list or quote is swallowed by it and two quotes become one. An explicit
        // [lineBreak] is the caller's own choice and is kept as it was.
        if (lineBreak.isEmpty &&
            previous != null &&
            text.isNotEmpty &&
            !_keepsTight(previous, node)) {
          final soFar = buffer.toString();
          if (soFar.isNotEmpty && soFar.endsWith('\n') && !soFar.endsWith('\n\n')) {
            buffer.write('\n');
          }
        }
        buffer.write(text);
        if (text.isNotEmpty) previous = node;
        if (lineBreak.isNotEmpty && node.id != input.root.children.last.id) {
          buffer.write(lineBreak);
        }
      }
    }
    return buffer.toString();
  }

  static const _listTypes = {
    BulletedListBlockKeys.type,
    NumberedListBlockKeys.type,
    TodoListBlockKeys.type,
  };

  /// Two neighbouring items of one list stay on consecutive lines (a blank line would turn the list
  /// "loose"); a bullet and a to-do share the same `*` marker family.
  static bool _keepsTight(Node a, Node b) {
    if (!_listTypes.contains(a.type) || !_listTypes.contains(b.type)) return false;
    if (a.type == b.type) return true;
    return a.type != NumberedListBlockKeys.type && b.type != NumberedListBlockKeys.type;
  }

  String convertNodes(
    List<Node> nodes, {
    bool withIndent = false,
  }) {
    final result = convert(Document(root: pageNode(children: nodes)));
    if (result.isNotEmpty && withIndent) {
      return result
          .split('\n')
          .map((e) => e.isNotEmpty ? '\t$e' : e)
          .join('\n');
    }
    return result;
  }
}
