import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';
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

  void phoneTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      PlatformExtension.debugMobileOverride = true;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
      } finally {
        PlatformExtension.debugMobileOverride = null;
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Offset textCenter(EditorState s) {
    final box = s.getNodeAtPath([0])!.key.currentContext!.findRenderObject()
        as RenderBox;
    return box.localToGlobal(Offset(4, box.size.height / 2));
  }

  phoneTest('a second tap on a selected picture opens it again',
      (tester) async {
    final (actions, state) = await pump(tester);
    final r =
        (state.getNodeAtPath([1])!.selectable as ImageBlockComponentWidgetState)
            .imageGlobalRect!;
    for (var i = 1; i <= 2; i++) {
      await tester.tapAt(r.center);
      await _frames(tester);
    }
    expect(actions.opened, hasLength(2));
  });

  phoneTest(
      'a slow second tap on a selected picture opens it and nothing throws',
      (tester) async {
    final (actions, state) = await pump(tester);
    final r =
        (state.getNodeAtPath([1])!.selectable as ImageBlockComponentWidgetState)
            .imageGlobalRect!;
    for (var i = 0; i < 2; i++) {
      await tester.tapAt(r.center);
      await _frames(tester);
      // Past the double-tap window on the wall clock the detector uses.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 450)),
      );
    }
    expect(actions.opened, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  phoneTest('a same-spot second tap on text still asks for the keyboard',
      (tester) async {
    final (_, state) = await pump(tester);
    final at = textCenter(state);
    await tester.tapAt(at);
    await _frames(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    // The person dismisses the keyboard; the caret stays where it was.
    state.service.keyboardService!.closeKeyboard();
    final first = state.selection;
    expect(first, isNotNull);
    expect(first!.isCollapsed, isTrue);
    expect(state.getNodeAtPath(first.start.path)!.type, 'paragraph');
    // Count attaches by watching the text input connection.
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, null));
    await tester.tapAt(at);
    await _frames(tester);
    expect(state.selection, first);
    expect(calls, contains('TextInput.show'));
  });
}
