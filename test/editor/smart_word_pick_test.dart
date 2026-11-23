import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/src/editor/util/smart_word_pick.dart';
import 'package:prevon_quilltext_engine/src/service/selection/mobile_selection_gesture.dart';

String _pick(String text, int offset, TextRange raw) {
  final r = smartWordRange(text, offset, raw);
  return text.substring(r.start, r.end);
}

void main() {
  group('smartWordRange', () {
    const t = 'hello   world, again';
    test('a real word stays as the engine gave it', () {
      expect(_pick(t, 2, const TextRange(start: 0, end: 5)), 'hello');
    });
    test('a tap in a run of spaces takes the nearer word', () {
      // engine returns the blank run 5..8
      expect(_pick(t, 6, const TextRange(start: 5, end: 8)), 'hello');
      expect(_pick(t, 7, const TextRange(start: 5, end: 8)), 'world');
    });
    test('a tap on punctuation takes the word before it on a tie', () {
      expect(_pick(t, 13, const TextRange(start: 13, end: 14)), 'world');
    });
    test('blank at the very start or end still finds the only word', () {
      expect(_pick('  hi', 0, const TextRange(start: 0, end: 2)), 'hi');
      expect(_pick('hi  ', 4, const TextRange(start: 2, end: 4)), 'hi');
    });
    test('nothing selectable stays as the engine gave it', () {
      const raw = TextRange(start: 1, end: 1);
      expect(smartWordRange('   ', 1, raw), raw);
      expect(smartWordRange('', 0, TextRange.empty), TextRange.empty);
    });
    test('other scripts and inline objects count as words', () {
      expect(
          _pick('привет  мир', 7, const TextRange(start: 6, end: 8)), 'привет',);
      expect(_pick('a ￼', 2, const TextRange(start: 2, end: 3)), '￼');
    });
  });

  group('MobileSelectionGestureDetector', () {
    testWidgets('two quick taps far apart are not a double tap',
        (tester) async {
      var singles = 0, doubles = 0;
      await tester.pumpWidget(MaterialApp(
        home: MobileSelectionGestureDetector(
          onTapUp: (_) => singles++,
          onDoubleTapUp: (_) => doubles++,
          child: const SizedBox.expand(),
        ),
      ),);
      await tester.tapAt(const Offset(40, 100));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(300, 400));
      await tester.pump(const Duration(milliseconds: 600));
      expect(singles, 2);
      expect(doubles, 0);
    });

    testWidgets('two quick taps on the same spot are a double tap',
        (tester) async {
      var singles = 0, doubles = 0;
      await tester.pumpWidget(MaterialApp(
        home: MobileSelectionGestureDetector(
          onTapUp: (_) => singles++,
          onDoubleTapUp: (_) => doubles++,
          child: const SizedBox.expand(),
        ),
      ),);
      await tester.tapAt(const Offset(40, 100));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(46, 104));
      await tester.pump(const Duration(milliseconds: 600));
      expect(singles, 1);
      expect(doubles, 1);
    });
  });
}
