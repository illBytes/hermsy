import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/presence/presence_engine.dart';
import 'package:hermes_app/presence/presence_shaders.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/edge_glow.dart';
import 'package:hermes_app/widgets/frank_backdrop.dart';
import 'package:hermes_app/widgets/presence_picker.dart';
import 'package:hermes_app/widgets/presence_preview.dart';

void main() {
  late PresenceEngine engine;

  setUp(() {
    engine = PresenceEngine(vsync: const TestVSync());
  });

  tearDown(() {
    engine.dispose();
  });

  Future<void> run(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Widget app({required Widget home}) {
    return MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => PresenceScope(
        engine: engine,
        child: Stack(
          fit: StackFit.expand,
          children: [child!, const EdgeGlowLayer()],
        ),
      ),
      home: home,
    );
  }

  testWidgets('the glow layer builds above the app and is idle at rest',
      (tester) async {
    await tester.pumpWidget(app(home: const Scaffold(body: Text('Inside'))));
    await tester.pump();

    expect(find.byType(EdgeGlowLayer), findsOneWidget);
    expect(find.text('Inside'), findsOneWidget);
    expect(engine.ticking, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('touches pass through the glow while it is lit',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Tap me'),
            ),
          ),
        ),
      ),
    );
    engine.event(PresenceEvent.unlock);
    await run(tester, 200);
    expect(engine.frame.visible, isTrue);

    await tester.tap(find.text('Tap me'));
    expect(taps, 1);
    engine.silence();
  });

  testWidgets('the painter draws a lit frame with the shader and without',
      (tester) async {
    engine.event(PresenceEvent.listenStart, origin: const Offset(370, 860));
    await run(tester, 300);
    expect(engine.frame.visible, isTrue);

    void paint(EdgeGlowResources resources) {
      final recorder = ui.PictureRecorder();
      EdgeGlowPainter(
        engine: engine,
        resources: resources,
        radius: 44,
        devicePixelRatio: 3,
      ).paint(Canvas(recorder), const Size(412, 892));
      recorder.endRecording().dispose();
    }

    // Fallback: blurred strokes, no shader.
    final fallback = EdgeGlowResources();
    expect(fallback.shader, isNull);
    paint(fallback);

    // Shader: every uniform index must exist (setFloat asserts otherwise).
    final program = await tester.runAsync(PresenceShaders.loadEdgeGlow);
    if (program != null) {
      final resources = EdgeGlowResources()..load(() {});
      expect(resources.shader, isNotNull);
      paint(resources);
      resources.dispose();
    }
    engine.silence();
  });

  testWidgets('the painter repaints only when its inputs change',
      (tester) async {
    final resources = EdgeGlowResources();
    EdgeGlowPainter painter(double radius) => EdgeGlowPainter(
          engine: engine,
          resources: resources,
          radius: radius,
          devicePixelRatio: 3,
        );
    expect(painter(44).shouldRepaint(painter(44)), isFalse);
    expect(painter(52).shouldRepaint(painter(44)), isTrue);
  });

  testWidgets('the backdrop is static and shows its child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const FrankBackdrop(
          live: true,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Text('Inside'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inside'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the preview tours Hermsy\'s states under a scrubber',
      (tester) async {
    await tester.pumpWidget(
      app(
        home: const Scaffold(
          body: Center(child: PresencePreview(style: PresenceStyle.aura)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('While Hermsy is working'), findsOneWidget);
    for (final label in const [
      'Listening',
      'Thinking',
      'Tool',
      'Replying',
      'Speaking',
      'Done',
      'Error',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    // Tapping a state pins it; the tour keeps running without errors.
    await tester.tap(find.text('Thinking'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2600));
    expect(find.text('Thinking'), findsOneWidget);
  });

  testWidgets('the off preview says there is no edge glow', (tester) async {
    await tester.pumpWidget(
      app(
        home: const Scaffold(
          body: Center(child: PresencePreview(style: PresenceStyle.off)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No edge glow'), findsOneWidget);
    expect(find.text('While Hermsy is working'), findsNothing);
  });

  testWidgets('the picker lists every style and runs the real preview',
      (tester) async {
    PresenceStyle? picked;
    await tester.pumpWidget(
      app(
        home: Scaffold(
          body: PresencePicker(
            current: PresenceStyle.aura,
            onChanged: (style) => picked = style,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Presence'), findsOneWidget);
    expect(find.byType(PresencePreview), findsOneWidget);
    for (final style in AppSettings.presenceOrder) {
      expect(find.text(AppSettings.presenceLabel(style)), findsOneWidget);
    }

    await tester.tap(find.text('Twin'));
    await tester.pump();
    expect(picked, PresenceStyle.twin);

    await tester.ensureVisible(find.text('Preview on screen'));
    await tester.pump();
    await tester.tap(find.text('Preview on screen'));
    await tester.pump();
    expect(find.text('Previewing…'), findsOneWidget);
    await run(tester, 600);
    expect(engine.frame.visible, isTrue);
    await run(tester, 9000);
    expect(find.text('Preview on screen'), findsOneWidget);
    expect(engine.ticking, isFalse);
  });
}
