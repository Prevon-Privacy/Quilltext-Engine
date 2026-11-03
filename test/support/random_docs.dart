// Random documents for the round-trip tests: a few block kinds, each with plain or syntax-heavy words
// and bold / italic / strike / code spans.
import 'dart:math';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

const kPlainWords = ['alpha', 'beta gamma', 'x1', 'Hello World', 'naïve', '日本語', 'two words'];
const kTrickyWords = [
  '2*3*4', 'a_b_c', 'snake_case_name', '# not a heading', '1. not a list', '- not a bullet', '> not a quote',
  'a [b] c', 'a (b) c', '`tick`', 'back\\slash', 'a | b', '<tag>', 'a & b', '* star', '+ plus', '~tilde~',
  '[x] box', '![img]', '====', '---', '***', 'a `b` c', '``',
];

String nodeText(Node n) => n.delta?.toPlainText() ?? '';

/// type + text + which spans carry which attribute (as plain-text slices).
String nodeSignature(Node n) {
  final d = n.delta;
  final spans = <String>[];
  if (d != null) {
    for (final op in d) {
      if (op is TextInsert && op.attributes != null) {
        final a = op.attributes!;
        final keys = [
          for (final k in ['bold', 'italic', 'strikethrough', 'code', 'href'])
            if (a[k] != null && a[k] != false) k == 'href' ? 'href=${a[k]}' : k,
        ]..sort();
        if (keys.isNotEmpty && op.text.trim().isNotEmpty) spans.add('${op.text.trim()}{${keys.join(',')}}');
      }
    }
  }
  return '${n.type}|${nodeText(n)}|${spans.join(';')}';
}

Node randomTextNode(Random r, bool tricky, {String type = 'paragraph'}) {
  final pool = tricky ? kTrickyWords : kPlainWords;
  final d = Delta();
  final parts = 1 + r.nextInt(3);
  for (var i = 0; i < parts; i++) {
    final t = pool[r.nextInt(pool.length)];
    final fmt = r.nextInt(6);
    final attrs = switch (fmt) {
      1 => {'bold': true},
      2 => {'italic': true},
      3 => {'strikethrough': true},
      4 => {'code': true},
      _ => null,
    };
    d.insert(i == 0 ? t : ' $t', attributes: attrs);
  }
  return Node(type: type, attributes: {'delta': d.toJson()});
}


/// 1 to 4 random text-bearing top-level blocks.
List<Node> randomBlocks(Random r, {required bool tricky}) => [
      for (var i = 0; i < 1 + r.nextInt(4); i++)
        switch (r.nextInt(5)) {
          0 => randomTextNode(r, tricky, type: 'bulleted_list'),
          1 => randomTextNode(r, tricky, type: 'numbered_list'),
          2 => randomTextNode(r, tricky, type: 'quote'),
          _ => randomTextNode(r, tricky),
        },
    ];
