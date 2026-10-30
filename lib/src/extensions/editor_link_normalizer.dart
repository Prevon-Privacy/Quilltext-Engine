// The ONE function that decides whether a link in a note may be handed to the
// operating system, and what exact text is handed over. The host gate
// (`isOpenableEditorLink`) and the launcher (`safeLaunchUrl`) both call it, so
// they can never disagree about trimming, scheme or host. Pure Dart.

/// Schemes a note link may hand to the OS (no scheme = `http://`).
const Set<String> kLaunchableLinkSchemes = {
  'http',
  'https',
  'mailto',
  'tel',
  'sms',
  'geo',
  'facetime',
  'facetime-audio',
  'webcal',
  'ftp',
  'prevon',
  'pie-note',
  'pie-att',
  'prevonpie',
};

/// Schemes that name a website and so need a real host.
const Set<String> _kHostSchemes = {'http', 'https', 'webcal', 'ftp'};

/// Schemes that are never openable, even when written like `javascript:80`.
const Set<String> _kNeverSchemes = {
  'javascript', 'vbscript', 'data', 'blob', 'file', 'content', 'intent',
  'android-app', 'about', 'chrome', 'chrome-extension', 'ms-msdt',
  'ms-officecmd', 'ms-appinstaller', 'ms-settings', 'search-ms', 'search',
  'shell', 'ws', 'wss',
};

final RegExp _control = RegExp(
    r'[\u0000-\u001f\u007f-\u009f­​-‏ -‮⁠-⁤﻿]');
final RegExp _schemeHead = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*):');
final RegExp _portRest = RegExp(r'^\d{1,5}(?:[/?#].*)?$', dotAll: true);

/// The text to launch for [href], or null when it must not be opened. Trims
/// (Unicode whitespace) first, refuses control and invisible characters,
/// allows only [kLaunchableLinkSchemes], reads `host:port` and `localhost:3000`
/// as `http://`, and converts a non-ASCII host to punycode (`xn--`).
/// Never throws.
String? normalizeEditorLink(String? href) {
  if (href == null) return null;
  final raw = href.trim();
  if (raw.isEmpty || _control.hasMatch(raw)) return null;
  try {
    final head = _schemeHead.firstMatch(raw);
    String scheme;
    String rest;
    if (head != null) {
      final s = head.group(1)!.toLowerCase();
      final after = raw.substring(head.end);
      if (kLaunchableLinkSchemes.contains(s)) {
        scheme = s;
        rest = after;
      } else if (!_kNeverSchemes.contains(s) && _portRest.hasMatch(after)) {
        // `localhost:3000`, `192.168.1.5:8080/x`, `example.com:8080`.
        scheme = 'http';
        rest = '//$raw';
      } else {
        return null;
      }
    } else {
      scheme = 'http';
      rest = '//$raw';
    }
    if (!_kHostSchemes.contains(scheme)) {
      final u = Uri.tryParse('$scheme:$rest');
      return (u == null || u.scheme.toLowerCase() != scheme)
          ? null
          : '$scheme:$rest';
    }
    if (!rest.startsWith('//')) return null;
    final body = rest.substring(2);
    final end = body.indexOf(RegExp(r'[/?#]'));
    final authority = end < 0 ? body : body.substring(0, end);
    final tail = end < 0 ? '' : body.substring(end);
    final at = authority.lastIndexOf('@');
    final userInfo = at < 0 ? '' : authority.substring(0, at + 1);
    var hostPort = at < 0 ? authority : authority.substring(at + 1);
    var port = '';
    if (!hostPort.startsWith('[')) {
      final c = hostPort.lastIndexOf(':');
      if (c >= 0) {
        port = hostPort.substring(c);
        hostPort = hostPort.substring(0, c);
        if (!RegExp(r'^:\d{0,5}$').hasMatch(port)) return null;
      }
      hostPort = _asciiHost(hostPort);
    }
    if (hostPort.isEmpty || RegExp(r'[%\s]').hasMatch(hostPort)) return null;
    final uri = Uri.tryParse('$scheme://$userInfo$hostPort$port$tail');
    if (uri == null || uri.host.isEmpty) return null;
    return uri.toString();
  } catch (_) {
    return null;
  }
}

/// Lower-cases a host and converts each non-ASCII label to `xn--` punycode.
String _asciiHost(String host) {
  if (host.runes.every((r) => r < 0x80)) return host;
  return host
      .replaceAll(RegExp('[。．｡]'), '.')
      .split('.')
      .map((l) => l.runes.every((r) => r < 0x80)
          ? l
          : 'xn--${punycodeEncode(l.toLowerCase())}')
      .join('.');
}

/// RFC 3492 punycode encoder (no `xn--` prefix).
String punycodeEncode(String input) {
  const base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700;
  int adapt(int delta, int numPoints, bool first) {
    delta = first ? delta ~/ damp : delta ~/ 2;
    delta += delta ~/ numPoints;
    var k = 0;
    while (delta > ((base - tMin) * tMax) ~/ 2) {
      delta ~/= base - tMin;
      k += base;
    }
    return k + (((base - tMin + 1) * delta) ~/ (delta + skew));
  }

  String digit(int d) =>
      String.fromCharCode(d < 26 ? 0x61 + d : 0x30 + d - 26);
  final cps = input.runes.toList();
  final out = StringBuffer();
  for (final c in cps) {
    if (c < 0x80) out.writeCharCode(c);
  }
  final b = out.length;
  var h = b;
  if (b > 0) out.write('-');
  var n = 128, delta = 0, bias = 72;
  while (h < cps.length) {
    final m = cps.where((c) => c >= n).reduce((a, c) => a < c ? a : c);
    delta += (m - n) * (h + 1);
    n = m;
    for (final c in cps) {
      if (c < n) delta++;
      if (c == n) {
        var q = delta;
        for (var k = base;; k += base) {
          final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
          if (q < t) break;
          out.write(digit(t + (q - t) % (base - t)));
          q = (q - t) ~/ (base - t);
        }
        out.write(digit(q));
        bias = adapt(delta, h + 1, h == b);
        delta = 0;
        h++;
      }
    }
    delta++;
    n++;
  }
  return out.toString();
}
