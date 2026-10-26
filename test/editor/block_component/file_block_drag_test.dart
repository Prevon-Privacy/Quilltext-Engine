import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:provider/provider.dart';

class _Actions implements FileActions {
  int opened = 0;
  int menus = 0;

  @override
  Future<void> openFile(BuildContext context, FileViewRequest request) async =>
      opened++;

  @override
  Future<void> saveFile(BuildContext context, FileViewRequest request) async {}

  @override
  Future<FileMenuChoice?> showFileMenu(
    BuildContext context,
    FileMenuRequest request,
  ) async {
    menus++;
    return null;
  }
}

Future<(_Actions, EditorState)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final actions = _Actions();
  final state = EditorState(
    document: Document.blank()
      ..insert([
        0
      ], [
        paragraphNode(text: 'first'),
        fileNode(url: 'pie-att://v1/abc', name: 'Report.pdf', size: 2400),
        paragraphNode(text: 'second'),
        paragraphNode(text: 'third'),
      ]),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Provider<FileActions>.value(
          value: actions,
          child: AppFlowyEditor(editorState: state),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  return (actions, state);
}

List<String> _types(EditorState s) =>
    s.document.root.children.map((n) => n.type).toList();

void main() {
  group('file block hold and drag', () {
    testWidgets('hold, drag below the last block and drop moves it, one undo',
        (tester) async {
      final (actions, state) = await _pump(tester);
      final g = await tester.startGesture(
        tester.getCenter(find.text('Report.pdf')),
      );
      await tester.pump(const Duration(milliseconds: 700));
      final last = state.getNodeAtPath([3])!.rect;
      final target = Offset(last.center.dx, last.bottom - 2);
      await g.moveTo(target);
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveTo(target + const Offset(0, 1));
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_types(state), ['paragraph', 'paragraph', 'paragraph', 'file']);
      expect(actions.menus, 0, reason: 'a drag must not open the menu');
      expect(actions.opened, 0);

      undoCommand.execute(state);
      await tester.pump();
      expect(_types(state), ['paragraph', 'file', 'paragraph', 'paragraph']);
    });

    testWidgets('hold without moving still opens the menu', (tester) async {
      final (actions, state) = await _pump(tester);
      await tester.longPress(find.text('Report.pdf'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(actions.menus, 1);
      expect(_types(state), ['paragraph', 'file', 'paragraph', 'paragraph']);
    });

    testWidgets('a plain tap still opens the file', (tester) async {
      final (actions, _) = await _pump(tester);
      await tester.tap(find.text('Report.pdf'));
      await tester.pump();
      expect(actions.opened, 1);
      expect(actions.menus, 0);
    });

    testWidgets('a hold that is cancelled leaves the note unchanged',
        (tester) async {
      final (_, state) = await _pump(tester);
      final g = await tester.startGesture(
        tester.getCenter(find.text('Report.pdf')),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await g.moveBy(const Offset(0, 120));
      await tester.pump();
      await g.cancel();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_types(state), ['paragraph', 'file', 'paragraph', 'paragraph']);
      expect(tester.takeException(), isNull);
    });
  });
}
