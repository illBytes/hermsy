import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays Kokoro's audio in order. In a call ([call]) it goes on the
/// voice-call path, so the mic's echo cancellation can hear it and take it
/// out; otherwise (voice previews) it plays as ordinary media, which reaches
/// Bluetooth headphones at once and at full quality.
///
/// Two players take turns: while one plays, the next clip is already
/// loaded on the other and starts the moment the first ends, so sentences
/// run on without the pause of preparing each clip.
class SpeechPlayer {
  SpeechPlayer({List<AudioPlayer>? players, this.call = true})
    : _players = players ?? [AudioPlayer(), AudioPlayer()];

  final List<AudioPlayer> _players;

  /// On the voice-call path (calls) rather than as media (previews).
  final bool call;
  final _queue = <Uint8List>[];
  final _subscriptions = <StreamSubscription<void>>[];
  int? _active;
  int? _loaded;
  var _loading = false;
  var _gen = 0;
  var _next = 0;
  Future<void>? _configured;

  /// True while a clip plays, waits loaded, or waits in the queue.
  bool get busy =>
      _active != null || _loaded != null || _loading || _queue.isNotEmpty;

  /// Called with true when Frank starts talking and false when it stops.
  void Function(bool speaking)? onSpeaking;

  /// Sets the players up now rather than on the first clip. A call does
  /// this before it takes the audio route: setting up touches Android's
  /// audio settings, and doing it later would knock a headset off the route.
  Future<void> prepare() => _configure();

  Future<void> _configure() => _configured ??= () async {
    final context = call ? _callContext : _mediaContext;
    for (var i = 0; i < _players.length; i++) {
      await _players[i].setAudioContext(context);
      _subscriptions.add(_players[i].onPlayerComplete.listen((_) => _done(i)));
    }
  }();

  static final _mediaContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      audioMode: AndroidAudioMode.normal,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
  );

  static final _callContext = AudioContext(
    android: const AudioContextAndroid(
      // The call's audio route picks headset or loudspeaker (AudioRoute);
      // forcing the speaker here would pull a call off a headset.
      isSpeakerphoneOn: false,
      stayAwake: true,
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.voiceCommunication,
      // Taking focus would pause the call's mic.
      audioFocus: AndroidAudioFocus.none,
      audioMode: AndroidAudioMode.inCommunication,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: const {
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.allowBluetooth,
      },
    ),
  );

  /// Queues [samples] at [sampleRate]; plays at once if nothing else is.
  Future<void> enqueue(Float32List samples, int sampleRate) async {
    _queue.add(wavBytes(samples, sampleRate));
    await _configure();
    await _pump(_gen);
  }

  /// Loads the next clip on the free player, and starts it if nothing is
  /// playing.
  Future<void> _pump(int gen) async {
    if (gen != _gen || _loading) {
      return;
    }
    if (_loaded == null && _queue.isNotEmpty) {
      final target = _free();
      _loading = true;
      try {
        _log('load on player $target (gen $gen)');
        await _players[target].setSource(
          BytesSource(_queue.removeAt(0), mimeType: 'audio/wav'),
        );
        _log('loaded on player $target');
      } catch (error) {
        _log('load failed: $error');
        rethrow;
      } finally {
        if (gen == _gen) {
          _loading = false;
        }
      }
      if (gen != _gen) {
        return;
      }
      _loaded = target;
    }
    if (_active == null && _loaded != null) {
      final start = _active = _loaded;
      _loaded = null;
      onSpeaking?.call(true);
      _log('play player $start');
      await _players[start!].resume();
      // Get the clip after it ready while this one plays.
      unawaited(_pump(gen));
    }
  }

  int _free() {
    final active = _active;
    if (active == null) {
      return _next;
    }
    return (active + 1) % _players.length;
  }

  void _done(int index) {
    _log('player $index done (active $_active)');
    if (index != _active) {
      return;
    }
    _active = null;
    _next = (index + 1) % _players.length;
    if (!busy) {
      onSpeaking?.call(false);
      return;
    }
    unawaited(_pump(_gen));
  }

  /// Stops now and drops what was queued (barge-in, end of call).
  Future<void> stop() async {
    _gen++;
    _queue.clear();
    _active = null;
    _loaded = null;
    _loading = false;
    onSpeaking?.call(false);
    for (final player in _players) {
      try {
        await player.stop();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await stop();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    for (final player in _players) {
      await player.dispose();
    }
  }
}

void _log(String message) {
  if (kDebugMode) {
    debugPrint('speech player: $message');
  }
}

/// Float samples as a 16-bit mono WAV file.
Uint8List wavBytes(Float32List samples, int sampleRate) {
  final data = samples.length * 2;
  final out = ByteData(44 + data);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      out.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + data, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  out.setUint32(40, data, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    out.setInt16(44 + i * 2, (clamped * 32767).round(), Endian.little);
  }
  return out.buffer.asUint8List();
}

/// [samples] without the near-silence Kokoro leaves at each end, keeping
/// [leadMs] and [tailMs] so words do not start or stop abruptly.
Float32List trimSilence(
  Float32List samples,
  int sampleRate, {
  double threshold = 0.008,
  int leadMs = 20,
  int tailMs = 60,
}) {
  var start = 0;
  while (start < samples.length && samples[start].abs() < threshold) {
    start++;
  }
  if (start == samples.length) {
    return samples;
  }
  var end = samples.length - 1;
  while (end > start && samples[end].abs() < threshold) {
    end--;
  }
  final from = (start - sampleRate * leadMs ~/ 1000).clamp(0, samples.length);
  final to = (end + 1 + sampleRate * tailMs ~/ 1000).clamp(0, samples.length);
  return Float32List.sublistView(samples, from, to);
}
