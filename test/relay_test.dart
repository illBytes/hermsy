import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/screens/inbox_screen.dart';
import 'package:hermes_app/screens/message_reader_screen.dart';
import 'package:hermes_app/services/connection_store.dart';
import 'package:hermes_app/services/delivery_inbox.dart';
import 'package:hermes_app/services/push_service.dart';
import 'package:hermes_app/services/relay_client.dart';
import 'package:hermes_app/services/relay_sync.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const config = AppConfig(baseUrl: 'https://relay.example', apiKey: 'key-1234');

Map<String, dynamic> message(
  int seq, {
  String text = 'Body',
  String? title,
  DateTime? at,
}) => {
  'seq': seq,
  'id': 'm$seq',
  'title': title ?? 'Job $seq',
  'text': text,
  'source': 'cron',
  'job_name': 'Job $seq',
  'job_id': 'j$seq',
  'created_at': (at ?? DateTime.utc(2026, 10, 23, 22, 19, 8)).toIso8601String(),
  'received_at': (at ?? DateTime.utc(2026, 10, 23, 22, 19, 8))
      .toIso8601String(),
};

/// The Hermsy plugin on a Hermes, holding [messages] and paging two at a
/// time. [store] names its store; change it to act out a reinstall.
class FakePlugin {
  FakePlugin(this.messages, {this.store = 'store-1'});

  final List<Map<String, dynamic>> messages;
  String store;
  final requests = <Map<String, dynamic>>[];
  var installed = true;

  MockClient get client => MockClient(handle);

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path != '/api/platforms/hermsy/events') {
      return http.Response('not found', 404);
    }
    if (!installed) {
      return http.Response(
        jsonEncode({
          'error': {'code': 'platform_unavailable'},
        }),
        503,
      );
    }
    if (request.headers['Authorization'] != 'Bearer key-1234') {
      return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    requests.add(body);
    Object answer;
    switch (body['op']) {
      case 'register_device' || 'remove_device':
        answer = {'ok': true};
      case 'messages':
        final since = body['since'] as int;
        final page = messages.where((m) => m['seq'] > since).take(2).toList();
        answer = {
          'store': store,
          'messages': page,
          'next': page.isEmpty ? since : page.last['seq'],
        };
      case 'message':
        answer = messages.firstWhere(
          (m) => m['id'] == body['id'],
          orElse: () => {'error': 'no such message', 'status': 404},
        );
      case 'hello':
        answer = {
          'plugin': 'hermsy',
          'version': '2.0.0',
          'store': store,
          'push': true,
          'voices': ['openai'],
          'setup': {
            'brief': {'name': 'Hermsy Brief', 'schedule': '0 5,11,17 * * *'},
            'chief_of_staff': null,
          },
        };
      case 'setup':
        answer = {
          'created': ['Hermsy Brief'],
        };
      case 'speak':
        answer = {
          'audio': base64Encode([0, 0, 255, 127]),
          'sample_rate': 24000,
        };
      default:
        answer = {'error': 'unknown op', 'status': 400};
    }
    return http.Response(jsonEncode(answer), 200);
  }
}

void main() {
  group('RelayClient', () {
    test('talks to the plugin through Hermes with the Hermes key', () async {
      final log = <http.Request>[];
      final plugin = FakePlugin([]);
      final client = RelayClient(
        config,
        httpClient: MockClient((request) {
          log.add(request);
          return plugin.handle(request);
        }),
      );
      await client.registerDevice('fcm-token');
      final request = log.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://relay.example/api/platforms/hermsy/events',
      );
      expect(jsonDecode(request.body), {
        'op': 'register_device',
        'token': 'fcm-token',
        'platform': 'android',
      });
    });

    test('fetches one message', () async {
      final client = RelayClient(
        config,
        httpClient: FakePlugin([message(3, text: 'Hi')]).client,
      );
      final fetched = await client.message('m3');
      expect(fetched.title, 'Job 3');
      expect(fetched.text, 'Hi');
      expect(fetched.seq, 3);
      expect(fetched.createdAt, DateTime.utc(2026, 10, 23, 22, 19, 8));
    });

    test(
      'a bad key, a missing message or no plugin is a RelayException',
      () async {
        final wrong = RelayClient(
          const AppConfig(baseUrl: 'https://relay.example', apiKey: 'nope'),
          httpClient: FakePlugin([]).client,
        );
        await expectLater(
          wrong.registerDevice('t'),
          throwsA(
            isA<RelayException>().having(
              (e) => '$e',
              'says',
              contains('API key'),
            ),
          ),
        );
        final client = RelayClient(config, httpClient: FakePlugin([]).client);
        await expectLater(
          client.message('gone'),
          throwsA(isA<RelayException>()),
        );
        final absent = FakePlugin([])..installed = false;
        await expectLater(
          RelayClient(config, httpClient: absent.client).hello(),
          throwsA(
            isA<RelayException>().having((e) => e.missing, 'missing', isTrue),
          ),
        );
      },
    );

    test('hello says what is set up, and setup sends the time zone', () async {
      final plugin = FakePlugin([]);
      final client = RelayClient(config, httpClient: plugin.client);
      final status = await client.hello();
      expect(status.version, '2.0.0');
      expect(status.push, isTrue);
      expect(status.voices, ['openai']);
      expect(status.brief!.schedule, '0 5,11,17 * * *');
      expect(status.chiefOfStaff, isNull);

      await client.setup(chiefOfStaff: true, timezone: 'Africa/Lagos');
      expect(plugin.requests.firstWhere((r) => r['op'] == 'setup'), {
        'op': 'setup',
        'brief': false,
        'chief_of_staff': true,
        'timezone': 'Africa/Lagos',
      });
    });

    test('cloud speech arrives as samples', () async {
      final client = RelayClient(config, httpClient: FakePlugin([]).client);
      final spoken = await client.speech(
        provider: 'openai',
        voice: 'marin',
        text: 'Hi.',
      );
      expect(spoken.sampleRate, 24000);
      expect(spoken.samples, hasLength(2));
      expect(spoken.samples.last, closeTo(1.0, 0.001));
    });
  });

  group('previews', () {
    test('the preview is the first line without Markdown', () {
      expect(
        relayPreview(
          '## **Due today:** see [the quote](https://x.test)\n\nMore',
        ),
        'Due today: see the quote',
      );
      expect(relayPreview('\n\n- `one` item'), '• one item');
    });

    test('long previews are cut with an ellipsis', () {
      final preview = relayPreview('a' * 300, max: 20);
      expect(preview.length, 20);
      expect(preview.endsWith('…'), isTrue);
    });
  });

  group('RelaySync', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('relay_sync');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => dir.delete(recursive: true));

    test('catches up every page once and remembers where it was', () async {
      final plugin = FakePlugin([message(1), message(2), message(3)]);
      final inbox = DeliveryInbox(dir);
      final sync = RelaySync(
        client: RelayClient(config, httpClient: plugin.client),
        inbox: inbox,
      );

      final added = await sync.catchUp();
      expect(added.map((r) => r.id), ['relay_m1', 'relay_m2', 'relay_m3']);
      final items = await inbox.list();
      expect(items, hasLength(3));
      expect(items.every(isRelayRecord), isTrue);
      expect(items.first.source, 'cron');

      plugin.requests.clear();
      expect(await sync.catchUp(), isEmpty);
      // From where it was, not from the start.
      expect(plugin.requests.single['since'], 3);
    });

    test(
      'a new store (the plugin reinstalled) is read from the start',
      () async {
        final plugin = FakePlugin([message(1), message(2)]);
        final sync = RelaySync(
          client: RelayClient(config, httpClient: plugin.client),
          inbox: DeliveryInbox(dir),
        );
        await sync.catchUp();
        plugin
          ..store = 'store-2'
          ..messages.setAll(0, [
            {...message(1, text: 'Fresh'), 'id': 'n1'},
            {...message(2, text: 'Also fresh'), 'id': 'n2'},
          ]);
        final added = await sync.catchUp();
        expect(added.map((r) => r.id), ['relay_n1', 'relay_n2']);
      },
    );
  });

  group('PushService', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('push_service');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => dir.delete(recursive: true));

    test('a failed registration retries on the next catch-up', () async {
      final connection = ConnectionStore(
        bundled: config,
        vault: MemoryConnectionVault(),
      );
      await connection.load();
      var relayUp = false;
      final registrations = <String>[];
      final plugin = FakePlugin([message(1)]);
      final push = PushService(
        connection: connection,
        openInbox: () async => DeliveryInbox(dir),
        relayFor: (config) => RelayClient(
          config,
          httpClient: MockClient((request) async {
            if (!relayUp) {
              return http.Response('down', 502);
            }
            if (jsonDecode(request.body)['op'] == 'register_device') {
              registrations.add(request.body);
            }
            return plugin.handle(request);
          }),
        ),
      )..debugUseToken('fcm-token');

      await push.catchUp();
      expect(push.registered, isFalse);
      expect(push.relayError, contains('502'));

      relayUp = true;
      await push.catchUp();
      expect(push.registered, isTrue);
      expect(push.relayError, isNull);
      expect(registrations, hasLength(1));
      expect((await DeliveryInbox(dir).list()).single.id, 'relay_m1');

      // Registered once; later catch-ups do not repeat it.
      await push.catchUp();
      expect(registrations, hasLength(1));
    });
  });

  group('notifications from a wake', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('say the title and first line', () {
      final content = notificationContent(
        'Chief of Staff',
        'Quotes are due today.\n\nAlso: call Ade.',
      );
      expect(content.title, 'Chief of Staff');
      expect(content.body, 'Quotes are due today.');
      expect(content.expanded, 'Quotes are due today.\n\nAlso: call Ade.');
      expect(notificationContent('', '').body, 'New message from Hermsy');
      expect(notificationContent('', '').title, 'Hermsy');
    });

    test('show each new message once, and nothing old', () async {
      final now = DateTime.now().toUtc();
      final plugin = FakePlugin([
        message(1, at: now.subtract(const Duration(days: 3))),
        message(2, at: now),
        message(3, at: now),
      ]);
      final shown = <String>[];
      Future<int> wake() => notifyNewMessages(
        config,
        relayFor: (config) => RelayClient(config, httpClient: plugin.client),
        show: (m) async => shown.add(m.id),
      );

      await wake();
      expect(shown, ['m2', 'm3']);
      await wake();
      expect(shown, ['m2', 'm3'], reason: 'already shown');
      plugin.messages.add(message(4, at: now));
      await wake();
      expect(shown, ['m2', 'm3', 'm4']);
    });

    test('what the app already filed is not shown again', () async {
      final now = DateTime.now().toUtc();
      final plugin = FakePlugin([message(1, at: now)]);
      final dir = await Directory.systemTemp.createTemp('wake');
      addTearDown(() => dir.delete(recursive: true));
      await RelaySync(
        client: RelayClient(config, httpClient: plugin.client),
        inbox: DeliveryInbox(dir),
      ).catchUp();
      final shown = <String>[];
      await notifyNewMessages(
        config,
        relayFor: (config) => RelayClient(config, httpClient: plugin.client),
        show: (m) async => shown.add(m.id),
      );
      expect(shown, isEmpty);
    });
  });

  testWidgets('a relay message in the Inbox opens in the reader', (
    tester,
  ) async {
    final record = relayRecord(
      RelayMessage.fromJson(
        message(1, title: 'Morning brief', text: '**Full** text here'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: InboxBody(items: [record])),
      ),
    );
    expect(find.textContaining('**'), findsNothing);
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageReaderScreen), findsOneWidget);
    expect(find.text('Morning brief'), findsWidgets);
    expect(find.textContaining('Full text here'), findsWidgets);
  });
}
