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
(the Pie Notes note editor + scratchpad) pass a Dart record of those props. A
debug-only `debugAppFlowyEditorServiceBuildCount` counter (kDebugMode-gated) exists
solely to let tests observe whether `_buildServices` actually ran.

**Deviation type:** deliberate local extension, not an upstream-bug workaround. There
is no upstream issue to track; the upstream `didUpdateWidget` remains correct for
callers that change the service-rendered props wholesale. Do not "restore" the
unconditional `services = null` — that re-introduces the per-rebuild waste this patch
removes.

## Upstream Tracking
https://github.com/AppFlowy-IO/appflowy-editor/issues/1180

## Maintenance Note
This vendor copy should be checked periodically against upstream. If AppFlowy-IO ever
publishes a pub.dev release that includes these fixes (check the above issue), this
vendor copy should be replaced with a normal pub.dev dependency in `pubspec.yaml`.
The path dependency in Pie Notes' `pubspec.yaml` would be removed at that time.