import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/voice/call_chimes.dart';
import 'package:hermes_app/voice/turn_hold.dart';

void main() {
  group('TurnHold', () {
    late List<String> turns;
    late TurnHold hold;

    setUp(() {
      turns = [];
      hold = TurnHold(pause: const Duration(seconds: 1), onTurn: turns.add);
    });

    testWidgets('a turn goes once you have paused long enough', (tester) async {
      hold.heard('What is on today');
      await tester.pump(const Duration(milliseconds: 900));
      expect(turns, isEmpty, reason: 'still within the pause');
      await tester.pump(const Duration(milliseconds: 200));
      expect(turns, ['What is on today']);
    });

    testWidgets('talking again within the pause makes it one turn', (
      tester,
    ) async {
      hold.heard('What is on today');
      await tester.pump(const Duration(milliseconds: 600));
      hold.speechStarted();
      // However long the second stretch takes.
      await tester.pump(const Duration(seconds: 3));
      expect(turns, isEmpty);
      hold
        ..speechEnded()
        ..heard('and tomorrow?');
      await tester.pump(const Duration(seconds: 1));
      expect(turns, ['What is on today and tomorrow?']);
    });

    testWidgets('a noise that says nothing neither sends nor holds forever', (
      tester,
    ) async {
      hold
        ..speechStarted()
        ..speechEnded()
        ..heard('');
      await tester.pump(const Duration(seconds: 5));
      expect(turns, isEmpty);

      hold.heard('Hello');
      await tester.pump(const Duration(milliseconds: 500));
      hold
        ..speechStarted()
        ..speechEnded(); // a cough, no words
      await tester.pump(const Duration(seconds: 1));
      expect(turns, ['Hello']);
    });

    testWidgets('hanging up drops what was held', (tester) async {
      hold.heard('Never mind');
      hold.clear();
      await tester.pump(const Duration(seconds: 2));
      expect(turns, isEmpty);
    });
  });

  test('the chimes are short, quiet, and end in silence', () {
    for (final chime in [readyChime, endChime]) {
      final heard = chimeHeard(chime);
      expect(heard, greaterThan(const Duration(milliseconds: 300)));
      expect(heard, lessThan(const Duration(milliseconds: 1200)));
      expect(chimeLength(chime), lessThan(const Duration(seconds: 2)));
      final peak = chime.fold<double>(0, (m, s) => math.max(m, s.abs()));
      expect(peak, inInclusiveRange(0.1, 0.4));
      expect(chime.first.abs(), lessThan(0.01));
      expect(chime.last.abs(), lessThan(0.001));
    }
  });
}
