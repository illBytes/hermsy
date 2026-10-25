import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/state/assistant_mood.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/frank_backdrop.dart';
import 'package:hermes_app/widgets/frank_mark.dart';
import 'package:hermes_app/widgets/frank_orb.dart';
import 'package:hermes_app/widgets/typing_indicator.dart';

void main() {
  testWidgets('Hermsy mark is an orb', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FrankMark(size: 48, active: true),
        ),
      ),
    );

    expect(find.byType(FrankOrb), findsOneWidget);
    expect(find.text('F'), findsNothing);
  });

  testWidgets('live orb announces that Hermsy is responding', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FrankOrb(size: 36, live: true, intense: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.bySemanticsLabel('Hermsy is responding'), findsOneWidget);
  });

  testWidgets('listening orb announces that Hermsy is listening', (
    tester,
  ) async {
    await tester.pumpWidget(
      _orb(
        const FrankMark(size: 30, active: true, mood: AssistantMood.listening),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.bySemanticsLabel('Hermsy is listening'), findsOneWidget);
  });

  testWidgets('idle orb paints one still frame without a ticker', (
    tester,
  ) async {
    await tester.pumpWidget(_orb(const FrankOrb(size: 112)));
    await tester.pump();

    expect(find.bySemanticsLabel('Hermsy'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a still orb never ticks, even while Hermsy is busy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _orb(const FrankOrb(size: 44, live: false, mood: AssistantMood.thinking)),
    );
    await tester.pump();

    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(
      _orb(const FrankOrb(size: 44, live: false, mood: AssistantMood.tool)),
    );
    await tester.pumpAndSettle();

    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('busy orb moves, then settles once Hermsy is idle', (
    tester,
  ) async {
    await tester.pumpWidget(
      _orb(const FrankOrb(size: 30, mood: AssistantMood.thinking)),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(
      _orb(const FrankOrb(size: 30, mood: AssistantMood.responding)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    // The done flash plays, then the orb freezes.
    await tester.pumpWidget(
      _orb(const FrankOrb(size: 30, mood: AssistantMood.idle)),
    );
    await tester.pumpAndSettle();

    expect(tester.binding.transientCallbackCount, 0);
    expect(find.bySemanticsLabel('Hermsy'), findsOneWidget);
  });

  testWidgets('a live idle orb wakes briefly, then dozes off', (tester) async {
    await tester.pumpWidget(
      _orb(const FrankOrb(size: 112, live: true, mood: AssistantMood.idle)),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpAndSettle();

    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('error shakes the orb once, then it rests', (tester) async {
    await tester.pumpWidget(
      _orb(const FrankOrb(size: 44, mood: AssistantMood.thinking)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(
      _orb(const FrankOrb(size: 44, mood: AssistantMood.error)),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpAndSettle();

    expect(tester.binding.transientCallbackCount, 0);
    expect(find.bySemanticsLabel('Hermsy'), findsOneWidget);
  });

  testWidgets('pulse plays a one-shot flash on a resting orb', (tester) async {
    await tester.pumpWidget(_orb(const FrankOrb(size: 96)));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_orb(const FrankOrb(size: 96, pulse: 1)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion still animates while busy and settles after', (
    tester,
  ) async {
    final level = ValueNotifier<double>(0.8);
    addTearDown(level.dispose);
    Widget reduced(AssistantMood mood) {
      return MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: FrankOrb(size: 120, mood: mood, level: level),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(reduced(AssistantMood.listening));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(reduced(AssistantMood.idle));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final fallback in [false, true]) {
    testWidgets(
      'orb paints every mood at every size '
      '(${fallback ? 'canvas fallback' : 'shader'})',
      (tester) async {
        FrankOrb.debugForceFallback = fallback;
        addTearDown(() => FrankOrb.debugForceFallback = false);
        if (!fallback) {
          await tester.runAsync(FrankOrb.precache);
        }
        final level = ValueNotifier<double>(0.9);
        addTearDown(level.dispose);

        for (final mood in AssistantMood.values) {
          await tester.pumpWidget(
            _orb(
              Wrap(
                children: [
                  for (final size in const [16.0, 30.0, 44.0, 112.0]) ...[
                    FrankOrb(size: size, mood: mood, level: level),
                    FrankOrb(size: size, mood: mood, lit: false, live: false),
                  ],
                ],
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull, reason: '$mood');
        }

        await tester.pumpWidget(_orb(const SizedBox()));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('typing indicator is a live orb', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TypingIndicator()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(FrankOrb), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);
  });

  testWidgets('live backdrop still shows its child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const FrankBackdrop(
          live: true,
          presence: PresenceStyle.off,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Text('Inside'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Inside'), findsOneWidget);
  });
}

Widget _orb(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}
