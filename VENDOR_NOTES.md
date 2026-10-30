# Vendor Notes — prevon_quilltext_engine 6.2.0

## Original Package
- **Name:** appflowy_editor
- **Version:** 6.2.0
- **Source:** pub.dev

## License
This fork is distributed under the **MPL-2.0** half of AppFlowy Editor's dual
AGPL-3.0 / MPL-2.0 license (full text in `LICENSE`). That election is **confirmed** —
not an in-house interpretation — by AppFlowy's official licensing FAQ at
<https://docs.appflowy.io/docs/documentation/appflowy-editor/licenses>, which states that
the editor (referred to there simply as available under "the MPL") may be included in
commercially sold, closed-source software without triggering AGPL-3.0 obligations.
Confirmed as of 2026-09-25. See `README.md` → "Basis for MPL-2.0 election" for the full
note, including the caveat that the FAQ is a live page and should be re-checked if the
licensing posture is revisited.

## Reason for Vendoring
Three real incompatibilities with this app's environment:
- Flutter SDK: 3.44.7
- file_picker: 12.0.0

The upstream pub.dev release of appflowy_editor 6.2.0 relies on file_picker APIs that
were removed or changed in file_picker 12.0.0. These incompatibilities are upstream
bugs, not bugs in this app's code.

## Patches Applied

### Patch 1: file_picker_impl.dart — Static API Migration
**File:** `lib/src/editor/util/file_picker/file_picker_impl.dart`

**Problem:** The upstream code instantiated `FilePicker()` as a concrete object
(`final picker = FilePicker()`) and accessed `.platform.` as a synchronous property
on the instance. In file_picker 12.0.0, the `FilePicker()` constructor is removed
(non-instantiable) and `.platform.` is no longer a synchronous property.

**Fix:** Replaced all instance-based calls with static `fp.FilePicker.pickFiles(...)`,
`fp.FilePicker.getDirectoryPath(...)`, and `fp.FilePicker.saveFile(...)` calls.
The `saveFile` method is stubbed (returns null) because file_picker 12.0.0 requires
a `Uint8List bytes` parameter that the `FilePickerService` interface does not carry —
and no caller in the vendor library currently invokes `saveFile`, so the stub is safe.
Additionally: `fp.FilePicker.pickFiles(...)` returns `FilePickerResult?` (nullable), but
`FilePickerResult(files: List<PlatformFile>)` takes a non-nullable list. The fix passes
`result?.files ?? []` to handle the nullable cleanly on all file_picker versions.

### Patch 2: image_upload_widget.dart — use PlatformFile.bytes directly (readAsBytes unavailable)
**File:** `lib/src/editor/block_component/image_block_component/image_upload_widget.dart`

**Problem:** The upstream code assumed `PlatformFile.readAsBytes()` (async) was available
as an alternative to the synchronous `bytes` getter. In file_picker 11.x, `readAsBytes()`
does not exist on `PlatformFile` at all.

**Fix:** On web, use `file.bytes` (synchronous, non-nullable when `withData: true` is set
on the pick call — confirmed populated for all web platforms). The `withData: true` flag
is already set in the call above, so `bytes` is always populated for web picks.

### Patch 3: delta_input_service.dart — DeltaTextInputClient + TextInputClient Mixins
**File:** `lib/src/editor/editor_component/service/ime/delta_input_service.dart`

**Problem:** The upstream `DeltaTextInputService` class declared `with DeltaTextInputClient`
but omitted `TextInputClient` from the mixin list. Flutter 3.44.7 tightened the
interface requirements for `TextInputClient`, causing compilation errors.

**Fix:** Changed the class declaration from:
  `class DeltaTextInputService extends TextInputService with DeltaTextInputClient {`
to:
  `class DeltaTextInputService extends TextInputService with DeltaTextInputClient, TextInputClient {`
Both mixins are now in the `with` clause, satisfying the full interface contract.

### Patch 4: editor.dart — opt-in service-graph invalidation token (`serviceConfigKey`)
**File:** `lib/src/editor/editor_component/service/editor.dart`

**Problem (performance, not a crash):** `_AppFlowyEditorState` caches its internal
service-widget subtree (`services`, built by `_buildServices`) so the expensive
subtree is not rebuilt on every frame. Upstream's `didUpdateWidget` unconditionally
set `services = null`, which defeats the cache on *every* rebuild — i.e. every
`AppFlowyEditor` rebuild caused by anything on the host screen (word-count ticks,
focus changes, unrelated ancestor `setState`s), not just changes the editor actually
renders. On the note editor and scratchpad this is wasted work on every interaction.

**Fix:** Added an optional `Object? serviceConfigKey` constructor parameter (default
`null`). In `didUpdateWidget`, `services` is now invalidated only when:
  - the `EditorState` identity changed (`!identical(widget.editorState, oldWidget.editorState)`), or
  - `serviceConfigKey == null` (preserves the legacy always-rebuild behaviour for any
    caller that has not opted in), or
  - `serviceConfigKey != oldWidget.serviceConfigKey`.
Callers that opt in should pass a value whose identity changes if and only if one of
the props baked into the rendered service graph changes. The two in-app call sites
(the host app's note editor and scratchpad) pass a Dart record of those props. A
debug-only `debugAppFlowyEditorServiceBuildCount` counter (kDebugMode-gated) exists
solely to let tests observe whether `_buildServices` actually ran.

**Deviation type:** deliberate local extension, not an upstream-bug workaround. There
is no upstream issue to track; the upstream `didUpdateWidget` remains correct for
callers that change the service-rendered props wholesale. Do not "restore" the
unconditional `services = null` — that re-introduces the per-rebuild waste this patch
removes.

### Patch 14: shared touch reorder grip (`touch_reorder_handle.dart`)
**Files:** `lib/src/editor/block_component/base_component/touch_reorder_handle.dart` (new),
`base_component/block_hover_action.dart`, `todo_list_block_component/todo_list_block_component.dart`

**Problem (mobile):** the checklist grip and the generic block grip (bullets, numbered,
headings, quotes…) were two copies of the same widget: `SizedBox(18)` around
`OverflowBox(44)`. Flutter only hit-tests a child inside its parent's bounds, so the 44px
overflow never received touches (real target = the 18px glyph). The generic copy also never
called `TouchDragHandleGate.claim` (Patch 11), so on Android the document-wide pan recognizer
won the arena and the long-press drag never started. The app's checkbox additionally forced a
44px layout box, so the grip, checkbox and first text line had three different vertical centres.

**Fix:** one `TouchReorderHandle` — a real 28×24 box (first-line height, so it never grows a row),
opaque hit testing, Patch 11 gate, `LongPressDraggable`. Both call sites use it. The collapse
chevron is a real 24×24 box for the same reason.

**Also fixed under Patch 14 (found on a Pixel 2, not reproducible on a desktop test host):**
- `mobile_selection_service.dart` stubbed `renderDropTargetForOffset` / `removeDropTarget` /
  `getDropTargetRenderData` ("Do nothing on mobile" / `=> null`), so no drag-to-reorder could ever
  resolve a drop on a phone. Ported the desktop implementation (same drop indicator).
- `block_component_action_wrapper.dart`: on touch the gutter is persistent; ending a drag set
  `alwaysShowActions = false` and hid the grip permanently.
- `TouchReorderHandle` treats `onDraggableCanceled` as the drop as well (Flutter reports every
  drop without a `DragTarget` as cancelled, and skips `onDragEnd` if the State unmounted mid-drag).
- Swipe the grip right = indent, left = outdent (`indent_block_node.dart`, selection-free, no depth cap).

- **Indent / outdent everywhere.** `indent_block_node.dart` holds the shared rules: every grip block type
  (`movableBlockTypes`) can be indented under a previous *container* sibling (paragraph / bulleted / numbered /
  to-do — the only components that render children), depth is limited by **width**, not a count
  (`indentWouldFit`: the row must keep `kMinIndentedRowWidth` = 170dp after the extra `indentPadding` step), and
  wrapped text stays inside the indent because children render in a narrower padded column. Triggers: one-finger
  swipe on the grip, **two-finger horizontal swipe anywhere on a row** (`two_finger_indent_detector.dart`; one
  finger over text is the Android caret-drag gesture, so `GateAwarePanGestureRecognizer` rejects itself when a
  second finger lands), Tab / Shift+Tab, and Ctrl/Cmd+] / [ (`indentBracketCommand` / `outdentBracketCommand`).
  Device-tested on a phone (gesture arbitration against the platform text-selection recognizers).
- **Slash menu.** `SelectionMenu` holds `keepEditorFocusNotifier` for its whole life (the keyboard service closes
  the soft keyboard on any focus loss the notifier doesn't cover; the slash command only held it one frame),
  draws an optional grey `searchHint` ghost right after the `/` until a filter character is typed, and the plain
  "Text" item is exported as `textSelectionMenuItem` so a host can drop it by identity.
  PATCH 16: Enter picks the highlighted row on every input path — hardware Enter / numpad Enter in
  `_onKeyEvent`, and a keyboard-service interceptor for soft-keyboard / IME Enter (a `"\n"` insertion,
  a `"/q" -> "/q\n"` replacement, or `performAction(newline|done|go|search|send|next)`). Tests in
  `test/editor/selection_menu/slash_menu_search_test.dart`.

Regression tests: `test/editor/block_component/touch_reorder_test.dart`. NOTE: those run on a
desktop host, so they exercise the desktop selection service — the mobile drop-target path is
only verifiable on a phone/emulator.

### Patch 15: invisible grip overlay, one-finger indent swipe, table fit, slash-menu search
**Files:** `touch_reorder_handle.dart`, `block_component_action_wrapper.dart`,
`block_hover_action.dart`, `todo_list_block_component.dart`, `two_finger_indent_detector.dart`,
`touch_drag_gate.dart`, `table_block_component/*`, `selection_menu/selection_menu_widget.dart`,
`selection_menu/selection_menu_item_widget.dart`

- **Touch grip is an invisible overlay** (`TouchReorderHandle(invisible: true)`, 36x30) stacked over
  the row's own bullet / checkbox by `BlockComponentActionWrapper` (no gutter), hit-test translucent
  so a tap still reaches the marker underneath. Grip glyph 28->20px wide / 18->16px; desktop gutter
  36->22px. The touch collapse chevron was dropped with the gutter. The todo inline touch grip was removed.
- **One-finger indent swipe** (`TwoFingerIndentDetector`): a horizontal swipe on a movable row indents /
  outdents when the caret is NOT in that row, when the row is EMPTY (swipe anywhere, caret or not), or when
  it starts in the 32px left/right edge zone. A non-empty caret row keeps caret-drag. The selection is
  remapped through the move so the caret stays on the moved row. A swipe that starts on the grip (marker) counts as edge; the grip's own
  horizontal recognizer is off on touch (`onIndent`/`onOutdent` unset) so the two never compete. Rows
  inside a table cell are skipped. First level at 24px, then one more per 40px. Uses `TouchDragHandleGate.claimPan` (pan recognizer only, so tap and
  long-press still work).
- **Tables fit the width:** `TableFitScope` scales column widths at render time (stored widths untouched,
  floor 0.3, scroll view remains the fallback).
- **Slash menu:** search text is derived from the document (`/` to caret) instead of key events only;
  selection resets to the first hit; backspace on an empty query no longer eats the char before `/`;
  restyled rows/card.

Tests: `test/editor/block_component/{touch_reorder,one_finger_indent,table_fit}_test.dart`,
`test/editor/selection_menu/slash_menu_search_test.dart`. Mobile-only paths are unverified on a real
phone at the time of writing.

### Patch 17: every block is draggable from its left edge (touch)
**Files:** `touch_reorder_handle.dart` (`touchGripLayoutFor`, `kTouchTextOverlayWidth`),
`block_component_action_wrapper.dart`, `block_hover_action.dart`, `reorder_drag_visuals.dart`,
`table_block_component/{table_view,table_block_component}.dart`

The Patch 15 hold-the-left-edge grip was only wired for bullets / numbered / to-do rows. The app
(`applyBlockHoverActions` in `note_block_components.dart`) now wires it for paragraph, heading, quote,
divider, image and table too (not blocks inside a table cell). Engine side:
- **Grip geometry per type** (`touchGripLayoutFor`): marker rows keep the 36px overlay; plain text
  (paragraph / heading) uses a 24px strip so it steals as little of the first characters as possible
  (tap still places the caret, only a long-press drags); divider / image span the block's full height.
- **Table:** the overlay would sit on the row handles / first column, so on touch the grip is a visible
  glyph in the table's own empty top-left corner cell (`TableView.cornerBuilder`); no wrapper overlay.
- **Drag preview:** divider / image / table show an icon (they have no text) and the card is capped at 96px.
- Desktop unchanged (hover gutter for lists only — the gutter is in-flow and would indent all text).

### Patch 16: Enter while a word is composing (Android IME)
**File:** `lib/src/editor/editor_component/service/ime/delta_input_on_replace_impl.dart`

Gboard delivers Enter, pressed right after typing a word, as a REPLACEMENT of the composing word
("alpha" -> "alpha\n"), not as a bare "\n". `onReplace` looked up a character shortcut named
`alpha\n`, found none, and wrote the newline into the text — so Enter in a bullet / to-do /
numbered item made a soft line break inside the item instead of a new one. `onReplace` now commits the
word, then runs the ordinary `\n` shortcuts at the end of it (falling back to a literal newline only
if none wants it). Test: `test/editor/ime/enter_while_composing_test.dart` (fails on the old code).
Also: `TwoFingerIndentDetector` treats `PointerDeviceKind.unknown` (adb / remote-control input,
some vendor drivers) like touch; real fingers are `touch`.

### Patch 18: note/folder links look like links and open on tap
**Files:** `block_component/rich_text/appflowy_rich_text.dart`, `editor_component/service/selection/{shared,mobile_selection_service,desktop_selection_service}.dart`

`noteLink` / `folderLink` runs (the `[[` picker, `/` "Link to note", the "+" menu) rendered as plain text and
never navigated: only `href` got the link style, and the selection gesture layer consumes every tap before a
span's own `TapGestureRecognizer` can fire. Now (1) both attributes get `textStyleConfiguration.href`
(blue + underline), and (2) `openNoteLinkAtPosition` runs from the Android/iOS tap-up and desktop tap-down
handlers: it hit-tests the tap against the link run's painted rects and calls the host's `NoteLinkNavigator`.
Tap on a link opens it instead of placing the caret inside it. Test: `test/editor/note_link_tap_test.dart`.

PATCH 18: `selectionMenuRanker` (lib/src/editor/selection_menu/selection_menu_widget.dart) — an optional host hook that ranks the
slash menu (typos, plurals, word order) before the upstream substring match; items the substring match finds are appended, so nothing
that matched before disappears. Null keeps upstream behaviour. Test: `test/editor/selection_menu/slash_menu_ranker_test.dart`.

PATCH 19: pictures. A tap on an image opens it full screen (like a link opens its page) and a hold / right-click opens a menu, both
through the host-supplied `ImageActions` bridge (lib/src/editor/image_actions.dart; hooks in
editor_component/service/selection/shared.dart: `openImageAtPosition`, `showImageMenuAtPosition`, `ImageHoldLift`, called from the
desktop and mobile selection services). On a phone a hold LIFTS the image (drag to move it among its siblings, drop line and
auto-scroll shared with the margin hold); letting go without moving opens the menu. `ResizableImage` was rewritten: visible grips
with a 44dp touch band (selected / hovered only), width capped by the block, follows `width` changes from outside, snaps to
25/50/75/100% with a haptic tick and a live percentage, one `ImageProvider` for every source (`resolveImageProvider`,
`AttachmentImageProvider`) decoded once at screen width. Edits (`setImageWidth`, `setImageAlign`, `moveImage`, `removeImage`) live in
image_block_component/image_edit.dart. `PlatformExtension.debugMobileOverride` (tests only) makes the editor use the phone's selection
service on a desktop host. Tests: `test/editor/block_component/{resizable_image,image_edit,image_actions}_test.dart`.

PATCH 20: `QuoteBlockComponentBuilder(tint:)` — optional background wash for a quote that sets no colour of its own. Null keeps the
original faint cyan (`0x1A00BCF0`), so `quote_block_tint_test.dart` is unchanged; the host app passes a theme colour. Test:
`test/editor/block_component/quote_block_tint_param_test.dart`.

PATCH 21: `formatDoubleQuoteToQuote` also accepts the markdown `>` marker (typing `> ` at the start of a line makes a quote, as `- `, `1. `, `# ` and `[] ` already do). Only a line whose text before the caret is exactly the marker converts. Test: `test/editor/block_component/quote_markdown_marker_test.dart`.

PATCH 22: table menu. A row or column handle opens the host's popup through the `TableMenuActions` bridge
(lib/src/editor/block_component/table_block_component/table_menu_actions.dart; hook at the top of `showActionMenu`). Added
`TableActions.clearTable` / `deleteTable` and the table-to-text helpers (`table_text.dart`), and exported `TableActions` and
`getCellNode`. Fixed row/column Clear: it inserted an empty paragraph above the old one instead of replacing the cell's content.
Test: `test/editor/block_component/table_block_component/table_menu_actions_test.dart`.

PATCH 23: `TodoListBlockComponentBuilder(childrenDecorator:)` (todo_list_block_component.dart). An optional host hook that wraps the
whole rendered block of a TOP-LEVEL checklist row that has nested rows, so the host can draw connector rails over the nest. Never
called for a row inside another checklist row or a row with no children. Null keeps the stock rendering.

PATCH 24: smooth hold-to-select (`mobile_selection_service.dart`, `mobile_magnifier.dart`). (1) The Android hold-and-drag no longer attaches the
keyboard on every move (`selectionExtraInfoDoNotAttachTextService` while the finger is down, attached once on release), so the keyboard cannot
pop up mid-gesture and resize the page under the finger. (2) Auto-scroll under a resting finger re-extends the held word (`_extendWordSelectionTo`)
instead of collapsing it to a caret. (3) Haptics tick only when the caret or word really changes (the horizontal-drag path used to buzz on every
pointer event). (4) A 1.5 px jitter slop damps the selection (the magnifier still tracks the raw finger). (5) A cancelled hold resets the drag
state and magnifier. (6) The magnifier lens is pinned inside the editor, its focal point still on the finger. Test:
`test/editor/service/mobile_hold_select_test.dart`.

### Patch 26: collapsible block ("toggle")
**Files:** `block_component/collapsible_block_component/*`, `plugins/{markdown,html}/encoder/parser/collapsible_node_parser.dart`, plus one-line
registrations (`standard_block_components.dart`, `block_component.dart`, `indent_command.dart`, `indent_block_node.dart`,
`convert_to_paragraph_command.dart`, `auto_complete_command.dart`, `slash_command.dart`, `note_link_command.dart`, `toolbar_item.dart`,
`reorder_drag_visuals.dart`, the two exporters' parser lists).

A title line with an always-visible chevron; the nested children are the body. Open/closed is the existing `collapsed` attribute
(absent = open), so it is saved with the note, old documents are untouched, and the body stays in the document (search and
export still see it). The chevron is a touch-sized tap target (the older hover-handle collapse is desktop-only). Enter in an open title
starts the first body line, in a closed one adds a line after the block; `>> ` converts a line; a caret that lands in a closed body
(find, undo, a link jump) opens it; fold state is not recorded in undo. Exports as `<details>`/`<summary>` (markdown and HTML) so a
hidden body is never dropped. Host hooks: `toggleDescription`, `hiddenHint`, colours. Test: `test/editor/block_component/collapsible_block_test.dart`.

### Patch 27: columns block (side by side)
**Files:** `plugins/blocks/columns/*` (reworked; it shipped unregistered and unusable), `plugins/{markdown,html}/encoder/parser/columns_node_parser.dart`,
plus registrations (`standard_block_components.dart`, `plugins.dart`, `indent_block_node.dart` `gutterReorderBlockTypes`, `gutter_reorder_detector.dart`,
`reorder_drag_visuals.dart`, `backspace_command.dart`, `delete_command.dart`, the two exporters' parser lists).

`columns > column > blocks`. A column's width is a SHARE (`weight`, absent = 1), not pixels, so it follows the screen: the row is
`Expanded(flex)` per column, dividers are a Stack overlay (no `IntrinsicHeight`, which breaks nested editor widgets). When the average column
would be under 120 px (a phone with 3 columns) the block STACKS vertically. A divider drags width between its two neighbours (in memory while
the finger is down, ONE undoable edit on release; double tap = equal widths). Every edit is a function in `ColumnsActions` (insert, add, remove,
move, equalize, unwrap, delete, repair) so the widget, the host menu and the keys all do the same thing. Rules kept: 2..5 columns, no empty column,
a single remaining column dissolves into the page, no nesting (not inside columns or a table cell). A deletion that spans columns can break
those, so the block repairs itself on screen (`ColumnsActions.repair`). Backspace: the first block of a column never merges leftwards, an emptied
column goes away, and an empty line right after the block just disappears. Press and hold (touch) or drag (mouse) the grip above a column to move it (`columns_drag.dart`: the landing column is found from the pointer against the columns' real rectangles, so it works side by side, stacked and right-to-left; one undo step). Host hooks: colors, `gripSemanticLabel`, `ColumnsMenuActions`
(the popup behind the grip above each column). Exports as columns one after another (markdown) / a flex row (HTML). Tests:
`test/editor/block_component/columns_block_test.dart`.

### Patch 28: table row/column reorder, header row/column, cell fill
**Files:** `table_block_component/{table_action,table_drag,table_view,table_action_handler,table_cell_block_component,table_block_component}.dart`.
`TableActions.move` rewrites the whole grid in column-major order (the Tab key and "add" rely on that order) as ONE undo step; sizes and fills
travel with the line. `table_drag.dart` makes the row/column handle draggable (touch: press and hold; mouse: drag) with a tint on the moving line and a
bar where it lands. `headerRow` / `headerCol` table attributes pin the first line (nothing moves above it) and add/remove the default tint; deleting
that line clears the flag. `cellBackgroundColor` fills one cell and wins over the row/column fill; setting a row/column fill clears the cell fills
in it. Host menu: `table_menu_actions_impl.dart`. Tests: `test/editor/block_component/table_block_component/table_move_test.dart`.

## Upstream Tracking
https://github.com/AppFlowy-IO/appflowy-editor/issues/1180

## Maintenance Note
This vendor copy should be checked periodically against upstream. If AppFlowy-IO ever
publishes a pub.dev release that includes these fixes (check the above issue), this
vendor copy should be replaced with a normal pub.dev dependency in `pubspec.yaml`.
The path dependency in the host app's `pubspec.yaml` would be removed at that time.
PATCH 25: `TodoListBlockComponentBuilder(labelVerticalInset:)` (todo_list_block_component.dart). An optional host hook giving the space above and below a checklist
label INSIDE the row (the label is wrapped in a vertical Padding, and the desktop drag grip becomes a box as tall as the first line plus that inset), so the
host can give the row zero block padding and still make the checkbox tap slot taller than the first line (a child is only hit-tested inside its parent bounds).
Row height is unchanged. Null keeps the stock rendering. Host: `note_block_components.dart` (`noteChecklistRowInset`).

PATCH 27: shift+click / shift+double-click / shift+triple-click / shift+drag (desktop_selection_service.dart). The selection now extends from the live
selection's anchor (`editorState.selection.start`), not from the last tap or drag start, which went stale after keyboard moves and word/paragraph picks and
made the range jump. Shift+double and shift+triple click extend instead of replacing the selection with a word or paragraph. Test:
`test/editor/shift_click_selection_test.dart`.

### Patch 29: a keystroke no longer rebuilds every visible block (typing lag)
**Files:** `block_component/paragraph_block_component/paragraph_block_component.dart`, `block_component/base_component/selection/block_selection_area.dart`

A keystroke moves the caret, so the selection notifier fires on every key, and two listeners fanned that out to every built block:
(1) a paragraph with a host `showPlaceholder` hook called `setState` unconditionally (the app wires one), re-laying out every paragraph's text;
(2) every `BlockSelectionArea` was a `ValueListenableBuilder` that rebuilt although only blocks in the selection can draw anything.
Now (1) rebuilds only when the block shows, or just stopped showing, a hint, and (2) rebuilds only when the block was in or is now in the selection.
Measured on 300 paragraphs: 1902 rebuilt widgets and 30 ms per key before, 24 and 3 ms after. Test: `test/editor/typing_rebuild_budget_test.dart`.

### Patch 29b: adding or removing a block no longer rebuilds the blocks below it (Enter lag)
**Files:** `editor_component/entry/page_block_component.dart`, `flutter/scrollable_positioned_list/src/{positioned_list,scrollable_positioned_list}.dart`

The page list keyed each slot by its INDEX, so inserting a block shifted every block below it into another slot and Flutter
re-parented and rebuilt all of them (about 6400 widgets and 200 ms per Enter on a 300-block test note, debug host).
(1) `PositionedList` takes optional `itemId` / `indexOfItemId`; the slot key (`_ItemKey`) is matched by the item's identity and carries
its current index, and each sliver delegate gets a `findChildIndexCallback`, so a moved item keeps its element. Without them the key is
the index, as upstream (`.separated` lists ignore them). (2) The page passes the block's `Node` as identity (header/footer have fixed ids).
(3) Paragraph, heading and quote items are reused as the same widget instance (`_stableItems`, checked against the editor state, style,
renderer and wrapper), so Flutter skips them. Bullets are reused too (they follow only their ancestors); a numbered item is reused while
its marker (`numberedListLabel`) is unchanged, so an insert rebuilds only the items whose number moved. Checklist rows are NOT reused:
they follow their completed group. Now about 1300 widgets per Enter in text and bullets (the slot wrappers). Tests:
`test/editor/typing_rebuild_budget_test.dart` (budget, content kept, numbered list still renumbers).

### Patch 30: checklist and numbered rows are reused too; checklist rows stop rebuilding on typing
**Files:** `todo_list_block_component/todo_list_block_component.dart`, `numbered_list_block_component/numbered_list_block_component.dart`, `editor_component/entry/page_block_component.dart`

A checklist row already rebuilds itself when its run view changes, so the page-level rebuild was redundant. Its signature held the row's
ABSOLUTE index, which shifts on every insert above and rebuilt every row below. It is now `(role, completedCount, collapsed)` where role is
before-pile / pile-start / inside-pile (`idx` is only ever compared with the pile start in `build`). The row's transaction listener also
skips `TransactionTime.before` and text-only transactions (one run walk per visible row per keystroke saved). Checklist items join
`_stableItemTypes`; numbered items join it with their marker (`numberedListLabel`) as the extra reuse condition. Guide:
`docs/guides/editor-performance.md`. Tests: `test/editor/typing_rebuild_budget_test.dart`, `todo_completed_divider_test.dart`.

### Patch 31: paste a picture (host bridge `ClipboardMediaPaster`)
**Files:** `editor/clipboard_media_paster.dart` (new), `editor_component/service/shortcuts/command/paste_command.dart`, `prevon_quilltext_engine.dart` (export)

Paste only ever read text and HTML, so a copied picture (a screenshot, an image from a web page, a file copied in the file manager) did nothing.
The fork now asks an optional host bridge, `ClipboardMediaPaster.pasteMedia()`, but only when it can matter: never for a clipboard that carries
text (no extra platform call on a normal paste), always for an empty-text clipboard, and for an HTML copy that contains `<img` (so a picture
copied from a web page can become a local attachment instead of a remote link). `true` means the host took the clipboard and nothing is pasted
on top; `false`, an exception, or no provider all fall through to the old text/HTML paste unchanged. The fork has no clipboard plugin: reading
the clipboard, storing the picture and inserting the block belong to the host (same decoupling as `ImageActions`). Tests:
`test/editor/paste_clipboard_media_test.dart`.
