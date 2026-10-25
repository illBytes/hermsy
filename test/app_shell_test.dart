import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/main.dart';
import 'package:hermes_app/presence/presence_engine.dart';
import 'package:hermes_app/screens/brief_screen.dart';
import 'package:hermes_app/screens/chat_screen.dart';
import 'package:hermes_app/screens/pin_screen.dart';
import 'package:hermes_app/screens/set_pin_screen.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/services/connection_store.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/pin_vault.dart';
import 'package:hermes_app/services/voice_service.dart';
import 'package:hermes_app/state/chat_controller.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Shell> pumpApp(
    WidgetTester tester, {
    String? pin,
    Stream<Uri?>? widgetTaps,
  }) async {
    final shell = _Shell(pin: pin);
    await tester.pumpWidget(
      FrankApp(
        connection: ConnectionStore(vault: MemoryConnectionVault()),
        vault: shell.vault,
        settings: shell.settings,
        widgetTaps: widgetTaps,
        chatBuilder: shell.build,
      ),
    );
    // Vault and settings load asynchronously.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return shell;
  }

  Future<void> enter(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tester.tap(find.text(digit).first);
      await tester.pump();
    }
  }

  /// Sends a lifecycle change the way the engine does, so Flutter fills in
  /// the intermediate states (resumed -> inactive -> hidden -> paused).
  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> leaveFor(WidgetTester tester, Duration away) async {
    await lifecycle(tester, AppLifecycleState.paused);
    await tester.runAsync(() => Future<void>.delayed(away));
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> unlock(WidgetTester tester) async {
    await enter(tester, '1234');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 700));
  }

  PresenceEngine engineOf(WidgetTester tester) {
    return PresenceScope.of(tester.element(find.byType(Navigator).first));
  }

  testWidgets('unlocking plays the beat, then shows the chat and lights it', (
    tester,
  ) async {
    final shell = await pumpApp(tester, pin: '1234');
    expect(find.byType(PinScreen), findsOneWidget);
    // Nothing private is built behind the lock.
    expect(find.byType(ChatScreen), findsNothing);
    expect(shell.chats, isEmpty);

    await enter(tester, '1234');
    // The dots fly into the orb before the hand-off.
    expect(find.byType(ChatScreen), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(PinScreen), findsNothing);
    final engine = engineOf(tester);
    expect(engine.lastEvent, PresenceEvent.unlock);
    expect(engine.chat, same(shell.chats.single));

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('locking drops the chat at once and detaches the glow', (
    tester,
  ) async {
    await pumpApp(tester, pin: '1234');
    await enter(tester, '1234');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 700));

    tester.widget<ChatScreen>(find.byType(ChatScreen)).onLock();
    await tester.pump();

    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(PinScreen), findsOneWidget);
    expect(engineOf(tester).chat, isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('auto-lock measures the time away, not the trip back', (
    tester,
  ) async {
    final shell = await pumpApp(tester, pin: '1234');
    await shell.settings.setAutoLockAfter(const Duration(seconds: 1));
    await unlock(tester);
    expect(find.byType(ChatScreen), findsOneWidget);

    // A short trip stays unlocked.
    await leaveFor(tester, Duration.zero);
    expect(find.byType(ChatScreen), findsOneWidget);

    // Longer than the delay locks on return.
    await leaveFor(tester, const Duration(milliseconds: 1200));
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(PinScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a widget tap after the auto-lock opens the Brief on unlock', (
    tester,
  ) async {
    final taps = StreamController<Uri?>();
    addTearDown(taps.close);
    final shell = await pumpApp(tester, pin: '1234', widgetTaps: taps.stream);
    await shell.settings.setAutoLockAfter(const Duration(seconds: 1));
    await unlock(tester);

    // Away long enough to lock; Android hands over the tap just before
    // Frank is back in front, while it still counts as unlocked.
    await lifecycle(tester, AppLifecycleState.paused);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1200)),
    );
    taps.add(Uri.parse('frank://brief'));
    await tester.pump();
    // Android brings Frank back in two steps, drawing in between.
    await lifecycle(tester, AppLifecycleState.inactive);
    await tester.pump();
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PinScreen), findsOneWidget);
    expect(find.byType(BriefScreen), findsNothing);

    await unlock(tester);
    // One frame to push the page, then its transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(BriefScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a widget tap while unlocked opens the Brief once in front', (
    tester,
  ) async {
    final taps = StreamController<Uri?>();
    addTearDown(taps.close);
    await pumpApp(tester, pin: '1234', widgetTaps: taps.stream);
    await unlock(tester);

    await lifecycle(tester, AppLifecycleState.paused);
    taps.add(Uri.parse('frank://brief'));
    await tester.pump();
    expect(find.byType(BriefScreen), findsNothing, reason: 'still away');
    await lifecycle(tester, AppLifecycleState.inactive);
    await tester.pump();
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(BriefScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a live call is not cut off by the auto-lock', (tester) async {
    final shell = await pumpApp(tester, pin: '1234');
    await shell.settings.setAutoLockAfter(const Duration(seconds: 1));
    await unlock(tester);
    shell.chats.last.inCall = true;

    await leaveFor(tester, const Duration(milliseconds: 1200));
    expect(
      find.byType(ChatScreen),
      findsOneWidget,
      reason: 'still on the call',
    );

    // The call ends while Frank is away: the lock counts from then.
    await lifecycle(tester, AppLifecycleState.paused);
    shell.chats.last.inCall = false;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1200)),
    );
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PinScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a lock during Change PIN shows the lock, not the PIN editor', (
    tester,
  ) async {
    final shell = await pumpApp(tester, pin: '1234');
    await shell.settings.setAutoLockAfter(Duration.zero);
    await unlock(tester);

    tester.widget<ChatScreen>(find.byType(ChatScreen)).onChangePin!();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(SetPinScreen), findsOneWidget);

    await leaveFor(tester, Duration.zero);
    expect(find.byType(SetPinScreen), findsNothing);
    expect(find.byType(PinScreen), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
    final stored = (await shell.vault.read())!;
    expect(await stored.matches('1234'), isTrue);
    expect(
      shell.vault.saved[PinVault.storageKey],
      isNot(contains('1234')),
      reason: 'kept as a hash, never as the PIN',
    );

    // Unlocking returns to the chat, not to a half-done PIN change.
    await unlock(tester);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(SetPinScreen), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('locking removes open pages without animating them out', (
    tester,
  ) async {
    await pumpApp(tester, pin: '1234');
    await unlock(tester);

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Private page')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Private page'), findsOneWidget);

    tester
        .widget<ChatScreen>(find.byType(ChatScreen, skipOffstage: false))
        .onLock();
    await tester.pump();

    expect(find.text('Private page', skipOffstage: false), findsNothing);
    expect(find.byType(PinScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('creating the first PIN goes straight to the chat', (
    tester,
  ) async {
    final shell = await pumpApp(tester);
    expect(find.byType(SetPinScreen), findsOneWidget);

    await enter(tester, '2468');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 400));
    await enter(tester, '2468');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Save PIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    final stored = (await shell.vault.read())!;
    expect(await stored.matches('2468'), isTrue);
    expect(
      shell.vault.saved[PinVault.storageKey],
      isNot(contains('2468')),
      reason: 'kept as a hash, never as the PIN',
    );
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(engineOf(tester).lastEvent, PresenceEvent.unlock);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('reduce motion reaches every route without rebuilding the chat', (
    tester,
  ) async {
    final shell = await pumpApp(tester, pin: '1234');
    await enter(tester, '1234');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 700));

    final before = tester.state(find.byType(ChatScreen));
    BuildContext chatContext() => tester.element(find.byType(ChatScreen));
    expect(MediaQuery.disableAnimationsOf(chatContext()), isFalse);

    await shell.settings.setReduceMotion(true);
    await tester.pump();

    expect(MediaQuery.disableAnimationsOf(chatContext()), isTrue);
    expect(tester.state(find.byType(ChatScreen)), same(before));
    expect(engineOf(tester).reduceMotion, isTrue);

    await shell.settings.setReduceMotion(false);
    await tester.pump();
    expect(MediaQuery.disableAnimationsOf(chatContext()), isFalse);
    expect(tester.state(find.byType(ChatScreen)), same(before));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('light and dark follow the system, keeping the chat', (
    tester,
  ) async {
    addTearDown(() {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      AppColors.use(Brightness.dark);
    });
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    AppColors.use(Brightness.dark);
    await pumpApp(tester, pin: '1234');
    await unlock(tester);
    final before = tester.state(find.byType(ChatScreen));
    BuildContext chatContext() => tester.element(find.byType(ChatScreen));
    expect(Theme.of(chatContext()).brightness, Brightness.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    expect(AppColors.isDark, isFalse);
    expect(AppColors.background, FrankPalette.light.background);
    expect(Theme.of(chatContext()).brightness, Brightness.light);
    expect(tester.state(find.byType(ChatScreen)), same(before));

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(AppColors.isDark, isTrue);
    expect(Theme.of(chatContext()).brightness, Brightness.dark);
    expect(tester.state(find.byType(ChatScreen)), same(before));
    await tester.pump(const Duration(seconds: 3));
  });
}

class _Shell {
  _Shell({String? pin}) : vault = _MemoryPinVault(pin);

  final _MemoryPinVault vault;
  final settings = AppSettings();
  final chats = <ChatController>[];

  ChatController build(AppConfig config) {
    final chat = ChatController(
      config: config,
      client: HermesClient(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        httpClient: MockClient((_) async => http.Response('', 503)),
      ),
      voice: _QuietVoice(),
      settings: settings,
    );
    chats.add(chat);
    return chat;
  }
}

/// The PIN vault in memory, with few hash rounds so tests stay quick. The
/// first PIN is stored as an older Frank stored it, in the clear.
class _MemoryPinVault extends PinVault {
  _MemoryPinVault(String? pin) : super(iterations: 1000) {
    if (pin != null) {
      saved[PinVault.storageKey] = pin;
    }
  }

  final saved = <String, String>{};

  @override
  Future<String?> load(String key) async => saved[key];

  @override
  Future<void> save(String key, String? value) async =>
      value == null ? saved.remove(key) : saved[key] = value;
}

class _QuietVoice implements VoiceService {
  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
