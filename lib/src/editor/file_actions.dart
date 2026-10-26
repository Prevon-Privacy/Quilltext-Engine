// File block tap / hold actions — injected by the host app.
//
// Same decoupling as [ImageActions]: the fork owns the gestures and every
// document edit; the host owns what a file can do (decrypt to a temporary
// copy, open it, save it out), because only the host can reach the stored
// attachment store. The fork never parses the `pie-att://` reference: it hands
// the host the block's opaque `src` and the host resolves it.
//
// Read with `context.read<FileActions>()` inside a
// `try { } on ProviderNotFoundException`. With no provider a file block still
// draws (name, size) but tap and hold do nothing.

import 'package:flutter/widgets.dart';

/// One file block, as the host needs to see it.
@immutable
class FileViewRequest {
  const FileViewRequest({
    required this.src,
    required this.name,
    required this.mime,
    required this.sizeBytes,
    this.hiddenFromAi = false,
  });

  /// The block's opaque reference. The host resolves it.
  final String src;

  /// The name shown on the card (kept inside the saved note body).
  final String name;

  /// MIME type, or an empty string when unknown.
  final String mime;

  /// Plaintext size in bytes, or 0 when unknown.
  final int sizeBytes;

  /// True when the person hid this one file from the host's features. Lives in the saved note body
  /// (`FileBlockKeys.hiddenFromAi`), so it travels and syncs with the note and nowhere else.
  final bool hiddenFromAi;
}

/// What the person can do to a file block from the hold / right-click menu.
enum FileMenuChoice {
  open,

  /// Opens the in-app safe viewer (handled by the host inside `showFileMenu`; the fork never sees it).
  view,
  save,
  moveUp,
  moveDown,
  remove,

  /// Opens the host's list of every file in the note (handled inside `showFileMenu`; the fork never sees it).
  listAll,

  /// Toggle "Hide" for this one file (the label follows the current state).
  toggleAiHidden,
}

@immutable
class FileMenuRequest {
  const FileMenuRequest({
    required this.file,
    required this.editable,
    required this.canMoveUp,
    required this.canMoveDown,
    this.allFiles = const [],
  });

  final FileViewRequest file;

  /// Every file block in the note, in document order (this one included). Lets the host show its
  /// "Files in this note" list from the menu without reaching into the document.
  final List<FileViewRequest> allFiles;

  /// False in a read-only note: the host shows only open and save.
  final bool editable;
  final bool canMoveUp;
  final bool canMoveDown;
}

abstract interface class FileActions {
  /// Opens the file. Called from a tap, so it is safe to start work directly.
  /// The host decrypts to an app-owned temporary copy and removes it afterwards.
  Future<void> openFile(BuildContext context, FileViewRequest request);

  /// Saves a decrypted copy where the person chooses.
  Future<void> saveFile(BuildContext context, FileViewRequest request);

  /// Shows the host-styled menu. Resolves to the choice, or null when
  /// dismissed. The fork applies move / remove itself.
  Future<FileMenuChoice?> showFileMenu(
    BuildContext context,
    FileMenuRequest request,
  );
}

/// Optional second bridge for the per-file "Hide" choice: the fork owns the
/// document edit, the host owns the words (badge label, Undo toast). Read with
/// `context.read<FileAiHideHost>()` inside a `try { } on ProviderNotFoundException`; without it the
/// choice still works, just silently.
abstract interface class FileAiHideHost {
  /// A small marker drawn on a card whose file is hidden, or null for none.
  Widget? hiddenBadge(BuildContext context);

  /// Called after the fork flipped the choice. [undo] puts it back (one more edit).
  void aiHiddenChanged(
    BuildContext context, {
    required bool hidden,
    required VoidCallback undo,
  });
}
