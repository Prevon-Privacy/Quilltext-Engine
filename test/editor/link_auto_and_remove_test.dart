import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:provider/provider.dart';

class _FakeNavigator implements NoteLinkNavigator {
  @override
  void openNote(BuildContext context, String noteId) {}
  @override
  void openFolder(BuildContext context, String folderId) {}
}

EditorState _stateWith(String text, {Map<String, dynamic>? attrs}) {
  final state = EditorState(
    document: Document.blank()
      ..insert([
        0,
      ], [
        Node(
          type: 'paragraph',
          attributes: {
            'delta': (Delta()..insert(text, attributes: attrs)).toJson(),
          },
        ),
      ]),
  );
  state.selection = Selection.collapsed(
    Position(path: [0], offset: text.length),
  );
  return state;
}

String? _hrefOf(EditorState s, int index) {
  var at = 0;
  for (final op in s.getNodeAtPath([0])!.delta!) {
    if (index < at + op.length) {
      return (op as TextInsert).attributes?['href'] as String?;
    }
    at += op.length;
  }
  return null;
}

void main() {
  group('autoLinkOnSpace', () {
    test('links a bare domain', () {
      final s = _stateWith('visit prevonprivacy.com');
      handleAutoLinkBeforeSpace(s);
      expect(_hrefOf(s, 10), 'https://prevonprivacy.com');
      expect(_hrefOf(s, 2), isNull);
    });

    test('keeps scheme, drops trailing punctuation', () {
      final s = _stateWith('see https://a.io/x?y=1.');
      handleAutoLinkBeforeSpace(s);
      expect(_hrefOf(s, 6), 'https://a.io/x?y=1');
      expect(_hrefOf(s, 22), isNull); // the final "."
    });

    test('ignores ordinary words and file-like names', () {
      for (final t in ['hello', 'e.g.', 'notes.txt', 'v1.2']) {
        final s = _stateWith(t);
        handleAutoLinkBeforeSpace(s);
        expect(_hrefOf(s, 0), isNull, reason: t);
      }
    });

    test('does not touch an existing link', () {
      final s = _stateWith('x.com', attrs: {'href': 'https://other'});
      handleAutoLinkBeforeSpace(s);
      expect(_hrefOf(s, 0), 'https://other');
    });
  });

  testWidgets('secondary-click on a link offers Remove link and strips it',
      (tester) async {
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
                    ..insert('a.com', attributes: {'href': 'https://a.com'})
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
            value: _FakeNavigator(),
            child: AppFlowyEditor(
              editorState: state,
              editorStyle: EditorStyle.mobile(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Offset center(int s, int e) {
      final node = state.getNodeAtPath([0])!;
      final r = node.selectable!
          .getRectsInSelection(
            Selection.single(path: [0], startOffset: s, endOffset: e),
          )
          .first;
      return node.renderBox!.localToGlobal(r.center);
    }

    await tester.tapAt(center(3, 8), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Remove link'), findsOneWidget);
    await tester.tap(find.text('Remove link'));
    await tester.pumpAndSettle();
    expect(_hrefOf(state, 4), isNull);

    await tester.tapAt(center(13, 17), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove link'));
    await tester.pumpAndSettle();
    final ops = state.getNodeAtPath([0])!.delta!.toList();
    expect(
      ops.every((o) => (o as TextInsert).attributes?['noteLink'] == null),
      isTrue,
    );
  });
}
