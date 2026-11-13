// Plain paragraphs indent like headings and lists (owner 2026-11-08, replacing the 2026-11-02 block).
// Moving one back out keeps the same gap to the paragraph above.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

double _top(EditorState s, List<int> p) {
  final box =
      s.getNodeAtPath(p)!.key.currentContext!.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero).dy;
}

double _bottom(EditorState s, List<int> p) {
  final box =
      s.getNodeAtPath(p)!.key.currentContext!.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset(0, box.size.height)).dy;
}

Future<EditorState> _pump(WidgetTester tester, List<Node> nodes) async {
  final s = EditorState(document: Document.blank()..insert([0], nodes));
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

void main() {
  testWidgets('a paragraph indents by swipe helper and Tab, and outdents with its gap',
      (tester) async {
    final s = await _pump(
        tester, [paragraphNode(text: 'above'), paragraphNode(text: 'below')]);
    final gapBefore = _top(s, [1]) - _bottom(s, [0]);
    s.selection = Selection.collapsed(Position(path: [1]));
    expect(isIndentable(s), isTrue);
    expect(tryIndentBlockNode(s, s.getNodeAtPath([1])!), isNotNull);
    await tester.pumpAndSettle();
    expect(s.document.root.children.length, 1);
    expect(s.getNodeAtPath([0, 0])!.type, ParagraphBlockKeys.type);
    expect(tryOutdentBlockNode(s, s.getNodeAtPath([0, 0])!), isNotNull);
    await tester.pumpAndSettle();
    expect(s.document.root.children.length, 2);
    expect(_top(s, [1]) - _bottom(s, [0]), gapBefore);
  });

  testWidgets('a list row still indents under a paragraph', (tester) async {
    final s = await _pump(
        tester, [paragraphNode(text: 'above'), bulletedListNode(text: 'item')]);
    expect(tryIndentBlockNode(s, s.getNodeAtPath([1])!), isNotNull);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(s.document.root.children.length, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('an already nested paragraph moves out and keeps its gap',
      (tester) async {
    final s = await _pump(tester, [
      paragraphNode(text: 'above'),
      paragraphNode(text: 'below'),
      paragraphNode(text: 'last'),
    ]);
    final gapBefore = _top(s, [1]) - _bottom(s, [0]);
    final lastBefore = _top(s, [2]);
    // An older note: 'below' already sits under 'above'.
    final t = s.transaction
      ..deleteNode(s.getNodeAtPath([1])!)
      ..insertNodes([0, 0], [paragraphNode(text: 'below')]);
    await s.apply(t);
    await tester.pumpAndSettle();
    expect(tryOutdentBlockNode(s, s.getNodeAtPath([0, 0])!), isNotNull);
    await tester.pumpAndSettle();
    expect(s.document.root.children.length, 3);
    expect(_top(s, [1]) - _bottom(s, [0]), gapBefore);
    expect(_top(s, [2]), lastBefore);
  });
}
