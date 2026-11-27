import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/ime/delta_input_service.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/ime/non_delta_input_service.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/ime/text_diff.dart';

bool _wellFormed(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 >= s.length) return false;
      final n = s.codeUnitAt(i + 1);
      if (n < 0xDC00 || n > 0xDFFF) return false;
      i++;
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      return false;
    }
  }
  return true;
}

/// Applies the single delta the diff produced and returns the new text.
String _apply(String oldText, String newText, {int? cursor}) {
  final deltas = getTextEditingDeltas(
    TextEditingValue(text: oldText),
    TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor ?? newText.length),
    ),
  );
  expect(deltas, hasLength(1));
  final d = deltas.single;
  if (d is TextEditingDeltaInsertion) {
    expect(_wellFormed(d.textInserted), isTrue, reason: 'inserted $d');
    return oldText.replaceRange(
        d.insertionOffset, d.insertionOffset, d.textInserted);
  }
  if (d is TextEditingDeltaDeletion) {
    final removed = oldText.substring(d.deletedRange.start, d.deletedRange.end);
    expect(_wellFormed(removed), isTrue, reason: 'deleted half pair: $d');
    return oldText.replaceRange(d.deletedRange.start, d.deletedRange.end, '');
  }
  if (d is TextEditingDeltaReplacement) {
    final removed =
        oldText.substring(d.replacedRange.start, d.replacedRange.end);
    expect(_wellFormed(removed), isTrue, reason: 'replaced half pair: $d');
    expect(_wellFormed(d.replacementText), isTrue, reason: 'replacement: $d');
    return oldText.replaceRange(
        d.replacedRange.start, d.replacedRange.end, d.replacementText);
  }
  return oldText;
}

void _roundTrip(String a, String b, {int? cursor}) {
  final out = _apply(a, b, cursor: cursor);
  expect(out, b);
  expect(_wellFormed(out), isTrue);
}

void main() {
  test('insert an emoji', () => _roundTrip('ab', 'a\u{1F600}b', cursor: 3));
  test('insert a ZWJ family sequence',
      () => _roundTrip('x', 'x\u{1F468}‍\u{1F469}‍\u{1F467}'));
  test('insert a combining accent after a letter', () => _roundTrip('e', 'é'));
  test('dead key replaces the base letter with a precomposed one',
      () => _roundTrip('e', 'é', cursor: 1));
  test('Korean composition grows jamo into a syllable',
      () => _roundTrip('ᄒ', '하'));
  test('Korean composing syllable is replaced by the next',
      () => _roundTrip('한', '한글'));
  test('Japanese composing kana replaced by kanji',
      () => _roundTrip('あい', '愛', cursor: 1));
  test(
      'delete a whole emoji', () => _roundTrip('a\u{1F600}b', 'ab', cursor: 1));

  test('emoji replaced by a sibling emoji (shared high surrogate)', () {
    // U+1F600 = D83D DE00, U+1F601 = D83D DE01
    _roundTrip('\u{1F600}', '\u{1F601}');
    _roundTrip('a\u{1F600}b', 'a\u{1F601}b', cursor: 3);
  });

  test('emoji replaced by one with the same low surrogate', () {
    // U+1F600 = D83D DE00, U+1F200 = D83C DE00
    _roundTrip('\u{1F600}', '\u{1F200}');
    _roundTrip('a\u{1F600}b', 'a\u{1F200}b', cursor: 3);
  });

  test('same low surrogate with the caret reported inside the pair', () {
    // The caret sits between the two halves: the diff must still widen the
    // end past the shared low surrogate (end++).
    _roundTrip('a\u{1F600}b', 'a\u{1F200}b', cursor: 2);
  });

  test('same high surrogate with the caret reported inside the pair', () {
    // Kills the start-- widening: shared high surrogate, caret mid-pair.
    _roundTrip('a\u{1F600}b', 'a\u{1F601}b', cursor: 2);
  });

  test('skin tone swap keeps pairs whole', () {
    _roundTrip('\u{1F44D}\u{1F3FB}', '\u{1F44D}\u{1F3FD}');
  });

  test('ZWJ sequence member swapped', () {
    _roundTrip('\u{1F468}‍\u{1F469}', '\u{1F468}‍\u{1F466}');
  });

  test('deleteBackward: on an emoji removes the whole pair', () {
    TextEditingDeltaDeletion? got;
    final service = DeltaTextInputService(
      onInsert: (_) async => true,
      onDelete: (d) async {
        got = d;
        return true;
      },
      onReplace: (_) async => true,
      onNonTextUpdate: (_) async => true,
      onPerformAction: (_) async {},
    );
    // the service keeps a leading space in its editing value
    service.currentTextEditingValue = const TextEditingValue(
      text: ' a\u{1F600}',
      selection: TextSelection.collapsed(offset: 4),
    );
    service.performSelector('deleteBackward:');
    final r = got!.deletedRange;
    expect(r.start, 2);
    expect(r.end, 4);
  });

  group('backspace removes', () {
    final cases = <String, String>{
      'emoji pair': 'a\u{1F600}',
      'ZWJ family (whole cluster)': 'a\u{1F468}\u200D\u{1F469}\u200D\u{1F467}',
      'flag (two regional indicators)': 'a\u{1F1FA}\u{1F1F8}',
      'skin tone emoji': 'a\u{1F44D}\u{1F3FD}',
      'emoji + variation selector': 'a\u2764\uFE0F',
    };
    cases.forEach((name, text) {
      test(name, () {
        expect(backspaceLength(text, text.length), text.length - 1);
      });
    });
    test('only the combining mark, not the letter', () {
      expect(backspaceLength('ae\u0301', 3), 1);
    });
    test('one flag of two', () {
      const t = '\u{1F1FA}\u{1F1F8}\u{1F1E9}\u{1F1EA}';
      expect(backspaceLength(t, t.length), 4);
      expect(backspaceLength(t, 4), 4);
    });
    test('plain letter and start of text', () {
      expect(backspaceLength('ab', 2), 1);
      expect(backspaceLength('ab', 0), 1);
    });
  });

  test('non-delta deleteBackward: on a ZWJ family removes the cluster', () {
    TextEditingDeltaDeletion? got;
    final service = NonDeltaTextInputService(
      onInsert: (_) async => true,
      onDelete: (d) async {
        got = d;
        return true;
      },
      onReplace: (_) async => true,
      onNonTextUpdate: (_) async => true,
      onPerformAction: (_) async {},
    );
    const fam = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
    service.currentTextEditingValue = TextEditingValue(
      text: ' a$fam',
      selection:
          TextSelection.collapsed(offset: 2 + fam.length - 1 + 1 - 1 + 1),
    );
    service.performSelector('deleteBackward:');
    expect(got!.deletedRange, TextRange(start: 1, end: 1 + fam.length));
    expect(got!.selection.extentOffset, 1);
  });

  test('caret after a diff-based emoji insert is on a pair boundary', () {
    final d = getTextEditingDeltas(
      const TextEditingValue(text: 'ab'),
      const TextEditingValue(
        text: 'a\u{1F600}b',
        selection: TextSelection.collapsed(offset: 3),
      ),
    ).single as TextEditingDeltaInsertion;
    expect(d.insertionOffset, 1);
    expect(d.textInserted, '\u{1F600}');
    expect(d.selection.extentOffset, d.insertionOffset + d.textInserted.length);
  });
}
