import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// Every line ending a clipboard can carry (Windows, old Mac, Unicode separators).
final RegExp pasteLineBreak = RegExp(r'\r\n|[\r\n\u2028\u2029]');

/// A copied web page often arrives as ONE block whose text holds line breaks (`<br>`). Left
/// whole, converting it to a checklist or bullets makes a single row. Split it into one block
/// per line so each pasted line is its own row; children stay with the last line.
List<Node> splitLineBreaks(List<Node> nodes) {
  final out = <Node>[];
  for (final node in nodes) {
    final delta = node.delta;
    if (delta == null || !delta.toPlainText().contains(pasteLineBreak)) {
      out.add(node);
      continue;
    }
    final text = delta.toPlainText();
    var start = 0;
    final lines = <Delta>[];
    for (final m in pasteLineBreak.allMatches(text)) {
      lines.add(delta.slice(start, m.start));
      start = m.end;
    }
    lines.add(delta.slice(start));
    for (var i = 0; i < lines.length; i++) {
      final last = i == lines.length - 1;
      out.add(
        node.copyWith(
          children: last ? node.children.map((c) => c.deepCopy()) : const [],
          attributes: {
            ...node.attributes,
            blockComponentDelta: lines[i].toJson(),
            if (node.type == TodoListBlockKeys.type)
              TodoListBlockKeys.checked: false,
          },
        ),
      );
    }
  }
  return out;
}
