// Pictures on the system clipboard — injected by the host app.
//
// Same decoupling as [ImageTextScanner]: the fork owns the paste shortcut and the decision of
// WHEN to ask (see `paste_command.dart`); the host owns everything that touches the platform
// clipboard's non-text formats, the encrypted attachment store and the document edit that
// follows. The fork has no clipboard plugin and never learns how bytes are read or kept.
//
// The fork reads this with `context.read<ClipboardMediaPaster>()` inside a
// `try { } on ProviderNotFoundException`. With no provider (a host that cannot own an
// attachment, such as the scratchpad) paste behaves exactly as before: text and HTML only.

abstract interface class ClipboardMediaPaster {
  /// Looks for pictures on the system clipboard and, when there are any, stores and inserts them
  /// at the caret, replacing the selection. Returns true when it took the clipboard (the paste is
  /// finished and no text or HTML may be pasted on top), false when there was nothing it could use
  /// (the caller pastes text as usual). Never throws.
  Future<bool> pasteMedia();
}
