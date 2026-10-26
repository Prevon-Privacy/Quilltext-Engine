import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:string_validator/string_validator.dart';

import '../../attachment_image_loader.dart';
import 'attachment_image_provider.dart';
import 'base64_image.dart';

/// The one [ImageProvider] for an image block's `url` attribute, or null for a
/// remote image the policy does not allow to load.
///
/// Used by the inline block and by the full-screen viewer's page list, so both
/// agree on what a source means. Order matters: a host attachment URI first (so
/// `pie-att://` can never be misrouted into a branch it does not belong to),
/// then base64, a network URL, and last a legacy local file path.
ImageProvider? resolveImageProvider(
  String src, {
  required AttachmentImageLoader? loader,
  required bool allowRemote,
}) {
  final attachmentId = loader?.attachmentIdFromSrc(src);
  if (loader != null && attachmentId != null) {
    return AttachmentImageProvider(loader, attachmentId);
  }
  if (isBase64(src)) return _memoryImageFor(src);
  if (isURL(src)) return allowRemote ? NetworkImage(src) : null;
  if (kIsWeb) return null;
  // A legacy local path: the same header guard and bounded decode as an attachment, never the raw codec.
  return GuardedBytesImageProvider('file:$src', () => File(src).readAsBytes());
}

// A MemoryImage is keyed by its byte list, so a fresh one per call would miss
// the image cache every time (and decode the base64 again). Keep the last few.
final Map<String, GuardedBytesImageProvider> _memoryImages =
    <String, GuardedBytesImageProvider>{};

GuardedBytesImageProvider _memoryImageFor(String src) {
  final cached = _memoryImages.remove(src);
  // Untrusted base64 from a note: guarded and bounded like an attachment.
  final image = cached ??
      GuardedBytesImageProvider(
          'b64:$src', () async => dataFromBase64String(src));
  _memoryImages[src] = image; // most recent last
  if (_memoryImages.length > 8) _memoryImages.remove(_memoryImages.keys.first);
  return image;
}
