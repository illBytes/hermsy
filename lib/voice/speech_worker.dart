import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Where each model file lives, as plain strings an isolate can receive.
class EarsPaths {
  const EarsPaths({
    required this.vad,
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
  });

  final String vad;
  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
}

class MouthPaths {
  const MouthPaths({
    required this.model,
    required this.voices,
    required this.tokens,
    required this.dataDir,
    required this.lexicon,
  });

  final String model;
  final String voices;
  final String tokens;
  final String dataDir;
  final String lexicon;
}

/// What the ears heard during a call.
sealed class EarEvent {
  const EarEvent();
}

/// Speech began (Frank should stop talking: barge-in).
class SpeechStarted extends EarEvent {
  const SpeechStarted();
}

/// Speech stopped for a moment (its words follow as [Heard], if any).
class SpeechEnded extends EarEvent {
  const SpeechEnded();
}

/// A finished utterance, already transcribed.
class Heard extends EarEvent {
  const Heard(this.text);

  final String text;
}

/// A background isolate that holds sherpa-onnx models and runs them, so
/// the UI never waits on a model. Each worker is one isolate; voice mode
/// uses two ("ears" for VAD + Parakeet, "mouth" for Kokoro) so Frank can
/// hear an interruption while it is still synthesizing.
class SpeechWorker {
  SpeechWorker._(this._isolate, this._requests, this._replies);

  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _replies;
  final _pending = <int, Completer<Object?>>{};
  final _events = StreamController<EarEvent>.broadcast();
  var _nextId = 0;

  Stream<EarEvent> get events => _events.stream;

  static Future<SpeechWorker> spawn(String name) async {
    final replies = ReceivePort('$name replies');
    final ready = Completer<SendPort>();
    late final SpeechWorker worker;
    replies.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      worker._onMessage(message as Map);
    });
    final isolate = await Isolate.spawn(
      _workerMain,
      replies.sendPort,
      debugName: name,
    );
    worker = SpeechWorker._(isolate, await ready.future, replies);
    return worker;
  }

  void _onMessage(Map message) {
    final event = message['event'];
    if (event == 'speechStart') {
      _events.add(const SpeechStarted());
      return;
    }
    if (event == 'speechEnd') {
      _events.add(const SpeechEnded());
      return;
    }
    if (event == 'heard') {
      _events.add(Heard(message['text'] as String));
      return;
    }
    final completer = _pending.remove(message['id']);
    if (completer == null) {
      return;
    }
    if (message['error'] != null) {
      completer.completeError(StateError(message['error'] as String));
    } else {
      completer.complete(message['result']);
    }
  }

  Future<Object?> _call(String op, [Map<String, Object?> args = const {}]) {
    final id = _nextId++;
    final completer = _pending[id] = Completer<Object?>();
    _requests.send({'id': id, 'op': op, ...args});
    return completer.future;
  }

  /// Loads Silero VAD and Parakeet. [silence] is how long a pause ends a
  /// turn in calls.
  Future<void> loadEars(EarsPaths paths, {double silence = 0.7}) =>
      _call('loadEars', {
        'vad': paths.vad,
        'encoder': paths.encoder,
        'decoder': paths.decoder,
        'joiner': paths.joiner,
        'tokens': paths.tokens,
        'silence': silence,
      });

  /// Transcribes one finished clip of 16 kHz mono samples.
  Future<String> transcribe(Float32List samples) async {
    final result = await _call('transcribe', {
      'samples': TransferableTypedData.fromList([samples]),
    });
    return result as String;
  }

  /// Streams mic samples to the VAD; [events] reports speech and words.
  void listen(Float32List samples) {
    _requests.send({
      'op': 'listen',
      'samples': TransferableTypedData.fromList([samples]),
    });
  }

  /// Forgets any half-heard speech.
  Future<void> resetListening() => _call('resetVad');

  Future<void> loadMouth(MouthPaths paths) => _call('loadMouth', {
    'model': paths.model,
    'voices': paths.voices,
    'tokens': paths.tokens,
    'dataDir': paths.dataDir,
    'lexicon': paths.lexicon,
  });

  /// Speaks [text] with Kokoro voice [voice]: samples and their rate.
  Future<({Float32List samples, int sampleRate})> speak(
    String text, {
    int voice = 0,
    double speed = 1.0,
  }) async {
    final result =
        await _call('speak', {'text': text, 'sid': voice, 'speed': speed})
            as Map;
    return (
      samples: (result['samples'] as TransferableTypedData)
          .materialize()
          .asFloat32List(),
      sampleRate: result['rate'] as int,
    );
  }

  void dispose() {
    _requests.send({'op': 'free'});
    for (final completer in _pending.values) {
      completer.completeError(StateError('voice worker closed'));
    }
    _pending.clear();
    _replies.close();
    _events.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

// ------------------------------------------------------------- the isolate

const _sampleRate = 16000;
const _vadWindow = 512;

void _workerMain(SendPort replies) {
  sherpa.initBindings();
  final requests = ReceivePort();
  replies.send(requests.sendPort);

  sherpa.VoiceActivityDetector? vad;
  sherpa.OfflineRecognizer? recognizer;
  sherpa.OfflineTts? tts;
  var pending = Float32List(0);
  var speaking = false;

  String transcribe(Float32List samples) {
    final asr = recognizer!;
    final stream = asr.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
      asr.decode(stream);
      return asr.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  void drainSegments() {
    final detector = vad!;
    while (!detector.isEmpty()) {
      final segment = detector.front();
      detector.pop();
      final text = transcribe(segment.samples);
      if (text.isNotEmpty) {
        replies.send({'event': 'heard', 'text': text});
      }
    }
  }

  requests.listen((raw) {
    final message = raw as Map;
    final id = message['id'];
    void reply(Object? result) => replies.send({'id': id, 'result': result});
    try {
      switch (message['op']) {
        case 'loadEars':
          vad ??= sherpa.VoiceActivityDetector(
            config: sherpa.VadModelConfig(
              sileroVad: sherpa.SileroVadModelConfig(
                model: message['vad'] as String,
                threshold: 0.5,
                minSilenceDuration: message['silence'] as double,
                minSpeechDuration: 0.25,
                windowSize: _vadWindow,
                // Parakeet takes whole turns; split only very long ones.
                maxSpeechDuration: 25,
              ),
              sampleRate: _sampleRate,
              numThreads: 1,
              debug: false,
            ),
            bufferSizeInSeconds: 60,
          );
          recognizer ??= sherpa.OfflineRecognizer(
            sherpa.OfflineRecognizerConfig(
              model: sherpa.OfflineModelConfig(
                transducer: sherpa.OfflineTransducerModelConfig(
                  encoder: message['encoder'] as String,
                  decoder: message['decoder'] as String,
                  joiner: message['joiner'] as String,
                ),
                tokens: message['tokens'] as String,
                modelType: 'nemo_transducer',
                numThreads: 4,
                debug: false,
              ),
            ),
          );
          reply(null);
        case 'transcribe':
          final samples = (message['samples'] as TransferableTypedData)
              .materialize()
              .asFloat32List();
          reply(transcribe(samples));
        case 'listen':
          final incoming = (message['samples'] as TransferableTypedData)
              .materialize()
              .asFloat32List();
          // The VAD takes whole windows; keep the remainder for next time.
          final joined = Float32List(pending.length + incoming.length)
            ..setAll(0, pending)
            ..setAll(pending.length, incoming);
          final detector = vad!;
          var offset = 0;
          while (offset + _vadWindow <= joined.length) {
            detector.acceptWaveform(
              Float32List.sublistView(joined, offset, offset + _vadWindow),
            );
            offset += _vadWindow;
            final detected = detector.isDetected();
            if (detected && !speaking) {
              replies.send({'event': 'speechStart'});
            } else if (!detected && speaking) {
              replies.send({'event': 'speechEnd'});
            }
            speaking = detected;
            drainSegments();
          }
          pending = Float32List.fromList(
            Float32List.sublistView(joined, offset),
          );
        case 'resetVad':
          vad?.reset();
          pending = Float32List(0);
          speaking = false;
          reply(null);
        case 'loadMouth':
          tts ??= sherpa.OfflineTts(
            sherpa.OfflineTtsConfig(
              model: sherpa.OfflineTtsModelConfig(
                kokoro: sherpa.OfflineTtsKokoroModelConfig(
                  model: message['model'] as String,
                  voices: message['voices'] as String,
                  tokens: message['tokens'] as String,
                  dataDir: message['dataDir'] as String,
                  lexicon: message['lexicon'] as String,
                  lang: 'en-us',
                ),
                numThreads: 4,
                debug: false,
              ),
              maxNumSenetences: 1,
            ),
          );
          reply(null);
        case 'speak':
          final audio = tts!.generate(
            text: message['text'] as String,
            sid: message['sid'] as int,
            speed: message['speed'] as double,
          );
          reply({
            'samples': TransferableTypedData.fromList([audio.samples]),
            'rate': audio.sampleRate,
          });
        case 'free':
          vad?.free();
          recognizer?.free();
          tts?.free();
          vad = null;
          recognizer = null;
          tts = null;
          requests.close();
      }
    } catch (error) {
      if (id != null) {
        replies.send({'id': id, 'error': '$error'});
      }
    }
  });
}
