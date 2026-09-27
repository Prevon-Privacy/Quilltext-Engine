import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sensitive_clipboard.dart';

class AppFlowyClipboardData {
  const AppFlowyClipboardData({
    this.text,
    this.html,
  });
  final String? text;
  final String? html;
}

class AppFlowyClipboard {
  static AppFlowyClipboardData? _mockData;

  @visibleForTesting
  static String? lastText;

  static Future<void> setData({
    String? text,
    String? html,
  }) async {
    if (text == null) {
      return;
    }

    lastText = text;

    // Single choke point for every editor copy path (keyboard cmd/ctrl+C,
    // context-menu copy/cut, link-menu copy). Routes through the editor's own
    // EditorSensitiveClipboard so the 60s auto-clear timer is armed and the
    // Android EXTRA_IS_SENSITIVE flag is set — never a bare Clipboard.setData write.
    return EditorSensitiveClipboard.copy(text);
  }

  static Future<AppFlowyClipboardData> getData() async {
    if (_mockData != null) {
      return _mockData!;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return AppFlowyClipboardData(
      text: data?.text,
      html: null,
    );
  }

  @visibleForTesting
  static void mockSetData(AppFlowyClipboardData? data) {
    _mockData = data;
  }
}
