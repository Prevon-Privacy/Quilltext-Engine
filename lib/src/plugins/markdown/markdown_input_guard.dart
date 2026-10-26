/// Linear-time pre-pass for markdown import (see `markdownToDocument`).
///
/// package:markdown 7.3.1 is quadratic on hostile inputs (unclosed link
/// openers, delimiter storms, deeply nested quotes). This scan splits the
/// input into blocks (blank-line separated, fenced code kept whole and never
/// inspected) and flags the blocks that exceed the limits below. A flagged
/// block is emitted as a literal paragraph by the caller; everything else
/// goes through the normal parser untouched.
library;

/// More unclosed `](` link openers than this in one block is hostile.
/// An opener is "unclosed" when no `)` follows within [kGuardLinkCloseWindow].
const int kGuardMaxUnclosedLinkOpeners = 64;

/// How far ahead (chars) a `)` may be and still count as closing a link.
const int kGuardLinkCloseWindow = 2048;

/// A single run of `*`, `_`, `~` or `` ` `` longer than this is hostile.
const int kGuardMaxDelimiterRun = 256;

/// Total emphasis/code delimiter characters in one block above this is hostile.
const int kGuardMaxDelimitersPerBlock = 20000;

/// Leading `>` markers on one line above this is hostile.
const int kGuardMaxQuoteDepth = 20;

/// A block longer than this (chars) is hostile.
const int kGuardMaxBlockLength = 200000;

/// One contiguous slice of the input. [hostile] blocks must not be parsed.
class MarkdownGuardSegment {
  const MarkdownGuardSegment(this.start, this.end, {required this.hostile});

  /// Half-open range into the original string.
  final int start;
  final int end;
  final bool hostile;
}

/// Returns the segments of [input] in order, covering it without gaps, or an
/// empty list when no block is hostile (caller then parses [input] whole).
List<MarkdownGuardSegment> scanMarkdownForHostileBlocks(String input) {
  final n = input.length;
  final segments = <MarkdownGuardSegment>[];
  var anyHostile = false;

  var safeStart = 0; // start of the pending safe chunk
  var i = 0;

  // Fence state.
  int fenceChar = 0;
  var fenceLen = 0;

  // Current block (lines since last blank line outside a fence).
  var blockStart = -1;
  var blockEnd = -1;

  void closeBlock() {
    if (blockStart < 0) return;
    final hostile = _blockIsHostile(input, blockStart, blockEnd);
    if (hostile) {
      anyHostile = true;
      if (blockStart > safeStart) {
        segments.add(MarkdownGuardSegment(safeStart, blockStart, hostile: false));
      }
      segments.add(MarkdownGuardSegment(blockStart, blockEnd, hostile: true));
      safeStart = blockEnd;
    }
    blockStart = -1;
  }

  while (i < n) {
    var eol = input.indexOf('\n', i);
    if (eol < 0) eol = n;
    final lineEnd = eol; // exclusive, excludes '\n'

    if (fenceChar != 0) {
      // Inside a fence: inert. Check for closing fence.
      if (_fenceMarker(input, i, lineEnd, fenceChar, fenceLen, closing: true) >
          0) {
        fenceChar = 0;
      }
      blockEnd = lineEnd;
    } else if (_isBlank(input, i, lineEnd)) {
      closeBlock();
    } else {
      final open = _openingFence(input, i, lineEnd);
      if (open != null) {
        // A fence line starts/continues a block that is inert. Close any
        // pending paragraph block first only if it is hostile-checkable; we
        // keep it simple: the fence joins the current block, whose scan skips
        // fenced ranges.
        fenceChar = open.$1;
        fenceLen = open.$2;
      }
      if (blockStart < 0) blockStart = i;
      blockEnd = lineEnd;
    }
    i = eol + 1;
  }
  closeBlock();

  if (!anyHostile) return const [];
  if (safeStart < n) {
    segments.add(MarkdownGuardSegment(safeStart, n, hostile: false));
  }
  return segments;
}

bool _isBlank(String s, int start, int end) {
  for (var k = start; k < end; k++) {
    final c = s.codeUnitAt(k);
    if (c != 0x20 && c != 0x09 && c != 0x0D) return false;
  }
  return true;
}

/// If the line opens a fence (up to 3 spaces, then 3+ of ` or ~) returns
/// (char, length), else null.
(int, int)? _openingFence(String s, int start, int end) {
  var k = start;
  var spaces = 0;
  while (k < end && s.codeUnitAt(k) == 0x20 && spaces < 4) {
    k++;
    spaces++;
  }
  if (spaces > 3 || k >= end) return null;
  final c = s.codeUnitAt(k);
  if (c != 0x60 && c != 0x7E) return null;
  var run = 0;
  while (k < end && s.codeUnitAt(k) == c) {
    k++;
    run++;
  }
  if (run < 3) return null;
  if (c == 0x60) {
    // Backtick fence info string may not contain backticks.
    for (var j = k; j < end; j++) {
      if (s.codeUnitAt(j) == 0x60) return null;
    }
  }
  return (c, run);
}

/// Length of a closing fence marker on this line, or 0.
int _fenceMarker(String s, int start, int end, int char, int minLen,
    {required bool closing,}) {
  var k = start;
  var spaces = 0;
  while (k < end && s.codeUnitAt(k) == 0x20 && spaces < 4) {
    k++;
    spaces++;
  }
  if (spaces > 3) return 0;
  var run = 0;
  while (k < end && s.codeUnitAt(k) == char) {
    k++;
    run++;
  }
  if (run < minLen) return 0;
  while (k < end) {
    final c = s.codeUnitAt(k);
    if (c != 0x20 && c != 0x09 && c != 0x0D) return 0;
    k++;
  }
  return run;
}

bool _isDelim(int c) => c == 0x2A || c == 0x5F || c == 0x7E || c == 0x60;

/// Single linear pass over [start, end). Fenced ranges inside the block are
/// skipped (they are inert for the parser).
bool _blockIsHostile(String s, int start, int end) {
  if (end - start > kGuardMaxBlockLength) return true;

  // Pass 1 (forward): delimiter runs/total, quote depth, fence skipping, and
  // positions of ')' / '](' collected implicitly via a backward pass later.
  var delimTotal = 0;
  var fenceChar = 0;
  var fenceLen = 0;

  // Collect non-fenced line ranges for the backward pass.
  final ranges = <int>[]; // pairs start,end
  var i = start;
  while (i < end) {
    var eol = s.indexOf('\n', i);
    if (eol < 0 || eol > end) eol = end;
    if (fenceChar != 0) {
      if (_fenceMarker(s, i, eol, fenceChar, fenceLen, closing: true) > 0) {
        fenceChar = 0;
      }
    } else {
      final open = _openingFence(s, i, eol);
      if (open != null) {
        fenceChar = open.$1;
        fenceLen = open.$2;
      } else {
        ranges
          ..add(i)
          ..add(eol);

        // Quote depth: leading '>' markers separated by spaces/tabs.
        var depth = 0;
        var k = i;
        while (k < eol) {
          final c = s.codeUnitAt(k);
          if (c == 0x3E) {
            depth++;
            if (depth > kGuardMaxQuoteDepth) return true;
          } else if (c != 0x20 && c != 0x09) {
            break;
          }
          k++;
        }

        // Delimiter runs.
        var run = 0;
        for (var j = i; j < eol; j++) {
          if (_isDelim(s.codeUnitAt(j))) {
            run++;
            delimTotal++;
            if (run > kGuardMaxDelimiterRun) return true;
          } else {
            run = 0;
          }
        }
        if (delimTotal > kGuardMaxDelimitersPerBlock) return true;
      }
    }
    i = eol + 1;
  }

  // Pass 2 (backward): count '](' openers with no ')' within the window.
  // nextClose = index of nearest ')' at or after the scan position, across
  // the whole (non-fenced) block, found in one right-to-left sweep.
  var unclosed = 0;
  var nextClose = -1;
  for (var r = ranges.length - 2; r >= 0; r -= 2) {
    final rs = ranges[r];
    final re = ranges[r + 1];
    for (var j = re - 1; j >= rs; j--) {
      final c = s.codeUnitAt(j);
      if (c == 0x29) {
        nextClose = j;
      } else if (c == 0x28 && j > rs && s.codeUnitAt(j - 1) == 0x5D) {
        if (nextClose < 0 || nextClose - j > kGuardLinkCloseWindow) {
          unclosed++;
          if (unclosed > kGuardMaxUnclosedLinkOpeners) return true;
        }
      }
    }
  }
  return false;
}
