import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:provider/provider.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

class _Actions implements ImageActions {
  final opened = <ImageViewRequest>[];
  @override
  void openImage(BuildContext context, ImageViewRequest request) =>
      opened.add(request);
  @override
  Future<ImageMenuChoice?> showImageMenu(
    BuildContext context,
    ImageMenuRequest request,
  ) async =>
      null;
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<(_Actions, EditorState)> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final actions = _Actions();
    final state = EditorState(
      document: Document.blank()
        ..insert([
          0,
        ], [
          paragraphNode(text: 'before'),
          imageNode(url: _png, width: 211),
          paragraphNode(text: 'after'),
        ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Provider<ImageActions>.value(
            value: actions,
            child: AppFlowyEditor(editorState: state),
          ),
        ),
      ),
    );
    await _frames(tester);
    return (actions, state);
  }

  void desktopTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> doubleClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await _frames(tester);
  }

  desktopTest('a fast second click on a picture opens it again',
      (tester) async {
    final (actions, state) = await pump(tester);
    final r =
        (state.getNodeAtPath([1])!.selectable as ImageBlockComponentWidgetState)
            .imageGlobalRect!;
    await doubleClick(tester, r.center);
    expect(actions.opened, hasLength(2));
    expect(state.selection?.start.path, [1]);
  });

  desktopTest('a double click on text still selects the word', (tester) async {
    final (_, state) = await pump(tester);
    final box = state.getNodeAtPath([0])!.key.currentContext!.findRenderObject()
        as RenderBox;
    await doubleClick(tester, box.localToGlobal(const Offset(4, 8)));
    final s = state.selection!;
    expect(s.start.path, [0]);
    expect(s.isCollapsed, isFalse);
  });
}
