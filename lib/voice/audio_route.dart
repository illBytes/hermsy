import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What Frank holds the audio route for.
enum AudioPurpose { call, dictation }

/// Where voice goes in and out right now.
class AudioRouteInfo {
  const AudioRouteInfo({required this.kind, this.name});

  factory AudioRouteInfo.fromMap(Map<Object?, Object?> map) => AudioRouteInfo(
    kind: map['kind'] as String? ?? 'phone',
    name: map['name'] as String?,
  );

  /// "bluetooth", "wired", "speaker" or "phone" (the phone's own mic, for
  /// dictation without a headset).
  final String kind;

  /// The headset's name, for Bluetooth.
  final String? name;

  bool get headset => kind == 'bluetooth' || kind == 'wired';

  /// For the call screen: where you hear Frank.
  String get label => switch (kind) {
    'bluetooth' => name ?? 'Bluetooth headset',
    'wired' => 'Headset',
    _ => 'Speaker',
  };
}

/// Sends voice through a connected headset, Bluetooth or wired, for calls
/// and dictation; a call without one is on the loudspeaker. Android only
/// (android/.../AudioRoute.kt); elsewhere, and in tests, it does nothing.
class AudioRoute {
  static const _channel = MethodChannel('frank/audio_route');

  /// The route while Frank holds one; null otherwise. Follows headsets
  /// connecting and disconnecting.
  static final current = ValueNotifier<AudioRouteInfo?>(null);

  static AudioPurpose? _held;
  static var _listening = false;

  static Future<AudioRouteInfo?> begin(AudioPurpose purpose) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'routeChanged' && _held != null) {
          current.value = AudioRouteInfo.fromMap(
            call.arguments as Map<Object?, Object?>,
          );
        }
      });
    }
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>(
        'begin',
        purpose.name,
      );
      _held = purpose;
      return current.value = map == null ? null : AudioRouteInfo.fromMap(map);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Lets go, if [purpose] still holds the route (a call outranks a
  /// dictation that started before it).
  static Future<void> end(AudioPurpose purpose) async {
    if (_held != purpose) {
      return;
    }
    _held = null;
    current.value = null;
    try {
      await _channel.invokeMethod<void>('end', purpose.name);
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // Nothing to undo.
    }
  }
}
