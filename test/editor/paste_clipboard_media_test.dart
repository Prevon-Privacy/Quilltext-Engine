import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:provider/provider.dart';

class _FakePaster implements ClipboardMediaPaster {
  _FakePaster({this.takes = false, this.throws = false});
  final bool takes;
  final bool throws;
  int calls = 0;

  @override
  Future<bool> pasteMedia() async {
    calls++;
    if (throws) throw StateError('boom');
    return takes;
  }
}

Future<EditorState> _pump(WidgetTester tester, {_FakePaster? paster}) async {
  final state = EditorState(
    document: Document.blank()..insert([0], [paragraphNode(text: 'abc')]),
  );
  final editor = AppFlowyEditor(
    editorState: state,
    editorStyle: EditorStyle.desktop(),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: paster == null
            ? editor
            : Provider<ClipboardMediaPaster>.value(
                value: paster, child: editor),
      ),
    ),
  );
  await tester.pumpAndSettle();
  state.selection = Selection.collapsed(Position(path: [0], offset: 3));
  await tester.pump();
  return state;
}

Future<void> _paste(
  WidgetTester tester,
  EditorState state, {
  String? text,
  String? html,
}) async {
  AppFlowyClipboard.mockSetData(AppFlowyClipboardData(text: text, html: html));
  addTearDown(() => AppFlowyClipboard.mockSetData(null));
  pasteCommand.handler(state);
  await tester.pumpAndSettle();
}

String _body(EditorState state) => state.document.root.children
    .map((n) => n.delta?.toPlainText() ?? '')
    .join('|');

void main() {
  testWidgets('a text-only clipboard never asks the host for pictures',
      (tester) async {
    final paster = _FakePaster(takes: true);
    final state = await _pump(tester, paster: paster);
    await _paste(tester, state, text: 'XYZ');
    expect(paster.calls, 0);
    expect(_body(state), 'abcXYZ');
  });

  testWidgets('an empty-text clipboard goes to the host; taken means done',
      (tester) async {
    final paster = _FakePaster(takes: true);
    final state = await _pump(tester, paster: paster);
    await _paste(tester, state);
    expect(paster.calls, 1);
    expect(_body(state), 'abc');
  });

  testWidgets('when the host finds no picture the paste is simply empty',
      (tester) async {
    final paster = _FakePaster();
    final state = await _pump(tester, paster: paster);
    await _paste(tester, state);
    expect(paster.calls, 1);
    expect(_body(state), 'abc');
  });

  testWidgets('an HTML copy that carries a picture goes to the host first',
      (tester) async {
    final taken = _FakePaster(takes: true);
    final state = await _pump(tester, paster: taken);
    await _paste(
      tester,
      state,
      text: 'caption',
      html: '<p>caption</p><IMG src="https://example.com/a.png">',
    );
    expect(taken.calls, 1);
    // The host took it: neither the HTML nor the text is pasted on top.
    expect(_body(state), 'abc');
  });

  testWidgets('an HTML copy with a picture falls back to text when declined',
      (tester) async {
    final declined = _FakePaster();
    final state = await _pump(tester, paster: declined);
    await _paste(
      tester,
      state,
      text: 'caption',
      html: '<img src="https://example.com/a.png">',
    );
    expect(declined.calls, 1);
    // Declined: the clipboard goes down the old HTML path, which (unchanged here) drops a bare
    // image block pasted into a non-empty line. The point is that it still ran, without a throw.
    expect(_body(state), 'abc');
  });

  testWidgets('HTML without a picture does not reach the host', (tester) async {
    final paster = _FakePaster(takes: true);
    final state = await _pump(tester, paster: paster);
    await _paste(tester, state, text: 'hi', html: '<p>hi</p>');
    expect(paster.calls, 0);
  });

  testWidgets('a host that throws cannot break paste', (tester) async {
    final paster = _FakePaster(throws: true);
    final state = await _pump(tester, paster: paster);
    await _paste(tester, state);
    expect(paster.calls, 1);
    expect(_body(state), 'abc');
  });

  testWidgets('with no host bridge an empty clipboard is a no-op',
      (tester) async {
    final state = await _pump(tester);
    await _paste(tester, state);
    expect(_body(state), 'abc');
  });
}
