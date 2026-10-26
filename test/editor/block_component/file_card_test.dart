import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

FileViewRequest _f(String n, [String m = '', int s = 0]) =>
    FileViewRequest(src: 'x', name: n, mime: m, sizeBytes: s);

Widget _host(Widget c) => MaterialApp(home: Scaffold(body: Center(child: c)));

void main() {
  group('middleEllipsis', () {
    test('keeps short names whole', () {
      expect(middleEllipsis('report.pdf', 44), 'report.pdf');
    });

    test('keeps the start and the extension of a long name', () {
      final out = middleEllipsis(
          'Quarterly_report_final_v7_reviewed_by_everyone_twice.pdf', 30);
      expect(out.length, lessThanOrEqualTo(30));
      expect(out, startsWith('Quarterly_'));
      expect(out, endsWith('.pdf'));
      expect(out, contains('…'));
    });

    test('a long name with no extension still shortens in the middle', () {
      final out = middleEllipsis('x' * 100, 20);
      expect(out.length, lessThanOrEqualTo(20));
      expect(out, contains('…'));
    });
  });

  test('fileFamilyOf groups by mime and by extension', () {
    expect(fileFamilyOf('application/pdf', 'a'), FileFamily.pdf);
    expect(fileFamilyOf('', 'Budget.XLSX'), FileFamily.sheet);
    expect(fileFamilyOf('', 'a.zip'), FileFamily.archive);
    expect(fileFamilyOf('', 'noext'), FileFamily.other);
  });

  testWidgets('card shows name, detail and a Retry that fires', (t) async {
    var retried = 0;
    await t.pumpWidget(_host(FileCard(
      file: _f('Scan.pdf', 'application/pdf', 3000000),
      status: FileCardStatus(FileCardPhase.failed,
          label: 'Could not read', onRetry: () => retried++),
      onMore: () {},
    )));
    expect(find.text('Scan.pdf'), findsOneWidget);
    expect(find.text('PDF · 3.0 MB'), findsOneWidget);
    expect(find.text('Could not read'), findsOneWidget);
    await t.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('hostile name and 3x text do not overflow', (t) async {
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3)),
        child: Scaffold(
          body: SizedBox(
            width: 320,
            child: FileCard(
              file: _f('${'long' * 40}.docx', '', 150000000),
              status: const FileCardStatus(FileCardPhase.localOnly,
                  label: 'Stays on this device'),
              onMore: () {},
            ),
          ),
        ),
      ),
    ));
    expect(tester(t), isNull);
  });
}

Object? tester(WidgetTester t) => t.takeException();
