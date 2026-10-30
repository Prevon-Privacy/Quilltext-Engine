// F7: one gate-and-launcher decision for note links (R6 item 7).
import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/src/extensions/editor_link_normalizer.dart';

void main() {
  test('punycode matches RFC 3492 / IDNA vectors', () {
    expect(punycodeEncode('пример'), 'e1afmkfd');
    expect(punycodeEncode('рф'), 'p1ai');
    expect(punycodeEncode('bücher'), 'bcher-kva');
  });

  test('allowed forms open, and normalise', () {
    const ok = {
      'https://example.com/a?b=c': 'https://example.com/a?b=c',
      'HTTPS://Example.com': 'https://Example.com',
      '  https://example.com  ': 'https://example.com',
      ' https://example.com ': 'https://example.com',
      'example.com': 'http://example.com',
      'example.com:8080/x': 'http://example.com:8080/x',
      'localhost:3000': 'http://localhost:3000',
      '192.168.1.5:8080/x': 'http://192.168.1.5:8080/x',
      'https://пример.рф': 'https://xn--e1afmkfd.xn--p1ai',
      'https://пример.рф/путь': 'https://xn--e1afmkfd.xn--p1ai/%D0%BF%D1%83%D1%82%D1%8C',
      'пример.рф': 'http://xn--e1afmkfd.xn--p1ai',
      'mailto:a@b.co': 'mailto:a@b.co',
      'MAILTO:a@b.co': 'MAILTO:a@b.co',
      'tel:+15551234': 'tel:+15551234',
      'sms:+15551234': 'sms:+15551234',
      'geo:37.78,-122.41': 'geo:37.78,-122.41',
      'facetime:a@b.co': 'facetime:a@b.co',
      'facetime-audio:a@b.co': 'facetime-audio:a@b.co',
      'webcal://example.com/c.ics': 'webcal://example.com/c.ics',
      'ftp://example.com/f': 'ftp://example.com/f',
      'prevon://n/abc': 'prevon://n/abc',
    };
    ok.forEach((k, v) {
      expect(normalizeEditorLink(k), isNotNull, reason: k);
      expect(normalizeEditorLink(k)!.toLowerCase(), v.toLowerCase(), reason: k);
    });
  });

  test('refused forms: other schemes, case and control-character tricks', () {
    for (final h in [
      'javascript:alert(1)',
      'JaVaScRiPt:alert(1)',
      'javascript:80',
      'data:text/html;base64,AAAA',
      'data:80',
      'vbscript:MsgBox(1)',
      'file:///etc/passwd',
      'file:80',
      'blob:https://x.test/a',
      'whatsapp://send?text=x',
      'tg://resolve?domain=x',
      'obsidian://open?vault=x',
      'intent://x#Intent;end',
      'com.example.app:/cb',
      'ms-settings:privacy',
      'java\u0000script:alert(1)',
      'java\tscript:alert(1)',
      '​javascript:alert(1)',
      'https://exa\nmple.com',
      'https://exa​mple.com',
      'https://a b\u0000c',
      'https:///x',
      'https:javascript:alert(1)',
      'http:evil.com',
      '//host/x',
      'http://%',
      'http://[::1',
      'http://a.com:99x/',
      '',
      '   ',
      null,
    ]) {
      expect(normalizeEditorLink(h), isNull, reason: '$h');
    }
  });

  test('the launcher trims exactly as the gate does', () {
    expect(normalizeEditorLink(' https://a.com'), 'https://a.com');
  });
}
