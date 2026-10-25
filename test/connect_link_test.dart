import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/screens/server_settings_screen.dart';
import 'package:hermes_app/services/connect_link.dart';
import 'package:hermes_app/theme/app_theme.dart';

const key = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  group('connect links', () {
    test('the link from hermes-spawn connect gives the address and key', () {
      final link = parseConnectLink(
        'hermsy://connect?url=https%3A%2F%2F203-0-113-5.sslip.io&key=$key',
      );
      expect(link?.url, 'https://203-0-113-5.sslip.io');
      expect(link?.key, key);
    });

    test('anything else is not taken', () {
      for (final other in [
        'https://example.com',
        'hermsy://connect?url=https%3A%2F%2Fx.example',
        'hermsy://connect?key=$key',
        'hermsy://connect?url=http%3A%2F%2Fx.example&key=$key',
        'hermsy://other?url=https%3A%2F%2Fx.example&key=$key',
        'not a link at all',
        '',
      ]) {
        expect(parseConnectLink(other), isNull, reason: other);
      }
    });
  });

  testWidgets('scanning fills in the server and saves it', (tester) async {
    AppConfig? verified;
    AppConfig? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ServerSettingsScreen(
                    initial: const AppConfig(baseUrl: '', apiKey: ''),
                    verify: (config) async => verified = config,
                    onSave: (config) async => saved = config,
                    scan: (_) async =>
                        (url: 'https://hermes.example.com', key: key),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan QR code'));
    await tester.pumpAndSettle();
    expect(verified?.baseUrl, 'https://hermes.example.com');
    expect(saved?.apiKey, key);
    expect(
      find.byType(ServerSettingsScreen),
      findsNothing,
      reason: 'it closed after saving',
    );
  });
}
