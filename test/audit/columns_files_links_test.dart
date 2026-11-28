import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/util/link_util.dart';
import 'package:prevon_quilltext_engine/src/plugins/blocks/columns/column_width_resizer.dart';
import 'package:provider/provider.dart';

EditorState _columnsState(List<List<String>> cols) {
  return EditorState(
    document: Document.blank()
      ..insert([
        0
      ], [
        columnsNode(children: [
          for (final c in cols)
            columnNode(children: [for (final l in c) paragraphNode(text: l)]),
        ]),
      ]),
  );
}

EditorState _textState(Delta delta, int offset) {
  final state = EditorState(
    document: Document.blank()
      ..insert([
        0
      ], [
        Node(type: 'paragraph', attributes: {'delta': delta.toJson()}),
      ]),
  );
  state.selection = Selection.collapsed(Position(path: [0], offset: offset));
  return state;
}

class _Host implements NoteLinkNavigator, LinkEditor {
  _Host({this.choice, this.result});
  final LinkMenuChoice? choice;
  final LinkEditResult? result;
  @override
  void openNote(BuildContext context, String noteId) {}
  @override
  void openFolder(BuildContext context, String folderId) {}
  @override
  Future<LinkMenuChoice?> showLinkMenu(
          BuildContext context, LinkEditRequest request) async =>
      choice;
  @override
  Future<LinkEditResult?> editLink(
          BuildContext context, LinkEditRequest request) async =>
      result;
}

Future<EditorState> _pumpLink(WidgetTester tester, _Host host) async {
  final state = _textState(
    Delta()
      ..insert('he', attributes: {'href': 'https://x.y'})
      ..insert('llo', attributes: {'href': 'https://x.y', 'bold': true}),
    0,
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Provider<NoteLinkNavigator>.value(
        value: host,
        child: AppFlowyEditor(
          editorState: state,
          editorStyle: EditorStyle.mobile(),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return state;
}

Offset _centerOf(EditorState s, int a, int b) {
  final node = s.getNodeAtPath([0])!;
  final r = node.selectable!
      .getRectsInSelection(
          Selection.single(path: [0], startOffset: a, endOffset: b))
      .first;
  return node.renderBox!.localToGlobal(r.center);
}

List<TextInsert> _ops(EditorState s) =>
    s.getNodeAtPath([0])!.delta!.whereType<TextInsert>().toList();

void main() {
  test('1 moveColumn keeps the caret in the same column text', () {
    final s = _columnsState([
      ['A'],
      ['Bravo'],
      ['C'],
    ]);
    s.selection = Selection.collapsed(Position(path: [0, 1, 0], offset: 4));
    ColumnsActions.moveColumn(s.getNodeAtPath([0])!, 0, 2, s);
    expect(s.getNodeAtPath([0, 0, 0])!.delta!.toPlainText(), 'Bravo');
    expect(
        s.selection, Selection.collapsed(Position(path: [0, 0, 0], offset: 4)));
  });

  test('2 a later ")" never touches an earlier finished link', () {
    final s = _textState(Delta()..insert('see [a](b) and (note'), 20);
    expect(handleFormatMarkdownLinkToLink(editorState: s), isFalse);
    expect(s.getNodeAtPath([0])!.delta!.toPlainText(), 'see [a](b) and (note');
  });

  test('2b a link at the caret keeps the title formatting', () {
    final s = _textState(
      Delta()
        ..insert('[')
        ..insert('ab', attributes: {'bold': true})
        ..insert('](u'),
      6,
    );
    expect(handleFormatMarkdownLinkToLink(editorState: s), isTrue);
    final op = _ops(s).firstWhere((o) => o.text == 'ab');
    expect(op.attributes?['href'], 'u');
    expect(op.attributes?['bold'], true);
  });

  test('3 a file at the empty last paragraph leaves a paragraph to type in',
      () async {
    final s = EditorState(
      document: Document.blank()..insert([0], [paragraphNode()]),
    );
    s.selection = Selection.collapsed(Position(path: [0], offset: 0));
    await s.insertFileNode(url: 'u', name: 'n');
    final kids = s.document.root.children.toList();
    expect(kids.length, 2);
    expect(kids.first.type, FileBlockKeys.type);
    expect(kids.last.type, ParagraphBlockKeys.type);
    expect(s.selection?.start.path, [1]);
  });

  testWidgets('4 cancelling a width drag restores the widths, no undo step',
      (tester) async {
    final s = _columnsState([
      ['a'],
      ['b'],
    ]);
    final cols = s.getNodeAtPath([0])!;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          height: 100,
          child: ColumnWidthResizer(
            columns: cols,
            left: cols.children.first,
            right: cols.children.last,
            editorState: s,
            pixelsPerWeight: 100,
            editable: true,
          ),
        ),
      ),
    ));
    final g = await tester
        .startGesture(tester.getCenter(find.byType(ColumnWidthResizer)));
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(columnWeightOf(cols.children.first), isNot(closeTo(1, 0.001)));
    await g.cancel();
    await tester.pump();
    expect(columnWeightOf(cols.children.first), closeTo(1, 0.001));
    expect(columnWeightOf(cols.children.last), closeTo(1, 0.001));
    expect(s.undoManager.undoStack.isEmpty, isTrue);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('5 Remove link on one span removes the whole link',
      (tester) async {
    final state = await _pumpLink(tester, _Host(choice: LinkMenuChoice.remove));
    await tester.tapAt(_centerOf(state, 2, 5), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(_ops(state).every((o) => o.attributes?['href'] == null), isTrue);
  });

  testWidgets('5b editing the address changes the whole link, keeps bold',
      (tester) async {
    final state = await _pumpLink(
      tester,
      _Host(
        choice: LinkMenuChoice.edit,
        result: const LinkEditResult(text: 'hello', url: 'https://z.y'),
      ),
    );
    await tester.tapAt(_centerOf(state, 2, 5), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(state.getNodeAtPath([0])!.delta!.toPlainText(), 'hello');
    expect(_ops(state).every((o) => o.attributes?['href'] == 'https://z.y'),
        isTrue);
  });

  test('6 typed link addresses are trimmed and normalised', () {
    expect(normalizeTypedLink('  example.com '), startsWith('https://'));
    expect(normalizeTypedLink('http://a.com'), startsWith('http://a.com'));
    expect(normalizeTypedLink('   '), isNull);
    expect(normalizeTypedLink(''), isNull);
    expect(normalizeTypedLink('javascript:alert(1)'), isNull);
  });

  test('7 Backspace at an empty first block removes it, caret to the next', () {
    final s = _columnsState([
      ['', 'next'],
      ['b'],
    ]);
    s.selection = Selection.collapsed(Position(path: [0, 0, 0], offset: 0));
    final block = s.getNodeAtPath([0, 0, 0])!;
    expect(ColumnsActions.backspaceAtColumnStart(block, s), isTrue);
    expect(s.getNodeAtPath([0, 0])!.children.length, 1);
    expect(s.getNodeAtPath([0, 0, 0])!.delta!.toPlainText(), 'next');
    expect(
        s.selection, Selection.collapsed(Position(path: [0, 0, 0], offset: 0)));
  });

  test(
      '3b a file after a non-empty last paragraph leaves a paragraph with the caret',
      () async {
    final s = EditorState(
      document: Document.blank()..insert([0], [paragraphNode(text: 'x')]),
    );
    s.selection = Selection.collapsed(Position(path: [0], offset: 1));
    await s.insertFileNode(url: 'u', name: 'n');
    final kids = s.document.root.children.toList();
    expect(kids.map((k) => k.type).toList(), [
      ParagraphBlockKeys.type,
      FileBlockKeys.type,
      ParagraphBlockKeys.type,
    ]);
    expect(s.selection?.start.path, [2]);
  });

  test('3c a file in the middle of the note adds no extra paragraph', () async {
    final s = EditorState(
      document: Document.blank()
        ..insert([0], [paragraphNode(text: 'a'), paragraphNode(text: 'b')]),
    );
    s.selection = Selection.collapsed(Position(path: [0], offset: 1));
    await s.insertFileNode(url: 'u', name: 'n');
    final kids = s.document.root.children.toList();
    expect(kids.map((k) => k.type).toList(), [
      ParagraphBlockKeys.type,
      FileBlockKeys.type,
      ParagraphBlockKeys.type,
    ]);
    expect(kids.last.delta!.toPlainText(), 'b');
  });

  testWidgets('6b the link overlay trims and normalises, rejects a blank',
      (tester) async {
    final state = _textState(Delta()..insert('hello'), 0);
    state.selection = Selection.single(path: [0], startOffset: 0, endOffset: 5);
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return AppFlowyEditor(
            editorState: state,
            editorStyle: EditorStyle.mobile(),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    showLinkMenu(ctx, state, state.selection!, false);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_ops(state).every((o) => o.attributes?['href'] == null), isTrue);
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '  example.com ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_ops(state).first.attributes?['href'],
        startsWith('https://example.com'));
  });
}
