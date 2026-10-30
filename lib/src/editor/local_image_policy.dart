import 'dart:io';

/// Which absolute LOCAL paths an image block may display (audit: hostile note
/// `src` pointing at any readable file).
///
/// New images are `pie-att://` attachments; an absolute path is legacy (the
/// file picker used to return one). The host app installs the roots it owns
/// (documents, support, temp, cache) at boot with [setAllowedRoots]. Three
/// states:
///  * never touched: permissive (the fork's own tests and non-host users);
///  * [requireRoots] called but no roots yet: every absolute path is refused
///    (the host calls it first, so a slow path lookup never fails open);
///  * roots set: only a path whose symlink-resolved form is inside a root is read
///    (the authoritative check, at read time); `..`, UNC and relative forms are
///    refused by the syntax guard first.
class LocalImagePolicy {
  LocalImagePolicy._();

  static List<String>? _roots; // null = never installed (permissive)

  /// Switches to deny-all until [setAllowedRoots] runs. Call synchronously at boot.
  static void requireRoots() => _roots ??= const <String>[];

  /// Installs the allowed roots, each canonicalised (symlinks resolved when it
  /// exists; a root that cannot be resolved is dropped).
  static void setAllowedRoots(Iterable<String> roots) {
    final out = <String>[];
    for (final r in roots) {
      if (r.isEmpty) continue;
      try {
        // Keep BOTH forms: a note path may be written through the supplied
        // spelling (Android /data/user/0, iOS /var, Windows 8.3 names) while
        // the canonical one is what a symlink-resolved file reports.
        final canonical = _norm(Directory(r).resolveSymbolicLinksSync());
        final supplied = _norm(_collapse(r));
        if (!out.contains(canonical)) out.add(canonical);
        if (!out.contains(supplied)) out.add(supplied);
      } on FileSystemException {
        // not there: nothing to allow
      }
    }
    _roots = List.unmodifiable(out);
  }

  /// Test hook: back to the never-installed state.
  static void resetForTest() => _roots = null;

  /// Cheap, lexical check (no filesystem): fine for choosing a placeholder.
  /// Only a hint: a `true` is final-looking but the read still re-checks, and a
  /// `false` must not be the last word for an absolute path (a symlinked root
  /// is only seen by [allowsResolved]).
  static bool allowsLexically(String path) {
    final roots = _roots;
    if (roots == null) return true;
    return _inside(roots, _norm(_collapse(path)));
  }

  /// The real check, run before a read: the symlink-resolved path must sit in a root.
  static Future<bool> allowsResolved(String path) async {
    final roots = _roots;
    if (roots == null) return true;
    try {
      return _inside(roots, _norm(await File(path).resolveSymbolicLinks()));
    } on FileSystemException {
      return false;
    }
  }

  static bool _inside(List<String> roots, String p) {
    for (final r in roots) {
      final base = r.endsWith('/') ? r : '$r/';
      if (p == r || p.startsWith(base)) return true;
    }
    return false;
  }

  static String _norm(String p) {
    final s = p.replaceAll('\\', '/');
    return Platform.isWindows || Platform.isMacOS ? s.toLowerCase() : s;
  }

  // Collapses `.` segments; `..` is refused upstream by isSafeLocalImagePath.
  static String _collapse(String p) =>
      p.replaceAll('\\', '/').split('/').where((s) => s != '.').join('/');
}
