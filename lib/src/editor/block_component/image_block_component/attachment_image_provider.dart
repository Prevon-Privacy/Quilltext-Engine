import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../attachment_image_loader.dart';

/// An [ImageProvider] for a host-app attachment, decrypted on demand through
/// the [AttachmentImageLoader] bridge.
///
/// Being a real provider is what makes a stored image behave like any
/// other image: Flutter's image cache keeps the decoded picture, so scrolling
/// a note back and forth does not decrypt and decode it again, and the inline
/// block and the full-screen viewer share one decode. Wrapped in a
/// `ResizeImage`, the inline block holds only a screen-sized copy of a large
/// photo instead of every pixel.
///
/// Loading starts when the image stream is first listened to (from the `Image`
/// widget's `didChangeDependencies`), never from a `build`, so the bridge's
/// "no command dispatch while building" rule holds.
/// Most pixels one attachment picture may occupy once decoded (~64 MB RGBA), wherever it is drawn (inline, full screen, no
/// MediaQuery). A bigger picture (the host's header guard allows up to 100M) is decoded scaled down to fit.
const int kAttachmentDecodeMaxPixels = 16 * 1000 * 1000;

/// The decode size for a [width]x[height] picture under [maxPixels], or null when it already fits. Keeps the aspect ratio and
/// never returns a side below 1.
({int width, int height})? boundedDecodeSize(int width, int height,
    {int maxPixels = kAttachmentDecodeMaxPixels}) {
  if (width <= 0 || height <= 0 || width * height <= maxPixels) return null;
  final s = math.sqrt(maxPixels / (width * height));
  var w = math.max(1, (width * s).floor());
  var h = math.max(1, (height * s).floor());
  while (w * h > maxPixels) {
    if (w >= h) {
      w = math.max(1, w - 1);
    } else {
      h = math.max(1, h - 1);
    }
  }
  return (width: w, height: h);
}

/// Read-time guard limits, the same numbers as the host's header guard (`kImageMaxPixels`, `kImageMaxSide` in pie_contracts,
/// which this fork cannot import): a picture declaring more is refused before any pixel is allocated.
const int kImageGuardMaxPixels = 100 * 1000 * 1000;
const int kImageGuardMaxSide = 30000;

/// Thrown when a picture's own header declares a size the guard refuses. The image block shows its "could not load" state.
class ImageHeaderRefused implements Exception {
  const ImageHeaderRefused(this.width, this.height);
  final int width;
  final int height;
  @override
  String toString() => 'ImageHeaderRefused(${width}x$height)';
}

/// THE one way an image block turns untrusted encoded bytes into a codec: read only the header, refuse a hostile size, and decode
/// a big picture straight to at most [maxPixels]. Within the budget [decode] runs unchanged (so a `ResizeImage` still applies).
Future<ui.Codec> decodeGuardedBounded(
  Uint8List bytes,
  ImageDecoderCallback decode, {
  int maxPixels = kAttachmentDecodeMaxPixels,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final ui.ImageDescriptor desc;
  try {
    desc = await ui.ImageDescriptor.encoded(buffer);
  } catch (_) {
    buffer.dispose();
    rethrow;
  }
  final w = desc.width, h = desc.height;
  if (w <= 0 ||
      h <= 0 ||
      w > kImageGuardMaxSide ||
      h > kImageGuardMaxSide ||
      w * h > kImageGuardMaxPixels) {
    desc.dispose();
    buffer.dispose();
    throw ImageHeaderRefused(w, h);
  }
  final target = boundedDecodeSize(w, h, maxPixels: maxPixels);
  if (target == null) {
    desc.dispose();
    return decode(buffer);
  }
  buffer.dispose();
  return desc.instantiateCodec(
      targetWidth: target.width, targetHeight: target.height);
}

/// An image block picture from bytes that are not an attachment (a base64 `src`, a legacy local file path): the same guard and
/// bounded decode as [AttachmentImageProvider], never the raw codec. [key] identifies the source for the image cache.
@immutable
class GuardedBytesImageProvider
    extends ImageProvider<GuardedBytesImageProvider> {
  const GuardedBytesImageProvider(this.key, this.load,
      {this.maxDecodePixels = kAttachmentDecodeMaxPixels});

  final String key;
  final Future<Uint8List> Function() load;
  final int maxDecodePixels;

  @override
  Future<GuardedBytesImageProvider> obtainKey(
          ImageConfiguration configuration) =>
      SynchronousFuture<GuardedBytesImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
      GuardedBytesImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: () async {
        final bytes = await load();
        return decodeGuardedBounded(bytes, decode, maxPixels: maxDecodePixels);
      }(),
      scale: 1.0,
      debugLabel: 'guarded-image',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GuardedBytesImageProvider &&
      other.key == key &&
      other.maxDecodePixels == maxDecodePixels;

  @override
  int get hashCode => Object.hash(key, maxDecodePixels);
}

@immutable
class AttachmentImageProvider extends ImageProvider<AttachmentImageProvider> {
  const AttachmentImageProvider(this.loader, this.attachmentId,
      {this.maxDecodePixels = kAttachmentDecodeMaxPixels});

  final AttachmentImageLoader loader;
  final String attachmentId;

  /// Pixel budget for the decoded picture (see [kAttachmentDecodeMaxPixels]).
  final int maxDecodePixels;

  @override
  Future<AttachmentImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<AttachmentImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    AttachmentImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1.0,
      debugLabel: 'pie-att://v1/$attachmentId',
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    // A load right after a login or account switch can land before the host has
    // wired attachment decryption for the new session; a failed first try is
    // retried a few times instead of leaving the block broken for good.
    const delays = [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
    ];
    Uint8List? bytes;
    for (var attempt = 0;; attempt++) {
      try {
        bytes = await loader.loadAttachment(attachmentId);
        break;
      } catch (_) {
        if (attempt >= delays.length) rethrow;
        await Future<void>.delayed(delays[attempt]);
      }
    }
    // Header first: a hostile size is refused, a huge picture decoded straight to a bounded size.
    return decodeGuardedBounded(bytes!, decode, maxPixels: maxDecodePixels);
  }

  @override
  bool operator ==(Object other) =>
      other is AttachmentImageProvider &&
      identical(other.loader, loader) &&
      other.attachmentId == attachmentId &&
      other.maxDecodePixels == maxDecodePixels;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(loader), attachmentId, maxDecodePixels);

  @override
  String toString() => 'AttachmentImageProvider($attachmentId)';
}
