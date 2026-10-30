import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';

// dry-ok: the editor is published standalone and cannot import the host app's shared helpers, so it keeps its own copy of the host's
// sensitive-clipboard helper; the two behave identically (same channel, expiry, still-ours clear). Change both.
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

  static Duration _effectiveDelay(Duration? timeout) =>
      timeout ?? autoClearDelayResolver?.call() ?? defaultTimeout;

  static void _armTimer(Duration? timeout) {
    final duration = _effectiveDelay(timeout);
    if (duration <= Duration.zero) return;
    _clearTimer = Timer(duration, () {
      _clearIfStillOurs();
    });
  }

  /// The text this class last put on the clipboard; the timer only clears when
  /// the clipboard still holds it, so a later copy (text, or an image or file
  /// that reads back as no text) is never wiped.
  static String? _lastCopied;

  static Future<void> _clearIfStillOurs() async {
    _clearTimer = null;
    final ours = _lastCopied;
    if (ours == null) return;
    try {
      final now = await Clipboard.getData(Clipboard.kTextPlain);
      // A null answer (the platform gave no data at all) is unreadable: clear to fail closed. A data answer whose text is not ours,
      // including null text (an image or file is on the board), is somebody else's.
      if (now != null && now.text != ours) {
        _lastCopied = null;
        return;
      }
    } catch (_) {
      // getData throws when the board holds no text at all (an image or a file) and when it cannot be read (iOS paste prompt). No text
      // on the board means it is not ours to wipe; anything else (text we cannot read, or a failing probe) clears to fail closed.
      try {
        if (!await Clipboard.hasStrings()) {
          _lastCopied = null;
          return;
        }
      } catch (_) {
        // Fail closed.
      }
    }
    await clear();
  }

  /// Vault lock / logout: stop the timer and wipe what THIS class placed on the clipboard, unless something newer replaced it. Never throws.
  static Future<void> clearIfOurs() async {
    _clearTimer?.cancel();
    try {
      await _clearIfStillOurs();
    } catch (_) {
      _lastCopied = null;
    }
  }

  static String sensitiveChannelName = 'com.prevon.pie/sensitive_clipboard';

  static const String sensitiveMethod = 'setSensitiveClipboard';

  static MethodChannel get _sensitiveChannel =>
      MethodChannel(sensitiveChannelName);

  static Future<void> copy(String text, {Duration? timeout}) async {
    _clearTimer?.cancel();
    _clearTimer = null;
    await _setClipboardWithSensitiveFlag(text, timeout);
    _lastCopied = text;
    _armTimer(timeout);
  }

  static Future<void> copyBytes(List<int> bytes, {Duration? timeout}) async {
    _clearTimer?.cancel();
    _clearTimer = null;
    final text = String.fromCharCodes(bytes);
    await _setClipboardWithSensitiveFlag(text, timeout);
    _lastCopied = text;
    _armTimer(timeout);
  }

  /// Android sets the sensitive flag natively; iOS writes a local-only pasteboard item (no Universal Clipboard). Both carry a native
  /// expiry equal to the auto-clear delay, so the OS drops the text even when the Dart timer never fires (app suspended).
  static Future<void> _setClipboardWithSensitiveFlag(
      String text, Duration? timeout) async {
    if (_secureEnabled && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final delay = _effectiveDelay(timeout);
        await _sensitiveChannel.invokeMethod(sensitiveMethod, {
          'text': text,
          if (delay > Duration.zero)
            'expirySeconds': delay.inSeconds < 1 ? 1 : delay.inSeconds,
        });
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
    _lastCopied = null;
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
