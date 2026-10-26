import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/ime/delta_input_on_replace_impl.dart';

/// Gboard sends "Enter while a word is still composing" as a REPLACEMENT of the
/// composing word with "word\n", not as a bare "\n" insertion.
Future<EditorState> _enterAfterWord(
  WidgetTester tester,
  String type,
  String word,
) async {
  final state = EditorState(
    document: Document.blank()
      ..insert([0], [
        Node(type: type, attributes: {
          'delta': (Delta()..insert(word)).toJson(),
          if (type == 'todo_list') 'checked': false,
        }),
      ]),
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: AppFlowyEditor(editorState: state)),
  ));
  await tester.pumpAndSettle();
  state.selection =
      Selection.collapsed(Position(path: [0], offset: word.length));
  await tester.pumpAndSettle();

  await onReplace(
    TextEditingDeltaReplacement(
      oldText: word,
      replacementText: '$word\n',
      replacedRange: TextRange(start: 0, end: word.length),
      selection: TextSelection.collapsed(offset: word.length + 1),
      composing: TextRange.empty,
    ),
    state,
    standardCharacterShortcutEvents,
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  for (final type in ['bulleted_list', 'numbered_list', 'todo_list', 'paragraph']) {
    testWidgets('Enter after a composing word starts a new $type block',
        (tester) async {
      final state = await _enterAfterWord(tester, type, 'alpha');
      final blocks = state.document.root.children;
      expect(blocks.length, 2, reason: 'a new block, not a soft line break');
      expect(blocks.first.delta!.toPlainText(), 'alpha');
      expect(blocks.first.delta!.toPlainText().contains('\n'), isFalse);
      expect(blocks.last.type, type,
          reason: 'the new block continues the same list type');
      expect(blocks.last.delta!.toPlainText(), isEmpty);
    });
  }

  testWidgets('a replacement that is NOT an Enter is left alone', (tester) async {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [
          Node(type: 'paragraph', attributes: {
            'delta': (Delta()..insert('helo')).toJson(),
          }),
        ]),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppFlowyEditor(editorState: state)),
    ));
    await tester.pumpAndSettle();
    state.selection = Selection.collapsed(Position(path: [0], offset: 4));
    await onReplace(
      TextEditingDeltaReplacement(
        oldText: 'helo',
        replacementText: 'hello',
        replacedRange: const TextRange(start: 0, end: 4),
        selection: const TextSelection.collapsed(offset: 5),
        composing: TextRange.empty,
      ),
      state,
      standardCharacterShortcutEvents,
    );
    await tester.pumpAndSettle();
    expect(state.document.root.children.length, 1);
    expect(state.document.root.children.first.delta!.toPlainText(), 'hello');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
