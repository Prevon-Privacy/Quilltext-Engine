// Markdown out and back in must keep what the person wrote: block kinds, words, and bold / italic /
// strike / code / link spans, including text full of characters markdown treats as syntax.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

import '../support/random_docs.dart';

void main() {
  for (final tricky in [false, true]) {
    test('markdown round trip keeps blocks and spans (${tricky ? 'syntax-heavy' : 'plain'} words)', () {
      final bad = <String>[];
      for (var seed = 0; seed < 150; seed++) {
        final r = Random(seed);
        final nodes = randomBlocks(r, tricky: tricky);
        final doc = Document.blank()..insert([0], nodes);
        final md = documentToMarkdown(doc);
        final back = markdownToDocument(md);
        final a = [for (final n in doc.root.children) nodeSignature(n)];
        final b = [for (final n in back.root.children) nodeSignature(n)];
        if (a.join('\n') != b.join('\n')) {
          bad.add('seed $seed\n  md: ${md.replaceAll('\n', '⏎')}\n  in : ${a.join(' / ')}\n  out: ${b.join(' / ')}');
        }
      }
      // ignore: avoid_print
      if (bad.isNotEmpty) print('RT ${bad.take(14).join('\n').replaceAll('\n', '\nRT ')}');
      expect(bad, isEmpty, reason: '${bad.length} of 150 changed');
    });
  }
}
