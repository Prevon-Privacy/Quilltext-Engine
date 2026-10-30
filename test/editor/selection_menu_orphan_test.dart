import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// The slash menu lives in the ROOT overlay, so it outlives the editor when the
/// page is popped under it (a tour's Resume walking back, a system back swipe).
/// It must clean itself up instead of throwing on every rebuild and leaving a
/// full-screen layer that swallows touches.
void main() {
  testWidgets('menu left open when the editor goes away dismisses itself',
      (tester) async {
    final state = EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          Node(type: 'paragraph', attributes: {'delta': Delta().toJson()}),
        ]),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppFlowyEditor(editorState: state)),
    ));
    await tester.pumpAndSettle();
    state.selection = Selection.collapsed(Position(path: [0], offset: 0));
    await tester.pumpAndSettle();

    await customSlashCommand(standardSelectionMenuItems).handler(state);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SelectionMenuWidget), findsOneWidget);

    // The editor page goes away; nothing dismissed the menu.
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull,
        reason: 'the orphaned menu must not throw while rebuilding');
    expect(find.byType(SelectionMenuWidget), findsNothing);
    expect(keepEditorFocusNotifier.shouldKeepFocus, isFalse,
        reason: 'the focus hold is released when the orphan dismisses');
  });
}
