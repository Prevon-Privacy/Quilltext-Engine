import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:provider/provider.dart';

class _Nav implements NoteLinkNavigator {
  @override
  void openNote(BuildContext context, String noteId) {}
  @override
  void openFolder(BuildContext context, String folderId) {}
}

class _AppNav extends _Nav implements AppLinkNavigator {
  final targets = <String>[];
  @override
  void openApp(BuildContext context, String target) => targets.add(target);
}

Future<EditorState> _pump(
  WidgetTester tester,
  NoteLinkNavigator nav, {
  bool mobile = false,
}) async {
  final state = EditorState(
    document: Document.blank()
      ..insert([0], [
        Node(type: 'paragraph', attributes: {
          'delta': (Delta()
                ..insert('before ')
                ..insert('GoThere', attributes: {'appLink': 'settings/x'})
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
  return state;
}

Offset _centerOf(EditorState state, int start, int end) {
  final node = state.getNodeAtPath([0])!;
  final rect = node.selectable!
      .getRectsInSelection(
          Selection.single(path: [0], startOffset: start, endOffset: end))
      .first;
  return node.renderBox!.localToGlobal(rect.center);
}

void main() {
  // "before " = 7, "GoThere" = 7 (7..14), " after" = 6.
  for (final mobile in [false, true]) {
    testWidgets('tapping an app link opens its target (mobile=$mobile)',
        (tester) async {
      final nav = _AppNav();
      final state = await _pump(tester, nav, mobile: mobile);

      await tester.tapAt(_centerOf(state, 0, 6));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(nav.targets, isEmpty);

      await tester.tapAt(_centerOf(state, 7, 14));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(nav.targets, ['settings/x']);
    });
  }

  testWidgets('a navigator that cannot open app links leaves it inert',
      (tester) async {
    // Plain NoteLinkNavigator (not an AppLinkNavigator): must not throw.
    final state = await _pump(tester, _Nav());
    await tester.tapAt(_centerOf(state, 7, 14));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  test('NoteLinkPick.attributes carries appLink', () {
    const pick = NoteLinkPick(
      id: '',
      label: 'Recovery',
      isFolder: false,
      appTarget: 'settings/recoveryPhrase',
    );
    expect(pick.attributes, {'appLink': 'settings/recoveryPhrase'});
  });
}
