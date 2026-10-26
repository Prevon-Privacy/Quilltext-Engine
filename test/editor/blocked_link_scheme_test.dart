// A link inside a note is untrusted (imports, shares). The editor's launcher
// must never hand a code-running or app-starting scheme to the OS, however it
// is spelled, while ordinary links keep working.

import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

void main() {
  test('dangerous schemes are blocked, in any spelling', () {
    const hostile = [
      'javascript:alert(1)',
      'JAVASCRIPT:alert(1)',
      ' javascript:alert(1)',
      'java\u0000script:alert(1)',
      'java\nscript:alert(1)',
      '\u00A0javascript:alert(1)',
      'file:///etc/passwd',
      'file://C:/Windows/system32',
      'content://com.android.providers.media.documents/document/1',
      'intent://scan/#Intent;scheme=zxing;package=com.evil;end',
      'android-app://com.evil',
      'data:text/html,<script>alert(1)</script>',
      'blob:https://x.test/abc',
      'vbscript:MsgBox(1)',
      'ms-msdt:/id PCWDiagnostic /skip force /param "IT_RebrowseForFile=..."',
      'search-ms:query=x&crumb=location:\\\\evil',
      'about:blank',
    ];
    for (final h in hostile) {
      expect(isBlockedLinkScheme(h), isTrue, reason: h);
    }
  });

  test('ordinary links are not blocked', () {
    const fine = [
      'https://prevon.ai',
      'http://example.test/path?q=1',
      'mailto:hi@example.test',
      'tel:+15551234567',
      'sms:+15551234567',
      'prevon://note/abc',
      'pie-note://abc',
      'pie-att://v1/abc',
      'obsidian://open?vault=x',
      'example.test/no-scheme',
      'localhost:8080/x',
      'C:/not/a/scheme',
      '10:30 meeting',
      '',
    ];
    for (final h in fine) {
      expect(isBlockedLinkScheme(h), isFalse, reason: h);
    }
    expect(isBlockedLinkScheme(null), isFalse);
  });

  test('safeLaunchUrl refuses a blocked scheme without touching the launcher',
      () async {
    // No url_launcher platform is registered in a unit test: a real launch
    // attempt would throw inside launchUrlString (swallowed) and return true.
    // A blocked scheme must return false BEFORE that point.
    expect(await safeLaunchUrl('javascript:alert(1)'), isFalse);
    expect(await safeLaunchUrl('intent://x#Intent;end'), isFalse);
  });
}
