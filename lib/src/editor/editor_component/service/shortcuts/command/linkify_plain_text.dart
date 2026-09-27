// Save-time URL/phone linkifier. Mirrors what paste_command.dart does on
// paste, but applied at the moment the autosave debouncer flushes —
// so a URL the user TYPES (not pastes) becomes a live link the next time
// the buffer is sealed to disk.
//
// Pairs with the shared regexes in `url_phone_regex.dart` (consumed by
// both this file and the paste handler). Keep the two regex definitions
// in ONE place; do not duplicate them here or in paste_command.dart.
//
// The same skip rules from `_pasteCommandHandler` apply as
// **inviolable pre-conditions** here:
//
//   1. Already linkified — don't double-attribute an existing href run.
//   2. Cursor lives INSIDE [matchStart, matchEnd) of the match — the user
//      is still composing that token, do NOT preempt them.
//   3. Terminator rule — a match is only "finitely finished" when the
//      character immediately AFTER it is whitespace, a newline, or
//      end-of-document — EXCEPT when end-of-document AND the cursor is
//      sitting at the match end (offset == matchEnd), skip too. This is
//      how an in-progress URL like "https://ex" mid-typing survives the
//      3-second autosave flush unharmed even when the document already
//      has no trailing whitespace/newline.

import 'package:flutter/foundation.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

import 'url_phone_regex.dart';

/// Walks [editorState]'s document, applies the URL/phone linkification
/// transaction to plain-text runs that pass every safety filter, and
/// commits the result through [EditorState.apply] in a single undo group.
///
/// Returns `true` iff any run was linkified — caller can use this as a
/// "did the linkifier change anything" signal for tests and for the
/// "only write scratchpadLastActivityAt if work happened" future hook.
///
/// The function deliberately runs as a single `editorState.transaction`
/// + one `apply(...)` call rather than one transaction per match — a
/// burst of N URLs in a buffer becomes one undo step + one rebuild,
/// not N.
///
/// All child nodes of container-style parents (callout, toggle, etc.)
/// are recursed the same way as the document root, so a URL inside a
/// nested child paragraph is linkified identically to one at the top
/// level. Container parents with their own non-text delta (e.g. image
/// nodes) are skipped — `node.delta` is null on those.
Future<bool> linkifyDocument(EditorState editorState) async {
  final doc = editorState.document;

  // Resolve the cursor's (path, offset-within-block) once for cheap
  // per-match skipping. If selection is null (no focus), nothing can be
  // "in progress" — every match is eligible excluding only the
  // already-linkified and terminator checks.
  final selection = editorState.selection;
  Node? cursorNode;
  int? cursorOffset;
  if (selection != null) {
    cursorNode = editorState.getNodeAtPath(selection.start.path);
    cursorOffset = selection.start.offset;
  }
  final bool hasCursor = cursorNode != null && cursorOffset != null;

  bool rangesAlreadyContainsHref(Delta delta, int start, int end) {
    // walk `[start, end)` in delta.ops, returning true if ANY op in
    // the range carries an href attribute (= already linkified).
    int deltaOffset = 0;
    for (final op in delta) {
      final opStart = deltaOffset;
      final opEnd = deltaOffset + op.length;
      deltaOffset = opEnd;
      if (opEnd <= start) continue;
      if (opStart >= end) break;
      final attrs = op.attributes;
      if (attrs != null && attrs.containsKey(AppFlowyRichTextKeys.href)) {
        return true;
      }
    }
    return false;
  }

  bool isWhitespaceLike(String c) =>
      c == ' ' || c == '\n' || c == '\r' || c == '\t';

  // Decision matrix for a single match (start, end, text):
  //
  //   Cursor in (start, end)?  → skip (in-progress).
  //   Already linked?          → skip (no-op).
  //   Terminator is EOD
  //     AND cursor at end?     → skip (mid-typing URL whose terminator
  //                                hasn't been typed yet).
  //   else                     → linkify.
  bool shouldLinkifyForMatch(Delta nodeDelta, Node node, int start, int end) {
    final cursorInThisNode = hasCursor && identical(node, cursorNode);
    if (cursorInThisNode) {
      // `cursorOffset` is provably non-null here because `hasCursor`
      // gates on `cursorOffset != null`. The Dart static analyzer
      // doesn't carry the implication through `&&`, so the explicit
      // `!` is needed; the surrounding ignore directive keeps the
      // `unnecessary_non_null_assertion` lint gated to this line.
      // ignore: unnecessary_non_null_assertion
      final cursorOffsetHere = cursorOffset!;
      if (cursorOffsetHere > start && cursorOffsetHere < end) {
        return false;
      }
    }
    if (rangesAlreadyContainsHref(nodeDelta, start, end)) return false;
    if (end == nodeDelta.toPlainText().length) {
      // End-of-block terminator. Only eligible if the cursor is
      // strictly past the match end — otherwise it's an in-progress
      // URL whose terminator hasn't been typed yet (test fixture
      // expectation: "https://ex" at EOD with cursor at 11 must NOT
      // linkify).
      if (cursorInThisNode &&
          // ignore: unnecessary_non_null_assertion
          cursorOffset == end) {
        return false;
      }
      return true;
    }
    // Non-EOD terminator: must be whitespace / newline.
    return isWhitespaceLike(nodeDelta.toPlainText()[end]);
  }

  final transaction = editorState.transaction;
  bool any = false;

  void visit(Node node) {
    final delta = node.delta;
    if (delta == null) {
      // Skip this node's content; recurse into children anyway.
      for (final child in node.children) {
        visit(child);
      }
      return;
    }

    final plain = delta.toPlainText();
    if (plain.isEmpty) {
      for (final child in node.children) {
        visit(child);
      }
      return;
    }

    // ─── Phone branch ──────────────────────────────────────────────
    // Pasted-phone parity: only fire when the WHOLE plain text matches
    // the anchored kPhoneRegex. Substring phone detection is too
    // ambiguous for "in-progress tokens like '1234'" (would catch any
    // 4+ digit run — false positives everywhere).
    {
      final wholeMatch = kPhoneRegex.firstMatch(plain);
      // kPhoneRegex has ^...$, so firstMatch == hasMatch: only when
      // the entire plain text IS a phone. Reuse shouldLinkifyForMatch
      // for the safety filters.
      if (wholeMatch != null &&
          wholeMatch.start == 0 &&
          wholeMatch.end == plain.length &&
          shouldLinkifyForMatch(delta, node, 0, plain.length)) {
        transaction.formatText(node, 0, plain.length, {
          AppFlowyRichTextKeys.href: 'tel:$plain',
        });
        any = true;
      }
    }

    // ─── URL branch ────────────────────────────────────────────────
    // kHrefRegex is NOT anchored — finds URL substrings inside any
    // larger paragraph. Note: `RegExp.firstMatch` only accepts one
    // positional arg (the string) in modern Dart, so we collect
    // `allMatches` once per node and walk the matches in order.
    final urlMatches = kHrefRegex.allMatches(plain).toList();
    int searchFrom = 0;
    for (final m in urlMatches) {
      final start = m.start;
      final end = m.end;
      if (start < searchFrom) continue;
      if (shouldLinkifyForMatch(delta, node, start, end)) {
        transaction.formatText(
          node,
          start,
          end - start,
          {AppFlowyRichTextKeys.href: m.group(0)},
        );
        any = true;
        // Past the linkified run; do not re-scan inside it (matches
        // rarely overlap a clean URL exactly, but defensively guard
        // against re-matching inside an already-styled range).
        searchFrom = end;
      } else {
        // Skipped (cursor inside / already linked / in-progress at
        // EOD). Advance by one so a future match whose start is
        // strictly past this one's start+1 can still be considered.
        searchFrom = start + 1;
      }
    }

    for (final child in node.children) {
      visit(child);
    }
  }

  for (final node in doc.root.children) {
    visit(node);
  }

  if (any) {
    await editorState.apply(transaction);
  }
  return any;
}
