import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

void main() {
  test('words added from a scan are one undo step', () async {
    final state = EditorState.blank(withInitialText: true);
    state.selection = Selection.collapsed(Position(path: [0], offset: 0));
    await state.insertTextAtCurrentSelection('Scanned words');
    expect(state.document.root.children.first.delta?.toPlainText(), 'Scanned words');
    state.undoManager.undo();
    expect(state.document.root.children.first.delta?.toPlainText() ?? '', '');
  });
}
