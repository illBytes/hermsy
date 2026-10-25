// Design screenshots of the real app at Galaxy S26 Ultra size.
//
//   SHOTS_DIR=/tmp/frank_shots flutter test tool/shots/shots_test.dart
//
// Add SHOTS_THEME=light for the light palette.
//
// Renders through the real shell (lock, glow layer, chat) with a scripted
// Hermes server and a fake mic, so nothing touches the network or hardware.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/main.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/screens/call_screen.dart';
import 'package:hermes_app/screens/inbox_screen.dart';
import 'package:hermes_app/screens/message_reader_screen.dart';
import 'package:hermes_app/screens/server_settings_screen.dart';
import 'package:hermes_app/screens/settings_screen.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/services/connection_store.dart';
import 'package:hermes_app/services/delivery_inbox.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/voice_models.dart';
import 'package:hermes_app/state/chat_controller.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/voice/call_controller.dart';
import 'package:hermes_app/voice/on_device_voice.dart';
import 'package:hermes_app/voice/speech_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shot_kit.dart';
import 'shot_rig.dart';

const _reply1 = '''Here's what's on your plate for **Saturday, October 3**:

1. **Thumbnail + SEO** for the A57 review — due tonight
2. **Pay rent** — marked done this morning
3. Reply to Ada about the *Lagos shoot* schedule

The forecast for Lagos tomorrow is **31°C with afternoon storms**, so plan the outdoor shots before 1 pm.

> Tip: say "remind me at noon" and I'll ping you.''';

const _reply2 = '''Sure — here's a tiny script that renames the exports:

```bash
for f in exports/*.png; do
  mv "\$f" "\${f%.png}_a57.png"
done
```

Run it from the project root. It only touches `exports/`.''';

void main() {
  late Directory temp;

  final brightness = Platform.environment['SHOTS_THEME'] == 'light'
      ? Brightness.light
      : Brightness.dark;

  setUpAll(() async {
    await loadShotFonts();
    AppColors.use(brightness);
  });

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('frank_shots_');
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<ShotRig> pumpApp(
    WidgetTester tester, {
    String? pin = '1234',
    bool healthy = true,
  }) async {
    usePhoneView(tester);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    final rig = ShotRig(temp, pin: pin, healthy: healthy);
    final connection = ConnectionStore(
      bundled: const AppConfig(
        baseUrl: 'https://hermes.example.com',
        apiKey: 'shot-key-0000',
      ),
      vault: MemoryConnectionVault(),
    );
    await tester.runAsync(connection.load);
    await tester.pumpWidget(
      RepaintBoundary(
        key: rig.boundary,
        child: FrankApp(
          connection: connection,
          vault: rig.vault,
          settings: rig.settings,
          chatBuilder: rig.build,
        ),
      ),
    );
    await realAsync(tester);
    await settleFor(tester, const Duration(milliseconds: 900));
    return rig;
  }

  Future<void> enter(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tester.tap(find.text(digit).first);
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> unlock(WidgetTester tester, ShotRig rig) async {
    await enter(tester, '1234');
    await settleFor(tester, const Duration(milliseconds: 1400));
    // Let start() talk to the fake server.
    for (var i = 0; i < 80; i++) {
      await realAsync(tester, const Duration(milliseconds: 25));
      await tester.pump(const Duration(milliseconds: 50));
      if (rig.chats.isNotEmpty && !rig.chats.last.loading) {
        break;
      }
    }
    await settleFor(tester, const Duration(milliseconds: 600));
  }

  Future<void> pumpStream(WidgetTester tester, [int rounds = 4]) async {
    for (var i = 0; i < rounds; i++) {
      await realAsync(tester, const Duration(milliseconds: 30));
    }
  }

  testWidgets('lock and set PIN', (tester) async {
    final rig = await pumpApp(tester);
    await settleFor(tester, const Duration(milliseconds: 1200));
    await saveShot(tester, rig.boundary, '01_lock_idle');

    await enter(tester, '12');
    await settleFor(tester, const Duration(milliseconds: 300));
    await saveShot(tester, rig.boundary, '02_lock_typing');

    await enter(tester, '99');
    await tester.pump(const Duration(milliseconds: 160));
    await saveShot(tester, rig.boundary, '03_lock_wrong');
    await settleFor(tester, const Duration(seconds: 2));
  });

  testWidgets('create PIN', (tester) async {
    final rig = await pumpApp(tester, pin: null);
    await enter(tester, '12');
    await settleFor(tester, const Duration(milliseconds: 600));
    await saveShot(tester, rig.boundary, '04_set_pin');
    await settleFor(tester, const Duration(seconds: 2));
  });

  testWidgets('conversation flow', (tester) async {
    final rig = await pumpApp(tester);
    await unlock(tester, rig);
    await saveShot(tester, rig.boundary, '05_chat_empty');

    // Slash palette.
    await tester.enterText(find.byType(TextField).last, '/');
    await settleFor(tester, const Duration(milliseconds: 400));
    await saveShot(tester, rig.boundary, '06_slash_palette');

    // Typed message.
    await tester.enterText(find.byType(TextField).last, "What's on my plate today?");
    await settleFor(tester, const Duration(milliseconds: 400));
    await saveShot(tester, rig.boundary, '07_typing');

    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await pumpStream(tester);
    await settleFor(tester, const Duration(milliseconds: 140), steps: 4);
    await saveShot(tester, rig.boundary, '08_send_bloom');
    await settleFor(tester, const Duration(milliseconds: 900));
    await saveShot(tester, rig.boundary, '09_thinking');

    rig.hermes.tool('web_search', 'weather Lagos tomorrow', emoji: '🔍');
    await pumpStream(tester);
    await settleFor(tester, const Duration(milliseconds: 700));
    await saveShot(tester, rig.boundary, '10_tool');

    rig.hermes.toolDone('web_search');
    rig.hermes.tool('read_file', 'notes/todo.md', emoji: '📄');
    await pumpStream(tester);
    rig.hermes.toolDone('read_file');
    final half = _reply1.length ~/ 2;
    rig.hermes.words(_reply1.substring(0, half));
    await pumpStream(tester, 8);
    await settleFor(tester, const Duration(milliseconds: 500));
    await saveShot(tester, rig.boundary, '11_responding');

    rig.hermes.words(_reply1.substring(half));
    rig.hermes.finish();
    await pumpStream(tester, 8);
    await settleFor(tester, const Duration(milliseconds: 240), steps: 6);
    await saveShot(tester, rig.boundary, '12_done_sweep');
    await settleFor(tester, const Duration(milliseconds: 2400));
    await saveShot(tester, rig.boundary, '13_reply_done');

    // A second exchange with code.
    await tester.enterText(find.byType(TextField).last, 'Write me a script to rename the exports');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await pumpStream(tester);
    rig.hermes.words(_reply2);
    rig.hermes.finish();
    await pumpStream(tester, 10);
    await settleFor(tester, const Duration(milliseconds: 2600));
    await saveShot(tester, rig.boundary, '14_conversation_code');

    // Message actions sheet.
    await tester.longPress(find.textContaining('Run it from the project root'));
    await settleFor(tester, const Duration(milliseconds: 500));
    await saveShot(tester, rig.boundary, '15_message_actions');
    await tester.tapAt(const Offset(200, 120));
    await settleFor(tester, const Duration(milliseconds: 500));

    // Conversation sheet from the header title.
    await tester.tap(find.textContaining("What's on my plat").first);
    await settleFor(tester, const Duration(milliseconds: 500));
    await saveShot(tester, rig.boundary, '16_conversation_sheet');
    await tester.tapAt(const Offset(200, 120));
    await settleFor(tester, const Duration(milliseconds: 500));

    // Listening with a live mic level.
    final chat = rig.chats.single;
    unawaited(chat.startVoice());
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      rig.voice.levelFeed.add(0.25 + 0.6 * ((i * 7) % 10) / 10);
      await realAsync(tester, const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await saveShot(tester, rig.boundary, '17_listening');
    await chat.cancelVoice();
    await settleFor(tester, const Duration(milliseconds: 900));

    // Drawer, with two unread in the Inbox.
    DeliveryInbox.unread.value = 2;
    await tester.tap(find.byTooltip('Chats'));
    await settleFor(tester, const Duration(milliseconds: 800));
    await saveShot(tester, rig.boundary, '18_drawer');
    await tester.tapAt(const Offset(370, 400));
    await settleFor(tester, const Duration(milliseconds: 600));
    DeliveryInbox.unread.value = 0;

    // A failed reply: the provider answers 502.
    rig.hermes.nextStatus = 502;
    await tester.enterText(find.byType(TextField).last, 'Book the studio for Monday');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await pumpStream(tester);
    rig.hermes.finish();
    await pumpStream(tester);
    await settleFor(tester, const Duration(milliseconds: 500));
    await saveShot(tester, rig.boundary, '19_error');
    await settleFor(tester, const Duration(seconds: 3));
  });

  testWidgets('offline', (tester) async {
    final rig = await pumpApp(tester, healthy: false);
    await unlock(tester, rig);
    await settleFor(tester, const Duration(milliseconds: 800));
    await saveShot(tester, rig.boundary, '20_offline');
    await settleFor(tester, const Duration(seconds: 2));
  });

  testWidgets('settings and secondary screens', (tester) async {
    usePhoneView(tester);
    final boundary = GlobalKey();
    final settings = AppSettings(preferences: await SharedPreferences.getInstance());
    await settings.load();
    final connection = ConnectionStore(
      bundled: const AppConfig(baseUrl: 'https://hermes.example.com', apiKey: 'test-key-1234'),
      vault: MemoryConnectionVault(),
    );
    await connection.load();

    Future<void> show(Widget home, String name, {Duration wait = const Duration(milliseconds: 700)}) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            key: ValueKey(name),
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(brightness),
            home: home,
          ),
        ),
      );
      await realAsync(tester);
      await settleFor(tester, wait);
      await saveShot(tester, boundary, name);
    }

    await show(
      SettingsScreen(
        settings: settings,
        connection: connection,
        onChangePin: () {},
        onLock: () {},
      ),
      '21_settings',
    );
    await tester.tap(find.text('Appearance'));
    await settleFor(tester, const Duration(milliseconds: 700));
    await saveShot(tester, boundary, '21b_settings_appearance');
    await tester.tap(find.text('Presence'));
    await settleFor(tester, const Duration(milliseconds: 1600));
    await saveShot(tester, boundary, '22_presence_picker');
    await show(
      SettingsScreen(
        settings: settings,
        connection: connection,
        onChangePin: () {},
        onLock: () {},
      ),
      '21a_settings_again',
    );
    await tester.tap(find.text('Privacy & security'));
    await settleFor(tester, const Duration(milliseconds: 700));
    await saveShot(tester, boundary, '21c_settings_privacy');

    await show(
      ServerSettingsScreen(initial: connection.current, onSave: (_) async {}),
      '23_server_settings',
    );

    final inbox = DeliveryInbox(Directory('${temp.path}/inbox'));
    await show(InboxScreen(inbox: inbox), '24_inbox_empty');

    await show(
      MessageReaderScreen(
        message: ChatMessage(id: 'r1', role: MessageRole.assistant, text: _reply1),
      ),
      '25_reader',
    );

    // A call mid-reply, its caption running past the top edge.
    final callChat = ChatController(
      config: connection.current,
      client: HermesClient(baseUrl: 'https://hermes.example.com', apiKey: 'k'),
      voice: ShotVoice(),
      settings: settings,
    );
    final onDevice = OnDeviceVoice(VoiceModelStore(root: temp));
    // No players: nothing plays in a screenshot.
    final call = CallController(
      chat: callChat,
      voice: onDevice,
      player: SpeechPlayer(players: []),
    )
      ..phase = CallPhase.speaking
      ..heard = 'What should I know about today?'
      ..reply = _reply1
          .replaceAll(RegExp(r'[*>`#]'), '')
          .replaceAll(RegExp(r'\n+'), ' ');
    await show(
      CallScreen(chat: callChat, voice: onDevice, controller: call),
      '26_call_captions',
      wait: const Duration(milliseconds: 1200),
    );
    await settleFor(tester, const Duration(seconds: 2));
  });
}
