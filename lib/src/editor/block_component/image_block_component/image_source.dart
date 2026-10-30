import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:string_validator/string_validator.dart';

import '../../attachment_image_loader.dart';
import '../../local_image_policy.dart';
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
  if (_isHttpUrl(src)) return allowRemote ? NetworkImage(src) : null;
  if (kIsWeb) return null;
  // A note can carry any string here: only a plain absolute local path may reach the filesystem.
  // The roots check is NOT done lexically here: a root reached through a symlink
  // (Android /data/user/0, iOS /var) only matches after resolving, so the
  // provider decides at read time (readLocalImageBounded) and fails closed.
  if (!isSafeLocalImagePath(src)) return null;
  // A legacy local path: the same header guard and bounded decode as an attachment, never the raw codec.
  return GuardedBytesImageProvider(
      'file:$src', () => readLocalImageBounded(src));
}

// Only an explicit http(s) URL is remote; isURL also accepts scheme-less strings such as `\\h\s\x.png`.
bool _isHttpUrl(String s) =>
    RegExp(r'^https?://', caseSensitive: false).hasMatch(s) && isURL(s);

/// Whether a bare-path image `src` from a note is a plain absolute LOCAL path.
///
/// Refuses everything that could reach another machine or a special namespace:
/// UNC and device paths (`\\host\share`, `//host/share`, `\\?\`, `\\.\`),
/// any `scheme:` form (`file://host/x`, `file:///x`, `smb:`) except a drive
/// letter, relative paths, `..` segments and NUL. Accepts `/abs/path` and
/// `C:\abs` / `C:/abs`. Legit sources are the picker's absolute path and
/// `pie-att://` (routed to the loader before this is reached).
bool isSafeLocalImagePath(String src) {
  if (src.isEmpty || src.contains('\u0000')) return false;
  final n = src.replaceAll('\\', '/');
  if (n.startsWith('//')) return false;
  final abs = n.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(n);
  if (!abs) return false;
  return !n.split('/').contains('..');
}

/// Largest local image file a bare-path `src` may load.
const int kLocalImageMaxBytes = 64 * 1024 * 1024;

/// Reads a bare-path image (untrusted note content) without trusting the
/// filesystem: it must be a regular file (never a device such as /dev/zero or
/// a pipe) of at most [maxBytes], and the read itself is streamed and aborted
/// at [maxBytes] in case the size lies (/proc files report 0). Audit L09-001.
Future<Uint8List> readLocalImageBounded(String path,
    {int maxBytes = kLocalImageMaxBytes}) async {
  if (!isSafeLocalImagePath(path)) {
    throw FileSystemException('Not a plain local image path', path);
  }
  if (!await LocalImagePolicy.allowsResolved(path)) {
    throw FileSystemException('Local image outside the allowed folders', path);
  }
  final stat = await FileStat.stat(path);
  if (stat.type != FileSystemEntityType.file || stat.size > maxBytes) {
    throw FileSystemException('Not a bounded regular image file', path);
  }
  final out = BytesBuilder(copy: false);
  await for (final chunk in File(path).openRead()) {
    out.add(chunk);
    if (out.length > maxBytes) {
      throw FileSystemException('Image file too large', path);
    }
  }
  return out.takeBytes();
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
