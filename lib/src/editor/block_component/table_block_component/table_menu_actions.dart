// Table menu — injected by the host app.
//
// Same decoupling as [ImageActions] and [NoteLinkNavigator]: the fork owns the
// handles on a table's rows and columns and every document edit
// ([TableActions]); the host owns the menu screen, which uses its own design system
// widgets and localized strings the fork may not import.
//
// The fork reads this with `context.read<TableMenuActions>()` inside a
// `try { } on ProviderNotFoundException`. With no provider a handle keeps its
// old built-in menu.

import 'package:flutter/widgets.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// Which row or column handle was pressed, and on which table.
@immutable
class TableMenuRequest {
  const TableMenuRequest({
    required this.table,
    required this.editorState,
    required this.position,
    required this.dir,
  });

  /// The table node (not a cell).
  final Node table;
  final EditorState editorState;

  /// Zero-based row or column index, per [dir].
  final int position;
  final TableDirection dir;
}

/// The host's table menu. It applies the user's choice itself through
/// [TableActions] and the table text helpers.
abstract interface class TableMenuActions {
  Future<void> showTableMenu(BuildContext context, TableMenuRequest request);
}
