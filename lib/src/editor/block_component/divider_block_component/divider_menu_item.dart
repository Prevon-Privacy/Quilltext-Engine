import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';

SelectionMenuItem dividerMenuItem = SelectionMenuItem(
  getName: () => AppFlowyEditorL10n.current.divider,
  icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
    icon: Icons.horizontal_rule,
    isSelected: isSelected,
    style: style,
  ),
  keywords: ['horizontal rule', 'divider'],
  handler: (editorState, _, __) => insertDividerAtCaret(editorState),
);

/// Inserts a divider (plus a paragraph after it) at the collapsed caret. An
/// empty current block is replaced; otherwise the divider goes after it. No-op
/// without a collapsed caret on a text node. Shared by [dividerMenuItem] and
/// the app toolbar so both entry points behave identically.
void insertDividerAtCaret(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return;
  }
  final path = selection.end.path;
  final node = editorState.getNodeAtPath(path);
  final delta = node?.delta;
  if (node == null || delta == null) {
    return;
  }
  final insertedPath = delta.isEmpty ? path : path.next;
  final transaction = editorState.transaction
    ..insertNode(insertedPath, dividerNode())
    ..insertNode(insertedPath, paragraphNode())
    ..afterSelection = Selection.collapsed(Position(path: insertedPath.next));
  editorState.apply(transaction);
}
