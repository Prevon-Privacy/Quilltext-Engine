import 'dart:convert';
import 'dart:math';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// A [Delta] encoder that encodes a [Delta] to Markdown.
///
/// Only support inline styles, like bold, italic, underline, strike, code.
class DeltaMarkdownEncoder extends Converter<Delta, String> {
  @override
  String convert(Delta input) {
    final buffer = StringBuffer();
    final iterator = input.iterator;
    while (iterator.moveNext()) {
      final op = iterator.current;
      if (op is TextInsert) {
        final attributes = op.attributes;
        if (attributes != null) {
          final formula = attributes[BuiltInAttributeKey.formula] ?? '';
          if (formula.isNotEmpty) {
            buffer.write(_prefixSyntax(attributes));
            buffer.write(formula);
            buffer.write(_suffixSyntax(attributes));
          } else {
            // Markdown only opens an emphasis next to a word: `** x**` and `**x **` stay literal
            // asterisks. A span that starts or ends in spaces (a selection that took the space with it)
            // keeps them outside the markers, and a span of only spaces carries no markers at all.
            final text = op.text;
            final core = text.trim();
            if (core.isEmpty) {
              buffer.write(text);
            } else {
              final lead = text.substring(0, text.indexOf(core));
              final trail = text.substring(lead.length + core.length);
              buffer.write(lead);
              final isCode = attributes[BuiltInAttributeKey.code] == true;
              // A code span is fenced by more backticks than any run inside it, padded with a space when
              // the content itself starts or ends in a backtick.
              var fence = '`';
              var body = core;
              if (isCode) {
                final longest = RegExp(r'`+').allMatches(core).fold<int>(0, (m, e) => max(m, e.end - e.start));
                fence = '`' * (longest + 1);
                if (core.startsWith('`') || core.endsWith('`')) body = ' $core ';
              }
              buffer.write(_prefixSyntax(attributes, fence));
              buffer.write(isCode ? body : escapeMarkdownText(core));
              buffer.write(_suffixSyntax(attributes, fence));
              buffer.write(trail);
            }
          }
        } else {
          buffer.write(escapeMarkdownText(op.text));
        }
      }
    }
    return escapeMarkdownLineStarts(buffer.toString());
  }

  /// Characters the person typed that markdown would read as formatting, written so they come back as
  /// typed. Words with an underscore inside (snake_case) and a lone backslash are left alone: neither
  /// is formatting.
  static String escapeMarkdownText(String text) {
    if (text.isEmpty) return text;
    final out = StringBuffer();
    final hasPairOfTildes = '~'.allMatches(text).length >= 2;
    final looksLikeLink = text.contains('](');
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      final prev = i > 0 ? text[i - 1] : '';
      final next = i + 1 < text.length ? text[i + 1] : '';
      bool alnum(String x) => x.isNotEmpty && RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(x);
      final escape = switch (c) {
        '*' || '`' => true,
        '_' => !(alnum(prev) && alnum(next)),
        '~' => hasPairOfTildes,
        '[' || ']' => looksLikeLink,
        '<' => next.isNotEmpty && RegExp(r'[A-Za-z/!?]').hasMatch(next),
        r'\' => next.isNotEmpty && RegExp(r'[!-/:-@\[-`{-~]').hasMatch(next),
        _ => false,
      };
      if (escape) out.write(r'\');
      out.write(c);
    }
    return out.toString();
  }

  static final _blockStart = RegExp(
    r'^( {0,3})(#{1,6}(?=[ \t]|$)|>|[-+](?=[ \t]|$)|\d{1,9}[.)](?=[ \t]|$)|(?:-{3,}|={3,})[ \t]*$|\[[ xX]\](?=[ \t]|$))',
  );

  /// A line that begins like a heading, quote, list item or rule would turn into one when read back:
  /// the first character is escaped.
  static String escapeMarkdownLineStarts(String text) {
    if (text.isEmpty) return text;
    return text.split('\n').map((line) {
      final m = _blockStart.firstMatch(line);
      if (m == null) return line;
      final at = m.group(1)!.length;
      final marker = m.group(2)!;
      // `\1.` is no escape in markdown (only punctuation is), so a number is kept and its dot escaped.
      final shift = RegExp(r'^\d').hasMatch(marker) ? marker.length - 1 : 0;
      return '${line.substring(0, at + shift)}\\${line.substring(at + shift)}';
    }).join('\n');
  }

  String _prefixSyntax(Attributes attributes, [String fence = '`']) {
    var syntax = '';

    if (attributes[BuiltInAttributeKey.bold] == true &&
        attributes[BuiltInAttributeKey.italic] == true) {
      syntax += '***';
    } else if (attributes[BuiltInAttributeKey.bold] == true) {
      syntax += '**';
    } else if (attributes[BuiltInAttributeKey.italic] == true) {
      syntax += '_';
    }

    if (attributes[BuiltInAttributeKey.strikethrough] == true) {
      syntax += '~~';
    }
    if (attributes[BuiltInAttributeKey.underline] == true) {
      syntax += '<u>';
    }
    if (attributes[BuiltInAttributeKey.code] == true) {
      syntax += fence;
    }

    if (attributes[BuiltInAttributeKey.href] != null) {
      syntax += '[';
    }

    if (attributes[BuiltInAttributeKey.formula] != null) {
      syntax += r'$';
    }

    return syntax;
  }

  String _suffixSyntax(Attributes attributes, [String fence = '`']) {
    var syntax = '';

    if (attributes[BuiltInAttributeKey.href] != null) {
      syntax += '](${attributes[BuiltInAttributeKey.href]})';
    }

    if (attributes[BuiltInAttributeKey.code] == true) {
      syntax += fence;
    }

    if (attributes[BuiltInAttributeKey.underline] == true) {
      syntax += '</u>';
    }

    if (attributes[BuiltInAttributeKey.strikethrough] == true) {
      syntax += '~~';
    }

    if (attributes[BuiltInAttributeKey.bold] == true &&
        attributes[BuiltInAttributeKey.italic] == true) {
      syntax += '***';
    } else if (attributes[BuiltInAttributeKey.bold] == true) {
      syntax += '**';
    } else if (attributes[BuiltInAttributeKey.italic] == true) {
      syntax += '_';
    }

    if (attributes[BuiltInAttributeKey.formula] != null) {
      syntax += r'$';
    }

    return syntax;
  }
}
