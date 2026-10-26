import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:provider/provider.dart';

class _FakeFileActions implements FileActions {
  final opened = <FileViewRequest>[];
  final saved = <FileViewRequest>[];
  final menus = <FileMenuRequest>[];
  FileMenuChoice? answer;

  @override
  Future<void> openFile(BuildContext context, FileViewRequest request) async =>
      opened.add(request);

  @override
  Future<void> saveFile(BuildContext context, FileViewRequest request) async =>
      saved.add(request);

  @override
  Future<FileMenuChoice?> showFileMenu(
    BuildContext context,
    FileMenuRequest request,
  ) async {
    menus.add(request);
    return answer;
  }
}

class _FakeHideHost implements FileAiHideHost {
  final changes = <bool>[];
  VoidCallback? lastUndo;

  @override
  Widget? hiddenBadge(BuildContext context) =>
      const Icon(Icons.shield, key: Key('hidden-badge'));

  @override
  void aiHiddenChanged(BuildContext context,
      {required bool hidden, required VoidCallback undo}) {
    changes.add(hidden);
    lastUndo = undo;
  }
}

Future<(_FakeFileActions?, EditorState)> _pump(
  WidgetTester tester, {
  bool withActions = true,
  FileAiHideHost? hideHost,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final actions = withActions ? _FakeFileActions() : null;
  final state = EditorState(
    document: Document.blank()
      ..insert([
        0
      ], [
        paragraphNode(text: 'before'),
        fileNode(
          url: 'pie-att://v1/abc',
          name: 'Report.pdf',
          mime: 'application/pdf',
          size: 2400000,
        ),
        paragraphNode(text: 'after'),
      ]),
  );
  Widget editor = AppFlowyEditor(editorState: state);
  if (actions != null) {
    editor = Provider<FileActions>.value(value: actions, child: editor);
  }
  if (hideHost != null) {
    editor = Provider<FileAiHideHost>.value(value: hideHost, child: editor);
  }
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
  await tester.pump(const Duration(milliseconds: 200));
  return (actions, state);
}

void main() {
  group('file block', () {
    testWidgets('draws the name, type and size', (tester) async {
      await _pump(tester);
      expect(find.text('Report.pdf'), findsOneWidget);
      expect(find.text('PDF · 2.4 MB'), findsOneWidget);
    });

    testWidgets('a tap opens the file with its opaque reference',
        (tester) async {
      final (actions, _) = await _pump(tester);
      await tester.tap(find.text('Report.pdf'));
      await tester.pump();
      expect(actions!.opened, hasLength(1));
      expect(actions.opened.single.src, 'pie-att://v1/abc');
      expect(actions.opened.single.name, 'Report.pdf');
      expect(actions.opened.single.sizeBytes, 2400000);
    });

    testWidgets('hold opens the menu and Remove deletes the block',
        (tester) async {
      final (actions, state) = await _pump(tester);
      actions!.answer = FileMenuChoice.remove;
      await tester.longPress(find.text('Report.pdf'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(actions.menus, hasLength(1));
      expect(actions.menus.single.canMoveUp, isTrue);
      expect(actions.menus.single.canMoveDown, isTrue);
      expect(state.document.root.children.map((n) => n.type),
          ['paragraph', 'paragraph']);
    });

    testWidgets('hold then Move down swaps it with the next block',
        (tester) async {
      final (actions, state) = await _pump(tester);
      actions!.answer = FileMenuChoice.moveDown;
      await tester.longPress(find.text('Report.pdf'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.document.root.children.map((n) => n.type),
          ['paragraph', 'paragraph', 'file']);
    });

    testWidgets('with no FileActions provider it still draws and a tap is safe',
        (tester) async {
      await _pump(tester, withActions: false);
      expect(find.text('Report.pdf'), findsOneWidget);
      await tester.tap(find.text('Report.pdf'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('insertFileNode', () {
    test('replaces an empty paragraph and keeps the attributes', () async {
      final state = EditorState.blank();
      state.selection = Selection.collapsed(Position(path: [0], offset: 0));
      await state.insertFileNode(
        url: 'pie-att://v1/x',
        name: 'a.txt',
        mime: 'text/plain',
        size: 12,
      );
      final node = state.getNodeAtPath([0])!;
      expect(node.type, FileBlockKeys.type);
      expect(node.attributes[FileBlockKeys.url], 'pie-att://v1/x');
      expect(node.attributes[FileBlockKeys.name], 'a.txt');
      expect(node.attributes[FileBlockKeys.size], 12);
    });
  });

  group('hide from the assistant', () {
    testWidgets(
        'toggle writes the attribute on the block, shows the badge, undo clears it',
        (tester) async {
      final host = _FakeHideHost();
      final (actions, state) = await _pump(tester, hideHost: host);
      final node = state.document.root.children[1];
      expect(node.attributes.containsKey(FileBlockKeys.hiddenFromAi), isFalse);
      expect(find.byKey(const Key('hidden-badge')), findsNothing);

      actions!.answer = FileMenuChoice.toggleAiHidden;
      await tester.longPress(find.text('Report.pdf'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(node.attributes[FileBlockKeys.hiddenFromAi], isTrue);
      expect(host.changes, [true]);
      expect(find.byKey(const Key('hidden-badge')), findsOneWidget);

      host.lastUndo!();
      await tester.pump();
      expect(node.attributes.containsKey(FileBlockKeys.hiddenFromAi), isFalse,
          reason: 'visible is the attribute being absent');
      expect(find.byKey(const Key('hidden-badge')), findsNothing);
      await tester.pump(const Duration(seconds: 2)); // editor debounce timers
    });

    testWidgets('the menu request carries the current state', (tester) async {
      final (actions, state) = await _pump(tester);
      state.document.root.children[1]
          .updateAttributes({FileBlockKeys.hiddenFromAi: true});
      actions!.answer = null;
      await tester.longPress(find.text('Report.pdf'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(actions.menus.single.file.hiddenFromAi, isTrue);
    });
  });

  test('formatFileSize', () {
    expect(formatFileSize(0), '0 B');
    expect(formatFileSize(999), '999 B');
    expect(formatFileSize(1000), '1.0 KB');
    expect(formatFileSize(2400000), '2.4 MB');
    expect(formatFileSize(150000000), '150 MB');
  });
}
