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
    this.via,
  });

  /// The note id of the Files item that owns this file when the block is a LINK to it (`FileBlockKeys.via`), else null (the block
  /// holds its own copy). An id only, never a name. The block's `src` is the owner's blob either way, so opening needs no special case.
  final String? via;

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

  /// The file moves into Files and this block becomes a link to it (needs a [FileLinkHost]; without one nothing happens).
  moveToFiles,

  /// A copy of the file is kept in Files; this block is unchanged (needs a [FileLinkHost]).
  copyToFiles,

  /// A link becomes its own independent copy inside this note (needs a [FileLinkHost]).
  makeCopy,

  /// Opens the Files item a link points at (handled by the host inside `showFileMenu`; the fork never sees it).
  openInFiles,

  /// Opens the host's file page and starts turning the file into text (handled by the host inside `showFileMenu`; the fork never sees it).
  convertToText,
}

/// What a file block holds after the host moved or copied its bytes: the blob `url` it now points at, the owning Files item (`via`, or
/// null for a block that holds its own copy) and, when they changed, the shown name, type and size.
@immutable
class FileLinkChange {
  const FileLinkChange({
    required this.url,
    this.via,
    this.name,
    this.mime,
    this.size,
  });

  final String url;
  final String? via;
  final String? name;
  final String? mime;
  final int? size;
}

/// Optional third bridge for Copy / Move / Link: the fork owns the document edit, the host owns the bytes (it stores a new attachment,
/// makes the Files item and says why when it cannot). Read with `context.read<FileLinkHost>()` inside a
/// `try { } on ProviderNotFoundException`; without it the three choices do nothing.
abstract interface class FileLinkHost {
  /// Moves the file into Files (a verified copy first) and returns the link this block should now hold, or null when it was
  /// cancelled or failed (the host has already told the person).
  Future<FileLinkChange?> moveToFiles(
      BuildContext context, FileViewRequest file);

  /// Keeps a copy of the file in Files. True when it landed.
  Future<bool> copyToFiles(BuildContext context, FileViewRequest file);

  /// Makes this link's file an independent copy owned by the note, and returns what the block should now hold (`via` null), or null.
  Future<FileLinkChange?> makeIndependentCopy(
      BuildContext context, FileViewRequest file);
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
