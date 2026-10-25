// Google Play screenshots, 1080x1920, with made-up content only: no real
// chats, names, places or numbers.
//
//   SHOTS_DIR=store/screenshots/dark flutter test tool/shots/store_shots_test.dart
//
// Add SHOTS_THEME=light for the light set. The feature graphic is drawn here
// too (1024x500).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/main.dart';
import 'package:hermes_app/models/brief.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/screens/brief_screen.dart';
import 'package:hermes_app/screens/call_screen.dart';
import 'package:hermes_app/screens/inbox_screen.dart';
import 'package:hermes_app/screens/settings_screen.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/services/brief_store.dart';
import 'package:hermes_app/services/connection_store.dart';
import 'package:hermes_app/services/conversation_store.dart';
import 'package:hermes_app/services/delivery_inbox.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/voice_models.dart';
import 'package:hermes_app/state/chat_controller.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/voice/call_controller.dart';
import 'package:hermes_app/voice/on_device_voice.dart';
import 'package:hermes_app/voice/speech_player.dart';
import 'package:hermes_app/widgets/frank_backdrop.dart';
import 'package:hermes_app/widgets/frank_orb.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shot_kit.dart';
import 'shot_rig.dart';

const _server = AppConfig(
  baseUrl: 'https://hermes.example.com',
  apiKey: 'demo-key-0000',
);

/// This morning, whenever the shots are taken, so the history reads
/// Today, Yesterday and so on.
final _today = () {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 8, 30);
}();

DateTime _at(int dayOffset, int hour, [int minute = 0]) =>
    DateTime(_today.year, _today.month, _today.day + dayOffset, hour, minute);

const _question = 'What does my day look like?';

const _answer = '''Here's your day:

1. **Design review** at 10:00 with the product team
2. **Lunch with Sam** at 13:00, Café Lumen
3. **Gym** at 18:00

It's 24°C and sunny, so walking to the review takes 15 minutes. You also asked me to remind you: the library books are due tomorrow.''';

/// Made-up chats for the history.
List<ConversationRecord> _chats() {
  ConversationRecord chat(
    String id,
    String title,
    DateTime at,
    String question,
    String answer, {
    bool pinned = false,
    List<String> tools = const [],
  }) => ConversationRecord(
    id: id,
    title: title,
    hermesTitle: title,
    updatedAt: at,
    pinned: pinned,
    sessionKey: 'agent:main:mobile:dm:$id',
    messages: [
      ChatMessage(
        id: '$id-u',
        role: MessageRole.user,
        text: question,
        createdAt: at,
      ),
      ChatMessage(
        id: '$id-a',
        role: MessageRole.assistant,
        text: answer,
        toolTrail: tools,
        createdAt: at.add(const Duration(seconds: 20)),
      ),
    ],
  );

  return [
    chat(
      'convo_trip',
      'Weekend trip to the coast',
      _at(-3, 19),
      'Plan a two-day trip to the coast',
      'Here is a relaxed plan: leave Saturday at 9, lunch by the harbour…',
      pinned: true,
    ),
    chat(
      'convo_budget',
      'Monthly budget check',
      _at(-1, 21, 10),
      'How did my spending look this month?',
      'You stayed under budget in four of five categories…',
    ),
    chat(
      'convo_gift',
      'Birthday gift ideas',
      _at(-5, 12),
      'Gift ideas for a friend who loves hiking',
      'A few ideas: a lightweight headlamp, a trail guide…',
    ),
    chat(
      'convo_printer',
      'Fix the office printer',
      _at(-9, 16),
      'The printer keeps going offline',
      'Try this first: give the printer a fixed IP address…',
    ),
    chat(
      'convo_today',
      'Planning the day',
      _at(0, 8, 30),
      _question,
      _answer,
      tools: const ['Checked your calendar', 'Weather'],
    ),
  ];
}

Brief _brief() => Brief.fromJson({
  'id': 'demo',
  'created_at': _today.toIso8601String(),
  'greeting': 'Good morning, Alex',
  'headline': 'A calm day: one meeting, lunch with Sam, then the gym.',
  'summary':
      'Your morning is clear until the design review at 10. The library '
      'books are due tomorrow, and the team update needs a last read.',
  'sections': [
    {
      'id': 'today',
      'title': 'Today',
      'items': [
        {'title': 'Design review', 'time': '10:00', 'detail': 'Room 4B'},
        {'title': 'Lunch with Sam', 'time': '13:00', 'detail': 'Café Lumen'},
        {'title': 'Gym', 'time': '18:00'},
      ],
    },
    {
      'id': 'due',
      'title': 'Due soon',
      'items': [
        {'title': 'Return library books', 'when': 'Tomorrow'},
        {'title': 'Send the team update', 'when': 'Monday'},
      ],
    },
    {
      'id': 'suggestions',
      'title': 'Suggestions',
      'items': [
        {
          'title': 'Leave by 9:40 for the review',
          'detail': 'A 15-minute walk in the sun',
          'action': 'Remind me at 9:35',
        },
      ],
    },
  ],
});

List<DeliveryRecord> _deliveries() => [
  DeliveryRecord(
    id: 'relay_d1',
    title: 'Morning summary',
    body:
        'Morning summary\nThree things today, and the library books are due '
        'tomorrow. The weather is clear all day.',
    createdAt: _at(0, 7),
    source: 'cron',
    read: false,
  ),
  DeliveryRecord(
    id: 'relay_d2',
    title: 'Flight price alert',
    body:
        'Flight price alert\nThe weekend flight you were watching dropped '
        'by 18%. Want me to hold a seat?',
    createdAt: _at(0, 6, 15),
    source: 'cron',
    read: false,
  ),
  DeliveryRecord(
    id: 'relay_d3',
    title: 'Weekly review',
    body:
        'Weekly review\nYou finished 12 tasks this week. Two are still open: '
        'the team update and the printer fix.',
    createdAt: _at(-1, 18),
    source: 'cron',
  ),
];

void main() {
  late Directory temp;
  final brightness = Platform.environment['SHOTS_THEME'] == 'light'
      ? Brightness.light
      : Brightness.dark;
  const ratio = 2.625;

  setUpAll(() async {
    await loadShotFonts();
    AppColors.use(brightness);
  });

  setUp(() async {
    // Frank reopens the day's plan.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'frank.conversation_id': 'convo_today',
    });
    temp = Directory.systemTemp.createTempSync('frank_store_');
  });

  tearDown(() {
    DeliveryInbox.unread.value = 0;
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<ShotRig> pumpApp(WidgetTester tester) async {
    useStoreView(tester);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    final rig = ShotRig(temp, pin: '1234');
    await tester.runAsync(() async {
      for (final chat in _chats()) {
        await rig.store.write(chat);
      }
      for (final item in _deliveries()) {
        await rig.inbox.add(item);
      }
    });
    final connection = ConnectionStore(
      bundled: _server,
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

  Future<void> unlock(WidgetTester tester, ShotRig rig) async {
    for (final digit in '1234'.split('')) {
      await tester.tap(find.text(digit).first);
      await tester.pump(const Duration(milliseconds: 60));
    }
    for (var i = 0; i < 80; i++) {
      await realAsync(tester, const Duration(milliseconds: 25));
      await tester.pump(const Duration(milliseconds: 50));
      if (rig.chats.isNotEmpty && !rig.chats.last.loading) {
        break;
      }
    }
    await settleFor(tester, const Duration(milliseconds: 1200));
  }

  testWidgets('lock, chat and history', (tester) async {
    final rig = await pumpApp(tester);
    await saveShot(tester, rig.boundary, '08_lock', pixelRatio: ratio);

    await unlock(tester, rig);
    // The most recent chat opens: the day's plan.
    await saveShot(tester, rig.boundary, '01_chat', pixelRatio: ratio);

    DeliveryInbox.unread.value = 2;
    await tester.tap(find.byTooltip('Chats'));
    await settleFor(tester, const Duration(milliseconds: 900));
    await saveShot(tester, rig.boundary, '04_history', pixelRatio: ratio);
    await tester.tapAt(const Offset(380, 400));
    await settleFor(tester, const Duration(seconds: 2));
  });

  testWidgets('call, brief, inbox and settings', (tester) async {
    useStoreView(tester);
    final boundary = GlobalKey();
    final settings = AppSettings(
      preferences: await SharedPreferences.getInstance(),
    );
    await settings.load();
    final connection = ConnectionStore(
      bundled: _server,
      vault: MemoryConnectionVault(),
    );
    await connection.load();

    Future<void> show(
      Widget home,
      String name, {
      Duration wait = const Duration(milliseconds: 900),
    }) async {
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
      // Files load in real time, a step per round.
      for (var i = 0; i < 30; i++) {
        await realAsync(tester, const Duration(milliseconds: 20));
      }
      await settleFor(tester, wait);
      await saveShot(tester, boundary, name, pixelRatio: ratio);
    }

    // A voice call, mid-answer.
    final chat = ChatController(
      config: _server,
      client: HermesClient(baseUrl: _server.baseUrl, apiKey: _server.apiKey),
      voice: ShotVoice(),
      settings: settings,
    )..conversationTitle = 'Planning the day';
    final onDevice = OnDeviceVoice(VoiceModelStore(root: temp));
    final call =
        CallController(
            chat: chat,
            voice: onDevice,
            player: SpeechPlayer(players: []),
          )
          ..phase = CallPhase.speaking
          ..heard = 'Can you move the gym to tomorrow?'
          ..reply =
              'Done. The gym is now tomorrow at 18:00, and I left this '
              'evening free.';
    await show(
      CallScreen(chat: chat, voice: onDevice, controller: call),
      '02_call',
      wait: const Duration(milliseconds: 1400),
    );

    // The Brief.
    final brief = BriefStore(connection: connection)..brief = _brief();
    final inboxDir = Directory('${temp.path}/brief_inbox');
    await show(
      BriefScreen(
        store: brief,
        settings: settings,
        inbox: DeliveryInbox(inboxDir),
        now: _today,
      ),
      '03_brief',
    );

    // Messages Hermes sent on its own.
    final inbox = DeliveryInbox(Directory('${temp.path}/inbox'));
    await tester.runAsync(() async {
      for (final item in _deliveries()) {
        await inbox.add(item);
      }
    });
    await show(InboxScreen(inbox: inbox), '05_inbox');

    // Settings, and the presence styles.
    await show(
      SettingsScreen(
        settings: settings,
        connection: connection,
        onChangePin: () {},
        onLock: () {},
      ),
      '06_settings',
    );
    await tester.tap(find.text('Appearance'));
    await settleFor(tester, const Duration(milliseconds: 700));
    await tester.tap(find.text('Presence'));
    await settleFor(tester, const Duration(milliseconds: 1800));
    await saveShot(tester, boundary, '07_presence', pixelRatio: ratio);
    await settleFor(tester, const Duration(seconds: 2));
  });

  testWidgets('feature graphic', (tester) async {
    tester.view.physicalSize = const Size(1024, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(brightness),
          home: FrankBackdrop(
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 72),
                child: Row(
                  children: [
                    const FrankOrb(size: 260, live: true, lit: true),
                    const SizedBox(width: 56),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Frank',
                            style: AppText.title.copyWith(
                              fontSize: 76,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.5,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Your own AI agent, in your pocket.',
                            style: TextStyle(
                              color: AppColors.secondary,
                              fontSize: 30,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleFor(tester, const Duration(milliseconds: 1200));
    await saveShot(tester, boundary, 'feature_graphic', pixelRatio: 1);
  });
}
