// Probe: every single edit kind must be exactly undone by one undo-all, from many cursor spots.
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

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final names = ['insertText', 'backspace', 'delete', 'newline', 'indent', 'outdent', 'bold'];
  for (var k = 0; k < names.length; k++) {
    test('${names[k]} is exactly undone from every cursor spot', () async {
      final bad = <String>[];
      for (var blk = 0; blk < 6; blk++) {
        final len = _seed().document.root.children[blk].delta?.length ?? 0;
        for (var off = 0; off <= len; off++) {
          for (final range in [false, true]) {
            final errors = <Object>[];
            await runZonedGuarded(() async {
              final s = _seed();
              final start = s.document.toJson().toString();
              final p = Position(path: [blk], offset: off);
              s.selection = range
                  ? Selection(start: p, end: Position(path: [min(blk + 1, 5)], offset: 0))
                  : Selection.collapsed(p);
              switch (k) {
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
              }
              await _settle();
              var g = 0;
              while (s.undoManager.undoStack.isNonEmpty && g++ < 20) {
                s.undoManager.undo();
                await _settle();
              }
              if (s.document.toJson().toString() != start) {
                errors.add('doc differs after undo');
              }
            }, (e, st) => errors.add(e));
            if (errors.isNotEmpty) bad.add('blk $blk off $off range=$range: ${errors.first}');
          }
        }
      }
      expect(bad, isEmpty);
    });
  }
}
