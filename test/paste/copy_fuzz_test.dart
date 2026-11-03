// Copy a random range: the copied blocks hold exactly the selected words, copying never touches the page,
// and the HTML that goes on the clipboard reads back as the same blocks (types, words, bold / italic /
// strike / code / links).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

import '../support/random_docs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final tricky in [false, true]) {
    test(
        'copy of a random range is faithful (${tricky ? 'syntax-heavy' : 'plain'} words)',
        () {
      final bad = <String>[];
      for (var seed = 0; seed < 150; seed++) {
        final r = Random(seed);
        final nodes = [
          for (var i = 0; i < 2 + r.nextInt(4); i++)
            randomTextNode(r, tricky,
                type: ['paragraph', 'bulleted_list', 'quote'][r.nextInt(3)])
        ];
        final s = EditorState(document: Document.blank()..insert([0], nodes));
        final before = s.document.toJson().toString();
        final a = r.nextInt(nodes.length);
        final b = a + r.nextInt(nodes.length - a);
        final sel = Selection(
          start: Position(
              path: [a], offset: r.nextInt(nodeText(nodes[a]).length + 1)),
          end: Position(
              path: [b], offset: r.nextInt(nodeText(nodes[b]).length + 1)),
        ).normalized;
        if (sel.isCollapsed) continue;
        final copied = s.getSelectedNodes(selection: sel);
        final wanted = s.getTextInSelection(sel);
        final got = [for (final n in copied) nodeText(n)];
        if (got.join('\n') != wanted.join('\n')) {
          bad.add(
              'seed $seed text: copied ${got.join('⏎')} wanted ${wanted.join('⏎')}');
          continue;
        }
        if (s.document.toJson().toString() != before) {
          bad.add('seed $seed copy changed the page');
          continue;
        }
        final html = documentToHTML(Document.blank()..insert([0], copied));
        final back = htmlToDocument(html).root.children;
        final x = [for (final n in copied) nodeSignature(n)].join('\n');
        final y = [for (final n in back) nodeSignature(n)].join('\n');
        if (x != y)
          bad.add(
              'seed $seed html\n  in : ${x.replaceAll('\n', ' / ')}\n  out: ${y.replaceAll('\n', ' / ')}\n  html: $html');
      }
      // ignore: avoid_print
      if (bad.isNotEmpty)
        print('CP ${bad.take(10).join('\n').replaceAll('\n', '\nCP ')}');
      expect(bad, isEmpty, reason: '${bad.length} of 150 changed');
    });
  }
}
