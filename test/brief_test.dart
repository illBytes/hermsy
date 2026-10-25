import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/models/brief.dart';
import 'package:hermes_app/screens/brief_screen.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/services/brief_store.dart';
import 'package:hermes_app/services/brief_widget.dart';
import 'package:hermes_app/services/connection_store.dart';
import 'package:hermes_app/services/delivery_inbox.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/relay_client.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const config = AppConfig(baseUrl: 'https://relay.test', apiKey: 'key-1234');

Map<String, dynamic> briefJson({
  String id = 'b1',
  String headline = 'Quotes are due today.',
}) => {
  'id': id,
  'created_at': '2026-10-24T05:00:00+00:00',
  'greeting': 'Good morning, Alex',
  'headline': headline,
  'summary': 'A light day.',
  'sections': [
    {
      'id': 'today',
      'title': 'Today',
      'items': [
        {'title': 'Dentist', 'time': '16:00', 'detail': 'Bring the card'},
      ],
    },
    {
      'id': 'due',
      'title': 'Due soon',
      'items': [
        {'title': 'Passport renewal', 'when': 'Overdue'},
      ],
    },
    {
      'id': 'suggestions',
      'title': 'Suggestions',
      'items': [
        {
          'title': 'Line up insurers',
          'detail': 'Cover ends soon',
          'action': 'Ask for three quotes',
        },
      ],
    },
    {
      'id': 'money',
      'title': 'Money',
      'items': [
        {'title': 'Cash above target', 'detail': '9.6% against 5%'},
      ],
    },
  ],
};

Future<ConnectionStore> connection() async {
  final store = ConnectionStore(
    bundled: config,
    vault: MemoryConnectionVault(),
  );
  await store.load();
  return store;
}

/// A plugin handing out [briefs] in turn (the last one repeats). Clients
/// made from it share the turn, as the real plugin would.
RelayClient Function(AppConfig) relayServing(
  List<Map<String, dynamic>?> briefs,
) {
  var i = 0;
  final client = MockClient((request) async {
    final next = briefs[i < briefs.length - 1 ? i++ : i];
    return http.Response(jsonEncode({'brief': next}), 200);
  });
  return (config) => RelayClient(config, httpClient: client);
}

class _Hermes extends HermesClient {
  _Hermes() : super(baseUrl: 'https://relay.test', apiKey: 'key-1234');

  final ran = <String>[];
  bool hasJob = true;

  @override
  Future<bool> runJobNamed(String name) async {
    ran.add(name);
    return hasJob;
  }
}

void main() {
  test('a brief reads its sections and round-trips through JSON', () {
    final brief = Brief.fromJson(briefJson());
    expect(brief.section('today')!.items.single.time, '16:00');
    expect(brief.section('due')!.items.single.overdue, isTrue);
    expect(brief.section('nothing'), isNull);
    final again = Brief.fromJson(brief.toJson());
    expect(again.headline, brief.headline);
    expect(
      again.section('suggestions')!.items.single.action,
      'Ask for three quotes',
    );
  });

  group('BriefStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('loads from the relay and keeps a copy for next time', () async {
      final store = BriefStore(
        connection: await connection(),
        relayFor: relayServing([briefJson()]),
      );
      await store.load();
      expect(store.brief!.headline, 'Quotes are due today.');

      final offline = BriefStore(
        connection: await connection(),
        relayFor: (_) => RelayClient(
          config,
          httpClient: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        ),
      );
      await offline.load();
      expect(
        offline.brief!.headline,
        'Quotes are due today.',
        reason: 'from the cache',
      );
      expect(offline.error, isNotNull);
    });

    test(
      'asking for a fresh one runs the job and waits for a new brief',
      () async {
        final hermes = _Hermes();
        final store = BriefStore(
          connection: await connection(),
          relayFor: relayServing([
            briefJson(),
            briefJson(),
            briefJson(id: 'b2', headline: 'Fresh.'),
          ]),
          hermesFor: (_) => hermes,
        );
        await store.load();
        await store.requestFresh(poll: Duration.zero);
        expect(hermes.ran, ['Hermsy Brief']);
        expect(store.brief!.headline, 'Fresh.');
        expect(store.writing, isFalse);
        expect(store.error, isNull);
      },
    );

    test('a fresh brief that comes by push ends the wait too', () async {
      final store = BriefStore(
        connection: await connection(),
        relayFor: relayServing([briefJson(), briefJson(id: 'b2')]),
        hermesFor: (_) => _Hermes(),
      );
      await store.load();
      final waiting = store.requestFresh(
        poll: const Duration(milliseconds: 20),
        timeout: const Duration(seconds: 5),
      );
      // What a push does: refresh, which brings b2.
      await store.refresh();
      await waiting;
      expect(store.brief!.id, 'b2');
      expect(store.error, isNull, reason: 'it did not wait out the timeout');
    });

    test('says so when Hermes has no brief job', () async {
      final hermes = _Hermes()..hasJob = false;
      final store = BriefStore(
        connection: await connection(),
        relayFor: relayServing([null]),
        hermesFor: (_) => hermes,
      );
      await store.requestFresh(poll: Duration.zero);
      // It tried the job's old name too before giving up.
      expect(hermes.ran, ['Hermsy Brief', 'Frank Brief']);
      expect(store.error, contains('Hermsy Brief'));
    });
  });

  testWidgets('the Brief shows sections in your order and hides the rest', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(
      preferences: await SharedPreferences.getInstance(),
    );
    await settings.load();
    await settings.setBriefShown('money', false);
    await settings.setBriefOrder([
      'due',
      'today',
      'suggestions',
      'coming_up',
      'money',
      'updates',
    ]);
    final store = BriefStore(
      connection: await tester.runAsync(connection) as ConnectionStore,
      relayFor: relayServing([briefJson()]),
    )..brief = Brief.fromJson(briefJson());
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('brief'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: BriefScreen(
          store: store,
          settings: settings,
          inbox: DeliveryInbox(dir!),
          now: DateTime(2026, 10, 24, 7),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Good morning, Alex'), findsOneWidget);
    expect(find.text('SATURDAY, 24 OCTOBER'), findsOneWidget);
    expect(find.text('Quotes are due today.'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('16:00'), findsOneWidget);
    expect(
      find.text('Cash above target'),
      findsNothing,
      reason: 'money is hidden',
    );
    final due = tester.getTopLeft(find.text('Passport renewal')).dy;
    final today = tester.getTopLeft(find.text('Dentist')).dy;
    expect(due, lessThan(today), reason: 'due comes first');
    // Without a chat there is nothing to reply in, so no Do it.
    expect(find.text('Do it'), findsNothing);
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  group('home-screen widget', () {
    late AppSettings settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = AppSettings(
        preferences: await SharedPreferences.getInstance(),
      );
      await settings.load();
    });

    test('shows the name, the headline and rows in the Brief order', () {
      final content = briefWidgetContent(Brief.fromJson(briefJson()), settings);
      expect(content.name, 'Alex');
      expect(content.headline, 'Quotes are due today.');
      expect(content.rows.map((r) => r.title), [
        'Dentist',
        'Passport renewal',
      ]);
      expect(content.rows.first.lead, '16:00');
      expect(content.rows[1].lead, 'Overdue');
      expect(content.rows[1].alert, isTrue);
      expect(content.footer, startsWith('1 suggestion · Updated '));
    });

    test('money only when you turn it on; headline and count can go', () async {
      await settings.setWidgetSection('money', true);
      await settings.setWidgetHeadline(false);
      await settings.setWidgetSuggestions(false);
      final content = briefWidgetContent(Brief.fromJson(briefJson()), settings);
      expect(content.rows.map((r) => r.title), contains('Cash above target'));
      expect(content.rows.last.lead, 'Money');
      expect(content.headline, isNull);
      expect(content.footer, startsWith('Updated '));

      final reloaded = AppSettings(
        preferences: await SharedPreferences.getInstance(),
      );
      await reloaded.load();
      expect(reloaded.widgetSections, contains('money'));
      expect(reloaded.widgetHeadline, isFalse);
    });

    test('at most four rows', () {
      final busy = briefJson();
      (busy['sections'] as List)[0] = {
        'id': 'today',
        'title': 'Today',
        'items': [
          for (var i = 0; i < 6; i++) {'title': 'Thing $i', 'time': '0$i:00'},
        ],
      };
      expect(
        briefWidgetContent(Brief.fromJson(busy), settings).rows,
        hasLength(4),
      );
    });

    test('no brief yet: nothing to list', () {
      final content = briefWidgetContent(null, settings);
      expect(content.rows, isEmpty);
      expect(content.headline, isNull);
    });
  });
}
