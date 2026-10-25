import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/voice/quiet_watch.dart';

void main() {
  group('QuietWatch', () {
    late List<String> said;
    late QuietWatch watch;

    setUp(() {
      said = [];
      watch = QuietWatch(
        checkIn: const Duration(minutes: 2),
        giveUp: const Duration(seconds: 20),
        onCheckIn: () => said.add('still there?'),
        onGiveUp: () => said.add('bye'),
      );
    });

    testWidgets('a long quiet checks in, then hangs up', (tester) async {
      watch.listening();
      await tester.pump(const Duration(seconds: 119));
      expect(said, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(said, ['still there?']);
      // Frank says it, then listens again: the shorter wait.
      watch.pause();
      await tester.pump(const Duration(seconds: 2));
      watch.listening();
      await tester.pump(const Duration(seconds: 19));
      expect(said, ['still there?']);
      await tester.pump(const Duration(seconds: 1));
      expect(said, ['still there?', 'bye']);
    });

    testWidgets('an answer to the check-in starts it over', (tester) async {
      watch.listening();
      await tester.pump(const Duration(minutes: 2));
      expect(watch.asked, isTrue);
      watch.heardYou();
      watch.listening();
      await tester.pump(const Duration(seconds: 30));
      expect(said, ['still there?'], reason: 'back to the full two minutes');
      await tester.pump(const Duration(minutes: 2));
      expect(said, ['still there?', 'still there?']);
    });

    testWidgets('thinking and speaking do not count', (tester) async {
      watch.listening();
      await tester.pump(const Duration(seconds: 90));
      // You spoke; Hermes takes its time.
      watch.heardYou();
      watch.pause();
      await tester.pump(const Duration(minutes: 5));
      expect(said, isEmpty);
      watch.listening();
      await tester.pump(const Duration(seconds: 90));
      expect(said, isEmpty, reason: 'the count starts again when listening');
      watch.pause();
    });
  });
}
