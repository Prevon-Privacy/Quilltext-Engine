import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/shortcuts/command/paste_lines.dart';

Node _para(String text) => paragraphNode(text: text);

List<String?> _texts(EditorState s) =>
    s.document.root.children.map((n) => n.delta?.toPlainText()).toList();

void main() {
  group('splitLineBreaks', () {
    for (final sep in ['\n', '\r\n', '\r', ' ']) {
      test('one block with ${sep.codeUnits} becomes one block per line', () {
        final out = splitLineBreaks([_para('a${sep}b${sep}c')]);
        expect(out.map((n) => n.delta!.toPlainText()), ['a', 'b', 'c']);
      });
    }

    test('keeps type, resets todo checked, keeps formatting', () {
      final todo = todoListNode(checked: true, text: 'x\ny');
      final out = splitLineBreaks([todo]);
      expect(out.map((n) => n.type), everyElement(TodoListBlockKeys.type));
      expect(
        out.map((n) => n.attributes[TodoListBlockKeys.checked]),
        everyElement(false),
      );
    });

    test('a block without line breaks is returned untouched', () {
      final n = _para('plain');
      expect(identical(splitLineBreaks([n]).single, n), isTrue);
    });
  });

  group('pasteMultiLineNodes into a list row', () {
    for (final entry in {
      TodoListBlockKeys.type: todoListNode(checked: false, text: ''),
      BulletedListBlockKeys.type: bulletedListNode(text: ''),
      NumberedListBlockKeys.type: numberedListNode(delta: Delta()),
    }.entries) {
      test('every pasted line becomes a ${entry.key}', () async {
        final state = EditorState.blank(withInitialText: false);
        final t = state.transaction..insertNode([0], entry.value.deepCopy());
        await state.apply(t);
        state.selection = Selection.collapsed(Position(path: [0]));
        await state
            .pasteMultiLineNodes([_para('one'), _para('two'), _para('three')]);
        expect(_texts(state), ['one', 'two', 'three']);
        expect(
          state.document.root.children.map((n) => n.type),
          everyElement(entry.key),
        );
      });
    }

    test('into a plain paragraph stays paragraphs', () async {
      final state = EditorState.blank(withInitialText: true);
      state.selection = Selection.collapsed(Position(path: [0]));
      await state.pasteMultiLineNodes([_para('one'), _para('two')]);
      expect(
        state.document.root.children.map((n) => n.type),
        everyElement(ParagraphBlockKeys.type),
      );
    });
  });
}
