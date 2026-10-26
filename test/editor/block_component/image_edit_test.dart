import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

EditorState _doc(List<Node> nodes) {
  return EditorState(document: Document.blank()..insert([0], nodes));
}

Node _para(String t) => paragraphNode(text: t);
Node _img({double? width, String align = 'center', double? height}) =>
    imageNode(url: 'x', width: width, align: align, height: height);

List<String> _types(EditorState s) =>
    [for (final n in s.document.root.children) n.type];

void main() {
  group('setImageWidth', () {
    test('sets the width and clears the height', () {
      final s = _doc([_para('a'), _img(width: 100, height: 80)]);
      final node = s.getNodeAtPath([1])!;
      setImageWidth(s, node, 240);
      expect(node.attributes[ImageBlockKeys.width], 240);
      expect(node.attributes[ImageBlockKeys.height], isNull);
    });

    test('null means fill the page', () {
      final s = _doc([_img(width: 100)]);
      final node = s.getNodeAtPath([0])!;
      setImageWidth(s, node, null);
      expect(node.attributes[ImageBlockKeys.width], isNull);
    });

    test('is one undo step', () {
      final s = _doc([_img(width: 100)]);
      final node = s.getNodeAtPath([0])!;
      setImageWidth(s, node, 240);
      s.undoManager.undo();
      expect(s.getNodeAtPath([0])!.attributes[ImageBlockKeys.width], 100);
    });
  });

  group('setImageWidthFraction', () {
    test('a fraction becomes whole dp of the available width', () {
      final s = _doc([_img()]);
      final node = s.getNodeAtPath([0])!;
      setImageWidthFraction(s, node, fraction: 0.5, available: 333);
      expect(node.attributes[ImageBlockKeys.width], 167);
    });

    test('full width stores null so it keeps following the page', () {
      final s = _doc([_img(width: 100)]);
      final node = s.getNodeAtPath([0])!;
      setImageWidthFraction(s, node, fraction: 1.0, available: 333);
      expect(node.attributes[ImageBlockKeys.width], isNull);
    });

    test('before layout (no width known) falls back to full width', () {
      final s = _doc([_img(width: 100)]);
      final node = s.getNodeAtPath([0])!;
      setImageWidthFraction(s, node, fraction: 0.5, available: 0);
      expect(node.attributes[ImageBlockKeys.width], isNull);
    });
  });

  test('setImageAlign changes only the alignment', () {
    final s = _doc([_img(width: 100)]);
    final node = s.getNodeAtPath([0])!;
    setImageAlign(s, node, 'right');
    expect(node.attributes[ImageBlockKeys.align], 'right');
    expect(node.attributes[ImageBlockKeys.width], 100);
  });

  group('moveImage', () {
    test('up swaps with the block above', () {
      final s = _doc([_para('a'), _img(), _para('b')]);
      expect(moveImage(s, s.getNodeAtPath([1])!, -1), isTrue);
      expect(_types(s), ['image', 'paragraph', 'paragraph']);
    });

    test('down swaps with the block below', () {
      final s = _doc([_para('a'), _img(), _para('b')]);
      expect(moveImage(s, s.getNodeAtPath([1])!, 1), isTrue);
      expect(_types(s), ['paragraph', 'paragraph', 'image']);
      expect(s.getNodeAtPath([1])!.delta!.toPlainText(), 'b');
    });

    test('does nothing at either end', () {
      final s = _doc([_img(), _para('a')]);
      expect(moveImage(s, s.getNodeAtPath([0])!, -1), isFalse);
      final t = _doc([_para('a'), _img()]);
      expect(moveImage(t, t.getNodeAtPath([1])!, 1), isFalse);
      expect(_types(t), ['paragraph', 'image']);
    });

    test('the moved block stays selected at its new place', () {
      final s = _doc([_para('a'), _img(), _para('b')]);
      moveImage(s, s.getNodeAtPath([1])!, 1);
      expect(s.selection!.start.path, [2]);
    });

    test('undo puts it back', () {
      final s = _doc([_para('a'), _img(), _para('b')]);
      moveImage(s, s.getNodeAtPath([1])!, -1);
      s.undoManager.undo();
      expect(_types(s), ['paragraph', 'image', 'paragraph']);
    });
  });

  group('removeImage', () {
    test('removes the block and puts the caret on the next one', () {
      final s = _doc([_para('a'), _img(), _para('b')]);
      removeImage(s, s.getNodeAtPath([1])!);
      expect(_types(s), ['paragraph', 'paragraph']);
      expect(s.selection, Selection.collapsed(Position(path: [1])));
    });

    test('the last block puts the caret at the end of the one before', () {
      final s = _doc([_para('abc'), _img()]);
      removeImage(s, s.getNodeAtPath([1])!);
      expect(_types(s), ['paragraph']);
      expect(
        s.selection,
        Selection.collapsed(Position(path: [0], offset: 3)),
      );
    });

    test('a note that would be empty keeps an empty paragraph', () {
      final s = _doc([_img()]);
      removeImage(s, s.getNodeAtPath([0])!);
      expect(_types(s), ['paragraph']);
      expect(s.selection, Selection.collapsed(Position(path: [0])));
    });

    test('undo brings the picture back', () {
      final s = _doc([_para('a'), _img(width: 90), _para('b')]);
      removeImage(s, s.getNodeAtPath([1])!);
      s.undoManager.undo();
      expect(_types(s), ['paragraph', 'image', 'paragraph']);
      expect(s.getNodeAtPath([1])!.attributes[ImageBlockKeys.width], 90);
    });
  });

  group('ImageSizePreset.match', () {
    test('matches within two dp, else null', () {
      expect(ImageSizePreset.match(200, 400), ImageSizePreset.medium);
      expect(ImageSizePreset.match(201.5, 400), ImageSizePreset.medium);
      expect(ImageSizePreset.match(400, 400), ImageSizePreset.full);
      expect(ImageSizePreset.match(250, 400), isNull);
      expect(ImageSizePreset.match(100, 0), isNull);
    });
  });
}
