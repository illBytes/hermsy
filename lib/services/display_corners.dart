import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('frank/display');

/// The phone's screen corner radius in logical pixels, so the edge glow can
/// trace the real glass instead of a guessed rectangle.
class DisplayCorners {
  DisplayCorners._();

  /// A typical modern phone corner, used until (or unless) the OS reports one.
  static const fallback = 44.0;

  /// Logical corner radius. Starts at [fallback] and updates once Android 12+
  /// reports the real value.
  static final ValueNotifier<double> radius = ValueNotifier<double>(fallback);

  static bool _asked = false;
  static int _attempts = 0;

  /// Gives up after this many "window not ready" answers, so metric changes
  /// (the keyboard animating) never keep calling the channel.
  static const _maxAttempts = 6;

  /// Asks Android for the rounded-corner radii once. Safe to call repeatedly
  /// (it retries a few times until the window can answer) and on platforms
  /// without the channel.
  static Future<void> load(double devicePixelRatio) async {
    if (_asked) {
      return;
    }
    _asked = true;
    _attempts++;
    if (kIsWeb) {
      return;
    }
    if (Platform.isIOS) {
      // iOS keeps the display radius private; recent iPhones sit near 55pt.
      radius.value = 55;
      return;
    }
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final raw = await _channel.invokeMapMethod<String, int>('cornerRadii');
      if (raw == null || devicePixelRatio <= 0) {
        // The window is not attached yet: ask again on the next metrics change.
        _asked = _attempts >= _maxAttempts;
        return;
      }
      if (raw.isEmpty) {
        // Before Android 12 there is no API for it; keep the fallback.
        return;
      }
      final px = raw.values.fold<int>(0, math.max);
      if (px > 0) {
        radius.value = px / devicePixelRatio;
      }
    } catch (_) {
      // Older Android or no window yet: keep the fallback.
    }
  }
}

/// Keeps the app out of screenshots and the recents preview.
///
/// Android sets FLAG_SECURE on the window. iOS has no equivalent, so
/// `main.dart` covers the app while it is inactive instead.
class SecureDisplay {
  SecureDisplay._();

  static bool? _applied;

  /// Turns the secure window on or off. A no-op when nothing changes and on
  /// platforms without the channel.
  static Future<void> apply(bool secure) async {
    if (_applied == secure || kIsWeb || !Platform.isAndroid) {
      return;
    }
    _applied = secure;
    try {
      await _channel.invokeMethod<void>('setSecure', secure);
    } catch (_) {
      _applied = null;
    }
  }
}
