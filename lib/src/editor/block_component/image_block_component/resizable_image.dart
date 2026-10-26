import 'dart:math';
import 'dart:ui' as ui;

import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'attachment_image_provider.dart';
import 'image_source.dart';

Widget buildImageLoadingPlaceholder(BuildContext context) {
  // Scaled down to whatever width the picture has: a narrow image (30dp is the
  // floor) must not overflow while it loads.
  return SizedBox(
    height: 150,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.fromSize(
            size: const Size(18, 18),
            child: const CircularProgressIndicator(),
          ),
          SizedBox.fromSize(
            size: const Size(10, 10),
          ),
          Text(AppFlowyEditorL10n.current.loading),
        ],
      ),
    ),
  );
}

Widget buildImageLoadError(BuildContext context, {required double imageWidth}) {
  return Container(
    height: 100,
    width: imageWidth,
    alignment: Alignment.center,
    padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
    decoration: BoxDecoration(
      borderRadius: const BorderRadius.all(Radius.circular(4.0)),
      border: Border.all(width: 1, color: Colors.black),
    ),
    child: Text(AppFlowyEditorL10n.current.imageLoadFailed),
  );
}

/// An image block's picture, with drag handles to resize it.
///
/// PREVON PATCH 19 — what changed from upstream:
///  * Handles are real, visible grips (a pill on each side, a 44dp touch band
///    behind it). They show while the block is [selected] (touch) or hovered
///    (mouse) and are inert otherwise, so an unselected image never resizes
///    by accident while the page scrolls. Upstream had invisible 5dp strips.
///  * The width is capped by the block (a width saved on a wider screen no
///    longer overflows), follows the block's `width` attribute when it
///    changes from outside (menu preset, undo), and snaps to 25/50/75/100%
///    with a haptic tick while dragging, with a live percentage badge.
///  * Every kind of source (attachment, base64, file, network) goes through one
///    [ImageProvider], decoded once at page width via [ResizeImage]: a resize
///    drag only rescales, and a large photo does not cost its full size in
///    memory.
class ResizableImage extends StatefulWidget {
  const ResizableImage({
    super.key,
    required this.alignment,
    required this.editable,
    required this.onResize,
    required this.width,
    required this.src,
    this.height,
    this.selected = false,
  });

  final String src;
  final double width;
  final double? height;
  final Alignment alignment;
  final bool editable;

  /// True while the block is the editor's selection: the resize grips show.
  final bool selected;

  /// Called once, when a resize drag ends, with the new width.
  final void Function(double width) onResize;

  @override
  State<ResizableImage> createState() => ResizableImageState();
}

const _kImageBlockComponentMinWidth = 30.0;

/// Width fractions a drag snaps to, and how close (dp) it must come.
const List<double> _kSnapFractions = [0.25, 0.5, 0.75, 1.0];
const double _kSnapDistance = 8.0;

class ResizableImageState extends State<ResizableImage> {
  late double imageWidth;

  double initialOffset = 0;

  /// Live width while a grip is being dragged, null otherwise.
  double? _dragWidth;
  double _dragStartWidth = 0;
  double? _snapped;

  /// The page width this image can fill, measured when a drag starts.
  double _available = 0;

  final GlobalKey _contentKey = GlobalKey();

  /// The user tapped a blocked remote image to load just this one.
  bool _loadRemoteOnce = false;

  // Picture check (host bridge `AttachmentImageLoader.shouldBlur`). A received
  // picture is not painted until the host has answered; if the answer is "blur"
  // it shows as a small blurred copy until the person taps it. Fails closed.
  String? _blurId; // attachment the verdict below belongs to
  bool? _blurVerdict; // null while the host is still checking
  bool _pictureRevealed = false;

  // Cache: building a provider (base64 decode, string validation) per build is
  // wasteful, and a fresh MemoryImage per build would never hit the image
  // cache. Keyed by everything the provider depends on.
  String? _cachedSrc;
  AttachmentImageLoader? _cachedLoader;
  bool? _cachedRemoteAllowed;
  ImageProvider? _cachedProvider;

  @visibleForTesting
  bool onFocus = false;

  @override
  void initState() {
    super.initState();
    imageWidth = widget.width;
  }

  @override
  void didUpdateWidget(ResizableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The `width` attribute can change from outside (a size preset in the
    // hold menu, undo, a synced edit); keep following it unless a grip is
    // being dragged right now.
    if (_dragWidth == null && widget.width != oldWidget.width) {
      imageWidth = widget.width;
    }
    if (widget.src != oldWidget.src) {
      _loadRemoteOnce = false;
      _blurId = null;
      _blurVerdict = null;
      _pictureRevealed = false;
    }
  }

  /// null while the host is still checking, else whether to blur. Anything that
  /// is not a host attachment is never blurred. The question is asked after the
  /// frame (never from `build`), and an error answers "blur".
  bool? _blurNeeded(ImageProvider provider) {
    if (provider is! AttachmentImageProvider) return false;
    final id = provider.attachmentId;
    if (_blurId != id) {
      _blurId = id;
      _blurVerdict = null;
      _pictureRevealed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        bool verdict;
        try {
          verdict = await provider.loader.shouldBlur(id);
        } catch (_) {
          verdict = true;
        }
        if (!mounted || _blurId != id) return;
        setState(() => _blurVerdict = verdict);
      });
    }
    return _blurVerdict;
  }

  bool _pictureShown(AttachmentImageProvider p) =>
      _blurId == p.attachmentId && (_blurVerdict == false || _pictureRevealed);

  Widget _buildHiddenPicture(
    BuildContext context,
    ImageProvider provider,
    double width,
  ) {
    String label;
    try {
      label = context.read<RemoteImagePolicy>().hiddenPictureLabel;
    } on ProviderNotFoundException {
      label = 'Picture hidden. Tap to show it.';
    }
    return GestureDetector(
      key: const Key('hidden_picture'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (provider is AttachmentImageProvider) {
          try {
            provider.loader.onPictureRevealed(provider.attachmentId);
          } catch (_) {}
        }
        setState(() => _pictureRevealed = true);
      },
      child: ClipRect(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Only a tiny copy is ever decoded for a hidden picture, then
            // blurred on top: no detail to leak even if the blur were skipped.
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 14,
                sigmaY: 14,
                tileMode: ui.TileMode.clamp,
              ),
              child: Image(
                image: ResizeImage(provider, width: 48),
                width: width,
                fit: BoxFit.fitWidth,
                filterQuality: FilterQuality.low,
                errorBuilder: (context, error, stackTrace) =>
                    SizedBox(width: width, height: 100),
              ),
            ),
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.visibility_off_outlined,
                    size: 18,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The picture's painted box in global coordinates (the part a tap or hold
  /// counts as "on the image"), or null before the first layout.
  Rect? get globalRect {
    final box = _contentKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The page width this image can fill: what the block gives it. Measured on
  /// demand (a gesture, never `build`) so no `LayoutBuilder` is involved, which
  /// would break a parent that asks for intrinsic sizes.
  double get availableWidth {
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize && box.size.width > 0) {
      _available = box.size.width;
    }
    return _available > 0 ? _available : max(widget.width, 0.0);
  }

  /// The width the image is drawn at right now.
  double get currentWidth {
    final box = _contentKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) return box.size.width;
    return _dragWidth ?? imageWidth;
  }

  /// The provider for the full-screen viewer, or null when there is nothing to
  /// show (a remote image the user has not allowed to load).
  ImageProvider? get viewerProvider {
    final p = _providerFor(context);
    // A received picture that is still hidden (or still being checked) does not
    // open full screen: the person taps it to show it first.
    if (p is AttachmentImageProvider && !_pictureShown(p)) return null;
    return p;
  }

  @override
  Widget build(BuildContext context) {
    // The block's own constraints cap the width (SizedBox clamps a too-wide
    // request), so a width saved on a wider screen never overflows.
    final width = max(
      _kImageBlockComponentMinWidth,
      _dragWidth ?? imageWidth,
    );
    return Align(
      alignment: widget.alignment,
      child: SizedBox(
        key: _contentKey,
        width: width,
        height: widget.height,
        child: MouseRegion(
          onEnter: (event) => setState(() {
            onFocus = true;
          }),
          onExit: (event) => setState(() {
            onFocus = false;
          }),
          child: _buildResizableImage(context, width),
        ),
      ),
    );
  }

  bool _remoteImageAllowed(BuildContext context) {
    if (_loadRemoteOnce) return true;
    try {
      return context.read<RemoteImagePolicy>().allowed;
    } on ProviderNotFoundException {
      return false;
    }
  }

  AttachmentImageLoader? _attachmentLoader(BuildContext context) {
    try {
      return context.read<AttachmentImageLoader>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Widget _buildBlockedRemoteImage(BuildContext context, double width) {
    String label;
    try {
      label = context.read<RemoteImagePolicy>().blockedLabel;
    } on ProviderNotFoundException {
      // No host policy: use a neutral default. The host app always provides a
      // localized label; this fallback only serves bare use of the fork.
      label = 'Remote image blocked. Tap to load it once.';
    }
    return GestureDetector(
      key: const Key('blocked_remote_image'),
      onTap: () => setState(() => _loadRemoteOnce = true),
      child: Container(
        height: 100,
        width: width,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(4.0)),
          border: Border.all(width: 1, color: Colors.grey),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported_outlined, size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }

  /// The one [ImageProvider] for [widget.src] (see [resolveImageProvider]), or
  /// null for a remote image the policy blocks.
  ImageProvider? _providerFor(BuildContext context) {
    final src = widget.src;
    final loader = _attachmentLoader(context);
    final remoteAllowed = _remoteImageAllowed(context);
    if (_cachedProvider != null &&
        _cachedSrc == src &&
        identical(_cachedLoader, loader) &&
        _cachedRemoteAllowed == remoteAllowed) {
      return _cachedProvider;
    }
    final provider = resolveImageProvider(
      src,
      loader: loader,
      allowRemote: remoteAllowed,
    );
    _cachedSrc = src;
    _cachedLoader = loader;
    _cachedRemoteAllowed = remoteAllowed;
    _cachedProvider = provider;
    return provider;
  }

  Widget _buildResizableImage(BuildContext context, double width) {
    final provider = _providerFor(context);
    final Widget child;
    final blur = provider == null ? false : _blurNeeded(provider);
    if (provider == null) {
      child = _buildBlockedRemoteImage(context, width);
    } else if (blur == null) {
      // The host is still checking: paint nothing of the picture yet.
      child = buildImageLoadingPlaceholder(context);
    } else if (blur && !_pictureRevealed) {
      child = _buildHiddenPicture(context, provider, width);
    } else {
      final media = MediaQuery.maybeOf(context);
      // Decoded once at the widest the screen can show, never per drag frame.
      final decodeWidth = media == null
          ? null
          : (media.size.width * media.devicePixelRatio).round();
      child = Image(
        image: decodeWidth == null
            ? provider
            : ResizeImage.resizeIfNeeded(decodeWidth, null, provider),
        width: width,
        gaplessPlayback: true,
        // A spinner only for sources that genuinely take a moment (decrypting
        // an attachment, a network fetch). Memory and file images arrive at
        // once; until then they hold a still, empty box (an endlessly
        // animating spinner would also keep a test's pumpAndSettle from ever
        // settling).
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          if (provider is AttachmentImageProvider || provider is NetworkImage) {
            return buildImageLoadingPlaceholder(context);
          }
          return const SizedBox(height: 100);
        },
        errorBuilder: (context, error, stackTrace) => GestureDetector(
          key: const Key('retry_image_load'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // Drop the failed provider so the next build starts a fresh load.
            provider.evict();
            setState(() => _cachedProvider = null);
          },
          child: buildImageLoadError(context, imageWidth: width),
        ),
      );
    }

    final gripsShown = widget.editable &&
        provider != null &&
        (widget.selected || onFocus || _dragWidth != null);
    // A band wider than a third of a narrow image would cover its middle.
    final band = min(44.0, width / 3);
    return Stack(
      children: [
        child,
        if (gripsShown) ...[
          // The edge on the aligned side stays put, so only the free side's
          // grip makes sense; a centred image grows on both and shows both.
          if (widget.alignment != Alignment.centerLeft)
            _buildGrip(context, left: true, band: band),
          if (widget.alignment != Alignment.centerRight)
            _buildGrip(context, left: false, band: band),
        ],
        if (_dragWidth != null) _buildSizeBadge(width, _available),
      ],
    );
  }

  Widget _buildSizeBadge(double width, double available) {
    final percent = available <= 0 ? 100 : (width / available * 100).round();
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$percent%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One side's grip. The touch band is [band] wide and as tall as the image;
  /// the visible pill sits inside it, inset from the image edge.
  Widget _buildGrip(
    BuildContext context, {
    required bool left,
    required double band,
  }) {
    // Dragging outward grows the image. A centred image grows on both sides,
    // so the edge follows the finger at half the width change per side.
    final factor = widget.alignment == Alignment.center ? 2.0 : 1.0;
    final sign = left ? -1.0 : 1.0;
    final dragging = _dragWidth != null;
    return Positioned(
      top: 0,
      bottom: 0,
      left: left ? 0 : null,
      right: left ? null : 0,
      width: band,
      child: GestureDetector(
        key: Key(left ? 'image_grip_left' : 'image_grip_right'),
        behavior: HitTestBehavior.opaque,
        // Track from the press, not from where the touch slop ends, so the
        // edge stays under the finger.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (details) {
          initialOffset = details.globalPosition.dx;
          _available = availableWidth;
          _dragStartWidth = currentWidth;
          _snapped = null;
          HapticFeedback.lightImpact();
          setState(() => _dragWidth = _dragStartWidth);
        },
        onHorizontalDragUpdate: (details) {
          final delta =
              (details.globalPosition.dx - initialOffset) * sign * factor;
          final available = _available;
          final floor = min(_kImageBlockComponentMinWidth, available);
          var proposed = (_dragStartWidth + delta).clamp(floor, available);
          double? hit;
          for (final f in _kSnapFractions) {
            final target = f * available;
            if ((proposed - target).abs() <= _kSnapDistance) {
              proposed = target;
              hit = f;
              break;
            }
          }
          if (hit != null && hit != _snapped) HapticFeedback.selectionClick();
          _snapped = hit;
          setState(() => _dragWidth = proposed);
        },
        onHorizontalDragEnd: (details) => _endDrag(),
        // A drag taken away (scroll takeover, system gesture) is undone, not
        // committed half way.
        onHorizontalDragCancel: () => _endDrag(commit: false),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: Align(
            alignment: left ? Alignment.centerLeft : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: dragging ? 8 : 6,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: dragging ? 0.75 : 0.55),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(width: 1.5, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _endDrag({bool commit = true}) {
    final live = _dragWidth;
    if (live == null) return;
    initialOffset = 0;
    if (!commit || (live - _dragStartWidth).abs() < 0.5) {
      // Cancelled, or let go where it started: nothing to write (and no empty
      // undo step).
      setState(() => _dragWidth = null);
      return;
    }
    imageWidth = live;
    setState(() => _dragWidth = null);
    widget.onResize(live);
  }
}
