import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';

/// Outdent the current block
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent outdentCommand = CommandShortcutEvent(
  key: 'outdent',
  getDescription: () => AppFlowyEditorL10n.current.cmdOutdent,
  command: 'shift+tab',
  handler: _outdentCommandHandler,
);

/// PATCH 14: Ctrl+[ (Cmd+[ on macOS) — the same outdent.
final CommandShortcutEvent outdentBracketCommand = CommandShortcutEvent(
  key: 'outdent (bracket)',
  getDescription: () => AppFlowyEditorL10n.current.cmdOutdent,
  command: 'ctrl+bracket left',
  macOSCommand: 'cmd+bracket left',
  handler: _outdentCommandHandler,
);

/// The rows Shift+Tab moves: the selected rows that sit inside a container,
/// taken from the first nested one (a range that starts or ends on a top-level
/// row outdents its nested part instead of doing nothing), limited to the
/// children of that one parent. Empty when nothing can move.
List<Node> outdentableNodes(EditorState editorState) {
  final selection = editorState.selection?.normalized;
  if (selection == null) return const [];
  final nested = editorState
      .getNodesInSelection(selection)
      .normalized
      .where((node) => node.path.length > 1)
      .toList();
  if (nested.isEmpty) return const [];
  final parent = nested.first.parent;
  if (parent == null || !indentableBlockTypes.contains(parent.type)) {
    return const [];
  }
  final run = nested.where((node) => node.parent == parent).toList();
  return run.every((node) => movableBlockTypes.contains(node.type))
      ? run
      : const [];
}

bool isOutdentable(EditorState editorState) =>
    outdentableNodes(editorState).isNotEmpty;

CommandShortcutEventHandler _outdentCommandHandler = (editorState) {
  if (editorState.selection == null) return KeyEventResult.ignored;
  // ignore the system default tab behavior even when nothing can move
  final nodes = outdentableNodes(editorState);
  if (nodes.isNotEmpty) outdentBlocks(editorState, nodes);
  return KeyEventResult.handled;
};
