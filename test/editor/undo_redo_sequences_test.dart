// Edit / undo / redo in any order: a new edit ends the redo branch, a redo keeps the rest of it, and
// undo-all then redo-all is exact. (Found by shrinking: edit, undo, edit, redo used to crash.)
import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

EditorState _seed() => EditorState(
      document: Document.blank()
        ..insert([0], [
          paragraphNode(text: 'hello world'),
          bulletedListNode(text: 'item one'),
          todoListNode(checked: false, text: 'task'),
          quoteNode(delta: Delta()..insert('quoted')),
          paragraphNode(text: ''),
          numberedListNode(delta: Delta()..insert('first')),
        ]),
    );

class Op {
  Op(this.kind, this.sel, this.arg);
  final int kind;
  final List<int> sel;
  final int arg;
}

const kinds = ['insert', 'backspace', 'delete', 'newline', 'indent', 'outdent', 'bold', 'format', 'UNDO', 'REDO'];

Future<String?> _run(List<Op> ops) async {
  final errors = <Object>[];
  String? result;
  await runZonedGuarded(() async {
    final s = _seed();
    final start = s.document.toJson().toString();
    for (final o in ops) {
      final n = s.document.root.children.length;
      Position at(int i, int off) {
        final idx = min(i, n - 1);
        final len = s.document.root.children[idx].delta?.length ?? 0;
        return Position(path: [idx], offset: min(off, len));
      }

      s.selection = Selection(start: at(o.sel[0], o.sel[1]), end: at(o.sel[2], o.sel[3]));
      switch (o.kind) {
        case 0:
          await s.insertTextAtCurrentSelection('zz');
        case 1:
          backspaceCommand.execute(s);
        case 2:
          deleteCommand.execute(s);
        case 3:
          await s.insertNewLine();
        case 4:
          indentCommand.execute(s);
        case 5:
          outdentCommand.execute(s);
        case 6:
          await s.toggleAttribute('bold');
        case 7:
          final t = [
            BulletedListBlockKeys.type,
            TodoListBlockKeys.type,
            QuoteBlockKeys.type,
            ParagraphBlockKeys.type,
          ][o.arg % 4];
          await s.formatNode(s.selection, (node) => node.copyWith(type: t));
        case 8:
          s.undoManager.undo();
        case 9:
          s.undoManager.redo();
      }
      await Future<void>.delayed(Duration.zero);
    }
    final end = s.document.toJson().toString();
    var g = 0;
    while (s.undoManager.undoStack.isNonEmpty && g++ < 200) {
      s.undoManager.undo();
      await Future<void>.delayed(Duration.zero);
    }
    if (s.document.toJson().toString() != start) result = 'undo-all differs';
    final undone = g; // exactly as many redos as undos put the document back where it ended
    for (var i = 0; result == null && i < undone; i++) {
      s.undoManager.redo();
      await Future<void>.delayed(Duration.zero);
    }
    if (result == null && s.document.toJson().toString() != end) result = 'redo-all differs';
  }, (e, st) => errors.add(e));
  if (errors.isNotEmpty) return 'threw ${errors.first}';
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a new edit after undo ends the redo branch (redo does nothing)', () async {
    final s = EditorState(document: Document.blank()..insert([0], [paragraphNode(text: 'x')]));
    s.selection = Selection.collapsed(Position(path: [0], offset: 1));
    await s.insertTextAtCurrentSelection('a');
    s.undoManager.undo();
    await Future<void>.delayed(Duration.zero);
    await s.insertTextAtCurrentSelection('b');
    final after = s.document.toJson().toString();
    s.undoManager.redo();
    await Future<void>.delayed(Duration.zero);
    expect(s.document.toJson().toString(), after);
    expect(s.undoManager.redoStack.isEmpty, isTrue);
  });

  test('redo keeps the rest of the redo branch', () async {
    final s = EditorState(document: Document.blank()..insert([0], [paragraphNode(text: '')]));
    s.disableSealTimer = true;
    s.selection = Selection.collapsed(Position(path: [0], offset: 0));
    for (final c in ['a', 'b', 'c']) {
      await s.insertTextAtCurrentSelection(c);
      s.undoManager.undoStack.last.seal();
    }
    final full = s.document.toJson().toString();
    for (var i = 0; i < 3; i++) {
      s.undoManager.undo();
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 3; i++) {
      s.undoManager.redo();
      await Future<void>.delayed(Duration.zero);
    }
    expect(s.document.toJson().toString(), full);
  });

  test('random edit / undo / redo sequences never crash and undo-all, redo-all are exact', () async {
    final bad = <String>[];
    for (var seed = 0; seed < 40; seed++) {
      final r = Random(seed);
      final ops = [
        for (var i = 0; i < 40; i++)
          Op(r.nextInt(10), [r.nextInt(6), r.nextInt(8), r.nextInt(6), r.nextInt(8)], r.nextInt(4)),
      ];
      final why = await _run(ops);
      if (why != null) bad.add('seed $seed: $why');
    }
    expect(bad, isEmpty);
  });
}
