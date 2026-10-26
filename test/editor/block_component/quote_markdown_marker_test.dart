import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Future<EditorState> _stateWith(String text) async {
  final state = EditorState(
    document: Document.blank()..insert([0], [paragraphNode(text: text)]),
  );
  state.selection =
      Selection.collapsed(Position(path: [0], offset: text.length));
  return state;
}

void main() {
  test('"> " at the start of a line becomes a quote', () async {
    final state = await _stateWith('>');
    final handled = await formatDoubleQuoteToQuote.handler(state);
    expect(handled, isTrue);
    final node = state.getNodeAtPath([0])!;
    expect(node.type, QuoteBlockKeys.type);
    expect(node.delta!.toPlainText(), '');
  });

  test('the original double quote still works', () async {
    final state = await _stateWith('"');
    expect(await formatDoubleQuoteToQuote.handler(state), isTrue);
    expect(state.getNodeAtPath([0])!.type, QuoteBlockKeys.type);
  });

  test('a ">" in the middle of a line is left alone', () async {
    final state = await _stateWith('a>');
    expect(await formatDoubleQuoteToQuote.handler(state), isFalse);
    expect(state.getNodeAtPath([0])!.type, ParagraphBlockKeys.type);
  });
}
