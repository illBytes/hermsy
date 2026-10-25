import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/relay_client.dart';
import '../state/chat_controller.dart';
import 'audio_route.dart';
import 'call_chimes.dart';
import 'call_service.dart';
import 'mic_capture.dart';
import 'on_device_voice.dart';
import 'quiet_watch.dart';
import 'speech_player.dart';
import 'speech_source.dart';
import 'speech_worker.dart';
import 'turn_hold.dart';
import 'spoken_text.dart';

enum CallPhase { starting, listening, thinking, speaking, ended }

/// A live voice call with Frank, all on the phone except Hermes itself.
///
/// The mic streams into Silero VAD; each finished turn is transcribed by
/// Parakeet and sent to Hermes through [chat], so the call is saved in the
/// thread. The streamed reply is cut into sentences, each spoken by Kokoro
/// as soon as it is ready while the next one is generated. Talking over
/// Frank stops it (barge-in), and short fillers cover slow starts and tools.
class CallController extends ChangeNotifier {
  CallController({
    required this.chat,
    required this.voice,
    this.voiceId = defaultKokoroVoice,
    this.speed = 1.0,
    this.cloud,
    this.fallback = true,
    this.pause = const Duration(seconds: 1),
    this.quietCheckIn = const Duration(minutes: 2),
    this.quietGiveUp = const Duration(seconds: 20),
    SpeechPlayer? player,
    Future<MicCapture> Function()? openMic,
  }) : _player = player ?? SpeechPlayer(),
       _openMic = openMic ?? (() => MicCapture.start(call: true));

  final ChatController chat;
  final OnDeviceVoice voice;
  final int voiceId;
  final double speed;

  /// A cloud voice to speak with instead of Kokoro, which it falls back to.
  final ({RelayClient relay, String provider, String voice})? cloud;

  /// Finish in Kokoro's voice if the cloud voice fails.
  final bool fallback;

  /// How long you can stop mid-thought before Frank answers, on top of the
  /// short silence that ends a stretch of speech.
  final Duration pause;

  /// How long Frank listens to silence before asking whether you are still
  /// there, and then how long it waits for an answer before hanging up.
  final Duration quietCheckIn;
  final Duration quietGiveUp;

  /// Set when the cloud voice failed and Kokoro took over, for the screen.
  String? fallbackReason;

  /// Set when a sentence could not be spoken at all (cloud failed with no
  /// fallback), for the screen.
  String? speechError;
  final SpeechPlayer _player;
  final Future<MicCapture> Function() _openMic;

  CallPhase phase = CallPhase.starting;
  String? error;

  /// What you said last, as Parakeet heard it.
  String heard = '';

  /// Frank's reply so far, as text.
  String reply = '';

  /// What Hermes is doing ("Searching the web…"), shown, never spoken.
  String? activity;
  bool muted = false;
  bool captions = true;

  /// Mic loudness while listening, Frank's while speaking (0–1).
  final level = ValueNotifier<double>(0);

  SpeechWorker? _ears;
  SpeechSource? _source;
  MicCapture? _mic;
  final _subscriptions = <StreamSubscription<Object?>>[];
  var _sentences = SentenceBuffer();
  var _turn = 0;
  var _pendingSpeech = 0;
  var _heardReply = false;
  var _ended = false;
  Timer? _firstFiller;
  Timer? _secondFiller;
  Timer? _toolFiller;
  var _saidToolFiller = false;
  Future<void> _speaking = Future.value();
  final _fillers = <String, ({Float32List samples, int sampleRate})>{};
  final _random = math.Random();
  String? _lastFiller;

  /// What Frank said this turn, to tell its own echo from your voice.
  final _spoken = <String>[];

  /// What you say, gathered until you pause for [pause].
  late final _hold = TurnHold(
    pause: pause,
    onTurn: (text) {
      if (!_ended) {
        unawaited(_userSaid(text));
      }
    },
  );

  /// A call left alone (phone down, out of range) checks in, then ends.
  late final _quiet = QuietWatch(
    checkIn: quietCheckIn,
    giveUp: quietGiveUp,
    onCheckIn: () => _sayAlone(callCheckIn),
    onGiveUp: () {
      _sayAlone(callQuietGoodbye);
      // Hang up once it is said, unless you speak first.
      _hangUpAfterReply = true;
      _replyDone = true;
    },
  );

  /// The mic is not listened to until then: the ready chime would be heard
  /// as you.
  DateTime? _deafUntil;

  /// The call reached listening, so it ends with a chime.
  var _wasLive = false;

  /// Hermes said goodbye (or you did): hang up once Frank has finished
  /// saying its last words, unless you speak first.
  var _hangUpAfterReply = false;

  /// The call ended without the screen's End button (Frank hung up after a
  /// goodbye, or you ended it from the notification), so the screen closes.
  bool endedOffScreen = false;

  /// This turn's reply, with Hermes's hang-up marker taken out.
  var _reply = EndMarkerFilter();

  /// Hermes finished this turn's reply.
  var _replyDone = false;

  /// What you said this turn wrapped up ("nothing for now"): if Frank's
  /// reply is a farewell, the call is over.
  var _closingTurn = false;

  Future<void> start() async {
    chat.inCall = true;
    try {
      Future<SpeechSource> kokoro() async =>
          KokoroSpeech(await voice.mouths(), voice: voiceId, speed: speed);
      final cloud = this.cloud;
      final ready = await Future.wait<Object>([
        voice.ears(),
        // A cloud voice needs no Kokoro unless it fails.
        cloud == null
            ? kokoro()
            : Future.value(
                CloudSpeech(
                  relay: cloud.relay,
                  provider: cloud.provider,
                  voice: cloud.voice,
                  speed: speed,
                  fallback: fallback ? kokoro : null,
                  onFallback: (reason) {
                    fallbackReason = reason;
                    notifyListeners();
                  },
                ),
              ),
      ]);
      if (_ended) {
        return;
      }
      _ears = ready[0] as SpeechWorker;
      _source = ready[1] as SpeechSource;
      await _ears!.resetListening();
      // The player first: setting it up touches Android's audio settings,
      // which would knock a headset off a route taken before it.
      await _player.prepare();
      // A headset if one is connected, else the loudspeaker. This waits
      // until the headset's call link is live, so the chime and Frank are
      // heard in it, and the mic, opened next, listens on it.
      await AudioRoute.begin(AudioPurpose.call);
      final mic = _mic = await _openMic();
      if (_ended) {
        // Hung up while the mic opened: end() ran before there was a
        // route or a mic to let go of.
        await mic.stop();
        await AudioRoute.end(AudioPurpose.call);
        return;
      }
      _subscriptions
        ..add(
          mic.samples.listen((samples) {
            final deaf = _deafUntil;
            if (deaf != null && DateTime.now().isBefore(deaf)) {
              return;
            }
            if (!muted) {
              _ears?.listen(samples);
            }
          }),
        )
        ..add(
          mic.levels.listen((value) {
            if (phase == CallPhase.listening && !muted) {
              level.value = value;
            }
          }),
        )
        ..add(_ears!.events.listen(_onEar))
        ..add(chat.turnEvents.listen(_onTurn));
      // The chime says "talk now"; Frank listens from its last note.
      final chime = chimeHeard(readyChime);
      _deafUntil = DateTime.now().add(
        chime + const Duration(milliseconds: 150),
      );
      _wasLive = true;
      phase = CallPhase.listening;
      notifyListeners();
      // From here the call goes on off screen and with the phone locked.
      unawaited(
        CallService.start(
          title: chat.conversationTitle ?? 'Hermsy',
          onEnd: () {
            endedOffScreen = true;
            unawaited(end());
          },
        ),
      );
      unawaited(_player.enqueue(readyChime, chimeSampleRate));
      await Future<void>.delayed(chime);
      if (_ended) {
        return;
      }
      _player.onSpeaking = (_) => _settle();
      _quiet.listening();
      unawaited(_prepareFillers());
    } catch (err) {
      error = '$err';
      await end();
    }
  }

  /// Renders the filler lines in the background: one of each kind first,
  /// then the rest, only while Frank is listening so a reply is never kept
  /// waiting behind a filler.
  Future<void> _prepareFillers() async {
    List<String> shuffled(List<String> lines) =>
        List.of(lines)..shuffle(_random);
    final pools = {
      for (final entry in callFillers.entries) entry.key: shuffled(entry.value),
    };
    final order = [
      for (final pool in pools.values) pool.first,
      for (final pool in pools.values) ...pool.skip(1),
    ];
    for (final line in order) {
      while (!_ended && phase != CallPhase.listening) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      if (_ended) {
        return;
      }
      try {
        _fillers[line] = await _source!.speak(line);
      } catch (_) {
        return;
      }
    }
  }

  /// A ready filler of [kind], not the one just said.
  ({Float32List samples, int sampleRate})? _pickFiller(FillerKind kind) {
    final ready = callFillers[kind]!
        .where((line) => _fillers.containsKey(line) && line != _lastFiller)
        .toList();
    if (ready.isEmpty) {
      return null;
    }
    final line = ready[_random.nextInt(ready.length)];
    _lastFiller = line;
    return _fillers[line];
  }

  void _onEar(EarEvent event) {
    if (_ended) {
      return;
    }
    switch (event) {
      case SpeechStarted():
        if (phase == CallPhase.speaking) {
          _bargeIn();
        } else {
          // Not Frank's own echo: it is not speaking.
          _quiet.heardYou();
        }
        // Still talking: keep listening.
        _hold.speechStarted();
      case SpeechEnded():
        _hold.speechEnded();
        if (phase == CallPhase.listening) {
          // A cough or a door: count the quiet again.
          _quiet.listening();
        }
      case Heard(:final text):
        if (_isEcho(text)) {
          return;
        }
        _quiet.heardYou();
        _hold.heard(text);
        if (_hold.text.isNotEmpty) {
          heard = _hold.text;
          notifyListeners();
        }
    }
  }

  /// You started talking over Frank: it stops at once and listens.
  void _bargeIn() {
    _turn++;
    // Still talking: not goodbye after all.
    _hangUpAfterReply = false;
    _cancelFillers();
    _pendingSpeech = 0;
    unawaited(_player.stop());
    if (chat.sending) {
      unawaited(chat.stopReply());
    }
    _settle();
  }

  Future<void> _userSaid(String text) async {
    if (chat.sending) {
      // A new turn replaces the reply still coming in.
      _turn++;
      await chat.stopReply();
    }
    await _player.stop();
    final turn = ++_turn;
    heard = text;
    reply = '';
    _reply = EndMarkerFilter();
    _replyDone = false;
    // "Okay, bye": end after Frank answers, even if Hermes forgets to.
    _hangUpAfterReply = isGoodbye(text);
    _closingTurn = isClosing(text);
    activity = null;
    _sentences = SentenceBuffer();
    _spoken.clear();
    _pendingSpeech = 0;
    _heardReply = false;
    _saidToolFiller = false;
    _quiet.pause();
    phase = CallPhase.thinking;
    notifyListeners();
    _firstFiller = Timer(
      const Duration(milliseconds: 1500),
      () => _filler(FillerKind.start, turn),
    );
    _secondFiller = Timer(
      const Duration(seconds: 8),
      () => _filler(FillerKind.long, turn),
    );
    await chat.send(text, systemMessage: callSystemMessage);
  }

  void _onTurn(TurnEvent event) {
    if (_ended || phase == CallPhase.starting) {
      return;
    }
    final turn = _turn;
    if (event.text case final delta?) {
      if (!_heardReply) {
        _heardReply = true;
        _cancelFillers();
      }
      for (final sentence in _sentences.add(_speakable(delta))) {
        _say(sentence, turn);
      }
    } else if (event.tool case final tool?) {
      activity = event.toolCompleted ? null : tool;
      _toolFiller?.cancel();
      if (!event.toolCompleted && !_saidToolFiller) {
        // A tool that runs past two seconds gets one spoken "let me check".
        _toolFiller = Timer(const Duration(seconds: 2), () {
          _saidToolFiller = true;
          _filler(FillerKind.tool, turn);
        });
      }
    }
    if (event.done) {
      _replyDone = true;
      _cancelFillers();
      activity = null;
      _sentences.add(_reply.flush());
      reply = _reply.shown;
      if (_closingTurn && isFarewell(reply)) {
        _hangUpAfterReply = true;
      }
      for (final sentence in _sentences.flush()) {
        _say(sentence, turn);
      }
      if (event.error != null && reply.trim().isEmpty) {
        _say('Sorry, that did not work. Could you say it again?', turn);
      }
    }
    _settle();
  }

  /// The part of [delta] that can be spoken (see [EndMarkerFilter]).
  String _speakable(String delta) {
    final fresh = _reply.add(delta);
    reply = _reply.shown;
    if (_reply.hangUp) {
      _hangUpAfterReply = true;
    }
    return fresh;
  }

  /// Speaks [sentence] after the ones before it. Sentences render on the
  /// two speaking workers in turn, so the next one is usually ready before
  /// the current one ends, and they play strictly in order.
  void _say(String sentence, int turn) {
    final source = _source;
    if (turn != _turn || _ended || source == null) {
      return;
    }
    _pendingSpeech++;
    _spoken.add(sentence);
    final watch = Stopwatch()..start();
    final audio = source.speak(sentence);
    final previous = _speaking;
    _speaking = () async {
      try {
        await previous;
        final clip = await audio;
        if (kDebugMode) {
          final seconds = clip.samples.length / clip.sampleRate;
          debugPrint(
            'kokoro: ready ${watch.elapsedMilliseconds} ms after asking, '
            '${(seconds * 1000).round()} ms of speech',
          );
        }
        if (turn == _turn && !_ended) {
          unawaited(
            _player.enqueue(
              trimSilence(clip.samples, clip.sampleRate),
              clip.sampleRate,
            ),
          );
        }
      } catch (error) {
        // The sentence is still on screen; say why it was not spoken.
        if (speechError == null) {
          speechError = '$error';
          notifyListeners();
        }
      } finally {
        if (turn == _turn && _pendingSpeech > 0) {
          _pendingSpeech--;
        }
        _settle();
      }
    }();
  }

  /// Says [line] on Frank's own, without Hermes (the quiet check-in).
  void _sayAlone(String line) {
    if (_ended || phase != CallPhase.listening) {
      return;
    }
    // Only this line counts as Frank's echo now.
    _spoken.clear();
    reply = line;
    _say(line, _turn);
    _settle();
  }

  void _filler(FillerKind kind, int turn) {
    if (turn != _turn || _heardReply || _ended || _player.busy) {
      return;
    }
    final audio = _pickFiller(kind);
    if (audio == null) {
      return;
    }
    unawaited(_player.enqueue(audio.samples, audio.sampleRate));
    _settle();
  }

  void _cancelFillers() {
    _firstFiller?.cancel();
    _secondFiller?.cancel();
    _toolFiller?.cancel();
  }

  /// Picks the phase from what is actually happening.
  void _settle() {
    if (_ended) {
      return;
    }
    final next = _player.busy || _pendingSpeech > 0
        ? CallPhase.speaking
        : chat.sending
        ? CallPhase.thinking
        : CallPhase.listening;
    if (next == CallPhase.listening && _hangUpAfterReply && _replyDone) {
      // The goodbye has been said: hang up, with the falling chime.
      _hangUpAfterReply = false;
      endedOffScreen = true;
      unawaited(end());
      return;
    }
    if (next != phase) {
      phase = next;
      if (next == CallPhase.listening) {
        _quiet.listening();
      } else {
        _quiet.pause();
        level.value = 0;
      }
    }
    notifyListeners();
  }

  /// True when [text] is mostly words Frank just said: its own voice coming
  /// back through the mic, not you.
  bool _isEcho(String text) {
    if (_spoken.isEmpty || phase != CallPhase.speaking) {
      return false;
    }
    final said = _words(_spoken.join(' ')).toSet();
    final heardWords = _words(text);
    if (heardWords.isEmpty) {
      return true;
    }
    final overlap = heardWords.where(said.contains).length;
    return overlap / heardWords.length >= 0.6;
  }

  static List<String> _words(String text) => text
      .toLowerCase()
      .split(RegExp(r"[^a-z0-9']+"))
      .where((word) => word.isNotEmpty)
      .toList();

  /// A tap on the call screen: you are there.
  void _tapped() {
    _quiet.heardYou();
    if (phase == CallPhase.listening) {
      _quiet.listening();
    }
  }

  void toggleMute() {
    _tapped();
    muted = !muted;
    if (muted) {
      level.value = 0;
      unawaited(_ears?.resetListening());
    }
    notifyListeners();
  }

  void toggleCaptions() {
    _tapped();
    captions = !captions;
    notifyListeners();
  }

  /// Hangs up. A reply still streaming finishes as text in the thread.
  Future<void> end() async {
    if (_ended) {
      return;
    }
    _ended = true;
    _turn++;
    _cancelFillers();
    _hold.clear();
    _quiet.pause();
    phase = CallPhase.ended;
    notifyListeners();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    try {
      await _mic?.stop();
    } catch (_) {}
    if (_wasLive) {
      // Hung up: Frank stops mid-word, and the falling chime says so.
      _player.onSpeaking = null;
      await _player.stop();
      await _player.enqueue(endChime, chimeSampleRate);
      await Future<void>.delayed(
        chimeHeard(endChime) + const Duration(milliseconds: 200),
      );
    }
    await _player.dispose();
    await CallService.stop();
    await AudioRoute.end(AudioPurpose.call);
    chat.inCall = false;
    voice.releaseSoon();
  }

  @override
  void dispose() {
    unawaited(end());
    level.dispose();
    super.dispose();
  }
}
