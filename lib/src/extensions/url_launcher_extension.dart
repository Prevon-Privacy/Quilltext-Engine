import 'package:flutter/widgets.dart' show BuildContext;
import 'package:url_launcher/url_launcher_string.dart';

/// Schemes a link in a note may never hand to the operating system. A note can
/// come from an import (Keep, Obsidian, Evernote, HTML...) or a share, so its
/// links are untrusted bytes: `javascript:` runs code in a browser, `file:` /
/// `content:` reach other apps' files, `intent:` / `android-app:` start other
/// apps with chosen extras, `data:` / `blob:` smuggle a page past the address
/// check, and the `ms-*` / `search-ms:` handlers on Windows have run code from a
/// link before. Everything else (http, https, mailto, tel, sms, the app's own
/// schemes, a third-party app link the person typed) still opens, behind the
/// host's question.
const Set<String> kBlockedLinkSchemes = {
  'javascript',
  'vbscript',
  'data',
  'blob',
  'file',
  'content',
  'intent',
  'android-app',
  'about',
  'chrome',
  'chrome-extension',
  'ms-msdt',
  'ms-officecmd',
  'ms-appinstaller',
  'ms-settings',
  'search-ms',
  'search',
  'shell',
  'ws',
  'wss',
};

/// Scheme of [href] as the launcher would read it: lower-cased, with the
/// control and whitespace characters a hostile link hides in front of or
/// inside the scheme (`java\u0000script:`, ` JAVASCRIPT:`) removed first, so
/// a scheme can never be smuggled past the check by spelling.
String linkSchemeOf(String href) {
  final cleaned = href.replaceAll(RegExp(r'[\u0000- \u007F- ]'), '');
  final colon = cleaned.indexOf(':');
  if (colon <= 0) return '';
  final scheme = cleaned.substring(0, colon).toLowerCase();
  // A scheme is letters, digits, '+', '-' and '.': anything else means the
  // colon belongs to something else (a port, a Windows drive, a time).
  if (!RegExp(r'^[a-z][a-z0-9+.\-]*$').hasMatch(scheme)) return '';
  return scheme;
}

/// True when [href] must never be launched (see [kBlockedLinkSchemes]).
bool isBlockedLinkScheme(String? href) {
  if (href == null) return false;
  return kBlockedLinkSchemes.contains(linkSchemeOf(href));
}

Future<bool> safeLaunchUrl(String? href, [BuildContext? context]) async {
  if (href == null) {
    return Future.value(false);
  }
  // Untrusted bytes from a note never reach the OS with a code-running or
  // app-starting scheme, whoever calls this (the host gate checks too).
  if (isBlockedLinkScheme(href)) {
    return Future.value(false);
  }
  final uri = Uri.parse(href);
  // url_launcher cannot open a link without scheme.
  final newHref = (uri.scheme.isNotEmpty ? href : 'http://$href').trim();
  // canLaunchUrlString can wrongly say no on desktop; try the launch anyway.
  try {
    await launchUrlString(newHref);
  } catch (_) {}
  return true;
}

/// The one entry for opening a web link from the editor. [context] is the
/// editor widget the link was on, so the host can ask before leaving the app.
Future<bool> Function(String? href, [BuildContext? context]) editorLaunchUrl =
    safeLaunchUrl;
