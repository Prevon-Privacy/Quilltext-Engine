import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';

class EditorSensitiveClipboard {
  EditorSensitiveClipboard._();

  static Timer? _clearTimer;

  static const Duration defaultTimeout = Duration(seconds: 60);

  static String sensitiveChannelName = 'com.prevon.pie/sensitive_clipboard';

  static const String sensitiveMethod = 'setSensitiveClipboard';

  static MethodChannel get _sensitiveChannel =>
      MethodChannel(sensitiveChannelName);

  static Future<void> copy(String text, {Duration? timeout}) async {
    _clearTimer?.cancel();
    await _setClipboardWithSensitiveFlag(text);
    final duration = timeout ?? defaultTimeout;
    _clearTimer = Timer(duration, () {
      clear();
    });
  }

  static Future<void> copyBytes(List<int> bytes, {Duration? timeout}) async {
    _clearTimer?.cancel();
    final text = String.fromCharCodes(bytes);
    await _setClipboardWithSensitiveFlag(text);
    final duration = timeout ?? defaultTimeout;
    _clearTimer = Timer(duration, () {
      clear();
    });
  }

  static Future<void> _setClipboardWithSensitiveFlag(String text) async {
    if (Platform.isAndroid) {
      try {
        await _sensitiveChannel.invokeMethod(sensitiveMethod, {'text': text});
        return;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[SEC] Sensitive clipboard channel failed, falling back to standard clipboard: $e',
          );
        }
      }
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  static Future<void> clear() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    await Clipboard.setData(const ClipboardData(text: ''));
  }

  static void cancelTimer() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }

  static bool get hasActiveTimer => _clearTimer?.isActive ?? false;

  static Duration? get remainingTime {
    if (_clearTimer == null || !_clearTimer!.isActive) return null;
    return null;
  }
}
