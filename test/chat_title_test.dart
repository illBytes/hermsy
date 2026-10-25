import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/services/conversation_store.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/voice_service.dart';
import 'package:hermes_app/state/chat_controller.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Lets the turn, the title checks and the file writes finish.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a Hermes title is a real name, not empty or a placeholder', () {
    expect(
      hermesChatTitle('  Asking what is going on '),
      'Asking what is going on',
    );
    expect(hermesChatTitle('Frank · 2026-10-23 23:20'), isNull);
    expect(hermesChatTitle('Hermsy · 2026-10-24 14:40'), isNull);
    expect(hermesChatTitle('   '), isNull);
    expect(hermesChatTitle(null), isNull);
    expect(
      titleForPersist(
        messages: const [],
        titleCustom: true,
        currentTitle: 'My name',
        hermesTitle: 'Hermes name',
      ),
      'My name',
      reason: 'your own name wins',
    );
  });

  group('chat titles from Hermes', () {
    late Directory dir;
    late _TitledClient client;
    late ChatController chat;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('chat_title');
      SharedPreferences.setMockInitialValues({});
      client = _TitledClient();
      chat =
          ChatController(
              config: const AppConfig(
                baseUrl: 'https://relay.example',
                apiKey: 'k',
              ),
              client: client,
              preferences: await SharedPreferences.getInstance(),
              store: ConversationStore(dir),
              voice: _QuietVoice(),
            )
            ..hasAudioApi = false
            ..titleChecks = const [Duration.zero, Duration.zero, Duration.zero];
    });

    tearDown(() async {
      await pumpEventQueue();
      chat.dispose();
      await dir.delete(recursive: true);
    });

    test('the first reply brings Hermes\'s name for the chat', () async {
      // Hermes writes a quick title, then its model's better one.
      client.titles = ['Whats going on today', 'Asking what is going on'];
      await chat.send("What's going on today?");
      await settle();

      expect(chat.conversationTitle, 'Asking what is going on');
      expect(chat.history.single.title, 'Asking what is going on');
      final saved = await ConversationStore(dir).read(chat.conversationId!);
      expect(saved!.title, 'Asking what is going on');
      expect(saved.hermesTitle, 'Asking what is going on');

      // A later turn keeps it.
      await chat.send('And tomorrow?');
      await settle();
      expect(chat.history.single.title, 'Asking what is going on');
    });

    test(
      'until Hermes names it, the chat is called by your first words',
      () async {
        client.titles = ['Frank · 2026-10-24 03:00'];
        await chat.send("What's going on today?");
        await settle();
        expect(chat.conversationTitle, "What's going on today?");
      },
    );

    test('an older chat picks up its Hermes name', () async {
      // Three turns before Frank looked for names.
      client.titles = const [];
      for (final text in ['First', 'Second', 'Third']) {
        await chat.send(text);
        await settle();
      }
      expect(chat.conversationTitle, 'First');
      final old = chat.history.single;

      // On the next reply.
      client.titles = ['Daily overview request'];
      await chat.send('Fourth');
      await settle();
      expect(chat.conversationTitle, 'Daily overview request');

      // And on opening it, for one never replied to again.
      await chat.newChat();
      await ConversationStore(dir).read(old.id).then((record) async {
        record!
          ..hermesTitle = null
          ..title = 'First';
        await ConversationStore(dir).write(record);
      });
      client.titles = ['Daily overview request'];
      await chat.openConversation(old);
      await settle();
      expect(chat.conversationTitle, 'Daily overview request');
    });

    test('a chat you renamed keeps your name', () async {
      client.titles = ['Asking what is going on'];
      await chat.send("What's going on today?");
      await settle();
      await chat.renameConversation(chat.history.single, 'Plans');

      client.titles = ['Something else'];
      await chat.send('And tomorrow?');
      await settle();
      expect(chat.conversationTitle, 'Plans');
      expect(chat.history.single.title, 'Plans');
    });
  });
}

/// Hermes with sessions for titles: each turn lands in session s1, and
/// reading the session gives the next of [titles] (the last one repeats).
class _TitledClient extends HermesClient {
  _TitledClient()
    : super(
        baseUrl: 'https://relay.example',
        apiKey: 'k',
        httpClient: _Offline(),
      );

  List<String> titles = const [];
  var _read = 0;

  @override
  Future<HermesSession> createSession({required String title}) =>
      throw SessionsUnsupported();

  @override
  Future<HermesSession> getSession(String sessionId) async {
    final title = titles.isEmpty
        ? null
        : titles[_read < titles.length - 1 ? _read++ : _read];
    return HermesSession(id: sessionId, title: title);
  }

  @override
  Stream<HermesStreamEvent> streamCompletions({
    required String message,
    List<String> imagePaths = const [],
    String? systemMessage,
  }) {
    // What the X-Hermes-Session-Id response header does.
    useTranscript('s1');
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
