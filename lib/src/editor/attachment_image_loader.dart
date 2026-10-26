import 'dart:typed_data';

/// Bridges the editor's image-rendering widget to host-app attachment
/// storage, without the fork depending on any host-app package.
///
/// The host app provides the concrete implementation and
/// supplies it via a `Provider<AttachmentImageLoader>` above the editor
/// widget tree, mirroring `NoteLinkNavigator`'s bridge pattern in this same
/// directory. See `docs/ai_knowledge_map/rule_library/06-fork-app-bridges-and-attachment-uris.md`
/// once that rule file exists.
abstract class AttachmentImageLoader {
  /// Returns the attachment id if [src] is a resolvable attachment URI in
  /// the host app's own URI scheme, or null if [src] is not an attachment
  /// reference (e.g. it's base64, a network URL, or a legacy raw file path).
  /// The fork never parses or knows the URI format itself.
  String? attachmentIdFromSrc(String src);

  /// Decrypts and returns the attachment's raw bytes. Must throw (never
  /// return null) on any failure — missing attachment, decryption failure,
  /// or the host app's storage layer not yet being ready.
  Future<Uint8List> loadAttachment(String attachmentId);

  /// True when the picture must be shown blurred until the person taps it (the
  /// host's picture check). Asked once per picture, before it is painted; a
  /// failure counts as true. The default never blurs, so a host without a check
  /// is unchanged.
  Future<bool> shouldBlur(String attachmentId) async => false;

  /// The person tapped a blurred picture to show it. The host may remember that
  /// for the session so the picture is not blurred again on the next open.
  void onPictureRevealed(String attachmentId) {}
}
