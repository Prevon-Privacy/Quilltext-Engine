// Image tap / hold actions — injected by the host app.
//
// Same decoupling as [NoteLinkNavigator] and [LinkEditor]: the fork owns the
// gestures (tap, hold, right-click on an image) and every document edit; the
// host owns the screens it opens (the full-screen viewer, the hold menu), which
// use design-system widgets and localized strings the fork may not import.
//
// A tap on an image behaves like a tap on a link to a page: it opens the image
// on its own screen ([ImageActions.openImage]). A hold or right-click opens the
// host's menu ([ImageActions.showImageMenu]); the fork applies whatever the
// user picks.
//
// The fork reads this with `context.read<ImageActions>()` inside a
// `try { } on ProviderNotFoundException`. With no provider an image keeps its
// old behaviour (select on tap, no menu).

import 'package:flutter/widgets.dart';

/// One image the full-screen viewer can show.
@immutable
class ImageViewItem {
  const ImageViewItem({required this.image, this.id});

  /// How to draw it. Already resolved by the fork (attachment, base64, file or
  /// network), so the host never needs to know where the bytes came from.
  final ImageProvider image;

  /// Opaque, stable per image block; lets the host keep a hero / page key.
  final String? id;
}

/// What to show: every viewable image of the note, in reading order, and which
/// one was tapped, so the viewer can swipe between them.
@immutable
class ImageViewRequest {
  const ImageViewRequest({required this.items, required this.initialIndex})
      : assert(initialIndex >= 0);

  final List<ImageViewItem> items;
  final int initialIndex;
}

/// How wide an image sits in the page, as a share of the page width.
enum ImageSizePreset {
  small(0.25),
  medium(0.5),
  large(0.75),
  full(1.0);

  const ImageSizePreset(this.fraction);

  final double fraction;

  /// The preset [width] matches within a small tolerance (a pixel or two of
  /// rounding), or null when it is a custom size.
  static ImageSizePreset? match(double width, double available) {
    if (available <= 0) return null;
    for (final p in values) {
      if ((width - p.fraction * available).abs() <= 2.0) return p;
    }
    return null;
  }
}

/// What the user can do to an image from the hold / right-click menu.
enum ImageMenuChoice {
  open,
  alignLeft,
  alignCenter,
  alignRight,
  sizeSmall,
  sizeMedium,
  sizeLarge,
  sizeFull,
  moveUp,
  moveDown,
  remove,

  /// Read the words in the picture on this device ([ImageTextScanner]).
  scanText,
}

/// What the host needs to draw the menu: the current state of the image and
/// which edits are possible.
@immutable
class ImageMenuRequest {
  const ImageMenuRequest({
    required this.editable,
    required this.align,
    required this.size,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canOpen,
    this.canScanText = false,
  });

  /// False in a read-only note: the host shows only "open".
  final bool editable;

  /// `left`, `center` or `right`.
  final String align;

  /// The preset the image currently matches, or null for a custom width.
  final ImageSizePreset? size;

  final bool canMoveUp;
  final bool canMoveDown;

  /// False while the image is a blocked remote image or still failed to load:
  /// there is nothing to open full screen.
  final bool canOpen;

  /// The host can read text from this picture (an [ImageTextScanner] is provided).
  final bool canScanText;
}

abstract interface class ImageActions {
  /// Opens [request] full screen. Called from a tap, so it is safe to push a
  /// route directly.
  void openImage(BuildContext context, ImageViewRequest request);

  /// Shows the host-styled menu for an image held or right-clicked. Resolves
  /// to what the user chose, or null when dismissed.
  Future<ImageMenuChoice?> showImageMenu(
    BuildContext context,
    ImageMenuRequest request,
  );
}
