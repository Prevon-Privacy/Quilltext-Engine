import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/style/default_text_span_decorator_for_attribute.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/style/mobile_text_span_decorator_for_attribute.dart';
import 'package:provider/provider.dart';

class _Nav implements NoteLinkNavigator {
  @override
  void openFolder(BuildContext context, String folderId) {}
  @override
  void openNote(BuildContext context, String noteId) {}
}

typedef _Decorator = TextSpan Function(
    BuildContext, Node, int, TextInsert, TextSpan, TextSpan);

void main() {
  final cases = <String, _Decorator>{
    'desktop': defaultTextSpanDecoratorForAttribute,
    'mobile': mobileTextSpanDecoratorForAttribute,
  };
  for (final entry in cases.entries) {
    for (final key in [
      AppFlowyRichTextKeys.noteLink,
      AppFlowyRichTextKeys.folderLink,
    ]) {
      testWidgets('${entry.key} decorator styles $key run', (tester) async {
        final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
        TextSpan? result;
        final editorState = EditorState.blank();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: MultiProvider(
              providers: [
                Provider<EditorState>.value(value: editorState),
                Provider<NoteLinkNavigator>.value(value: _Nav()),
              ],
              child: Builder(builder: (context) {
                final text = TextInsert('link', attributes: {key: 'id-1'});
                const before =
                    TextSpan(text: 'link', style: TextStyle(fontSize: 17));
                result = entry.value(
                    context, Node(type: 'paragraph'), 0, text, before, before);
                return const SizedBox();
              }),
            ),
          ),
        );
        expect(result!.style!.color, scheme.primary);
        // Note/folder links are drawn as a painted chip behind the text
        // (NoteLinkBoxPainter), bold and with no underline by design, see
        // noteLinkTextStyle; the old underline assertion was stale.
        expect(result!.style!.decoration, TextDecoration.none);
        expect(result!.style!.fontWeight, FontWeight.w600);
        expect(result!.style!.fontSize, 17);
        expect(result!.recognizer, isNotNull);
      });
    }
  }
}
