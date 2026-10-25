import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/pin_vault.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/screens/pin_screen.dart';
import 'package:hermes_app/screens/set_pin_screen.dart';
import 'package:hermes_app/services/biometric_gate.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/message_actions_sheet.dart';
import 'package:hermes_app/widgets/message_bubble.dart';
import 'package:hermes_app/widgets/reply_markdown.dart';

void main() {
  testWidgets('unlocks when the PIN matches', (tester) async {
    var unlocked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PinScreen(
          pin: StoredPin.unhashed('1234'),
          onUnlocked: () => unlocked = true,
        ),
      ),
    );

    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit).first);
      await tester.pump();
    }

    // The dots fly into the orb first; the screen hands over after the beat.
    expect(unlocked, isFalse);
    await tester.pump(const Duration(milliseconds: 400));

    expect(unlocked, isTrue);
  });

  testWidgets('rejects the wrong PIN', (tester) async {
    var unlocked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PinScreen(
          pin: StoredPin.unhashed('1234'),
          onUnlocked: () => unlocked = true,
        ),
      ),
    );

    for (final digit in ['0', '0', '0', '0']) {
      await tester.tap(find.text(digit).first);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 50));

    expect(unlocked, isFalse);
    expect(find.text('Wrong PIN'), findsOneWidget);
  });

  testWidgets('creates a PIN after confirm', (tester) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: SetPinScreen(onSaved: (pin) => saved = pin),
      ),
    );

    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit).first);
      await tester.pump();
    }
    await tester.tap(find.text('Continue'));
    await tester.pump();

    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit).first);
      await tester.pump();
    }
    await tester.tap(find.text('Save PIN'));
    await tester.pump();

    expect(saved, '1234');
  });

  testWidgets('pauses the PIN pad after five wrong tries', (tester) async {
    var unlocked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PinScreen(
          pin: StoredPin.unhashed('1234'),
          onUnlocked: () => unlocked = true,
        ),
      ),
    );

    Future<void> enter(String pin) async {
      for (final digit in pin.split('')) {
        await tester.tap(find.text(digit).first);
        await tester.pump();
      }
    }

    for (var i = 0; i < 5; i++) {
      await enter('0000');
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Too many attempts'), findsOneWidget);
    expect(find.text('Try again in 0:30'), findsOneWidget);

    // The pad ignores digits while it waits.
    await enter('1234');
    await tester.pump(const Duration(milliseconds: 400));
    expect(unlocked, isFalse);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Try again in 0:29'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Too many attempts'), findsNothing);
    await enter('1234');
    await tester.pump(const Duration(milliseconds: 400));
    expect(unlocked, isTrue);
  });

  testWidgets('holding delete clears the PIN', (tester) async {
    var unlocked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PinScreen(
          pin: StoredPin.unhashed('1234'),
          onUnlocked: () => unlocked = true,
        ),
      ),
    );

    for (final digit in ['9', '9']) {
      await tester.tap(find.text(digit).first);
      await tester.pump();
    }
    await tester.longPress(find.byTooltip('Delete'));
    await tester.pump();

    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit).first);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));

    expect(unlocked, isTrue);
  });

  testWidgets('biometric unlock plays the same beat', (tester) async {
    var unlocked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PinScreen(
          pin: StoredPin.unhashed('1234'),
          biometric: _PassingGate(),
          onUnlocked: () => unlocked = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Touch the sensor or enter your PIN'), findsOneWidget);
    expect(unlocked, isFalse);
    await tester.pump(const Duration(milliseconds: 400));

    expect(unlocked, isTrue);
  });

  testWidgets('a mismatched confirm starts the PIN over', (tester) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: SetPinScreen(onSaved: (pin) => saved = pin),
      ),
    );

    expect(find.text('STEP 1 OF 2'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit).first);
      await tester.pump();
    }
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('STEP 2 OF 2'), findsOneWidget);
    expect(find.text('Confirm your PIN'), findsOneWidget);

    for (final digit in ['5', '6', '7', '8']) {
      await tester.tap(find.text(digit).first);
      await tester.pump();
    }
    await tester.tap(find.text('Save PIN'));
    await tester.pump();
    expect(find.text("PINs didn't match. Start again."), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    expect(saved, isNull);
    expect(find.text('STEP 1 OF 2'), findsOneWidget);
    expect(find.text('Create a PIN'), findsOneWidget);
  });

  testWidgets('change PIN can be cancelled', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SetPinScreen(
          title: 'Change PIN',
          onSaved: (_) {},
          onCancel: () => cancelled = true,
        ),
      ),
    );

    expect(find.text('Change PIN'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel'));
    expect(cancelled, isTrue);
  });

  testWidgets('shows a playable voice card on a voice message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'u1',
              role: MessageRole.user,
              text: 'Meet me at six',
              isVoice: true,
              audioPath: '/tmp/note.m4a',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Voice note'), findsOneWidget);
    expect(find.text('Tap to play'), findsOneWidget);
    expect(find.text('Meet me at six'), findsOneWidget);
  });

  testWidgets('renders markdown in a Hermsy reply', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'a1',
              role: MessageRole.assistant,
              text: 'Say **hello** and then *quietly*.',
            ),
          ),
        ),
      ),
    );

    expect(find.text('**hello**'), findsNothing);
    expect(find.byType(ReplyMarkdown), findsOneWidget);
    expect(find.textContaining('hello'), findsWidgets);
  });

  testWidgets('long-press actions include copy, select text, speak, and retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: MessageActionsSheet(
            onCopy: _noop,
            onSelectText: _noop,
            onSpeak: _noop,
            onRetry: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select text'), findsOneWidget);
    expect(find.text('Speak'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

void _noop() {}

/// A fingerprint sensor that always recognises the finger.
class _PassingGate extends BiometricGate {
  @override
  Future<BiometricOffer> probe() async => BiometricOffer.fingerprint;

  @override
  Future<bool> authenticate() async => true;
}
