import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Visual affordance for note/folder link runs: semibold primary text, no
/// underline (PRE2-1321). The rounded, bordered "chip" box itself is painted
/// behind the text by `NoteLinkBoxPainter` (appflowy_rich_text.dart), because
/// a TextStyle background can only be a square, borderless rectangle. Stays a
/// plain styled TextSpan, not a WidgetSpan, so text offsets, selection and
/// copy/paste are unaffected.
TextStyle noteLinkTextStyle(BuildContext context, TextStyle? base) {
  final primary = Theme.of(context).colorScheme.primary;
  return (base ?? const TextStyle()).copyWith(
    color: primary,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.none,
  );
}

/// Support Desktop and Web platform
///   - customize the href text span
TextSpan defaultTextSpanDecoratorForAttribute(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
) {
  final attributes = text.attributes;
  if (attributes == null) {
    return before;
  }
  // In-note note/folder link (the [[ … ]] picker, or "Link to note" toolbar
  // action) — independent of the existing href branch below. Resolved via an
  // abstract NoteLinkNavigator that the host app provides via
  // Provider<NoteLinkNavigator> above the AppFlowyEditor, so this fork stays
  // app-layer-clean (no upward import).
  final noteLinkId = attributes[AppFlowyRichTextKeys.noteLink] as String?;
  final folderLinkId = attributes[AppFlowyRichTextKeys.folderLink] as String?;
  final appLinkTarget = attributes[AppFlowyRichTextKeys.appLink] as String?;
  if (appLinkTarget != null && noteLinkId == null && folderLinkId == null) {
    NoteLinkNavigator? navigator;
    try {
      navigator = context.read<NoteLinkNavigator>();
    } on ProviderNotFoundException {
      navigator = null;
    }
    // A host whose navigator cannot open app links shows plain text.
    if (navigator is! AppLinkNavigator) return before;
    final AppLinkNavigator appNavigator = navigator as AppLinkNavigator;
    return TextSpan(
      style: noteLinkTextStyle(context, before.style),
      text: text.text,
      recognizer: TapGestureRecognizer()
        ..onTap = () => appNavigator.openApp(context, appLinkTarget),
      mouseCursor: SystemMouseCursors.click,
    );
  }
  if (noteLinkId != null || folderLinkId != null) {
    // Not every AppFlowyEditor host wires Provider<NoteLinkNavigator> (e.g.
    // a surface that only reads/displays notes rather than editing them with
    // the [[ picker enabled). Degrade to plain, non-interactive text instead
    // of throwing ProviderNotFoundException on render.
    NoteLinkNavigator? navigator;
    try {
      navigator = context.read<NoteLinkNavigator>();
    } on ProviderNotFoundException {
      navigator = null;
    }
    if (navigator == null) {
      return before;
    }
    final resolvedNavigator = navigator;
    final tapGestureRecognizer = TapGestureRecognizer()
      ..onTap = () => noteLinkId != null
          ? resolvedNavigator.openNote(context, noteLinkId)
          : resolvedNavigator.openFolder(context, folderLinkId!);
    return TextSpan(
      style: noteLinkTextStyle(context, before.style),
      text: text.text,
      recognizer: tapGestureRecognizer,
      mouseCursor: SystemMouseCursors.click,
    );
  }
  // Web links open from the selection layer (openNoteLinkAtPosition: tap
  // opens, right-click offers "Remove link"); a span recognizer here would
  // launch twice.
  if (attributes[AppFlowyRichTextKeys.href] != null) {
    return TextSpan(
      style: before.style,
      text: text.text,
      mouseCursor: SystemMouseCursors.click,
    );
  }
  return before;
}
