// Pasting blocks over random carets and ranges: nothing the person had typed outside the selection is
// lost, the caret lands inside the document, and one undo per paste puts the page back exactly.
import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

import '../support/random_docs.dart';

const _words = ['alpha', 'be', 'gamma ray', 'δ', '😀x', 'line', ''];

Node _text(Random r) {
  final t = _words[r.nextInt(_words.length)];
  return switch (r.nextInt(6)) {
    0 => bulletedListNode(text: t),
    1 => todoListNode(checked: false, text: t),
    2 => quoteNode(delta: Delta()..insert(t)),
    3 => headingNode(level: 1 + r.nextInt(3), text: t),
    4 => numberedListNode(delta: Delta()..insert(t)),
    _ => paragraphNode(text: t),
  };
}

Node _pasted(Random r) {
  final n = r.nextInt(8);
  if (n == 0) return dividerNode();
  final node = _text(r);
  if (n == 1) node.insert(_text(r));
  return node;
}

String? _violation(EditorState s) {
  if (s.document.root.children.isEmpty) return 'no blocks';
  final sel = s.selection;
  if (sel == null) return null;
  for (final p in [sel.start, sel.end]) {
    final n = s.getNodeAtPath(p.path);
    if (n == null) return 'caret path ${p.path} has no node';
    final len = n.delta?.length;
    if (len != null && p.offset > len)
      return 'caret offset ${p.offset} > $len at ${p.path}';
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (var seed = 0; seed < 200; seed++) {
    test('paste session $seed loses nothing outside the selection', () async {
      final r = Random(seed);
      // Every block has text, so ranges have width.
      final nodes = [
        for (var i = 0; i < 2 + r.nextInt(4); i++)
          switch (r.nextInt(3)) {
            0 => bulletedListNode(text: 'item ${r.nextInt(99)} here'),
            1 => paragraphNode(text: 'para ${r.nextInt(99)} text'),
            _ =>
              quoteNode(delta: Delta()..insert('quote ${r.nextInt(99)} text')),
          },
      ];
      final s = EditorState(document: Document.blank()..insert([0], nodes));
      final startJson = s.document.toJson().toString();

      final a = r.nextInt(nodes.length);
      final b = r.nextBool() ? a : r.nextInt(nodes.length);
      final aLen = nodeText(s.document.root.children[a]).length;
      final bLen = nodeText(s.document.root.children[b]).length;
      final from = Position(path: [a], offset: r.nextInt(aLen + 1));
      final to = Position(path: [b], offset: r.nextInt(bLen + 1));
      final sel = Selection(start: from, end: to).normalized;
      s.selection = sel;
      final first = s.document.root.children[sel.start.path.first];
      final last = s.document.root.children[sel.end.path.first];
      final keepBefore = nodeText(first).substring(0, sel.start.offset);
      final keepAfter = nodeText(last).substring(sel.end.offset);
      final untouched = <String>[
        for (var i = 0; i < nodes.length; i++)
          if (i < sel.start.path.first || i > sel.end.path.first)
            nodeText(s.document.root.children[i]),
      ];

      final count = 1 + r.nextInt(4);
      final pasted = [for (var i = 0; i < count; i++) _pasted(r)];
      final errors = <String>[];
      await runZonedGuarded(() async {
        if (pasted.length == 1) {
          await s.pasteSingleLineNode(pasted.single);
        } else {
          await s.pasteMultiLineNodes(pasted);
        }
        await Future<void>.delayed(Duration.zero);
        final v = _violation(s);
        if (v != null) errors.add(v);
        final texts = [
          for (final n in s.document.root.children) ..._allText(n)
        ];
        final joined = texts.join('\n');
        if (keepBefore.isNotEmpty &&
            !texts.any((t) => t.startsWith(keepBefore))) {
          errors.add('text before the caret "$keepBefore" is gone: $texts');
        }
        if (keepAfter.isNotEmpty && !texts.any((t) => t.endsWith(keepAfter))) {
          errors.add('text after the selection "$keepAfter" is gone: $texts');
        }
        for (final u in untouched) {
          if (u.isNotEmpty && !joined.contains(u))
            errors.add('untouched block "$u" is gone: $texts');
        }
        var g = 0;
        while (
            errors.isEmpty && s.undoManager.undoStack.isNonEmpty && g++ < 20) {
          s.undoManager.undo();
          await Future<void>.delayed(Duration.zero);
        }
        if (errors.isEmpty && s.document.toJson().toString() != startJson) {
          errors.add('undo did not restore the page');
        }
      }, (e, st) => errors.add('threw $e\n$st'));
      if (errors.isNotEmpty) {
        fail(
            'seed $seed sel=${sel.start.path}:${sel.start.offset}-${sel.end.path}:${sel.end.offset} '
            'pasted=${pasted.map(nodeSignature).join(' / ')}\n${errors.first}');
      }
    });
  }
}

Iterable<String> _allText(Node n) sync* {
  if (n.delta != null) yield nodeText(n);
  for (final c in n.children) {
    yield* _allText(c);
  }
}
