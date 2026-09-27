// In-editor note/folder link picker controller — injected by the host app
// (Pie Notes) so the editor can surface the picker when the user types `[[`
// without depending on app-layer code.
//
// MANDATE: prevon_quilltext_engine sits below the Pie Notes app. The host
// supplies the picker via Provider<NoteLinkPickerController> above the
// AppFlowyEditor; the editor's [[ character-event handler calls
// [showOrReplace] when the user types the second `[`.
//
// The picker itself is owned by the host app — the fork only defines the
// trigger handshake. This is the same decoupling the NoteLinkNavigator
// (default_text_span_decorator_for_attribute.dart) uses for tap handling.

import 'package:flutter/material.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart'
    show EditorState;

/// Identity of a picked note/folder inside a picker result handed back to
/// the editor. The host app resolves [id] to a real route through its own
/// [NoteLinkNavigator]; the editor only knows that something was picked.
class NoteLinkPick {
  final String id;
  final String label;
  final bool isFolder;
  const NoteLinkPick({
    required this.id,
    required this.label,
    required this.isFolder,
  });
}

/// Abstract controller the host app supplies. The editor's [[ character
/// handler calls [showOrReplace] (idempotent — replace any already-open
/// picker); the picker entity itself lives entirely inside the host app.
abstract class NoteLinkPickerController {
  /// Open a fresh picker anchored at the current caret, or replace any
  /// already-open picker with a new one. Called when the user types the
  /// second `[`.
  ///
  /// [editorState] and [context] are the editor's own state and the
  /// BuildContext that caused the trigger (so the overlay can be inserted
  /// in the right ancestor).
  ///
  /// [onPicked] is invoked by the host when the user picks a result — the
  /// editor then deletes the `[[`-and-query text and inserts the chosen
  /// label as a clickable link.
  void showOrReplace(
    EditorState editorState,
    BuildContext context, {
    required void Function(NoteLinkPick picked) onPicked,
  });

  /// Tear down the picker (e.g. when the user presses Escape or focus
  /// leaves the editor).
  void dismiss();
}

/// No-op fallback so the [[ character event stays a no-op when the host
/// app has not wired a real controller (e.g. editor surfaces outside
/// Pie Notes). Returning early from the [[ trigger avoids throwing.
class NoopNoteLinkPickerController implements NoteLinkPickerController {
  const NoopNoteLinkPickerController();
  @override
  void showOrReplace(
    EditorState editorState,
    BuildContext context, {
    required void Function(NoteLinkPick picked) onPicked,
  }) {}
  @override
  void dismiss() {}
}
