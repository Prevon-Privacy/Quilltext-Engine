// Structural edits at random: table rows and columns (add, delete, duplicate, clear), block moves, deletes,
// duplicates and fold toggles. After every step the page is sound (a table has exactly rows x columns
// cells, each at its own place; the caret sits on a real block), and undoing everything restores the start.
import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

EditorState _seed() => EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          paragraphNode(text: 'intro'),
          TableNode.fromList([
            ['a', 'b', 'c'],
            ['d', 'e', 'f'],
          ]).node,
          paragraphNode(text: 'between'),
          collapsibleNode(text: 'Fold', children: [
            paragraphNode(text: 'inside'),
            bulletedListNode(text: 'deep')
          ]),
          dividerNode(),
          paragraphNode(text: 'end'),
        ]),
    )..disableSealTimer = true;

String? _violation(EditorState s) {
  if (s.document.root.children.isEmpty) return 'no blocks';
  String? walk(Node n) {
    if (n.type == TableBlockKeys.type) {
      final rows = n.attributes[TableBlockKeys.rowsLen] as int;
      final cols = n.attributes[TableBlockKeys.colsLen] as int;
      if (n.children.length != rows * cols)
        return 'table ${n.path} has ${n.children.length} cells, not $rows x $cols';
      final seen = <String>{};
      for (final c in n.children) {
        final r = c.attributes[TableCellBlockKeys.rowPosition] as int;
        final k = c.attributes[TableCellBlockKeys.colPosition] as int;
        if (r < 0 || r >= rows || k < 0 || k >= cols)
          return 'cell at $r,$k outside $rows x $cols';
        if (!seen.add('$r,$k')) return 'two cells at $r,$k';
      }
    }
    for (final c in n.children) {
      if (c.parent != n) return 'parent link broken at ${c.path}';
      final r = walk(c);
      if (r != null) return r;
    }
    return null;
  }

  final w = walk(s.document.root);
  if (w != null) return w;
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

Node? _table(EditorState s) {
  for (final n in s.document.root.children) {
    if (n.type == TableBlockKeys.type) return n;
  }
  return null;
}

Future<void> _op(EditorState s, Random r, List<String> log) async {
  final kind = r.nextInt(10);
  final root = s.document.root.children;
  final t = _table(s);
  log.add('$kind');
  switch (kind) {
    case 0 || 1 || 2 || 3:
      if (t == null) return;
      final dir = r.nextBool() ? TableDirection.row : TableDirection.col;
      final count = dir == TableDirection.row
          ? t.attributes[TableBlockKeys.rowsLen] as int
          : t.attributes[TableBlockKeys.colsLen] as int;
      final pos = r.nextInt(count);
      switch (kind) {
        case 0:
          TableActions.add(t, pos, s, dir);
        case 1:
          if (count > 1) TableActions.delete(t, pos, s, dir);
        case 2:
          TableActions.duplicate(t, pos, s, dir);
        case 3:
          TableActions.clear(t, pos, s, dir);
      }
    case 4:
      if (root.length < 2) return;
      final from = r.nextInt(root.length);
      var to = r.nextInt(root.length);
      if (to == from) return;
      final node = root[from];
      await s.apply(s.transaction..moveNode([to], node));
    case 5:
      if (root.length < 2) return;
      final node = root[r.nextInt(root.length)];
      await s.apply(s.transaction..deleteNode(node));
    case 6:
      final node = root[r.nextInt(root.length)];
      if (node.type == TableBlockKeys.type)
        return; // a copied table would need fresh cell ids: not an editor action
      await s.apply(s.transaction..insertNode(node.path.next, node.deepCopy()));
    case 7:
      final fold =
          root.where((n) => n.type == CollapsibleBlockKeys.type).firstOrNull;
      if (fold == null) return;
      await s.apply(s.transaction
        ..updateNode(fold, {
          CollapsibleBlockKeys.collapsed:
              !(fold.attributes[CollapsibleBlockKeys.collapsed] == true)
        }));
    case 8:
      final i = r.nextInt(root.length);
      final len = root[i].delta?.length ?? 0;
      s.selection = Selection.collapsed(
          Position(path: [i], offset: len == 0 ? 0 : r.nextInt(len + 1)));
    case 9:
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
    test(
        'structural session $seed keeps tables and blocks sound and undoes exactly',
        () async {
      final s = _seed();
      final start = s.document.toJson().toString();
      final r = Random(7000 + seed);
      final log = <String>[];
      final errors = <String>[];
      await runZonedGuarded(() async {
        for (var i = 0; i < 40 && errors.isEmpty; i++) {
          await _op(s, r, log);
          await Future<void>.delayed(Duration.zero);
          final v = _violation(s);
          if (v != null) errors.add('step $i (${log.last}): $v');
        }
        var g = 0;
        while (
            errors.isEmpty && s.undoManager.undoStack.isNonEmpty && g++ < 300) {
          s.undoManager.undo();
          await Future<void>.delayed(Duration.zero);
          final v = _violation(s);
          if (v != null) errors.add('while undoing: $v');
        }
        if (errors.isEmpty && s.document.toJson().toString() != start)
          errors.add('undo-all did not restore the page');
      }, (e, st) => errors.add('threw $e\n$st'));
      if (errors.isNotEmpty)
        fail('seed $seed ${errors.first}\nlog: ${log.join(',')}');
    });
  }
}
