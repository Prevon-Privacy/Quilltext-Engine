// Blind-round-2 probe B (editor fork): hostile clipboard HTML and markdown. Prints "PROBE ..." lines.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/src/plugins/html/html_document.dart';
import 'package:prevon_quilltext_engine/src/plugins/markdown/document_markdown.dart';

String rss() => '${(ProcessInfo.currentRss / (1024 * 1024)).round()}MB';

void run(String name, void Function() f) {
  final sw = Stopwatch()..start();
  var out = 'ok';
  try {
    f();
  } catch (e) {
    out = 'THREW ${e.runtimeType}';
  }
  print('PROBE $name ${sw.elapsedMilliseconds}ms $out rss=${rss()}');
}

void main() {
  final html = <String, String>{
    'div-nest-5k': '${'<div>' * 5000}x${'</div>' * 5000}',
    'div-nest-50k': '${'<div>' * 50000}x${'</div>' * 50000}',
    'ul-nest-2k': '${'<ul><li>' * 2000}x${'</li></ul>' * 2000}',
    'ul-nest-20k': '${'<ul><li>' * 20000}x${'</li></ul>' * 20000}',
    'span-nest-20k': '${'<span><b>' * 20000}x${'</b></span>' * 20000}',
    'blockquote-nest-5k': '${'<blockquote>' * 5000}x${'</blockquote>' * 5000}',
    'table-nest-1k': '${'<table><tr><td>' * 1000}x${'</td></tr></table>' * 1000}',
    'a-1M': '<a href="http://x">${'a' * 1000000}</a>',
    'a-flood-100k': '<a href="http://x">y</a>' * 100000,
    'li-flood-200k': '<ul>${'<li>x</li>' * 200000}</ul>',
    'img-flood-50k': '<img src="http://e.test/a.png">' * 50000,
    'table-wide-5k': '<table><tr>${'<td>x</td>' * 5000}</tr></table>',
    'table-5k-rows': '<table>${'<tr><td>x</td></tr>' * 5000}</table>',
    'unclosed-lt-1M': '<' * 1000000,
    'unclosed-b-300k': '<b>' * 300000,
    'attr-1M': '<a href="${'x' * 1000000}">y</a>',
    'entity-flood': '&amp;' * 500000,
  };
  for (final e in html.entries) {
    test('html ${e.key}', () => run('html ${e.key}', () => htmlToDocument(e.value)),
        timeout: const Timeout(Duration(minutes: 8)));
  }

  final md = <String, String>{
    'nested-list-indent-3k': List.generate(3000, (i) => '${'  ' * i}- x').join('\n'),
    'nested-list-flat-100k': List.generate(100000, (i) => '- x').join('\n'),
    'ordered-flat-100k': List.generate(100000, (i) => '${i + 1}. x').join('\n'),
    'quote-chain-lines': List.generate(20000, (i) => '> ' * 15 + 'x').join('\n'),
    'ref-defs-100k': List.generate(100000, (i) => '[r$i]: http://x/$i').join('\n'),
    'ref-uses-20k': List.generate(20000, (i) => '[r$i]').join(' '),
    'emph-alt-150k': '*a ' * 60000,
    'bracket-pairs-100k': '[a]' * 100000,
    'image-pairs-50k': '![a](b)' * 50000,
    'autolink-lt-100k': '<http://x>' * 50000,
    'html-inline-100k': '<span>' * 50000,
    'table-wide': '|${'a|' * 20000}\n|${'-|' * 20000}\n|${'b|' * 20000}',
    'table-rows-50k': '|a|b|\n|-|-|\n${'|x|y|\n' * 50000}',
    'fence-unclosed-1M': '```\n${'x\n' * 500000}',
    'many-blank-paras-300k': 'a\n\n' * 300000,
    'setext-flood': 'a\n---\n' * 100000,
    'heading-flood-200k': '# h\n' * 200000,
    'link-nest': '[${'[' * 500}x${']' * 500}](y)',
    'esc-flood': r'\*' * 500000,
    'codespan-pairs': '`a` ' * 100000,
    'list-lazy-cont-100k': '- a\n${'b\n' * 100000}',
    'hr-flood': '***\n' * 200000,
    'deep-quote-in-list': List.generate(200, (i) => '${'  ' * i}- ${'> ' * 10}x').join('\n'),
  };
  for (final e in md.entries) {
    test('md ${e.key}', () => run('md ${e.key} (${e.value.length} chars)', () => markdownToDocument(e.value)),
        timeout: const Timeout(Duration(minutes: 8)));
  }
}
