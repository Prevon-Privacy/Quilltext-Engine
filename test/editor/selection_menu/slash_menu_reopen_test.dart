import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Future<EditorState> _pump(WidgetTester tester) async {
  final state = EditorState(
    document: Document.blank()..insert([0], [paragraphNode(text: '')]),
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AppFlowyEditor(
        editorState: state,
        characterShortcutEvents: [
          customSlashCommand(standardSelectionMenuItems,
              style: SelectionMenuStyle.dark),
        ],
      ),
    ),
  ));
  await tester.pumpAndSettle();
  state.selection = Selection.collapsed(Position(path: [0], offset: 0));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('autocorrect that finds no row: Enter picks from what was typed',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final state = await _pump(tester);
      await customSlashCommand(standardSelectionMenuItems,
              style: SelectionMenuStyle.dark)
          .handler(state);
      await tester.pumpAndSettle();
      final node = state.getNodeAtPath([0])!;
      await state.apply(state.transaction..insertText(node, 1, 'bu'));
      await tester.pumpAndSettle();
      state.selection = Selection.collapsed(Position(path: [0], offset: 3));
      await tester.pumpAndSettle();
      // Keyboard rewrites "bu" to "by" and sends Enter in one replacement.
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '/by\n',
        selection: TextSelection.collapsed(offset: 4),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(SelectionMenuItemWidget), findsNothing);
      expect(state.getNodeAtPath([0])!.type, 'bulleted_list');
      expect(state.document.root.children.length, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('deleting back into /b brings the menu back', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final state = await _pump(tester);
      await customSlashCommand(standardSelectionMenuItems,
              style: SelectionMenuStyle.dark)
          .handler(state);
      await tester.pumpAndSettle();
      final node = state.getNodeAtPath([0])!;
      await state.apply(state.transaction..insertText(node, 1, 'bu'));
      await tester.pumpAndSettle();
      // Dismiss the menu (tap outside), as when the person goes elsewhere.
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(find.byType(SelectionMenuItemWidget), findsNothing);
      // Come back, delete the last letter.
      state.selection = Selection.collapsed(Position(path: [0], offset: 3));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(state.getNodeAtPath([0])!.delta!.toPlainText(), '/b');
      expect(find.byType(SelectionMenuItemWidget), findsWidgets);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('typing letters after a closed /b brings the menu back',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final state = await _pump(tester);
      await customSlashCommand(standardSelectionMenuItems,
              style: SelectionMenuStyle.dark)
          .handler(state);
      await tester.pumpAndSettle();
      final node = state.getNodeAtPath([0])!;
      await state.apply(state.transaction..insertText(node, 1, 'b'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(find.byType(SelectionMenuItemWidget), findsNothing);
      state.selection = Selection.collapsed(Position(path: [0], offset: 2));
      await tester.pumpAndSettle();
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '/bu',
        selection: TextSelection.collapsed(offset: 3),
      ));
      await tester.pumpAndSettle();
      expect(state.getNodeAtPath([0])!.delta!.toPlainText(), '/bu');
      expect(find.byType(SelectionMenuItemWidget), findsWidgets);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
