import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android's ongoing "Call with Frank" notification (CallService.kt). While
/// it shows, the call keeps listening and speaking with Frank off screen or
/// the phone locked; its End call button hangs up. Elsewhere, and in tests,
/// it does nothing.
class CallService {
  static const _channel = MethodChannel('frank/call');
  static VoidCallback? _onEnd;

  /// Shows the notification for a call in [title]; [onEnd] runs if you end
  /// the call from it. False when Android would not start it.
  static Future<bool> start({
    required String title,
    required VoidCallback onEnd,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    _onEnd = onEnd;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'endCall') {
        _onEnd?.call();
      }
    });
    try {
      return await _channel.invokeMethod<bool>('start', title) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> stop() async {
    _onEnd = null;
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // Already gone.
    }
  }
}
