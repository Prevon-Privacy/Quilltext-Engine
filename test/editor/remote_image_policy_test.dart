import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/image_block_component/resizable_image.dart';
import 'package:provider/provider.dart';

Widget _host({RemoteImagePolicy? policy}) {
  Widget image = ResizableImage(
    alignment: Alignment.center,
    editable: false,
    onResize: (_) {},
    width: 200,
    src: 'https://tracker.example/pixel.png?note=secret',
  );
  if (policy != null) {
    image = Provider<RemoteImagePolicy>.value(value: policy, child: image);
  }
  return MaterialApp(home: Scaffold(body: Center(child: image)));
}

void main() {
  group('remote images are blocked by default', () {
    testWidgets('with no policy provider, no network image is built',
        (tester) async {
      await tester.pumpWidget(_host());
      expect(find.byKey(const Key('blocked_remote_image')), findsOneWidget);
      expect(find.byType(Image), findsNothing,
          reason: 'an Image.network must not exist, so nothing is fetched');
    });

    testWidgets('a policy that disallows them also blocks', (tester) async {
      await tester.pumpWidget(_host(
          policy: const RemoteImagePolicy(
              allowed: false, blockedLabel: 'Blocked (test)')));
      expect(find.text('Blocked (test)'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('tapping the placeholder loads just that image',
        (tester) async {
      await tester.pumpWidget(_host(
          policy: const RemoteImagePolicy(
              allowed: false, blockedLabel: 'Blocked (test)')));
      await tester.tap(find.byKey(const Key('blocked_remote_image')));
      await tester.pump();
      expect(find.byKey(const Key('blocked_remote_image')), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('an allowing policy builds the network image directly',
        (tester) async {
      await tester.pumpWidget(_host(
          policy: const RemoteImagePolicy(allowed: true, blockedLabel: 'x')));
      expect(find.byKey(const Key('blocked_remote_image')), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
