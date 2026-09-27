import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';

/// End key event.
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent exitEditingCommand = CommandShortcutEvent(
  key: 'exit the editing mode',
  getDescription: () => AppFlowyEditorL10n.current.cmdExitEditing,
  command: 'escape',
  handler: _exitEditingCommandHandler,
);

CommandShortcutEventHandler _exitEditingCommandHandler = (editorState) {
  editorState.selection = null;
  editorState.service.keyboardService?.closeKeyboard();
  return KeyEventResult.handled;
};
