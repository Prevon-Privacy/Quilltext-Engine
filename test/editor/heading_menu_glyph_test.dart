import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/selection_menu/selection_menu_icon.dart';

void main() {
  // The slash menu icons sit under no Material ancestor; without an explicit
  // decoration Flutter paints its yellow double-underline fallback.
  for (final level in [1, 2, 3]) {
    testWidgets('heading $level glyph has no text decoration', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: headingMenuGlyph(
            level,
            isSelected: false,
            style: SelectionMenuStyle.light,
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('Aa'));
      expect(text.style?.decoration, TextDecoration.none);
    });
  }
}
