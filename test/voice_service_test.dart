import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/voice_service.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  const paths = MethodChannel('plugins.flutter.io/path_provider');

  late Directory temp;
  late _FakeRecorder recorder;
  late _FakeSpeech speech;
  late VoiceService voice;
  late List<double> levels;
  late List<String> words;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('frank_voice_service');
    messenger.setMockMethodCallHandler(permissions, (call) async {
      // Microphone (7) granted (1).
      return {7: 1};
    });
    messenger.setMockMethodCallHandler(paths, (call) async => temp.path);
    recorder = _FakeRecorder();
    speech = _FakeSpeech();
    voice = VoiceService(
      recorder: recorder,
      player: _FakePlayer(),
      speech: speech,
    );
    levels = [];
    words = [];
    voice.levels.listen(levels.add);
    voice.partials.listen(words.add);
  });

  tearDown(() async {
    voice.dispose();
    messenger.setMockMethodCallHandler(permissions, null);
    messenger.setMockMethodCallHandler(paths, null);
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  group('recording', () {
    test('turns recorder decibels into levels, and 0 when it stops',
        () async {
      await voice.startRecording();
      recorder.amplitude.add(Amplitude(current: -12, max: -6));
      await pumpEventQueue();
      expect(levels.single, greaterThan(0.5));

      recorder.amplitude.add(Amplitude(current: -160, max: -6));
      await pumpEventQueue();
      expect(levels.last, lessThan(levels.first), reason: 'a softer fall');

      await voice.stopRecording();
      expect(levels.last, 0);
      recorder.amplitude.add(Amplitude(current: -10, max: -6));
      await pumpEventQueue();
      expect(levels.last, 0, reason: 'no samples once stopped');
    });

    test('cancel deletes the take', () async {
      final path = await voice.startRecording();
      File(path).writeAsBytesSync([1, 2, 3]);

      await voice.cancelRecording();

      expect(recorder.cancelled, isTrue);
      expect(File(path).existsSync(), isFalse);
    });
  });

  group('on-device dictation', () {
    test('streams partial words and levels, then returns the final words',
        () async {
      final heard = voice.listenOnDevice();
      await pumpEventQueue();

      speech.soundLevel(8);
      speech.result('turn on', last: false);
      speech.result('turn on the lights', last: true);

      expect(await heard, 'turn on the lights');
      await pumpEventQueue();
      expect(words, ['turn on', 'turn on the lights']);
      expect(levels.first, greaterThan(0.5));
    });

    test('cancel resolves empty and ignores late words', () async {
      final heard = voice.listenOnDevice();
      await pumpEventQueue();
      speech.result('never', last: false);

      await voice.cancelDeviceListen();
      speech.result('never mind', last: true);

      expect(await heard, '');
      await pumpEventQueue();
      expect(speech.cancelled, isTrue);
      expect(words, ['never']);
    });

    test('cancel before the recognizer starts never listens', () async {
      final heard = voice.listenOnDevice();
      await voice.cancelDeviceListen();
      expect(await heard, '');
      expect(speech.listened, isFalse);
    });

    test('ends promptly when the recognizer finishes without words',
        () async {
      final heard = voice.listenOnDevice();
      await pumpEventQueue();
      speech.status(SpeechToText.notListeningStatus);
      speech.status(SpeechToText.doneStatus);
      expect(await heard.timeout(const Duration(seconds: 1)), '');
    });

    test('a recognizer error settles with the words heard', () async {
      final heard = voice.listenOnDevice();
      await pumpEventQueue();
      speech.soundLevel(9);
      speech.result('remind me', last: false);
      speech.error('error_network');
      await pumpEventQueue();

      expect(levels.first, greaterThan(0.5));
      expect(levels.last, 0, reason: 'the mic is closed');
      expect(await heard.timeout(const Duration(seconds: 4)), 'remind me');
    });

    test('stop settles with the words heard if no final result comes',
        () async {
      final heard = voice.listenOnDevice();
      await pumpEventQueue();
      speech.result('call mum', last: false);

      await voice.stopDeviceListen();

      expect(speech.stopped, isTrue);
      expect(await heard.timeout(const Duration(seconds: 4)), 'call mum');
    });
  });
}

class _FakeRecorder implements AudioRecorder {
  final amplitude = StreamController<Amplitude>.broadcast();
  bool cancelled = false;
  String? _path;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    _path = path;
  }

  @override
  Future<String?> stop() async => _path;

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) => amplitude.stream;

  @override
  Future<void> dispose() async {
    await amplitude.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayer implements AudioPlayer {
  @override
  PlayerState get state => PlayerState.stopped;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSpeech implements SpeechToText {
  @override
  SpeechStatusListener? statusListener;

  @override
  SpeechErrorListener? errorListener;

  SpeechResultListener? _onResult;
  SpeechSoundLevelChange? _onLevel;
  bool listened = false;
  bool stopped = false;
  bool cancelled = false;

  void result(String words, {required bool last}) {
    _onResult?.call(
      SpeechRecognitionResult(
        [SpeechRecognitionWords(words, null, 0.9)],
        (last ? ResultType.finalResult : ResultType.partial).value,
      ),
    );
  }

  void soundLevel(double level) => _onLevel?.call(level);

  void status(String value) => statusListener?.call(value);

  void error(String message) =>
      errorListener?.call(SpeechRecognitionError(message, true));

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #initialize) {
      return Future<bool>.value(true);
    }
    if (invocation.memberName == #listen) {
      listened = true;
      _onResult = invocation.namedArguments[#onResult] as SpeechResultListener?;
      _onLevel =
          invocation.namedArguments[#onSoundLevelChange] as SpeechSoundLevelChange?;
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}
