// Copy and paste inside the editor goes out as HTML and comes back in: blocks, words and spans must survive,
// including text full of characters HTML treats as syntax.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

import '../support/random_docs.dart';

void main() {
  for (final tricky in [false, true]) {
    test('html round trip keeps blocks and spans (${tricky ? 'syntax-heavy' : 'plain'} words)', () {
      final bad = <String>[];
      for (var seed = 0; seed < 150; seed++) {
        final r = Random(seed);
        final doc = Document.blank()..insert([0], randomBlocks(r, tricky: tricky));
        final html = documentToHTML(doc);
        final back = htmlToDocument(html);
        final a = [for (final n in doc.root.children) nodeSignature(n)];
        final b = [for (final n in back.root.children) nodeSignature(n)];
        if (a.join('\n') != b.join('\n')) {
          bad.add('seed $seed\n  html: ${html.replaceAll('\n', '⏎')}\n  in : ${a.join(' / ')}\n  out: ${b.join(' / ')}');
        }
      }
      // ignore: avoid_print
      if (bad.isNotEmpty) print('RT ${bad.take(10).join('\n').replaceAll('\n', '\nRT ')}');
      expect(bad, isEmpty, reason: '${bad.length} of 150 changed');
    });
  }
}
