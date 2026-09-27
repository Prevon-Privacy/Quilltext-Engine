// Regression guard for the TableConfig borderWidth data-loss bug.
//
// `TableConfig.fromJson` reads a `borderWidth` field, but `toJson` used to
// omit it — so any table persisted with a custom borderWidth silently
// reverted to the class default on the next load. These tests pin the key
// name and the round-trip so the omission cannot return.

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/table_block_component/table_config.dart';

void main() {
  group('TableConfig JSON round-trip', () {
    test('toJson writes the borderWidth key', () {
      final config = TableConfig(borderWidth: 3.5);
      final json = config.toJson();

      // Pin the literal key name `fromJson` reads, so a future key rename on
      // one side fails here rather than silently losing the value again.
      expect(json.containsKey('borderWidth'), isTrue);
      expect(json['borderWidth'], 3.5);
    });

    test('a non-default borderWidth survives toJson -> fromJson unchanged', () {
      final original = TableConfig(borderWidth: 3.5);
      final restored = TableConfig.fromJson(original.toJson());

      expect(restored.borderWidth, 3.5);
    });

    test('all four configurable fields survive the round-trip', () {
      final original = TableConfig(
        colDefaultWidth: 200.0,
        rowDefaultHeight: 48.0,
        colMinimumWidth: 60.0,
        borderWidth: 1.5,
      );
      final restored = TableConfig.fromJson(original.toJson());

      expect(restored.colDefaultWidth, 200.0);
      expect(restored.rowDefaultHeight, 48.0);
      expect(restored.colMinimumWidth, 60.0);
      expect(restored.borderWidth, 1.5);
    });
  });
}
