// https://github.com/singerdmx/flutter-quill/blob/master/lib/src/utils/delta.dart

import 'dart:math' as math;

import 'package:flutter/services.dart';

// Diff between two texts - old text and new text
class Diff {
  Diff(this.start, this.deleted, this.inserted);

  // Start index in old text at which changes begin.
  final int start;

  /// The deleted text
  final String deleted;

  // The inserted text
  final String inserted;

  @override
  String toString() {
    return 'Diff[$start, "$deleted", "$inserted"]';
  }
}

bool _isHigh(int c) => c >= 0xD800 && c <= 0xDBFF;
bool _isLow(int c) => c >= 0xDC00 && c <= 0xDFFF;

/* Get diff operation between old text and new text */
Diff getDiff(String oldText, String newText, int cursorPosition) {
  var end = oldText.length;
  final delta = newText.length - end;
  final limit = math.max(0, cursorPosition - delta);

  while (end > limit &&
      oldText[end - 1] == newText[end + delta - 1] &&
      !newText.startsWith(oldText)) {
    end--;
  }

  var start = 0;
  final startLimit = cursorPosition - math.max(0, delta);

  while (start < startLimit && oldText[start] == newText[start]) {
    start++;
  }

  // Never cut a surrogate pair (emoji) in half: a shared high or low
  // surrogate between two different emoji must widen the changed range.
  if (start > 0 &&
      start < oldText.length &&
      start < newText.length &&
      _isHigh(oldText.codeUnitAt(start - 1))) {
    start--;
  }
  if (end < oldText.length &&
      end + delta < newText.length &&
      end + delta >= 0 &&
      end > 0 &&
      _isLow(oldText.codeUnitAt(end))) {
    end++;
  }

  final deleted = (start >= end) ? '' : oldText.substring(start, end);
  final inserted = newText.substring(start, end + delta);

  var i = 0;
  while (
      i < deleted.length && i < inserted.length && deleted[i] == inserted[i]) {
    i++;
  }
  if (i > 0 && _isHigh(deleted.codeUnitAt(i - 1))) {
    i--;
  }

  return i != 0
      ? Diff(start + i, deleted.substring(i), inserted.substring(i))
      : Diff(start, deleted, inserted);
}

List<TextEditingDelta> getTextEditingDeltas(
  TextEditingValue? oldValue,
  TextEditingValue newValue,
) {
  if (oldValue == null) {
    return [
      TextEditingDeltaNonTextUpdate(
        oldText: newValue.text,
        selection: newValue.selection,
        composing: newValue.composing,
      ),
    ];
  }
  final currentText = oldValue.text;
  final diff = getDiff(
    currentText,
    newValue.text,
    newValue.selection.extentOffset,
  );
  if (diff.inserted.isNotEmpty && diff.deleted.isEmpty) {
    return [
      TextEditingDeltaInsertion(
        oldText: currentText,
        textInserted: diff.inserted,
        insertionOffset: diff.start,
        selection: newValue.selection,
        composing: newValue.composing,
      ),
    ];
  } else if (diff.inserted.isEmpty && diff.deleted.isNotEmpty) {
    return [
      TextEditingDeltaDeletion(
        oldText: currentText,
        selection: newValue.selection,
        composing: newValue.composing,
        deletedRange: TextRange(
          start: diff.start,
          end: diff.start + diff.deleted.length,
        ),
      ),
    ];
  } else if (diff.inserted.isNotEmpty && diff.deleted.isNotEmpty) {
    return [
      TextEditingDeltaReplacement(
        oldText: currentText,
        selection: newValue.selection,
        composing: newValue.composing,
        replacementText: diff.inserted,
        replacedRange: TextRange(
          start: diff.start,
          end: diff.start + diff.deleted.length,
        ),
      ),
    ];
  } else if (diff.inserted.isEmpty && diff.deleted.isEmpty) {
    return [
      TextEditingDeltaNonTextUpdate(
        oldText: newValue.text,
        selection: newValue.selection,
        composing: newValue.composing,
      ),
    ];
  }
  throw UnsupportedError('Unknown diff: $diff');
}

/// How many UTF-16 units one backspace removes before [offset].
///
/// A whole emoji cluster goes at once (surrogate pair, skin tone, variation
/// selector, ZWJ sequence, flag), like platform text fields do. A combining
/// accent removes the mark only.
int backspaceLength(String text, int offset) {
  if (offset <= 0 || offset > text.length) return 1;
  int cpBefore(int pos) {
    if (pos >= 2 &&
        _isLow(text.codeUnitAt(pos - 1)) &&
        _isHigh(text.codeUnitAt(pos - 2))) {
      return 2;
    }
    return pos >= 1 ? 1 : 0;
  }

  int cpAt(int pos, int len) => len == 2
      ? 0x10000 +
          ((text.codeUnitAt(pos - 2) - 0xD800) << 10) +
          (text.codeUnitAt(pos - 1) - 0xDC00)
      : text.codeUnitAt(pos - 1);
  bool isRi(int c) => c >= 0x1F1E6 && c <= 0x1F1FF;
  bool isGlue(int c) =>
      (c >= 0x1F3FB && c <= 0x1F3FF) ||
      c == 0xFE0F ||
      c == 0x20E3 ||
      (c >= 0xE0020 && c <= 0xE007F);

  var pos = offset;
  var len = cpBefore(pos);
  var cp = cpAt(pos, len);
  pos -= len;
  if (isRi(cp)) {
    var run = 1;
    var p = pos;
    while (true) {
      final l = cpBefore(p);
      if (l == 0 || !isRi(cpAt(p, l))) break;
      run++;
      p -= l;
    }
    return run.isEven ? offset - pos + cpBefore(pos) : offset - pos;
  }
  while (pos > 0) {
    if (isGlue(cp)) {
      len = cpBefore(pos);
      cp = cpAt(pos, len);
      pos -= len;
      continue;
    }
    // [..., X, ZWJ, cp]: pull in the joiner and what it joins.
    if (text.codeUnitAt(pos - 1) == 0x200D && pos >= 2) {
      pos -= 1;
      len = cpBefore(pos);
      cp = cpAt(pos, len);
      pos -= len;
      continue;
    }
    break;
  }
  return offset - pos;
}
