import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';
import 'package:provider/provider.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

class _FakeActions implements ImageActions {
  final opened = <ImageViewRequest>[];
  final menus = <ImageMenuRequest>[];
  ImageMenuChoice? answer;

  @override
  void openImage(BuildContext context, ImageViewRequest request) =>
      opened.add(request);

  @override
  Future<ImageMenuChoice?> showImageMenu(
    BuildContext context,
    ImageMenuRequest request,
  ) async {
    menus.add(request);
    return answer;
  }
}

Future<(_FakeActions?, EditorState)> _pump(
  WidgetTester tester, {
  bool withActions = true,
  double imageWidth = 211,
  List<Node>? nodes,
  bool editable = true,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final actions = withActions ? _FakeActions() : null;
  final state = EditorState(
    document: Document.blank()
      ..insert(
        [0],
        nodes ??
            [
              paragraphNode(text: 'before'),
              imageNode(url: _png, width: imageWidth),
              paragraphNode(text: 'after'),
            ],
      ),
  );
  Widget editor = AppFlowyEditor(editorState: state, editable: editable);
  if (actions != null) {
    editor = Provider<ImageActions>.value(value: actions, child: editor);
  }
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
  await _frames(tester);
  return (actions, state);
}

// The loading spinner animates forever, so pumpAndSettle would never return.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Rect _imageRect(EditorState s, [int index = 1]) {
  final state = s.getNodeAtPath([index])!.selectable;
  return (state as ImageBlockComponentWidgetState).imageGlobalRect!;
}

/// `testWidgets` on [platform]. The override must be back to null before the
/// test body returns (the binding checks it right after), so no tearDown.
void _onPlatform(
  String name,
  TargetPlatform platform,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  // The editor picks its selection service from the HOST operating system
  // (dart:io), not from `debugDefaultTargetPlatformOverride`, so a unit test
  // always exercises the desktop service. The phone's service (tap-up and
  // long-press handlers in mobile_selection_service.dart) is covered by the
  // live WISP check, not here.
  for (final platform in [TargetPlatform.macOS]) {
    const desktop = true;
    group('on $platform', () {
      void testWidgets(String name, Future<void> Function(WidgetTester) body) =>
          _onPlatform(name, platform, body);

      testWidgets('a tap on the picture opens it full screen', (tester) async {
        final (actions, state) = await _pump(tester);
        await tester.tapAt(_imageRect(state).center);
        await _frames(tester);
        expect(actions!.opened, hasLength(1));
        expect(actions.opened.single.items, hasLength(1));
        expect(actions.opened.single.initialIndex, 0);
      });

      testWidgets('a tap beside a narrow picture does not', (tester) async {
        final (actions, state) = await _pump(tester);
        final r = _imageRect(state);
        await tester.tapAt(Offset(r.left - 40, r.center.dy));
        await _frames(tester);
        expect(actions!.opened, isEmpty);
      });

      testWidgets('a tap with no host actions just selects', (tester) async {
        final (_, state) = await _pump(tester, withActions: false);
        await tester.tapAt(_imageRect(state).center);
        await _frames(tester);
        expect(state.selection?.start.path, [1]);
      });

      testWidgets('opens at the tapped picture among several', (tester) async {
        final (actions, state) = await _pump(
          tester,
          nodes: [
            imageNode(url: _png, width: 100),
            paragraphNode(text: 'mid'),
            imageNode(url: _png, width: 100),
          ],
        );
        await tester.tapAt(_imageRect(state, 2).center);
        await _frames(tester);
        final req = actions!.opened.single;
        expect(req.items, hasLength(2));
        expect(req.initialIndex, 1);
      });

      testWidgets('a held picture shows the menu with its current state',
          (tester) async {
        final (actions, state) = await _pump(tester);
        if (desktop) {
          final g = await tester.startGesture(
            _imageRect(state).center,
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await g.up();
        } else {
          await tester.longPressAt(_imageRect(state).center);
        }
        await _frames(tester);
        expect(actions!.menus, hasLength(1));
        final m = actions.menus.single;
        expect(m.editable, isTrue);
        expect(m.align, 'center');
        expect(m.canMoveUp, isTrue);
        expect(m.canMoveDown, isTrue);
        expect(m.canOpen, isTrue);
        expect(m.size, isNull, reason: '200 of 900 is a custom size');
        expect(state.selection?.start.path, [1], reason: 'block is selected');
      });

      testWidgets('menu choices edit the note', (tester) async {
        final (actions, state) = await _pump(tester);
        var at = 1;
        Future<void> hold() async {
          if (desktop) {
            final g = await tester.startGesture(
              _imageRect(state, at).center,
              kind: PointerDeviceKind.mouse,
              buttons: kSecondaryMouseButton,
            );
            await g.up();
          } else {
            await tester.longPressAt(_imageRect(state, at).center);
          }
          await _frames(tester);
        }

        actions!.answer = ImageMenuChoice.alignRight;
        await hold();
        expect(state.getNodeAtPath([1])!.attributes['align'], 'right');

        actions.answer = ImageMenuChoice.sizeMedium;
        await hold();
        final w = state.getNodeAtPath([1])!.attributes['width'] as double;
        final avail =
            (state.getNodeAtPath([1])!.selectable as ImageBlockComponentWidgetState)
                .availableWidth;
        expect(w, (avail / 2).roundToDouble());

        actions.answer = ImageMenuChoice.sizeFull;
        await hold();
        expect(state.getNodeAtPath([1])!.attributes['width'], isNull);

        actions.answer = ImageMenuChoice.moveDown;
        await hold();
        expect(state.getNodeAtPath([2])!.type, 'image');
        at = 2;

        actions.answer = ImageMenuChoice.remove;
        await hold();
        expect(
          [for (final n in state.document.root.children) n.type],
          ['paragraph', 'paragraph'],
        );
      });

      testWidgets('a read-only note reports itself and cannot be edited',
          (tester) async {
        final (actions, state) = await _pump(tester, editable: false);
        if (desktop) {
          final g = await tester.startGesture(
            _imageRect(state).center,
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await g.up();
        } else {
          await tester.longPressAt(_imageRect(state).center);
        }
        await _frames(tester);
        expect(actions!.menus.single.editable, isFalse);
      });
    });
  }

  group('desktop grips', () {
  _onPlatform('pressing a resize grip does not open the viewer',
      TargetPlatform.macOS, (tester) async {
    final (actions, state) = await _pump(tester, imageWidth: 400);
    final r = _imageRect(state);
    await tester.tapAt(Offset(r.left + 10, r.center.dy), kind: PointerDeviceKind.mouse);
    await _frames(tester);
    expect(actions!.opened, isEmpty);
    await tester.tapAt(r.center, kind: PointerDeviceKind.mouse);
    await _frames(tester);
    expect(actions.opened, hasLength(1));
  });
  });

  // The phone's own selection service: tap-up, long-press lift, menu.
  group('phone', () {
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

    Future<TestGesture> hold(
      WidgetTester tester,
      Offset at,
    ) async {
      final g = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 700));
      return g;
    }

    phoneTest('a tap on the picture opens it full screen', (tester) async {
      final (actions, state) = await _pump(tester);
      await tester.tapAt(_imageRect(state).center);
      await _frames(tester);
      expect(actions!.opened, hasLength(1));
    });

    phoneTest('a tap on an already selected picture still opens it',
        (tester) async {
      final (actions, state) = await _pump(tester);
      await tester.tapAt(_imageRect(state).center);
      await _frames(tester);
      await tester.tapAt(_imageRect(state).center);
      await _frames(tester);
      expect(actions!.opened, hasLength(2));
    });

    phoneTest('holding without moving opens the menu', (tester) async {
      final (actions, state) = await _pump(tester);
      final g = await hold(tester, _imageRect(state).center);
      expect(actions!.menus, isEmpty, reason: 'only when the finger lifts');
      await g.up();
      await _frames(tester);
      expect(actions.menus, hasLength(1));
      expect(actions.menus.single.canMoveUp, isTrue);
    });

    phoneTest('holding and dragging down moves the picture', (tester) async {
      final (actions, state) = await _pump(tester);
      final start = _imageRect(state).center;
      final g = await hold(tester, start);
      for (var i = 1; i <= 12; i++) {
        await g.moveTo(start + Offset(0, 25.0 * i));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await g.up();
      await _frames(tester);
      expect(actions!.menus, isEmpty, reason: 'a drag is not a menu request');
      expect(
        [for (final n in state.document.root.children) n.type],
        ['paragraph', 'paragraph', 'image'],
      );
      expect(state.selection?.start.path, [2]);
    });

    phoneTest('holding and dragging up moves it the other way',
        (tester) async {
      final (actions, state) = await _pump(tester);
      final start = _imageRect(state).center;
      final g = await hold(tester, start);
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(start - Offset(0, 30.0 * i));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await g.up();
      await _frames(tester);
      expect(
        [for (final n in state.document.root.children) n.type],
        ['image', 'paragraph', 'paragraph'],
      );
    });

    phoneTest('a read-only note still gets the menu on hold', (tester) async {
      final (actions, state) = await _pump(tester, editable: false);
      await tester.longPressAt(_imageRect(state).center);
      await _frames(tester);
      expect(actions!.menus.single.editable, isFalse);
    });

    phoneTest('with no host actions a hold does nothing to the picture',
        (tester) async {
      final (_, state) = await _pump(tester, withActions: false);
      await tester.longPressAt(_imageRect(state).center);
      await _frames(tester);
      expect(
        [for (final n in state.document.root.children) n.type],
        ['paragraph', 'image', 'paragraph'],
      );
    });
  });
}
