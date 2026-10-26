import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:provider/provider.dart';

class _Host implements NoteLinkNavigator, LinkEditor {
  _Host({this.choice, this.result});
  LinkMenuChoice? choice;
  LinkEditResult? result;
  LinkEditRequest? menuRequest;
  LinkEditRequest? editRequest;
  final opened = <String>[];

  @override
  void openNote(BuildContext context, String noteId) => opened.add(noteId);
  @override
  void openFolder(BuildContext context, String folderId) {}
  @override
  Future<LinkMenuChoice?> showLinkMenu(
    BuildContext context,
    LinkEditRequest request,
  ) async {
    menuRequest = request;
    return choice;
  }

  @override
  Future<LinkEditResult?> editLink(
    BuildContext context,
    LinkEditRequest request,
  ) async {
    editRequest = request;
    return result;
  }
}

Future<EditorState> _pump(WidgetTester tester, _Host host) async {
  final state = EditorState(
    document: Document.blank()
      ..insert([
        0,
      ], [
        Node(
          type: 'paragraph',
          attributes: {
            'delta': (Delta()
                  ..insert('go ')
                  ..insert('a.com',
                      attributes: {'href': 'https://a.com', 'bold': true})
                  ..insert(' and ')
                  ..insert('Note', attributes: {'noteLink': 'n1'}))
                .toJson(),
          },
        ),
      ]),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Provider<NoteLinkNavigator>.value(
          value: host,
          child: AppFlowyEditor(
            editorState: state,
            editorStyle: EditorStyle.mobile(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Offset _center(EditorState state, int s, int e) {
  final node = state.getNodeAtPath([0])!;
  final r = node.selectable!
      .getRectsInSelection(
        Selection.single(path: [0], startOffset: s, endOffset: e),
      )
      .first;
  return node.renderBox!.localToGlobal(r.center);
}

List<TextInsert> _ops(EditorState s) =>
    s.getNodeAtPath([0])!.delta!.whereType<TextInsert>().toList();

Future<void> _hold(WidgetTester tester, Offset at) async {
  await tester.tapAt(at, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menu request describes the link', (tester) async {
    final host = _Host();
    final state = await _pump(tester, host);
    await _hold(tester, _center(state, 3, 8));
    expect(host.menuRequest!.kind, LinkEditKind.web);
    expect(host.menuRequest!.text, 'a.com');
    expect(host.menuRequest!.url, 'https://a.com');
    await _hold(tester, _center(state, 13, 17));
    expect(host.menuRequest!.kind, LinkEditKind.note);
    expect(host.menuRequest!.target, 'n1');
  });

  testWidgets('rename keeps the link and other formatting', (tester) async {
    final host = _Host(
      choice: LinkMenuChoice.edit,
      result: const LinkEditResult(text: 'Anchor', url: 'https://a.com'),
    );
    final state = await _pump(tester, host);
    await _hold(tester, _center(state, 3, 8));
    expect(host.editRequest!.text, 'a.com');
    final run = _ops(state).firstWhere((o) => o.text == 'Anchor');
    expect(run.attributes?['href'], 'https://a.com');
    expect(run.attributes?['bold'], true);
    expect(state.getNodeAtPath([0])!.delta!.toPlainText(),
        'go Anchor and Note');
  });

  testWidgets('web address can change; text stays', (tester) async {
    final host = _Host(
      choice: LinkMenuChoice.edit,
      result: const LinkEditResult(text: 'a.com', url: 'https://b.org'),
    );
    final state = await _pump(tester, host);
    await _hold(tester, _center(state, 3, 8));
    final run = _ops(state).firstWhere((o) => o.text == 'a.com');
    expect(run.attributes?['href'], 'https://b.org');
    expect(run.attributes?['bold'], true);
  });

  testWidgets('renaming a note link keeps it pointing at the note',
      (tester) async {
    final host = _Host(
      choice: LinkMenuChoice.edit,
      result: const LinkEditResult(text: 'Groceries'),
    );
    final state = await _pump(tester, host);
    await _hold(tester, _center(state, 13, 17));
    final run = _ops(state).firstWhere((o) => o.text == 'Groceries');
    expect(run.attributes?['noteLink'], 'n1');
  });

  testWidgets('dismissed edit and empty names change nothing', (tester) async {
    final host = _Host(choice: LinkMenuChoice.edit);
    final state = await _pump(tester, host);
    await _hold(tester, _center(state, 3, 8));
    expect(state.getNodeAtPath([0])!.delta!.toPlainText(), 'go a.com and Note');
    host.result = const LinkEditResult(text: '');
    await _hold(tester, _center(state, 3, 8));
    expect(state.getNodeAtPath([0])!.delta!.toPlainText(), 'go a.com and Note');
  });

  testWidgets('remove and open choices', (tester) async {
    final host = _Host(choice: LinkMenuChoice.open);
    final state = await _pump(tester, host);
    await _hold(tester, _center(state, 13, 17));
    expect(host.opened, ['n1']);
    host.choice = LinkMenuChoice.remove;
    await _hold(tester, _center(state, 3, 8));
    expect(_ops(state).every((o) => o.attributes?['href'] == null), isTrue);
  });
}
