// Exhaustive indent / outdent / move audit (owner 2026-11-27: "any possible indent or dedent combo ...
// moving indented or dedented stuff anywhere ... it just works").
//
// Unlike the seeded fuzz in test/editor/block_component/indent_move_audit_test.dart, nothing here is random:
//  1. Over several small page shapes, for EVERY selection (a caret in each row, a range from each row to
//     each later row) every sequence of up to 4 of {Tab, Shift+Tab, Cmd+], Cmd+[} is run. Each step must
//     keep the reading order, the block ids, the caret text, be ONE undo step, and undoing everything must
//     give back the starting page.
//  2. After every indent/outdent prefix of up to 2 steps, EVERY (block, slot) pair is dragged with
//     moveBlockTo and moved with Move up/down: no block lost or doubled, the moved row keeps its subtree,
//     everything else keeps its relative order, ids stay, one undo step, undo restores the page.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

import '../editor/block_component/indent_move_audit_test.dart'
    show b, n, todo, p, doc, read, order, ids, caretText, violation, flat;

typedef Shape = List<Node> Function();

final Map<String, Shape> shapes = {
  'flat bullets': () => [b('a'), b('b'), b('c'), b('d')],
  'mixed flat': () => [
        b('a'),
        n('b'),
        todo('c'),
        p('d'),
        headingNode(level: 2, text: 'e'),
      ],
  'one tree': () => [
        b('a', [
          b('a1', [b('a1x')]),
          b('a2'),
        ]),
        b('b'),
        b('c', [b('c1')]),
      ],
  'numbered runs': () => [
        n('a'),
        n('b', [n('b1'), n('b2')]),
        n('c'),
        todo('d', [todo('d1')]),
      ],
  'folded': () => [
        b('a', [b('hidden1'), b('hidden2')])
          ..updateAttributes({blockComponentCollapsed: true}),
        b('b'),
        b('c'),
      ],
  'paragraphs between lists': () => [
        b('a'),
        p('mid'),
        b('b', [b('b1')]),
        p('end'),
      ],
};

const _ops = ['tab', 'shift+tab', 'cmd+]', 'cmd+['];

void _run(EditorState s, String op) {
  switch (op) {
    case 'tab':
      indentCommand.execute(s);
    case 'shift+tab':
      outdentCommand.execute(s);
    case 'cmd+]':
      indentBracketCommand.execute(s);
    case 'cmd+[':
      outdentBracketCommand.execute(s);
  }
}

int _undoLen(EditorState s) => s.undoManager.undoStack.toList().length;

/// Selections to try: a caret at the start/end of each row and a range from each row to each later row.
List<Selection> _selections(EditorState s) {
  final rows = flat(s);
  final out = <Selection>[];
  for (var i = 0; i < rows.length; i++) {
    final len = rows[i].delta?.length ?? 0;
    out.add(Selection.collapsed(Position(path: rows[i].path, offset: 0)));
    if (len > 0) {
      out.add(Selection.collapsed(Position(path: rows[i].path, offset: len)));
    }
    for (var j = i + 1; j < rows.length; j++) {
      out.add(Selection(
        start: Position(path: rows[i].path, offset: 0),
        end: Position(path: rows[j].path, offset: 0),
      ));
    }
  }
  return out;
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in shapes.entries) {
    test('every Tab/Shift+Tab/Cmd+]/Cmd+[ sequence on "${entry.key}"',
        () async {
      final errors = <String>[];
      await runZonedGuarded(() async {
        final probe = doc(entry.value());
        final selections = _selections(probe)
            .map((x) => [
                  x.start.path,
                  x.start.offset,
                  x.end.path,
                  x.end.offset,
                ])
            .toList();
        for (final sel in selections) {
          final range = sel[0].toString() != sel[2].toString();
          final depth = range ? 3 : 4;
          // Walk every sequence by counting in base 4.
          var total = 1;
          for (var i = 0; i < depth; i++) {
            total *= _ops.length;
          }
          for (var code = 0; code < total && errors.isEmpty; code++) {
            final s = doc(entry.value());
            s.selection = Selection(
              start: Position(path: sel[0] as List<int>, offset: sel[1] as int),
              end: Position(path: sel[2] as List<int>, offset: sel[3] as int),
            );
            final start = s.document.toJson().toString();
            final startOrder = order(s);
            final log = <String>[];
            var c = code;
            for (var i = 0; i < depth && errors.isEmpty; i++) {
              final op = _ops[c % _ops.length];
              c ~/= _ops.length;
              final beforeOrder = order(s);
              final beforeIds = ids(s);
              final beforeCaret = caretText(s);
              final undoBefore = _undoLen(s);
              log.add(op);
              _run(s, op);
              await Future<void>.delayed(Duration.zero);
              final tag = '${entry.key} sel=$sel seq=${log.join(',')}';
              final v = violation(s);
              if (v != null) {
                errors.add('$tag: $v');
                break;
              }
              if (_undoLen(s) - undoBefore > 1) {
                errors.add('$tag: one command made several undo steps');
              }
              if (ids(s).join() != beforeIds.join()) {
                errors.add('$tag: block ids changed or reordered');
              }
              if (order(s).join('|') != beforeOrder.join('|')) {
                errors.add('$tag: reading order changed\n'
                    '  before ${beforeOrder.join(',')}\n  after  ${order(s).join(',')}');
              }
              // A caret (not a range) must stay on its own text.
              if (!range &&
                  beforeCaret != null &&
                  caretText(s) != beforeCaret) {
                errors.add(
                    '$tag: caret moved off its text $beforeCaret -> ${caretText(s)}');
              }
            }
            if (errors.isNotEmpty) break;
            if (order(s).join('|') != startOrder.join('|')) {
              errors.add(
                  '${entry.key} sel=$sel seq=${log.join(',')}: final order differs from start');
              break;
            }
            var g = 0;
            while (s.undoManager.undoStack.isNonEmpty && g++ < 50) {
              s.undoManager.undo();
              await Future<void>.delayed(Duration.zero);
            }
            if (s.document.toJson().toString() != start) {
              errors.add(
                  '${entry.key} sel=$sel seq=${log.join(',')}: undo-all did not restore the page');
            }
          }
          if (errors.isNotEmpty) break;
        }
      }, (e, st) => errors.add('threw $e\n$st'));
      if (errors.isNotEmpty) fail(errors.first);
    });

    test('moves after every indent/outdent prefix on "${entry.key}"', () async {
      final errors = <String>[];
      var reordered = 0;
      await runZonedGuarded(() async {
        // Prefixes: none, then every 1 and 2 step sequence, applied to the row at each index.
        final prefixes = <List<String>>[
          [],
          for (final a in _ops) [a],
          for (final a in _ops)
            for (final bb in _ops) [a, bb],
        ];
        final rowCount = flat(doc(entry.value())).length;
        for (var rowIdx = 0; rowIdx < rowCount && errors.isEmpty; rowIdx++) {
          for (final prefix in prefixes) {
            if (errors.isNotEmpty) break;
            // Build the prepared page once to learn its rows, then try every move on a fresh copy.
            EditorState prepared() {
              final s = doc(entry.value());
              final row = flat(s)[rowIdx];
              s.selection =
                  Selection.collapsed(Position(path: row.path, offset: 0));
              for (final op in prefix) {
                _run(s, op);
              }
              s.undoManager.undoStack.clear();
              return s;
            }

            final base = prepared();
            final rows = flat(base).length;
            final baseDoc = base.document.toJson().toString();
            final baseIds = order(base);
            for (var from = 0; from < rows && errors.isEmpty; from++) {
              for (var to = 0; to < rows; to++) {
                for (final after in [false, true]) {
                  final s = prepared();
                  final all = flat(s);
                  final pick = all[from];
                  final target = all[to];
                  final subtree = <String>[];
                  void collect(Node x) {
                    subtree.add(x.delta?.toPlainText() ?? x.type);
                    x.children.forEach(collect);
                  }

                  collect(pick);
                  final slot = after ? target.path.next : target.path;
                  final tag =
                      '${entry.key} row=$rowIdx prefix=${prefix.join(',')} move ${pick.path}->$slot '
                      'doc=${read(s).join(',')}';
                  // Dropping a row inside its own subtree is not a legal move; the command must refuse
                  // cleanly (no change).
                  moveBlockTo(s, pick, slot);
                  await Future<void>.delayed(Duration.zero);
                  final v = violation(s);
                  if (v != null) {
                    errors.add('$tag: $v');
                    break;
                  }
                  final nowIds = order(s);
                  if (nowIds.length != baseIds.length ||
                      nowIds.toSet().length != baseIds.length ||
                      !nowIds.toSet().containsAll(baseIds)) {
                    errors.add(
                        '$tag: blocks lost or doubled: ${read(s).join(',')}');
                    break;
                  }
                  // The moved subtree stays contiguous, in its own order.
                  final at =
                      nowIds.indexOf(pick.delta?.toPlainText() ?? pick.type);
                  if (at < 0 ||
                      nowIds.sublist(at, at + subtree.length).join() !=
                          subtree.join()) {
                    errors.add(
                        '$tag: moved subtree broken: ${read(s).join(',')}');
                    break;
                  }
                  // Everything else keeps its relative order.
                  final others = nowIds.where((x) => !subtree.contains(x));
                  final baseOthers = baseIds.where((x) => !subtree.contains(x));
                  if (others.join() != baseOthers.join()) {
                    errors.add(
                        '$tag: other rows reordered: ${read(s).join(',')}');
                    break;
                  }
                  if (_undoLen(s) > 1) {
                    errors.add('$tag: one move made ${_undoLen(s)} undo steps');
                    break;
                  }
                  if (nowIds.join() != baseIds.join()) reordered++;
                  var g = 0;
                  while (s.undoManager.undoStack.isNonEmpty && g++ < 10) {
                    s.undoManager.undo();
                    await Future<void>.delayed(Duration.zero);
                  }
                  if (s.document.toJson().toString() != baseDoc) {
                    errors.add('$tag: undo did not restore the page');
                    break;
                  }
                }
                if (errors.isNotEmpty) break;
              }
            }
            // Move up / down from every row.
            for (var from = 0; from < rows && errors.isEmpty; from++) {
              for (final up in [true, false]) {
                final s = prepared();
                final pick = flat(s)[from];
                s.selection =
                    Selection.collapsed(Position(path: pick.path, offset: 0));
                final beforeIds = order(s);
                final tag =
                    '${entry.key} row=$rowIdx prefix=${prefix.join(',')} moveRows ${up ? 'up' : 'down'} from=$from '
                    'doc=${read(s).join(',')}';
                moveRows(s, up: up);
                await Future<void>.delayed(Duration.zero);
                final v = violation(s);
                if (v != null) {
                  errors.add('$tag: $v');
                  break;
                }
                final nowIds = order(s);
                if (nowIds.length != beforeIds.length ||
                    nowIds.toSet().length != beforeIds.length) {
                  errors.add(
                      '$tag: blocks lost or doubled: ${read(s).join(',')}');
                  break;
                }
                if (_undoLen(s) > 1) {
                  errors.add('$tag: one move made ${_undoLen(s)} undo steps');
                  break;
                }
              }
            }
          }
        }
      }, (e, st) => errors.add('threw $e\n$st'));
      if (errors.isNotEmpty) fail(errors.first);
      expect(reordered, greaterThan(20),
          reason: 'the move cases must really move rows, not all be refused');
    });
  }
}
