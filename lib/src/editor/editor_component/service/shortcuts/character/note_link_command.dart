// In-note note/folder `[[` trigger — fires on the SECOND `[` typed at the
// caret. The handler asks the host app (Pie Notes, supplied via
// Provider<NoteLinkPickerController>) to surface a picker overlay.
//
// MANDATE: deep clone of slashCommand's structure (the precedent cited in
// the spec — see forks/prevon_quilltext_engine/lib/src/editor/editor_component/
// service/shortcuts/character/slash_command.dart:23-30) but adapted for
// two-character triggers. CharacterShortcutEvent's constructor assertion
// (character_shortcut_event.dart:22-23) only accepts a single char, so the
// trigger is a single `[` and the handler checks that the character
// immediately before the caret is also `[`.
//
// IMPORTANT: this handler runs BEFORE the in-flight `[` is inserted into the
// document (see character_shortcut_event_helper.dart / delta_input_on_insert_impl.dart —
// the character is only applied afterward, and only if this handler returns
// false). So on the second `[` keystroke, the document still contains only
// the FIRST bracket (from keystroke 1) — check exactly one character back,
// not two, or the trigger won't fire until a third bracket is typed.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

const Set<String> _supportNoteLinkNodeTypes = {
  ParagraphBlockKeys.type,
  HeadingBlockKeys.type,
  TodoListBlockKeys.type,
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
  QuoteBlockKeys.type,
};

/// `[[` character event. Fires on each `[` typed at the caret; the handler
/// confirms the prior character is also `[` before opening the picker.
final CharacterShortcutEvent noteLinkCommand = CharacterShortcutEvent(
  key: 'in-note note/folder link',
  character: '[',
  handler: (editorState) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) return false;
    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null || !_isSupportNoteLinkNode(node)) return false;

    // Verify the character immediately before the caret is also `[`. Only
    // one prior bracket is in the document at this point — see the file
    // header comment for why this must be a one-character-back check.
    final delta = node.delta;
    if (delta == null) return false;
    final caret = selection.start.offset;
    if (caret < 1) return false;
    final plain = delta.toPlainText();
    if (plain.length < caret) return false;
    if (plain[caret - 1] != '[') return false;

    // Resolve the picker controller from context. The Provider is wired
    // above the AppFlowyEditor by Pie Notes; the controller is the host's
    // own overlay manager. Use the editor's own service-key contexts to
    // reach a live BuildContext (editorState.renderBox is a RenderBox —
    // it does NOT carry a `context` getter).
    final ctx = editorState.service.scrollServiceKey.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    final controller = ctx.read<NoteLinkPickerController>();

    keepEditorFocusNotifier.increase();
    controller.showOrReplace(
      editorState,
      ctx,
      onPicked: (picked) => _onPicked(editorState, picked),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => keepEditorFocusNotifier.decrease(),
    );
    return true;
  },
);

void _onPicked(EditorState editorState, NoteLinkPick picked) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) return;
  final node = editorState.getNodeAtPath(selection.start.path);
  if (node == null) return;

  // The text immediately before the caret is `[` — only the first bracket
  // was actually inserted into the document; the second (which fired this
  // trigger) was suppressed by the handler above returning true. Find that
  // single bracket and delete it in a single transaction, then insert the
  // picked label and apply the corresponding inline attribute.
  final delta = node.delta;
  if (delta == null) return;
  final caret = selection.start.offset;
  final plain = delta.toPlainText();
  if (caret < 1) return;
  if (plain[caret - 1] != '[') return;
  final startOfBrackets = caret - 1;
  // After deleting `[[…<typed>` the caret sits at `startOfBrackets` in the
  // shrunk node. Insert + format at exactly that offset, then put the
  // caret just past the inserted label.
  final insertOffset = startOfBrackets;
  final labelLen = picked.label.length;

  final transaction = editorState.transaction
    ..deleteText(
      node,
      startOfBrackets,
      caret - startOfBrackets,
    )
    ..insertText(
      node,
      insertOffset,
      picked.label,
    )
    ..formatText(
      node,
      insertOffset,
      labelLen,
      picked.isFolder
          ? {AppFlowyRichTextKeys.folderLink: picked.id}
          : {AppFlowyRichTextKeys.noteLink: picked.id},
    )
    ..afterSelection = Selection.collapsed(
      Position(path: selection.end.path, offset: insertOffset + labelLen),
    );
  editorState.apply(transaction);
}

bool _isSupportNoteLinkNode(Node node) =>
    _supportNoteLinkNodeTypes.contains(node.type) ||
    (node.level > 1 && node.parent != null
        ? _isSupportNoteLinkNode(node.parent!)
        : false);
