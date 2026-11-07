// A block keeps its stable id when it moves (indent, outdent) and gets a fresh one when it is copied
// (docs/design/block-ids-spec-2026-11-05.md).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

EditorState _state() => EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          bulletedListNode(text: 'one'),
          bulletedListNode(text: 'two'),
        ]),
    );

Future<void> _show(WidgetTester tester, EditorState state) async {
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
}

void main() {
  test('ids are well formed and unique per block', () {
    final s = _state();
    final ids = s.document.root.children.map((n) => n.id).toList();
    expect(ids.every(isBlockId), isTrue);
    expect(ids.toSet(), hasLength(ids.length));
  });

  testWidgets('indent keeps the block id; outdent keeps it again',
      (tester) async {
    final s = _state();
    await _show(tester, s);
    final two = s.getNodeAtPath([1])!;
    final id = two.id;

    final indented = tryIndentBlockNode(s, two);
    expect(indented, isNotNull);
    expect(indented!.id, id, reason: 'indent is a move, not a copy');
    expect(s.getNodeAtPath([0, 0])!.id, id);

    final outdented = tryOutdentBlockNode(s, s.getNodeAtPath([0, 0])!);
    expect(outdented, isNotNull);
    expect(outdented!.id, id);
    expect(s.getNodeAtPath([1])!.id, id);
    await tester
        .pump(const Duration(milliseconds: 100)); // the history seal timer
  });

  testWidgets('a moved block keeps the ids of its children', (tester) async {
    final s = EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          bulletedListNode(text: 'one'),
          bulletedListNode(text: 'two', children: [
            bulletedListNode(text: 'child'),
          ]),
        ]),
    );
    await _show(tester, s);
    final two = s.getNodeAtPath([1])!;
    final childId = two.children.first.id;
    final moved = tryIndentBlockNode(s, two)!;
    expect(moved.children.first.id, childId);
    await tester
        .pump(const Duration(milliseconds: 100)); // the history seal timer
  });

  test('a copy is a new block with a new id, children included', () {
    final s = EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          bulletedListNode(text: 'a', children: [
            bulletedListNode(text: 'b'),
          ]),
        ]),
    );
    final a = s.getNodeAtPath([0])!;
    final copy = a.copyWith();
    expect(copy.id, isNot(a.id));
    expect(copy.children.first.id, isNot(a.children.first.id));
    final same = a.copyWith(keepIds: true);
    expect(same.id, a.id);
    expect(same.children.first.id, a.children.first.id);
  });

  test('ids survive the stored form and the old form carries none', () {
    final s = _state();
    final stored = s.document.toJson(withIds: true);
    final back = Document.fromJson(stored);
    expect(back.root.children.map((n) => n.id),
        s.document.root.children.map((n) => n.id));
    expect(s.document.toJson().toString().contains('id:'), isFalse);
  });
}
