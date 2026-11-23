// A text field inside the editor (the note title) keeps Backspace and Delete: the body's stale selection
// used to take the key, so selected title text never went away.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

void main() {
  for (final key in [LogicalKeyboardKey.backspace, LogicalKeyboardKey.delete]) {
    testWidgets('${key.keyLabel} deletes selected text in a header field',
        (tester) async {
      final s = EditorState(
        document: Document.blank()..insert([0], [paragraphNode(text: 'body')]),
      )..disableSealTimer = true;
      s.selection = Selection.collapsed(Position(path: [0], offset: 2));
      final title = TextEditingController(text: 'hello');
      final focus = FocusNode();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: s,
            editorStyle: EditorStyle.desktop(),
            header: TextField(controller: title, focusNode: focus),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pump();
      title.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(title.text, '');
      expect(s.getNodeAtPath([0])!.delta!.toPlainText(), 'body');
    });
  }
}
