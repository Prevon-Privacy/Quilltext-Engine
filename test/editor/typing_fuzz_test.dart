// Typing, one character at a time, through the same path the keyboard uses (markdown shortcuts, auto links,
// newlines). Whatever is typed: no crash, a sound document, a caret inside it, and undo-all restores the start.
import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/ime/delta_input_on_insert_impl.dart';

const _alphabet = [
  'a', 'b', 'c', 'x', 'Z', '1', '2', ' ', ' ', ' ', '\n', '\n', '*', '*', '_', '`', '~', '#', '>', '-', '+', '.',
  '[', ']', '(', ')', '/', ':', 'é', '日', '😀', '!', '@', '\\', '<', '"',
];

EditorState _fresh() => EditorState(
      document: Document.blank()..insert([0], [paragraphNode(text: 'start')]),
    );

Future<void> _type(EditorState s, String c) async {
  final sel = s.selection;
  if (sel == null) return;
  final node = s.getNodeAtPath(sel.start.path);
  final text = node?.delta?.toPlainText() ?? '';
  final at = sel.start.offset.clamp(0, text.length);
  final after = at + c.length;
  await onInsert(
    TextEditingDeltaInsertion(
      oldText: text,
      textInserted: c,
      insertionOffset: at,
      selection: TextSelection.collapsed(offset: after),
      composing: TextRange.empty,
    ),
    s,
    standardCharacterShortcutEvents,
  );
}

String? _violation(EditorState s) {
  if (s.document.root.children.isEmpty) return 'no blocks';
  final sel = s.selection;
  if (sel != null) {
    for (final p in [sel.start, sel.end]) {
      final n = s.getNodeAtPath(p.path);
      if (n == null) return 'caret path ${p.path} has no node';
      final len = n.delta?.length;
      if (len != null && p.offset > len) return 'caret offset ${p.offset} > $len at ${p.path}';
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (var seed = 0; seed < 80; seed++) {
    test('typing session $seed', () async {
      final r = Random(seed);
      final s = _fresh();
      s.selection = Selection.collapsed(Position(path: [0], offset: 5));
      final start = s.document.toJson().toString();
      final typed = StringBuffer();
      final errors = <String>[];
      await runZonedGuarded(() async {
        for (var i = 0; i < 60 && errors.isEmpty; i++) {
          final c = _alphabet[r.nextInt(_alphabet.length)];
          typed.write(c == '\n' ? '⏎' : c);
          await _type(s, c);
          await Future<void>.delayed(Duration.zero);
          final v = _violation(s);
          if (v != null) errors.add('after "$typed": $v');
        }
        var g = 0;
        while (errors.isEmpty && s.undoManager.undoStack.isNonEmpty && g++ < 300) {
          s.undoManager.undo();
          await Future<void>.delayed(Duration.zero);
        }
        if (errors.isEmpty && s.undoManager.undoStack.isEmpty && g < 300 && s.document.toJson().toString() != start) {
          errors.add('undo-all did not restore the start after "$typed"');
        }
      }, (e, st) => errors.add('threw $e after "$typed"\n$st'));
      if (errors.isNotEmpty) fail('seed $seed ${errors.first}');
    });
  }
}
