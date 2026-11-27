// Audit of find and replace (SearchServiceV3). BUG tests pin real defects; GUARD tests only pin behaviour
// that already held.
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

EditorState _state(List<Node> nodes) {
  final doc = Document.blank()..insert([0], nodes);
  return EditorState(document: doc)..disableSealTimer = true;
}

EditorState _texts(List<String> t) =>
    _state(t.map((e) => paragraphNode(text: e)).toList());

String _t(EditorState s, Path p) => s.getNodeAtPath(p)!.delta!.toPlainText();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('find', () {
    test('GUARD empty query finds nothing', () {
      final s = _texts(['abc']);
      final f = SearchServiceV3(editorState: s);
      expect(f.findAndHighlight(''), 'Empty');
      expect(f.matchWrappers.value, isEmpty);
    });

    test('GUARD regex special chars are literal when regex is off', () {
      final s = _texts(['a.b a+b (x) [y] a.b']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('a.b');
      expect(f.matchWrappers.value.length, 2);
      f.findAndHighlight('(x)');
      expect(f.matchWrappers.value.length, 1);
      f.findAndHighlight('[y]');
      expect(f.matchWrappers.value.length, 1);
    });

    test('GUARD invalid regex does not throw', () {
      final s = _texts(['abc']);
      final f = SearchServiceV3(editorState: s)..regex = true;
      expect(f.findAndHighlight('('), 'Regex');
      expect(f.matchWrappers.value, isEmpty);
    });

    test('GUARD case sensitivity', () {
      final s = _texts(['Abc abc ABC']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('abc');
      expect(f.matchWrappers.value.length, 3);
      f.caseSensitive = true;
      expect(f.matchWrappers.value.length, 1);
    });

    test('GUARD match spans inline formatting boundary', () {
      final n = paragraphNode(
        delta: Delta()
          ..insert('hel', attributes: {'bold': true})
          ..insert('lo world'),
      );
      final s = _state([n]);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('hello');
      expect(f.matchWrappers.value.length, 1);
    });

    test('GUARD matches in nested children and table cells', () {
      final parent = paragraphNode(text: 'foo', children: [
        paragraphNode(text: 'foo child'),
      ]);
      final table = TableNode.fromList([
        ['foo', 'x'],
        ['y', 'foo'],
      ]);
      final s = _state([parent, table.node]);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('foo');
      expect(f.matchWrappers.value.length, 4);
    });

    test('GUARD emoji match offsets are UTF-16 and replace is exact', () async {
      final s = _texts(['a😀b😀b']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('😀b');
      expect(f.matchWrappers.value.map((m) => m.match.start), [1, 4]);
      f.replaceAllMatches('X');
      await _settle();
      expect(_t(s, [0]), 'aXX');
    });
  });

  group('replace all', () {
    test('GUARD length-changing replace keeps every match correct', () async {
      final s = _texts(['aa aa aa', 'aa']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('aa');
      f.replaceAllMatches('bbbbb');
      await _settle();
      expect(_t(s, [0]), 'bbbbb bbbbb bbbbb');
      expect(_t(s, [1]), 'bbbbb');
    });

    test('GUARD adjacent matches', () async {
      final s = _texts(['aaaa']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('aa');
      expect(f.matchWrappers.value.length, 2);
      f.replaceAllMatches('b');
      await _settle();
      expect(_t(s, [0]), 'bb');
    });

    test('BUG replacing with an empty string deletes the matches', () async {
      final s = _texts(['foo bar foo']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('foo');
      f.replaceAllMatches('');
      await _settle();
      expect(_t(s, [0]), ' bar ');
    });

    test('BUG replace-selected with empty string deletes the match', () async {
      final s = _texts(['foo bar']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('foo');
      await f.replaceSelectedWord('');
      expect(_t(s, [0]), ' bar');
    });

    test('GUARD replace-all is ONE undo step', () async {
      final s = _texts(['foo', 'foo', 'foo']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('foo');
      f.replaceAllMatches('barbar');
      await _settle();
      expect(_t(s, [2]), 'barbar');
      s.undoManager.undo();
      await _settle();
      expect([
        _t(s, [0]),
        _t(s, [1]),
        _t(s, [2])
      ], [
        'foo',
        'foo',
        'foo'
      ]);
    });

    test('GUARD replace-all leaves no stale selection on shifted offsets',
        () async {
      final s = _texts(['foo foo']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('foo');
      f.replaceAllMatches('x');
      await _settle();
      final sel = s.selection;
      if (sel != null) {
        final len = _t(s, sel.end.path).length;
        expect(sel.end.offset <= len && sel.start.offset <= len, isTrue);
      }
    });

    test('GUARD regex group substitution does not re-expand replaced text',
        () async {
      final s = _texts(['ab']);
      final f = SearchServiceV3(editorState: s)..regex = true;
      f.findAndHighlight('(a)(b)');
      f.replaceAllMatches(r'\2\1');
      await _settle();
      expect(_t(s, [0]), 'ba');
      // group text containing a backslash-digit must stay literal
      final s2 = _texts([r'\1x']);
      final f2 = SearchServiceV3(editorState: s2)..regex = true;
      f2.findAndHighlight(r'(\\1)(x)');
      f2.replaceAllMatches(r'\2\1');
      await _settle();
      expect(_t(s2, [0]), r'x\1');
    });
  });

  group('lifecycle', () {
    test('BUG dispose clears highlight selection', () {
      final s = _texts(['foo bar']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('foo');
      expect(s.selection, isNotNull);
      f.dispose();
      expect(s.selection, isNull);
    });
  });

  group('extra cases', () {
    test('GUARD replace across a bold boundary yields exact text', () async {
      final s = _state([
        paragraphNode(
          delta: Delta()
            ..insert('hel', attributes: {'bold': true})
            ..insert('lo world'),
        ),
      ]);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('hello');
      f.replaceAllMatches('hi');
      await _settle();
      expect(_t(s, [0]), 'hi world');
    });

    test('GUARD replace-selected keeps selection inside the document',
        () async {
      final s = _texts(['foo foo']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('foo');
      await f.replaceSelectedWord('x');
      expect(_t(s, [0]), 'x foo');
      final sel = s.selection!;
      expect(sel.end.offset <= _t(s, sel.end.path).length, isTrue);
    });
  });

  group('round 2', () {
    test('GUARD caret after replace-selected is on the NEXT match', () async {
      final s = _texts(['foo foo']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('foo');
      await f.replaceSelectedWord('xy');
      expect(_t(s, [0]), 'xy foo');
      expect(
          s.selection,
          Selection(
              start: Position(path: [0], offset: 3),
              end: Position(path: [0], offset: 6)));
    });

    test(
        'GUARD caret after replace-all is collapsed after the first replacement',
        () async {
      final s = _texts(['foo foo', 'foo']);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('foo');
      f.replaceAllMatches('z');
      await _settle();
      expect([
        _t(s, [0]),
        _t(s, [1])
      ], [
        'z z',
        'z'
      ]);
      expect(s.selection, Selection.collapsed(Position(path: [0], offset: 1)));
    });

    test('GUARD zero-length regex matches terminate and replace sanely',
        () async {
      final cases = {
        'x*': 'QaQbQ|QcQdQ',
        '^': 'Qab|Qcd',
        r'$': 'abQ|cdQ',
        r'\b': 'QabQ|QcdQ',
      };
      for (final e in cases.entries) {
        final s = _texts(['ab', 'cd']);
        final f = SearchServiceV3(editorState: s)..regex = true;
        f.findAndHighlight(e.key);
        f.replaceAllMatches('Q');
        await _settle();
        expect('${_t(s, [0])}|${_t(s, [1])}', e.value, reason: e.key);
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('GUARD find and replace a word inside a columns block', () async {
      final cols = columnsNode(children: [
        columnNode(children: [paragraphNode(text: 'left foo')]),
        columnNode(children: [paragraphNode(text: 'right foo')]),
      ]);
      final s = _state([cols]);
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('foo');
      expect(f.matchWrappers.value.length, 2);
      f.replaceAllMatches('bar');
      await _settle();
      expect(_t(s, [0, 0, 0]), 'left bar');
      expect(_t(s, [0, 1, 0]), 'right bar');
    });

    test(
        'GUARD replace across bold in a table cell: one undo, attributes restored',
        () async {
      final table = TableNode.fromList([
        ['a0', 'a1'],
        ['b0', 'b1'],
      ]);
      final para = table.node.children.first.children.first;
      para.updateAttributes({
        'delta': (Delta()
              ..insert('hel', attributes: {'bold': true})
              ..insert('lo world'))
            .toJson(),
      });
      final s = _state([table.node]);
      final before = s.getNodeAtPath([0, 0, 0])!.delta!.toJson();
      expect(_t(s, [0, 0, 0]), 'hello world');
      final f = SearchServiceV3(editorState: s);
      f.findAndHighlight('hello');
      expect(f.matchWrappers.value.length, 1);
      f.replaceAllMatches('hi');
      await _settle();
      expect(_t(s, [0, 0, 0]), 'hi world');
      s.undoManager.undo();
      await _settle();
      expect(s.getNodeAtPath([0, 0, 0])!.delta!.toJson(), before);
      expect(_t(s, [0, 0, 0]), 'hello world');
    });
  });
}
