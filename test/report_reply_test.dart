import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/services/message_actions.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/message_actions_sheet.dart';
import 'package:hermes_app/widgets/reply_actions.dart';
import 'package:hermes_app/widgets/report_reply.dart';

void main() {
  test('a report is an email to illbytes with the reply in it', () {
    final uri = reportEmailUri(
      reason: 'Offensive or hateful',
      reply: 'Some reply text',
      sentAt: DateTime(2026, 10, 24, 9, 30),
    );
    expect(uri.scheme, 'mailto');
    expect(uri.path, 'support@illbytes.com');
    expect(uri.query, isNot(contains('+')), reason: 'spaces stay spaces');
    final subject = Uri.decodeComponent(
      RegExp(r'subject=([^&]*)').firstMatch(uri.query)!.group(1)!,
    );
    final body = Uri.decodeComponent(uri.query.split('&body=').last);
    expect(subject, 'Hermsy report: Offensive or hateful');
    expect(body, contains('Reason: Offensive or hateful'));
    expect(body, contains('a chat reply, 2026-10-24 09:30'));
    expect(body, contains('Some reply text'));
    expect(body, contains('Hermsy 1.0.0'));

    final long = reportEmailUri(
      reason: 'Something else',
      reply: 'x' * 5000,
      sentAt: DateTime(2026),
    );
    expect(
      Uri.decodeComponent(long.query).length,
      lessThan(3400),
      reason: 'a long reply is clipped',
    );
  });

  test('only finished AI replies can be reported', () {
    ChatMessage message(
      MessageRole role, {
      String text = 'Hello',
      bool streaming = false,
      bool error = false,
      String id = 'a1',
    }) => ChatMessage(
      id: id,
      role: role,
      text: text,
      streaming: streaming,
      error: error,
    );

    expect(canReportMessage(message(MessageRole.assistant)), isTrue);
    expect(canReportMessage(message(MessageRole.user)), isFalse);
    expect(
      canReportMessage(message(MessageRole.assistant, streaming: true)),
      isFalse,
    );
    expect(
      canReportMessage(message(MessageRole.assistant, error: true)),
      isFalse,
      reason: "Hermsy's own error notes are not AI replies",
    );
    expect(
      canReportMessage(message(MessageRole.assistant, id: 'cmd_1')),
      isFalse,
    );
    expect(
      canReportMessage(message(MessageRole.assistant, text: ' ')),
      isFalse,
    );
  });

  testWidgets('the flag under a reply and the long-press sheet both report', (
    tester,
  ) async {
    var flagged = 0;
    var sheetReported = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(
            children: [
              ReplyActions(onCopy: () {}, onReport: () => flagged++),
              MessageActionsSheet(
                onCopy: () {},
                onReport: () => sheetReported++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Report reply'));
    expect(flagged, 1);
    await tester.tap(find.text('Report'));
    expect(sheetReported, 1);
  });

  testWidgets('choosing a reason opens the report, or copies it without an '
      'email app', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => reportReply(
                context,
                reply: 'A bad reply',
                sentAt: DateTime(2026, 10, 24),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Report this reply'), findsOneWidget);
    for (final reason in reportReasons) {
      expect(find.text(reason), findsOneWidget);
    }

    // No url_launcher in tests: like a phone without an email app.
    await tester.tap(find.text('Harmful or dangerous'));
    await tester.pumpAndSettle();
    // The launcher answers in real time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(copied, contains('Reason: Harmful or dangerous'));
    expect(copied, contains('A bad reply'));
    expect(find.textContaining('support@illbytes.com'), findsOneWidget);
  });
}
