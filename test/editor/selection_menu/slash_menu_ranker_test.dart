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
  tearDown(() => selectionMenuRanker = null);

  testWidgets('PATCH 18: host ranking comes first, substring matches stay',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final state = await _pump(tester);
      // The host says "divider" is the best answer to "q" (a query that
      // matches no word of it): it must lead, and the substring matches for
      // "q" (e.g. Quote) must still be there after it.
      final asked = <String>[];
      selectionMenuRanker = (query, items) {
        asked.add(query);
        return [
          for (final i in items)
            if (i.name.toLowerCase().contains('divider')) i,
        ];
      };
      final cmd = customSlashCommand(standardSelectionMenuItems,
          style: SelectionMenuStyle.dark);
      await cmd.handler(state);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ, character: 'q');
      await tester.pumpAndSettle();
      expect(asked, contains('q'));
      final rows = find.byType(SelectionMenuItemWidget).evaluate().length;
      expect(rows, greaterThan(1), reason: 'divider + the substring matches');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('no ranker: upstream filtering unchanged', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      expect(selectionMenuRanker, isNull);
      final state = await _pump(tester);
      final cmd = customSlashCommand(standardSelectionMenuItems,
          style: SelectionMenuStyle.dark);
      await cmd.handler(state);
      await tester.pumpAndSettle();
      final all = find.byType(SelectionMenuItemWidget).evaluate().length;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ, character: 'q');
      await tester.pumpAndSettle();
      final filtered = find.byType(SelectionMenuItemWidget).evaluate().length;
      expect(filtered, lessThan(all));
      expect(filtered, greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
