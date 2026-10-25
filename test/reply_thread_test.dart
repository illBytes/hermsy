import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/services/conversation_store.dart';
import 'package:hermes_app/services/delivery_inbox.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/proactive_reply.dart';
import 'package:hermes_app/services/voice_service.dart';
import 'package:hermes_app/state/chat_controller.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

final brief = DeliveryRecord(
  id: 'relay_m1',
  title: 'Chief of Staff (Proactive)',
  body: 'Travel insurance quotes are due today.',
  createdAt: DateTime(2026, 10, 23, 23, 19),
  source: 'cron',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hermesPromptFor', () {
    final proactive = ChatMessage(
      id: '${proactiveMessagePrefix}relay_m1',
      role: MessageRole.assistant,
      text: 'Quotes are due today.',
      createdAt: DateTime(2026, 10, 23, 23, 19),
    );

    test('the first reply quotes the message it answers', () {
      final prompt = hermesPromptFor(
        [proactive],
        'Remind me at 5pm',
        title: 'Chief of Staff (Proactive)',
      );
      expect(
        prompt,
        startsWith(
          '[Replying to your earlier message from "Chief of Staff (Proactive)", sent 2026-10-23 23:19:',
        ),
      );
      expect(prompt, contains('Quotes are due today.'));
      expect(prompt, endsWith('\n---]\n\nRemind me at 5pm'));
    });

    test('later replies and ordinary chats send the text as typed', () {
      final reply = ChatMessage(id: 'u1', role: MessageRole.user, text: 'Hi');
      expect(hermesPromptFor([proactive, reply], 'And?'), 'And?');
      expect(hermesPromptFor([], 'Hello'), 'Hello');
      final ordinary = ChatMessage(
        id: 'a1',
        role: MessageRole.assistant,
        text: 'x',
      );
      expect(hermesPromptFor([ordinary], 'Hello'), 'Hello');
    });

    test('a stored first reply splits back into the quote and the reply', () {
      final stored = hermesPromptFor(
        [proactive],
        'Remind me at 5pm',
        title: 'Job',
      );
      final split = splitProactivePrompt(stored);
      expect(split.quoted, 'Quotes are due today.');
      expect(split.text, 'Remind me at 5pm');
      expect(splitProactivePrompt('plain').quoted, isNull);
    });
  });

  group('ChatController.replyTo', () {
    late Directory dir;
    late _RecordingClient client;
    late ChatController chat;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('reply_thread');
      SharedPreferences.setMockInitialValues({});
      client = _RecordingClient();
      chat = ChatController(
        config: const AppConfig(baseUrl: 'https://relay.example', apiKey: 'k'),
        client: client,
        preferences: await SharedPreferences.getInstance(),
        store: ConversationStore(dir),
        voice: _QuietVoice(),
      )..hasAudioApi = false;
    });

    tearDown(() async {
      await pumpEventQueue();
      chat.dispose();
      await dir.delete(recursive: true);
    });

    test(
      'opens a thread that starts with the message, titled by its job',
      () async {
        await chat.replyTo(brief);
        expect(chat.conversationTitle, 'Chief of Staff (Proactive)');
        expect(chat.messages, hasLength(1));
        expect(chat.messages.single.isAssistant, isTrue);
        expect(chat.messages.single.text, brief.body);
        expect(chat.history.single.title, 'Chief of Staff (Proactive)');
      },
    );

    test('Hermes gets the message with the first reply only', () async {
      await chat.replyTo(brief);
      await chat.send('Book the cheapest one');
      await pumpEventQueue();
      await chat.send('Thanks');
      await pumpEventQueue();

      expect(client.prompts, hasLength(2));
      expect(client.prompts.first, contains(brief.body));
      expect(client.prompts.first, endsWith('Book the cheapest one'));
      expect(client.prompts.last, 'Thanks');
      // On the phone the reply reads as typed.
      expect(chat.messages[1].text, 'Book the cheapest one');
      expect(chat.conversationTitle, 'Chief of Staff (Proactive)');
    });

    test('replying again reopens the same thread', () async {
      await chat.replyTo(brief);
      final thread = chat.conversationId;
      await chat.send('Book it');
      await pumpEventQueue();
      await chat.newChat();
      expect(chat.conversationId, isNot(thread));

      await chat.replyTo(brief);
      expect(chat.conversationId, thread);
      expect(chat.messages.map((m) => m.text), contains('Book it'));
    });
  });
}

/// Hermes without sessions: every turn goes through completions, and the
/// prompts it was sent are kept.
class _RecordingClient extends HermesClient {
  _RecordingClient()
    : super(
        baseUrl: 'https://relay.example',
        apiKey: 'k',
        httpClient: _Offline(),
      );

  final prompts = <String>[];

  @override
  Future<HermesSession> createSession({required String title}) =>
      throw SessionsUnsupported();

  @override
  Stream<HermesStreamEvent> streamCompletions({
    required String message,
    List<String> imagePaths = const [],
    String? systemMessage,
  }) {
    prompts.add(message);
    return Stream.fromIterable(const [
      HermesStreamEvent(kind: HermesEventKind.delta, text: 'On it.'),
      HermesStreamEvent(kind: HermesEventKind.done),
    ]);
  }
}

/// A voice that is never used here: playback and recording are no-ops.
class _QuietVoice implements VoiceService {
  @override
  Stream<void> get onComplete => const Stream.empty();

  @override
  Stream<String> get partials => const Stream.empty();

  @override
  Stream<double> get levels => const Stream.empty();

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Offline extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw http.ClientException('offline');
  }
}
