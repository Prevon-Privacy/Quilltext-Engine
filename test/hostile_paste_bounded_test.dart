// Regression tests for blind round 2 lane B (B-05, B-06): hostile markdown tables and pasted
// HTML, attacker inputs reproduced small. Bounds are generous (slow CI), the unfixed code needed
// 40-116 s and threw a StackOverflowError.
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/src/plugins/html/html_document.dart';
import 'package:prevon_quilltext_engine/src/plugins/html/html_input_guard.dart';
import 'package:prevon_quilltext_engine/src/plugins/markdown/document_markdown.dart';
import 'package:prevon_quilltext_engine/src/plugins/markdown/markdown_input_guard.dart';

const _maxTime = Duration(seconds: 5);

T _fast<T>(T Function() f) {
  final sw = Stopwatch()..start();
  final r = f();
  expect(sw.elapsed, lessThan(_maxTime));
  return r;
}

void main() {
  group('markdown tables (B-05)', () {
    test('20,000-column table is a literal paragraph, quickly', () {
      final md = '|${'a|' * 20000}\n|${'-|' * 20000}\n|${'b|' * 20000}';
      expect(scanMarkdownForHostileBlocks(md).any((s) => s.hostile), isTrue);
      final doc = _fast(() => markdownToDocument(md));
      expect(doc.root.children.length, greaterThan(0));
    });

    test('many rows of a wide table are hostile by the block cap', () {
      final row = '|${'x|' * 200}\n';
      final md = '$row|${'-|' * 200}\n${row * 80}';
      expect(scanMarkdownForHostileBlocks(md).any((s) => s.hostile), isTrue);
      _fast(() => markdownToDocument(md));
    });

    test('a normal 6-column table still parses as a table', () {
      const md = '| a | b | c | d | e | f |\n|---|---|---|---|---|---|\n'
          '| 1 | 2 | 3 | 4 | 5 | 6 |\n';
      expect(scanMarkdownForHostileBlocks(md), isEmpty);
    });
  });

  group('pasted HTML (B-06)', () {
    final shapes = <String, String>{
      'div x50k': '${'<div>' * 50000}x${'</div>' * 50000}',
      'ul/li x20k': '${'<ul><li>' * 20000}x${'</li></ul>' * 20000}',
      'span/b x20k': '${'<span><b>' * 20000}x${'</b></span>' * 20000}',
      'unclosed b x300k': '<b>' * 300000,
      'stray closers hide depth': '${'<div></span>' * 5000}x',
      'closers in script do not lower depth':
          '${'<div><script></div></script>' * 5000}x',
      'closers in comment do not lower depth': '${'<div><!--</div>-->' * 5000}x',
      'attribute with > and />': '${'<div x="/>">' * 5000}x',
    };
    for (final e in shapes.entries) {
      test('${e.key} is refused by the budget and decodes to an empty paste', () {
        expect(pasteHtmlWithinBudget(e.value), isFalse);
        final doc = _fast(() => htmlToDocument(e.value));
        expect(doc.root.children.where((n) => n.delta?.isNotEmpty ?? true),
            isEmpty);
      });
    }

    test('input over the size cap is refused', () {
      expect(pasteHtmlWithinBudget('x' * (kPasteHtmlMaxLength + 1)), isFalse);
    });

    test('flat and ordinary pages stay accepted and decode', () {
      expect(pasteHtmlWithinBudget('<ul>${'<li>x' * 5000}</ul>'), isTrue);
      expect(pasteHtmlWithinBudget('<ul>${'<li>x</li>' * 5000}</ul>'), isTrue);
      expect(
          pasteHtmlWithinBudget(
              '<div><p>a<br>b</p><table><tr><td><b>c</b></td></tr></table></div>'),
          isTrue);
      final doc = htmlToDocument('<h1>Title</h1><p>Hello <b>world</b></p>');
      expect(doc.root.children.length, greaterThanOrEqualTo(2));
    });
  });
}
