import 'dart:typed_data';

/// Bridges the editor's image-rendering widget to host-app attachment
/// storage, without the fork depending on any host-app package.
///
/// The host app (Pie Notes) provides the concrete implementation and
/// supplies it via a `Provider<AttachmentImageLoader>` above the editor
/// widget tree, mirroring `NoteLinkNavigator`'s bridge pattern in this same
/// directory. See `.kilocode/rules/24-fork-app-bridges-and-attachment-uris.md`
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
}
