// The document model's cost per keystroke, with no widgets: build a long note,
// type into it, and time what `EditorState.apply` does (parse the block's delta,
// compose, write it back, notify, record undo). It prints microseconds per key
// so a change to core/ can be compared before and after; the asserts are loose
// ceilings that only catch an order-of-magnitude regression, not machine noise.
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

EditorState _note(int blocks) => EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          for (var i = 0; i < blocks; i++)
            paragraphNode(text: 'Paragraph $i with some words to lay out.'),
        ]),
    )..disableSealTimer = true;

Future<double> _typeMicrosPerKey(EditorState state, List<int> path, int keys,
    {int startOffset = 5}) async {
  final node = state.getNodeAtPath(path)!;
  final sw = Stopwatch()..start();
  for (var i = 0; i < keys; i++) {
    await state.apply(state.transaction
      ..insertText(node, startOffset + i, 'x')
      ..afterSelection = Selection.collapsed(
          Position(path: path, offset: startOffset + i + 1)));
  }
  sw.stop();
  return sw.elapsedMicroseconds / keys;
}

void main() {
  test('typing in a 2000-block note costs well under a frame per key',
      () async {
    final state = _note(2000);
    await _typeMicrosPerKey(state, [1000], 50); // warm up the JIT
    final us = await _typeMicrosPerKey(state, [1000], 400, startOffset: 60);
    // ignore: avoid_print
    print('MODEL_SPEED short block in 2000: ${us.toStringAsFixed(0)} us/key');
    expect(us, lessThan(4000));
  });

  test('typing into one very long block stays flat per key', () async {
    final state = EditorState(
      document: Document.blank()
        ..insert([0], [paragraphNode(text: 'word ' * 4000)]),
    )..disableSealTimer = true;
    await _typeMicrosPerKey(state, [0], 50);
    final us = await _typeMicrosPerKey(state, [0], 300, startOffset: 100);
    // ignore: avoid_print
    print('MODEL_SPEED 20k-char block: ${us.toStringAsFixed(0)} us/key');
    expect(us, lessThan(8000));
  });

  test('typing into a block with many formatted runs', () async {
    final delta = Delta();
    for (var i = 0; i < 400; i++) {
      delta.insert('run$i ', attributes: i.isEven ? {'bold': true} : null);
    }
    final state = EditorState(
      document: Document.blank()..insert([0], [paragraphNode(delta: delta)]),
    )..disableSealTimer = true;
    await _typeMicrosPerKey(state, [0], 50);
    final us = await _typeMicrosPerKey(state, [0], 300, startOffset: 20);
    // ignore: avoid_print
    print('MODEL_SPEED 400-run block: ${us.toStringAsFixed(0)} us/key');
    expect(us, lessThan(8000));
  });

  test('serializing a 2000-block note', () {
    final state = _note(2000);
    state.document.toJson(); // warm
    final sw = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      state.document.toJson();
    }
    sw.stop();
    final ms = sw.elapsedMicroseconds / 10 / 1000;
    // ignore: avoid_print
    print('MODEL_SPEED toJson 2000 blocks: ${ms.toStringAsFixed(1)} ms');
    expect(ms, lessThan(120));
  });

  test('pasting 500 blocks into a 2000-block note', () async {
    final state = _note(2000);
    final sw = Stopwatch()..start();
    await state.apply(state.transaction
      ..insertNodes([
        1000
      ], [
        for (var i = 0; i < 500; i++)
          paragraphNode(text: 'Pasted line $i here.'),
      ]));
    sw.stop();
    // ignore: avoid_print
    print('MODEL_SPEED paste 500 blocks: ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });
}
