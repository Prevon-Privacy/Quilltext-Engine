/// Linear pre-pass for pasted HTML (see `DocumentHTMLDecoder.convert`).
///
/// The decoder and the `html` parser are recursive: a clipboard of 50,000 nested `<div>` took
/// 44 s and then threw an uncaught `StackOverflowError`. This scan rejects input that is too
/// big or nests too deep BEFORE anything is parsed; the caller then treats the paste as having
/// no HTML, so the plain-text fallback runs.
library;

/// Longest clipboard HTML (chars) that is parsed. Flat pages of this size parse in about 2 s;
/// a real copied selection (even a whole article) is far smaller. Larger input pastes as text.
const int kPasteHtmlMaxLength = 2000000;

/// Deepest element nesting that is parsed. Real pages (Google Docs, Word, web articles) stay
/// under about 40 open elements, so 256 leaves a wide margin while keeping recursion shallow.
const int kPasteHtmlMaxDepth = 256;

// Elements whose end tag is optional: `<li>a<li>b` is flat in the parser, so they do not add depth.
const Set<String> _optionalEnd = {
  'p', 'li', 'dt', 'dd', 'tr', 'td', 'th', 'tbody', 'thead', 'tfoot', //
  'option', 'optgroup', 'colgroup', 'caption',
};

const Set<String> _voidTags = {
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', //
  'param', 'source', 'track', 'wbr', 'basefont', 'bgsound', 'frame', 'keygen',
};

const Set<String> _rawText = {
  'script', 'style', 'textarea', 'title', 'xmp', 'iframe', 'noembed', //
  'noframes', 'plaintext',
};

bool _isNameChar(int c) =>
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x2D ||
    c == 0x3A ||
    c == 0x5F;

/// True when [html] is small enough and shallow enough to parse. Keeps a stack of open element
/// names so a stray end tag that matches nothing cannot lower the depth (the parser ignores it
/// too), and skips comments, quoted attribute values and raw-text elements (`<script>`).
bool pasteHtmlWithinBudget(String html) {
  final n = html.length;
  if (n > kPasteHtmlMaxLength) return false;
  final open = <String>[];
  String? lower; // lower-cased copy, made once and only if a raw-text element appears
  var i = html.indexOf('<');
  while (i >= 0 && i + 1 < n) {
    final c = html.codeUnitAt(i + 1);
    var next = i + 1;
    if (c == 0x21 || c == 0x3F) {
      // <!-- comment -->, <!doctype>, <![CDATA[ bogus comment, <?pi>
      if (html.startsWith('<!--', i)) {
        final e = html.indexOf('-->', i + 4);
        next = e < 0 ? n : e + 3;
      } else {
        final e = html.indexOf('>', i + 2);
        next = e < 0 ? n : e + 1;
      }
    } else if (c == 0x2F) {
      var j = i + 2;
      while (j < n && _isNameChar(html.codeUnitAt(j))) {
        j++;
      }
      final name = html.substring(i + 2, j).toLowerCase();
      final e = html.indexOf('>', j);
      next = e < 0 ? n : e + 1;
      // Pop down to the nearest matching open element (the parser does the same), within the window.
      final lowest = open.length > kPasteHtmlMaxDepth + 8
          ? open.length - kPasteHtmlMaxDepth - 8
          : 0;
      for (var k = open.length - 1; k >= lowest; k--) {
        if (open[k] == name) {
          open.length = k;
          break;
        }
      }
    } else if (_isNameChar(c)) {
      var j = i + 1;
      while (j < n && _isNameChar(html.codeUnitAt(j))) {
        j++;
      }
      final name = html.substring(i + 1, j).toLowerCase();
      // Closing '>' outside quoted attribute values.
      var close = -1;
      while (j < n) {
        final d = html.codeUnitAt(j);
        if (d == 0x3E) {
          close = j;
          break;
        }
        if (d == 0x22 || d == 0x27) {
          final q = html.indexOf(String.fromCharCode(d), j + 1);
          if (q < 0) {
            j = n;
            break;
          }
          j = q;
        }
        j++;
      }
      next = close < 0 ? n : close + 1;
      final selfClosed = close > 0 && html.codeUnitAt(close - 1) == 0x2F;
      if (close >= 0 && _rawText.contains(name) && !selfClosed) {
        final e = (lower ??= html.toLowerCase()).indexOf('</$name', next);
        next = e < 0 ? n : e;
      } else if (!_voidTags.contains(name) &&
          !_optionalEnd.contains(name) &&
          !selfClosed) {
        open.add(name);
        if (open.length > kPasteHtmlMaxDepth) return false;
      }
    }
    i = html.indexOf('<', next);
  }
  return true;
}
