// What a note/folder link looks like — injected by the host app.
//
// Same decoupling as [NoteLinkNavigator] and [LinkEditor]: the fork paints the
// chip and reserves room for the icon; the host knows the target's icon,
// emoji and color (app-layer data the fork may not import). The host's
// navigator implements this too; the fork checks `navigator is LinkTargetLook`
// and falls back to the plain theme-colored chip when it does not.

import 'package:flutter/widgets.dart';

import 'link_editor.dart' show LinkEditKind;

/// Paints a link target's icon (or emoji) into [rect] on [canvas].
typedef LinkIconPainter = void Function(Canvas canvas, Rect rect);

/// The look of one note/folder link's target.
class LinkLook {
  const LinkLook({this.color, required this.paintIcon});

  /// The target's own color, or null to keep the theme's link color.
  final Color? color;

  /// Draws the target's icon. Always set for a note or folder link: a target
  /// with no icon of its own gets the default note/folder glyph, so the room
  /// the fork reserves for it is never empty.
  final LinkIconPainter paintIcon;
}

abstract interface class LinkTargetLook {
  /// Notifies when a look arrives or changes. A separate object, never the
  /// navigator itself: `Provider` refuses to provide a [Listenable].
  Listenable get lookChanges;

  /// The look of the note ([LinkEditKind.note]) or folder
  /// ([LinkEditKind.folder]) named by [target], or null for any other kind.
  ///
  /// Called while the editor builds, so it must answer at once (from a cache,
  /// a placeholder while the target loads) and never notify listeners
  /// synchronously; it notifies once the real look arrives.
  LinkLook? lookFor(BuildContext context, LinkEditKind kind, String target);
}
