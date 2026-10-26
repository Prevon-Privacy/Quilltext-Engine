// A block moved by drag is ONE undo step whose undo restores the exact original order, with the
// document rule that keeps a paragraph beside every non-text block switched on (as in the app).
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

String _tag(Node n) => n.type == 'paragraph'
    ? (n.delta?.toPlainText() ?? '')
    : n.attributes['name']?.toString() ?? n.type;
List<String> _order(EditorState s) => [for (final n in s.document.root.children) _tag(n)];

Future<EditorState> _build(List<String> spec) async {
  final doc = Document.blank()
    ..insert([0], [
      for (final x in spec)
        x.startsWith('f:')
            ? Node(type: 'file', attributes: {'url': 'x', 'name': x})
            : paragraphNode(text: x),
    ]);
  final s = EditorState(document: doc);
  s.documentRules = const [SurroundNonTextBlocksRule()];
  await SurroundNonTextBlocksRule.normalize(s); // a note is normalised when it loads
  return s;
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  // Guarded layouts, as the app holds them: a paragraph beside every file block.
  final layouts = <String, List<String>>{
    'three': ['A', 'B', 'f:one'],
    'five': ['A', 'f:one', 'B', 'C', 'f:two'],
  };
  layouts.forEach((label, spec) {
    for (var from = 0; from < spec.length; from++) {
      for (var to = 0; to <= spec.length; to++) {
        if (to == from || to == from + 1) continue;
        test('$label: move $from -> slot $to, one undo restores the exact order', () async {
          final s = await _build(spec);
          final original = _order(s);
          final node = s.document.root.children[from];
          if (!moveNodeAmongSiblings(s, node, to)) return;
          await _settle();
          final moved = _order(s);
          // The block lands in the gap the drop line showed (a slot in the PRE-move list), guards aside.
          final expected = [...original];
          final tag = expected.removeAt(from);
          expected.insert(to > from ? to - 1 : to, tag);
          expect(moved.where((e) => e.isNotEmpty).toList(), expected.where((e) => e.isNotEmpty).toList(),
              reason: 'the block landed in the dropped slot');
          s.undoManager.undo();
          await _settle();
          expect(_order(s), original, reason: 'undo restores the exact original order');
          expect(s.undoManager.undoStack.isNonEmpty, isFalse, reason: 'the move was ONE history item');
          s.undoManager.redo();
          await _settle();
          expect(_order(s), moved, reason: 'redo repeats the move');
        });
      }
    }
  });
}
