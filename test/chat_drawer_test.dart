import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/services/conversation_store.dart';
import 'package:hermes_app/services/delivery_inbox.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/voice_service.dart';
import 'package:hermes_app/state/chat_controller.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/chat_drawer.dart';
import 'package:hermes_app/widgets/prompt_rename_chat.dart';

class _QuietVoice extends Fake implements VoiceService {}

/// A controller with canned history that records what the drawer asks for.
class _FakeChat extends ChatController {
  _FakeChat(List<ConversationSummary> items)
    : super(
        config: const AppConfig(baseUrl: 'https://relay.example', apiKey: 'k'),
        client: HermesClient(baseUrl: 'https://relay.example', apiKey: 'k'),
        voice: _QuietVoice(),
      ) {
    history = items;
    loading = false;
    connected = true;
  }

  final opened = <String>[];
  final deleted = <String>[];
  var newChats = 0;

  @override
  Future<void> refreshHistory() async {}

  @override
  Future<void> openConversation(ConversationSummary item) async {
    opened.add(item.id);
  }

  @override
  Future<void> deleteConversation(ConversationSummary item) async {
    deleted.add(item.id);
    history = [
      for (final entry in history)
        if (entry.id != item.id) entry,
    ];
    notifyListeners();
  }

  @override
  Future<void> newChat({bool saveCurrent = true}) async {
    newChats++;
  }
}

ConversationSummary _chat(
  String id,
  String title,
  DateTime updatedAt, {
  bool pinned = false,
  String preview = '',
}) {
  return ConversationSummary(
    id: id,
    title: title,
    updatedAt: updatedAt,
    pinned: pinned,
    preview: preview,
  );
}

void main() {
  group('groupConversations', () {
    final now = DateTime(2026, 9, 10, 15);

    test('buckets by day under pinned, keeping order', () {
      final sections = groupConversations([
        _chat('p', 'Pinned', DateTime(2020), pinned: true),
        _chat('t', 'Today', DateTime(2026, 9, 10, 9, 5)),
        _chat('y', 'Yesterday', DateTime(2026, 9, 9, 22)),
        _chat('w1', 'Monday', DateTime(2026, 9, 7, 8)),
        _chat('w2', 'Week edge', DateTime(2026, 9, 3, 8)),
        _chat('o1', 'Older', DateTime(2026, 9, 2, 8)),
        _chat('o2', 'Unknown', DateTime.fromMillisecondsSinceEpoch(0)),
      ], now: now);

      expect(
        [for (final section in sections) section.label],
        ['Pinned', 'Today', 'Yesterday', 'Previous 7 days', 'Older'],
      );
      expect(
        [
          for (final section in sections)
            section.items.map((i) => i.id).toList(),
        ],
        [
          ['p'],
          ['t'],
          ['y'],
          ['w1', 'w2'],
          ['o1', 'o2'],
        ],
      );
      expect(sections[2].clockForYesterday, isTrue);
    });

    test('leaves out empty sections', () {
      final sections = groupConversations([
        _chat('t', 'Today', DateTime(2026, 9, 10, 9)),
      ], now: now);
      expect(sections.single.label, 'Today');
    });
  });

  group('drawerTimeLabel', () {
    final now = DateTime(2026, 9, 10, 15);

    test('uses the clock today in either hour format', () {
      final morning = DateTime(2026, 9, 10, 9, 5);
      expect(drawerTimeLabel(morning, now: now), '09:05');
      expect(drawerTimeLabel(morning, now: now, use24h: false), '9:05 AM');
      expect(
        drawerTimeLabel(DateTime(2026, 9, 10, 0, 30), now: now, use24h: false),
        '12:30 AM',
      );
    });

    test('names yesterday unless the section already does', () {
      final late = DateTime(2026, 9, 9, 22);
      expect(drawerTimeLabel(late, now: now), 'Yesterday');
      expect(drawerTimeLabel(late, now: now, clockForYesterday: true), '22:00');
    });

    test('uses weekdays this week, then dates', () {
      expect(drawerTimeLabel(DateTime(2026, 9, 7, 8), now: now), 'Mon');
      expect(drawerTimeLabel(DateTime(2026, 9, 3, 8), now: now), 'Sep 3');
      expect(
        drawerTimeLabel(DateTime(2025, 8, 20, 15, 30), now: now),
        'Aug 20, 2025',
      );
      expect(
        drawerTimeLabel(DateTime.fromMillisecondsSinceEpoch(0), now: now),
        '',
      );
    });
  });

  group('ChatDrawer', () {
    Future<_FakeChat> pumpDrawer(
      WidgetTester tester,
      List<ConversationSummary> items, {
      String? current,
      VoidCallback? onOpenSettings,
      VoidCallback? onLock,
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final chat = _FakeChat(items)..conversationId = current;
      final scaffold = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            key: scaffold,
            drawer: ChatDrawer(
              controller: chat,
              onOpenSettings: onOpenSettings ?? () {},
              onOpenInbox: () {},
              onLock: onLock,
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
      scaffold.currentState!.openDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      return chat;
    }

    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 12);

    testWidgets('groups chats by day with the drawer chrome', (tester) async {
      var settings = 0;
      var locks = 0;
      await pumpDrawer(
        tester,
        [
          _chat('p', 'Trip plans', DateTime(2020), pinned: true),
          _chat('t', 'Weather in Lagos', now, preview: 'Draft · bring a coat'),
          _chat('y', 'Budget review', yesterday),
          _chat('o', 'Old notes', DateTime(2021, 3, 4)),
        ],
        current: 't',
        onOpenSettings: () => settings++,
        onLock: () => locks++,
      );

      expect(find.text('Hermsy'), findsOneWidget);
      expect(find.text('New chat'), findsOneWidget);
      expect(find.text('Search chats'), findsOneWidget);
      for (final label in ['PINNED', 'TODAY', 'YESTERDAY', 'OLDER']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Trip plans'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
      expect(
        find.text('Draft · bring a coat', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('No messages'), findsNWidgets(3));
      expect(find.text('HOLD A CHAT TO RENAME, PIN, OR DELETE'), findsNothing);
      expect(find.text('Inbox'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      expect(settings, 1);
      await tester.tap(find.byTooltip('Lock Hermsy'));
      expect(locks, 1);
    });

    testWidgets('the Inbox shows how many are unread', (tester) async {
      addTearDown(() => DeliveryInbox.unread.value = 0);
      await pumpDrawer(tester, []);
      expect(find.text('3'), findsNothing);

      DeliveryInbox.unread.value = 3;
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(find.bySemanticsLabel('Inbox'), findsOneWidget);

      DeliveryInbox.unread.value = 0;
      await tester.pump();
      expect(find.text('3'), findsNothing);
    });

    testWidgets('shows the hold hint while history is short', (tester) async {
      await pumpDrawer(tester, [_chat('a', 'Only chat', now)]);
      expect(
        find.text('HOLD A CHAT TO RENAME, PIN, OR DELETE'),
        findsOneWidget,
      );
    });

    testWidgets('shows empty copy with no history', (tester) async {
      await pumpDrawer(tester, const []);
      expect(find.text('No earlier conversations yet.'), findsOneWidget);
    });

    testWidgets('search filters and clears', (tester) async {
      await pumpDrawer(tester, [
        _chat('a', 'Weather in Lagos', now),
        _chat('b', 'Budget review', now),
      ]);

      await tester.enterText(find.byType(TextField), 'budget');
      await tester.pump();
      expect(find.text('Budget review'), findsOneWidget);
      expect(find.text('Weather in Lagos'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('No chats match.'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text('Weather in Lagos'), findsOneWidget);
      expect(find.text('Budget review'), findsOneWidget);
    });

    testWidgets('tapping a chat opens it and closes the drawer', (
      tester,
    ) async {
      final chat = await pumpDrawer(tester, [
        _chat('a', 'Weather in Lagos', now),
      ]);

      await tester.tap(find.text('Weather in Lagos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(chat.opened, ['a']);
      expect(find.byType(ChatDrawer), findsNothing);
    });

    testWidgets('new chat pill starts a fresh chat', (tester) async {
      final chat = await pumpDrawer(tester, [_chat('a', 'Weather', now)]);

      await tester.tap(find.text('New chat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(chat.newChats, 1);
      expect(find.byType(ChatDrawer), findsNothing);
    });

    testWidgets('swipe left asks before deleting', (tester) async {
      final chat = await pumpDrawer(tester, [
        _chat('a', 'Weather in Lagos', now),
        _chat('b', 'Budget review', now),
      ]);

      await tester.drag(find.text('Weather in Lagos'), const Offset(-260, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Delete chat?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(chat.deleted, isEmpty);
      expect(find.text('Weather in Lagos'), findsOneWidget);

      await tester.drag(find.text('Weather in Lagos'), const Offset(-260, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(chat.deleted, ['a']);
      expect(find.text('Weather in Lagos'), findsNothing);
      expect(find.text('Budget review'), findsOneWidget);
    });

    testWidgets('holding a chat offers rename, pin, and delete', (
      tester,
    ) async {
      await pumpDrawer(tester, [_chat('a', 'Weather in Lagos', now)]);

      await tester.longPress(find.text('Weather in Lagos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Pin'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('promptRenameChat', () {
    Future<void> open(
      WidgetTester tester,
      void Function(String? value) onResult,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () async {
                    onResult(
                      await promptRenameChat(context, currentTitle: 'Old name'),
                    );
                  },
                  child: const Text('Ask'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ask'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('returns the new name on save', (tester) async {
      String? result = 'unset';
      await open(tester, (value) => result = value);

      expect(find.text('Rename chat'), findsOneWidget);
      expect(find.text('Old name'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Trip plans');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(result, 'Trip plans');
      expect(find.text('Rename chat'), findsNothing);
    });

    testWidgets('returns null on cancel and blocks empty names', (
      tester,
    ) async {
      String? result = 'unset';
      await open(tester, (value) => result = value);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Rename chat'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(result, isNull);
    });
  });
}
