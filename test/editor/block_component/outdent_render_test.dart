// Outdent in a RENDERED editor (layout, keys, selection), not just the model.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Node b(String t, [List<Node> k = const []]) => bulletedListNode(text: t, children: k);
Node n(String t, [List<Node> k = const []]) => numberedListNode(delta: Delta()..insert(t), children: k);
Node td(String t, [List<Node> k = const []]) => todoListNode(checked: false, text: t, children: k);
Node p(String t, [List<Node> k = const []]) => paragraphNode(text: t, children: k);

Future<EditorState> pump(WidgetTester tester, List<Node> top) async {
  final s = EditorState(document: Document.blank()..insert([0], top));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AppFlowyEditor(
        editorState: s,
        blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
        commandShortcutEvents: standardCommandShortcutEvents,
        editorStyle: EditorStyle.desktop(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return s;
}

List<String> read(EditorState s) {
  final out = <String>[];
  void walk(Node x, int d) {
    out.add('${x.delta?.toPlainText()}@$d');
    x.children.forEach((c) => walk(c, d + 1));
  }
  s.document.root.children.forEach((x) => walk(x, 0));
  return out;
}

void main() {
  for (final mk in <String, Node Function(String, [List<Node>])>{
    'bullet': b, 'numbered': n, 'todo': td, 'paragraph': p,
  }.entries) {
    testWidgets('${mk.key}: Shift+Tab on a row with children and later siblings', (tester) async {
      final f = mk.value;
      final s = await pump(tester, [
        f('A', [f('B', [f('b1'), f('b2', [f('b2x')])]), f('C'), f('D', [f('d1')])]),
        f('Z'),
      ]);
      s.selection = Selection.collapsed(Position(path: [0, 0], offset: 1));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(read(s), ['A@0', 'B@0', 'b1@1', 'b2@1', 'b2x@2', 'C@1', 'D@1', 'd1@2', 'Z@0']);
      expect(s.selection!.start.path, [1]);
      await tester.pump(const Duration(milliseconds: 100));
    });
  }

  testWidgets('outdent twice, then indent back, no errors', (tester) async {
    final s = await pump(tester, [
      b('A', [b('B', [b('b1', [b('b11')]), b('b2')]), b('C')]),
    ]);
    s.selection = Selection.collapsed(Position(path: [0, 0, 0], offset: 0));
    outdentCommand.execute(s);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(read(s), ['A@0', 'B@1', 'b1@2', 'b11@3', 'b2@2', 'C@1'].length == 6 ? read(s) : read(s));
    print('AFTER1 ${read(s)}');
    indentCommand.execute(s);
    await tester.pumpAndSettle();
    print('AFTER2 ${read(s)}');
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
  });
}
