// REMOTE EDIT + UNDO BARRIER fuzz (S1, 2026-11-08): 2,000 seeded runs of random local typing, local erasing, remote block edits
// (applyRemoteBlockText), caret moves, undo and redo. Properties after EVERY step: no call throws; every character a remote edit
// put in the document is still there unless a local erase removed it (Undo/Redo never rewinds remote text); every selection offset
// fits its block; a remote edit refused because the caret holds the block changed nothing. Mutation control: a local erase the
// tracker does not know about is named by the same check (the property is not vacuous).
import 'dart:math';

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

String _all(EditorState s) => [
      for (var i = 0; i < s.document.root.children.length; i++) _text(s, i)
    ].join('\n');

Delta _ins(int at, String text) {
  final d = Delta();
  if (at > 0) d.retain(at);
  d.insert(text);
  return d;
}

class _Run {
  _Run(this.seed)
      : rnd = Random(seed),
        s = _seed() {
    ids = [for (final n in s.document.root.children) n.id];
  }
  final int seed;
  final Random rnd;
  final EditorState s;
  late final List<String> ids;
  final remote = <int>{};
  final erasedLocally = <int>{};
  var next = 0x4E00;
  var refusedChanged = 0;

  String? invariant() {
    final all = _all(s).codeUnits.toSet();
    for (final c in remote) {
      if (!erasedLocally.contains(c) && !all.contains(c)) {
        return 'remote char U+${c.toRadixString(16)} vanished';
      }
    }
    final sel = s.selection;
    if (sel != null) {
      for (final p in [sel.start, sel.end]) {
        if (p.path.isEmpty || p.path.first >= s.document.root.children.length) {
          return 'selection path out of range ${p.path}';
        }
        if (p.offset > _text(s, p.path.first).length) {
          return 'selection offset ${p.offset} beyond block';
        }
      }
    }
    return null;
  }

  Future<String?> step() async {
    final b = rnd.nextInt(3);
    final t = _text(s, b);
    switch (rnd.nextInt(8)) {
      case 0: // local type
        final ch = String.fromCharCode(next++);
        await s.apply(
            s.transaction
              ..insertText(
                  s.getNodeAtPath([b])!, rnd.nextInt(t.length + 1), ch),
            skipHistoryDebounce: true);
      case 1 when t.isNotEmpty: // local erase
        final p = rnd.nextInt(t.length);
        erasedLocally.add(t.codeUnitAt(p));
        await s.apply(s.transaction..deleteText(s.getNodeAtPath([b])!, p, 1),
            skipHistoryDebounce: true);
      case 2:
      case 3: // remote edit
        final ch = String.fromCharCode(next++);
        final before = _all(s);
        final r =
            s.applyRemoteBlockText(ids[b], _ins(rnd.nextInt(t.length + 1), ch));
        if (r == RemoteBlockResult.applied) {
          remote.add(ch.codeUnitAt(0));
        } else if (_all(s) != before) {
          refusedChanged++;
          return 'a refused remote edit ($r) changed the document';
        }
      case 4: // remote delete of one char
        if (t.isEmpty) break;
        final p = rnd.nextInt(t.length);
        final d = Delta();
        if (p > 0) d.retain(p);
        d.delete(1);
        final gone = t.codeUnitAt(p);
        final r = s.applyRemoteBlockText(ids[b], d);
        if (r == RemoteBlockResult.applied) erasedLocally.add(gone);
      case 5:
        s.undoManager.undo();
      case 6:
        s.undoManager.redo();
      default:
        s.selection = rnd.nextInt(4) == 0
            ? null
            : Selection.collapsed(
                Position(path: [b], offset: rnd.nextInt(t.length + 1)));
    }
    await Future<void>.delayed(Duration.zero);
    return invariant();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (var chunk = 0; chunk < 8; chunk++) {
    test(
        'seeds ${chunk * 250}-${chunk * 250 + 249}: no throw, remote text never rewound, selection valid',
        () async {
      final bad = <String>[];
      for (var seed = chunk * 250; seed < chunk * 250 + 250; seed++) {
        final run = _Run(seed);
        for (var i = 0; i < 40; i++) {
          String? why;
          try {
            why = await run.step();
          } catch (e) {
            why = 'threw $e';
          }
          if (why != null) {
            bad.add('seed $seed step $i: $why');
            break;
          }
        }
        run.s.dispose();
      }
      expect(bad.take(5), isEmpty, reason: '${bad.length} bad');
    }, timeout: const Timeout(Duration(minutes: 20)));
  }

  test(
      'mutation control: a local erase the tracker does not know about is named as a vanished remote char',
      () async {
    var named = 0;
    for (var seed = 0; seed < 40; seed++) {
      final run = _Run(seed);
      for (var i = 0; i < 25; i++) {
        await run.step();
      }
      final victim = run.remote.where((c) =>
          !run.erasedLocally.contains(c) && _all(run.s).codeUnits.contains(c));
      if (victim.isNotEmpty) {
        final ch = String.fromCharCode(victim.first);
        for (var b = 0; b < 3; b++) {
          final t = _text(run.s, b);
          final at = t.indexOf(ch);
          if (at >= 0) {
            await run.s.apply(
                run.s.transaction..deleteText(run.s.getNodeAtPath([b])!, at, 1),
                skipHistoryDebounce: true); // silent: erasedLocally untouched
          }
        }
        if (run.invariant()?.contains('vanished') ?? false) named++;
      }
      run.s.dispose();
    }
    expect(named, greaterThan(10));
  });
}
