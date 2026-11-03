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
  CollapsibleBlockKeys.type,
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
  String? searchHint,
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
      searchHint: searchHint,
    ),
  );
}

SelectionMenuService? _selectionMenuService;

/// What it takes to bring the slash menu back in one editor (see
/// [reopenSlashMenuIfTyping]): the items and node types of the slash command
/// that last fired THERE. Keyed by editor so an editor with no slash command
/// (a title, a comment box) never grows a menu.
class _SlashReopen {
  _SlashReopen(this.items, this.nodeTypes, this.show);
  final List<SelectionMenuItem> items;
  final Set<String> nodeTypes;
  final Future<bool> Function(EditorState editorState) show;
}

final Expando<_SlashReopen> _slashReopenByEditor = Expando<_SlashReopen>();

/// Brings the slash menu back when the caret sits right after a `/word` that
/// starts a block or follows whitespace and no menu is open. Call after a
/// deletion: deleting back into `/b` (e.g. after leaving the line and
/// returning) must show the menu again, exactly as typing it would.
Future<void> reopenSlashMenuIfTyping(EditorState editorState) async {
  final reopen = _slashReopenByEditor[editorState];
  if (reopen == null) return;
  final service = _selectionMenuService;
  if (service is SelectionMenu && service.isShowing) return;
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) return;
  final node = editorState.getNodeAtPath(selection.start.path);
  final text = node?.delta?.toPlainText();
  if (node == null ||
      text == null ||
      !_isSupportSlashMenuNode(node, reopen.nodeTypes)) {
    return;
  }
  final caret = selection.start.offset;
  if (caret > text.length) return;
  final slash = findSlashTrigger(text, caret);
  if (slash < 0) return;
  // Only when the letters still name a command, so ordinary words that start
  // with a `/` do not make the menu flicker open and shut.
  final query = text.substring(slash + 1, caret).toLowerCase();
  if (query.isNotEmpty &&
      !reopen.items.any(
        (i) => i.allKeywords.any((k) => k.toLowerCase().contains(query)),
      ) &&
      (selectionMenuRanker?.call(query, reopen.items).isEmpty ?? true)) {
    return;
  }
  await reopen.show(editorState);
}

/// Offset of the `/` that starts the command word ending at [caret], or -1
/// when the text before the caret is not a `/word` at a block start or after
/// whitespace.
int findSlashTrigger(String text, int caret) {
  for (var i = caret - 1; i >= 0; i--) {
    final c = text[i];
    if (c == '/') {
      if (i == 0) return i;
      final before = text[i - 1];
      return (before == ' ' || before == '\n' || before == '\t') ? i : -1;
    }
    if (c == ' ' || c == '\n' || c == '\t') return -1;
  }
  return -1;
}

Future<bool> _showSlashMenu(
  EditorState editorState,
  List<SelectionMenuItem> items, {
  bool shouldInsertSlash = true,
  bool singleColumn = true,
  bool deleteKeywordsByDefault = false,
  SelectionMenuStyle style = SelectionMenuStyle.light,
  Set<String> supportSlashMenuNodeTypes = _defaultSupportSlashMenuNodeTypes,
  String? searchHint,
  bool reopen = false,
}) async {
  _slashReopenByEditor[editorState] = _SlashReopen(
    items,
    supportSlashMenuNodeTypes,
    (state) => _showSlashMenu(
      state,
      items,
      shouldInsertSlash: shouldInsertSlash,
      singleColumn: singleColumn,
      deleteKeywordsByDefault: deleteKeywordsByDefault,
      style: style,
      supportSlashMenuNodeTypes: supportSlashMenuNodeTypes,
      searchHint: searchHint,
      reopen: true,
    ),
  );
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
  if (reopen) {
    // The `/word` is already in the text: no trigger gate, nothing to insert.
    final context = node.context;
    if (context == null || !context.mounted) return false;
    _selectionMenuService = SelectionMenu(
      context: context,
      editorState: editorState,
      selectionMenuItems: items,
      deleteSlashByDefault: true,
      deleteKeywordsByDefault: deleteKeywordsByDefault,
      singleColumn: singleColumn,
      style: style,
      searchHint: searchHint,
    );
    await _selectionMenuService?.show();
    return true;
  }
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
      searchHint: searchHint,
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
