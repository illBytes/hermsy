import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/composer_bar.dart';
import 'package:hermes_app/widgets/listening_stage.dart';

void main() {
  testWidgets('shows stop instead of send while Hermsy is answering', (
    tester,
  ) async {
    var stopped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ComposerBar(
            controller: TextEditingController(text: 'Hello'),
            enabled: false,
            recording: false,
            sending: true,
            showMic: false,
            onSend: () {},
            onStop: () => stopped = true,
            onRecordStart: () {},
            onRecordStop: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Stop reply'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    await tester.tap(find.byTooltip('Stop reply'));
    expect(stopped, isTrue);
  });

  testWidgets(
    'the wave beside the mic starts a call, and steps aside for send',
    (tester) async {
      var calls = 0;
      final text = TextEditingController();
      Widget bar() => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ComposerBar(
            controller: text,
            enabled: true,
            recording: false,
            sending: false,
            showMic: text.text.isEmpty,
            onSend: () {},
            onStop: () {},
            onRecordStart: () {},
            onRecordStop: () {},
            onCall: () => calls++,
          ),
        ),
      );
      await tester.pumpWidget(bar());
      await _settle(tester);

      expect(find.byTooltip('Voice call'), findsOneWidget);
      await tester.tap(find.byTooltip('Voice call'));
      expect(calls, 1);

      text.text = 'Typed something';
      await tester.pumpWidget(bar());
      await _settle(tester);
      expect(find.byTooltip('Voice call'), findsNothing);
      expect(find.byTooltip('Send'), findsOneWidget);
    },
  );

  testWidgets('hides attach while sending but keeps the field', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ComposerBar(
            controller: TextEditingController(),
            enabled: true,
            recording: false,
            sending: true,
            showMic: true,
            onSend: () {},
            onStop: () {},
            onRecordStart: () {},
            onRecordStop: () {},
            onAttach: () {},
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byTooltip('Attach photo'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Message Hermsy'), findsOneWidget);
  });

  testWidgets('shows an attach control when photos are enabled', (
    tester,
  ) async {
    var attached = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ComposerBar(
            controller: TextEditingController(),
            enabled: true,
            recording: false,
            sending: false,
            showMic: true,
            onSend: () {},
            onStop: () {},
            onRecordStart: () {},
            onRecordStop: () {},
            onAttach: () => attached = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byTooltip('Attach photo'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_rounded));
    expect(attached, isTrue);
  });

  testWidgets('morphs the mic into send once there is text', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_Harness(controller: controller));
    final harness = tester.state<_HarnessState>(find.byType(_Harness));

    expect(find.text('Message Hermsy'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byTooltip('Send'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Hello Hermsy');
    await _settle(tester);

    expect(find.byIcon(Icons.mic_rounded), findsNothing);
    await tester.tap(find.byTooltip('Send'));
    expect(harness.sends, 1);
  });

  testWidgets('holding the mic records and releasing sends', (tester) async {
    await tester.pumpWidget(const _Harness());
    final harness = tester.state<_HarnessState>(find.byType(_Harness));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await tester.pump();
    await _settle(tester);

    expect(harness.starts, 1);
    expect(harness.recording, isTrue);
    expect(find.text('Slide left to cancel · up to lock'), findsOneWidget);
    expect(find.byTooltip('Cancel recording'), findsOneWidget);

    await gesture.up(timeStamp: const Duration(milliseconds: 900));
    await _settle(tester);

    expect(harness.stops, 1);
    expect(harness.cancels, 0);
    expect(harness.recording, isFalse);
    // No flash of the idle composer while Hermes picks the note up.
    expect(find.text('Transcribing'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
  });

  testWidgets('holding with the keyboard up keeps it up until release', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await _settle(tester);
    expect(field.focusNode!.hasFocus, isTrue);

    await gesture.up(timeStamp: const Duration(seconds: 2));
    await _settle(tester);
    expect(field.focusNode!.hasFocus, isFalse);
  });

  testWidgets('an idle composer is completely still', (tester) async {
    await tester.pumpWidget(const _Harness());
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a quick tap keeps recording hands-free until Send', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    final harness = tester.state<_HarnessState>(find.byType(_Harness));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await tester.pump();
    await gesture.up(timeStamp: const Duration(milliseconds: 120));
    await _settle(tester);

    expect(harness.starts, 1);
    expect(harness.stops, 0);
    expect(harness.recording, isTrue);
    expect(find.text('Slide left to cancel · up to lock'), findsNothing);

    await tester.tap(find.byTooltip('Send voice'));
    await _settle(tester);
    expect(harness.stops, 1);
  });

  testWidgets('a short hold never sends an empty blip', (tester) async {
    await tester.pumpWidget(const _Harness());
    final harness = tester.state<_HarnessState>(find.byType(_Harness));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await tester.pump();
    await gesture.up(timeStamp: const Duration(milliseconds: 450));
    await _settle(tester);

    expect(harness.stops, 0);
    expect(harness.recording, isTrue);
    expect(find.byTooltip('Send voice'), findsOneWidget);
  });

  testWidgets('sliding left past the threshold cancels', (tester) async {
    await tester.pumpWidget(const _Harness());
    final harness = tester.state<_HarnessState>(find.byType(_Harness));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(-50, 0));
    await tester.pump();
    expect(harness.cancels, 0);

    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(harness.cancels, 1);

    await gesture.up(timeStamp: const Duration(seconds: 2));
    await _settle(tester);
    expect(harness.stops, 0);
    expect(harness.recording, isFalse);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
  });

  testWidgets('sliding up locks hands-free', (tester) async {
    final capture = ValueNotifier(VoiceCapture.none);
    await tester.pumpWidget(_Harness(capture: capture));
    final harness = tester.state<_HarnessState>(find.byType(_Harness));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await tester.pump();
    expect(capture.value, VoiceCapture.holding);

    await gesture.moveBy(const Offset(0, -90));
    await tester.pump();
    await gesture.up(timeStamp: const Duration(seconds: 2));
    await _settle(tester);

    expect(harness.stops, 0);
    expect(harness.recording, isTrue);
    expect(capture.value, VoiceCapture.handsFree);
    expect(find.byTooltip('Send voice'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel recording'));
    await _settle(tester);
    expect(harness.cancels, 1);
    expect(capture.value, VoiceCapture.none);
  });

  testWidgets('shows the transcribing state after a voice note', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ComposerBar(
            controller: TextEditingController(),
            enabled: true,
            recording: false,
            sending: false,
            showMic: true,
            transcribing: true,
            onSend: () {},
            onStop: () {},
            onRecordStart: () {},
            onRecordStop: () {},
            onAttach: () {},
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('Transcribing'), findsOneWidget);
    expect(find.byTooltip('Transcribing'), findsOneWidget);
    expect(find.byTooltip('Attach photo'), findsNothing);
    // The field stays mounted (keeping any draft) but hidden and inert.
    final field = find.ancestor(
      of: find.byType(TextField),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(field.first).opacity, 0);
  });

  testWidgets('streams on-device words into the recording capsule', (
    tester,
  ) async {
    final words = ValueNotifier('');
    await tester.pumpWidget(_Harness(transcript: words));

    await tester.tap(find.byIcon(Icons.mic_rounded));
    await _settle(tester);
    expect(find.text('Listening on device'), findsOneWidget);

    words.value = 'remind me to call';
    await _settle(tester);
    expect(find.text('remind me to call'), findsOneWidget);
  });

  testWidgets('the slash palette filters and runs a command', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_Harness(controller: controller));
    final harness = tester.state<_HarnessState>(find.byType(_Harness));

    await tester.enterText(find.byType(TextField), '/');
    await _settle(tester);
    expect(find.text('/new'), findsOneWidget);
    expect(find.text('/usage'), findsOneWidget);
    expect(find.text('/help', skipOffstage: false), findsOneWidget);

    await tester.enterText(find.byType(TextField), '/us');
    await _settle(tester);
    expect(find.text('Tokens and cost for this chat'), findsOneWidget);
    expect(find.text('/help'), findsNothing);

    await tester.tap(find.text('/usage'));
    await tester.pump();
    expect(harness.sends, 1);
    expect(harness.sentText, '/usage');

    await tester.enterText(find.byType(TextField), '/usage now');
    await _settle(tester);
    expect(find.text('Tokens and cost for this chat'), findsNothing);
  });

  testWidgets('no slash palette while photos are attached', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ComposerBar(
              controller: TextEditingController(text: '/'),
              enabled: true,
              recording: false,
              sending: false,
              showMic: false,
              onSend: () {},
              onStop: () {},
              onRecordStart: () {},
              onRecordStop: () {},
              onAttach: () {},
              pendingImages: const ['/nowhere/photo.jpg'],
              onRemoveImage: (_) {},
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    // A command would go to Frank as the photo's caption.
    expect(find.text('/new'), findsNothing);
    expect(find.text('/usage'), findsNothing);
  });

  testWidgets('/stop from the palette stops a reply instead of sending', (
    tester,
  ) async {
    final controller = TextEditingController(text: '/st');
    var stopped = false;
    var sent = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ComposerBar(
              controller: controller,
              enabled: true,
              recording: false,
              sending: true,
              showMic: false,
              onSend: () => sent = true,
              onStop: () => stopped = true,
              onRecordStart: () {},
              onRecordStop: () {},
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('/stop'));
    expect(stopped, isTrue);
    expect(sent, isFalse);
    expect(controller.text, isEmpty);
  });

  testWidgets('pending photos can be removed and change the hint', (
    tester,
  ) async {
    String? removed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ComposerBar(
            controller: TextEditingController(),
            enabled: true,
            recording: false,
            sending: false,
            showMic: false,
            pendingImages: const ['/missing/photo.jpg'],
            onRemoveImage: (path) => removed = path,
            onSend: () {},
            onStop: () {},
            onRecordStart: () {},
            onRecordStop: () {},
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('Add a caption'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove photo'));
    expect(removed, '/missing/photo.jpg');
  });

  testWidgets('a disabled composer says it is connecting and ignores the mic', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness(enabled: false));
    final harness = tester.state<_HarnessState>(find.byType(_Harness));

    expect(find.text('Connecting to Hermes…'), findsOneWidget);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await tester.pump();
    await gesture.up(timeStamp: const Duration(seconds: 1));
    await tester.pump();
    expect(harness.starts, 0);
  });
}

/// Lets switchers finish and drop their outgoing children. Recording keeps a
/// ticker running, so pumpAndSettle would never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// A composer wired like the chat screen: recording follows the callbacks.
class _Harness extends StatefulWidget {
  const _Harness({
    this.controller,
    this.enabled = true,
    this.transcript,
    this.capture,
  });

  final TextEditingController? controller;
  final bool enabled;
  final ValueNotifier<String>? transcript;
  final ValueNotifier<VoiceCapture>? capture;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final controller = widget.controller ?? TextEditingController();
  bool recording = false;
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  int sends = 0;
  String? sentText;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return ComposerBar(
                controller: controller,
                enabled: widget.enabled,
                recording: recording,
                sending: false,
                showMic: controller.text.trim().isEmpty,
                transcript: widget.transcript,
                onDeviceDictation: widget.transcript != null,
                capture: widget.capture,
                onSend: () {
                  sends++;
                  sentText = controller.text;
                  controller.clear();
                },
                onStop: () {},
                onRecordStart: () => setState(() {
                  starts++;
                  recording = true;
                }),
                onRecordStop: () => setState(() {
                  stops++;
                  recording = false;
                }),
                onCancelRecording: () => setState(() {
                  cancels++;
                  recording = false;
                }),
                onAttach: () {},
              );
            },
          ),
        ),
      ),
    );
  }
}
