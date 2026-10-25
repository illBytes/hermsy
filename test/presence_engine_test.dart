import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/presence/glow_geometry.dart';
import 'package:hermes_app/presence/presence_engine.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/state/assistant_mood.dart';

/// A stand-in conversation the engine can follow.
class _Feed extends ChangeNotifier implements PresenceFeed {
  AssistantMood _mood = AssistantMood.idle;
  String? _tool;
  (String, int)? _reply;
  final ValueNotifier<double> level = ValueNotifier<double>(0);

  @override
  AssistantMood get mood => _mood;
  set mood(AssistantMood value) {
    _mood = value;
    notifyListeners();
  }

  @override
  String? get toolLabel => _tool;
  set toolLabel(String? value) {
    _tool = value;
    notifyListeners();
  }

  @override
  (String, int)? get streamingReply => _reply;
  set streamingReply((String, int)? value) {
    _reply = value;
    notifyListeners();
  }

  @override
  ValueListenable<double> get voiceLevel => level;
}

void main() {
  late PresenceEngine engine;
  late _Feed feed;

  /// A widget test that leaves the engine silent, so no ticker outlives it.
  void glowTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      await body(tester);
      engine.silence();
    });
  }

  setUp(() {
    engine = PresenceEngine(vsync: const TestVSync());
    feed = _Feed();
  });

  tearDown(() {
    engine.dispose();
  });

  /// Runs the engine's ticker for [ms] milliseconds in 60Hz steps.
  Future<void> run(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  glowTest('starts dark, idle and not ticking', (tester) async {
    expect(engine.mood, AssistantMood.idle);
    expect(engine.ticking, isFalse);
    expect(engine.frame.visible, isFalse);
    expect(engine.level.value, 0);
  });

  glowTest('every beat is safe without a chat and settles dark',
      (tester) async {
    for (final event in PresenceEvent.values) {
      engine.event(event, origin: const Offset(40, 40), strength: 0.5);
      await run(tester, 48);
    }
    await run(tester, 3000);
    expect(engine.ticking, isFalse);
    expect(engine.frame.visible, isFalse);
  });

  glowTest('listening blooms, and the ticker stops once Hermsy is idle',
      (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.listening;
    expect(engine.mood, AssistantMood.listening);
    await run(tester, 600);
    expect(engine.ticking, isTrue);
    expect(engine.frame.visible, isTrue);
    expect(engine.frame.reveal, closeTo(1, 0.01));
    expect(engine.frame.bias, greaterThan(0.5), reason: 'input glows from below');

    feed.mood = AssistantMood.idle;
    await run(tester, 2000);
    expect(engine.ticking, isFalse);
    expect(engine.frame.visible, isFalse);
  });

  glowTest('the voice level thickens the light and spawns ripples',
      (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.listening;
    await run(tester, 400);
    final quiet = engine.frame.amp;
    feed.level.value = 0.9;
    await run(tester, 96);
    expect(engine.frame.amp, greaterThan(quiet + 0.3));
    expect(
      engine.frame.ripples[1] > 0 || engine.frame.ripples[3] > 0,
      isTrue,
      reason: 'a sudden onset sends a ripple up the frame',
    );
  });

  glowTest('a finished reply plays the done sweep, then goes dark',
      (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.thinking;
    await run(tester, 400);
    feed
      ..streamingReply = ('a', 4)
      ..mood = AssistantMood.responding;
    await run(tester, 200);
    feed.streamingReply = ('a', 120);
    await run(tester, 32);
    feed
      ..streamingReply = null
      ..mood = AssistantMood.idle;
    await run(tester, 240);
    expect(engine.lastEvent, PresenceEvent.done);
    expect(engine.frame.flash, greaterThanOrEqualTo(0));
    await run(tester, 2000);
    expect(engine.ticking, isFalse);
    expect(engine.frame.visible, isFalse);
  });

  glowTest('a short pass through idle between states is not "done"',
      (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.listening;
    await run(tester, 400);
    // The controller drops to idle for a moment before transcribing.
    feed.mood = AssistantMood.idle;
    await run(tester, 48);
    feed.mood = AssistantMood.transcribing;
    await run(tester, 400);
    expect(engine.lastEvent, isNot(PresenceEvent.done));
    expect(engine.frame.visible, isTrue);
    expect(engine.frame.comet, greaterThanOrEqualTo(0),
        reason: 'two comets fall towards the mic while transcribing');
  });

  glowTest('a failed reply pulses red instead of sweeping', (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.thinking;
    await run(tester, 400);
    feed.mood = AssistantMood.error;
    await run(tester, 200);
    expect(engine.lastEvent, PresenceEvent.error);
    expect(engine.frame.flash, lessThan(0));
    final p = engine.frame.palette;
    expect(p[0], greaterThan(p[2]), reason: 'the palette turns red');
    await run(tester, 3000);
    expect(engine.ticking, isFalse);
  });

  glowTest('an error at launch (not after work) stays dark',
      (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.error;
    await run(tester, 400);
    expect(engine.frame.visible, isFalse);
    expect(engine.lastEvent, isNull);
  });

  glowTest('stopping a reply retracts the light without a sweep',
      (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.responding;
    await run(tester, 500);
    // Stop lands just after the chat settles: still no "done".
    feed.mood = AssistantMood.idle;
    await run(tester, 32);
    engine.event(PresenceEvent.stop);
    await run(tester, 400);
    expect(engine.lastEvent, PresenceEvent.stop);
    expect(engine.frame.flash, lessThan(0));
    expect(engine.frame.visible, isFalse);
    expect(engine.ticking, isFalse);
  });

  glowTest('a mic that heard nothing pulses softly after idle', (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.transcribing;
    await run(tester, 400);
    // On-device dictation notifies idle first, then the error.
    feed.mood = AssistantMood.idle;
    await run(tester, 16);
    feed.mood = AssistantMood.error;
    await run(tester, 100);
    expect(engine.lastEvent, PresenceEvent.error);
    expect(engine.frame.flash, lessThan(0));
    await run(tester, 3000);
    expect(engine.ticking, isFalse);
  });

  glowTest('a reply read aloud still lands with the done sweep',
      (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.responding;
    await run(tester, 500);
    // The reply finishes, and speech starts within the settle window.
    feed.mood = AssistantMood.idle;
    await run(tester, 32);
    feed.mood = AssistantMood.speaking;
    await run(tester, 64);
    expect(engine.lastEvent, PresenceEvent.done);
    expect(engine.frame.flash, greaterThanOrEqualTo(0));
    expect(engine.frame.visible, isTrue, reason: 'then it hands to speaking');
  });

  glowTest('a Stop does not swallow the next reply\'s sweep', (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.responding;
    await run(tester, 500);
    feed.mood = AssistantMood.idle;
    await run(tester, 32);
    engine.event(PresenceEvent.stop);
    await run(tester, 600);
    expect(engine.ticking, isFalse);

    // Later, a short reply finishes normally.
    feed.mood = AssistantMood.responding;
    await run(tester, 700);
    feed.mood = AssistantMood.idle;
    await run(tester, 240);
    expect(engine.lastEvent, PresenceEvent.done);
    await run(tester, 2000);
  });

  glowTest('a beat that lands just after its mood still blooms from it',
      (tester) async {
    engine.updateGeometry(const Size(400, 800), 40);
    engine.follow(feed);
    const mic = Offset(368, 770);
    // The controller flips to listening before the composer's beat.
    feed.mood = AssistantMood.listening;
    engine.event(PresenceEvent.listenStart, origin: mic);
    await run(tester, 32);
    expect(
      engine.frame.origin,
      closeTo(const GlowGeometry(Size(400, 800), 40).loopOf(mic), 1e-9),
    );
  });

  glowTest('the light past the reading gutter is capped for text',
      (tester) async {
    final settings = AppSettings()..glowIntensity = GlowIntensity.vivid;
    engine
      ..configure(settings)
      ..follow(feed);
    feed.mood = AssistantMood.responding;
    await run(tester, 400);
    expect(engine.frame.readCap, 0.22);
    feed.mood = AssistantMood.listening;
    feed.level.value = 1;
    await run(tester, 400);
    expect(engine.frame.readCap, greaterThan(0.3));
    expect(engine.frame.readCap, lessThanOrEqualTo(0.35));
  });

  glowTest('a new tool label spikes a comet', (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.thinking;
    await run(tester, 300);
    feed
      ..toolLabel = '🔍 Web search: weather'
      ..mood = AssistantMood.tool;
    await run(tester, 32);
    expect(engine.lastEvent, PresenceEvent.tool);
    expect(engine.frame.comet, greaterThanOrEqualTo(0));
    expect(engine.frame.cometGain, greaterThan(1));
  });

  glowTest('streamed words pump the light while replying', (tester) async {
    engine.follow(feed);
    feed
      ..streamingReply = ('a', 0)
      ..mood = AssistantMood.responding;
    await run(tester, 600);
    final resting = engine.frame.depth;
    for (var i = 1; i <= 6; i++) {
      feed.streamingReply = ('a', i * 40);
      await run(tester, 32);
    }
    expect(engine.frame.depth, greaterThan(resting + 2));
  });

  glowTest('send blooms from where the finger landed', (tester) async {
    engine.updateGeometry(const Size(400, 800), 40);
    const thumb = Offset(360, 770);
    engine.event(PresenceEvent.send, origin: thumb);
    await run(tester, 32);
    expect(engine.frame.visible, isTrue);
    expect(
      engine.frame.origin,
      closeTo(const GlowGeometry(Size(400, 800), 40).loopOf(thumb), 1e-9),
    );
    // Nothing followed (a slash command, say): the cue fades on its own.
    await run(tester, 3000);
    expect(engine.ticking, isFalse);
  });

  glowTest('unlock glows gold from the top, then goes dark',
      (tester) async {
    engine.event(PresenceEvent.unlock);
    await run(tester, 200);
    expect(engine.frame.visible, isTrue);
    expect(engine.frame.origin, closeTo(0.5, 1e-9));
    final p = engine.frame.palette;
    expect(p[0], greaterThan(p[2]), reason: 'gold, not aurora');
    await run(tester, 1600);
    expect(engine.frame.visible, isFalse);
    expect(engine.ticking, isFalse);
  });

  glowTest('the off style draws nothing and does not tick',
      (tester) async {
    final settings = AppSettings()..presence = PresenceStyle.off;
    engine
      ..configure(settings)
      ..follow(feed);
    feed.mood = AssistantMood.responding;
    await run(tester, 400);
    expect(engine.frame.visible, isFalse);
    expect(engine.ticking, isFalse);
  });

  glowTest('glow intensity scales the light', (tester) async {
    final settings = AppSettings();
    engine
      ..configure(settings)
      ..follow(feed);
    feed.mood = AssistantMood.tool;
    await run(tester, 600);
    final balanced = engine.frame.intensity;
    settings.glowIntensity = GlowIntensity.subtle;
    await run(tester, 32);
    expect(engine.frame.intensity, closeTo(balanced * 0.6, 0.02));
  });

  glowTest('reduce motion breathes in place: no travel, ripples or sweep',
      (tester) async {
    final settings = AppSettings()..reduceMotion = true;
    engine
      ..configure(settings)
      ..follow(feed);
    feed.mood = AssistantMood.listening;
    await run(tester, 32);
    expect(engine.frame.reveal, 1, reason: 'enters as a fade, not a bloom');
    expect(engine.frame.ringMix, greaterThan(0.5));
    feed.level.value = 1;
    await run(tester, 200);
    expect(engine.frame.ripples[1] + engine.frame.ripples[3], 0);

    feed.level.value = 0;
    feed.mood = AssistantMood.responding;
    await run(tester, 300);
    feed.mood = AssistantMood.idle;
    await run(tester, 240);
    expect(engine.frame.flash, lessThan(0));
  });

  glowTest('speaking glows from the top', (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.speaking;
    await run(tester, 600);
    expect(engine.frame.origin, closeTo(0.5, 1e-9));
    expect(engine.frame.bias, lessThan(-0.5));
  });

  glowTest('recedes while you read a long reply', (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.responding;
    await run(tester, 1000);
    final early = engine.frame.intensity;
    await run(tester, 6200);
    expect(engine.frame.intensity, lessThan(early * 0.75));
  });

  glowTest('preview runs the real sequence and completes', (tester) async {
    var finished = false;
    engine.preview().then((_) => finished = true);
    await run(tester, 600);
    expect(engine.frame.visible, isTrue);
    await run(tester, 9000);
    expect(finished, isTrue);
    expect(engine.lastEvent, PresenceEvent.done);
    expect(engine.ticking, isFalse);
  });

  glowTest('detach goes dark and stops following the old chat',
      (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.thinking;
    await run(tester, 300);
    engine.detach();
    feed.mood = AssistantMood.responding;
    expect(engine.mood, AssistantMood.idle);
    await run(tester, 2000);
    expect(engine.frame.visible, isFalse);
    expect(engine.ticking, isFalse);
  });

  glowTest('silence cuts the light at once', (tester) async {
    engine.follow(feed);
    feed.mood = AssistantMood.listening;
    await run(tester, 300);
    engine
      ..detach()
      ..silence();
    expect(engine.frame.visible, isFalse);
    expect(engine.ticking, isFalse);
  });

  glowTest('the picker preview stages states on its own engine',
      (tester) async {
    engine
      ..setStyle(PresenceStyle.twin)
      ..demo(PresenceDemo.thinking);
    await run(tester, 400);
    expect(engine.frame.visible, isTrue);
    expect(engine.frame.twin, 1);
    expect(engine.frame.cometOnly, closeTo(1, 0.01));
    engine.demo(PresenceDemo.done);
    await run(tester, 2000);
    expect(engine.frame.visible, isFalse);
    expect(engine.ticking, isFalse);
  });

  glowTest('PresenceScope is optional and does not rebuild per tick',
      (tester) async {
    PresenceEngine? found = engine;
    var builds = 0;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          found = PresenceScope.maybeOf(context);
          return const SizedBox();
        },
      ),
    );
    expect(found, isNull);

    await tester.pumpWidget(
      PresenceScope(
        engine: engine,
        child: Builder(
          builder: (context) {
            builds++;
            found = PresenceScope.maybeOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(found, same(engine));
    engine.event(PresenceEvent.unlock);
    await run(tester, 300);
    expect(builds, 1);
  });

  test('the loop parameter traces the glass', () {
    const geometry = GlowGeometry(Size(400, 800), 40);
    expect(geometry.loopOf(const Offset(200, 800)), closeTo(0, 1e-9));
    expect(geometry.loopOf(const Offset(400, 400)), closeTo(0.25, 1e-9));
    expect(geometry.loopOf(const Offset(200, 0)), closeTo(0.5, 1e-9));
    expect(geometry.loopOf(const Offset(0, 400)), closeTo(0.75, 1e-9));
    for (var u = 0.0; u < 1; u += 0.037) {
      final point = geometry.pointAt(u);
      expect(geometry.loopOf(point), closeTo(u, 1e-6), reason: 'u = $u');
    }
  });
}
