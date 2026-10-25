import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/screens/chat_screen.dart';
import 'package:hermes_app/services/conversation_store.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/voice_service.dart';
import 'package:hermes_app/state/assistant_mood.dart';
import 'package:hermes_app/state/chat_controller.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/chat_empty_state.dart';
import 'package:hermes_app/widgets/chat_error_strip.dart';
import 'package:hermes_app/widgets/chat_header.dart';
import 'package:hermes_app/widgets/conversation_sheet.dart';
import 'package:hermes_app/widgets/day_separator.dart';
import 'package:hermes_app/widgets/message_bubble.dart';
import 'package:hermes_app/widgets/scroll_to_latest.dart';
import 'package:hermes_app/widgets/thread_find_bar.dart';
import 'package:hermes_app/widgets/ui/frank_ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget _app(Widget child) {
  return MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));
}

ChatStatus _status(
  AssistantMood mood, {
  bool loading = false,
  bool connected = true,
  bool onDevice = false,
  bool showError = true,
}) {
  return chatStatusFor(
    mood: mood,
    loading: loading,
    connected: connected,
    onDevice: onDevice,
    toolLabel: '🔍 web search: cats…',
    modelLabel: 'Claude Opus 4',
    showError: showError,
  );
}

ChatNotice? _notice({
  String? error,
  bool connected = true,
  bool loading = false,
  bool hasMessages = true,
  bool lastReplyFailed = false,
  bool fromVoice = false,
}) {
  return chatNoticeFor(
    error: error,
    connected: connected,
    loading: loading,
    hasMessages: hasMessages,
    lastReplyFailed: lastReplyFailed,
    fromVoice: fromVoice,
    host: 'relay.example.com',
  );
}

void main() {
  group('day separators', () {
    final now = DateTime(2026, 10, 3, 14);

    test('label today and yesterday', () {
      expect(dayLabel(DateTime(2026, 10, 3, 1), now: now), 'TODAY');
      expect(dayLabel(DateTime(2026, 10, 2, 23, 59), now: now), 'YESTERDAY');
      expect(
        dayLabel(DateTime(2026, 9, 30, 8), now: DateTime(2026, 10, 1, 9)),
        'YESTERDAY',
      );
    });

    test('label older days with the weekday, and the year when it differs', () {
      expect(dayLabel(DateTime(2026, 9, 10), now: now), 'THU 10 SEP');
      expect(dayLabel(DateTime(2025, 12, 31), now: now), 'WED 31 DEC 2025');
    });

    testWidgets('renders as a micro label', (tester) async {
      await tester.pumpWidget(
        _app(DaySeparator(date: DateTime(2026, 9, 10), now: now)),
      );
      expect(find.text('THU 10 SEP'), findsOneWidget);
    });
  });

  test('greets by the time of day', () {
    expect(greetingFor(DateTime(2026, 1, 1, 5)), 'Good morning');
    expect(greetingFor(DateTime(2026, 1, 1, 11, 59)), 'Good morning');
    expect(greetingFor(DateTime(2026, 1, 1, 12)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 1, 1, 17)), 'Good evening');
    expect(greetingFor(DateTime(2026, 1, 1, 22)), 'Still up?');
    expect(greetingFor(DateTime(2026, 1, 1, 4, 59)), 'Still up?');
  });

  test('shows only the server host', () {
    expect(hostOf('https://relay.example.com/v1'), 'relay.example.com');
    expect(hostOf('http://10.0.0.2:8642'), '10.0.0.2:8642');
    expect(hostOf(''), '');
  });

  group('header status', () {
    test('cleans Hermes tool lines', () {
      expect(
        cleanToolLabel('🔍 web search: weather Lagos…'),
        'Web search · weather Lagos',
      );
      expect(cleanToolLabel('📖 Read file...'), 'Read file');
      expect(cleanToolLabel(null), 'Working');
    });

    test('maps every mood to calm copy', () {
      expect(_status(AssistantMood.idle).label, 'Ready · Claude Opus 4');
      expect(_status(AssistantMood.idle, loading: true).label, 'Connecting…');
      expect(
        _status(AssistantMood.idle, connected: false).label,
        'Offline · tap to retry',
      );
      expect(_status(AssistantMood.listening).label, 'Listening');
      expect(
        _status(AssistantMood.listening, onDevice: true).label,
        'Listening on device',
      );
      expect(_status(AssistantMood.transcribing).label, 'Transcribing');
      expect(_status(AssistantMood.thinking).label, 'Thinking');
      expect(_status(AssistantMood.tool).label, 'Web search · cats');
      expect(_status(AssistantMood.responding).label, 'Replying');
      expect(_status(AssistantMood.speaking).label, 'Speaking · tap to stop');
      expect(_status(AssistantMood.reconnecting).label, 'Reconnecting…');
      expect(_status(AssistantMood.error).label, 'Something went wrong');
    });

    test('offline retries, speaking stops, a dismissed error reads ready', () {
      expect(
        _status(AssistantMood.idle, connected: false).action,
        ChatStatusAction.retry,
      );
      expect(
        _status(AssistantMood.speaking).action,
        ChatStatusAction.stopSpeaking,
      );
      expect(_status(AssistantMood.thinking).action, ChatStatusAction.none);
      expect(
        _status(AssistantMood.error, showError: false).label,
        'Ready · Claude Opus 4',
      );
    });
  });

  group('error notices', () {
    test('connection trouble shows the host over a thread only', () {
      final notice = _notice(error: 'SocketException', connected: false);
      expect(notice?.kind, ChatNoticeKind.connection);
      expect(notice?.title, "Can't reach Hermes");
      expect(notice?.detail, 'relay.example.com');
      expect(_notice(connected: false, hasMessages: false), isNull);
    });

    test('voice trouble is a gentle notice', () {
      expect(_notice(error: 'No speech detected.')?.kind, ChatNoticeKind.voice);
      expect(
        _notice(error: 'Permission denied', fromVoice: true)?.kind,
        ChatNoticeKind.voice,
      );
    });

    test('failed and cut-off replies offer a retry', () {
      final failed = _notice(error: 'HTTP 500', lastReplyFailed: true);
      expect(failed?.kind, ChatNoticeKind.reply);
      expect(failed?.title, "Hermsy couldn't finish that reply.");
      expect(failed?.detail, 'HTTP 500');
      expect(
        _notice(error: describeStreamDrop(hadText: true))?.kind,
        ChatNoticeKind.reply,
      );
    });

    test('anything else is a plain notice; nothing while connecting', () {
      final plain =
          _notice(error: 'That conversation is no longer on this phone.');
      expect(plain?.kind, ChatNoticeKind.notice);
      expect(plain?.title, 'That conversation is no longer on this phone.');
      expect(plain?.detail, isNull);

      // Raw technical text never leads; it becomes the detail.
      final raw = _notice(error: 'HTTP 500: upstream model timed out');
      expect(raw?.kind, ChatNoticeKind.notice);
      expect(raw?.title, 'Hermes ran into a problem');
      expect(raw?.detail, 'HTTP 500: upstream model timed out');

      final split =
          _notice(error: 'Could not speak that message. HttpException: 502');
      expect(split?.title, 'Could not speak that message.');
      expect(split?.detail, 'HttpException: 502');

      expect(_notice(error: 'HTTP 500', loading: true), isNull);
      expect(_notice(), isNull);
    });
  });

  group('error strip', () {
    testWidgets('a failed reply retries and dismisses', (tester) async {
      var retries = 0;
      ChatNotice? dismissed;
      final notice = _notice(error: 'HTTP 500', lastReplyFailed: true);
      Widget strip(ChatNotice? value) => _app(
            ChatErrorStrip(
              notice: value,
              onRetry: () => retries++,
              onDismiss: (item) => dismissed = item,
            ),
          );

      await tester.pumpWidget(strip(notice));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text("Hermsy couldn't finish that reply."), findsOneWidget);
      expect(find.text('HTTP 500'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retries, 1);
      await tester.tap(find.byTooltip('Dismiss'));
      expect(dismissed, notice);

      await tester.pumpWidget(strip(null));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text("Hermsy couldn't finish that reply."), findsNothing);
    });

    testWidgets('a voice notice dismisses itself', (tester) async {
      ChatNotice? dismissed;
      await tester.pumpWidget(
        _app(
          ChatErrorStrip(
            notice: _notice(error: 'No speech detected.'),
            onDismiss: (item) => dismissed = item,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('No speech detected.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      expect(dismissed?.kind, ChatNoticeKind.voice);
    });

    testWidgets('the connection strip offers retry and settings', (tester) async {
      var retries = 0;
      var settings = 0;
      await tester.pumpWidget(
        _app(
          ChatErrorStrip(
            notice: _notice(connected: false),
            onRetry: () => retries++,
            onSettings: () => settings++,
            onDismiss: (_) {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text("Can't reach Hermes"), findsOneWidget);
      expect(find.text('relay.example.com'), findsOneWidget);
      expect(find.byTooltip('Dismiss'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Settings'));
      expect(retries, 1);
      expect(settings, 1);
    });
  });

  group('header', () {
    testWidgets('shows the status and fires its actions', (tester) async {
      Offset? orbOrigin;
      var drawer = 0;
      var sheet = 0;
      var finds = 0;
      var chats = 0;
      await tester.pumpWidget(
        _app(
          ChatHeader(
            title: 'Friday dinner',
            status: _status(AssistantMood.idle),
            mood: AssistantMood.idle,
            onOpenDrawer: () => drawer++,
            onOrbTap: (origin) => orbOrigin = origin,
            onOpenConversation: () => sheet++,
            onFind: () => finds++,
            onNewChat: () => chats++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Friday dinner'), findsOneWidget);
      expect(find.text('Ready · Claude Opus 4'), findsOneWidget);

      await tester.tap(find.byTooltip('Chats'));
      await tester.tap(find.byTooltip('Find in chat'));
      await tester.tap(find.byTooltip('New conversation'));
      await tester.tap(find.text('Friday dinner'));
      await tester.tap(find.bySemanticsLabel('Talk to Hermsy'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(drawer, 1);
      expect(finds, 1);
      expect(chats, 1);
      expect(sheet, 1);
      expect(orbOrigin, isNotNull);
      expect(orbOrigin, isNot(Offset.zero));
    });

    testWidgets('tapping the offline status retries', (tester) async {
      var retries = 0;
      var sheet = 0;
      await tester.pumpWidget(
        _app(
          ChatHeader(
            title: 'Hermsy',
            status: _status(AssistantMood.idle, connected: false),
            mood: AssistantMood.idle,
            lit: false,
            orbEnabled: false,
            onOpenDrawer: () {},
            onOrbTap: (_) {},
            onOpenConversation: () => sheet++,
            onStatusAction: () => retries++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Offline · tap to retry'));
      expect(retries, 1);
      expect(sheet, 0);
    });

    testWidgets('morphs into the find bar', (tester) async {
      await tester.pumpWidget(
        _app(
          ChatHeader(
            title: 'Hermsy',
            status: _status(AssistantMood.idle),
            mood: AssistantMood.idle,
            finding: true,
            findBar: ThreadFindBar(
              controller: TextEditingController(text: 'wine'),
              focusNode: FocusNode(),
              matchLabel: '1/3',
              hasQuery: true,
              hasMatches: true,
              onPrevious: () {},
              onNext: () {},
              onClose: () {},
            ),
            onOpenDrawer: () {},
            onOrbTap: (_) {},
            onOpenConversation: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byTooltip('Close find'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.byTooltip('Chats'), findsNothing);
    });
  });

  group('empty state', () {
    testWidgets('greets and offers ways in', (tester) async {
      ConversationSummary? opened;
      Offset? talkedFrom;
      var commands = 0;
      await tester.pumpWidget(
        _app(
          ChatEmptyState(
            connected: true,
            modelLabel: 'Claude Opus 4',
            recent: [
              ConversationSummary(
                id: 'c1',
                title: 'Friday dinner',
                updatedAt: DateTime(2026, 10, 2),
              ),
            ],
            onOpenRecent: (item) => opened = item,
            onTalk: (origin) => talkedFrom = origin,
            onCommands: () => commands++,
            now: DateTime(2026, 10, 3, 9),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Good morning'), findsOneWidget);
      expect(find.text('Hermsy is ready'), findsOneWidget);
      expect(find.text('CLAUDE OPUS 4'), findsOneWidget);

      await tester.tap(find.text('Talk to Hermsy'));
      await tester.tap(find.text('Commands'));
      await tester.tap(
        find.text('Continue · Friday dinner', findRichText: true),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(talkedFrom, isNotNull);
      expect(commands, 1);
      expect(opened?.id, 'c1');
    });

    testWidgets('while connecting it waits without chips', (tester) async {
      await tester.pumpWidget(
        _app(
          ChatEmptyState(
            connected: false,
            connecting: true,
            onTalk: (_) {},
            now: DateTime(2026, 10, 3, 20),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Good evening'), findsOneWidget);
      expect(find.text('Connecting to Hermes…'), findsOneWidget);
      expect(find.text('Talk to Hermsy'), findsNothing);
    });

    testWidgets('offline shows the host, retry and settings', (tester) async {
      var retries = 0;
      var settings = 0;
      await tester.pumpWidget(
        _app(
          ChatEmptyState(
            connected: false,
            host: 'relay.example.com',
            onRetry: () => retries++,
            onSettings: () => settings++,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text("Can't reach Hermes"), findsOneWidget);
      expect(find.text('relay.example.com'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Server settings'));
      expect(retries, 1);
      expect(settings, 1);
    });
  });

  group('conversation sheet', () {
    Future<void> open(WidgetTester tester, ConversationSheet sheet) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      showFrankSheet<void>(context, builder: (_) => sheet),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('hides what is not possible and closes on an action',
        (tester) async {
      var deletes = 0;
      await open(
        tester,
        ConversationSheet(
          title: 'New chat',
          subtitle: 'No messages yet · Hermes',
          onUsage: () {},
          onStatus: () {},
          onDelete: () => deletes++,
        ),
      );

      expect(find.text('Rename'), findsNothing);
      expect(find.text('Pin'), findsNothing);
      expect(find.text('Find in chat'), findsNothing);
      expect(find.text('Usage'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);

      await tester.tap(find.text('Delete chat'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(find.text('New chat'), findsNothing);
    });

    testWidgets('offers rename, unpin and find for a saved chat',
        (tester) async {
      var renames = 0;
      var pins = 0;
      var finds = 0;
      await open(
        tester,
        ConversationSheet(
          title: 'Friday dinner',
          pinned: true,
          onRename: () => renames++,
          onTogglePin: () => pins++,
          onFind: () => finds++,
        ),
      );

      expect(find.text('Unpin'), findsOneWidget);
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(renames, 1);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find in chat'));
      await tester.pumpAndSettle();
      expect(finds, 1);
      expect(pins, 0);
    });
  });

  testWidgets('scroll to latest only takes taps while visible', (tester) async {
    var taps = 0;
    Widget button({required bool visible, bool unseen = false}) {
      return _app(
        Center(
          child: ScrollToLatestButton(
            visible: visible,
            unseen: unseen,
            onPressed: () => taps++,
          ),
        ),
      );
    }

    await tester.pumpWidget(button(visible: false));
    await tester.tap(find.byType(ScrollToLatestButton), warnIfMissed: false);
    expect(taps, 0);

    await tester.pumpWidget(button(visible: true, unseen: true));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byTooltip('Jump to new messages'), findsOneWidget);
    await tester.tap(find.byType(ScrollToLatestButton));
    expect(taps, 1);
  });

  testWidgets('the chat screen composes offline, thread, header and find',
      (tester) async {
    // Not configured: start() fails fast without touching the network.
    final chat = ChatController(
      config: const AppConfig(baseUrl: '', apiKey: ''),
      client: HermesClient(
        baseUrl: '',
        apiKey: '',
        httpClient: MockClient((_) async => http.Response('', 503)),
      ),
      voice: _QuietVoice(),
    );
    addTearDown(chat.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ChatScreen(controller: chat, onLock: () {}, onSettings: () {}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text("Can't reach Hermes"), findsOneWidget);
    expect(find.text('Offline · tap to retry'), findsOneWidget);
    expect(find.text('Server settings'), findsOneWidget);

    // Slash commands answer locally, which gives the thread two messages.
    await chat.send('/stop');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Hermsy'), findsWidgets);
    // Offline over a thread: the amber strip takes over from the empty state.
    expect(find.text("Can't reach Hermes"), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.byTooltip('Find in chat'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Close find'), findsOneWidget);

    final field = find.descendant(
      of: find.byType(ThreadFindBar),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'stopped');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1/1'), findsOneWidget);

    await tester.enterText(field, 'zebra');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No matches'), findsOneWidget);

    await tester.tap(find.byTooltip('Close find'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Chats'), findsOneWidget);

    // The drawer refreshes history as it opens; the screen must cope.
    await tester.tap(find.byTooltip('Chats'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

/// A voice service that is never asked to do anything in these tests.
class _QuietVoice implements VoiceService {
  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
