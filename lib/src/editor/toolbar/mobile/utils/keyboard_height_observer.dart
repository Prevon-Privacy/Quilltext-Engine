import 'package:prevon_quilltext_engine/src/editor/util/platform_extension.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:keyboard_height_plugin/keyboard_height_plugin.dart';

typedef KeyboardHeightCallback = void Function(double height);

// the KeyboardHeightPlugin only accepts one listener, so we need to create a
//  singleton class to manage the multiple listeners.
class KeyboardHeightObserver {
  static int androidSDKVersion = -1;

  KeyboardHeightObserver._() {
    if (PlatformExtension.isAndroid && androidSDKVersion == -1) {
      DeviceInfoPlugin().androidInfo.then(
            (value) => androidSDKVersion = value.version.sdkInt,
          );
    }
    // keyboard_height_plugin has a native side on Android and iOS only. On
    // macOS, Windows and Linux (and in a desktop-sized test window) the
    // channel has no implementation and subscribing throws
    // MissingPluginException, so the observer stays silent there: the
    // keyboard height simply stays 0, which is the true value on a machine
    // with no on-screen keyboard.
    if (PlatformExtension.isAndroid || PlatformExtension.isIOS) {
      try {
        _keyboardHeightPlugin = KeyboardHeightPlugin();
        _keyboardHeightPlugin!.onKeyboardHeightChanged((height) {
          notify(height);

          currentKeyboardHeight = height;
        });
      } catch (_) {
        _keyboardHeightPlugin = null;
      }
    }
  }

  static final KeyboardHeightObserver instance = KeyboardHeightObserver._();
  static double currentKeyboardHeight = 0;

  final List<KeyboardHeightCallback> _listeners = [];
  KeyboardHeightPlugin? _keyboardHeightPlugin;

  void addListener(KeyboardHeightCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(KeyboardHeightCallback listener) {
    _listeners.remove(listener);
  }

  void dispose() {
    _listeners.clear();
    try {
      _keyboardHeightPlugin?.dispose();
    } catch (_) {}
  }

  void notify(double height) {
    // the keyboard height will notify twice with the same value on Android
    if (PlatformExtension.isAndroid && height == currentKeyboardHeight) {
      return;
    }

    for (final listener in _listeners) {
      listener(height);
    }
  }
}
