import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/frank_orb.dart';
import 'package:hermes_app/widgets/listening_stage.dart';

Widget _app(Widget stage, {VoidCallback? onTapBehind}) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapBehind,
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: stage),
        ],
      ),
    ),
  );
}

/// Lets switchers drop their outgoing children; the live orb keeps ticking,
/// so pumpAndSettle would not return while the stage is up.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  final level = ValueNotifier<double>(0);

  testWidgets('renders nothing while inactive', (tester) async {
    await tester.pumpWidget(_app(ListeningStage(active: false, level: level)));

    expect(find.byType(FrankOrb), findsNothing);
    expect(find.text('Listening…'), findsNothing);
  });

  testWidgets('rises with a listening orb; the capsule keeps the time',
      (tester) async {
    await tester.pumpWidget(_app(ListeningStage(active: false, level: level)));
    await tester.pumpWidget(_app(ListeningStage(active: true, level: level)));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FrankOrb), findsOneWidget);
    expect(find.text('Listening…'), findsOneWidget);
    expect(find.text('Speak naturally — Hermsy is listening'), findsOneWidget);
    // One timer on screen: the composer capsule's, not a second one here.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('0:02'), findsNothing);
  });

  testWidgets('streams on-device words', (tester) async {
    final words = ValueNotifier('');
    await tester.pumpWidget(
      _app(
        ListeningStage(
          active: true,
          level: level,
          transcript: words,
          onDevice: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Listening…'), findsOneWidget);

    words.value = 'what is on my calendar tomorrow';
    await _settle(tester);
    expect(find.text('what is on my calendar tomorrow'), findsOneWidget);
    expect(find.text('Listening…'), findsNothing);
  });

  testWidgets('shows transcribing after the voice note is sent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(ListeningStage(active: true, level: level, transcribing: true)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Transcribing'), findsOneWidget);
    expect(find.text('Listening…'), findsNothing);
  });

  testWidgets('the hint follows how the mic is held', (tester) async {
    final capture = ValueNotifier(VoiceCapture.holding);
    await tester.pumpWidget(
      _app(ListeningStage(active: true, level: level, capture: capture)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Release to send'), findsOneWidget);

    capture.value = VoiceCapture.handsFree;
    await _settle(tester);
    expect(find.text('Tap send when you\'re done'), findsOneWidget);
  });

  testWidgets('never blocks touches behind it', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _app(
        ListeningStage(active: true, level: level),
        onTapBehind: () => tapped = true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byType(FrankOrb), warnIfMissed: false);
    expect(tapped, isTrue);
  });

  testWidgets('leaves the tree and settles once inactive', (tester) async {
    await tester.pumpWidget(_app(ListeningStage(active: true, level: level)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FrankOrb), findsOneWidget);

    await tester.pumpWidget(_app(ListeningStage(active: false, level: level)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FrankOrb), findsNothing);
    await tester.pumpAndSettle();
  });

  test('formats the voice clock', () {
    expect(formatVoiceClock(0), '0:00');
    expect(formatVoiceClock(7), '0:07');
    expect(formatVoiceClock(102), '1:42');
  });
}
