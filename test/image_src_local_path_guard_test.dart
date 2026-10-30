import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/image_block_component/image_source.dart';

void main() {
  test('UNC, device, file-host and scheme sources are refused', () {
    for (final s in [
      r'\\attacker\share\x.png',
      '//host/share/x.png',
      r'\\?\UNC\host\share\x.png',
      r'\\.\pipe\x',
      r'\/host/x.png',
      'file://host/share/x.png',
      'file:///etc/x.png',
      'smb://host/x.png',
      'relative/x.png',
      '/a/../etc/x.png',
      '/a/\u0000.png',
      '',
    ]) {
      expect(isSafeLocalImagePath(s), isFalse, reason: s);
    }
  });

  test('plain absolute local paths are accepted', () {
    for (final s in [
      '/data/user/0/app/x.png',
      r'C:\Users\a\x.png',
      'D:/p/x.png'
    ]) {
      expect(isSafeLocalImagePath(s), isTrue, reason: s);
    }
  });

  test(
      'resolveImageProvider: unsafe path gives null, safe path a provider, remote policy unchanged',
      () {
    expect(
        resolveImageProvider(r'\\h\s\x.png', loader: null, allowRemote: true),
        isNull);
    expect(resolveImageProvider('//h/s/x.png', loader: null, allowRemote: true),
        isNull);
    expect(resolveImageProvider('/tmp/x.png', loader: null, allowRemote: false),
        isNotNull);
    expect(
        resolveImageProvider('https://example.com/x.png',
            loader: null, allowRemote: false),
        isNull);
    expect(
        resolveImageProvider('https://example.com/x.png',
            loader: null, allowRemote: true),
        isNotNull);
  });

  test(
      'readLocalImageBounded refuses a UNC path before touching the filesystem',
      () async {
    await expectLater(readLocalImageBounded(r'\\h\s\x.png'),
        throwsA(isA<FileSystemException>()));
    await expectLater(readLocalImageBounded('//h/s/x.png'),
        throwsA(isA<FileSystemException>()));
  });
}
