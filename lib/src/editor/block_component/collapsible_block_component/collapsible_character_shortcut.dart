import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/services.dart';

/// Convert '>> ' to a collapsible block. ('> ' is the quote; a second '>' makes
/// it fold.)
///
/// - support
///   - desktop
///   - mobile
///   - web
///
CharacterShortcutEvent formatDoubleGreaterToCollapsible =
    CharacterShortcutEvent(
  key: 'format double greater to collapsible',
  character: ' ',
  handler: (editorState) async => await formatMarkdownSymbol(
    editorState,
    (node) => node.type != CollapsibleBlockKeys.type,
    (_, text, __) => text == '>>',
    (_, node, delta) => [
      collapsibleNode(
        delta: delta.compose(Delta()..delete(2)),
      ),
      if (node.children.isNotEmpty) ...node.children,
    ],
  ),
);

/// Enter inside a collapsible's title.
///
/// - Empty title, nothing inside: leave the block (outdent or back to text),
///   like every other list-like block.
/// - Open: the text after the caret starts the first line INSIDE the block, so
///   typing carries on in the body.
/// - Closed: a new line after the whole block (its body stays hidden and
///   untouched); text after the caret moves to that new line.
///
/// - support
///   - desktop
///   - web
///   - mobile
///
CharacterShortcutEvent insertNewLineAfterCollapsible = CharacterShortcutEvent(
  key: 'insert new block after collapsible',
  character: '\n',
  handler: (editorState) async {
    if (HardwareKeyboard.instance.isShiftPressed) return false;
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) return false;
    final node = editorState.getNodeAtPath(selection.end.path);
    final delta = node?.delta;
    if (node == null ||
        node.type != CollapsibleBlockKeys.type ||
        delta == null) {
      return false;
    }

    if (selection.startIndex == 0 && delta.isEmpty && node.children.isEmpty) {
      return await insertNewLineInType(editorState, CollapsibleBlockKeys.type);
    }

    final offset = selection.startIndex;
    if (offset == 0 && !delta.isEmpty) {
      // Caret at the very start of a titled block: Enter opens a blank line
      // ABOVE it and leaves the block (and its body) exactly as it was,
      // instead of pushing the title out from over its own body.
      final above = editorState.transaction
        ..insertNode(node.path, paragraphNode(), deepCopy: true);
      above.afterSelection = Selection.collapsed(
        Position(path: node.path.next, offset: 0),
      );
      above.selectionExtraInfo = {};
      above.customSelectionType = SelectionType.inline;
      await editorState.apply(above);
      return true;
    }
    final tail = delta.slice(offset);
    final transaction = editorState.transaction;
    if (offset < delta.length) {
      transaction.deleteText(node, offset, delta.length - offset);
    }
    final inserted = paragraphNode(
      attributes: {
        ParagraphBlockKeys.delta: tail.toJson(),
        if (node.attributes[blockComponentTextDirection] != null)
          blockComponentTextDirection:
              node.attributes[blockComponentTextDirection],
      },
    );
    final Path target;
    if (isCollapsibleClosed(node)) {
      target = node.path.next;
    } else {
      target = [...node.path, 0];
    }
    transaction.insertNode(target, inserted, deepCopy: true);
    transaction.afterSelection = Selection.collapsed(
      Position(path: target, offset: 0),
    );
    transaction.selectionExtraInfo = {};
    transaction.customSelectionType = SelectionType.inline;
    await editorState.apply(transaction);
    return true;
  },
);
