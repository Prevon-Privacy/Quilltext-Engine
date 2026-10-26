import 'dart:async';
import 'dart:math';

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

/// PREVON PATCH 18 — lets the host rank the slash menu with its own search
/// (typos, plurals, word order) instead of the built-in substring match. Given
/// the trimmed lower-case [query] and every item, return the items that match,
/// best first. The menu shows those first, then any item the substring match
/// would also have shown, so nothing that used to match disappears. Null (the
/// default) keeps the upstream behaviour. Set once at app start.
typedef SelectionMenuRanker = List<SelectionMenuItem> Function(
  String query,
  List<SelectionMenuItem> items,
);
SelectionMenuRanker? selectionMenuRanker;

typedef SelectionMenuItemHandler = void Function(
  EditorState editorState,
  SelectionMenuService menuService,
  BuildContext context,
);

typedef SelectionMenuItemNameBuilder = Widget Function(
  String name,
  SelectionMenuStyle style,
  bool isSelected,
);

/// Selection Menu Item
class SelectionMenuItem {
  SelectionMenuItem({
    required String Function() getName,
    required this.icon,
    required this.keywords,
    required SelectionMenuItemHandler handler,
    this.nameBuilder,
    this.deleteKeywords = false,
    this.deleteSlash = true,
  }) : _getName = getName {
    this.handler = (editorState, menuService, context) {
      if (deleteSlash || deleteKeywords) {
        _deleteSlash(editorState);
      }

      handler(editorState, menuService, context);
      onSelected?.call();
    };
  }

  final String Function() _getName;
  final Widget Function(
    EditorState editorState,
    bool onSelected,
    SelectionMenuStyle style,
  ) icon;
  final SelectionMenuItemNameBuilder? nameBuilder;

  String get name => _getName();

  /// Customizes keywords for item.
  ///
  /// The keywords are used to quickly retrieve items.
  final List<String> keywords;
  List<String> get allKeywords => keywords + [name.toLowerCase()];
  late final SelectionMenuItemHandler handler;

  VoidCallback? onSelected;

  bool deleteSlash;
  bool deleteKeywords;

  void _deleteSlash(EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final node = editorState.getNodeAtPath(selection.end.path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return;
    }
    final end = selection.start.offset;
    int deletedIndex = 0;

    if (deleteKeywords) {
      deletedIndex = 0;
    } else if (deleteSlash) {
      deletedIndex = delta.toPlainText().substring(0, end).lastIndexOf('/');
    }

    // delete all the texts after '/' along with '/'
    final transaction = editorState.transaction
      ..deleteText(
        node,
        deletedIndex,
        end - deletedIndex,
      );

    editorState.apply(transaction);
  }

  /// Creates a selection menu entry for inserting a [Node].
  /// [getName] and [iconData] define the appearance within the selection menu.
  ///
  /// The insert position is determined by the result of [replace] and
  /// [insertBefore]
  /// If no values are provided for [replace] and [insertBefore] the node is
  /// inserted after the current selection.
  /// [replace] takes precedence over [insertBefore]
  ///
  /// [updateSelection] can be used to update the selection after the node
  /// has been inserted.
  factory SelectionMenuItem.node({
    required String Function() getName,
    required List<String> keywords,
    required Node Function(EditorState editorState, BuildContext context)
        nodeBuilder,
    IconData? iconData,
    Widget Function(
      EditorState editorState,
      bool onSelected,
      SelectionMenuStyle style,
    )? iconBuilder,
    SelectionMenuItemNameBuilder? nameBuilder,
    bool Function(EditorState editorState, Node node)? insertBefore,
    bool Function(EditorState editorState, Node node)? replace,
    Selection? Function(
      EditorState editorState,
      Path insertPath,
      bool replaced,
      bool insertedBefore,
    )? updateSelection,
  }) {
    // the iconData and iconBuilder are mutually exclusive
    assert(iconData == null || iconBuilder == null);
    assert(iconData != null || iconBuilder != null);

    return SelectionMenuItem(
      getName: getName,
      nameBuilder: nameBuilder,
      icon: (editorState, onSelected, style) {
        if (iconData != null) {
          return Icon(
            iconData,
            color: onSelected
                ? style.selectionMenuItemSelectedIconColor
                : style.selectionMenuItemIconColor,
            size: 14.0,
          );
        } else if (iconBuilder != null) {
          return iconBuilder.call(editorState, onSelected, style);
        }

        return const SizedBox.shrink();
      },
      keywords: keywords,
      handler: (editorState, _, context) {
        final selection = editorState.selection;
        if (selection == null || !selection.isCollapsed) {
          return;
        }
        final node = editorState.getNodeAtPath(selection.end.path);
        final delta = node?.delta;
        if (node == null || delta == null) {
          return;
        }
        final newNode = nodeBuilder(editorState, context);
        final transaction = editorState.transaction;
        final bReplace = replace?.call(editorState, node) ?? false;
        final bInsertBefore = insertBefore?.call(editorState, node) ?? false;

        //default insert after
        var path = node.path.next;
        if (bReplace) {
          path = node.path;
        } else if (bInsertBefore) {
          path = node.path;
        }

        transaction
          ..insertNode(path, newNode)
          ..afterSelection = updateSelection?.call(
                editorState,
                path,
                bReplace,
                bInsertBefore,
              ) ??
              selection;

        if (bReplace) {
          transaction.deleteNode(node);
        }

        editorState.apply(transaction);
      },
    );
  }
}

class SelectionMenuStyle {
  const SelectionMenuStyle({
    required this.selectionMenuBackgroundColor,
    required this.selectionMenuItemTextColor,
    required this.selectionMenuItemIconColor,
    required this.selectionMenuItemSelectedTextColor,
    required this.selectionMenuItemSelectedIconColor,
    required this.selectionMenuItemSelectedColor,
    required this.selectionMenuItemHoverColor,
    required this.selectionMenuUnselectedLabelColor,
    required this.selectionMenuDividerColor,
    required this.selectionMenuLinkBorderColor,
    required this.selectionMenuInvalidLinkColor,
    required this.selectionMenuButtonColor,
    required this.selectionMenuButtonTextColor,
    required this.selectionMenuButtonIconColor,
    required this.selectionMenuButtonBorderColor,
    required this.selectionMenuTabIndicatorColor,
  });

  static const light = SelectionMenuStyle(
    selectionMenuBackgroundColor: Color(0xFFFFFFFF),
    selectionMenuItemTextColor: Color(0xFF333333),
    selectionMenuItemIconColor: Color(0xFF333333),
    selectionMenuItemSelectedTextColor: Color.fromARGB(255, 56, 91, 247),
    selectionMenuItemSelectedIconColor: Color.fromARGB(255, 56, 91, 247),
    selectionMenuItemSelectedColor: Color(0xFFE0F8FF),
    selectionMenuItemHoverColor: Color(0xFFF1F4F7),
    selectionMenuUnselectedLabelColor: Color(0xFF333333),
    selectionMenuDividerColor: Color(0xFF00BCF0),
    selectionMenuLinkBorderColor: Color(0xFF00BCF0),
    selectionMenuInvalidLinkColor: Color(0xFFE53935),
    selectionMenuButtonColor: Color(0xFF00BCF0),
    selectionMenuButtonTextColor: Color(0xFF333333),
    selectionMenuButtonIconColor: Color(0xFF333333),
    selectionMenuButtonBorderColor: Color(0xFF00BCF0),
    selectionMenuTabIndicatorColor: Color(0xFF00BCF0),
  );

  static const dark = SelectionMenuStyle(
    selectionMenuBackgroundColor: Color(0xFF282E3A),
    selectionMenuItemTextColor: Color(0xFFBBC3CD),
    selectionMenuItemIconColor: Color(0xFFBBC3CD),
    selectionMenuItemSelectedTextColor: Color(0xFF131720),
    selectionMenuItemSelectedIconColor: Color(0xFF131720),
    selectionMenuItemSelectedColor: Color(0xFF00BCF0),
    selectionMenuItemHoverColor: Color(0xFF2A2F36),
    selectionMenuUnselectedLabelColor: Color(0xFFBBC3CD),
    selectionMenuDividerColor: Color(0xFF3A3F44),
    selectionMenuLinkBorderColor: Color(0xFF3A3F44),
    selectionMenuInvalidLinkColor: Color(0xFFE53935),
    selectionMenuButtonColor: Color(0xFF00BCF0),
    selectionMenuButtonTextColor: Color(0xFFFFFFFF),
    selectionMenuButtonIconColor: Color(0xFFFFFFFF),
    selectionMenuButtonBorderColor: Color(0xFF00BCF0),
    selectionMenuTabIndicatorColor: Color(0xFF00BCF0),
  );

  final Color selectionMenuBackgroundColor;
  final Color selectionMenuItemTextColor;
  final Color selectionMenuItemIconColor;
  final Color selectionMenuItemSelectedTextColor;
  final Color selectionMenuItemSelectedIconColor;
  final Color selectionMenuItemSelectedColor;
  final Color selectionMenuItemHoverColor;
  final Color selectionMenuUnselectedLabelColor;
  final Color selectionMenuDividerColor;
  final Color selectionMenuLinkBorderColor;
  final Color selectionMenuInvalidLinkColor;
  final Color selectionMenuButtonColor;
  final Color selectionMenuButtonTextColor;
  final Color selectionMenuButtonIconColor;
  final Color selectionMenuButtonBorderColor;
  final Color selectionMenuTabIndicatorColor;
}

class SelectionMenuWidget extends StatefulWidget {
  const SelectionMenuWidget({
    super.key,
    required this.items,
    required this.maxItemInRow,
    required this.editorState,
    required this.menuService,
    required this.onExit,
    required this.onSelectionUpdate,
    required this.selectionMenuStyle,
    required this.itemCountFilter,
    required this.deleteSlashByDefault,
    this.singleColumn = false,
    this.nameBuilder,
    // PREVON PATCH 11: caller-supplied fit constraints for the single-column
    // (mobile slash) layout. Defaults preserve the pre-patch 300 cap.
    this.maxHeight = 300,
    this.minRowHeight = 0,
    this.availableWidth,
  });

  final List<SelectionMenuItem> items;
  final int itemCountFilter;
  final int maxItemInRow;

  /// PREVON PATCH 11: upper bound for the single-column menu height. Rows that
  /// fit render at natural height (ListView shrinkWrap); excess scrolls.
  final double maxHeight;

  /// PREVON PATCH 11: per-row minimum height so touch platforms get a tappable
  /// 44px row. `0` means no floor (desktop).
  final double minRowHeight;

  /// PREVON PATCH 11: width actually available on screen. When non-null the
  /// menu width is `min(300, availableWidth)`, preventing overflow on narrow
  /// screens.
  final double? availableWidth;

  final SelectionMenuService menuService;
  final EditorState editorState;

  final VoidCallback onSelectionUpdate;
  final VoidCallback onExit;

  final SelectionMenuStyle selectionMenuStyle;

  final bool deleteSlashByDefault;
  final bool singleColumn;

  final SelectionMenuItemNameBuilder? nameBuilder;

  @override
  State<SelectionMenuWidget> createState() => _SelectionMenuWidgetState();
}

class _SelectionMenuWidgetState extends State<SelectionMenuWidget>
    implements AppFlowyKeyboardServiceInterceptor {
  final _focusNode = FocusNode(debugLabel: 'popup_list_widget');

  bool get _touch =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  int _selectedIndex = 0;
  List<SelectionMenuItem> _showingItems = [];
  AutoScrollController? _scrollController;

  int _searchCounter = 0;
  StreamSubscription<EditorTransactionValue>? _txSub;
  AppFlowyKeyboardService? _keyboardService;

  /// Offset of the trigger `/` in the caret's node (-1 when unknown).
  int _slashOffset = -1;

  String _keyword = '';
  String get keyword => _keyword;

  /// Re-derives the search keyword from the document (text between the
  /// trigger `/` and the caret) so filtering stays correct no matter how the
  /// characters arrived (menu key handler, IME, paste).
  void _syncKeywordFromDocument() {
    if (!mounted || _slashOffset < 0) {
      return;
    }
    final selection = widget.editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final text = widget.editorState
        .getNodeAtPath(selection.end.path)
        ?.delta
        ?.toPlainText();
    final caret = selection.end.offset;
    if (text == null || caret > text.length) {
      return;
    }
    if (caret <= _slashOffset || text[_slashOffset] != '/') {
      // The `/` was deleted (soft-keyboard backspace): close the menu.
      widget.onExit();
      return;
    }
    final next = text.substring(_slashOffset + 1, caret);
    if (next != _keyword) {
      _applyKeyword(next);
    }
  }

  void _applyKeyword(String newKeyword) {
    final previous = _keyword;
    _keyword = newKeyword;
    final query = newKeyword.trim().toLowerCase();

    final substring = widget.items
        .where(
          (item) =>
              query.isEmpty ||
              item.allKeywords.any((k) => k.toLowerCase().contains(query)),
        )
        .toList(growable: false);
    // PREVON PATCH 18: host ranking first, then what the substring match found.
    final ranker = selectionMenuRanker;
    final List<SelectionMenuItem> items;
    if (ranker == null || query.isEmpty) {
      items = substring;
    } else {
      final ranked = ranker(query, widget.items);
      final seen = ranked.toSet();
      items = <SelectionMenuItem>[
        ...ranked,
        for (final item in substring)
          if (!seen.contains(item)) item,
      ];
    }

    if (items.isEmpty) {
      _searchCounter++;
      // Two consecutive characters without a match: the user is not
      // searching for a command any more, close the menu.
      if (newKeyword.length > previous.length &&
          _searchCounter >= 2 &&
          !(widget.deleteSlashByDefault && newKeyword.length < 2)) {
        widget.onExit();
        return;
      }
    } else {
      _searchCounter = 0;
    }
    setState(() {
      _showingItems = items;
      _selectedIndex = 0;
    });
    _scrollToSelectedIndex();
  }

  @override
  void initState() {
    super.initState();

    _showingItems = widget.items;
    final sel = widget.editorState.selection;
    if (sel != null && sel.isCollapsed && sel.end.offset > 0) {
      final t =
          widget.editorState.getNodeAtPath(sel.end.path)?.delta?.toPlainText();
      if (t != null &&
          sel.end.offset <= t.length &&
          t[sel.end.offset - 1] == '/') {
        _slashOffset = sel.end.offset - 1;
      }
    }
    _txSub = widget.editorState.transactionStream.listen(
      // The stream fires before the transaction's `afterSelection` lands, so
      // read the caret one microtask later.
      (_) => scheduleMicrotask(_syncKeywordFromDocument),
    );
    if (widget.singleColumn) {
      _scrollController = AutoScrollController();
    }

    // PREVON PATCH 16: Enter must pick the highlighted row on EVERY input path.
    // A hardware Enter reaches `_onKeyEvent`, but a soft keyboard (and some
    // desktop IMEs) deliver Enter through the text-input channel as a "\n"
    // insertion or a `performAction`, which the editor would otherwise turn
    // into a new line and leave the menu open.
    _keyboardService = widget.editorState.service.keyboardService;
    _keyboardService?.registerInterceptor(this);

    keepEditorFocusNotifier.increase();
    // Touch: leave focus with the editor so its IME (soft keyboard) keeps
    // delivering the typed search text.
    if (!_touch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _keyboardService?.unregisterInterceptor(this);
    _keyboardService = null;
    _txSub?.cancel();
    _focusNode.dispose();
    keepEditorFocusNotifier.decrease();
    _scrollController?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.selectionMenuStyle.selectionMenuBackgroundColor,
          border: Border.all(
            color: widget.selectionMenuStyle.selectionMenuDividerColor,
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 24,
              offset: const Offset(0, 8),
              color: Colors.black.withValues(alpha: 0.28),
            ),
          ],
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: _showingItems.isEmpty
            ? _buildNoResultsWidget(context)
            : _buildResultsWidget(
                context,
                _showingItems,
                widget.itemCountFilter,
                _selectedIndex,
              ),
      ),
    );
  }

  void _scrollToSelectedIndex() {
    if (_scrollController == null) {
      return;
    }

    _scrollController?.scrollToIndex(
      _selectedIndex,
      preferPosition: AutoScrollPosition.middle,
    );
  }

  Widget _buildResultsWidget(
    BuildContext buildContext,
    List<SelectionMenuItem> items,
    int itemCountFilter,
    int selectedIndex,
  ) {
    if (widget.singleColumn) {
      // PREVON PATCH 11: the menu width follows the space actually available
      // on screen (`min(300, availableWidth)`) and every row gets the
      // caller-supplied minimum height so touch platforms are tappable. The
      // concrete width is shared by minWidth and maxWidth so the box is a
      // fixed measure that still cannot exceed the viewport.
      final menuWidth = widget.availableWidth == null
          ? 300.0
          : min(300.0, widget.availableWidth!);
      List<Widget> itemWidgets = [];
      for (var i = 0; i < items.length; i++) {
        itemWidgets.add(
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: widget.minRowHeight),
            child: AutoScrollTag(
              key: ValueKey(i),
              index: i,
              controller: _scrollController!,
              child: SelectionMenuItemWidget(
                item: items[i],
                isSelected: selectedIndex == i,
                editorState: widget.editorState,
                menuService: widget.menuService,
                selectionMenuStyle: widget.selectionMenuStyle,
              ),
            ),
          ),
        );
      }
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: widget.maxHeight,
          minWidth: menuWidth,
          maxWidth: menuWidth,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          controller: _scrollController,
          children: itemWidgets,
        ),
      );
    } else {
      List<Widget> columns = [];
      List<Widget> itemWidgets = [];
      // apply item count filter
      if (itemCountFilter > 0) {
        items = items.take(itemCountFilter).toList();
      }

      for (var i = 0; i < items.length; i++) {
        if (i != 0 && i % (widget.maxItemInRow) == 0) {
          columns.add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: itemWidgets,
            ),
          );
          itemWidgets = [];
        }
        itemWidgets.add(
          SelectionMenuItemWidget(
            item: items[i],
            isSelected: selectedIndex == i,
            editorState: widget.editorState,
            menuService: widget.menuService,
            selectionMenuStyle: widget.selectionMenuStyle,
          ),
        );
      }
      if (itemWidgets.isNotEmpty) {
        columns.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: itemWidgets,
          ),
        );
        itemWidgets = [];
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columns,
      );
    }
  }

  Widget _buildNoResultsWidget(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: SizedBox(
        width: 180,
        child: Text(
          AppFlowyEditorL10n.current.noFindResult,
          style: TextStyle(
            fontSize: 12.5,
            decoration: TextDecoration.none,
            fontWeight: FontWeight.w400,
            color: widget.selectionMenuStyle.selectionMenuUnselectedLabelColor,
          ),
        ),
      ),
    );
  }

  /// Handles arrow keys to switch selected items
  /// Handles keyword searches
  /// Handles enter to select item and esc to exit
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    AppFlowyEditorLog.keyboard.debug('slash command, on key $event');

    if (event is KeyRepeatEvent) {
      return KeyEventResult.skipRemainingHandlers;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final arrowKeys = [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ];

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      // Always consume Enter while the menu is open: with no match it must not
      // fall through to the editor and split the line under the menu.
      _selectHighlighted();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onExit();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (keyword.isEmpty) {
        // dismiss() removes the untouched trigger `/` itself.
        widget.onExit();
        return KeyEventResult.handled;
      }
      _deleteLastCharacters();
      return KeyEventResult.handled;
    } else if (event.character != null &&
        event.character!.isNotEmpty &&
        event.character!.codeUnitAt(0) >= 0x20 &&
        event.character!.codeUnitAt(0) != 0x7f &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !arrowKeys.contains(event.logicalKey) &&
        event.logicalKey != LogicalKeyboardKey.tab) {
      _insertText(event.character!);
      return KeyEventResult.handled;
    }

    var newSelectedIndex = _selectedIndex;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      // When going left, wrap to the end of the previous row
      newSelectedIndex -= widget.maxItemInRow;
      if (newSelectedIndex < 0) {
        // Calculate the last row's starting position
        final lastRowStart = (_showingItems.length - 1) -
            ((_showingItems.length - 1) % widget.maxItemInRow);
        // Move to the same column in the last row
        newSelectedIndex =
            lastRowStart + (_selectedIndex % widget.maxItemInRow);
        if (newSelectedIndex >= _showingItems.length) {
          newSelectedIndex = _showingItems.length - 1;
        }
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      // When going right, wrap to the start of the next row
      newSelectedIndex += widget.maxItemInRow;
      if (newSelectedIndex >= _showingItems.length) {
        newSelectedIndex = _selectedIndex % widget.maxItemInRow;
        if (newSelectedIndex >= _showingItems.length) {
          newSelectedIndex = _showingItems.length - 1;
        }
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (newSelectedIndex > 0) {
        newSelectedIndex -= 1;
      } else {
        // Wrap to the last item
        newSelectedIndex = _showingItems.length - 1;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (newSelectedIndex < _showingItems.length - 1) {
        newSelectedIndex += 1;
      } else {
        // Wrap to the first item
        newSelectedIndex = 0;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.tab) {
      newSelectedIndex += 1;
      if (newSelectedIndex >= _showingItems.length) {
        newSelectedIndex = 0;
      }
    }

    if (newSelectedIndex != _selectedIndex) {
      setState(() {
        _selectedIndex = newSelectedIndex.clamp(0, _showingItems.length - 1);
        _scrollToSelectedIndex();
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Runs the highlighted row's handler. Returns false when nothing is
  /// highlighted (empty result list).
  bool _selectHighlighted() {
    if (_selectedIndex < 0 || _selectedIndex >= _showingItems.length) {
      return false;
    }
    _showingItems[_selectedIndex]
        .handler(widget.editorState, widget.menuService, context);
    return true;
  }

  bool _isNewlineText(String text) => text == '\n' || text == '\r\n';

  // --- AppFlowyKeyboardServiceInterceptor: Enter via the text-input channel.

  @override
  Future<bool> interceptInsert(
    TextEditingDeltaInsertion insertion,
    EditorState editorState,
    List<CharacterShortcutEvent> characterShortcutEvents,
  ) async {
    if (!_isNewlineText(insertion.textInserted)) {
      return false;
    }
    _selectHighlighted();
    return true;
  }

  @override
  Future<bool> interceptReplace(
    TextEditingDeltaReplacement replacement,
    EditorState editorState,
    List<CharacterShortcutEvent> characterShortcutEvents,
  ) async {
    // The text-diff may report "/q" -> "/q\n" as a replacement whose
    // replaced text is a prefix of the new text; the only addition is the
    // newline.
    final replaced = replacement.textReplaced;
    final added = replacement.replacementText;
    final onlyNewlineAdded = added.startsWith(replaced) &&
        _isNewlineText(added.substring(replaced.length));
    if (!_isNewlineText(added) && !onlyNewlineAdded) {
      return false;
    }
    _selectHighlighted();
    return true;
  }

  @override
  Future<bool> interceptPerformAction(
    TextInputAction action,
    EditorState editorState,
  ) async {
    switch (action) {
      case TextInputAction.newline:
      case TextInputAction.done:
      case TextInputAction.go:
      case TextInputAction.search:
      case TextInputAction.send:
      case TextInputAction.next:
        _selectHighlighted();
        return true;
      default:
        return false;
    }
  }

  @override
  Future<bool> interceptDelete(
    TextEditingDeltaDeletion deletion,
    EditorState editorState,
  ) async =>
      false;

  @override
  Future<bool> interceptNonTextUpdate(
    TextEditingDeltaNonTextUpdate nonTextUpdate,
    EditorState editorState,
    List<CharacterShortcutEvent> characterShortcutEvents,
  ) async =>
      false;

  @override
  Future<bool> interceptFloatingCursor(
    RawFloatingCursorPoint point,
    EditorState editorState,
  ) async =>
      false;

  void _deleteLastCharacters({int length = 1}) {
    final selection = widget.editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final node = widget.editorState.getNodeAtPath(selection.end.path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return;
    }

    widget.onSelectionUpdate();
    final transaction = widget.editorState.transaction
      ..deleteText(
        node,
        selection.start.offset - length,
        length,
      );
    widget.editorState.apply(transaction);
  }

  void _insertText(String text) {
    final selection = widget.editorState.selection;
    if (selection == null || !selection.isSingle) {
      return;
    }
    final node = widget.editorState.getNodeAtPath(selection.end.path);
    if (node == null) {
      return;
    }
    widget.onSelectionUpdate();
    final transaction = widget.editorState.transaction;
    transaction.insertText(
      node,
      selection.end.offset,
      text,
    );
    widget.editorState.apply(transaction);
  }
}
