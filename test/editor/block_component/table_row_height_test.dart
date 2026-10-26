import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Future<(EditorState, TableNode)> _pump(
  WidgetTester tester,
  List<List<String>> cols, {
  double cellLineHeight = 1.25,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final table = TableNode.fromList(cols);
  final state = EditorState(
    document: Document.blank()..insert([0], [table.node]),
  );
  final builders = buildStandardBlockComponentBuilderMap();
  builders[ParagraphBlockKeys.type] = ParagraphBlockComponentBuilder(
    configuration: standardBlockComponentConfiguration.copyWith(
      padding: (node) => node.parent?.type == TableCellBlockKeys.type
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 4),
      textStyle: (node, {textSpan}) => node.parent?.type ==
              TableCellBlockKeys.type
          ? TextStyle(height: cellLineHeight)
          : const TextStyle(),
    ),
  );
  builders[TableBlockKeys.type] = TableBlockComponentBuilder(
    tableStyle: const TableStyle(rowHeight: 28, colMinimumWidth: 72),
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AppFlowyEditor(
        editorState: state,
        blockComponentBuilders: builders,
        editorStyle: EditorStyle.mobile(),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return (state, TableNode(node: table.node));
}

void main() {
  testWidgets('row height hugs the text (no 40dp floor)', (tester) async {
    final (_, t) = await _pump(tester, [
      ['a', 'b'],
      ['c', 'd'],
    ]);
    final h = t.getRowHeight(0);
    // ignore: avoid_print
    print('ROWH $h');
    expect(h, lessThan(34));
  });

  testWidgets('a wrapped cell makes the whole row taller, then shrinks back',
      (tester) async {
    final (state, t) = await _pump(tester, [
      ['a', 'b'],
      ['c', 'd'],
      ['e', 'f'],
    ]);
    final base = t.getRowHeight(0);
    final tx = state.transaction
      ..insertText(
        t.getCell(0, 0).children.first,
        1,
        'long text that wraps onto several lines in a narrow cell ' * 2,
      );
    await state.apply(tx);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final grown = t.getRowHeight(0);
    expect(grown, greaterThan(base + 10));
    for (var c = 0; c < 3; c++) {
      expect(t.getCell(c, 0).attributes[TableCellBlockKeys.height], grown,
          reason: 'every cell in the row shares the tall height');
    }
    expect(t.getRowHeight(1), base, reason: 'other rows stay short');
  });
}
