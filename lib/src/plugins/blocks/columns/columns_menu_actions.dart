// Columns menu - injected by the host app.
//
// Same decoupling as [TableMenuActions]: the fork draws the grip above each
// column and owns every document edit ([ColumnsActions]); the host owns the
// menu screen, which uses design-system widgets and localized strings the fork may
// not import. The fork reads this with `context.read<ColumnsMenuActions>()`
// inside a `try { } on ProviderNotFoundException`; with no provider a grip
// does nothing.

import 'package:flutter/widgets.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// Which column's grip was pressed, and in which columns block.
@immutable
class ColumnsMenuRequest {
  const ColumnsMenuRequest({
    required this.columns,
    required this.editorState,
    required this.position,
  });

  /// The columns block (not a column).
  final Node columns;
  final EditorState editorState;

  /// Zero-based index of the pressed column, left to right.
  final int position;
}

/// The host's columns menu. It applies the user's choice itself through
/// [ColumnsActions].
abstract interface class ColumnsMenuActions {
  Future<void> showColumnsMenu(
    BuildContext context,
    ColumnsMenuRequest request,
  );
}
