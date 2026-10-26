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
  testWidgets('typing after / filters the menu', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final state = await _pump(tester);
      final cmd = customSlashCommand(standardSelectionMenuItems,
          style: SelectionMenuStyle.dark);
      await cmd.handler(state);
      await tester.pumpAndSettle();
      final all = find.byType(SelectionMenuItemWidget).evaluate().length;
      expect(all, greaterThan(3));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ, character: 'q');
      await tester.pumpAndSettle();
      final filtered = find.byType(SelectionMenuItemWidget).evaluate().length;
      expect(filtered, lessThan(all));
      expect(filtered, greaterThan(0));
      expect(state.getNodeAtPath([0])!.delta!.toPlainText(), '/q');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(state.getNodeAtPath([0])!.type, isNot('paragraph'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
  testWidgets('backspace on empty query removes only the slash',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final state = await _pump(tester);
      state.selection = Selection.collapsed(Position(path: [0], offset: 0));
      await state.apply(
          state.transaction..insertText(state.getNodeAtPath([0])!, 0, 'ab '));
      state.selection = Selection.collapsed(Position(path: [0], offset: 3));
      await customSlashCommand(standardSelectionMenuItems,
              style: SelectionMenuStyle.dark)
          .handler(state);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(state.getNodeAtPath([0])!.delta!.toPlainText(), 'ab ');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
  testWidgets('android: IME-typed text filters the menu and keeps it open',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final state = await _pump(tester);
      await customSlashCommand(standardSelectionMenuItems,
              style: SelectionMenuStyle.dark)
          .handler(state);
      await tester.pumpAndSettle();
      final all = find.byType(SelectionMenuItemWidget).evaluate().length;
      expect(all, greaterThan(3));

      // Simulate the IME inserting a character (no hardware key event).
      final node = state.getNodeAtPath([0])!;
      await state.apply(state.transaction..insertText(node, 1, 'q'));
      await tester.pumpAndSettle();
      final filtered = find.byType(SelectionMenuItemWidget).evaluate().length;
      expect(filtered, lessThan(all));
      expect(filtered, greaterThan(0));

      // Backspacing over the `/` closes the menu.
      await state.apply(state.transaction..deleteText(node, 0, 2));
      await tester.pumpAndSettle();
      expect(find.byType(SelectionMenuItemWidget), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'desktop: Enter picks the arrow-highlighted row of a filtered list',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final state = await _pump(tester);
      await customSlashCommand(standardSelectionMenuItems,
              style: SelectionMenuStyle.dark)
          .handler(state);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH, character: 'h');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE, character: 'e');
      await tester.pumpAndSettle();
      final names = find
          .byType(SelectionMenuItemWidget)
          .evaluate()
          .map((e) => (e.widget as SelectionMenuItemWidget).item.name)
          .toList();
      expect(names.length, greaterThan(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(SelectionMenuItemWidget), findsNothing);
      // The second row was inserted, the typed filter is gone.
      expect(state.getNodeAtPath([0])!.delta?.toPlainText() ?? '',
          isNot(contains('/')));
      expect(state.document.root.children.length, greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('IME Enter (newline insertion) picks the highlighted row',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final state = await _pump(tester);
      await customSlashCommand(standardSelectionMenuItems,
              style: SelectionMenuStyle.dark)
          .handler(state);
      await tester.pumpAndSettle();
      final node = state.getNodeAtPath([0])!;
      await state.apply(state.transaction..insertText(node, 1, 'q'));
      await tester.pumpAndSettle();
      // Keep the IME baseline in sync with the document ("/q", caret at 2).
      state.selection = Selection.collapsed(Position(path: [0], offset: 2));
      await tester.pumpAndSettle();
      // Soft keyboard Enter arrives as a "\n" in the editing value.
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '/q\n',
        selection: TextSelection.collapsed(offset: 3),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(SelectionMenuItemWidget), findsNothing);
      expect(state.getNodeAtPath([0])!.type, isNot('paragraph'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('IME performAction(newline) picks the highlighted row',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final state = await _pump(tester);
      await customSlashCommand(standardSelectionMenuItems,
              style: SelectionMenuStyle.dark)
          .handler(state);
      await tester.pumpAndSettle();
      final node = state.getNodeAtPath([0])!;
      await state.apply(state.transaction..insertText(node, 1, 'q'));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pumpAndSettle();
      expect(find.byType(SelectionMenuItemWidget), findsNothing);
      expect(state.getNodeAtPath([0])!.type, isNot('paragraph'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
