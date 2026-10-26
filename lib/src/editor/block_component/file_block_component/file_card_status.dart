// What a file card can show beside its name, beyond the block's own attributes.
//
// The fork owns the card; the host owns the facts (is the text read yet, is the file kept on this
// device, did attaching fail). The host hands them over through [FileStatusSource], read with
// `context.read<FileStatusSource>()` in a `try { } on ProviderNotFoundException`. With no provider
// the card simply shows name, type and size.

import 'package:flutter/foundation.dart';
import 'package:prevon_quilltext_engine/src/editor/file_actions.dart' show FileViewRequest;

/// Where a file is in its life, as the card should draw it.
enum FileCardPhase {
  /// Stored and nothing more to say.
  ready,

  /// Being attached or its text is being read: a small spinner or real progress.
  working,

  /// The words inside are searchable.
  searchable,

  /// Too big to travel: stays on this device.
  localOnly,

  /// Attaching or reading failed; [FileCardStatus.onRetry] may be set.
  failed,
}

@immutable
class FileCardStatus {
  const FileCardStatus(
    this.phase, {
    this.label = '',
    this.progress,
    this.onRetry,
  });

  const FileCardStatus.ready() : this(FileCardPhase.ready);

  final FileCardPhase phase;

  /// The localized chip words ("Reading text…", "Searchable"). Empty draws no chip.
  final String label;

  /// 0..1 while [FileCardPhase.working] with a known amount, else null (indeterminate).
  final double? progress;

  /// Shown as a Retry button on [FileCardPhase.failed].
  final VoidCallback? onRetry;
}

/// The host's answer to "what is the state of this file?", one live value per file reference.
abstract interface class FileStatusSource {
  ValueListenable<FileCardStatus> statusOf(FileViewRequest file);

  /// Words for the card's buttons and spoken labels (the fork has no strings of its own).
  FileCardWords get words;

  /// A file block was just removed from the note; [undo] puts it back (one editor undo).
  /// The host shows its Undo toast.
  void onRemoved(FileViewRequest file, VoidCallback undo);
}

@immutable
class FileCardWords {
  const FileCardWords({
    this.retry = 'Retry',
    this.moreActions = 'File actions',
    this.cleanName = _same,
  });

  /// Makes an untrusted file name safe to draw (the host passes its shared display sanitiser:
  /// control, bidi and zero-width characters become visible marks or vanish).
  final String Function(String) cleanName;

  static String _same(String s) => s;

  final String retry;
  final String moreActions;
}

/// The file's type family, used for the icon colour and the type label.
enum FileFamily { pdf, image, audio, video, slides, sheet, doc, archive, text, other }

FileFamily fileFamilyOf(String mime, String name) {
  final m = mime.toLowerCase();
  final n = name.toLowerCase();
  bool ext(List<String> exts) => exts.any((e) => n.endsWith('.$e'));
  if (m == 'application/pdf' || n.endsWith('.pdf')) return FileFamily.pdf;
  if (m.startsWith('image/')) return FileFamily.image;
  if (m.startsWith('audio/')) return FileFamily.audio;
  if (m.startsWith('video/')) return FileFamily.video;
  if (m.contains('presentation') || ext(['ppt', 'pptx', 'odp', 'key'])) {
    return FileFamily.slides;
  }
  if (m.contains('spreadsheet') ||
      m.contains('ms-excel') ||
      m == 'text/csv' ||
      m == 'text/tab-separated-values' ||
      ext(['csv', 'tsv', 'xls', 'xlsx', 'ods', 'numbers'])) {
    return FileFamily.sheet;
  }
  if (m.contains('wordprocessing') ||
      m.contains('msword') ||
      m.contains('opendocument.text') ||
      m == 'application/rtf' ||
      m == 'application/epub+zip' ||
      ext(['doc', 'docx', 'odt', 'rtf', 'pages', 'epub'])) {
    return FileFamily.doc;
  }
  if (m.contains('zip') ||
      m.contains('x-tar') ||
      m.contains('gzip') ||
      m.contains('7z') ||
      m.contains('rar') ||
      ext(['zip', 'tar', 'gz', 'tgz', '7z', 'rar'])) {
    return FileFamily.archive;
  }
  if (m.startsWith('text/') || m.contains('json') || m.contains('xml')) {
    return FileFamily.text;
  }
  return FileFamily.other;
}

/// Shortens a long file name in the MIDDLE so the start and the extension both stay visible:
/// `Quarterly_report_final_v7_reviewed.pdf` -> `Quarterly_repo…eviewed.pdf`. Names that already fit
/// come back unchanged. [maxChars] counts characters, extension included.
String middleEllipsis(String name, int maxChars) {
  if (maxChars < 8 || name.length <= maxChars) return name;
  final dot = name.lastIndexOf('.');
  final hasExt = dot > 0 && name.length - dot <= 6;
  final tail = hasExt ? name.substring(dot) : '';
  final stem = hasExt ? name.substring(0, dot) : name;
  // Keep the extension plus a few end characters of the stem.
  final endKeep = hasExt ? 4 : (maxChars ~/ 3);
  final startKeep = maxChars - 1 - tail.length - endKeep;
  if (startKeep < 3) return '${name.substring(0, maxChars - 1)}…';
  final end = stem.length > endKeep ? stem.substring(stem.length - endKeep) : '';
  return '${stem.substring(0, startKeep)}…$end$tail';
}
