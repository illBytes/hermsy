import 'dart:math' as math;

/// Turns a streamed reply into what Kokoro says: whole sentences, released
/// as soon as each one ends, with Markdown, links and code taken out.
class SentenceBuffer {
  SentenceBuffer({this.maxWords = 20, this.firstMaxWords = 10});

  /// A run-on is released after this many words even without a full stop,
  /// so a long sentence does not keep the speaker silent.
  final int maxWords;

  /// The first chunk of a reply is shorter, and may end at a comma, so
  /// Frank starts talking sooner.
  final int firstMaxWords;

  var _released = 0;

  final _text = StringBuffer();
  var _inCode = false;
  var _saidCode = false;

  /// Adds [delta] and returns the sentences it completed, ready to speak.
  List<String> add(String delta) {
    _text.write(delta);
    return _release(final_: false);
  }

  /// The rest, once the reply is done.
  List<String> flush() => _release(final_: true);

  List<String> _release({required bool final_}) {
    final out = <String>[];
    var rest = _text.toString();
    while (true) {
      // A fenced code block is shown, not read: one short line stands in.
      if (_inCode) {
        final close = rest.indexOf('```');
        if (close < 0) {
          if (final_) {
            rest = '';
          }
          break;
        }
        rest = rest.substring(close + 3);
        _inCode = false;
        continue;
      }
      final fence = rest.indexOf('```');
      final end = _sentenceEnd(rest, final_: final_);
      if (fence >= 0 && (end < 0 || fence < end)) {
        final before = speakable(rest.substring(0, fence));
        if (before.isNotEmpty) {
          out.add(before);
        }
        if (!_saidCode) {
          out.add("I've put the code on your screen.");
          _saidCode = true;
        }
        rest = rest.substring(fence + 3);
        _inCode = true;
        continue;
      }
      if (end < 0) {
        break;
      }
      final sentence = speakable(rest.substring(0, end));
      if (sentence.isNotEmpty) {
        out.add(sentence);
        _released++;
      }
      rest = rest.substring(end);
    }
    _text
      ..clear()
      ..write(rest);
    return out;
  }

  /// Where the first sentence in [text] ends, or -1 if it has not yet.
  /// A stop only counts once the next character is whitespace, so "3.5"
  /// and a stop still arriving are never split; [final_] ends the text.
  int _sentenceEnd(String text, {required bool final_}) {
    final first = _released == 0;
    final limit = first ? firstMaxWords : maxWords;
    int? best;
    void consider(int at) => best = best == null ? at : math.min(best!, at);
    for (final match in _stop.allMatches(text)) {
      final mark = match[1];
      if (mark == '.' &&
          _abbreviation.hasMatch(text.substring(0, match.start))) {
        continue;
      }
      consider(match.end);
      break;
    }
    if (first) {
      // "Sure, the quotes are due today" can start at "Sure, the quotes".
      for (final comma in RegExp(r',\s+').allMatches(text)) {
        if (_wordCount(text.substring(0, comma.end)) >= 4) {
          consider(comma.end);
          break;
        }
      }
    }
    final words = RegExp(r'\S+\s+').allMatches(text).toList();
    if (words.length >= limit) {
      consider(words[limit - 1].end);
    }
    if (best != null) {
      return best!;
    }
    return final_ && text.trim().isNotEmpty ? text.length : -1;
  }

  static int _wordCount(String text) => RegExp(r'\S+').allMatches(text).length;

  static final _stop = RegExp(
    r'([.!?…]+)["”’)\]]*\s+|\n\s*\n|\n(?=\s*(?:[-*•]|\d+[.)])\s)',
  );

  /// "e.g.", "U.S.", "Mr.": a full stop that does not end the sentence.
  static final _abbreviation = RegExp(
    r'(?:\b[A-Za-z]|\b(?:Mr|Mrs|Ms|Dr|St|vs|etc|approx|No))$',
  );
}

/// [text] as it should sound: no Markdown marks, links read as their label,
/// bare URLs and emoji dropped, whitespace tidied.
String speakable(String text) {
  var out = text
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'https?://\S+'), '')
      .replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m[1]!)
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*([-*+•]|\d+[.)])\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\*\*|__|~~|\*|(?<!\w)_|_(?!\w)'), '')
      .replaceAll(RegExp(r'^\s*\|.*\|\s*$', multiLine: true), '')
      .replaceAll(
        RegExp(
          r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]',
          unicode: true,
        ),
        '',
      );
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  // A chunk of punctuation alone says nothing.
  return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(out) ? out : '';
}

/// What Frank asks of Hermes for the length of a call.
const callSystemMessage =
    'You are on a live voice call with the user. Your reply is spoken aloud '
    'by text-to-speech. Answer in short, natural, conversational sentences. '
    'Do not use Markdown, code blocks, tables, lists, links or emoji unless '
    'the user asks for them. Keep most answers to a few sentences. '
    'When the conversation is over, reply with one short farewell and end '
    'your reply with $callEndMarker so the call hangs up. It is over when '
    'the user says goodbye, says they are done, or answers "nothing" or '
    '"that\'s all" when you ask if there is anything else; and whenever '
    'your own reply is a farewell such as "talk soon" or "have a good day". '
    'Never write $callEndMarker otherwise.';

/// Ends a reply when Hermes hangs up the call. Never spoken or shown.
const callEndMarker = '[[END_CALL]]';

/// [text] without [callEndMarker].
String withoutEndMarker(String text) => text.contains(callEndMarker)
    ? text.replaceAll(callEndMarker, '').trimRight()
    : text;

/// Takes Hermes's hang-up marker out of a reply as it streams. A tail
/// that may be the start of the marker is held back until the next delta
/// shows what it is, so no part of it is ever spoken.
class EndMarkerFilter {
  var _raw = '';
  var _given = 0;

  /// The reply asked to hang up.
  bool get hangUp => _raw.contains(callEndMarker);

  /// The reply so far, without the marker, as far as it has been given out.
  String shown = '';

  /// The new text in [delta] that is safe to speak.
  String add(String delta) {
    _raw += delta;
    final cleaned = _raw.replaceAll(callEndMarker, '');
    var safe = cleaned.length;
    for (var k = callEndMarker.length - 1; k > 0; k--) {
      if (cleaned.endsWith(callEndMarker.substring(0, k))) {
        safe = cleaned.length - k;
        break;
      }
    }
    return _give(cleaned, safe);
  }

  /// Whatever was held back, once the reply is done.
  String flush() {
    final cleaned = withoutEndMarker(_raw);
    return _give(cleaned, cleaned.length);
  }

  String _give(String cleaned, int upTo) {
    if (upTo <= _given) {
      return '';
    }
    final fresh = cleaned.substring(_given, upTo);
    _given = upTo;
    shown = cleaned.substring(0, upTo);
    return fresh;
  }
}

/// True when [heard] closes the conversation without saying goodbye:
/// "nothing for now", "no, that's all", "I'm good, thanks".
bool isClosing(String heard) =>
    isGoodbye(heard) || _closing.hasMatch(heard.trim());

final _closing = RegExp(
  r"^(?:(?:no|nope|nah|okay|ok|alright|all right|thanks|thank you)[\s,.!]*)*"
  r"(?:nothing(?: else)?(?: for now| right now| at the moment)?|"
  r"not (?:really|right now|for now)|"
  r"that'?s (?:all|it|everything)(?: for now)?|that will be all|"
  r"i'?m (?:good|fine|done|all set)(?: for now)?|we'?re (?:good|done)|"
  r"all good|no thanks|no thank you|no more)"
  r"[\s,.!]*(?:thanks|thank you)?[\s,.!]*(?:\p{L}+)?[\s,.!]*$",
  caseSensitive: false,
  unicode: true,
);

/// True when [reply] ends as a farewell ("Sounds good. Talk soon.").
bool isFarewell(String reply) => _farewell.hasMatch(reply.trim());

final _farewell = RegExp(
  r"(?:talk (?:to you )?(?:soon|later)|bye(?:[\s-]?bye)?|goodbye|"
  r"take care|see you(?: soon| later)?|catch you later|until next time|"
  r"have a (?:great|good|nice|lovely|wonderful) "
  r"(?:day|morning|afternoon|evening|night|one|weekend|week))"
  r"[\s,.!]*(?:\p{L}+)?[\s.!]*$",
  caseSensitive: false,
  unicode: true,
);

/// True when [heard] is only a goodbye ("okay bye", "bye bye, Frank" with
/// whatever name you gave your agent,
/// "talk to you later"): the call can end after Frank answers, even if
/// Hermes forgets to hang up.
bool isGoodbye(String heard) => _goodbye.hasMatch(heard.trim());

final _goodbye = RegExp(
  r'^(?:(?:ok(?:ay)?|alright|all right|thanks|thank you|great|cool|perfect)'
  r'[\s,.!]*)*'
  r'(?:bye(?:[\s-]?bye)?|good\s?bye|see you(?: later| soon)?|'
  r'talk (?:to you )?(?:later|soon)|later)'
  r'[\s,.!]*(?:\p{L}+)?[\s,.!]*$',
  caseSensitive: false,
  unicode: true,
);

/// When Frank fills a silence while Hermes works.
enum FillerKind {
  /// No words yet, 1.5 s after you finish.
  start,

  /// A tool has been running for 2 s.
  tool,

  /// Still nothing after 8 s.
  long,
}

/// Said after a long quiet in a call, when nothing has been heard.
const callCheckIn = 'Are you still there?';

/// Said when the check-in gets no answer, before hanging up.
const callQuietGoodbye = "I'll hang up for now. Call me any time.";

/// Short lines Frank picks from, at random and never the same one twice in
/// a row, so a call does not sound like a recording.
const callFillers = <FillerKind, List<String>>{
  FillerKind.start: [
    'One sec.',
    'Okay, give me a moment.',
    'Hmm, let me see.',
    'Sure, one moment.',
    'Let me think about that.',
    'Right, on it.',
    'Good question. Give me a second.',
    'Alright, let me look.',
  ],
  FillerKind.tool: [
    'Let me check that.',
    'Looking that up now.',
    'Let me pull that up.',
    'Checking on that.',
    'Give me a sec while I look.',
  ],
  FillerKind.long: [
    'Still on it.',
    'Almost there.',
    'Bear with me, this one is taking a little longer.',
    'Still working on it.',
  ],
};

/// Money as words Kokoro says properly. Left alone, it reads the symbol
/// where it stands: "$100" comes out "dollar hundred". OpenAI and
/// ElevenLabs do this themselves.
String sayMoney(String text) => text.replaceAllMapped(_money, (match) {
  final currency = _currencies[match.group(1)]!;
  final whole = match.group(2)!.replaceAll(',', '');
  final fraction = match.group(3);
  final scale = _scales[match.group(4)?.toLowerCase()];
  final buffer = StringBuffer();
  if (scale != null) {
    // "$2.5M": 2.5 million dollars.
    buffer.write('${fraction == null ? whole : '$whole.$fraction'} $scale ');
    buffer.write(currency.many);
    return buffer.toString();
  }
  final units = int.tryParse(whole) ?? 0;
  buffer.write('$whole ${units == 1 ? currency.one : currency.many}');
  if (fraction != null && fraction.length == 2) {
    final cents = int.parse(fraction);
    if (cents > 0) {
      buffer.write(
        ' and $cents ${cents == 1 ? currency.minorOne : currency.minor}',
      );
    }
  } else if (fraction != null) {
    return '$whole.$fraction ${currency.many}';
  }
  return buffer.toString();
});

final _money = RegExp(
  r'([$£€₦¥])\s?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d+))?'
  r'(?:\s?(k|m|bn|b|thousand|million|billion|trillion)\b)?',
  caseSensitive: false,
);

const _scales = {
  'k': 'thousand',
  'thousand': 'thousand',
  'm': 'million',
  'million': 'million',
  'b': 'billion',
  'bn': 'billion',
  'billion': 'billion',
  'trillion': 'trillion',
};

const _currencies = {
  r'$': (one: 'dollar', many: 'dollars', minorOne: 'cent', minor: 'cents'),
  '£': (one: 'pound', many: 'pounds', minorOne: 'penny', minor: 'pence'),
  '€': (one: 'euro', many: 'euros', minorOne: 'cent', minor: 'cents'),
  '₦': (one: 'naira', many: 'naira', minorOne: 'kobo', minor: 'kobo'),
  '¥': (one: 'yen', many: 'yen', minorOne: 'sen', minor: 'sen'),
};
