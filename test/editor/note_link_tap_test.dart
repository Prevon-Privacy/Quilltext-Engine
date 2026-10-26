import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:provider/provider.dart';

class _FakeNavigator implements NoteLinkNavigator {
  final notes = <String>[];
  final folders = <String>[];
  @override
  void openNote(BuildContext context, String noteId) => notes.add(noteId);
  @override
  void openFolder(BuildContext context, String folderId) =>
      folders.add(folderId);
}

Future<(_FakeNavigator, EditorState)> _pump(WidgetTester tester,
    {bool mobile = false}) async {
  final nav = _FakeNavigator();
  final state = EditorState(
    document: Document.blank()
      ..insert([0], [
        Node(type: 'paragraph', attributes: {
          'delta': (Delta()
                ..insert('before ')
                ..insert('NoteLinkText', attributes: {'noteLink': 'note-1'})
                ..insert(' mid ')
                ..insert('FolderLinkText', attributes: {'folderLink': 'fold-1'})
                ..insert(' after'))
              .toJson(),
        }),
      ]),
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Provider<NoteLinkNavigator>.value(
        value: nav,
        child: AppFlowyEditor(
          editorState: state,
          editorStyle: mobile ? EditorStyle.mobile() : EditorStyle.desktop(),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (nav, state);
}

/// Global centre of the characters [start, end) of the paragraph.
Offset _centerOf(EditorState state, int start, int end) {
  final node = state.getNodeAtPath([0])!;
  final rect = node.selectable!
      .getRectsInSelection(
          Selection.single(path: [0], startOffset: start, endOffset: end))
      .first;
  return node.renderBox!.localToGlobal(rect.center);
}

void main() {
  // "before " = 7, "NoteLinkText" = 12 (7..19), " mid " = 5 (19..24),
  // "FolderLinkText" = 14 (24..38).
  testWidgets('tapping a note link opens the note; plain text does not',
      (tester) async {
    final (nav, state) = await _pump(tester);

    await tester.tapAt(_centerOf(state, 0, 6)); // "before"
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(nav.notes, isEmpty);
    expect(nav.folders, isEmpty);

    await tester.tapAt(_centerOf(state, 7, 19));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(nav.notes, ['note-1']);
    expect(nav.folders, isEmpty);
  });

  testWidgets('tapping the outer edge of the first/last link char still hits',
      (tester) async {
    final (nav, state) = await _pump(tester);
    final first = _centerOf(state, 7, 8);
    await tester.tapAt(first.translate(-2, 0)); // left sliver of first char
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(nav.notes, ['note-1']);
  });

  testWidgets('tapping just outside the link does not open it',
      (tester) async {
    final (nav, state) = await _pump(tester);
    await tester.tapAt(_centerOf(state, 20, 23)); // " mid "
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(nav.notes, isEmpty);
    expect(nav.folders, isEmpty);
  });

  testWidgets('tapping a folder link opens the folder', (tester) async {
    final (nav, state) = await _pump(tester);
    await tester.tapAt(_centerOf(state, 24, 38));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(nav.folders, ['fold-1']);
    expect(nav.notes, isEmpty);
  });
}
