// Red-team (2026-10-19): a huge attachment picture is never decoded at full size, inline or full screen.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/src/editor/attachment_image_loader.dart';
import 'dart:convert';

import 'package:prevon_quilltext_engine/src/editor/block_component/image_block_component/attachment_image_provider.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/image_block_component/image_source.dart';

class _Loader implements AttachmentImageLoader {
  _Loader(this.bytes);
  final Uint8List bytes;
  @override
  String? attachmentIdFromSrc(String src) => 'x';
  @override
  Future<Uint8List> loadAttachment(String attachmentId) async => bytes;
}

Future<Uint8List> _realPng(int w, int h) async {
  final r = ui.PictureRecorder();
  ui.Canvas(r)
      .drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint());
  final img = await r.endRecording().toImage(w, h);
  final d = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return d!.buffer.asUint8List();
}

Future<ui.Image> _resolve(ImageProvider p) {
  final s = p.resolve(ImageConfiguration.empty);
  final done = Completer<ui.Image>();
  s.addListener(ImageStreamListener((i, _) => done.complete(i.image),
      onError: (e, _) => done.completeError(e)));
  return done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('boundedDecodeSize', () {
    test('a 100M-pixel header (10000x10000) fits 16M', () {
      final t = boundedDecodeSize(10000, 10000)!;
      expect(t.width * t.height, lessThanOrEqualTo(kAttachmentDecodeMaxPixels));
      expect(t.width, closeTo(4000, 2));
    });
    test('the tallest allowed shape (3334x30000) fits and keeps aspect', () {
      final t = boundedDecodeSize(3334, 30000)!;
      expect(t.width * t.height, lessThanOrEqualTo(kAttachmentDecodeMaxPixels));
      expect(t.height / t.width, closeTo(30000 / 3334, 0.05));
    });
    test('a 1x30000 strip never goes below one pixel', () {
      final t = boundedDecodeSize(30000, 30000, maxPixels: 10)!;
      expect(t.width >= 1 && t.height >= 1, isTrue);
      expect(t.width * t.height, lessThanOrEqualTo(10));
    });
    test('pictures inside the budget are left alone', () {
      expect(boundedDecodeSize(4000, 3000), isNull);
      expect(boundedDecodeSize(0, 5), isNull);
    });
  });

  testWidgets('the provider decodes an over-budget picture at the bounded size',
      (tester) async {
    await tester.runAsync(() async {
      final png = await _realPng(200, 100);
      final img = await _resolve(
          AttachmentImageProvider(_Loader(png), 'a', maxDecodePixels: 5000));
      expect(img.width * img.height, lessThanOrEqualTo(5000));
      expect(img.width, greaterThan(img.height));
      final full = await _resolve(AttachmentImageProvider(_Loader(png), 'b'));
      expect(full.width, 200);
      expect(full.height, 100);
    });
  });

  group('base64 and file-path sources take the same guard', () {
    Uint8List fakePng(int w, int h) {
      // Signature + IHDR declaring w x h, a valid CRC is not needed for the header read to refuse.
      final b = Uint8List(33);
      b.setAll(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      b.setAll(8, const [0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
      b.buffer.asByteData()
        ..setUint32(16, w)
        ..setUint32(20, h);
      b[24] = 8;
      b[25] = 6;
      return b;
    }

    testWidgets('a base64 PNG declaring 100000x100000 is refused', (t) async {
      await t.runAsync(() async {
        final src = base64Encode(fakePng(100000, 100000));
        final p = resolveImageProvider(src, loader: null, allowRemote: false)!;
        expect(p, isA<GuardedBytesImageProvider>());
        await expectLater(_resolve(p), throwsA(anything));
      });
    });

    testWidgets('a normal base64 PNG still renders at full size', (t) async {
      await t.runAsync(() async {
        final src = base64Encode(await _realPng(40, 20));
        final img = await _resolve(
            resolveImageProvider(src, loader: null, allowRemote: false)!);
        expect(img.width, 40);
        expect(img.height, 20);
      });
    });

    testWidgets('a 10000x10000 real PNG decodes bounded', (t) async {
      await t.runAsync(() async {
        final png = await _realPng(10000, 10000);
        final img =
            await _resolve(GuardedBytesImageProvider('big', () async => png));
        expect(img.width * img.height,
            lessThanOrEqualTo(kAttachmentDecodeMaxPixels));
        expect(img.width, img.height);
        final att =
            await _resolve(AttachmentImageProvider(_Loader(png), 'big'));
        expect(att.width * att.height,
            lessThanOrEqualTo(kAttachmentDecodeMaxPixels));
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
