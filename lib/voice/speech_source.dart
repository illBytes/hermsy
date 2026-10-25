import 'dart:typed_data';

import '../services/relay_client.dart';
import 'speech_worker.dart';
import 'spoken_text.dart' show sayMoney;

typedef Speech = ({Float32List samples, int sampleRate});

/// Something that turns a sentence into audio for a call.
abstract class SpeechSource {
  Future<Speech> speak(String text);
}

/// Kokoro on this phone. Sentences go to the speaking workers in turn so
/// consecutive ones render at the same time.
class KokoroSpeech implements SpeechSource {
  KokoroSpeech(this.workers, {required this.voice, this.speed = 1.0})
    : assert(workers.isNotEmpty);

  final List<SpeechWorker> workers;
  final int voice;
  final double speed;
  var _next = 0;

  @override
  Future<Speech> speak(String text) => workers[_next++ % workers.length].speak(
    sayMoney(text),
    voice: voice,
    speed: speed,
  );
}

/// A cloud voice (OpenAI, ElevenLabs) through the relay, whose key never
/// leaves the VPS. After the first failure the rest of the call uses
/// [fallback] (Kokoro), so a dropped connection costs one sentence's wait,
/// not one per sentence.
class CloudSpeech implements SpeechSource {
  CloudSpeech({
    required this.relay,
    required this.provider,
    required this.voice,
    this.speed = 1.0,
    this.fallback,
    this.onFallback,
  });

  final RelayClient relay;
  final String provider;
  final String voice;
  final double speed;
  final Future<SpeechSource> Function()? fallback;

  /// Told why the cloud voice stopped, once.
  final void Function(String reason)? onFallback;

  Future<SpeechSource>? _fallback;

  bool get usingFallback => _fallback != null;

  @override
  Future<Speech> speak(String text) async {
    final backup = _fallback;
    if (backup != null) {
      return (await backup).speak(text);
    }
    try {
      return await relay.speech(
        provider: provider,
        voice: voice,
        text: text,
        speed: speed,
      );
    } catch (error) {
      final load = fallback;
      if (load == null) {
        rethrow;
      }
      if (_fallback == null) {
        onFallback?.call('$error');
      }
      return (await (_fallback ??= load())).speak(text);
    }
  }
}
