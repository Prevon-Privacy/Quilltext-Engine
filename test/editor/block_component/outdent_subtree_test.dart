// Outdent keeps the reading order: the rows below the outdented row must not be
// left behind above it (owner bug 2026-11-22), ids stay, selection follows.
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Node b(String t, [List<Node> kids = const []]) =>
    bulletedListNode(text: t, children: kids);

EditorState doc(List<Node> top) =>
    EditorState(document: Document.blank()..insert([0], top));

/// Depth-first "text@depth" reading of the whole document.
List<String> read(EditorState s) {
  final out = <String>[];
  void walk(Node n, int d) {
    out.add('${n.delta?.toPlainText()}@$d');
    for (final c in n.children) {
      walk(c, d + 1);
    }
  }

  for (final n in s.document.root.children) {
    walk(n, 0);
  }
  return out;
}

void main() {
  test('outdent with later siblings keeps order; they become its children', () {
    final s = doc([
      b('A', [
        b('B', [b('b1')]),
        b('C'),
      ]),
    ]);
    final idB = s.getNodeAtPath([0, 0])!.id;
    outdentBlocks(s, [s.getNodeAtPath([0, 0])!]);
    expect(read(s), ['A@0', 'B@0', 'b1@1', 'C@1']);
    expect(s.getNodeAtPath([1])!.id, idB);
  });

  test('outdent of a leaf with later siblings keeps their level under it', () {
    final s = doc([
      b('A', [b('x'), b('y'), b('z')]),
    ]);
    expect(outdentBlockNode(s, s.getNodeAtPath([0, 1])!), isTrue);
    expect(read(s), ['A@0', 'x@1', 'y@0', 'z@1']);
  });

  test('outdent of a multi-row run moves the run, later rows follow the last',
      () {
    final s = doc([
      b('A', [b('x'), b('y'), b('z'), b('w')]),
    ]);
    outdentBlocks(s, [s.getNodeAtPath([0, 1])!, s.getNodeAtPath([0, 2])!]);
    expect(read(s), ['A@0', 'x@1', 'y@0', 'z@0', 'w@1']);
  });

  test('last row that cannot hold children: later rows move out with it', () {
    final s = doc([
      b('A', [headingNode(level: 2, text: 'H'), b('y')]),
    ]);
    expect(outdentBlockNode(s, s.getNodeAtPath([0, 0])!), isTrue);
    expect(read(s), ['A@0', 'H@0', 'y@0']);
  });

  test('selection inside a moved row and an adopted row follows the text', () {
    final s = doc([
      b('A', [b('x'), b('y')]),
    ]);
    s.selection = Selection.collapsed(Position(path: [0, 1], offset: 1));
    outdentBlockNode(s, s.getNodeAtPath([0, 0])!);
    expect(read(s), ['A@0', 'x@0', 'y@1']);
    expect(s.selection!.start.path, [1, 0]);
  });

  test('Shift+Tab command uses the same outdent', () {
    final s = doc([
      b('A', [b('x'), b('y')]),
    ]);
    s.selection = Selection.collapsed(Position(path: [0, 0]));
    outdentCommand.execute(s);
    expect(read(s), ['A@0', 'x@0', 'y@1']);
  });
}
