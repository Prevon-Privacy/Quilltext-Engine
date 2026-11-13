// A remote device's edit of ONE block (`applyRemoteBlockText`) and the undo barrier: the caret never moves by surprise, nothing
// reaches the "local edit" stream or the undo stack, and Undo never rewinds a remote edit or aims at a wrong block.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

EditorState _seed() => EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          paragraphNode(text: 'hello world'),
          paragraphNode(text: 'second block'),
          paragraphNode(text: 'third'),
        ]),
    );

String _text(EditorState s, int i) =>
    s.document.root.children.elementAt(i).delta!.toPlainText();

Delta _ins(int at, String text) {
  final d = Delta();
  if (at > 0) d.retain(at);
  d.insert(text);
  return d;
}

/// A local typed edit that is sealed as its own undo item.
Future<void> _type(EditorState s, int block, int at, String text) => s.apply(
      s.transaction..insertText(s.getNodeAtPath([block])!, at, text),
      skipHistoryDebounce: true,
    );

({int start, int end}) _shift(int start, int end, int at, int by) =>
    (start: start >= at ? start + by : start, end: end >= at ? end + by : end);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'a remote edit in another block keeps the caret, its offset and the selection object',
      () async {
    final s = _seed();
    final id1 = s.document.root.children.elementAt(1).id;
    final caret = Selection.collapsed(Position(path: [0], offset: 5));
    s.selection = caret;
    var events = 0;
    final sub = s.transactionStream.listen((_) => events++);
    final r = s.applyRemoteBlockText(id1, _ins(0, 'X'));
    await Future<void>.delayed(Duration.zero);
    expect(r, RemoteBlockResult.applied);
    expect(_text(s, 1), 'Xsecond block');
    expect(s.selection, caret);
    expect(events, 0, reason: 'a remote edit is not a local edit');
    expect(s.undoManager.undoStack.isEmpty, isTrue);
    expect(s.undoManager.redoStack.isEmpty, isTrue);
    await sub.cancel();
  });

  test(
      'a remote edit keeps attributes it carries and the local formatting it retains',
      () {
    final s = EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          paragraphNode(
              delta: Delta()
                ..insert('bold', attributes: {'bold': true})
                ..insert(' tail')),
        ]),
    );
    final id = s.document.root.children.first.id;
    final d = Delta()
      ..retain(4)
      ..insert('!', attributes: {'italic': true});
    expect(s.applyRemoteBlockText(id, d), RemoteBlockResult.applied);
    final ops = s.document.root.children.first.delta!.toList();
    expect(ops.first, TextInsert('bold', attributes: {'bold': true}));
    expect(ops[1], TextInsert('!', attributes: {'italic': true}));
    expect(ops.last, TextInsert(' tail'));
  });

  test('the block that holds the caret refuses (held) and nothing changes', () {
    final s = _seed();
    final id0 = s.document.root.children.first.id;
    final caret = Selection.collapsed(Position(path: [0], offset: 5));
    s.selection = caret;
    expect(
        s.applyRemoteBlockText(id0, _ins(0, 'NEW ')), RemoteBlockResult.held);
    expect(_text(s, 0), 'hello world');
    expect(s.selection, caret);
    // A range covering the block also holds it.
    s.selection = Selection(
        start: Position(path: [0], offset: 2),
        end: Position(path: [2], offset: 1));
    expect(
        s.applyRemoteBlockText(
            s.document.root.children.elementAt(1).id, _ins(0, 'Q')),
        RemoteBlockResult.held);
  });

  test(
      'held, then the caret leaves: the same edit applies and the new caret is untouched',
      () {
    final s = _seed();
    final id0 = s.document.root.children.first.id;
    s.selection = Selection.collapsed(Position(path: [0], offset: 5));
    final edit = _ins(0, 'NEW ');
    expect(s.applyRemoteBlockText(id0, edit), RemoteBlockResult.held);
    final elsewhere = Selection.collapsed(Position(path: [2], offset: 3));
    s.selection = elsewhere;
    expect(s.applyRemoteBlockText(id0, edit), RemoteBlockResult.applied);
    expect(_text(s, 0), 'NEW hello world');
    expect(s.selection, elsewhere);
  });

  test(
      'force: a remote insert before the caret in the SAME block moves the caret with the text',
      () {
    final s = _seed();
    final id0 = s.document.root.children.first.id;
    s.selection = Selection.collapsed(Position(path: [0], offset: 5));
    final r = s.applyRemoteBlockText(id0, _ins(0, 'NEW '),
        force: true, mapSelection: (a, b) => _shift(a, b, 0, 4));
    expect(r, RemoteBlockResult.applied);
    expect(_text(s, 0), 'NEW hello world');
    expect(s.selection, Selection.collapsed(Position(path: [0], offset: 9)));
  });

  test(
      'force without a mapper clamps, never nulls, and keeps a backwards range backwards',
      () {
    final s = _seed();
    final id2 = s.document.root.children.elementAt(2).id;
    s.selection = Selection(
        start: Position(path: [2], offset: 5),
        end: Position(path: [2], offset: 1));
    final del = Delta()
      ..retain(2)
      ..delete(3);
    expect(s.applyRemoteBlockText(id2, del, force: true),
        RemoteBlockResult.applied);
    expect(_text(s, 2), 'th');
    expect(s.selection, isNotNull);
    expect(s.selection!.start.offset, 2);
    expect(s.selection!.end.offset, 1);
  });

  test(
      'an IME composition is never forced, even with force: true, and a null selection while composing holds',
      () {
    final s = _seed();
    final id0 = s.document.root.children.first.id;
    s.selection = Selection.collapsed(Position(path: [0], offset: 2));
    expect(
        s.applyRemoteBlockText(id0, _ins(0, 'Z'),
            imeComposing: true, force: true),
        RemoteBlockResult.held);
    expect(_text(s, 0), 'hello world');
    s.selection = null;
    expect(s.applyRemoteBlockText(id0, _ins(0, 'Z'), imeComposing: true),
        RemoteBlockResult.held);
    // Composition elsewhere does not stop a block the caret is not in.
    s.selection = Selection.collapsed(Position(path: [2], offset: 1));
    expect(s.applyRemoteBlockText(id0, _ins(0, 'Z'), imeComposing: true),
        RemoteBlockResult.applied);
  });

  test('missing id, an edit that does not fit and a surrogate pair', () {
    final s = _seed();
    expect(s.applyRemoteBlockText('nosuchid0000', _ins(0, 'a')),
        RemoteBlockResult.missing);
    final id1 = s.document.root.children.elementAt(1).id;
    final tooLong = Delta()..retain(500);
    expect(s.applyRemoteBlockText(id1, tooLong), RemoteBlockResult.invalid);
    expect(_text(s, 1), 'second block');
    // An emoji (two code units) goes in whole; the caret in another block is untouched.
    final caret = Selection.collapsed(Position(path: [0], offset: 3));
    s.selection = caret;
    expect(s.applyRemoteBlockText(id1, _ins(6, '\u{1F600}')),
        RemoteBlockResult.applied);
    expect(_text(s, 1), 'second\u{1F600} block');
    expect(s.selection, caret);
    // Force-mapping a caret after the emoji lands after both halves.
    s.selection = Selection.collapsed(Position(path: [1], offset: 7));
    final r = s.applyRemoteBlockText(id1, _ins(0, '\u{1F600}'),
        force: true, mapSelection: (a, b) => _shift(a, b, 0, 2));
    expect(r, RemoteBlockResult.applied);
    expect(s.selection!.start.offset, 9);
  });

  group('undo barrier', () {
    test('Undo undoes only local edits and never rewinds a remote edit',
        () async {
      final s = _seed();
      final id0 = s.document.root.children.first.id;
      await _type(s, 1, 0, 'aa'); // local, block 1
      s.selection = Selection.collapsed(Position(path: [2], offset: 0));
      s.applyRemoteBlockText(id0, _ins(0, 'R: ')); // remote, block 0
      expect(_text(s, 0), 'R: hello world');
      s.undoManager.undo();
      await Future<void>.delayed(Duration.zero);
      expect(_text(s, 1), 'second block', reason: 'the local edit is undone');
      expect(_text(s, 0), 'R: hello world', reason: 'the remote edit stays');
      s.undoManager.undo(); // nothing left
      expect(_text(s, 0), 'R: hello world');
    });

    test(
        'a local edit of a block the remote then edited is no longer undoable (no rewind of the remote text)',
        () async {
      final s = _seed();
      final id0 = s.document.root.children.first.id;
      await _type(s, 0, 0, 'mine ');
      s.selection = Selection.collapsed(Position(path: [2], offset: 0));
      s.applyRemoteBlockText(id0, _ins(0, 'theirs '));
      expect(_text(s, 0), 'theirs mine hello world');
      expect(s.undoManager.undoStack.isEmpty, isTrue);
      s.undoManager.undo();
      expect(_text(s, 0), 'theirs mine hello world');
    });

    test(
        'a redo that would overwrite the remote edit is dropped; redo of another block survives',
        () async {
      final s = _seed();
      final id0 = s.document.root.children.first.id;
      await _type(s, 0, 0, 'A');
      await _type(s, 1, 0, 'B');
      s.undoManager.undo(); // B
      s.undoManager.undo(); // A
      await Future<void>.delayed(Duration.zero);
      s.selection = Selection.collapsed(Position(path: [2], offset: 0));
      s.applyRemoteBlockText(id0, _ins(0, 'R'));
      s.undoManager.redo(); // A was dropped; B is next in line
      await Future<void>.delayed(Duration.zero);
      expect(_text(s, 0), 'Rhello world');
    });

    test(
        'a structural remote insert above shifts the paths: Undo still hits the right block',
        () async {
      final s = _seed();
      await _type(s, 1, 0, 'zz');
      expect(_text(s, 1), 'zzsecond block');
      await s.apply(
        Transaction(document: s.document)
          ..add(InsertOperation([0], [paragraphNode(text: 'remote new')]),
              transform: false),
        isRemote: true,
      );
      expect(_text(s, 0), 'remote new');
      expect(_text(s, 2), 'zzsecond block');
      s.undoManager.undo();
      await Future<void>.delayed(Duration.zero);
      expect(_text(s, 2), 'second block');
      expect(_text(s, 0), 'remote new');
      expect(_text(s, 1), 'hello world');
    });

    test(
        'a structural remote delete of the block a local edit touched drops that edit; others shift',
        () async {
      final s = _seed();
      await _type(s, 0, 0, 'a');
      await _type(s, 2, 0, 'c');
      final doomed = s.document.root.children.first;
      await s.apply(
        Transaction(document: s.document)
          ..add(DeleteOperation([0], [doomed]), transform: false),
        isRemote: true,
      );
      expect(_text(s, 1), 'cthird');
      s.undoManager.undo();
      await Future<void>.delayed(Duration.zero);
      expect(_text(s, 1), 'third');
      s.undoManager
          .undo(); // the dropped 'a' edit: nothing left, nothing thrown
      expect(_text(s, 0), 'second block');
    });

    test(
        'local structural history plus a remote structural edit clears the history (valid, never wrong)',
        () async {
      final s = _seed();
      await s.apply(
        s.transaction..insertNode([1], paragraphNode(text: 'mine')),
        skipHistoryDebounce: true,
      );
      expect(s.undoManager.undoStack.isNonEmpty, isTrue);
      await s.apply(
        Transaction(document: s.document)
          ..add(InsertOperation([0], [paragraphNode(text: 'remote')]),
              transform: false),
        isRemote: true,
      );
      expect(s.undoManager.undoStack.isEmpty, isTrue);
      expect(s.undoManager.redoStack.isEmpty, isTrue);
    });

    test(
        'a block born locally then edited remotely: Undo does not delete the remote text',
        () async {
      final s = _seed();
      await s.apply(
        s.transaction..insertNode([3], paragraphNode(text: 'born')),
        skipHistoryDebounce: true,
      );
      await _type(s, 0, 0, 'k');
      final born = s.document.root.children.elementAt(3).id;
      s.selection = Selection.collapsed(Position(path: [2], offset: 0));
      s.applyRemoteBlockText(born, _ins(4, ' + theirs'));
      s.undoManager.undo(); // 'k' (newer, unrelated) may undo
      await Future<void>.delayed(Duration.zero);
      s.undoManager.undo(); // the birth was removed by the barrier
      await Future<void>.delayed(Duration.zero);
      expect(_text(s, 3), 'born + theirs');
    });
  });

  test(
      'applyRemoteBlockText does not throw while disposed or on a block without text',
      () {
    final s = _seed();
    s.dispose();
    expect(s.applyRemoteBlockText('x', Delta()), RemoteBlockResult.invalid);
  });
}
