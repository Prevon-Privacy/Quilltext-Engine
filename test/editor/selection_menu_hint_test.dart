import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// Opens the slash menu through the real `/` shortcut handler (it inserts the
/// slash, then opens the menu — the same path typing `/` takes).
Future<EditorState> _typeSlash(
  WidgetTester tester, {
  String? hint = 'Type to search',
}) async {
  final state = EditorState(
    document: Document.blank()
      ..insert([0], [
        Node(type: 'paragraph', attributes: {
          'delta': Delta().toJson(),
        }),
      ]),
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: AppFlowyEditor(editorState: state)),
  ));
  await tester.pumpAndSettle();
  state.selection = Selection.collapsed(Position(path: [0], offset: 0));
  await tester.pumpAndSettle();

  final slash = customSlashCommand(
    standardSelectionMenuItems,
    searchHint: hint,
  );
  await slash.handler(state);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return state;
}

void main() {
  testWidgets('shows the hint right after the slash, hides it once typing',
      (tester) async {
    final state = await _typeSlash(tester);
    expect(find.byType(SelectionMenuWidget), findsOneWidget);
    expect(find.text('Type to search'), findsOneWidget);

    final node = state.getNodeAtPath([0])!;
    await state.apply(state.transaction..insertText(node, 1, 'h'));
    state.selection = Selection.collapsed(Position(path: [0], offset: 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Type to search'), findsNothing,
        reason: 'the hint is only for the empty-filter state');

    // close the menu so the next test starts clean
    await tester.tapAt(const Offset(700, 500));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('no hint text when none is configured', (tester) async {
    await _typeSlash(tester, hint: null);
    expect(find.byType(SelectionMenuWidget), findsOneWidget);
    expect(find.text('Type to search'), findsNothing);
    await tester.tapAt(const Offset(700, 500));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('holds editor focus while the menu is open, releases on close',
      (tester) async {
    await _typeSlash(tester);
    expect(keepEditorFocusNotifier.shouldKeepFocus, isTrue,
        reason: 'the keyboard must not be closed by the menu unfocusing the '
            'editor key handler');
    await tester.tapAt(const Offset(700, 500)); // tap outside -> dismiss
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(keepEditorFocusNotifier.shouldKeepFocus, isFalse,
        reason: 'the hold must be released on dismiss (balanced)');
  });
}
