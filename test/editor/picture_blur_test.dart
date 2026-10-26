import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/image_block_component/resizable_image.dart';
import 'package:provider/provider.dart';

// A 1x1 transparent PNG.
final Uint8List _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, //
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F, 0x00, 0x05, 0xFE, 0x02,
  0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
]);

class _Loader extends AttachmentImageLoader {
  _Loader(this.verdict);

  final Future<bool> Function() verdict;
  final List<String> revealed = [];
  int asked = 0;

  @override
  String? attachmentIdFromSrc(String src) =>
      src.startsWith('att:') ? src.substring(4) : null;

  @override
  Future<Uint8List> loadAttachment(String attachmentId) async => _png;

  @override
  Future<bool> shouldBlur(String attachmentId) {
    asked++;
    return verdict();
  }

  @override
  void onPictureRevealed(String attachmentId) => revealed.add(attachmentId);
}

Widget _host(_Loader loader, {String src = 'att:one'}) {
  return MaterialApp(
    home: Scaffold(
      body: Provider<AttachmentImageLoader>.value(
        value: loader,
        child: Provider<RemoteImagePolicy>.value(
          value: const RemoteImagePolicy(
            allowed: false,
            blockedLabel: 'x',
            hiddenPictureLabel: 'Hidden (test)',
          ),
          child: Center(
            child: ResizableImage(
              alignment: Alignment.center,
              editable: false,
              onResize: (_) {},
              width: 200,
              src: src,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const hidden = Key('hidden_picture');

  testWidgets('a picture the host says to blur shows hidden until tapped',
      (tester) async {
    final loader = _Loader(() async => true);
    await tester.pumpWidget(_host(loader));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(hidden), findsOneWidget);
    expect(find.text('Hidden (test)'), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);

    await tester.tap(find.byKey(hidden));
    await tester.pump();
    expect(find.byKey(hidden), findsNothing);
    expect(loader.revealed, ['one']);
  });

  testWidgets('a picture the host clears is shown straight away',
      (tester) async {
    final loader = _Loader(() async => false);
    await tester.pumpWidget(_host(loader));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(hidden), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('nothing of the picture is painted while the host is checking',
      (tester) async {
    final gate = Completer<bool>();
    final loader = _Loader(() => gate.future);
    await tester.pumpWidget(_host(loader));
    await tester.pump();
    expect(find.byKey(hidden), findsNothing);
    expect(find.byType(Image), findsNothing);
    gate.complete(true);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(hidden), findsOneWidget);
  });

  testWidgets('a host that throws is treated as blur (fails closed)',
      (tester) async {
    final loader = _Loader(() async => throw StateError('boom'));
    await tester.pumpWidget(_host(loader));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(hidden), findsOneWidget);
  });

  testWidgets('a hidden picture does not open full screen', (tester) async {
    final loader = _Loader(() async => true);
    await tester.pumpWidget(_host(loader));
    await tester.pump();
    await tester.pump();
    final state =
        tester.state<ResizableImageState>(find.byType(ResizableImage));
    expect(state.viewerProvider, isNull);
    await tester.tap(find.byKey(hidden));
    await tester.pump();
    expect(state.viewerProvider, isNotNull);
  });

  testWidgets('a picture that is not a host attachment is never asked about',
      (tester) async {
    final loader = _Loader(() async => true);
    await tester.pumpWidget(_host(loader, src: 'https://x.example/a.png'));
    await tester.pump();
    expect(loader.asked, 0);
  });
}
