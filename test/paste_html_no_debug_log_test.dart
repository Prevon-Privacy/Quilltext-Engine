import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pasteHTML never logs the pasted HTML (plaintext clipboard)', () {
    final src = File(
            'lib/src/service/internal_key_event_handlers/copy_paste_handler.dart')
        .readAsStringSync();
    expect(src.contains('paste html'), isFalse);
  });
}
