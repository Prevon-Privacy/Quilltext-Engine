import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/image_block_component/image_source.dart';
import 'package:prevon_quilltext_engine/src/editor/local_image_policy.dart';

void main() {
  late Directory root;
  late Directory outside;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lip_root_');
    outside = Directory.systemTemp.createTempSync('lip_out_');
    File('${root.path}/in.png').writeAsBytesSync([1, 2, 3]);
    File('${outside.path}/secret.png').writeAsBytesSync([9]);
  });
  tearDown(() {
    LocalImagePolicy.resetForTest();
    root.deleteSync(recursive: true);
    outside.deleteSync(recursive: true);
  });

  test('never installed: legacy behaviour (permissive)', () async {
    expect(await readLocalImageBounded('${outside.path}/secret.png'), [9]);
  });

  test('requireRoots with no roots refuses everything', () async {
    LocalImagePolicy.requireRoots();
    await expectLater(readLocalImageBounded('${root.path}/in.png'),
        throwsA(isA<FileSystemException>()));
  });

  test('path inside a root is accepted, outside is refused', () async {
    LocalImagePolicy.setAllowedRoots([root.path]);
    expect(await readLocalImageBounded('${root.path}/in.png'), [1, 2, 3]);
    await expectLater(readLocalImageBounded('${outside.path}/secret.png'),
        throwsA(isA<FileSystemException>()));
    expect(LocalImagePolicy.allowsLexically('${outside.path}/secret.png'),
        isFalse);
  });

  test('a sibling dir sharing the root prefix is refused', () async {
    LocalImagePolicy.setAllowedRoots([root.path]);
    expect(LocalImagePolicy.allowsLexically('${root.path}_evil/x.png'), isFalse);
  });

  test('symlink inside a root pointing outside is refused', () async {
    Link('${root.path}/link.png').createSync('${outside.path}/secret.png');
    LocalImagePolicy.setAllowedRoots([root.path]);
    expect(LocalImagePolicy.allowsLexically('${root.path}/link.png'), isTrue);
    await expectLater(readLocalImageBounded('${root.path}/link.png'),
        throwsA(isA<FileSystemException>()));
  });

  test('relative and .. paths stay refused by the syntax guard', () {
    LocalImagePolicy.setAllowedRoots([root.path]);
    expect(isSafeLocalImagePath('in.png'), isFalse);
    expect(isSafeLocalImagePath('${root.path}/../x.png'), isFalse);
  });

  group('root registered through a symlink (Android /data/user/0, iOS /var)', () {
    late Directory holder;
    late String linkRoot;
    setUp(() {
      holder = Directory.systemTemp.createTempSync('lip_link_');
      linkRoot = '${holder.path}/rootlink';
      Link(linkRoot).createSync(root.path);
      LocalImagePolicy.setAllowedRoots([linkRoot]);
    });
    tearDown(() => holder.deleteSync(recursive: true));

    test('file addressed via the real path and via the symlink both pass',
        () async {
      expect(await readLocalImageBounded('${root.path}/in.png'), [1, 2, 3]);
      expect(await readLocalImageBounded('$linkRoot/in.png'), [1, 2, 3]);
      expect(
          resolveImageProvider('${root.path}/in.png',
              loader: null, allowRemote: false),
          isNotNull);
      expect(LocalImagePolicy.allowsLexically('$linkRoot/in.png'), isTrue);
    });

    test('escapes still fail', () async {
      await expectLater(readLocalImageBounded('${outside.path}/secret.png'),
          throwsA(isA<FileSystemException>()));
      await expectLater(readLocalImageBounded('${root.path}_evil/x.png'),
          throwsA(isA<FileSystemException>()));
      Link('${root.path}/esc.png').createSync('${outside.path}/secret.png');
      await expectLater(readLocalImageBounded('$linkRoot/esc.png'),
          throwsA(isA<FileSystemException>()));
      expect(isSafeLocalImagePath('$linkRoot/../x.png'), isFalse);
      expect(isSafeLocalImagePath('//host/share/x.png'), isFalse);
      expect(isSafeLocalImagePath('in.png'), isFalse);
      expect(
          resolveImageProvider('$linkRoot/../x.png',
              loader: null, allowRemote: false),
          isNull);
    });
  });
}
