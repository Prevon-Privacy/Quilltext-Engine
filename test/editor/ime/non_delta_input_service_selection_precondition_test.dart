// DIAGNOSTIC TEST A (test-only; no production code touched).
//
// Question under test: does `NonDeltaTextInputService` + the real `onInsert` /
// `onReplace` impls silently no-op when `editorState.selection == null`, even
// though the service reports the value as applied?
//
// This drives the service exactly the way the real platform IME does: attach()
// a starting value, then updateEditingValue() with the next value. The service
// callbacks are wired to the REAL onInsert/onReplace implementations, bound to
// a real headless EditorState, so a null-selection early-return inside those
// impls is observable as "callback fired, document unchanged".

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/ime/delta_input_impl.dart';
import 'package:prevon_quilltext_engine/src/editor/editor_component/service/ime/non_delta_input_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorState editorWith(String text) {
    final document = Document.fromJson({
      'document': {
        'type': 'page',
        'children': [
          {
            'type': 'paragraph',
            'data': {
              'delta': [
                {'insert': text},
              ],
            },
          },
        ],
      },
    });
    final editorState = EditorState(document: document);
    editorState.editorStyle = const EditorStyle.desktop();
    return editorState;
  }

  String textOf(EditorState s) =>
      s.getNodeAtPath([0])!.delta!.toPlainText();

  /// Builds a service whose callbacks invoke the REAL onInsert/onReplace impls
  /// against [editorState], recording whether each callback fired.
  _Recorder buildService(EditorState editorState) {
    final r = _Recorder();
    final service = NonDeltaTextInputService(
      onInsert: (insertion) async {
        r.insertFired++;
        r.lastInsert = insertion;
        await onInsert(insertion, editorState, const []);
        return true;
      },
      onDelete: (deletion) async {
        r.deleteFired++;
        return true;
      },
      onReplace: (replacement) async {
        r.replaceFired++;
        r.lastReplace = replacement;
        await onReplace(replacement, editorState, const []);
        return true;
      },
      onNonTextUpdate: (nonText) async {
        r.nonTextFired++;
        return true;
      },
      onPerformAction: (action) async {},
    );
    r.service = service;
    return r;
  }

  group('Test A — NonDeltaTextInputService selection precondition', () {
    test('A1: selection present + formatted insert value -> document changes',
        () async {
      final editorState = editorWith('and');
      editorState.selection =
          Selection.collapsed(Position(path: [0], offset: 3));
      final r = buildService(editorState);
      final service = r.service;

      service.attach(
        const TextEditingValue(
          text: 'and',
          selection: TextSelection.collapsed(offset: 3),
        ),
        const TextInputConfiguration(),
      );
      // ignore: avoid_print
      print('[A1] after attach currentTextEditingValue='
          '${service.currentTextEditingValue}');

      service.updateEditingValue(
        const TextEditingValue(
          text: ' andX',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // ignore: avoid_print
      print('[A1] insertFired=${r.insertFired} replaceFired=${r.replaceFired} '
          'nonTextFired=${r.nonTextFired} '
          'currentTextEditingValue=${service.currentTextEditingValue} '
          'doc="${textOf(editorState)}" selection=${editorState.selection}');

      expect(textOf(editorState), equals('andX'),
          reason: 'A1: with a selection, a formatted insert must reach the doc');
      expect(r.insertFired, equals(1));
    });

    test('A2: selection null + formatted insert value -> silent no-op',
        () async {
      final editorState = editorWith('and');
      // No selection is set — this is the WISP focus-without-selection shape.
      expect(editorState.selection, isNull);
      final r = buildService(editorState);
      final service = r.service;

      service.attach(
        const TextEditingValue(
          text: 'and',
          selection: TextSelection.collapsed(offset: 3),
        ),
        const TextInputConfiguration(),
      );
      service.updateEditingValue(
        const TextEditingValue(
          text: ' andX',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // ignore: avoid_print
      print('[A2] insertFired=${r.insertFired} replaceFired=${r.replaceFired} '
          'nonTextFired=${r.nonTextFired} '
          'currentTextEditingValue=${service.currentTextEditingValue} '
          'doc="${textOf(editorState)}" selection=${editorState.selection}');

      expect(r.insertFired, equals(1),
          reason: 'A2: the service DOES call onInsert…');
      expect(textOf(editorState), equals('and'),
          reason: 'A2: …but onInsert silently no-ops when selection is null');
      // The service already advanced its baseline to the new value, so a naive
      // "did it apply?" check that reads currentTextEditingValue reports true.
      expect(service.currentTextEditingValue?.text, equals(' andX'));
    });

    test('A3: selection null + replacement (append=false WISP shape) -> no-op',
        () async {
      final editorState = editorWith('and');
      expect(editorState.selection, isNull);
      final r = buildService(editorState);
      final service = r.service;

      service.attach(
        const TextEditingValue(
          text: 'and',
          selection: TextSelection.collapsed(offset: 3),
        ),
        const TextInputConfiguration(),
      );
      // Whole-value replacement, as a select-all-then-type would produce.
      service.updateEditingValue(
        const TextEditingValue(
          text: 'xyz',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // ignore: avoid_print
      print('[A3] insertFired=${r.insertFired} replaceFired=${r.replaceFired} '
          'nonTextFired=${r.nonTextFired} doc="${textOf(editorState)}"');

      expect(r.replaceFired + r.insertFired, greaterThan(0),
          reason: 'A3: a replace delta reaches the onReplace/onInsert callback');
      expect(textOf(editorState), equals('and'),
          reason: 'A3: replacement also silently no-ops without a selection');
    });

    test('A4: value-shape probe — UNformatted value diffs the leading space',
        () async {
      final editorState = editorWith('and');
      editorState.selection =
          Selection.collapsed(Position(path: [0], offset: 3));
      final r = buildService(editorState);
      final service = r.service;

      service.attach(
        const TextEditingValue(
          text: 'and',
          selection: TextSelection.collapsed(offset: 3),
        ),
        const TextInputConfiguration(),
      );
      // Same logical insert, but WITHOUT the service's leading-space format.
      service.updateEditingValue(
        const TextEditingValue(
          text: 'andX',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // ignore: avoid_print
      print('[A4] insertFired=${r.insertFired} replaceFired=${r.replaceFired} '
          'nonTextFired=${r.nonTextFired} '
          'lastReplace=${r.lastReplace} '
          'doc="${textOf(editorState)}"');

      // Record the shape; do not assert a document outcome (that is the point
      // of the probe). Just require the pipeline to have been exercised.
      expect(r.insertFired + r.replaceFired + r.nonTextFired, greaterThan(0));
    });
  });
}

class _Recorder {
  late NonDeltaTextInputService service;
  int insertFired = 0;
  int replaceFired = 0;
  int deleteFired = 0;
  int nonTextFired = 0;
  TextEditingDeltaInsertion? lastInsert;
  TextEditingDeltaReplacement? lastReplace;
}
