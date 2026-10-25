import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/services/relay_client.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/plugin_setup.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const config = AppConfig(baseUrl: 'https://hermes.test', apiKey: 'key-1234');

Widget host(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('without the plugin it says how to install it', (tester) async {
    await tester.pumpWidget(
      host(
        PluginSetupSection(
          config: config,
          clientFor: (config) => RelayClient(
            config,
            httpClient: MockClient(
              (_) async => http.Response('not found', 404),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not installed'), findsOneWidget);
    expect(find.text(pluginInstallCommand), findsOneWidget);
  });

  testWidgets('a tap sets up the Chief of Staff in the phone\'s time zone', (
    tester,
  ) async {
    Map<String, dynamic>? chief;
    final setups = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['op'] == 'setup') {
        setups.add(body);
        chief = {'name': 'Chief of Staff', 'schedule': '30 6,11,17 * * *'};
        return http.Response(
          jsonEncode({
            'created': ['Chief of Staff'],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'plugin': 'hermsy',
          'version': '2.0.0',
          'store': 's',
          'push': true,
          'voices': <String>[],
          'setup': {
            'brief': {'name': 'Hermsy Brief', 'schedule': '0 5,11,17 * * *'},
            'chief_of_staff': chief,
          },
        }),
        200,
      );
    });
    await tester.pumpWidget(
      host(
        PluginSetupSection(
          config: config,
          clientFor: (config) => RelayClient(config, httpClient: client),
          timeZone: () async => 'Africa/Lagos',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    expect(find.textContaining('OPENAI_API_KEY'), findsOneWidget);
    expect(
      find.text('Set up'),
      findsOneWidget,
      reason: 'the Brief is set up already',
    );

    await tester.tap(find.text('Set up'));
    await tester.pumpAndSettle();
    expect(setups.single['chief_of_staff'], isTrue);
    expect(setups.single['timezone'], 'Africa/Lagos');
    expect(find.text('Set up'), findsNothing);
    expect(find.textContaining('30 6,11,17'), findsOneWidget);
  });
}
