import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

const _tint = Color(0x1A00BCF0);

Node _quote(String text, {Iterable<Node>? children, String? bg}) => quoteNode(
      delta: Delta()..insert(text),
      attributes: {
        'delta': (Delta()..insert(text)).toJson(),
        if (bg != null) QuoteBlockKeys.backgroundColor: bg,
      },
      children: children,
    );

Future<void> _pump(WidgetTester tester, List<Node> nodes) async {
  tester.view.physicalSize = const Size(800, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = EditorState(document: Document.blank()..insert([0], nodes));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AppFlowyEditor(
        editorState: state,
        blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
        editorStyle: EditorStyle.desktop(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _tinted([Color color = _tint]) => find.byWidgetPredicate((w) =>
    w is Container &&
    w.decoration is BoxDecoration &&
    (w.decoration! as BoxDecoration).color == color);

void main() {
  testWidgets('short quote hugs its text, with trailing padding',
      (tester) async {
    await _pump(tester, [_quote('Hi')]);
    final box = tester.getSize(_tinted());
    final text = tester.getSize(find.byType(AppFlowyRichText));
    final editor = tester.getSize(find.byType(AppFlowyEditor));
    expect(box.width, lessThan(editor.width / 2));
    expect(box.width, greaterThanOrEqualTo(text.width + 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long wrapping quote fills the line and never overflows',
      (tester) async {
    await _pump(tester, [_quote('word ' * 120)]);
    final box = tester.getSize(_tinted());
    final editorRight = tester.getTopRight(find.byType(AppFlowyEditor)).dx;
    expect(tester.getTopRight(_tinted()).dx, lessThanOrEqualTo(editorRight));
    expect(box.height, greaterThan(60)); // wrapped to several lines
    expect(box.width, greaterThan(400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('indented (child of a list) quote stays inside its parent',
      (tester) async {
    final parent = bulletedListNode(
      delta: Delta()..insert('parent'),
      children: [_quote('nested quote'), _quote('long ' * 100)],
    );
    await _pump(tester, [_quote('top level'), parent]);
    final editorRight = tester.getTopRight(find.byType(AppFlowyEditor)).dx;
    expect(_tinted(), findsNWidgets(3));
    final topLeft = tester.getTopLeft(_tinted().at(0)).dx;
    for (var i = 1; i < 3; i++) {
      expect(tester.getTopLeft(_tinted().at(i)).dx, greaterThan(topLeft));
      expect(tester.getTopRight(_tinted().at(i)).dx,
          lessThanOrEqualTo(editorRight));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('quote with its own background color keeps it', (tester) async {
    await _pump(tester, [_quote('colored', bg: '0xFFFF0000')]);
    expect(_tinted(), findsNothing);
    expect(_tinted(const Color(0xFFFF0000)), findsOneWidget);
  });

  testWidgets('empty quote still renders without error', (tester) async {
    await _pump(tester, [_quote('')]);
    expect(_tinted(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
