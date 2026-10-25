import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/screens/server_settings_screen.dart';
import 'package:hermes_app/screens/settings_screen.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/services/connection_store.dart';
import 'package:hermes_app/services/push_service.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/presence_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ConnectionStore> store() async {
    final connection = ConnectionStore(
      bundled: const AppConfig(
        baseUrl: 'https://relay.example',
        apiKey: 'test-key-1234',
      ),
      vault: MemoryConnectionVault(),
    );
    await connection.load();
    return connection;
  }

  testWidgets('settings can turn on speak replies', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(
      preferences: await SharedPreferences.getInstance(),
    );
    await settings.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: SettingsScreen(
          settings: settings,
          connection: await store(),
          onChangePin: () {},
          onLock: () {},
        ),
      ),
    );

    expect(find.text('Replies stay as text'), findsOneWidget);
    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();
    expect(settings.speakReplies, isFalse);
    await tester.tap(find.text('Speak replies'));
    await tester.pump();
    expect(settings.speakReplies, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Reads replies aloud'), findsOneWidget);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Aura'), findsOneWidget);
    await tester.tap(find.text('Presence'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Twin'), findsOneWidget);
    expect(find.byType(PresencePreview), findsOneWidget);
    expect(find.text('While Hermsy is working'), findsOneWidget);
    // The picker is taller than the 800x600 test screen; Off is last.
    await tester.ensureVisible(find.text('Off'));
    await tester.pump();
    await tester.tap(find.text('Off'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(settings.presence, PresenceStyle.off);
    expect(find.text('No edge glow'), findsOneWidget);
  });

  testWidgets('notifications show only with push', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(
      preferences: await SharedPreferences.getInstance(),
    );
    await settings.load();
    final connection = await store();

    Widget screen({PushService? push}) => MaterialApp(
          theme: buildAppTheme(),
          home: SettingsScreen(
            settings: settings,
            connection: connection,
            push: push,
            onChangePin: () {},
            onLock: () {},
          ),
        );

    await tester.pumpWidget(screen());
    expect(find.text('Notifications'), findsNothing);

    await tester.pumpWidget(screen(push: PushService()));
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Not set up in this build'), findsOneWidget);
  });

  testWidgets('server settings can save a new URL and key', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(
      preferences: await SharedPreferences.getInstance(),
    );
    await settings.load();
    final connection = await store();
    AppConfig? saved;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: SettingsScreen(
          settings: settings,
          connection: connection,
          onChangePin: () {},
          onLock: () {},
          verifyConnection: (_) async {},
          onConnectionSaved: (next) async => saved = next,
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('Hermes'), 200);
    expect(find.textContaining('https://relay.example'), findsOneWidget);
    expect(find.textContaining('••••1234'), findsOneWidget);
    await tester.tap(find.text('Hermes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'https://other.example/');
    await tester.enterText(fields.at(1), 'abcd9999');
    await tester.tap(find.text('Save and check'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(saved?.baseUrl, 'https://other.example');
    expect(saved?.apiKey, 'abcd9999');
    expect(connection.current.baseUrl, 'https://other.example');
  });

  Future<AppSettings> loadSettings() async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(
      preferences: await SharedPreferences.getInstance(),
    );
    await settings.load();
    return settings;
  }

  testWidgets('settings sets glow intensity, reduce motion, and app switcher', (
    tester,
  ) async {
    final settings = await loadSettings();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: SettingsScreen(
          settings: settings,
          connection: await store(),
          onChangePin: () {},
          onLock: () {},
        ),
      ),
    );

    expect(find.text('Aura · balanced glow'), findsOneWidget);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Glow intensity'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    await tester.tap(find.text('Vivid'));
    await tester.pumpAndSettle();
    expect(settings.glowIntensity, GlowIntensity.vivid);

    expect(settings.reduceMotion, isFalse);
    await tester.tap(find.text('Reduce motion'));
    await tester.pumpAndSettle();
    expect(settings.reduceMotion, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Aura · vivid glow · reduced motion'), findsOneWidget);

    await tester.tap(find.text('Privacy & security'));
    await tester.pumpAndSettle();
    expect(settings.hideInSwitcher, isFalse);
    await tester.tap(find.text('Hide in app switcher'));
    await tester.pumpAndSettle();
    expect(settings.hideInSwitcher, isTrue);
  });

  testWidgets('lock after picks a delay and folds away with auto-lock off', (
    tester,
  ) async {
    final settings = await loadSettings();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: SettingsScreen(
          settings: settings,
          connection: await store(),
          onChangePin: () {},
          onLock: () {},
        ),
      ),
    );

    expect(find.text('Locks after 1 minute'), findsOneWidget);
    await tester.tap(find.text('Privacy & security'));
    await tester.pumpAndSettle();
    expect(find.text('1 minute'), findsOneWidget);
    await tester.tap(find.text('Lock after'));
    await tester.pumpAndSettle();
    expect(find.text('Immediately'), findsOneWidget);
    expect(find.text('30 seconds'), findsOneWidget);
    await tester.tap(find.text('5 minutes'));
    await tester.pumpAndSettle();
    expect(settings.autoLockAfter, const Duration(minutes: 5));
    expect(find.text('5 minutes'), findsOneWidget);

    await tester.ensureVisible(find.text('Lock when you leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock when you leave'));
    await tester.pumpAndSettle();
    expect(settings.autoLock, isFalse);
    expect(find.text('Lock after'), findsNothing);

    await tester.tap(find.text('Lock when you leave'));
    await tester.pumpAndSettle();
    expect(find.text('Lock after'), findsOneWidget);
  });

  testWidgets('settings flags a server that is not set up', (tester) async {
    final settings = await loadSettings();
    final connection = ConnectionStore(
      bundled: const AppConfig(baseUrl: '', apiKey: ''),
      vault: MemoryConnectionVault(),
    );
    await connection.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: SettingsScreen(
          settings: settings,
          connection: connection,
          onChangePin: () {},
          onLock: () {},
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('Hermes'), 200);
    expect(find.text('Needs setup'), findsOneWidget);
    expect(find.text('Add your server URL and key'), findsOneWidget);
    expect(find.textContaining('API key'), findsNothing);
  });

  testWidgets('server settings asks for both fields before checking', (
    tester,
  ) async {
    var verified = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ServerSettingsScreen(
          initial: const AppConfig(baseUrl: '', apiKey: ''),
          onSave: (_) async {},
          verify: (_) async => verified++,
        ),
      ),
    );

    expect(find.text('SERVER URL'), findsOneWidget);
    expect(find.text('API KEY'), findsOneWidget);
    await tester.tap(find.text('Save and check'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the HTTPS URL and API key.'), findsOneWidget);
    expect(verified, 0);

    await tester.enterText(find.byType(TextField).first, 'https://x.example');
    await tester.pumpAndSettle();
    expect(find.text('Enter the HTTPS URL and API key.'), findsNothing);
  });

  testWidgets('server settings explains a check that timed out', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ServerSettingsScreen(
          initial: const AppConfig(
            baseUrl: 'https://relay.example',
            apiKey: 'test-key-1234',
          ),
          onSave: (_) async {},
          verify: (_) async => throw TimeoutException('slow'),
        ),
      ),
    );

    await tester.tap(find.text('Save and check'));
    await tester.pumpAndSettle();
    expect(find.textContaining('didn\'t answer in time'), findsOneWidget);
    expect(find.text('Save and check'), findsOneWidget);
  });

  testWidgets('server settings can show and hide the key', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ServerSettingsScreen(
          initial: const AppConfig(
            baseUrl: 'https://relay.example',
            apiKey: 'test-key-1234',
          ),
          onSave: (_) async {},
        ),
      ),
    );

    TextField keyField() =>
        tester.widget<TextField>(find.byType(TextField).at(1));
    expect(keyField().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show key'));
    await tester.pump();
    expect(keyField().obscureText, isFalse);
    expect(find.byTooltip('Hide key'), findsOneWidget);
  });

  testWidgets('settings home lists each area with how it is set', (
    tester,
  ) async {
    final settings = await loadSettings();
    var changingPin = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: Text('Chat')),
      ),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    final connection = await store();
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (context) => SettingsScreen(
            settings: settings,
            connection: connection,
            onChangePin: () => changingPin++,
            onLock: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final area in [
      'Appearance',
      'Voice',
      'Brief',
      'Privacy & security',
    ]) {
      expect(find.text(area), findsOneWidget);
    }
    expect(find.text('Hermes'), findsOneWidget, reason: 'the server first');
    expect(find.text('6 of 6 sections shown'), findsOneWidget);

    // Change PIN is one page in, and goes straight back to the chat.
    await tester.tap(find.text('Privacy & security'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Change PIN'), 200);
    await tester.tap(find.text('Change PIN'));
    await tester.pumpAndSettle();
    expect(changingPin, 1);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Privacy & security'), findsNothing);
  });
}
