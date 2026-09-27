import 'dart:io';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const Set<String> _defaultSupportSlashMenuNodeTypes = {
  ParagraphBlockKeys.type,
  HeadingBlockKeys.type,
  TodoListBlockKeys.type,
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
  QuoteBlockKeys.type,
};

/// Show the slash menu
///
/// - support
///   - desktop
///   - web
///
final CharacterShortcutEvent slashCommand = CharacterShortcutEvent(
  key: 'show the slash menu',
  character: '/',
  handler: (editorState) async => await _showSlashMenu(
    editorState,
    standardSelectionMenuItems,
  ),
);

CharacterShortcutEvent customSlashCommand(
  List<SelectionMenuItem> items, {
  bool shouldInsertSlash = true,
  bool deleteKeywordsByDefault = false,
  bool singleColumn = true,
  SelectionMenuStyle style = SelectionMenuStyle.light,
  Set<String> supportSlashMenuNodeTypes = _defaultSupportSlashMenuNodeTypes,
}) {
  return CharacterShortcutEvent(
    key: 'show the slash menu',
    character: '/',
    handler: (editorState) => _showSlashMenu(
      editorState,
      items,
      shouldInsertSlash: shouldInsertSlash,
      deleteKeywordsByDefault: deleteKeywordsByDefault,
      singleColumn: singleColumn,
      style: style,
      supportSlashMenuNodeTypes: supportSlashMenuNodeTypes,
    ),
  );
}

SelectionMenuService? _selectionMenuService;
Future<bool> _showSlashMenu(
  EditorState editorState,
  List<SelectionMenuItem> items, {
  bool shouldInsertSlash = true,
  bool singleColumn = true,
  bool deleteKeywordsByDefault = false,
  SelectionMenuStyle style = SelectionMenuStyle.light,
  Set<String> supportSlashMenuNodeTypes = _defaultSupportSlashMenuNodeTypes,
}) async {
  // The slash menu is no longer desktop/web-only. The mobile
  // gate that previously returned `false` here is removed so the menu
  // can render on iOS/Android too — the downstream helpers
  // (`MobileSelectionServiceWidgetState.selectionRects` and
  // `calculateSelectionMenuOffset`) have been taught the collapsed /
  // soft-keyboard cases that mobile relies on.
  final selection = editorState.selection;
  if (selection == null) {
    return false;
  }

  // delete the selection
  if (!selection.isCollapsed) {
    await editorState.deleteSelection(selection);
  }

  final afterSelection = editorState.selection;
  if (afterSelection == null || !afterSelection.isCollapsed) {
    assert(false, 'the selection should be collapsed');
    return true;
  }

  final node = editorState.getNodeAtPath(selection.start.path);

  // only enable in white-list nodes
  if (node == null ||
      !_isSupportSlashMenuNode(node, supportSlashMenuNodeTypes)) {
    return false;
  }

  // PREVON PATCH 12: trigger-position gate. Only open the menu when the caret
  // sits at the very start of the block, or when the character immediately
  // before it is whitespace. A "/" typed mid-word ("and/or", "https://") is
  // NOT a command trigger — return false so the normal insert path writes the
  // literal "/" exactly once and no menu opens.
  final anchorOffset = selection.start.offset;
  final plainText = node.delta?.toPlainText() ?? '';
  if (anchorOffset > plainText.length) {
    return false;
  }
  if (anchorOffset != 0) {
    final triggerChar = plainText[anchorOffset - 1];
    if (triggerChar != ' ' && triggerChar != '\n' && triggerChar != '\t') {
      return false;
    }
  }
  final anchorPath = selection.start.path;

  // insert the slash character
  if (shouldInsertSlash) {
    keepEditorFocusNotifier.increase();
    await editorState.insertTextAtPosition('/', position: selection.start);
  }

  // show the slash menu

  final context = editorState.getNodeAtPath(selection.start.path)?.context;
  if (context != null && context.mounted) {
    _selectionMenuService = SelectionMenu(
      context: context,
      editorState: editorState,
      selectionMenuItems: items,
      deleteSlashByDefault: shouldInsertSlash,
      deleteKeywordsByDefault: deleteKeywordsByDefault,
      singleColumn: singleColumn,
      style: style,
      // PREVON PATCH 12: hand the menu the exact position of the `/` it (or its
      // caller) inserted, so a dismiss-without-selection can clean it up.
      // Null makes the cleanup a no-op for callers that do not insert one.
      insertedSlashPath: shouldInsertSlash ? anchorPath : null,
      insertedSlashOffset: shouldInsertSlash ? anchorOffset : null,
    );
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      _selectionMenuService?.show();
    } else {
      await _selectionMenuService?.show();
    }
  }

  if (shouldInsertSlash) {
    WidgetsBinding.instance.addPostFrameCallback(
      (timeStamp) => keepEditorFocusNotifier.decrease(),
    );
  }

  return true;
}

bool _isSupportSlashMenuNode(
  Node node,
  Set<String> supportSlashMenuNodeWhiteList,
) {
  // Check if current node type is supported
  if (!supportSlashMenuNodeWhiteList.contains(node.type)) {
    return false;
  }

  // If node has a parent and level > 1, recursively check parent nodes
  if (node.level > 1 && node.parent != null) {
    return _isSupportSlashMenuNode(
      node.parent!,
      supportSlashMenuNodeWhiteList,
    );
  }

  return true;
}
