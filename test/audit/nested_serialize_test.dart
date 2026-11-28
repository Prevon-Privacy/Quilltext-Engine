// Nested blocks through HTML, Node construction and the Quill delta encoder (wave 2, nested serialization).
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// "type:text[:checked]" per block, indented by depth, in reading order.
List<String> shape(Iterable<Node> nodes, [int depth = 0]) {
  final out = <String>[];
  for (final n in nodes) {
    final text = n.delta?.toPlainText() ?? '';
    final checked = n.type == TodoListBlockKeys.type &&
        (n.attributes[TodoListBlockKeys.checked] == true);
    out.add('${'  ' * depth}${n.type}:$text${checked ? ':checked' : ''}');
    out.addAll(shape(n.children, depth + 1));
  }
  return out;
}

Node numNode({required String text, List<Node> children = const []}) =>
    numberedListNode(delta: Delta()..insert(text), children: children);

Document roundTrip(List<Node> nodes) {
  final doc = Document.blank(withInitialText: false)..insert([0], nodes);
  return htmlToDocument(documentToHTML(doc));
}

void main() {
  group('html nested export', () {
    test('bulleted > bulleted keeps depth', () {
      final nodes = <Node>[
        bulletedListNode(
          text: 'a',
          children: <Node>[
            bulletedListNode(
                text: 'b', children: <Node>[bulletedListNode(text: 'c')]),
          ],
        ),
        bulletedListNode(text: 'd'),
      ];
      expect(shape(roundTrip(nodes).root.children), shape(nodes));
    });

    test('numbered > numbered keeps depth', () {
      final nodes = <Node>[
        numNode(text: 'a', children: <Node>[numNode(text: 'b')]),
        numNode(text: 'c'),
      ];
      expect(shape(roundTrip(nodes).root.children), shape(nodes));
    });

    test('bullet > numbered > todo keeps depth and checked', () {
      final nodes = <Node>[
        bulletedListNode(
          text: 'a',
          children: <Node>[
            numNode(
              text: 'b',
              children: <Node>[todoListNode(checked: true, text: 'c')],
            ),
          ],
        ),
      ];
      expect(shape(roundTrip(nodes).root.children), shape(nodes));
    });

    test('paragraph with a child keeps the child nested', () {
      final nodes = <Node>[
        paragraphNode(text: 't', children: <Node>[paragraphNode(text: 'c')]),
      ];
      expect(shape(roundTrip(nodes).root.children), shape(nodes));
    });

    test('export wraps a child list item in its own ul', () {
      final doc = Document.blank(withInitialText: false)
        ..insert([
          0
        ], [
          bulletedListNode(
              text: 'a', children: <Node>[bulletedListNode(text: 'b')]),
        ]);
      expect(documentToHTML(doc), contains('<ul><li>b</li></ul>'));
    });
  });

  group('html nested todo', () {
    test('checked and unchecked todos keep state', () {
      final nodes = <Node>[
        todoListNode(checked: true, text: 'x'),
        todoListNode(checked: false, text: 'y'),
      ];
      expect(shape(roundTrip(nodes).root.children), shape(nodes));
    });

    test('nested todo keeps checkbox and depth', () {
      final nodes = <Node>[
        todoListNode(
          checked: false,
          text: 'p',
          children: <Node>[todoListNode(checked: true, text: 'q')],
        ),
      ];
      expect(shape(roundTrip(nodes).root.children), shape(nodes));
    });
  });

  group('Node', () {
    test('a lazy children iterable is consumed once and parents are linked',
        () {
      var pulls = 0;
      Iterable<Node> lazy() => [1, 2, 3].map((i) {
            pulls++;
            return paragraphNode(text: '$i');
          });
      final node = Node(type: 'x', children: lazy());
      expect(pulls, 3);
      expect(node.children.length, 3);
      for (final c in node.children) {
        expect(c.parent, same(node));
      }
    });

    test('lazy chain 12 deep pulls each node once', () {
      var pulls = 0;
      Node build(int d) => Node(
            type: 'x',
            children: d == 0
                ? const []
                : [d].map((_) {
                    pulls++;
                    return build(d - 1);
                  }),
          );
      final root = build(12);
      expect(pulls, 12);
      var depth = 0;
      for (var c = root; c.children.isNotEmpty; c = c.children.first) {
        expect(c.children.first.parent, same(c));
        depth++;
      }
      expect(depth, 12);
    });

    test('list, lazy iterable and fromJson build the same tree', () {
      Node leaf(String t, String id) =>
          Node(type: 'p', id: id, attributes: {'t': t});
      final ids = [newBlockId(), newBlockId(), newBlockId()];
      final fromList = Node(
          type: 'r',
          children: [for (var i = 0; i < 3; i++) leaf('$i', ids[i])]);
      final fromLazy =
          Node(type: 'r', children: [0, 1, 2].map((i) => leaf('$i', ids[i])));
      final fromJson = Node.fromJson({
        'type': 'r',
        'children': [
          for (var i = 0; i < 3; i++)
            {
              'type': 'p',
              'id': ids[i],
              'data': {'t': '$i'}
            },
        ],
      });
      for (final n in [fromList, fromLazy, fromJson]) {
        expect(n.children.map((c) => c.id), ids);
        expect(n.children.map((c) => c.attributes['t']), ['0', '1', '2']);
        expect(n.children.every((c) => identical(c.parent, n)), isTrue);
        expect(n.children[1].previous, same(n.children[0]));
      }
    });

    test('fromJson on a deep chain links every parent', () {
      Map<String, Object> chain(int d) => {
            'type': 'paragraph',
            if (d > 0) 'children': [chain(d - 1)],
          };
      var cur = Node.fromJson(chain(14));
      var depth = 0;
      while (cur.children.isNotEmpty) {
        final c = cur.children.first;
        expect(c.parent, same(cur));
        cur = c;
        depth++;
      }
      expect(depth, 14);
    });

    test('insert at an index inside the same parent moves, never drops', () {
      final a = paragraphNode(text: 'a');
      final b = paragraphNode(text: 'b');
      final c = paragraphNode(text: 'c');
      final p = Node(type: 'x', children: <Node>[a, b, c]);
      String order() => p.children.map((n) => n.delta!.toPlainText()).join();
      // index is the final position of the moved node.
      p.insert(a, index: 2);
      expect(order(), 'bca');
      expect(a.parent, same(p));
      p.insert(a, index: 1);
      expect(order(), 'bac');
      p.insert(c, index: 0);
      expect(order(), 'cba');
    });
  });

  group('QuillDeltaEncoder', () {
    test('two conversions in a row are independent', () {
      final enc = QuillDeltaEncoder();
      final d1 = Delta()
        ..insert('a')
        ..insert('\n', attributes: {'list': 'bullet'})
        ..insert('b')
        ..insert('\n', attributes: {'list': 'bullet', 'indent': 1});
      final d2 = Delta()
        ..insert('x')
        ..insert('\n', attributes: {'list': 'bullet', 'indent': 1});
      enc.convert(d1);
      final doc2 = enc.convert(d2);
      expect(shape(doc2.root.children), ['bulleted_list:x']);
    });

    test('indented bullet after a paragraph does not throw', () {
      final d = Delta()
        ..insert('p\n')
        ..insert('b')
        ..insert('\n', attributes: {'list': 'bullet', 'indent': 1});
      final doc = QuillDeltaEncoder().convert(d);
      expect(shape(doc.root.children), ['paragraph:p', 'bulleted_list:b']);
    });

    test('child index counts only the own parent', () {
      final d = Delta()
        ..insert('a')
        ..insert('\n', attributes: {'list': 'bullet'})
        ..insert('a1')
        ..insert('\n', attributes: {'list': 'bullet', 'indent': 1})
        ..insert('b')
        ..insert('\n', attributes: {'list': 'bullet'})
        ..insert('b1')
        ..insert('\n', attributes: {'list': 'bullet', 'indent': 1});
      final doc = QuillDeltaEncoder().convert(d);
      expect(shape(doc.root.children), [
        'bulleted_list:a',
        '  bulleted_list:a1',
        'bulleted_list:b',
        '  bulleted_list:b1',
      ]);
    });

    test('indented to-do keeps its depth', () {
      final d = Delta()
        ..insert('a')
        ..insert('\n', attributes: {'list': 'bullet'})
        ..insert('t')
        ..insert('\n', attributes: {'list': 'checked', 'indent': 1});
      final doc = QuillDeltaEncoder().convert(d);
      expect(shape(doc.root.children), [
        'bulleted_list:a',
        '  todo_list:t:checked',
      ]);
    });

    test('text with three newline-separated parts keeps all parts', () {
      final d = Delta()..insert('one\ntwo\nthree');
      final doc = QuillDeltaEncoder().convert(d);
      expect(shape(doc.root.children),
          ['paragraph:one', 'paragraph:two', 'paragraph:three']);
    });
  });
}
