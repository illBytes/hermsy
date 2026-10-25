import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/voice/spoken_text.dart';

void main() {
  group('ending a call', () {
    test('the hang-up marker is never spoken, however it is split', () {
      final filter = EndMarkerFilter();
      final spoken = StringBuffer();
      for (final delta in [
        'Sounds good. Bye',
        ' for now! [[',
        'END_',
        'CALL]]',
      ]) {
        spoken.write(filter.add(delta));
      }
      spoken.write(filter.flush());
      expect(spoken.toString(), 'Sounds good. Bye for now! ');
      expect(filter.hangUp, isTrue);
      expect(filter.shown.trim(), 'Sounds good. Bye for now!');
    });

    test('brackets that are not the marker are spoken in the end', () {
      final filter = EndMarkerFilter();
      final first = filter.add('See [[');
      expect(first, 'See ', reason: 'held back: could be the marker');
      expect(filter.add('this]]'), '[[this]]');
      expect(filter.hangUp, isFalse);
      expect(withoutEndMarker('Bye! [[END_CALL]]'), 'Bye!');
    });

    test('a plain goodbye ends the call; a goodbye inside more does not', () {
      for (final bye in [
        'Okay bye',
        'okay, bye.',
        'Bye bye, Hermsy!',
        'Goodbye',
        'Thanks, talk to you later.',
        'Alright, see you soon',
        'bye-bye',
        // Whatever you named your agent.
        'Okay bye, Frank',
        'Thanks, see you later Ada',
      ]) {
        expect(isGoodbye(bye), isTrue, reason: bye);
      }
      for (final more in [
        'Say bye to Ada for me',
        'Okay, what is next',
        'Book it, then bye',
        'Byeongcheol called',
      ]) {
        expect(isGoodbye(more), isFalse, reason: more);
      }
    });

    test('a wrap-up answered with a farewell ends the call', () {
      for (final done in [
        'Nothing for now',
        'No, that\'s all.',
        "I'm good, thanks",
        'Nope, nothing else',
        'That will be all, Hermsy',
        'Okay bye',
      ]) {
        expect(isClosing(done), isTrue, reason: done);
      }
      for (final more in [
        'Nothing urgent, but remind me at five',
        'No, the other one',
        "I'm good at this",
      ]) {
        expect(isClosing(more), isFalse, reason: more);
      }
      expect(isFarewell('Sounds good. Talk soon.'), isTrue);
      expect(isFarewell('Okay. Have a great morning, Alex!'), isTrue);
      expect(isFarewell('Take care.'), isTrue);
      expect(isFarewell('Talk soon about the quotes, then?'), isFalse);
      expect(isFarewell('Your scan is at three.'), isFalse);
    });
  });

  group('money for Kokoro', () {
    test('amounts are said the way people say them', () {
      expect(sayMoney(r'It costs $100.'), 'It costs 100 dollars.');
      expect(sayMoney(r'Just $1'), 'Just 1 dollar');
      expect(sayMoney(r'$1.50 each'), '1 dollar and 50 cents each');
      expect(sayMoney(r'$19.99'), '19 dollars and 99 cents');
      expect(sayMoney(r'$3.00'), '3 dollars');
      expect(sayMoney(r'$1,250.75 total'), '1250 dollars and 75 cents total');
      expect(sayMoney(r'raised $2.5M'), 'raised 2.5 million dollars');
      expect(sayMoney(r'$40k a year'), '40 thousand dollars a year');
      expect(sayMoney(r'$5 billion'), '5 billion dollars');
      expect(sayMoney('£20 and €5'), '20 pounds and 5 euros');
      expect(sayMoney('₦50,000 rent'), '50000 naira rent');
      expect(sayMoney(r'$5 more'), '5 dollars more');
      expect(sayMoney('No money here: 100%'), 'No money here: 100%');
    });
  });
}
