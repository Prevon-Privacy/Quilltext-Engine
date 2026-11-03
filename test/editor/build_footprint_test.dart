// How much the page builds. Every built block is live (selection and find
// listeners, keep-alive, text layout), so the page builds only a little past
// the viewport (EditorScrollController.cacheScreens, half a screen) and a block carries no
// remote-selection layers unless the host turns them on (PATCH 33).
// Before the patch: 300 paragraphs in a 900x1600 view built 200 blocks and
// 11047 widgets (docs/guides/editor-performance.md).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

EditorState _note(int blocks, {bool remote = false}) {
  return EditorState(
    document: Document.blank()
      ..insert([
        0
      ], [
        for (var i = 0; i < blocks; i++)
          paragraphNode(text: 'Paragraph $i with some words to lay out.'),
      ]),
  )
    ..disableSealTimer = true
    ..enableRemoteSelections = remote;
}

Future<({int blocks, int elements, int visible})> _pump(
  WidgetTester tester, {
  bool remote = false,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AppFlowyEditor(editorState: _note(300, remote: remote)),
    ),
  ));
  await tester.pumpAndSettle();
  var elements = 0;
  void count(Element e) {
    elements++;
    e.visitChildren(count);
  }

  tester.binding.rootElement!.visitChildren(count);
  final built = find
      .byType(ParagraphBlockComponentWidget, skipOffstage: false)
      .evaluate();
  final visible = built.where((e) {
    final box = e.renderObject! as RenderBox;
    final y = box.localToGlobal(Offset.zero).dy;
    return y >= 0 && y < 1600;
  }).length;
  return (blocks: built.length, elements: elements, visible: visible);
}

void main() {
  testWidgets('the page builds half a screen past the viewport, not two',
      (tester) async {
    final r = await _pump(tester);
    debugPrint('FOOTPRINT blocks=${r.blocks} visible=${r.visible} '
        'elements=${r.elements}');
    // 100 of 300 at a half-screen buffer; the old two-screen buffer built 200.
    expect(r.blocks, lessThan(r.visible * 1.8));
    expect(r.elements, lessThan(6500));
  });

  testWidgets('a block carries no remote-selection layer by default',
      (tester) async {
    final off = await _pump(tester);
    await tester.pumpWidget(const SizedBox());
    final on = await _pump(tester, remote: true);
    debugPrint('FOOTPRINT off=${off.elements}/${off.blocks} '
        'on=${on.elements}/${on.blocks}');
    expect(off.elements / off.blocks, lessThan(on.elements / on.blocks - 4));
  });

  testWidgets('scrolling still builds the blocks that arrive', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppFlowyEditor(editorState: _note(300))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Paragraph 150 ', findRichText: true),
        findsNothing);
    await tester.drag(find.byType(AppFlowyEditor), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Paragraph 0 ', findRichText: true), findsNothing);
    expect(
        find
            .byType(ParagraphBlockComponentWidget, skipOffstage: false)
            .evaluate(),
        isNotEmpty);
  });
}
