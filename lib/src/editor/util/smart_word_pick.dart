import 'dart:ui' show TextRange;

/// PREVON PATCH 25: which word a double tap / hold means.
///
/// The text engine's word boundary answers "the run of characters around this
/// spot", which is a poor answer for a finger: a tap that lands in a gap
/// between two words (or on a comma, or a long run of spaces) selected just the
/// blank, so the person saw a sliver of highlight and had to try again. A
/// finger is wide: the blank next to a word means that word.
///
/// [raw] is the engine's boundary for the tapped spot; the result is the word
/// the person meant, or [raw] when it already is one.
TextRange smartWordRange(String text, int offset, TextRange raw) {
  if (text.isEmpty) return raw;
  final at = offset.clamp(0, text.length);
  final range = raw.isValid && !raw.isCollapsed ? raw : null;
  if (range != null && _holdsWordChar(text, range)) return range;

  // The tap fell on a blank or on punctuation: take the nearest word.
  final left = _wordEndingBefore(text, at);
  final right = _wordStartingAfter(text, at);
  if (left == null && right == null) return raw;
  if (left == null) return right!;
  if (right == null) return left;
  // Nearer wins; a tie goes to the word before (what you just typed or read).
  final toLeft = at - left.end;
  final toRight = right.start - at;
  return toRight < toLeft ? right : left;
}

bool _isWordChar(int unit) {
  // Letters, digits, underscore, and anything outside ASCII that is not
  // space or punctuation (covers every other script and the object
  // placeholder of an inline picture or mention).
  if (unit >= 0x30 && unit <= 0x39) return true; // 0-9
  if (unit >= 0x41 && unit <= 0x5A) return true; // A-Z
  if (unit >= 0x61 && unit <= 0x7A) return true; // a-z
  if (unit == 0x5F) return true; // _
  if (unit < 0x80) return false;
  // Non-ASCII spaces and common typographic punctuation are not word chars.
  if (unit == 0xA0 || unit == 0x2007 || unit == 0x202F || unit == 0x3000) {
    return false;
  }
  if (unit >= 0x2000 && unit <= 0x206F) return unit == 0x2060;
  if (unit >= 0x3001 && unit <= 0x303F) return false; // CJK punctuation
  return true;
}

bool _holdsWordChar(String text, TextRange r) {
  for (var i = r.start; i < r.end && i < text.length; i++) {
    if (_isWordChar(text.codeUnitAt(i))) return true;
  }
  return false;
}

/// The word that ends at or before [at] (skipping blanks and punctuation).
TextRange? _wordEndingBefore(String text, int at) {
  var end = at;
  while (end > 0 && !_isWordChar(text.codeUnitAt(end - 1))) {
    end--;
  }
  if (end == 0) return null;
  var start = end;
  while (start > 0 && _isWordChar(text.codeUnitAt(start - 1))) {
    start--;
  }
  return TextRange(start: start, end: end);
}

/// The word that starts at or after [at] (skipping blanks and punctuation).
TextRange? _wordStartingAfter(String text, int at) {
  var start = at;
  while (start < text.length && !_isWordChar(text.codeUnitAt(start))) {
    start++;
  }
  if (start >= text.length) return null;
  var end = start;
  while (end < text.length && _isWordChar(text.codeUnitAt(end))) {
    end++;
  }
  return TextRange(start: start, end: end);
}
