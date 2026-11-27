import 'dart:convert';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';

final QuillDeltaEncoder quillDeltaEncoder = QuillDeltaEncoder();

const _newLineSymbol = '\n';
const _header = 'header';
const _list = 'list';
const _orderedList = 'ordered';
const _bulletedList = 'bullet';
const _uncheckedList = 'unchecked';
const _checkedList = 'checked';
const _blockquote = 'blockquote';
const _indent = 'indent';

class QuillDeltaEncoder extends Converter<Delta, Document> {
  /// The last list item seen per indent level of the current run of list items; reset per [convert] and by any
  /// non-list block, so one document (or one paragraph) never nests under another's items.
  final Map<int, Node> _lastAtLevel = {};

  @override
  Document convert(Delta input) {
    _lastAtLevel.clear();
    final iterator = input.iterator;
    final document = Document.blank(withInitialText: false);

    Node node = paragraphNode();
    int index = 0;

    while (iterator.moveNext()) {
      final op = iterator.current;
      final attributes = op.attributes;
      if (op is TextInsert) {
        if (op.text == _newLineSymbol) {
          if (attributes != null) {
            node = _applyListStyleIfNeeded(node, attributes);
            node = _applyHeadingStyleIfNeeded(node, attributes);
            node = _applyBlockquoteIfNeeded(node, attributes);
            _applyIndentIfNeeded(node, attributes);
          }
          final level = _isListNode(node) ? _indentLevel(attributes) : null;
          final parent = level == null ? null : _parentFor(level);
          if (level != null) {
            _lastAtLevel.removeWhere((l, _) => l >= level);
            _lastAtLevel[level] = node;
          } else {
            _lastAtLevel.clear();
          }
          if (parent != null) {
            document.insert([...parent.path, parent.children.length], [node]);
          } else {
            document.insert([index++], [node]);
          }
          node = paragraphNode();
        } else {
          final texts = op.text.split(_newLineSymbol);
          for (var i = 0; i < texts.length; i++) {
            if (texts[i].isNotEmpty) {
              _applyStyle(node, texts[i], attributes);
            }
            if (i < texts.length - 1) {
              _lastAtLevel.clear();
              document.insert([index++], [node]);
              node = paragraphNode();
            }
          }
        }
      } else {
        throw UnsupportedError('only support text insert operation');
      }
    }

    // Text after the last newline is still a block of its own.
    if (index == 0 || (node.delta?.toPlainText().isNotEmpty ?? false)) {
      document.insert([index], [node]);
    }

    return document;
  }

  bool _isListNode(Node node) => const {
        BulletedListBlockKeys.type,
        NumberedListBlockKeys.type,
        TodoListBlockKeys.type,
      }.contains(node.type);

  /// The nearest item below [level] in the current run, or null for a top-level block.
  Node? _parentFor(int level) {
    for (var l = level - 1; l >= 0; l--) {
      final candidate = _lastAtLevel[l];
      if (candidate != null) return candidate;
    }
    return null;
  }

  void _applyStyle(Node node, String text, Map<String, dynamic>? attributes) {
    final Attributes attrs = {};
    if (_containsStyle(attributes, 'strike')) {
      attrs[AppFlowyRichTextKeys.strikethrough] = true;
    }
    if (_containsStyle(attributes, 'underline')) {
      attrs[AppFlowyRichTextKeys.underline] = true;
    }
    if (_containsStyle(attributes, 'bold')) {
      attrs[AppFlowyRichTextKeys.bold] = true;
    }
    if (_containsStyle(attributes, 'italic')) {
      attrs[AppFlowyRichTextKeys.italic] = true;
    }
    final link = attributes?['link'] as String?;
    if (link != null) {
      attrs[AppFlowyRichTextKeys.href] = link;
    }
    final color = attributes?['color'] as String?;
    final colorHex = _convertColorToHexString(color);
    if (colorHex != null) {
      attrs[AppFlowyRichTextKeys.textColor] = colorHex;
    }
    final backgroundColor = attributes?['background'] as String?;
    final backgroundHex = _convertColorToHexString(backgroundColor);
    if (backgroundHex != null) {
      attrs[AppFlowyRichTextKeys.backgroundColor] = backgroundHex;
    }
    node.updateAttributes({
      'delta': (node.delta?..insert(text, attributes: attrs))?.toJson(),
    });
  }

  void _applyIndentIfNeeded(Node node, Map<String, dynamic> attributes) {
    final indent = attributes[_indent] as int?;
    final list = attributes[_list] as String?;
    if (indent != null && list == null && node.delta != null) {
      node.updateAttributes({
        'delta': node.delta
            ?.compose(
              Delta()
                ..retain(0)
                ..insert('  ' * indent),
            )
            .toJson(),
      });
    }
  }

  Node _applyBlockquoteIfNeeded(Node node, Map<String, dynamic> attributes) {
    final blockquote = attributes[_blockquote] as bool?;
    if (blockquote == true) {
      return quoteNode(
        delta: node.delta,
      );
    }
    return node;
  }

  Node _applyHeadingStyleIfNeeded(Node node, Map<String, dynamic> attributes) {
    final header = attributes[_header] as int?;
    if (header == null) {
      return node;
    }
    return headingNode(
      delta: node.delta,
      level: header,
    );
  }

  // If the attributes contains the list style, then apply the list style to the node.
  Node _applyListStyleIfNeeded(Node node, Map<String, dynamic> attributes) {
    final list = attributes[_list] as String?;
    switch (list) {
      case _bulletedList:
        final bulletedList = bulletedListNode(
          delta: node.delta,
        );
        return bulletedList;
      case _orderedList:
        final numberedList = numberedListNode(
          delta: node.delta,
        );
        return numberedList;
      case _checkedList:
        final checkedList = todoListNode(
          delta: node.delta,
          checked: true,
        );
        return checkedList;
      case _uncheckedList:
        final uncheckedList = todoListNode(
          delta: node.delta,
          checked: false,
        );
        return uncheckedList;
      default:
        return node;
    }
  }

  int _indentLevel(Map? attributes) {
    final indent = attributes?[_indent] as int?;
    return indent ?? 0;
  }

  bool _containsStyle(Map<String, dynamic>? attributes, String key) {
    final value = attributes?[key] as bool?;
    return value == true;
  }

  String? _convertColorToHexString(String? color) {
    if (color == null) {
      return null;
    }
    if (color.startsWith('#')) {
      return '0xFF${color.substring(1)}';
    } else if (color.startsWith("rgba")) {
      List rgbaList = color.substring(5, color.length - 1).split(',');
      return Color.fromRGBO(
        int.parse(rgbaList[0]),
        int.parse(rgbaList[1]),
        int.parse(rgbaList[2]),
        double.parse(rgbaList[3]),
      ).toHex();
    }
    return null;
  }
}
