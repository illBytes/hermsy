import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/message_bubble.dart';
import 'package:hermes_app/widgets/reply_code_block.dart';
import 'package:hermes_app/widgets/reply_markdown.dart';
import 'package:hermes_app/widgets/tool_activity_line.dart';
import 'package:hermes_app/widgets/typing_indicator.dart';
import 'package:hermes_app/widgets/voice_note_card.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('splitReplyBlocks', () {
    test('splits paragraphs at blank lines', () {
      expect(
        splitReplyBlocks('One.\n\nTwo.\n\n\nThree.'),
        ['One.', 'Two.', 'Three.'],
      );
    });

    test('never splits inside a code fence', () {
      const text = 'Intro\n\n```dart\nvoid a() {}\n\nvoid b() {}\n```\n\nAfter';
      expect(splitReplyBlocks(text), [
        'Intro',
        '```dart\nvoid a() {}\n\nvoid b() {}\n```',
        'After',
      ]);
    });

    test('keeps loose lists and indented continuations together', () {
      const text = '1. First\n\n   More about it\n\n2. Second\n\nDone.';
      expect(splitReplyBlocks(text), [
        '1. First\n\n   More about it\n\n2. Second',
        'Done.',
      ]);
    });

    test('keeps text with reference links whole', () {
      const text = 'See [docs][1].\n\nMore.\n\n[1]: https://example.com';
      expect(splitReplyBlocks(text), [text]);
    });

    test('places the caret inline after prose, apart after code', () {
      expect(withCaret('Hello'), 'Hello$caretMark');
      expect(withCaret('Hello\n'), 'Hello$caretMark');
      expect(withCaret('```\ncode\n```'), '```\ncode\n```\n\n$caretMark');
      expect(withCaret('## Title'), '## Title\n\n$caretMark');
    });
  });

  group('ToolLabel', () {
    test('splits the emoji and tidies the label', () {
      final label = ToolLabel.parse('🔍 Web search: weather Lagos…');
      expect(label.emoji, '🔍');
      expect(label.text, 'Web search · weather Lagos');
    });

    test('maps an icon when Hermes sent no emoji', () {
      final label = ToolLabel.parse('Read File…');
      expect(label.emoji, isNull);
      expect(label.text, 'Read File');
      expect(label.icon, Icons.description_rounded);
      expect(ToolLabel.parse('Terminal…').icon, Icons.terminal_rounded);
      expect(ToolLabel.parse('Mystery…').icon, Icons.build_rounded);
    });
  });

  testWidgets('a block that starts at 3 keeps its number', (tester) async {
    await tester.pumpWidget(
      _host(const ReplyMarkdown(data: '1. One\n2. Two\n\nA note.\n\n3. Three')),
    );
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('3.'), findsOneWidget);
  });

  testWidgets('finished blocks are not parsed again while streaming', (tester) async {
    final data = ValueNotifier('First paragraph.\n\nSecond');
    addTearDown(data.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<String>(
          valueListenable: data,
          builder: (context, value, _) {
            return ReplyMarkdown(data: value, streaming: true);
          },
        ),
      ),
    );
    final first = tester.element(find.textContaining('First paragraph.'));

    data.value = 'First paragraph.\n\nSecond paragraph grows';
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.textContaining('grows'), findsOneWidget);
    expect(tester.element(find.textContaining('First paragraph.')), same(first));
  });

  testWidgets('the streaming caret fades out when the reply lands', (tester) async {
    Widget reply({required bool streaming}) {
      return _host(ReplyMarkdown(data: 'Almost there', streaming: streaming));
    }

    await tester.pumpWidget(reply(streaming: true));
    await tester.pump(const Duration(milliseconds: 250));
    // The caret rides the end of the line as an inline placeholder.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText() == 'Almost there\uFFFC',
      ),
      findsOneWidget,
    );
    expect(find.byType(FadeTransition), findsWidgets);
    final withCaretCount = find.byType(FadeTransition).evaluate().length;

    await tester.pumpWidget(reply(streaming: false));
    await tester.pumpAndSettle();
    expect(find.byType(FadeTransition).evaluate().length, lessThan(withCaretCount));
    expect(find.textContaining(caretMark), findsNothing);
  });

  testWidgets('waiting reply shows the inline presence row and tool chip', (tester) async {
    await tester.pumpWidget(
      _host(
        MessageBubble(
          message: ChatMessage(
            id: 'a1',
            role: MessageRole.assistant,
            text: '',
            streaming: true,
            toolStatus: '🔍 Web search: weather Lagos…',
            toolTrail: ['📄 Read file: notes.md…', '🔍 Web search: weather Lagos…'],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(TypingIndicator), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Web search · weather Lagos'), findsOneWidget);
    expect(find.text('📄 Read file · notes.md'), findsOneWidget);
  });

  testWidgets('finished reply folds its tool trail', (tester) async {
    await tester.pumpWidget(
      _host(
        MessageBubble(
          showHeader: false,
          message: ChatMessage(
            id: 'a1',
            role: MessageRole.assistant,
            text: 'Sunny all week.',
            toolTrail: ['🔍 Web search: weather Lagos…', '📄 Read file: notes.md…'],
          ),
        ),
      ),
    );

    expect(find.text('Used 2 tools'), findsOneWidget);
    expect(find.text('📄 Read file · notes.md'), findsNothing);

    await tester.tap(find.text('Used 2 tools'));
    await tester.pumpAndSettle();
    expect(find.text('🔍 Web search · weather Lagos'), findsOneWidget);
    expect(find.text('📄 Read file · notes.md'), findsOneWidget);
  });

  testWidgets('latest reply offers copy, speak and retry inline', (tester) async {
    var copied = 0;
    var retried = 0;
    await tester.pumpWidget(
      _host(
        MessageBubble(
          showHeader: false,
          isLatest: true,
          message: ChatMessage(id: 'a1', role: MessageRole.assistant, text: 'Done.'),
          onCopy: () => copied++,
          onSpeak: () {},
          onRetry: () => retried++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.byTooltip('Speak'), findsOneWidget);
    expect(find.byTooltip('Retry'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(copied, 1);
    expect(find.text('Copied'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsNothing);

    await tester.tap(find.byTooltip('Retry'));
    expect(retried, 1);
  });

  testWidgets('older replies keep their actions for long-press only', (tester) async {
    await tester.pumpWidget(
      _host(
        MessageBubble(
          showHeader: false,
          message: ChatMessage(id: 'a1', role: MessageRole.assistant, text: 'Done.'),
          onCopy: () {},
          onSpeak: () {},
          onRetry: () {},
        ),
      ),
    );
    expect(find.byTooltip('Copy'), findsNothing);
  });

  testWidgets('a failed message offers Not sent · Retry', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      _host(
        MessageBubble(
          message: ChatMessage(
            id: 'u1',
            role: MessageRole.user,
            text: 'Plan Friday',
            error: true,
          ),
          onRetry: () => retried++,
        ),
      ),
    );

    expect(find.text('Plan Friday'), findsOneWidget);
    await tester.tap(find.text('Not sent · Retry'));
    expect(retried, 1);
  });

  testWidgets('long code folds behind Show all and copies in place', (tester) async {
    final code = [for (var i = 1; i <= 30; i++) 'line $i'].join('\n');
    final copies = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copies.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(_host(ReplyCodeBlock(code: code, language: 'txt')));

    expect(find.text('Show all 30 lines'), findsOneWidget);
    expect(find.textContaining('line 30'), findsNothing);

    await tester.tap(find.text('Show all 30 lines'));
    await tester.pump();
    expect(find.textContaining('line 30'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy code'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(copies.single, code);
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('voice reply card says when it is playing', (tester) async {
    await tester.pumpWidget(
      _host(const VoiceNoteCard(playing: true, onPlay: null, seed: 'a1')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Voice reply'), findsOneWidget);
    expect(find.text('Playing'), findsOneWidget);
    expect(find.text('Tap to play'), findsNothing);
  });
}
