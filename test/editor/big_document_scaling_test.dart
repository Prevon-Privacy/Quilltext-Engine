// Headless cost of whole-note operations at 1k and 4k blocks. Four times the blocks should cost about four
// times as much; a ratio far above that means an operation walks the whole page per block.
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

EditorState _doc(int n) => EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          for (var i = 0; i < n; i++)
            switch (i % 4) {
              0 => bulletedListNode(text: 'item $i with a few words'),
              1 => numberedListNode(
                  delta: Delta()..insert('step $i with a few words')),
              2 => todoListNode(
                  checked: i % 8 == 2, text: 'task $i with a few words'),
              _ =>
                paragraphNode(text: 'paragraph $i with some **words** in it'),
            },
        ]),
    )..disableSealTimer = true;

int _us(void Function() f) {
  final sw = Stopwatch()..start();
  f();
  return sw.elapsedMicroseconds;
}

Future<int> _usAsync(Future<void> Function() f) async {
  final sw = Stopwatch()..start();
  await f();
  return sw.elapsedMicroseconds;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('whole-note operations scale roughly linearly', () async {
    final costs = <String, List<int>>{};
    for (final n in [1000, 4000]) {
      final s = _doc(n);
      void put(String k, int us) => (costs[k] ??= []).add(us);
      put(
          'insert text mid-note',
          await _usAsync(() => s.apply(
              s.transaction..insertText(s.getNodeAtPath([n ~/ 2])!, 2, 'x'))));
      put(
          'insert block at top x50',
          await _usAsync(() async {
            for (var i = 0; i < 50; i++) {
              await s.apply(
                  s.transaction..insertNode([0], paragraphNode(text: 'new')));
            }
          }));
      put('getNodeAtPath x2000', _us(() {
        for (var i = 0; i < 2000; i++) {
          s.getNodeAtPath([(i * 7) % s.document.root.children.length]);
        }
      }));
      final all = Selection(
        start: Position(path: [0]),
        end: Position(path: [s.document.root.children.length - 1], offset: 3),
      );
      put('getNodesInSelection all', _us(() => s.getNodesInSelection(all)));
      s.selection = all;
      put('bold whole note', await _usAsync(() => s.toggleAttribute('bold')));
      put('undo bold', await _usAsync(() async => s.undoManager.undo()));
      put('markdown export', _us(() => documentToMarkdown(s.document)));
      final rest = Selection(
        start: Position(path: [0]),
        end: Position(path: [s.document.root.children.length - 1], offset: 3),
      );
      put('delete whole note',
          await _usAsync(() async => s.deleteSelection(rest)));
    }
    final rows = StringBuffer();
    costs.forEach((k, v) => rows.writeln(
        '${k.padRight(26)} 1k=${(v[0] / 1000).toStringAsFixed(1)} ms  4k=${(v[1] / 1000).toStringAsFixed(1)} ms  x${(v[1] / (v[0] < 50 ? 50 : v[0])).toStringAsFixed(1)}'));
    // ignore: avoid_print
    print('SCALING\n$rows');
    // Generous ceilings (a 4000-block page): a slip back to per-block whole-page walks blows well past them.
    for (final e in costs.entries) {
      expect(e.value[1], lessThan(3 * 1000 * 1000),
          reason: '${e.key} took ${e.value[1] / 1000} ms at 4000 blocks');
    }
  });
}
