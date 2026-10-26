// Shared URL/phone regexes used by both the paste-time linkifier and the
// save-time linkifier. Lives next to paste_command.dart so the regexes and
// the matching logic stay co-located, but factored out so the two
// consumers (paste_command + scratchpad autosave) cannot drift.
//
// IMPORTANT: `kHrefRegex` is NOT anchored — it finds URL substrings
// inside any larger paragraph. `kPhoneRegex` IS anchored at both ends
// (^...$), so `hasMatch(paragraph)` only fires when the ENTIRE paragraph
// is a phone string. This is intentional: the paste path already gated
// linkification on those conditions (existing paste_command.dart
// behavior below), and the save-time path matches that scope by design
// — phone strings in the middle of prose are far more likely to be
// false positives than deliberate phone-link authoring.

// Shared URL/phone regexes used by both the paste-time linkifier and the
// save-time linkifier. Lives next to paste_command.dart so the regexes and
// the matching logic stay co-located, but factored out so the two
// consumers (paste_command + scratchpad autosave) cannot drift.
//
// IMPORTANT: `kHrefRegex` is NOT anchored — it finds URL substrings
// inside any larger paragraph. `kPhoneRegex` IS anchored at both ends
// (^...$), so `hasMatch(paragraph)` only fires when the ENTIRE paragraph
// is a phone string. This is intentional: the paste path already gated
// linkification on those conditions (existing paste_command.dart
// behavior below), and the save-time path matches that scope by design
// — phone strings in the middle of prose are far more likely to be
// false positives than deliberate phone-link authoring./// Matches http(s) URLs anywhere in a text run. Same shape as the old
/// paste_command `_hrefRegex` private const — kept identical so this is
/// a pure rename + extraction.
///
/// Final regex (verbatim, do NOT alter without auditing both
/// consumers — paste_command.dart's per-paragraph linkifier and the
/// new save-time linkifier in `linkify_plain_text.dart`):
///
///   `https?://(?:www\.)?[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:/[^\s]*)?`
final RegExp kHrefRegex = RegExp(
  r'https?://(?:www\.)?[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:/[^\s]*)?',
);

/// Matches a phone-number string (anchored start+end, so `hasMatch`
/// returns true only when the WHOLE input is a phone). Same as the old
/// paste_command `_phoneRegex` private const, kept identical — same two
/// consumers as `kHrefRegex`.
///
/// Final regex (verbatim):
///
///   `^\+?(?:[0-9][\s-.]?)+[0-9]$`
final RegExp kPhoneRegex = RegExp(r'^\+?(?:[0-9][\s-.]?)+[0-9]$');
