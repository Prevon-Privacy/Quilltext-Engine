import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

extension AttributesDelta on Delta {
  bool everyAttributes(bool Function(Attributes element) test) =>
      whereType<TextInsert>().every((element) {
        final attributes = element.attributes;
        return attributes != null && test(attributes);
      });
}
