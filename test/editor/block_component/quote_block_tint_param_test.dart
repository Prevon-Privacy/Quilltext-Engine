import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

const _custom = Color(0x1F0A8F7F);
const _default = Color(0x1A00BCF0);

Future<void> _pump(WidgetTester tester, {Color? tint}) async {
  tester.view.physicalSize = const Size(800, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = EditorState(
    document: Document.blank()
      ..insert([0], [quoteNode(delta: Delta()..insert('Hi'))]),
  );
  final builders = buildStandardBlockComponentBuilderMap();
  builders[QuoteBlockKeys.type] = QuoteBlockComponentBuilder(tint: tint);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AppFlowyEditor(
        editorState: state,
        blockComponentBuilders: builders,
        editorStyle: EditorStyle.desktop(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _washed(Color c) => find.byWidgetPredicate((w) =>
    w is Container &&
    w.decoration is BoxDecoration &&
    (w.decoration! as BoxDecoration).color == c);

void main() {
  testWidgets('a host tint replaces the default cyan wash', (tester) async {
    await _pump(tester, tint: _custom);
    expect(_washed(_custom), findsOneWidget);
    expect(_washed(_default), findsNothing);
  });

  testWidgets('no tint keeps the original cyan wash', (tester) async {
    await _pump(tester);
    expect(_washed(_default), findsOneWidget);
  });
}
