import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

void main() {
  testWidgets('wide table shrinks to fit a phone width without scrolling',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final table = TableNode.fromList([
      ['a', 'b'],
      ['c', 'd'],
      ['e', 'f'],
    ]);
    final state = EditorState(
      document: Document.blank()..insert([0], [table.node]),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: state,
          blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
          editorStyle: EditorStyle.mobile(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final scroll = tester.state<ScrollableState>(find
        .descendant(
          of: find.byType(TableBlockComponentWidget),
          matching: find.byType(Scrollable),
        )
        .first);
    expect(scroll.position.maxScrollExtent, 0);
  });
}
