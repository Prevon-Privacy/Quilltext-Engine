import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';

final List<CommandShortcutEvent> arrowRightKeys = [
  moveCursorRightCommand,
  moveCursorToEndCommand,
  moveCursorToRightWordCommand,
  moveCursorRightSelectCommand,
  moveCursorEndSelectCommand,
  moveCursorRightWordSelectCommand,
];

/// Arrow right key events.
///
/// - support
///   - desktop
///   - web
///

// arrow right key
// move the cursor backward one character
final CommandShortcutEvent moveCursorRightCommand = CommandShortcutEvent(
  key: 'move the cursor forward one character',
  getDescription: () => AppFlowyEditorL10n.current.cmdMoveCursorRight,
  command: 'arrow right',
  handler: _arrowRightCommandHandler,
);

CommandShortcutEventHandler _arrowRightCommandHandler = (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  if (isRTL(editorState)) {
    editorState.moveCursorForward(SelectionMoveRange.character);
  } else {
    editorState.moveCursorBackward(SelectionMoveRange.character);
  }
  return KeyEventResult.handled;
};

// arrow right key + ctrl or command
// move the cursor to the end of the block
final CommandShortcutEvent moveCursorToEndCommand = CommandShortcutEvent(
  key: 'move the cursor to the end of line',
  getDescription: () => AppFlowyEditorL10n.current.cmdMoveCursorLineEnd,
  command: 'end',
  macOSCommand: 'cmd+arrow right',
  handler: _moveCursorToEndCommandHandler,
);

CommandShortcutEventHandler _moveCursorToEndCommandHandler = (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  if (isRTL(editorState)) {
    editorState.moveCursorForward(SelectionMoveRange.line);
  } else {
    final edge = visualLineEdge(editorState, selection.end, atStart: false);
    if (edge != null) {
      editorState.updateSelectionWithReason(
        Selection.collapsed(edge),
        reason: SelectionUpdateReason.uiEvent,
      );
    } else {
      editorState.moveCursorBackward(SelectionMoveRange.line);
    }
  }
  return KeyEventResult.handled;
};

// arrow right key + alt
// move the cursor to the right word
final CommandShortcutEvent moveCursorToRightWordCommand = CommandShortcutEvent(
  key: 'move the cursor to the right word',
  getDescription: () => AppFlowyEditorL10n.current.cmdMoveCursorWordRight,
  command: 'ctrl+arrow right',
  macOSCommand: 'alt+arrow right',
  handler: _moveCursorToRightWordCommandHandler,
);

CommandShortcutEventHandler _moveCursorToRightWordCommandHandler =
    (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }

  final node = editorState.getNodeAtPath(selection.end.path);
  final delta = node?.delta;

  if (node == null || delta == null) {
    return KeyEventResult.ignored;
  }

  if (isRTL(editorState)) {
    final startOfWord = selection.end.moveHorizontal(
      editorState,
      selectionRange: SelectionRange.word,
    );
    if (startOfWord == null) {
      return KeyEventResult.ignored;
    }
    // PREVON PATCH 40: at offset 0 the word position is in the previous block: just step there.
    if (!startOfWord.path.equals(node.path)) {
      editorState.moveCursorForward(SelectionMoveRange.word);
      return KeyEventResult.handled;
    }
    final selectedWord = delta.toPlainText().substring(
          startOfWord.offset,
          selection.end.offset,
        );
    // check if the selected word is whitespace
    if (selectedWord.trim().isEmpty) {
      editorState.moveCursorForward(SelectionMoveRange.word);
    }
    editorState.moveCursorForward(SelectionMoveRange.word);
  } else {
    final endOfWord = selection.end.moveHorizontal(
      editorState,
      forward: false,
      selectionRange: SelectionRange.word,
    );
    if (endOfWord == null) {
      return KeyEventResult.handled;
    }
    // PREVON PATCH 40: at the end of the block the word position is in the next block: just step there.
    if (!endOfWord.path.equals(node.path)) {
      editorState.moveCursorBackward(SelectionMoveRange.word);
      return KeyEventResult.handled;
    }
    final selectedLine = delta.toPlainText();
    final selectedWord = selectedLine.substring(
      selection.end.offset,
      endOfWord.offset,
    );
    // check if the selected word is whitespace
    if (selectedWord.trim().isEmpty) {
      editorState.moveCursorBackward(SelectionMoveRange.word);
    }
    editorState.moveCursorBackward(SelectionMoveRange.word);
  }
  return KeyEventResult.handled;
};

// arrow right key + alt + shift
final CommandShortcutEvent moveCursorRightWordSelectCommand =
    CommandShortcutEvent(
  key: 'move the cursor to select the right word',
  getDescription: () => AppFlowyEditorL10n.current.cmdMoveCursorWordRightSelect,
  command: 'ctrl+shift+arrow right',
  macOSCommand: 'alt+shift+arrow right',
  handler: _moveCursorRightWordSelectCommandHandler,
);

CommandShortcutEventHandler _moveCursorRightWordSelectCommandHandler =
    (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  var forward = false;
  if (isRTL(editorState)) {
    forward = true;
  }
  final end = selection.end.moveHorizontal(
    editorState,
    selectionRange: SelectionRange.word,
    forward: forward,
  );
  if (end == null) {
    return KeyEventResult.ignored;
  }
  editorState.updateSelectionWithReason(
    selection.copyWith(end: end),
    reason: SelectionUpdateReason.uiEvent,
  );
  return KeyEventResult.handled;
};

// arrow right key + shift
// selects only one character
final CommandShortcutEvent moveCursorRightSelectCommand = CommandShortcutEvent(
  key: 'move the cursor right select',
  getDescription: () => AppFlowyEditorL10n.current.cmdMoveCursorRightSelect,
  command: 'shift+arrow right',
  handler: _moveCursorRightSelectCommandHandler,
);

CommandShortcutEventHandler _moveCursorRightSelectCommandHandler =
    (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  var forward = false;
  if (isRTL(editorState)) {
    forward = true;
  }
  final end = selection.end.moveHorizontal(editorState, forward: forward);
  if (end == null) {
    return KeyEventResult.ignored;
  }
  editorState.updateSelectionWithReason(
    selection.copyWith(end: end),
    reason: SelectionUpdateReason.uiEvent,
  );
  return KeyEventResult.handled;
};

// arrow right key + shift + ctrl or cmd
final CommandShortcutEvent moveCursorEndSelectCommand = CommandShortcutEvent(
  key: 'move cursor to select till end of line',
  getDescription: () => AppFlowyEditorL10n.current.cmdMoveCursorLineEndSelect,
  command: 'shift+end',
  macOSCommand: 'cmd+shift+arrow right',
  handler: _moveCursorEndSelectCommandHandler,
);

CommandShortcutEventHandler _moveCursorEndSelectCommandHandler = (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  final nodes = editorState.getNodesInSelection(selection);
  if (nodes.isEmpty) {
    return KeyEventResult.ignored;
  }
  var end = selection.end;
  final position = isRTL(editorState)
      ? nodes.last.selectable?.start()
      : visualLineEdge(editorState, selection.end, atStart: false) ??
          nodes.last.selectable?.end();
  if (position != null) {
    end = position;
  }
  editorState.updateSelectionWithReason(
    selection.copyWith(end: end),
    reason: SelectionUpdateReason.uiEvent,
  );
  return KeyEventResult.handled;
};
