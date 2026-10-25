import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import 'audio_route.dart';

/// The mic as 16 kHz mono float samples, for the on-device models.
class MicCapture {
  MicCapture._(
    this._recorder,
    this._subscription,
    this._samples,
    this._levels, {
    required bool call,
  }) : _call = call;

  final AudioRecorder _recorder;
  final StreamSubscription<Uint8List> _subscription;
  final StreamController<Float32List> _samples;
  final StreamController<double> _levels;

  /// A call's audio route belongs to the call; dictation holds its own.
  final bool _call;

  /// Samples as they arrive (about every 100 ms).
  Stream<Float32List> get samples => _samples.stream;

  /// Loudness 0–1 per chunk, for the waveform and the orb.
  Stream<double> get levels => _levels.stream;

  /// Opens the mic. [call] uses Android's voice-call path, whose echo
  /// cancellation keeps Frank from hearing its own voice; the call routes
  /// its audio itself. Dictation listens through a headset when one is
  /// connected.
  static Future<MicCapture> start({bool call = false}) async {
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      throw StateError('Hermsy needs microphone access for voice.');
    }
    if (!call) {
      await AudioRoute.begin(AudioPurpose.dictation);
    }
    final Stream<Uint8List> bytes;
    try {
      bytes = await recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: !call,
          // In a call Frank's own voice takes audio focus; the mic must
          // keep listening through it (that is how you interrupt).
          audioInterruption: call
              ? AudioInterruptionMode.none
              : AudioInterruptionMode.pause,
          androidConfig: AndroidRecordConfig(
            audioSource: call
                ? AndroidAudioSource.voiceCommunication
                : AndroidAudioSource.voiceRecognition,
            // Frank's audio route picks the device (AudioRoute), so the
            // recorder neither forces the speaker nor starts Bluetooth.
            manageBluetooth: false,
          ),
        ),
      );
    } catch (_) {
      if (!call) {
        await AudioRoute.end(AudioPurpose.dictation);
      }
      await recorder.dispose();
      rethrow;
    }
    final samples = StreamController<Float32List>.broadcast();
    final levels = StreamController<double>.broadcast();
    int? carry;
    final subscription = bytes.listen(
      (chunk) {
        final floats = pcm16ToFloat(chunk, carry: carry);
        carry = floats.carry;
        if (floats.samples.isEmpty) {
          return;
        }
        samples.add(floats.samples);
        levels.add(levelOf(floats.samples));
      },
      onDone: () {
        samples.close();
        levels.close();
      },
    );
    return MicCapture._(recorder, subscription, samples, levels, call: call);
  }

  Future<void> stop() async {
    try {
      await _recorder.stop();
    } finally {
      await _subscription.cancel();
      await _recorder.dispose();
      await _samples.close();
      await _levels.close();
      if (!_call) {
        await AudioRoute.end(AudioPurpose.dictation);
      }
    }
  }
}

/// Little-endian 16-bit PCM to floats in [-1, 1]. A byte left over from an
/// odd-sized chunk comes back as [carry] for the next one.
({Float32List samples, int? carry}) pcm16ToFloat(
  Uint8List bytes, {
  int? carry,
}) {
  final data = carry == null
      ? bytes
      : (Uint8List(bytes.length + 1)
          ..[0] = carry
          ..setAll(1, bytes));
  final count = data.length ~/ 2;
  final view = ByteData.sublistView(data);
  final out = Float32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return (samples: out, carry: data.length.isOdd ? data.last : null);
}

/// Loudness as the eye reads it: RMS on a -50..-10 dB scale.
double levelOf(Float32List samples) {
  if (samples.isEmpty) {
    return 0;
  }
  var sum = 0.0;
  for (final s in samples) {
    sum += s * s;
  }
  final rms = math.sqrt(sum / samples.length);
  if (rms <= 0) {
    return 0;
  }
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 50) / 40).clamp(0.0, 1.0);
}
