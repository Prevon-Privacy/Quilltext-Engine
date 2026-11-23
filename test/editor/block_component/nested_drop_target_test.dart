// A nested row can be dropped below the last nested row and at the end of the
// note; the pointer's x picks the level (owner bug 2026-11-22).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Node b(String t, [List<Node> kids = const []]) =>
    bulletedListNode(text: t, children: kids);

Future<EditorState> pump(WidgetTester tester, List<Node> top) async {
  final s = EditorState(document: Document.blank()..insert([0], top));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AppFlowyEditor(
        editorState: s,
        blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
        editorStyle: EditorStyle.desktop(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return s;
}

Offset bottomLeft(EditorState s, Path p) {
  final box =
      s.getNodeAtPath(p)!.key.currentContext!.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset(0, box.size.height));
}

List<String> read(EditorState s) {
  final out = <String>[];
  void walk(Node n, int d) {
    out.add('${n.delta?.toPlainText()}@$d');
    n.children.forEach((c) => walk(c, d + 1));
  }

  s.document.root.children.forEach((n) => walk(n, 0));
  return out;
}

void main() {
  testWidgets('below the whole note resolves to the end of the root',
      (tester) async {
    final s = await pump(tester, [
      b('A', [b('x'), b('y')]),
      b('z'),
    ]);
    final y = s.getNodeAtPath([0, 1])!;
    final end = bottomLeft(s, [1]) + const Offset(400, 60);
    final drop = resolveReorderDrop(s, y, end)!;
    expect(drop.target, [2]);
    moveBlockTo(s, y, drop.target);
    expect(read(s), ['A@0', 'x@1', 'z@0', 'y@0']);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('x picks the level after the last nested row', (tester) async {
    final s = await pump(tester, [
      b('A', [b('x'), b('y')]),
    ]);
    final x = s.getNodeAtPath([0, 0])!;
    final below = bottomLeft(s, [0, 1]).dy - 4;
    final left = resolveReorderDrop(s, x, Offset(0, below))!;
    expect(left.target, [1], reason: 'far left leaves the group');
    final deep = resolveReorderDrop(s, x, Offset(700, below))!;
    expect(deep.target, [0, 2], reason: 'far right stays in the group');
    moveBlockTo(s, x, left.target);
    expect(read(s), ['A@0', 'y@1', 'x@0']);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a row cannot drop inside its own subtree', (tester) async {
    final s = await pump(tester, [
      b('A', [b('x')]),
      b('z'),
    ]);
    final a = s.getNodeAtPath([0])!;
    expect(moveBlockTo(s, a, [0, 1]), isNull);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Move down on the last nested row leaves the group',
      (tester) async {
    final s = await pump(tester, [
      b('A', [b('x'), b('y')]),
      b('z'),
    ]);
    s.selection = Selection.collapsed(Position(path: [0, 1]));
    expect(canMoveRows(s, up: false), isTrue);
    expect(moveRows(s, up: false), isTrue);
    expect(read(s), ['A@0', 'x@1', 'y@0', 'z@0']);
    await tester.pump(const Duration(milliseconds: 100));
  });
}
