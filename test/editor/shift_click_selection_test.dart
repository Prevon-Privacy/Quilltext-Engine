import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Future<EditorState> _pump(WidgetTester tester) async {
  final state = EditorState(
    document: Document.blank()
      ..insert([
        0,
      ], [
        Node(
          type: 'paragraph',
          attributes: {
            'delta':
                (Delta()..insert('alpha beta gamma delta epsilon')).toJson(),
          },
        ),
      ]),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: state,
          editorStyle: EditorStyle.desktop(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Offset _at(EditorState state, int offset) {
  final node = state.getNodeAtPath([0])!;
  final rect = node.selectable!
      .getRectsInSelection(
        Selection.single(path: [0], startOffset: offset, endOffset: offset + 1),
      )
      .first;
  return node.renderBox!.localToGlobal(rect.center);
}

void main() {
  testWidgets('shift+click extends from the live selection anchor',
      (tester) async {
    final state = await _pump(tester);
    // A keyboard-style move: the last tap/drag start is now stale.
    await tester.tapAt(_at(state, 2));
    await tester.pump(const Duration(milliseconds: 600));
    state.selection = Selection.collapsed(Position(path: [0], offset: 20));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(_at(state, 6));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    final sel = state.selection!;
    expect(sel.start.offset, 20);
    expect(sel.end.offset, inInclusiveRange(6, 7));
  });

  testWidgets('shift+click twice keeps the same anchor', (tester) async {
    final state = await _pump(tester);
    await tester.tapAt(_at(state, 3));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(_at(state, 12));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tapAt(_at(state, 25));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    final sel = state.selection!;
    expect(sel.start.offset, inInclusiveRange(3, 4));
    expect(sel.end.offset, inInclusiveRange(25, 26));
  });

  testWidgets('plain click without shift still collapses', (tester) async {
    final state = await _pump(tester);
    await tester.tapAt(_at(state, 3));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tapAt(_at(state, 15));
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.selection!.isCollapsed, isTrue);
  });
}
