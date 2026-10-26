// In-app "app link" navigation — a link run that opens a PAGE or SETTING of the
// host app (a settings page, Recents, ...) instead of a note/folder.
//
// Same decoupling as [NoteLinkNavigator]: the fork only knows an opaque target
// string stored under `AppFlowyRichTextKeys.appLink`; the host app owns the
// vocabulary of targets and what each one opens.
//
// It is a SEPARATE interface (not a method on NoteLinkNavigator) so existing
// NoteLinkNavigator implementers keep compiling. The host's navigator
// implements both; the fork checks `navigator is AppLinkNavigator` and renders
// an app link as plain text when the host's navigator cannot open one.

import 'package:flutter/widgets.dart';

abstract interface class AppLinkNavigator {
  /// Opens the page/setting named by [target] (the stored attribute value).
  /// Must be navigation-only (never perform an action) and must tolerate a
  /// target it does not know: notes outlive app versions.
  void openApp(BuildContext context, String target);
}
