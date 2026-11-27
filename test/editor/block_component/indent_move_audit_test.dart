// Audit of indent, outdent and move (owner report 2026-11-26: "a ton of issues
// moving, indenting, dedenting"). Two parts:
//  1. A seeded fuzz over the real commands (Tab, Shift+Tab, Ctrl/Cmd+] [, Move up/down, moveBlockTo,
//     undo, redo). Indent and outdent must never change the reading order, ids stay, the caret stays on
//     the same text, one command is ONE undo step, and undoing everything restores the start.
//  2. Named cases for each bug the audit confirmed.
import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

Node b(String t, [List<Node> kids = const []]) =>
    bulletedListNode(text: t, children: kids);
Node n(String t, [List<Node> kids = const []]) =>
    numberedListNode(delta: Delta()..insert(t), children: kids);
Node todo(String t, [List<Node> kids = const []]) =>
    todoListNode(checked: false, text: t, children: kids);
Node p(String t) => paragraphNode(text: t);

EditorState doc(List<Node> top) =>
    EditorState(document: Document.blank()..insert([0], top))
      ..disableSealTimer = true;

/// Depth-first "text@depth" reading of the whole document.
List<String> read(EditorState s) {
  final out = <String>[];
  void walk(Node x, int d) {
    out.add('${x.delta?.toPlainText() ?? x.type}@$d');
    for (final c in x.children) {
      walk(c, d + 1);
    }
  }

  for (final x in s.document.root.children) {
    walk(x, 0);
  }
  return out;
}

List<String> order(EditorState s) =>
    [for (final r in read(s)) r.substring(0, r.lastIndexOf('@'))];

List<String> ids(EditorState s) {
  final out = <String>[];
  void walk(Node x) {
    out.add(x.id);
    x.children.forEach(walk);
  }

  s.document.root.children.forEach(walk);
  return out;
}

String? caretText(EditorState s) {
  final sel = s.selection;
  if (sel == null) return null;
  final node = s.getNodeAtPath(sel.start.path);
  return '${node?.delta?.toPlainText()}@${sel.start.offset}';
}

String? violation(EditorState s) {
  String? walk(Node x) {
    for (final c in x.children) {
      if (c.parent != x) return 'parent link broken at ${c.path}';
      final r = walk(c);
      if (r != null) return r;
    }
    return null;
  }

  final w = walk(s.document.root);
  if (w != null) return w;
  final sel = s.selection;
  if (sel == null) return null;
  for (final pos in [sel.start, sel.end]) {
    final node = s.getNodeAtPath(pos.path);
    if (node == null) return 'caret path ${pos.path} has no node';
    final len = node.delta?.length;
    if (len != null && pos.offset > len) {
      return 'caret offset ${pos.offset} > $len at ${pos.path}';
    }
  }
  return null;
}

List<Node> seedBlocks(Random r) {
  var k = 0;
  Node leaf() {
    final t = 'r${k++}';
    return switch (r.nextInt(5)) {
      0 => n(t),
      1 => todo(t),
      2 => p(t),
      3 => headingNode(level: 2, text: t),
      _ => b(t),
    };
  }

  Node tree(int depth) {
    final t = 'r${k++}';
    final kids = depth == 0
        ? <Node>[]
        : [for (var i = 0; i < r.nextInt(3); i++) r.nextBool() ? tree(depth - 1) : leaf()];
    return switch (r.nextInt(4)) {
      0 => n(t, kids),
      1 => todo(t, kids),
      _ => b(t, kids),
    };
  }

  return [
    for (var i = 0; i < 4 + r.nextInt(4); i++) r.nextInt(3) == 0 ? leaf() : tree(2),
  ];
}

List<Node> flat(EditorState s) {
  final out = <Node>[];
  void walk(Node x) {
    out.add(x);
    x.children.forEach(walk);
  }

  s.document.root.children.forEach(walk);
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (var seed = 0; seed < 80; seed++) {
    test('indent/outdent/move session $seed keeps order, ids, caret and undo exact',
        () async {
      final r = Random(26110 + seed);
      final s = doc(seedBlocks(r));
      final start = s.document.toJson().toString();
      final log = <String>[];
      final errors = <String>[];
      await runZonedGuarded(() async {
        for (var i = 0; i < 40 && errors.isEmpty && s.undoManager.undoStack.toList().length < 18; i++) {
          final all = flat(s);
          final pick = all[r.nextInt(all.length)];
          final len = pick.delta?.length ?? 0;
          // Half the time a range over two rows, else a caret.
          if (r.nextInt(3) == 0 && all.length > 1) {
            final other = all[r.nextInt(all.length)];
            s.selection = Selection(
              start: Position(path: pick.path, offset: 0),
              end: Position(path: other.path, offset: 0),
            );
          } else {
            s.selection = Selection.collapsed(
                Position(path: pick.path, offset: len == 0 ? 0 : r.nextInt(len + 1)));
          }
          final op = r.nextInt(8);
          final beforeOrder = order(s);
          final beforeIds = ids(s);
          final beforeCaret = caretText(s);
          final undoBefore = s.undoManager.undoStack.toList().length;
          log.add('op$op sel=${s.selection?.start.path}:${s.selection?.start.offset}-${s.selection?.end.path} doc=${read(s).join(',')}');
          var keepsOrder = false;
          switch (op) {
            case 0:
              indentCommand.execute(s);
              keepsOrder = true;
            case 1:
              outdentCommand.execute(s);
              keepsOrder = true;
            case 2:
              indentBracketCommand.execute(s);
              keepsOrder = true;
            case 3:
              outdentBracketCommand.execute(s);
              keepsOrder = true;
            case 4:
              moveRows(s, up: true);
            case 5:
              moveRows(s, up: false);
            case 6:
              final target = all[r.nextInt(all.length)];
              final slot = r.nextBool() ? target.path : target.path.next;
              log.add('  move ${pick.path} -> $slot');
              moveBlockTo(s, pick, slot);
            case 7:
              if (r.nextBool()) {
                s.undoManager.undo();
              } else {
                s.undoManager.redo();
              }
          }
          await Future<void>.delayed(Duration.zero);
          final v = violation(s);
          if (v != null) {
            errors.add('step $i (${log.last}): $v');
            break;
          }
          if (op == 7) continue;
          final grew = s.undoManager.undoStack.toList().length - undoBefore;
          if (grew > 1) errors.add('step $i (${log.last}): one command made $grew undo steps');
          if (ids(s).toSet().length != beforeIds.toSet().length) {
            errors.add('step $i (${log.last}): block ids changed');
          }
          if (keepsOrder && order(s).join('|') != beforeOrder.join('|')) {
            errors.add('step $i (${log.last}): reading order changed\n'
                '  before ${beforeOrder.join(',')}\n  after  ${order(s).join(',')}');
          }
          if (keepsOrder && selectionStaysPut(beforeCaret) && caretText(s) != beforeCaret) {
            errors.add('step $i (${log.last}): caret moved off its text '
                '$beforeCaret -> ${caretText(s)}');
          }
        }
        var g = 0;
        while (errors.isEmpty && s.undoManager.undoStack.isNonEmpty && g++ < 400) {
          s.undoManager.undo();
          await Future<void>.delayed(Duration.zero);
          final v = violation(s);
          if (v != null) errors.add('while undoing: $v');
        }
        if (errors.isEmpty && s.document.toJson().toString() != start) {
          errors.add('undo-all did not restore the page');
        }
      }, (e, st) => errors.add('threw $e\n$st'));
      if (errors.isNotEmpty) {
        fail('seed $seed ${errors.first}\nlog: ${log.join(' ')}');
      }
    });
  }

  group('named cases', () {
    test('Enter in a folded bullet keeps its children folded on the new row',
        () async {
      final s = doc([
        b('A', [b('hidden')])..updateAttributes({blockComponentCollapsed: true}),
      ]);
      s.selection = Selection.collapsed(Position(path: [0], offset: 1));
      await s.insertNewLine(nodeBuilder: (x) => x.copyWith(type: BulletedListBlockKeys.type));
      expect(read(s), ['A@0', '@0', 'hidden@1']);
      expect(s.getNodeAtPath([1])!.attributes[blockComponentCollapsed], true);
      expect(s.getNodeAtPath([0])!.attributes[blockComponentCollapsed], isNot(true));
    });

    test('a same-level drag keeps the caret on its text', () {
      final s = doc([p('A'), p('B'), p('C')]);
      s.selection = Selection.collapsed(Position(path: [2], offset: 1));
      moveNodeAmongSiblings(s, s.getNodeAtPath([0])!, 3);
      expect(order(s), ['B', 'C', 'A']);
      expect(caretText(s), 'C@1');
    });

    test('indent and outdent keep a caret in a later block on its text', () {
      final s = doc([b('A'), b('B'), b('C')]);
      s.selection = Selection.collapsed(Position(path: [2], offset: 1));
      indentBlocks(s, [s.getNodeAtPath([1])!]);
      expect(caretText(s), 'C@1');
      outdentBlocks(s, [s.getNodeAtPath([0, 0])!]);
      expect(caretText(s), 'C@1');
    });

    test('Delete at the end of a heading does not bury the next row\'s children',
        () {
      final s = doc([
        headingNode(level: 2, text: 'H'),
        b('B', [b('b1')]),
      ]);
      s.selection = Selection.collapsed(Position(path: [0], offset: 1));
      deleteCommand.execute(s);
      expect(read(s), ['HB@0', 'b1@0'],
          reason: 'a heading draws no children: they must not nest under it');
    });

    test('Delete at the end of a folded title does not pull in a hidden row', () {
      final s = doc([
        b('A', [b('hidden')])..updateAttributes({blockComponentCollapsed: true}),
        b('B'),
      ]);
      s.selection = Selection.collapsed(Position(path: [0], offset: 1));
      deleteCommand.execute(s);
      expect(read(s), ['A@0', 'hidden@1', 'B@0']);
    });

    test('Backspace after a folded block merges into its visible title', () {
      final s = doc([
        b('A', [b('hidden')])..updateAttributes({blockComponentCollapsed: true}),
        p('P'),
      ]);
      s.selection = Selection.collapsed(Position(path: [1], offset: 0));
      backspaceCommand.execute(s);
      expect(read(s), ['AP@0', 'hidden@1']);
      expect(s.selection!.start.path, [0]);
    });

    test('Enter on an empty bullet under a heading clears the style', () async {
      final s = doc([
        headingNode(level: 2, text: 'H'),
      ]);
      s.document.insert([0, 0], [b('')]);
      s.selection = Selection.collapsed(Position(path: [0, 0]));
      final done = await insertNewLineInType(s, BulletedListBlockKeys.type);
      expect(done, isTrue);
      expect(s.getNodeAtPath([0, 0])!.type, ParagraphBlockKeys.type,
          reason: 'the heading is not a list parent: Enter used to do nothing');
    });

    test('outdent never adopts the rows below into a folded block', () {
      final s = doc([
        b('A', [
          b('T', [b('t1')])..updateAttributes({blockComponentCollapsed: true}),
          b('S1'),
        ]),
      ]);
      outdentBlocks(s, [s.getNodeAtPath([0, 0])!]);
      expect(read(s), ['A@0', 'T@0', 't1@1', 'S1@0']);
    });

    test('moveBlockTo lands before the slot it was given (same level)', () {
      final s = doc([p('A'), p('B'), p('C'), p('D')]);
      moveBlockTo(s, s.getNodeAtPath([0])!, [3]);
      expect(order(s), ['B', 'C', 'A', 'D']);
    });

    test('moveBlockTo into a later sibling lands at the slot, caret follows', () {
      final s = doc([
        b('A'),
        b('B', [b('b0'), b('b1')]),
      ]);
      s.selection = Selection.collapsed(Position(path: [1, 1], offset: 0));
      moveBlockTo(s, s.getNodeAtPath([0])!, [1, 1]);
      expect(read(s), ['B@0', 'b0@1', 'A@1', 'b1@1']);
      expect(caretText(s), 'b1@0');
    });

    test('Tab into a collapsed block opens it so the caret stays visible', () {
      final s = doc([
        b('A', [b('a1')])..updateAttributes({blockComponentCollapsed: true}),
        b('B'),
      ]);
      s.selection = Selection.collapsed(Position(path: [1], offset: 1));
      indentCommand.execute(s);
      expect(read(s), ['A@0', 'a1@1', 'B@1']);
      expect(s.getNodeAtPath([0])!.attributes[blockComponentCollapsed], isNot(true),
          reason: 'the moved row would be hidden with the caret inside it');
    });

    test('Shift+Tab with a range from a nested row to a top-level row outdents the nested part',
        () {
      final s = doc([
        b('A', [b('x'), b('y')]),
        b('z'),
      ]);
      s.selection = Selection(
        start: Position(path: [0, 0]),
        end: Position(path: [1]),
      );
      outdentCommand.execute(s);
      expect(order(s), ['A', 'x', 'y', 'z']);
      expect(s.getNodeAtPath([1])!.delta!.toPlainText(), 'x',
          reason: 'the nested rows in the range should have left their parent');
    });
  });
}

// A range selection's start is the caret we compare; both kinds have one.
bool selectionStaysPut(String? caret) => caret != null;
