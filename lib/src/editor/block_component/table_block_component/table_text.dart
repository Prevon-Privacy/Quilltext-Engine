// A table as plain text, for "copy table".
//
// Pure functions over the table [Node]: no widgets, no clipboard. A cell's
// text is its blocks' text joined with a space; a table whose cell positions
// are inconsistent yields empty strings rather than throwing.

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// The text of one cell: each of its blocks' text, empty blocks skipped,
/// joined with a single space.
String tableCellText(Node cell) => cell.children
    .map((c) => c.delta?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .join(' ');

/// Every cell's text, as `rows[row][col]`.
List<List<String>> tableRowsText(Node table) {
  final cols = table.attributes[TableBlockKeys.colsLen];
  final rows = table.attributes[TableBlockKeys.rowsLen];
  if (cols is! int || rows is! int) return const [];
  return [
    for (var r = 0; r < rows; r++)
      [
        for (var c = 0; c < cols; c++)
          () {
            final cell = getCellNode(table, c, r);
            return cell == null ? '' : tableCellText(cell);
          }(),
      ],
  ];
}

/// Whether no cell of [table] holds any text.
bool tableHasNoText(Node table) =>
    tableRowsText(table).every((row) => row.every((s) => s.isEmpty));

String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Tab-separated rows, one per line: pastes into a spreadsheet as a grid.
String tableToTsv(Node table) =>
    tableRowsText(table).map((row) => row.map(_oneLine).join('\t')).join('\n');

/// A GitHub-style Markdown table; the first row is the header.
String tableToMarkdown(Node table) {
  final rows = tableRowsText(table);
  if (rows.isEmpty || rows.first.isEmpty) return '';
  String cell(String s) {
    final t = _oneLine(s).replaceAll('|', r'\|');
    return t.isEmpty ? ' ' : t;
  }

  String line(List<String> row) => '| ${row.map(cell).join(' | ')} |';
  return [
    line(rows.first),
    '| ${List.filled(rows.first.length, '---').join(' | ')} |',
    for (final row in rows.skip(1)) line(row),
  ].join('\n');
}
