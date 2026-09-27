import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

void formatHighlightColor(
  EditorState editorState,
  Selection? selection,
  String? color, {
  bool withUpdateSelection = false,
}) {
  editorState.formatDelta(
    selection,
    {AppFlowyRichTextKeys.backgroundColor: color},
    withUpdateSelection: withUpdateSelection,
  );
}

void formatFontColor(
  EditorState editorState,
  Selection? selection,
  String? color, {
  bool withUpdateSelection = false,
}) {
  editorState.formatDelta(
    selection,
    {AppFlowyRichTextKeys.textColor: color},
    withUpdateSelection: withUpdateSelection,
  );
}
