import 'package:flutter/foundation.dart';

/// Bridge that tells the editor whether it may fetch images over the network
/// on its own, without the fork depending on any host-app package.
///
/// The host app supplies it via a `Provider<RemoteImagePolicy>` above the
/// editor, mirroring `AttachmentImageLoader`. When NO provider is present the
/// editor behaves as if [allowed] were false: a remote image is never fetched
/// until the user taps it. This is deliberate. Fetching an `http(s)` image the
/// moment a note is opened tells the image host when and from where the note
/// was read (a tracking pixel), and is the classic way for injected or imported
/// note content to exfiltrate data in the URL.
@immutable
class RemoteImagePolicy {
  const RemoteImagePolicy({
    required this.allowed,
    required this.blockedLabel,
    this.hiddenPictureLabel = 'Picture hidden. Tap to show it.',
  });

  /// Localized text laid over a received picture that is blurred until tapped.
  final String hiddenPictureLabel;

  /// True when the user has opted in to automatic remote image loading.
  final bool allowed;

  /// Localized text for the placeholder shown instead of a blocked image.
  final String blockedLabel;
}
