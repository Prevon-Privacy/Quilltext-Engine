import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:provider/provider.dart';

class _LookNav implements NoteLinkNavigator, LinkTargetLook {
  _LookNav({this.color});
  @override
  final Listenable lookChanges = ChangeNotifier();
  final Color? color;
  final painted = <Rect>[];
  final opened = <String>[];

  @override
  void openNote(BuildContext context, String noteId) => opened.add(noteId);
  @override
  void openFolder(BuildContext context, String folderId) {}

  @override
  LinkLook? lookFor(BuildContext context, LinkEditKind kind, String target) =>
      LinkLook(color: color, paintIcon: (canvas, rect) => painted.add(rect));
}

class _PlainNav implements NoteLinkNavigator {
  @override
  void openNote(BuildContext context, String noteId) {}
  @override
  void openFolder(BuildContext context, String folderId) {}
}

EditorState _state() => EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          Node(type: 'paragraph', attributes: {
            'delta': (Delta()
                  ..insert('see ')
                  ..insert('Beta', attributes: {'noteLink': 'n1'})
                  ..insert(' after'))
                .toJson(),
          }),
          Node(type: 'paragraph', attributes: {
            'delta': (Delta()
                  ..insert('Gamma', attributes: {'noteLink': 'n2'})
                  ..insert(' tail'))
                .toJson(),
          }),
        ]),
    );

Future<EditorState> _pump(WidgetTester tester, NoteLinkNavigator nav) async {
  final state = _state();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Provider<NoteLinkNavigator>.value(
        value: nav,
        child: AppFlowyEditor(
          editorState: state,
          editorStyle: EditorStyle.desktop(),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return state;
}

Rect _rect(EditorState s, int block, int a, int b) => s
    .getNodeAtPath([block])!
    .selectable!
    .getRectsInSelection(
        Selection.single(path: [block], startOffset: a, endOffset: b))
    .first;

void main() {
  testWidgets('link icon room shifts the link, never the text offsets',
      (tester) async {
    final plain = await _pump(tester, _PlainNav());
    final plainLeft = _rect(plain, 0, 4, 8).left;
    final nav = _LookNav(color: Colors.red);
    final state = await _pump(tester, nav);

    // Same characters, same offsets.
    expect(state.getNodeAtPath([0])!.delta!.toPlainText(), 'see Beta after');
    final link = _rect(state, 0, 4, 8);
    expect(link.left, greaterThan(plainLeft + 10),
        reason: 'room for the icon sits before the link');
    // The text after the link keeps its offsets (selectable at 9..14).
    expect(_rect(state, 0, 9, 14).width, greaterThan(0));

    // One icon per link; block 0's icon sits left of its link text.
    expect(nav.painted.length, greaterThanOrEqualTo(2));
    final icon = nav.painted.first;
    expect(icon.width, greaterThan(8));
    expect(icon.right, lessThanOrEqualTo(link.left + 0.5));
  });

  testWidgets('a link at the start of a block gets its icon too',
      (tester) async {
    final nav = _LookNav();
    final state = await _pump(tester, nav);
    final link = _rect(state, 1, 0, 5);
    final icons = nav.painted.where((r) => r.right <= link.left + 0.5);
    expect(icons, isNotEmpty);
  });

  testWidgets('tapping a link with a look still opens its target',
      (tester) async {
    final nav = _LookNav(color: Colors.green);
    final state = await _pump(tester, nav);
    final node = state.getNodeAtPath([0])!;
    final c = node.renderBox!.localToGlobal(_rect(state, 0, 4, 8).center);
    await tester.tapAt(c);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(nav.opened, ['n1']);
  });

  testWidgets('no look provider: no gap, no icon', (tester) async {
    final a = await _pump(tester, _PlainNav());
    expect(_rect(a, 0, 4, 8).left, lessThan(80));
  });
}
