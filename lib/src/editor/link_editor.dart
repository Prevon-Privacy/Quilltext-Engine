// In-editor link rename/edit — injected by the host app.
//
// Same decoupling as [NoteLinkNavigator]: the fork owns the gesture (hold or
// right-click on a link run) and the document edit; the host owns the dialog
// (design-system widgets, localized strings), which the fork may not import.
//
// A separate interface so existing NoteLinkNavigator implementers keep
// compiling. The host's navigator implements both; the fork checks
// `navigator is LinkEditor` and hides the "Edit link" item when it does not.

import 'package:flutter/widgets.dart';

/// What a link run points at.
enum LinkEditKind { web, note, folder, app }

/// What the user picked in the host's hold / right-click link menu. Copying an
/// address is handled inside the host and reports no choice.
enum LinkMenuChoice { open, edit, remove }

/// What the user is editing: the visible [text] of a link run and, for web
/// links only, its [url].
class LinkEditRequest {
  const LinkEditRequest({
    required this.kind,
    required this.text,
    this.url,
    this.target,
  });
  final LinkEditKind kind;
  final String text;

  /// The raw attribute value naming where the link goes (note id, folder id,
  /// app target or the web address). Lets the host describe the destination.
  final String? target;

  /// Non-null only for [LinkEditKind.web].
  final String? url;
}

/// The user's answer. [text] is never empty; [url] is non-null only for web
/// links.
class LinkEditResult {
  const LinkEditResult({required this.text, this.url});
  final String text;
  final String? url;
}

abstract interface class LinkEditor {
  /// Shows the host-styled menu for a link run held or right-clicked.
  /// Resolves to what the user chose, or null when dismissed (or when the
  /// choice, such as copying the address, was fully handled by the host).
  Future<LinkMenuChoice?> showLinkMenu(
    BuildContext context,
    LinkEditRequest request,
  );

  /// Asks the user to rename [request] (and edit its URL when it is a web
  /// link). Resolves to null when dismissed.
  Future<LinkEditResult?> editLink(
    BuildContext context,
    LinkEditRequest request,
  );
}
