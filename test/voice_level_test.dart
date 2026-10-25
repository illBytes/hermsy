import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/services/frank_haptics.dart';
import 'package:hermes_app/services/voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('levelFromDecibels', () {
    test('silence is dark, loud speech is full', () {
      expect(levelFromDecibels(-160), 0);
      expect(levelFromDecibels(-52), 0);
      expect(levelFromDecibels(-51.5), 0, reason: 'under the noise gate');
      expect(levelFromDecibels(-6), 1);
      expect(levelFromDecibels(0), 1);
    });

    test('rises steadily through the speaking range', () {
      final quiet = levelFromDecibels(-40);
      final normal = levelFromDecibels(-25);
      final loud = levelFromDecibels(-12);
      expect(quiet, greaterThan(0));
      expect(normal, greaterThan(quiet));
      expect(loud, greaterThan(normal));
      expect(loud, lessThan(1));
    });

    test('ignores readings that are not numbers', () {
      expect(levelFromDecibels(double.negativeInfinity), 0);
      expect(levelFromDecibels(double.nan), 0);
    });
  });

  group('SoundLevelNormalizer', () {
    test('Android room hiss stays dark and speech fills the range', () {
      final normalizer = SoundLevelNormalizer();
      const hiss = [-2.1, -1.6, -2.0, -1.2, -2.1, -1.8, -1.5, -2.1];
      var loudestHiss = 0.0;
      for (var i = 0; i < 40; i++) {
        final level = normalizer.normalize(hiss[i % hiss.length]);
        if (level > loudestHiss) {
          loudestHiss = level;
        }
      }
      expect(loudestHiss, lessThan(0.2));

      final speech = normalizer.normalize(8);
      expect(speech, greaterThan(0.8));
      expect(normalizer.normalize(4), inInclusiveRange(0.3, speech));
      expect(normalizer.normalize(-2.1), 0, reason: 'back to silence');
    });

    test('iOS dBFS works with a wider minimum span', () {
      final normalizer = SoundLevelNormalizer.dbfs();
      const room = [-56.0, -53.0, -55.0, -51.0, -54.0, -57.0];
      var loudestRoom = 0.0;
      for (var i = 0; i < 30; i++) {
        final level = normalizer.normalize(room[i % room.length]);
        if (level > loudestRoom) {
          loudestRoom = level;
        }
      }
      expect(loudestRoom, lessThan(0.2));
      expect(normalizer.normalize(-18), greaterThan(0.8));
      expect(normalizer.normalize(double.negativeInfinity), 0);
    });

    test('a loud first reading does not leave later speech stuck low', () {
      final normalizer = SoundLevelNormalizer();
      normalizer.normalize(9);
      for (var i = 0; i < 8; i++) {
        normalizer.normalize(-2);
      }
      expect(normalizer.normalize(7), greaterThan(0.6));
    });

    test('a quieter phone is learned, and reset forgets it', () {
      final fresh = SoundLevelNormalizer().normalize(0);
      final normalizer = SoundLevelNormalizer();
      for (var i = 0; i < 10; i++) {
        normalizer.normalize(-8);
      }
      expect(normalizer.normalize(-6), lessThan(0.2), reason: 'still hiss');
      expect(normalizer.normalize(0), greaterThan(fresh));
      normalizer.reset();
      expect(normalizer.normalize(0), fresh);
    });
  });

  group('FrankHaptics', () {
    late List<String> buzzes;

    setUp(() {
      buzzes = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          buzzes.add(call.arguments as String);
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('tool taps are spaced at least 600ms apart', () {
      var now = DateTime(2026, 10, 3, 12);
      final haptics = FrankHaptics(AppSettings(), clock: () => now);
      haptics.tool();
      now = now.add(const Duration(milliseconds: 200));
      haptics.tool();
      now = now.add(const Duration(milliseconds: 399));
      haptics.tool();
      expect(buzzes, hasLength(1));
      now = now.add(const Duration(milliseconds: 1));
      haptics.tool();
      expect(buzzes, hasLength(2));
      expect(buzzes, everyElement('HapticFeedbackType.selectionClick'));
    });

    test('muted keeps tool and done quiet but not voice gestures', () {
      final haptics = FrankHaptics(AppSettings())..muted = true;
      haptics
        ..tool()
        ..done();
      expect(buzzes, isEmpty);
      haptics
        ..listenSend()
        ..listenCancel();
      expect(buzzes, hasLength(2));
      haptics
        ..muted = false
        ..done();
      expect(buzzes.last, 'HapticFeedbackType.mediumImpact');
    });

    test('the Haptics setting silences everything', () {
      final settings = AppSettings()..haptics = false;
      FrankHaptics(settings)
        ..tool()
        ..done()
        ..listenStart()
        ..send();
      expect(buzzes, isEmpty);
    });
  });
}
