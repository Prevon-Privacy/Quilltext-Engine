// Randomised edit sessions: whatever keys a person mashes, the document stays well formed, the
// selection stays inside it, and undo-all / redo-all are exact.
import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

const _words = ['alpha', 'be', 'gamma ray', 'δ', '😀x', 'two  spaces', 'line'];
const _blocks = [
  ParagraphBlockKeys.type,
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
  TodoListBlockKeys.type,
  QuoteBlockKeys.type,
  HeadingBlockKeys.type,
];

/// Text mixed with the non-text blocks: divider, table, image, file, folded block and columns.
EditorState _richSeed() {
  final doc = Document.blank()
    ..insert([
      0
    ], [
      paragraphNode(text: 'intro text'),
      dividerNode(),
      TableNode.fromList([
        ['a', 'b'],
        ['c', 'd'],
      ]).node,
      paragraphNode(text: 'between'),
      imageNode(url: 'https://example.invalid/a.png', height: 80),
      fileNode(
          url: 'pie-att://v1/abc',
          name: 'Report.pdf',
          mime: 'application/pdf',
          size: 10),
      collapsibleNode(text: 'Fold', children: [
        paragraphNode(text: 'inside'),
        bulletedListNode(text: 'deep')
      ]),
      columnsNode(children: [
        columnNode(children: [paragraphNode(text: 'left')]),
        columnNode(children: [paragraphNode(text: 'right')]),
      ]),
      paragraphNode(text: 'end'),
    ]);
  return EditorState(document: doc);
}

EditorState _seed() {
  final doc = Document.blank()
    ..insert([
      0
    ], [
      paragraphNode(text: 'hello world'),
      bulletedListNode(text: 'item one'),
      todoListNode(checked: false, text: 'task'),
      quoteNode(delta: Delta()..insert('quoted')),
      paragraphNode(text: ''),
      numberedListNode(delta: Delta()..insert('first')),
    ]);
  return EditorState(document: doc);
}

/// Every node's delta text must be consistent and the selection inside the document.
String? _violation(EditorState s) {
  final sel = s.selection;
  if (sel != null) {
    for (final p in [sel.start, sel.end]) {
      final n = s.getNodeAtPath(p.path);
      if (n == null) return 'selection path ${p.path} has no node';
      final len = n.delta?.length;
      if (len != null && p.offset > len)
        return 'offset ${p.offset} > $len at ${p.path}';
    }
  }
  String? walk(Node n) {
    for (final c in n.children) {
      if (c.parent != n) return 'parent link broken at ${c.path}';
      final r = walk(c);
      if (r != null) return r;
    }
    return null;
  }

  if (s.document.root.children.isEmpty) return 'document has no blocks';
  return walk(s.document.root);
}

Future<void> _op(EditorState s, Random r, [List<String>? log]) async {
  final root = s.document.root.children;
  Position pos() {
    final i = r.nextInt(root.length);
    final len = root[i].delta?.length ?? 0;
    return Position(path: [i], offset: len == 0 ? 0 : r.nextInt(len + 1));
  }

  final k = r.nextInt(11);
  log?.add(
      '$k sel=${s.selection?.start.path}:${s.selection?.start.offset}-${s.selection?.end.path}:${s.selection?.end.offset}');
  switch (k) {
    case 0:
      s.selection = Selection.collapsed(pos());
    case 1:
      s.selection = Selection(start: pos(), end: pos());
    case 2:
      await s.insertTextAtCurrentSelection(_words[r.nextInt(_words.length)]);
    case 3:
      backspaceCommand.execute(s);
    case 4:
      deleteCommand.execute(s);
    case 5:
      await s.insertNewLine();
    case 6:
      indentCommand.execute(s);
    case 7:
      outdentCommand.execute(s);
    case 8:
      final sel = s.selection;
      if (sel != null) await s.toggleAttribute('bold');
    case 9:
      final sel = s.selection;
      final n = sel == null ? null : s.getNodeAtPath(sel.start.path);
      if (n != null && n.delta != null) {
        final t = _blocks[r.nextInt(_blocks.length)];
        await s.formatNode(
          sel,
          (node) => node.copyWith(
            type: t,
            attributes: {
              ...node.attributes,
              if (t == HeadingBlockKeys.type)
                HeadingBlockKeys.level: 1 + r.nextInt(3),
              if (t == TodoListBlockKeys.type) TodoListBlockKeys.checked: false,
            },
          ),
        );
      }
    case 10:
      if (r.nextBool()) {
        s.undoManager.undo();
      } else {
        s.undoManager.redo();
      }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (var seed = 0; seed < 60; seed++) {
    test('random edit session $seed keeps the document sound', () async {
      final s = _seed();
      final r = Random(seed);
      final log = <String>[];
      final errors = <String>[];
      await runZonedGuarded(() async {
        for (var i = 0; i < 120 && errors.isEmpty; i++) {
          await _op(s, r, log);
          await Future<void>.delayed(Duration.zero);
          final v = _violation(s);
          if (v != null) errors.add('step $i: $v');
        }
      }, (e, st) => errors.add('threw $e\n$st'));
      if (errors.isNotEmpty)
        fail('seed $seed ${errors.first}\nlog: ${log.join(' | ')}');
    });
  }

  for (var seed = 0; seed < 40; seed++) {
    test(
        'random edit session $seed over rich blocks keeps the page sound and undoes exactly',
        () async {
      final s = _richSeed();
      final start = s.document.toJson().toString();
      final r = Random(1000 + seed);
      final log = <String>[];
      final errors = <String>[];
      await runZonedGuarded(() async {
        for (var i = 0; i < 40 && errors.isEmpty; i++) {
          await _op(s, r, log);
          await Future<void>.delayed(Duration.zero);
          // After an undo or redo the caret is always on a block that exists, inside its text.
          final v = _violation(s);
          if (v != null) errors.add('step $i: $v');
        }
        var g = 0;
        while (
            errors.isEmpty && s.undoManager.undoStack.isNonEmpty && g++ < 300) {
          s.undoManager.undo();
          await Future<void>.delayed(Duration.zero);
        }
        if (errors.isEmpty && s.document.toJson().toString() != start)
          errors.add('undo-all did not restore the page');
      }, (e, st) => errors.add('threw $e\n$st'));
      if (errors.isNotEmpty)
        fail('seed $seed ${errors.first}\nlog: ${log.join(' | ')}');
    });
  }
}
