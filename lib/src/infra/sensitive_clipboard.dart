import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';

class EditorSensitiveClipboard {
  EditorSensitiveClipboard._();

  static Timer? _clearTimer;

  /// Fallback delay used when no [autoClearDelayResolver] is installed. Fails
  /// closed: an unconfigured editor clipboard still clears itself.
  static const Duration defaultTimeout = Duration(seconds: 60);

  /// Reports whether the secure clipboard is on. Null means "on". The host app
  /// installs this (the fork cannot read app settings itself).
  static bool Function()? secureEnabledResolver;

  /// Reports the auto-clear delay; [Duration.zero] means never clear. Null
  /// means [defaultTimeout]. Installed by the host app.
  static Duration Function()? autoClearDelayResolver;

  static bool get _secureEnabled => secureEnabledResolver?.call() ?? true;

  static void _armTimer(Duration? timeout) {
    final duration =
        timeout ?? autoClearDelayResolver?.call() ?? defaultTimeout;
    if (duration <= Duration.zero) return;
    _clearTimer = Timer(duration, () {
      clear();
    });
  }

  static String sensitiveChannelName = 'com.prevon.pie/sensitive_clipboard';

  static const String sensitiveMethod = 'setSensitiveClipboard';

  static MethodChannel get _sensitiveChannel =>
      MethodChannel(sensitiveChannelName);

  static Future<void> copy(String text, {Duration? timeout}) async {
    _clearTimer?.cancel();
    _clearTimer = null;
    await _setClipboardWithSensitiveFlag(text);
    _armTimer(timeout);
  }

  static Future<void> copyBytes(List<int> bytes, {Duration? timeout}) async {
    _clearTimer?.cancel();
    _clearTimer = null;
    final text = String.fromCharCodes(bytes);
    await _setClipboardWithSensitiveFlag(text);
    _armTimer(timeout);
  }

  static Future<void> _setClipboardWithSensitiveFlag(String text) async {
    if (_secureEnabled && Platform.isAndroid) {
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
