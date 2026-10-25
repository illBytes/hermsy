import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/services/frank_haptics.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/voice_service.dart';
import 'package:hermes_app/state/assistant_mood.dart';
import 'package:hermes_app/state/chat_controller.dart';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeVoice voice;
  late _FakeClient client;
  late List<String> buzzes;

  setUp(() {
    voice = _FakeVoice();
    client = _FakeClient();
    buzzes = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        buzzes.add(call.arguments as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  ChatController controller({bool serverSpeech = true, FrankHaptics? haptics}) {
    final chat = ChatController(
      config: const AppConfig(baseUrl: 'https://relay.example', apiKey: 'k'),
      client: client,
      voice: voice,
      haptics: haptics,
    )..hasAudioApi = serverSpeech;
    addTearDown(() async {
      await pumpEventQueue();
      chat.dispose();
    });
    return chat;
  }

  group('server speech-to-text', () {
    test('the mic level follows the recorder and rests at 0 on stop', () async {
      final chat = controller();
      await chat.startVoice();
      expect(chat.recording, isTrue);
      expect(chat.mood, AssistantMood.listening);
      expect(chat.onDeviceDictation, isFalse);

      voice.levelFeed.add(0.42);
      await pumpEventQueue();
      expect(chat.voiceLevel.value, 0.42);

      await chat.stopVoice();
      expect(chat.voiceLevel.value, 0);
      voice.levelFeed.add(0.9);
      await pumpEventQueue();
      expect(chat.voiceLevel.value, 0, reason: 'late samples are ignored');
      expect(client.transcribed, 1);
      expect(chat.messages.first.text, 'hello from voice');
    });

    test('cancel discards the take: no transcription, no message', () async {
      final chat = controller();
      await chat.startVoice();
      voice.levelFeed.add(0.6);
      await pumpEventQueue();

      await chat.cancelVoice();

      expect(voice.calls, contains('cancelRecording'));
      expect(voice.calls, isNot(contains('stopRecording')));
      expect(client.transcribed, 0);
      expect(chat.messages, isEmpty);
      expect(chat.recording, isFalse);
      expect(chat.status, isNull);
      expect(chat.error, isNull);
      expect(chat.voiceLevel.value, 0);
      expect(chat.mood, AssistantMood.idle);
    });

    test('cancel while the mic is still opening discards it once open',
        () async {
      voice.opening = Completer<String>();
      final chat = controller();
      final started = chat.startVoice();
      await pumpEventQueue();

      await chat.cancelVoice();
      voice.opening!.complete('take.m4a');
      await started;

      expect(
        voice.calls.where((call) => call == 'cancelRecording'),
        hasLength(2),
      );
      expect(chat.recording, isFalse);
      expect(chat.messages, isEmpty);
    });

    test('stop while the mic is still opening waits, then sends', () async {
      voice.opening = Completer<String>();
      final chat = controller();
      final started = chat.startVoice();
      await pumpEventQueue();

      final stopped = chat.stopVoice();
      await pumpEventQueue();
      expect(voice.calls, isNot(contains('stopRecording')));

      voice.opening!.complete('take.m4a');
      await started;
      await stopped;

      expect(voice.calls, containsAllInOrder(['startRecording', 'stopRecording']));
      expect(voice.calls, isNot(contains('cancelRecording')));
      expect(chat.messages.first.text, 'hello from voice');
    });

    test('talking again right after a cancel keeps the new recording',
        () async {
      final first = voice.opening = Completer<String>();
      final chat = controller();
      final started = chat.startVoice();
      await pumpEventQueue();
      await chat.cancelVoice();

      // The second take opens at once, but only after the first has
      // finished opening and closing again.
      voice.opening = null;
      final again = chat.startVoice();
      await pumpEventQueue();
      List<String> recorder() =>
          voice.calls.where((call) => call.contains('Recording')).toList();
      expect(recorder(), ['startRecording', 'cancelRecording']);

      first.complete('take1.m4a');
      await started;
      await again;
      expect(recorder(), [
        'startRecording',
        'cancelRecording',
        'cancelRecording',
        'startRecording',
      ]);
      expect(chat.recording, isTrue);

      await chat.stopVoice();
      expect(chat.messages.first.text, 'hello from voice');
    });

    test('a second take waits until the first one is sent', () async {
      client.transcript = Completer<String>();
      final chat = controller();
      await chat.startVoice();
      final stopped = chat.stopVoice();
      // Transcribing from the moment the take is released.
      expect(chat.mood, AssistantMood.transcribing);
      await pumpEventQueue();

      await chat.startVoice();
      expect(chat.recording, isFalse);
      expect(
        voice.calls.where((call) => call == 'startRecording'),
        hasLength(1),
      );

      client.transcript!.complete('first words');
      await stopped;
      expect(chat.messages.first.text, 'first words');
    });

    test('a mic that cannot open still silences Hermsy', () async {
      voice.openError = Exception('Microphone permission denied.');
      final chat = controller();
      await chat.startVoice();
      expect(voice.calls, contains('stopPlayback'));
      expect(chat.recording, isFalse);
      expect(chat.error, contains('Microphone permission denied'));
    });

    test('cancel during transcription drops the transcript', () async {
      client.transcript = Completer<String>();
      final chat = controller();
      await chat.startVoice();
      final stopped = chat.stopVoice();
      await pumpEventQueue();
      expect(chat.mood, AssistantMood.transcribing);

      await chat.cancelVoice();
      expect(chat.mood, AssistantMood.idle);
      client.transcript!.complete('too late');
      await stopped;

      expect(chat.messages, isEmpty);
      expect(chat.error, isNull);
      expect(voice.calls, contains('discard'));
    });
  });

  group('on-device dictation', () {
    test('streams partial words, then sends the final words', () async {
      final chat = controller(serverSpeech: false);
      unawaited(chat.startVoice());
      await pumpEventQueue();
      expect(chat.onDeviceDictation, isTrue);

      voice.wordsFeed.add('what is');
      voice.levelFeed.add(0.3);
      await pumpEventQueue();
      expect(chat.liveTranscript.value, 'what is');
      expect(chat.voiceLevel.value, 0.3);

      await chat.stopVoice();
      expect(chat.mood, AssistantMood.transcribing);
      expect(chat.voiceLevel.value, 0);
      expect(
        chat.liveTranscript.value,
        'what is',
        reason: 'the words stay until they are sent',
      );

      voice.dictation!.complete('what is the weather');
      await pumpEventQueue();
      expect(chat.liveTranscript.value, isEmpty);
      expect(chat.messages.first.text, 'what is the weather');
      expect(client.prompts, ['what is the weather']);
    });

    test('cancel drops the words instead of sending them', () async {
      final chat = controller(serverSpeech: false);
      final take = chat.startVoice();
      await pumpEventQueue();
      voice.wordsFeed.add('never mind');
      await pumpEventQueue();

      await chat.cancelVoice();
      await take;

      expect(voice.calls, contains('cancelDeviceListen'));
      expect(chat.messages, isEmpty);
      expect(chat.error, isNull, reason: 'not "No speech detected."');
      expect(chat.liveTranscript.value, isEmpty);
      expect(chat.recording, isFalse);
    });

    test('silence reports no speech', () async {
      final chat = controller(serverSpeech: false);
      final take = chat.startVoice();
      await pumpEventQueue();
      voice.dictation!.complete('');
      await take;
      expect(chat.error, 'No speech detected.');
      expect(chat.messages, isEmpty);
    });
  });

  test('haptics: mic gestures buzz, ambient taps are muted while recording',
      () async {
    final haptics = FrankHaptics(AppSettings());
    final chat = controller(haptics: haptics);
    await chat.startVoice();
    expect(haptics.muted, isTrue);
    expect(buzzes, ['HapticFeedbackType.mediumImpact']);

    await chat.cancelVoice();
    expect(haptics.muted, isFalse);
    expect(buzzes.last, 'HapticFeedbackType.selectionClick');
  });

  group('speaking', () {
    test('stopSpeaking stops playback and clears the speaking state', () async {
      final dir = await Directory.systemTemp.createTemp('frank_voice_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/reply.mp3')..writeAsBytesSync([1, 2, 3]);
      final chat = controller();
      final reply = ChatMessage(
        id: 'a1',
        role: MessageRole.assistant,
        text: 'Hi',
        audioPath: file.path,
      );

      await chat.playMessage(reply);
      expect(chat.playingId, 'a1');
      expect(chat.mood, AssistantMood.speaking);

      await chat.stopSpeaking();
      expect(chat.playingId, isNull);
      expect(chat.mood, AssistantMood.idle);
      expect(voice.calls.last, 'stopPlayback');
    });

    test('stopping during synthesis keeps the reply from playing', () async {
      client.speech = Completer<List<int>>();
      final chat = controller();
      final reply = ChatMessage(
        id: 'a2',
        role: MessageRole.assistant,
        text: 'A long answer',
      );

      final speaking = chat.speakMessage(reply);
      await pumpEventQueue();
      expect(chat.mood, AssistantMood.speaking);

      await chat.stopSpeaking();
      expect(chat.mood, AssistantMood.idle);
      client.speech!.complete([1, 2, 3]);
      await speaking;

      expect(voice.calls, isNot(contains('play')));
      expect(chat.playingId, isNull);
      expect(chat.error, isNull);
      expect(reply.audioPath, isNotNull, reason: 'kept as a voice note');
    });

    test('a reply being prepared for speech can already be stopped',
        () async {
      client.speech = Completer<List<int>>();
      final chat = controller();
      final reply = ChatMessage(
        id: 'a4',
        role: MessageRole.assistant,
        text: 'Read me',
      );

      final speaking = chat.speakMessage(reply);
      await pumpEventQueue();
      expect(chat.pendingSpeechId, 'a4');
      expect(chat.playingId, isNull);

      await chat.stopSpeaking();
      expect(chat.pendingSpeechId, isNull);
      client.speech!.complete([1, 2, 3]);
      await speaking;
      expect(chat.pendingSpeechId, isNull);
      expect(voice.calls, isNot(contains('play')));
    });

    test('opening the mic silences Hermsy', () async {
      final dir = await Directory.systemTemp.createTemp('frank_voice_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/reply.mp3')..writeAsBytesSync([1]);
      final chat = controller();
      await chat.playMessage(
        ChatMessage(
          id: 'a3',
          role: MessageRole.assistant,
          text: 'Hi',
          audioPath: file.path,
        ),
      );
      await chat.startVoice();
      await chat.cancelVoice();
      expect(chat.playingId, isNull);
      expect(chat.mood, AssistantMood.idle);
    });
  });

  group('streaming', () {
    test('records each started tool once, skipping thinking lines', () async {
      client.reply = const [
        HermesStreamEvent(kind: HermesEventKind.tool, toolName: '_thinking'),
        HermesStreamEvent(
          kind: HermesEventKind.tool,
          toolName: 'web_search',
          toolLabel: 'weather Lagos',
          toolEmoji: '🔍',
        ),
        HermesStreamEvent(
          kind: HermesEventKind.tool,
          toolName: 'web_search',
          toolLabel: 'weather Lagos',
          toolEmoji: '🔍',
        ),
        HermesStreamEvent(
          kind: HermesEventKind.tool,
          toolName: 'web_search',
          toolCompleted: true,
        ),
        HermesStreamEvent(
          kind: HermesEventKind.tool,
          toolName: 'read_file',
          toolLabel: 'notes.md',
          toolEmoji: '📄',
        ),
        HermesStreamEvent(kind: HermesEventKind.delta, text: 'Sunny'),
        HermesStreamEvent(kind: HermesEventKind.done),
      ];
      final chat = controller();
      await chat.send('weather?');
      await pumpEventQueue();

      final reply = chat.messages.last;
      expect(reply.streaming, isFalse);
      expect(reply.toolTrail, ['🔍 weather Lagos…', '📄 notes.md…']);
      final again = ChatMessage.fromJson(reply.toJson());
      expect(again.toolTrail, reply.toolTrail);
    });

    test('streamedChars only grows, by the streamed text', () async {
      client.reply = const [
        HermesStreamEvent(kind: HermesEventKind.delta, text: 'Hel'),
        HermesStreamEvent(kind: HermesEventKind.delta, text: 'lo'),
        HermesStreamEvent(kind: HermesEventKind.done),
      ];
      final chat = controller();
      final seen = <int>[];
      chat.streamedChars.addListener(() => seen.add(chat.streamedChars.value));

      await chat.send('hi');
      await pumpEventQueue();
      await chat.send('again');
      await pumpEventQueue();

      expect(seen, [3, 5, 8, 10]);
    });
  });
}

class _FakeVoice implements VoiceService {
  final levelFeed = StreamController<double>.broadcast();
  final wordsFeed = StreamController<String>.broadcast();
  final completions = StreamController<void>.broadcast();
  final calls = <String>[];
  Completer<String>? opening;
  Completer<String>? dictation;
  Object? openError;

  @override
  Stream<double> get levels => levelFeed.stream;

  @override
  Stream<String> get partials => wordsFeed.stream;

  @override
  Stream<void> get onComplete => completions.stream;

  @override
  Future<String> startRecording() async {
    calls.add('startRecording');
    final error = openError;
    if (error != null) {
      throw error;
    }
    return opening?.future ?? 'take.m4a';
  }

  @override
  Future<String?> stopRecording() async {
    calls.add('stopRecording');
    return 'take.m4a';
  }

  @override
  Future<void> cancelRecording() async => calls.add('cancelRecording');

  @override
  Future<void> discard(String path) async => calls.add('discard');

  @override
  Future<String> listenOnDevice() {
    calls.add('listenOnDevice');
    dictation = Completer<String>();
    return dictation!.future;
  }

  @override
  Future<void> stopDeviceListen() async => calls.add('stopDeviceListen');

  @override
  Future<void> cancelDeviceListen() async {
    calls.add('cancelDeviceListen');
    if (dictation?.isCompleted == false) {
      dictation!.complete('');
    }
  }

  @override
  Future<String> keepRecording(String path) async => path;

  @override
  Future<String> writeSpeechBytes(List<int> bytes, {String? extension}) async =>
      'speech.mp3';

  @override
  bool canPlayExtension(String extension) => true;

  @override
  Future<void> preparePlayback() async {}

  @override
  Future<void> play(String path) async => calls.add('play');

  @override
  Future<void> stopPlayback() async => calls.add('stopPlayback');

  @override
  void dispose() {
    levelFeed.close();
    wordsFeed.close();
    completions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient extends HermesClient {
  _FakeClient()
      : super(
          baseUrl: 'https://relay.example',
          apiKey: 'k',
          httpClient: _Offline(),
        );

  int transcribed = 0;
  Completer<String>? transcript;
  Completer<List<int>>? speech;
  final prompts = <String>[];
  List<HermesStreamEvent> reply = const [
    HermesStreamEvent(kind: HermesEventKind.delta, text: 'On it.'),
    HermesStreamEvent(kind: HermesEventKind.done),
  ];

  @override
  Future<String> transcribe(String filePath) async {
    transcribed++;
    return transcript?.future ?? 'hello from voice';
  }

  @override
  Stream<HermesStreamEvent> streamCompletions({
    required String message,
    List<String> imagePaths = const [],
    String? systemMessage,
  }) {
    prompts.add(message);
    return Stream.fromIterable(reply);
  }

  @override
  Future<List<int>> synthesizeSpeech(String text) async =>
      speech?.future ?? [1, 2, 3];
}

class _Offline extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw http.ClientException('offline');
  }
}
