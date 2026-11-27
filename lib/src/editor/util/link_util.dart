import 'package:prevon_quilltext_engine/src/extensions/editor_link_normalizer.dart';
import 'package:string_validator/string_validator.dart';

bool isUri(String text) {
  final lowerText = text.toLowerCase();
  return isURL(text) ||
      isCustomUrL(text) ||
      lowerText.startsWith('mailto:') ||
      lowerText.startsWith('file:');
}

/// return true if the text looks like [xxx://xxx]
bool isCustomUrL(String text) => customUrlRegex.hasMatch(text);

final customUrlRegex =
    RegExp(r'^[a-zA-Z0-9]+:\/\/[^\/\s].*$', caseSensitive: false);

/// The address to store for a link the person typed, or null when it is blank
/// or not an address. Trims, adds `https://` to a bare domain (like the
/// auto-link path) and runs the result through [normalizeEditorLink].
String? normalizeTypedLink(String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty || !isUri(t)) return null;
  final lower = t.toLowerCase();
  final target =
      RegExp('^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(t) ||
              lower.startsWith('mailto:') ||
              lower.startsWith('file:')
          ? t
          : 'https://$t';
  return normalizeEditorLink(target);
}
