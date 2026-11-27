// Dragging a block over a table, a columns block or a folded block: the bottom
// half lands AFTER it (never "inside" cells or hidden rows), the top half before.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

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

Offset inside(EditorState s, Path p, {required double frac}) {
  final box =
      s.getNodeAtPath(p)!.key.currentContext!.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset(40, box.size.height * frac));
}

void main() {
  testWidgets('bottom half of a table drops after it, top half before it',
      (tester) async {
    final s = await pump(tester, [
      paragraphNode(text: 'mover'),
      TableNode.fromList([
        ['a', 'b'],
        ['c', 'd'],
      ]).node,
      paragraphNode(text: 'tail'),
    ]);
    final mover = s.getNodeAtPath([0])!;
    final low = resolveReorderDrop(s, mover, inside(s, [1], frac: 0.9));
    expect(low?.target, [2], reason: 'after the table, never inside a cell');
    final high = resolveReorderDrop(s, mover, inside(s, [1], frac: 0.05));
    expect(high?.target, [1]);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('bottom half of a folded block drops after it, not into it',
      (tester) async {
    final s = await pump(tester, [
      paragraphNode(text: 'mover'),
      bulletedListNode(text: 'F', children: [bulletedListNode(text: 'hid')]),
      paragraphNode(text: 'tail'),
    ]);
    s.apply(s.transaction
      ..updateNode(s.getNodeAtPath([1])!, {blockComponentCollapsed: true}));
    await tester.pumpAndSettle();
    final mover = s.getNodeAtPath([0])!;
    final low = resolveReorderDrop(s, mover, inside(s, [1], frac: 0.9));
    expect(low?.target, [2], reason: 'a drop inside a fold would be hidden');
    await tester.pump(const Duration(milliseconds: 100));
  });
}
