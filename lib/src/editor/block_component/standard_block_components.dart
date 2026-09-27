import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/heading_block_component/heading_command_shortcut.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const standardBlockComponentConfiguration = BlockComponentConfiguration();

// PREVON PATCH 13: fresh builder instances per call.
//
// `standardBlockComponentBuilderMap`'s values are shared global singletons.
// A host that wires per-host action affordances (the note editor and the
// full-page scratchpad set `showActions` + `actionBuilder` on every builder)
// must not mutate those singletons in place: the mutation leaks to every
// other host that captured the same instance — including a host that
// deliberately opted out (`showActions == false`), whose false branch never
// writes and so cannot reset what a true host already wrote. Returning a
// fresh map here gives each host its own builders; the global below remains
// for callers that want the shared default map (e.g. `AppFlowyEditor`'s own
// fallback).
Map<String, BlockComponentBuilder> buildStandardBlockComponentBuilderMap() => {
      PageBlockKeys.type: PageBlockComponentBuilder(),
      ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          placeholderText: (_) => PlatformExtension.isDesktopOrWeb
              ? AppFlowyEditorL10n.current.slashPlaceHolder
              : ' ',
        ),
      ),
      TodoListBlockKeys.type: TodoListBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          placeholderText: (_) => AppFlowyEditorL10n.current.toDoPlaceholder,
        ),
        toggleChildrenTriggers: [
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.shiftRight,
        ],
      ),
      BulletedListBlockKeys.type: BulletedListBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          placeholderText: (_) =>
              AppFlowyEditorL10n.current.listItemPlaceholder,
        ),
      ),
      NumberedListBlockKeys.type: NumberedListBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          placeholderText: (_) =>
              AppFlowyEditorL10n.current.listItemPlaceholder,
        ),
      ),
      QuoteBlockKeys.type: QuoteBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          placeholderText: (_) => AppFlowyEditorL10n.current.quote,
        ),
      ),
      HeadingBlockKeys.type: HeadingBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          placeholderText: (node) =>
              'Heading ${node.attributes[HeadingBlockKeys.level]}',
        ),
      ),
      ImageBlockKeys.type: ImageBlockComponentBuilder(),
      DividerBlockKeys.type: DividerBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          padding: (node) => const EdgeInsets.symmetric(vertical: 8.0),
        ),
      ),
      TableBlockKeys.type: TableBlockComponentBuilder(),
      TableCellBlockKeys.type: TableCellBlockComponentBuilder(),
    };

final Map<String, BlockComponentBuilder> standardBlockComponentBuilderMap =
    buildStandardBlockComponentBuilderMap();

final List<CharacterShortcutEvent> standardCharacterShortcutEvents = [
  // '\n'
  insertNewLineAfterBulletedList,
  insertNewLineAfterTodoList,
  insertNewLineAfterNumberedList,
  insertNewLineAfterHeading,
  insertNewLine,

  // bulleted list
  formatAsteriskToBulletedList,
  formatMinusToBulletedList,

  // numbered list
  formatNumberToNumberedList,

  // quote
  formatDoubleQuoteToQuote,

  // heading
  formatSignToHeading,

  // checkbox
  // format unchecked box, [] or -[]
  formatEmptyBracketsToUncheckedBox,
  formatHyphenEmptyBracketsToUncheckedBox,

  // format checked box, [x] or -[x]
  formatFilledBracketsToCheckedBox,
  formatHyphenFilledBracketsToCheckedBox,

  // slash
  slashCommand,

  // divider
  convertMinusesToDivider,
  convertStarsToDivider,
  convertUnderscoreToDivider,

  // markdown syntax
  ...markdownSyntaxShortcutEvents,

  // convert => to arrow
  formatGreaterEqual,
];

final List<CommandShortcutEvent> standardCommandShortcutEvents = [
  // undo, redo
  undoCommand,
  redoCommand,

  // backspace
  convertToParagraphCommand,
  ...tableCommands,
  backspaceCommand,
  deleteLeftWordCommand,
  deleteLeftSentenceCommand,

  //delete
  deleteCommand,
  deleteRightWordCommand,

  // arrow keys
  ...arrowLeftKeys,
  ...arrowRightKeys,
  ...arrowUpKeys,
  ...arrowDownKeys,

  //
  homeCommand,
  endCommand,

  //
  toggleTodoListCommand,
  ...toggleMarkdownCommands,
  ...toggleHeadingCommands,
  toggleHighlightCommand,
  showLinkMenuCommand,
  openInlineLinkCommand,
  openLinksCommand,

  //
  indentCommand,
  outdentCommand,

  //
  exitEditingCommand,

  //
  pageUpCommand,
  pageDownCommand,

  //
  selectAllCommand,

  // copy paste and cut
  copyCommand,
  ...pasteCommands,
  cutCommand,
];
