import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// Guarantees an editable paragraph directly before and after every top-level
/// block that has no text position of its own (image, divider, table, ...).
///
/// Without it the caret cannot be placed above or below such a block, so a
/// note that starts or ends with one (or has two in a row) traps the user: the
/// block has to be deleted and re-added around hand-made blank lines. The
/// paragraphs are ordinary, fully editable ones; they are just never absent.
/// The fix-up is not recorded on the undo stack so undo cannot be trapped by
/// the rule re-adding what was just undone.
class SurroundNonTextBlocksRule extends DocumentRule {
  const SurroundNonTextBlocksRule();

  @override
  bool shouldApply({
    required EditorState editorState,
    required EditorTransactionValue value,
  }) {
    if (value.$1 != TransactionTime.after) {
      return false;
    }
    return _missingPaths(editorState.document.root).isNotEmpty;
  }

  @override
  Future<void> apply({
    required EditorState editorState,
    required EditorTransactionValue value,
  }) =>
      normalize(editorState);

  /// Adds any missing guard paragraphs now. Call once when a document is
  /// loaded so a note saved without them (e.g. a lone image) is fixed before
  /// the first edit, which the rule alone could never get a chance to see.
  static Future<void> normalize(EditorState editorState) async {
    final paths = _missingPaths(editorState.document.root);
    if (paths.isEmpty) {
      return;
    }
    final transaction = editorState.transaction;
    // Insert from the bottom up so earlier paths stay valid.
    for (final path in paths.reversed) {
      transaction.insertNode([path], paragraphNode());
    }
    transaction.afterSelection = editorState.selection;
    await editorState.apply(
      transaction,
      options: const ApplyOptions(recordUndo: false),
      withUpdateSelection: false,
    );
  }

  /// Top-level indices (as paths, ascending) where a paragraph is missing.
  static List<int> _missingPaths(Node root) =>
      missingGuardIndices([for (final c in root.children) c.delta != null]);

  /// The same decision on a plain layout: [hasText] says, for each top-level block in order, whether it
  /// has a text position. Returns the indices a guard paragraph must be inserted at (ascending).
  /// A caller that rearranges blocks inside ONE transaction uses this to add the guards in that same
  /// transaction, so the fix-up is recorded with the move and undo restores the exact original layout
  /// (a guard added afterwards, unrecorded, would shift the recorded paths).
  static List<int> missingGuardIndices(List<bool> hasText) {
    final result = <int>{};
    for (var i = 0; i < hasText.length; i++) {
      if (hasText[i]) {
        continue;
      }
      if (i == 0 || !hasText[i - 1]) {
        result.add(i);
      }
      if (i == hasText.length - 1) {
        result.add(i + 1);
      }
    }
    return result.toList()..sort();
  }
}
