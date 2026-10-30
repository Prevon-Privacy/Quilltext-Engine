import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/image_block_component/image_source.dart';

// L09-001 poc shape: an image src of /dev/zero must be refused, not read.
void main() {
  test('character device /dev/zero is refused promptly', () async {
    if (!File('/dev/zero').existsSync()) return;
    await expectLater(
      readLocalImageBounded('/dev/zero').timeout(const Duration(seconds: 5)),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('regular file over the cap is refused, under the cap is read',
      () async {
    final dir = Directory.systemTemp.createTempSync('l09_img_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/a.bin')..writeAsBytesSync(List.filled(100, 1));
    expect((await readLocalImageBounded(f.path, maxBytes: 100)).length, 100);
    await expectLater(readLocalImageBounded(f.path, maxBytes: 99),
        throwsA(isA<FileSystemException>()));
  });
}
