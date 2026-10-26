import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/ime/character_shortcut_event_helper.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/ime/delta_input_impl.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';
import 'package:flutter/services.dart';

Future<void> onReplace(
  TextEditingDeltaReplacement replacement,
  EditorState editorState,
  List<CharacterShortcutEvent> characterShortcutEvents,
) async {
  AppFlowyEditorLog.input.debug('onReplace: $replacement');

  // delete the selection
  final selection = editorState.selection;
  if (selection == null) {
    return;
  }

  if (selection.isSingle) {
    // PREVON PATCH 16 — Enter while a word is still being composed.
    // Gboard (and most Android IMEs) do not send a bare "\n" then: they REPLACE
    // the composing word with "word\n". No character shortcut is registered for
    // "word\n", so the newline was written into the text as a literal line
    // break — pressing Enter right after typing in a bullet / to-do / numbered
    // item made a soft break inside the item instead of a new one. Commit the
    // word first, then run the ordinary "\n" shortcuts at the end of it.
    final text = replacement.replacementText;
    if (text.length > 1 &&
        text.endsWith('\n') &&
        !text.substring(0, text.length - 1).contains('\n')) {
      final word = text.substring(0, text.length - 1);
      final wordEnd = replacement.replacedRange.start + word.length;
      await onReplace(
        TextEditingDeltaReplacement(
          oldText: replacement.oldText,
          replacementText: word,
          replacedRange: replacement.replacedRange,
          selection: TextSelection.collapsed(offset: wordEnd),
          composing: TextRange.empty,
        ),
        editorState,
        characterShortcutEvents,
      );
      final ran = await executeCharacterShortcutEvent(
        editorState,
        '\n',
        characterShortcutEvents,
      );
      if (!ran) {
        // No shortcut wanted the newline: keep the literal break.
        await onInsert(
          TextEditingDeltaInsertion(
            oldText: replacement.oldText,
            textInserted: '\n',
            insertionOffset: wordEnd,
            selection: TextSelection.collapsed(offset: wordEnd + 1),
            composing: TextRange.empty,
          ),
          editorState,
          characterShortcutEvents,
        );
      }
      return;
    }

    final execution = await executeCharacterShortcutEvent(
      editorState,
      replacement.replacementText,
      characterShortcutEvents,
    );

    if (execution) {
      return;
    }

    if (PlatformExtension.isIOS) {
      // remove the trailing '\n' when pressing the return key
      if (replacement.replacementText.endsWith('\n')) {
        replacement = TextEditingDeltaReplacement(
          oldText: replacement.oldText,
          replacementText: replacement.replacementText
              .substring(0, replacement.replacementText.length - 1),
          replacedRange: replacement.replacedRange,
          selection: replacement.selection,
          composing: replacement.composing,
        );
      }
    }

    final node = editorState.getNodesInSelection(selection).first;
    final transaction = editorState.transaction;
    final start = replacement.replacedRange.start;
    final length = replacement.replacedRange.end - start;
    final afterSelection = Selection(
      start: Position(
        path: node.path,
        offset: replacement.selection.baseOffset,
      ),
      end: Position(
        path: node.path,
        offset: replacement.selection.extentOffset,
      ),
    );
    transaction
      ..replaceText(node, start, length, replacement.replacementText)
      ..afterSelection = afterSelection;
    await editorState.apply(transaction);
  } else {
    await editorState.deleteSelection(selection);
    // insert the replacement
    final insertion = replacement.toInsertion();
    await onInsert(
      insertion,
      editorState,
      characterShortcutEvents,
    );
  }
}

extension on TextEditingDeltaReplacement {
  TextEditingDeltaInsertion toInsertion() {
    final text = oldText.replaceRange(
      replacedRange.start,
      replacedRange.end,
      '',
    );
    return TextEditingDeltaInsertion(
      oldText: text,
      textInserted: replacementText,
      insertionOffset: replacedRange.start,
      selection: selection,
      composing: composing,
    );
  }
}
