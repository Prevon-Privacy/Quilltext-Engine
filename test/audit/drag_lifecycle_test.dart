// Block drag lifecycle: every end path (drop, cancel, dispose mid-drag, block
// removed mid-drag) ends the session exactly once and never loses the block.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:provider/provider.dart';

Future<EditorState> pump(WidgetTester tester) async {
  final s = EditorState(
      document: Document.blank()
        ..insert([
          0
        ], [
          paragraphNode(text: 'mover'),
          paragraphNode(text: 'two'),
          paragraphNode(text: 'tail'),
        ]));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AppFlowyEditor(
        editorState: s,
        blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
        editorStyle: EditorStyle.desktop(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return s;
}

Offset low(EditorState s, Path p) {
  final box =
      s.getNodeAtPath(p)!.key.currentContext!.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset(40, box.size.height * 0.9));
}

List<String?> texts(EditorState s) =>
    [for (final n in s.document.root.children) n.delta?.toPlainText()];

void main() {
  testWidgets('owner disposed mid-drag: block still lands, nothing left over',
      (tester) async {
    final s = await pump(tester);
    final session = BlockReorderSession(s, s.getNodeAtPath([0])!)..start();
    session.update(low(s, [2]));
    expect(reorderDraggingNode.value, isNotNull);
    session.dispose(); // the row was unmounted; Flutter's callbacks are dead
    expect(reorderDraggingNode.value, isNull);
    expect(session.active, isFalse);
    await tester.pump();
    await tester.pump();
    expect(texts(s), ['two', 'tail', 'mover']);
    session.dispose();
    session.finish(dropped: true);
    await tester.pump();
    expect(texts(s), ['two', 'tail', 'mover'], reason: 'commits exactly once');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('drop then cancel report moves the block once', (tester) async {
    final s = await pump(tester);
    final session = BlockReorderSession(s, s.getNodeAtPath([0])!)..start();
    session.update(low(s, [2]));
    session.finish(dropped: true);
    session.finish(dropped: true);
    session.finish(dropped: false);
    await tester.pump();
    expect(texts(s), ['two', 'tail', 'mover']);
    expect(reorderDraggingNode.value, isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('block removed mid-drag: no crash, no move, state cleared',
      (tester) async {
    final s = await pump(tester);
    final mover = s.getNodeAtPath([0])!;
    final session = BlockReorderSession(s, mover)..start();
    session.update(low(s, [2]));
    s.apply(s.transaction..deleteNode(mover));
    await tester.pumpAndSettle();
    session.finish(dropped: true);
    await tester.pump();
    expect(texts(s), ['two', 'tail']);
    expect(reorderDraggingNode.value, isNull);
  });

  testWidgets('removed mid-drag then owner disposed: still clean',
      (tester) async {
    final s = await pump(tester);
    final mover = s.getNodeAtPath([0])!;
    final session = BlockReorderSession(s, mover)..start();
    session.update(low(s, [2]));
    s.apply(s.transaction..deleteNode(mover));
    await tester.pumpAndSettle();
    session.dispose();
    await tester.pump();
    await tester.pump();
    expect(texts(s), ['two', 'tail']);
    expect(reorderDraggingNode.value, isNull);
  });

  testWidgets(
      'group session (todo divider) disposed mid-drag calls onDrop once',
      (tester) async {
    final s = await pump(tester);
    final drops = <int>[];
    final session =
        BlockReorderSession(s, s.getNodeAtPath([0])!, onDrop: drops.add)
          ..start();
    session.update(low(s, [2]));
    session.dispose();
    session.dispose();
    await tester.pump();
    await tester.pump();
    expect(drops, [3]);
    expect(reorderDraggingNode.value, isNull);
  });

  testWidgets('removed mid-drag, drop would cross parents: no throw, no move',
      (tester) async {
    final s = EditorState(
        document: Document.blank()
          ..insert([
            0
          ], [
            bulletedListNode(
                text: 'A', children: [bulletedListNode(text: 'x')]),
            paragraphNode(text: 'm'),
          ]));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppFlowyEditor(
          editorState: s,
          blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
          editorStyle: EditorStyle.desktop(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final mover = s.getNodeAtPath([1])!;
    final session = BlockReorderSession(s, mover)..start();
    session.update(low(s, [0]));
    s.apply(s.transaction..deleteNode(mover));
    await tester.pumpAndSettle();
    session.finish(dropped: true);
    await tester.pump();
    expect(s.document.root.children.length, 1);
    expect(s.getNodeAtPath([0])!.children.length, 1);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('desktop grip unmounted mid-drag: release still lands the block',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final s = await pump(tester);
    final host = ValueNotifier<bool>(true);
    final actions = _Actions();
    await tester.pumpWidget(MaterialApp(
      home: Provider<EditorState>.value(
        value: s,
        child: Scaffold(
          body: Stack(children: [
            AppFlowyEditor(
              editorState: s,
              blockComponentBuilders: buildStandardBlockComponentBuilderMap(),
              editorStyle: EditorStyle.desktop(),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: host,
              builder: (_, on, __) => on
                  ? Positioned(
                      left: 0,
                      top: 300,
                      child: BlockHoverActionHandle(
                          node: s.getNodeAtPath([0])!, state: actions))
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final g = await tester
        .startGesture(tester.getCenter(find.byIcon(Icons.drag_indicator)));
    await g.moveBy(const Offset(0, 5));
    await tester.pump();
    await g.moveTo(low(s, [2]));
    await tester.pump();
    expect(reorderDraggingNode.value, isNotNull);
    host.value = false; // the row (and its grip) goes away mid-drag
    await tester.pump();
    await g.up();
    await tester.pump();
    await tester.pump();
    expect(reorderDraggingNode.value, isNull);
    expect(texts(s), ['two', 'tail', 'mover']);
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
  });
}

class _Actions implements BlockComponentActionState {
  @override
  set alwaysShowActions(bool v) {}
}
