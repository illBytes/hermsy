import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/screens/message_reader_screen.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/reply_markdown.dart';

void main() {
  testWidgets('reader shows a selectable Hermsy reply', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MessageReaderScreen(
          message: ChatMessage(
            id: 'a1',
            role: MessageRole.assistant,
            text: 'Say **hello** and then *quietly*.',
          ),
        ),
      ),
    );

    expect(find.text('Hermsy'), findsOneWidget);
    expect(find.text('Hold to highlight a passage.'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(ReplyMarkdown), findsOneWidget);
    expect(find.textContaining('hello'), findsWidgets);
  });

  testWidgets('reader shows a selectable user message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MessageReaderScreen(
          message: ChatMessage(
            id: 'u1',
            role: MessageRole.user,
            text: 'Plan Friday around six',
          ),
        ),
      ),
    );

    expect(find.text('You'), findsOneWidget);
    expect(find.text('Plan Friday around six'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(ReplyMarkdown), findsNothing);
  });

  testWidgets('back leaves the reader', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MessageReaderScreen(
                        message: ChatMessage(
                          id: 'a1',
                          role: MessageRole.assistant,
                          text: 'A longer reply you might quote.',
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Hold to highlight a passage.'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Hold to highlight a passage.'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('copy all copies the message and shows a check', (tester) async {
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
        home: MessageReaderScreen(
          message: ChatMessage(
            id: 'a1',
            role: MessageRole.assistant,
            text: 'Say **hello** and then *quietly*.',
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Copy all'));
    await tester.pumpAndSettle();
    expect(copied, 'Say **hello** and then *quietly*.');
    expect(find.byTooltip('Copied'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Copy all'), findsOneWidget);
  });

  testWidgets('the selection tip can be dismissed', (tester) async {
    addTearDown(MessageReaderScreen.debugResetTip);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MessageReaderScreen(
          message: ChatMessage(
            id: 'u1',
            role: MessageRole.user,
            text: 'Plan Friday around six',
          ),
        ),
      ),
    );

    expect(find.text('Hold to highlight a passage.'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss tip'));
    await tester.pumpAndSettle();
    expect(find.text('Hold to highlight a passage.'), findsNothing);
    expect(find.text('Plan Friday around six'), findsOneWidget);
  });
}
