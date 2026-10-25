import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../services/app_settings.dart';
import '../state/assistant_mood.dart';
import '../state/chat_controller.dart';
import '../theme/app_theme.dart';
import 'glow_geometry.dart';
import 'glow_palette.dart';

/// One-shot beats the UI (or the engine itself) fires on top of the mood.
enum PresenceEvent {
  /// A text message left the composer.
  send,

  /// The mic opened. Pass the mic button's global centre as `origin`.
  listenStart,

  /// Voice was discarded (slide-to-cancel, X).
  listenCancel,

  /// Voice was sent for transcription.
  listenSend,

  /// The user stopped a reply.
  stop,

  /// A reply finished (fired by the engine from mood changes).
  done,

  /// Something failed (fired by the engine, or by the lock screen on a wrong
  /// PIN with a softer intensity).
  error,

  /// A tool started (fired by the engine from tool label changes).
  tool,

  /// The app unlocked: the gold welcome sweep.
  unlock,
}

/// States the presence picker's preview can stage on its own engine.
enum PresenceDemo { listening, thinking, tool, replying, speaking, done, error }

/// What the engine follows in a conversation. [PresenceEngine.attach] adapts
/// a [ChatController]; previews and tests can feed their own.
abstract class PresenceFeed implements Listenable {
  AssistantMood get mood;

  /// The live tool line, or null while Frank only thinks or writes.
  String? get toolLabel;

  /// Mic loudness 0–1 while listening.
  ValueListenable<double> get voiceLevel;

  /// The id and current length of the reply being streamed, if any.
  (String, int)? get streamingReply;
}

class _ChatFeed implements PresenceFeed {
  _ChatFeed(this.chat);

  final ChatController chat;

  @override
  AssistantMood get mood => chat.mood;

  @override
  String? get toolLabel => chat.toolLabel;

  @override
  ValueListenable<double> get voiceLevel => chat.voiceLevel;

  @override
  (String, int)? get streamingReply {
    final messages = chat.messages;
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.isAssistant && message.streaming) {
        return (message.id, message.text.length);
      }
    }
    return null;
  }

  @override
  void addListener(VoidCallback listener) => chat.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => chat.removeListener(listener);
}

/// Everything the edge glow painter needs for one frame. The engine mutates
/// it in place; painters only read it. Lengths are logical px.
class GlowFrame {
  double intensity = 0;
  double depth = 0;
  double amp = 0;
  double flow = 0;
  double hue = 0;
  double bias = 0;
  double origin = 0;
  double reveal = 0;
  double front = 0;
  double flare = 0;
  double comet = -1;
  double cometWidth = 0.06;
  double cometGain = 1;
  double twin = 0;
  double cometOnly = 0;
  double ringMix = 0;
  double flash = -1;

  /// Voice ripples: (age, strength) twice.
  final Float64List ripples = Float64List(4);

  /// Four palette stops as r, g, b (0–1).
  Float64List palette = Float64List(12);

  /// How far inward the light can reach right now, before preview scaling.
  /// Smoothed (quick rise, soft fall), so voice onsets never step it.
  double reach = 0;

  /// The most light (Rec.709 luma) the glow may add where reply text sits,
  /// 20dp in from the glass: 0.22, up to 0.35 at listening peaks.
  double readCap = 0.22;

  bool get visible => intensity >= 0.002;
}

/// Drives Frank's whole-screen presence: the edge glow above every route,
/// and the timeline the orb and haptics follow.
///
/// Lives in `_FrankAppState`, mounted with [PresenceScope] in
/// `MaterialApp.builder` so the glow survives sheets, the drawer and routes.
/// The ticker runs only while something is visible; idle is zero frames.
///
/// Haptics stay with [ChatController] and the screens (FrankHaptics), so no
/// beat ever buzzes twice.
class PresenceEngine extends ChangeNotifier {
  PresenceEngine({required this.vsync});

  /// Drives the glow's single ticker.
  final TickerProvider vsync;

  AssistantMood _mood = AssistantMood.idle;
  ChatController? _chat;
  PresenceFeed? _feed;
  AppSettings? _settings;

  /// The mood the glow is heading towards.
  AssistantMood get mood => _mood;

  /// The chat currently feeding the glow, if any.
  ChatController? get chat => _chat;

  /// Settings the glow reads (style, intensity, reduce motion).
  AppSettings? get settings => _settings;

  /// Mic level the glow follows (0–1).
  ValueListenable<double> get level => _feed?.voiceLevel ?? const _Silent();

  /// What the painter draws this frame.
  GlowFrame get frame => _frame;

  /// True while the ticker is producing frames.
  bool get ticking => _ticker?.isActive ?? false;

  /// The last beat played, whether fired by the UI or inferred from the chat.
  PresenceEvent? get lastEvent => _lastEvent;

  /// The style being drawn: an override (previews) or the user's setting.
  PresenceStyle get style =>
      _styleOverride ?? _settings?.presence ?? PresenceStyle.aura;

  /// True when either the OS or Frank's settings ask for calmer motion.
  bool get reduceMotion =>
      _platformReduceMotion || (_settings?.reduceMotion ?? false);

  // ---------------------------------------------------------------- wiring

  /// Follow [chat]'s mood, mic level, streamed text and tool events.
  void attach(ChatController chat) {
    if (identical(_chat, chat)) {
      return;
    }
    follow(_ChatFeed(chat));
    _chat = chat;
  }

  /// Follow any [PresenceFeed]. [attach] wraps a [ChatController] in one.
  void follow(PresenceFeed feed) {
    _unbind();
    _feed = feed;
    _toolLabel = feed.toolLabel;
    final reply = feed.streamingReply;
    _replyId = reply?.$1;
    _replyLength = reply?.$2 ?? 0;
    feed.addListener(_onFeed);
    _onFeed();
  }

  /// Stop following the chat; the glow drains to dark.
  void detach() {
    _unbind();
    _moveTo(AssistantMood.idle, infer: false);
    notifyListeners();
  }

  void _unbind() {
    _feed?.removeListener(_onFeed);
    _feed = null;
    _chat = null;
    _toolLabel = null;
    _replyId = null;
    _replyLength = 0;
  }

  /// Read presence style, glow intensity and reduce motion from [settings].
  void configure(AppSettings settings) {
    _settings = settings;
    _wake();
    notifyListeners();
  }

  /// Draw [style] instead of the user's setting (the picker preview).
  void setStyle(PresenceStyle? style) {
    if (style == _styleOverride) {
      return;
    }
    _styleOverride = style;
    _wake();
  }

  /// The OS "remove animations" switch, read by the glow layer.
  set platformReduceMotion(bool value) {
    if (value == _platformReduceMotion) {
      return;
    }
    _platformReduceMotion = value;
    _wake();
  }

  /// With the keyboard up the bottom edge is hidden behind it, so the glow
  /// stops leaning on it.
  set keyboardVisible(bool value) => _keyboard = value;

  /// The canvas the glow is drawn on, so origins map onto the real glass.
  void updateGeometry(Size size, double radius) {
    _geometry = GlowGeometry(size, radius);
  }

  /// Head towards [mood]. [origin] is a global logical position (for
  /// example the mic button centre) the glow blooms from.
  void setMood(AssistantMood mood, {Offset? origin}) {
    if (mood == _mood) {
      return;
    }
    if (origin != null) {
      _nextOrigin = _geometry.loopOf(origin);
    }
    _moveTo(mood, infer: true);
    notifyListeners();
  }

  /// Fire a one-shot beat. [origin] is a global logical position.
  void event(PresenceEvent event, {Offset? origin, double strength = 1}) {
    final u = origin == null ? null : _geometry.loopOf(origin);
    switch (event) {
      case PresenceEvent.send:
        _cue(AssistantMood.thinking, u ?? _actionOrigin, 1.6);
      case PresenceEvent.listenStart:
        _cue(AssistantMood.listening, u ?? _actionOrigin, 1.6);
      case PresenceEvent.listenSend:
        _cue(AssistantMood.transcribing, u ?? _actionOrigin, 3);
      case PresenceEvent.listenCancel:
      case PresenceEvent.stop:
        _retract(u);
      case PresenceEvent.done:
        _startDone(_lookMood);
      case PresenceEvent.error:
        _startError(strength);
      case PresenceEvent.tool:
        _toolBeat();
      case PresenceEvent.unlock:
        _startUnlock();
    }
    _lastEvent = event;
    _wake();
  }

  /// Run the glow through Listening → Thinking → Tool → Responding → Done on
  /// the real screen, for the presence picker's "Preview on screen".
  Future<void> preview() {
    final running = _previewDone;
    if (running != null) {
      return running.future;
    }
    if (style == PresenceStyle.off) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _previewDone = completer;
    _runScript([
      _Step(AssistantMood.listening, 2, origin: _actionOrigin),
      const _Step(AssistantMood.thinking, 1.6),
      const _Step(AssistantMood.tool, 1.2, beat: PresenceEvent.tool),
      const _Step(AssistantMood.responding, 2),
      const _Step(null, 1.1, beat: PresenceEvent.done),
    ]);
    _wake();
    return completer.future;
  }

  /// Stage one state on this engine (the picker preview). Null clears it.
  void demo(PresenceDemo? state) {
    _script = null;
    _finishPreview();
    switch (state) {
      case null:
        _demoMood = null;
      case PresenceDemo.listening:
        _demoMood = AssistantMood.listening;
        _nextOrigin = _actionOrigin;
      case PresenceDemo.thinking:
        _demoMood = AssistantMood.thinking;
      case PresenceDemo.tool:
        _demoMood = AssistantMood.tool;
        _toolBeat();
      case PresenceDemo.replying:
        _demoMood = AssistantMood.responding;
        _respondingSince = _t;
      case PresenceDemo.speaking:
        _demoMood = AssistantMood.speaking;
        _nextOrigin = 0.5;
      case PresenceDemo.done:
        if (_lit < 0.3 || _demoMood == null) {
          _runScript([
            const _Step(AssistantMood.responding, 0.55),
            const _Step(null, 1.1, beat: PresenceEvent.done),
          ]);
        } else {
          _startDone(_demoMood!);
          _demoMood = null;
        }
      case PresenceDemo.error:
        _demoMood = null;
        _startError(1);
    }
    _wake();
  }

  /// Cut all light at once (locking, backgrounding).
  void silence() {
    _script = null;
    _demoMood = null;
    _provisional = null;
    _pendingExit = null;
    _holdUntil = -1;
    _errorStart = null;
    _unlockStart = null;
    _flash.snap(0);
    _flashOn = false;
    _reveal.snap(0);
    _intensity.snap(0);
    _flare = 0;
    _front = 0;
    _amp = 0;
    _pump = 0;
    _ripples.fillRange(0, 4, 0);
    _ticker?.stop();
    _rest();
    _finishPreview();
    notifyListeners();
  }

  // ----------------------------------------------------------------- state

  Ticker? _ticker;
  double? _lastTick;
  double _t = 0;

  PresenceStyle? _styleOverride;
  bool _platformReduceMotion = false;
  bool _keyboard = false;
  GlowGeometry _geometry = GlowGeometry.zero;
  PresenceEvent? _lastEvent;

  // Inference from the feed.
  String? _toolLabel;
  String? _replyId;
  int _replyLength = 0;

  // Who decides the look.
  AssistantMood? _demoMood;
  AssistantMood? _provisional;
  double _provisionalUntil = 0;
  ({AssistantMood from, double at})? _pendingExit;
  AssistantMood _heldMood = AssistantMood.idle;
  double _holdUntil = -1;
  double _suppressDoneUntil = -1;
  double _suppressBloomUntil = -1;
  double? _nextOrigin;

  // Timelines (start times on the engine clock).
  double? _errorStart;
  double _errorStrength = 1;
  double? _unlockStart;
  bool _unlockDraining = false;
  double _doneStart = -10;
  double _respondingSince = 0;
  double _toolCometUntil = -1;
  List<_Step>? _script;
  int _scriptIndex = 0;
  double _scriptStepStart = 0;
  Completer<void>? _previewDone;

  // Animated values.
  final _intensity = _Spring(16, epsilon: 0.0008);
  final _depth = _Spring(16, value: 14, epsilon: 0.02);
  final _bias = _Spring(10, epsilon: 0.002);
  final _cometOnly = _Spring(12, epsilon: 0.002);
  final _ringMix = _Spring(12, epsilon: 0.002);
  // Voice, words and the speaking envelope are smoothed at the source; this
  // only softens hand-overs between them.
  final _energy = _Spring(40, epsilon: 0.002);
  final _reveal = _Ramp();
  final _flash = _Ramp();
  bool _flashOn = false;
  final _palette = GlowPalette(AppSpectrum.responding);
  double _origin = 0;
  double _flare = 0;
  double _front = 0;
  double _amp = 0;
  double _slowAmp = 0;
  double _pump = 0;
  double _env = 0;
  double _flow = 0;
  double _hue = 0;
  double _cometHead = 0.5;
  double _drainDepth = 14;
  double _cometGain = 1;
  double _lastRipple = -1;
  final Float64List _ripples = Float64List(4);
  final _look = _Look();
  final GlowFrame _frame = GlowFrame();

  /// How lit the glow is right now (intensity times bloom).
  double get _lit => _intensity.value * _reveal.value;

  PresenceStyle get _drawStyle {
    final chosen = style;
    if (chosen == PresenceStyle.off) {
      return chosen;
    }
    return reduceMotion ? PresenceStyle.pulse : chosen;
  }

  /// Where taps on the composer's action button land on the rim.
  double get _actionOrigin {
    if (_geometry.isEmpty) {
      return 0.04;
    }
    final size = _geometry.size;
    return _geometry.loopOf(Offset(size.width - 44, size.height - 36));
  }

  /// The header orb's projection on the rim (top left).
  double get _toolOrigin {
    if (_geometry.isEmpty) {
      return 0.9;
    }
    return _geometry.loopOf(const Offset(64, 0));
  }

  // ------------------------------------------------------------ inference

  void _onFeed() {
    final feed = _feed;
    if (feed == null) {
      return;
    }
    final tool = feed.toolLabel;
    if (tool != null && tool != _toolLabel) {
      _toolBeat();
      _lastEvent = PresenceEvent.tool;
    }
    _toolLabel = tool;

    final reply = feed.streamingReply;
    if (reply == null) {
      _replyId = null;
      _replyLength = 0;
    } else if (reply.$1 != _replyId) {
      _replyId = reply.$1;
      _replyLength = reply.$2;
    } else if (reply.$2 > _replyLength) {
      _pumpTokens(reply.$2 - _replyLength);
      _replyLength = reply.$2;
    }

    final next = feed.mood;
    if (next != _mood) {
      _moveTo(next, infer: true);
      notifyListeners();
    } else if (tool != null) {
      _wake();
    }
  }

  void _moveTo(AssistantMood next, {required bool infer}) {
    // A busy mood still settling through idle is the real "before": the
    // controller often notifies idle first, then the error or the next
    // state, a frame or two later.
    final exit = _pendingExit;
    final previous = exit?.from ?? _mood;
    _mood = next;
    if (moodIsBusy(next)) {
      _provisional = null;
      _pendingExit = null;
      if (infer &&
          exit != null &&
          next == AssistantMood.speaking &&
          _isReply(exit.from) &&
          _t >= _suppressDoneUntil) {
        // The reply landed and Frank reads it aloud: keep the landing
        // sweep, then hand over to speaking.
        _startDone(exit.from);
        _lastEvent = PresenceEvent.done;
      }
      if (next == AssistantMood.responding &&
          previous != AssistantMood.responding) {
        _respondingSince = _t;
      }
      _wake();
      return;
    }
    if (!infer || !moodIsBusy(previous)) {
      _wake();
      return;
    }
    if (next == AssistantMood.error) {
      _pendingExit = null;
      final soft = previous == AssistantMood.listening ||
          previous == AssistantMood.transcribing;
      _startError(soft ? 0.6 : 1);
      _lastEvent = PresenceEvent.error;
      _wake();
      return;
    }
    // Busy → idle. Wait a beat before calling it done: the controller often
    // passes through idle between states (listening → transcribing), and a
    // Stop tap may land just after the chat settles.
    if (ticking) {
      _pendingExit = (from: previous, at: _t);
    } else {
      _settleExit(previous);
    }
    _wake();
  }

  void _settleExit(AssistantMood from) {
    if (moodIsBusy(_mood) || _t < _suppressDoneUntil) {
      return;
    }
    if (_isReply(from)) {
      _startDone(from);
      _lastEvent = PresenceEvent.done;
    }
  }

  static bool _isReply(AssistantMood mood) {
    return mood == AssistantMood.thinking ||
        mood == AssistantMood.tool ||
        mood == AssistantMood.responding;
  }

  void _pumpTokens(int chars) {
    _pump = math.min(1, _pump + 0.05 + 0.004 * chars);
  }

  // --------------------------------------------------------------- beats

  void _cue(AssistantMood mood, double origin, double grace) {
    if (moodIsBusy(_mood) || _demoMood != null) {
      // Already lit: a spark where the finger landed is enough. If the
      // mood arrived a moment before this beat and the bloom has not left
      // yet, it still leaves from here.
      if (_reveal.value >= 0.999 || _reveal.value < 0.02) {
        _origin = origin;
        _nextOrigin = origin;
      }
      _flare = math.max(_flare, 0.7);
      return;
    }
    _provisional = mood;
    _provisionalUntil = _t + grace;
    _pendingExit = null;
    _holdUntil = -1;
    _suppressBloomUntil = -1;
    _nextOrigin = origin;
  }

  void _retract(double? origin) {
    _provisional = null;
    _pendingExit = null;
    _holdUntil = -1;
    _suppressDoneUntil = _t + 1.2;
    _suppressBloomUntil = _t + 1.0;
    if (_reveal.value <= 0.001) {
      return;
    }
    if (origin != null && _reveal.value >= 0.999) {
      _origin = origin;
    }
    _front = 0;
    _reveal.animate(0, reduceMotion ? 0.2 : 0.26, AppMotion.glowDrain);
  }

  void _toolBeat() {
    _cometGain = 1.6;
    _respondingSince = _t;
    _toolCometUntil = _t + 1.2;
    if (_drawStyle == PresenceStyle.aura) {
      _cometHead = _toolOrigin;
    }
  }

  void _startDone(AssistantMood from) {
    if (_lit < 0.02) {
      return;
    }
    _doneStart = _t;
    _heldMood = moodIsBusy(from) ? from : AssistantMood.responding;
    _holdUntil = _t + 0.38;
    if (!reduceMotion) {
      _flash.snap(0);
      _flash.animate(1, 0.48, AppMotion.sweep);
      _flashOn = true;
    }
  }

  void _startError(double strength) {
    _errorStart = _t;
    _errorStrength = strength.clamp(0.0, 1.0);
    if (_lit < 0.02) {
      _nextOrigin = 0;
    }
  }

  void _startUnlock() {
    if (style == PresenceStyle.off) {
      return;
    }
    _unlockStart = _t;
    _unlockDraining = false;
    if (_lit < 0.02) {
      _palette.fadeTo(AppSpectrum.welcome, 0);
      _reveal.snap(0);
      _nextOrigin = 0.5;
    }
  }

  void _runScript(List<_Step> steps) {
    _script = steps;
    _scriptIndex = -1;
    _advanceScript();
  }

  void _advanceScript() {
    final steps = _script;
    if (steps == null) {
      return;
    }
    _scriptIndex++;
    if (_scriptIndex >= steps.length) {
      _script = null;
      _demoMood = null;
      _finishPreview();
      return;
    }
    final step = steps[_scriptIndex];
    _scriptStepStart = _t;
    if (step.origin != null) {
      _nextOrigin = step.origin;
    }
    switch (step.beat) {
      case PresenceEvent.done:
        _startDone(_demoMood ?? _lookMood);
        _lastEvent = PresenceEvent.done;
      case PresenceEvent.tool:
        _toolBeat();
      default:
        break;
    }
    _demoMood = step.mood;
    if (step.mood == AssistantMood.responding) {
      _respondingSince = _t;
    }
  }

  void _finishPreview() {
    final done = _previewDone;
    _previewDone = null;
    if (done != null && !done.isCompleted) {
      done.complete();
    }
  }

  // ---------------------------------------------------------------- ticking

  void _wake() {
    final ticker = _ticker ??= vsync.createTicker(_onTick);
    if (!ticker.isActive) {
      _lastTick = null;
      ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final last = _lastTick;
    _lastTick = now;
    final dt = last == null ? 0.0 : (now - last).clamp(0.0, 1 / 30);
    _advance(dt);
    if (_atRest) {
      _ticker?.stop();
      _rest();
    }
    notifyListeners();
  }

  /// The mood whose look is on screen, after previews, settle windows,
  /// done holds and provisional cues.
  AssistantMood get _lookMood {
    final demo = _demoMood;
    if (demo != null) {
      return demo;
    }
    if (moodIsBusy(_mood)) {
      return _mood;
    }
    final pending = _pendingExit;
    if (pending != null) {
      return pending.from;
    }
    if (_t < _holdUntil) {
      return _heldMood;
    }
    final provisional = _provisional;
    if (provisional != null) {
      return provisional;
    }
    return AssistantMood.idle;
  }

  void _advance(double dt) {
    _t += dt;

    // Scripts, settle windows and cues that ran out.
    final script = _script;
    if (script != null &&
        _t - _scriptStepStart >= script[_scriptIndex].seconds) {
      _advanceScript();
    }
    final pending = _pendingExit;
    if (pending != null && _t - pending.at >= 0.16) {
      _pendingExit = null;
      _settleExit(pending.from);
    }
    if (_provisional != null && _t >= _provisionalUntil) {
      _provisional = null;
    }

    final mood = _lookMood;
    final style = _drawStyle;
    _signals(dt, mood);
    _compose(mood, style);
    final look = _look;

    // Bloom whenever the look wants light and nothing is lit or rising.
    final wantsLight = look.intensity > 0;
    if (wantsLight && _reveal.target < 1 && _t >= _suppressBloomUntil) {
      _bloom(
        _nextOrigin ?? (mood == AssistantMood.speaking ? 0.5 : 0),
        look.intensity,
      );
    }
    _nextOrigin = wantsLight ? null : _nextOrigin;

    // Retracted fully: nothing left to show.
    if (_reveal.target == 0 && !_reveal.running && _reveal.value == 0) {
      _intensity.snap(0);
    }

    if (_lit < 0.002) {
      // Unseen: jump straight to the new look so a bloom starts right.
      _depth.snap(look.depth);
      _bias.snap(look.bias);
      _cometOnly.snap(look.cometOnly);
      _ringMix.snap(look.ringMix);
      _palette.fadeTo(look.palette, 0);
    }
    _palette.fadeTo(look.palette, look.paletteSeconds);
    _palette.step(dt);

    _intensity.target = look.intensity;
    final draining = _intensity.target < _intensity.value;
    _intensity.step(dt, draining ? (_errorStart != null ? 6 : 8) : 16);
    _depth.target = look.depth;
    _depth.step(dt);
    _bias.target = _keyboard ? math.min(look.bias, 0) : look.bias;
    _bias.step(dt);
    _cometOnly.target = look.cometOnly;
    _cometOnly.step(dt);
    _ringMix.target = look.ringMix;
    _ringMix.step(dt);
    _energy.target = look.amp;
    _energy.step(dt);

    _reveal.step(dt);
    if (_reveal.running && _reveal.target == 1 && !reduceMotion) {
      _front = 1.2 * math.pow(1 - _reveal.progress, 0.8).toDouble();
    } else {
      _front = 0;
    }
    _flare = math.max(0, _flare - dt / 0.18);
    _cometGain = 1 + (_cometGain - 1) * math.exp(-dt / 0.3);
    if ((_cometGain - 1).abs() < 0.002) {
      _cometGain = 1;
    }
    _flash.step(dt);
    if (_flashOn && !_flash.running) {
      _flashOn = false;
    }

    _flow = (_flow + dt * look.flow) % 119;
    _hue = (_hue + dt * look.hue) % 1;
    if (look.comet > 0) {
      _cometHead = (_cometHead + dt * look.comet) % 1;
    }

    _write(look, mood, dt);
  }

  /// Light grows from [origin] along both sides at once and meets at the
  /// opposite point, two bright fronts racing ahead of it.
  void _bloom(double origin, double target) {
    final dark = _reveal.value < 0.02;
    if (dark) {
      _origin = origin;
      _reveal.snap(0);
      _intensity.snap(0);
    }
    if (_drawStyle == PresenceStyle.pulse) {
      // Breath enters as a fade, in place.
      _reveal.snap(1);
      return;
    }
    if (dark) {
      // The growing mask is the entrance, so the light starts most of the
      // way up; otherwise the racing fronts would pass unseen.
      _intensity.snap(target * 0.6);
    }
    _flare = 1;
    _reveal.animate(1, _unlockStart != null ? 0.4 : 0.46, _bloomCurve);
  }

  /// Quick off the mark, then a long glide, so the fronts read as travel.
  static const _bloomCurve = Cubic(0.3, 0.7, 0.2, 1);

  /// Mic envelope, voice ripples, token pump and the speaking envelope.
  void _signals(double dt, AssistantMood mood) {
    double level = 0;
    final simulated = _demoMood != null || _script != null;
    if (mood == AssistantMood.listening) {
      level = simulated ? _fakeVoice(_t) : _feed?.voiceLevel.value ?? 0;
    }
    level = level.clamp(0.0, 1.0);
    final tau = level > _amp ? 0.045 : 0.22;
    _amp += (level - _amp) * (1 - math.exp(-dt / tau));
    _slowAmp += (level - _slowAmp) * (1 - math.exp(-dt / 0.4));

    final ripples = mood == AssistantMood.listening &&
        _drawStyle == PresenceStyle.aura &&
        !reduceMotion;
    if (ripples && level - _slowAmp > 0.18 && _t - _lastRipple >= 0.14) {
      final slot = _ripples[0] >= _ripples[2] ? 0 : 2;
      _ripples[slot] = 0;
      _ripples[slot + 1] = math.min(1, 2 * (level - _slowAmp));
      _lastRipple = _t;
    }
    for (final slot in const [0, 2]) {
      if (_ripples[slot + 1] > 0) {
        _ripples[slot] += dt / 0.7;
        if (_ripples[slot] >= 1) {
          _ripples[slot] = 0;
          _ripples[slot + 1] = 0;
        }
      }
    }

    if (simulated && mood == AssistantMood.responding) {
      _pump = math.max(_pump, 0.35 + 0.45 * _vnoise(_t * 3.1 + 17));
    }
    _pump *= math.exp(-dt / 0.25);
    _env = mood == AssistantMood.speaking
        ? 0.35 + 0.65 * _vnoise(_t * 4.3)
        : 0;
  }

  /// Fill [_look] with the targets for [mood] drawn in [style].
  void _compose(AssistantMood mood, PresenceStyle style) {
    final look = _look..reset(_palette.target);
    final wave = math.sin(_t * math.pi); // 2000ms period
    switch (mood) {
      case AssistantMood.listening:
        look
          ..intensity = 0.85 + 0.15 * _amp
          ..depth = 17
          ..bias = 1
          ..flow = 0.9 + 0.4 * _amp
          ..hue = 0.03
          ..amp = _amp
          ..palette = AppSpectrum.listening;
      case AssistantMood.transcribing:
        look
          ..intensity = 0.82
          ..depth = 13
          ..bias = 0.6
          ..flow = 2.2
          ..hue = 0.05
          ..palette = AppSpectrum.transcribing;
      case AssistantMood.thinking:
        final breath = 0.5 + 0.5 * wave;
        look
          ..intensity = 0.68 + 0.2 * breath
          ..depth = 17 * (0.75 + 0.4 * breath)
          ..flow = 0.6
          ..hue = 0.025
          ..palette = AppSpectrum.thinking;
      case AssistantMood.tool:
        look
          ..intensity = 0.85
          ..depth = 12
          ..flow = 0.8
          ..hue = 0.04
          ..palette = AppSpectrum.tool;
      case AssistantMood.responding:
        final receded = _t - _respondingSince > 6 ? 0.6 : 1.0;
        look
          ..intensity = (0.8 + 0.2 * _pump) * receded
          ..depth = 16 + 8 * _pump
          ..bias = 0.3
          ..flow = 1.0
          ..hue = 0.035
          ..amp = 0.25 * _pump
          ..palette = AppSpectrum.responding;
      case AssistantMood.speaking:
        look
          ..intensity = 0.85
          ..depth = 14 * (0.8 + 0.4 * _env)
          ..bias = -1
          ..flow = 0.7
          ..hue = -0.03
          ..amp = 0.35 * _env
          ..palette = AppSpectrum.speaking;
      case AssistantMood.reconnecting:
        final blink = 0.5 + 0.5 * math.sin(_t * 2 * math.pi / 1.6);
        look
          ..intensity = 0.45 * (0.7 + 0.3 * blink)
          ..depth = 10
          ..flow = 0.2
          ..hue = 0.01
          ..palette = AppSpectrum.reconnecting;
      case AssistantMood.idle:
      case AssistantMood.error:
        // Draining: keep the colors, thin the light out.
        look
          ..intensity = 0
          ..depth = _drainDepth * 0.4
          ..bias = _bias.value
          ..flow = 0.5
          ..paletteSeconds = 0;
    }

    _overlayTimelines(look);
    _applyStyle(look, mood, style);
    if (reduceMotion) {
      look.intensity = math.min(look.intensity, _errorStart != null ? 0.5 : 0.85);
    }
    if (look.intensity > 0) {
      _drainDepth = look.depth;
    }
  }

  void _overlayTimelines(_Look look) {
    final unlock = _unlockStart;
    if (unlock != null) {
      final t = _t - unlock;
      if (t >= 1.1 || (t >= 0.6 && moodIsBusy(_lookMood))) {
        _unlockStart = null;
      } else {
        if (t >= 0.6 && !_unlockDraining) {
          // Drain downward and out: the light leaves the top first.
          _unlockDraining = true;
          _suppressBloomUntil = _t + 0.6;
          if (!reduceMotion) {
            if (_reveal.value >= 0.999) {
              _origin = 0;
            }
            _reveal.animate(0, 0.5, AppMotion.glowDrain);
          }
        }
        look
          ..intensity = reduceMotion ? 0.5 : 0.9
          ..depth = 15
          ..bias = -0.5
          ..flow = 1.0
          ..hue = 0.05
          ..palette = AppSpectrum.welcome
          ..paletteSeconds = 0.2;
        if (_unlockDraining && reduceMotion) {
          look.intensity = 0;
        }
      }
    }

    final error = _errorStart;
    if (error != null) {
      final t = _t - error;
      if (t >= 1.66) {
        _errorStart = null;
      } else {
        final busy = moodIsBusy(_lookMood);
        double swell = 1;
        if (t < 0.18) {
          swell = 1 + 0.6 * Curves.easeOutBack.transform(t / 0.18);
        } else if (t < 0.36) {
          swell = 1.6 - 0.6 * Curves.easeInOut.transform((t - 0.18) / 0.18);
        }
        if (t < 0.76 || !busy) {
          look
            ..intensity = t < 0.76 ? 0.85 * _errorStrength : 0
            ..depth = 16 * swell
            ..bias = 0.5
            ..flow = 1.2
            ..hue = 0.03
            ..amp = 0
            ..palette = AppSpectrum.error
            ..paletteSeconds = 0.12;
        }
      }
    }
  }

  void _applyStyle(_Look look, AssistantMood mood, PresenceStyle style) {
    switch (style) {
      case PresenceStyle.off:
        look.intensity = 0;
      case PresenceStyle.aura:
        if (mood == AssistantMood.transcribing) {
          // Two comets fall from the far side and meet at the origin.
          final p = (_t % 0.9) / 0.9;
          _cometHead = 0.5 + 0.5 * p;
          look
            ..twin = 2
            ..cometWidth = 0.05
            ..cometVisible = true;
          _cometGain = math.max(_cometGain, 1 + 0.4 * _smooth(0.8, 1.0, p));
        } else if (mood == AssistantMood.tool || _t < _toolCometUntil) {
          look
            ..comet = 0.7
            ..cometWidth = 0.06
            ..cometVisible = true;
        }
      case PresenceStyle.ribbon:
      case PresenceStyle.twin:
        look
          ..cometOnly = 1
          ..cometVisible = true
          ..twin = style == PresenceStyle.twin ? 1 : 0
          ..depth = look.depth * 1.2
          ..comet = _cometSpeed(mood)
          ..cometWidth = mood == AssistantMood.listening
              ? 0.06 + 0.07 * _amp
              : 0.08;
      case PresenceStyle.veil:
        look
          ..ringMix = 1
          ..depth = look.intensity > 0 ? 16 : look.depth
          ..bias = 0
          ..flow = 0
          ..hue = 0.125;
      case PresenceStyle.pulse:
        double level;
        switch (mood) {
          case AssistantMood.listening:
            level = _amp;
          case AssistantMood.responding:
            level = _pump;
          case AssistantMood.speaking:
            level = _env;
          default:
            level = 0.5 + 0.5 * math.sin(_t * math.pi); // 0.5 Hz
        }
        if (look.intensity > 0 && _errorStart == null && _unlockStart == null) {
          look.intensity = 0.35 + 0.5 * level;
        }
        look
          ..ringMix = 1
          ..depth = look.intensity > 0 ? 18 : look.depth
          ..bias = 0
          ..flow = 0
          ..hue = 0
          ..amp = 0;
    }
  }

  static double _cometSpeed(AssistantMood mood) {
    switch (mood) {
      case AssistantMood.listening:
        return 0.35;
      case AssistantMood.thinking:
        return 0.16;
      case AssistantMood.tool:
        return 0.7;
      case AssistantMood.responding:
        return 0.25;
      case AssistantMood.speaking:
        return 0.3;
      case AssistantMood.transcribing:
        return 0.5;
      case AssistantMood.reconnecting:
        return 0.1;
      case AssistantMood.idle:
      case AssistantMood.error:
        return 0.2;
    }
  }

  void _write(_Look look, AssistantMood mood, double dt) {
    final gain = _settings?.glowGain ?? 1.0;
    final sinceDone = _t - _doneStart;
    final boost = sinceDone < 0.2
        ? 1 + 0.25 * (1 - _smooth(0.09, 0.2, sinceDone))
        : 1.0;
    final calm = reduceMotion ? 0.5 : 1.0;
    final f = _frame
      ..intensity = _intensity.value * gain * boost
      ..depth = _depth.value
      ..amp = _energy.value.clamp(0.0, 1.0)
      ..flow = _flow
      ..hue = _hue
      ..bias = _bias.value
      ..origin = _origin
      ..reveal = _reveal.value
      ..front = _front * calm
      ..flare = _flare * calm
      ..comet = look.cometVisible ? _cometHead : -1
      ..cometWidth = look.cometWidth
      ..cometGain = _cometGain
      ..twin = look.twin
      ..cometOnly = _cometOnly.value
      ..ringMix = _ringMix.value
      ..flash = _flashOn ? _flash.value : -1
      ..palette = _palette.rgb;
    f.ripples.setAll(0, _ripples);
    // Mirrors the shader's thickness at its peak (noise, lean, voice, comet).
    final biasPeak = 1 + 0.6 * _bias.value.abs() * _bias.value.abs();
    final cometPeak = 1 + 0.6 * f.cometOnly;
    final rippleMax = math.max(_ripples[1], _ripples[3]);
    final thick = f.depth * biasPeak * 1.4 * (1 + 0.8 * f.amp) * cometPeak +
        rippleMax * f.depth;
    final reach = math.max(12.0, thick * 3.4);
    if (_lit < 0.002 || dt <= 0) {
      f.reach = reach;
    } else {
      final tau = reach > f.reach ? 0.05 : 0.3;
      f.reach += (reach - f.reach) * (1 - math.exp(-dt / tau));
    }
    f.readCap = mood == AssistantMood.listening ? 0.22 + 0.13 * f.amp : 0.22;
  }

  bool get _atRest {
    return _look.intensity <= 0 &&
        _intensity.value < 0.002 &&
        !_reveal.running &&
        !_flashOn &&
        _errorStart == null &&
        _unlockStart == null &&
        _pendingExit == null &&
        _provisional == null &&
        _script == null &&
        _demoMood == null &&
        _t >= _holdUntil &&
        _ripples[1] == 0 &&
        _ripples[3] == 0;
  }

  void _rest() {
    if (!moodIsBusy(_mood) && _pendingExit == null) {
      // The chat has settled since any Stop or Cancel. The engine clock
      // stands still at rest, so their windows would otherwise reach into
      // the next turn (no done sweep, a late bloom).
      _suppressDoneUntil = -1;
      _suppressBloomUntil = -1;
    }
    _intensity.snap(0);
    _reveal.snap(0);
    _depth.snap(_depth.target);
    _bias.snap(_bias.target);
    _cometOnly.snap(_cometOnly.target);
    _ringMix.snap(_ringMix.target);
    _energy.snap(0);
    _cometGain = 1;
    _amp = 0;
    _slowAmp = 0;
    _frame.intensity = 0;
  }

  @override
  void dispose() {
    _feed?.removeListener(_onFeed);
    _feed = null;
    _ticker?.dispose();
    _ticker = null;
    _finishPreview();
    super.dispose();
  }

  // ---------------------------------------------------------------- noise

  static double _hash(double n) {
    final s = math.sin(n * 127.1) * 43758.5453;
    return s - s.floorToDouble();
  }

  /// Smooth 1D value noise in 0–1.
  static double _vnoise(double x) {
    final i = x.floorToDouble();
    final f = x - i;
    final s = f * f * (3 - 2 * f);
    final a = _hash(i % 1000);
    final b = _hash((i + 1) % 1000);
    return a + (b - a) * s;
  }

  /// A believable voice for previews: syllables with pauses.
  static double _fakeVoice(double t) {
    final syllables = _vnoise(t * 6.3);
    final phrase = _vnoise(t * 0.9 + 40);
    return (((syllables - 0.3) / 0.7).clamp(0.0, 1.0) * (0.35 + 0.75 * phrase))
        .clamp(0.0, 1.0);
  }

  static double _smooth(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}

/// One step of a scripted presence sequence (previews).
class _Step {
  const _Step(this.mood, this.seconds, {this.beat, this.origin});

  final AssistantMood? mood;
  final double seconds;
  final PresenceEvent? beat;
  final double? origin;
}

/// Per-frame targets for the glow. Reused; never allocated per frame.
class _Look {
  double intensity = 0;
  double depth = 0;
  double bias = 0;
  double flow = 0;
  double hue = 0;
  double comet = 0;
  double cometWidth = 0.06;
  bool cometVisible = false;
  double twin = 0;
  double cometOnly = 0;
  double ringMix = 0;
  double amp = 0;
  List<Color> palette = AppSpectrum.responding;
  double paletteSeconds = 0.32;

  void reset(List<Color> current) {
    intensity = 0;
    depth = 14;
    bias = 0;
    flow = 0;
    hue = 0;
    comet = 0;
    cometWidth = 0.06;
    cometVisible = false;
    twin = 0;
    cometOnly = 0;
    ringMix = 0;
    amp = 0;
    palette = current;
    paletteSeconds = 0.32;
  }
}

/// A critically damped spring, stepped exactly so any frame time is stable.
class _Spring {
  _Spring(this.omega, {double value = 0, this.epsilon = 0.001})
      : value = value,
        target = value;

  final double omega;
  final double epsilon;
  double value;
  double target;
  double velocity = 0;

  void step(double dt, [double? omegaOverride]) {
    final w = omegaOverride ?? omega;
    final d = value - target;
    if (d.abs() < epsilon && velocity.abs() < epsilon * 10) {
      value = target;
      velocity = 0;
      return;
    }
    final c2 = velocity + w * d;
    final e = math.exp(-w * dt);
    value = target + (d + c2 * dt) * e;
    velocity = (c2 - w * (d + c2 * dt)) * e;
  }

  void snap(double v) {
    value = v;
    target = v;
    velocity = 0;
  }
}

/// A timed, curved move from one value to another.
class _Ramp {
  double value = 0;
  double _from = 0;
  double _to = 0;
  double _elapsed = 0;
  double _duration = 0;
  Curve _curve = Curves.linear;

  bool get running => _elapsed < _duration;
  double get target => _to;
  double get progress => _duration <= 0 ? 1 : _elapsed / _duration;

  void animate(double to, double seconds, Curve curve) {
    _from = value;
    _to = to;
    _elapsed = 0;
    _duration = seconds;
    _curve = curve;
    if (seconds <= 0) {
      value = to;
    }
  }

  void snap(double v) {
    value = v;
    _from = v;
    _to = v;
    _elapsed = 0;
    _duration = 0;
  }

  void step(double dt) {
    if (!running) {
      return;
    }
    _elapsed = math.min(_elapsed + dt, _duration);
    value = _from + (_to - _from) * _curve.transform(_elapsed / _duration);
  }
}

class _Silent implements ValueListenable<double> {
  const _Silent();

  @override
  double get value => 0;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Makes the app's [PresenceEngine] reachable from any widget. It does not
/// rebuild dependents when the engine ticks.
class PresenceScope extends InheritedWidget {
  const PresenceScope({
    super.key,
    required this.engine,
    required super.child,
  });

  final PresenceEngine engine;

  static PresenceEngine? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<PresenceScope>()?.engine;
  }

  static PresenceEngine of(BuildContext context) {
    final engine = maybeOf(context);
    assert(engine != null, 'No PresenceScope above this widget.');
    return engine!;
  }

  @override
  bool updateShouldNotify(PresenceScope oldWidget) {
    return !identical(engine, oldWidget.engine);
  }
}
