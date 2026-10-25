import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../presence/presence_engine.dart';
import '../state/assistant_mood.dart';
import '../theme/app_theme.dart';

/// Frank's face: a liquid-plasma glass sphere drawn by `shaders/orb.frag`.
///
/// It shares the edge glow's state palettes, so the face and the aura read as
/// one presence. Idle and still orbs paint a single frame and run no ticker;
/// a busy orb moves only while Frank is doing something.
class FrankOrb extends StatefulWidget {
  const FrankOrb({
    super.key,
    this.size = 28,
    this.live,
    this.listening = false,
    this.lit = true,
    this.intense = false,
    this.mood,
    this.level,
    this.pulse = 0,
  });

  final double size;

  /// Whether the orb may move. When null it moves only while Frank is busy.
  /// False always paints one still frame. True moves while busy, and gives an
  /// idle orb a short wake (a slow swirl for a few seconds) before it dozes.
  final bool? live;

  final bool listening;

  /// False dims the orb into its asleep look: desaturated and low energy.
  final bool lit;

  final bool intense;

  /// What Frank is doing. When null it is derived: [listening] → listening,
  /// [intense] → responding, [live] → thinking, otherwise idle.
  final AssistantMood? mood;

  /// Mic or speech energy (0–1). It drives the membrane and the core while
  /// listening or speaking, pumps the core while replying, and lifts the
  /// energy in any other moving state. Listening orbs fall back to the
  /// presence engine's mic level.
  final ValueListenable<double>? level;

  /// Change it to play the bright one-shot flash, for beats the mood cannot
  /// express (for example a successful unlock). A finished reply flashes on
  /// its own.
  final int pulse;

  /// Loads the orb shader once. Safe to call early (for example in `main`)
  /// and more than once; until it resolves orbs paint a canvas fallback.
  static Future<void> precache() => _OrbProgram.load();

  /// Paint the canvas fallback even when the shader is loaded (tests).
  @visibleForTesting
  static bool debugForceFallback = false;

  @override
  State<FrankOrb> createState() => _FrankOrbState();
}

class _FrankOrbState extends State<FrankOrb>
    with SingleTickerProviderStateMixin {
  static const _wakeSeconds = 6.0;
  static const _timeWrap = 600.0;
  static const _swirlWrap = math.pi * 20;
  static const _orbitWrap = math.pi * 10;

  final _frame = _OrbFrame();
  final _springs = _OrbSprings();
  final _palette = _OrbPalette();

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  PresenceEngine? _engine;
  bool _ready = false;
  bool _reduced = false;

  AssistantMood _mood = AssistantMood.idle;
  bool _moves = false;
  bool _lit = true;

  /// Seconds this orb has spent ticking; transients are timed against it.
  double _age = 0;

  /// The shared frame clock, so breath and blink are phase-locked across
  /// every orb on screen.
  double _clock = 0;

  double _env = 0;
  bool _envHigh = false;
  double? _wakeAt;
  double? _flashAt;
  double _flashPeak = 0;
  double? _shakeAt;
  double _waveAAt = -10;
  double _waveBAt = -10;
  bool _nextWaveA = true;

  @override
  void initState() {
    super.initState();
    // A still orb always shows the same, pleasing phase of the plasma.
    _frame
      ..time = 7.4
      ..swirl = 0.9
      ..orbit = 1.3;
    _OrbProgram.listeners.add(_attachShader);
    _attachShader();
    _OrbProgram.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _engine = PresenceScope.maybeOf(context);
    final reduced = _readReduced();
    if (!_ready) {
      _ready = true;
      _reduced = reduced;
      _clock = _frameClock;
      _resolve();
      if (_moves && _mood == AssistantMood.idle) {
        _wakeAt = _age;
      }
      _retarget(snap: true);
    } else if (reduced != _reduced) {
      _reduced = reduced;
      _retarget();
    }
  }

  @override
  void didUpdateWidget(covariant FrankOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mood = _mood;
    final moved = _moves;
    final lit = _lit;
    final reduced = _readReduced();
    _resolve();
    final pulsed = widget.pulse != oldWidget.pulse;
    if (_mood == mood &&
        _moves == moved &&
        _lit == lit &&
        reduced == _reduced &&
        !pulsed &&
        widget.size == oldWidget.size) {
      return;
    }
    _reduced = reduced;
    _react(from: mood, moved: moved, wasLit: lit);
    if (pulsed) {
      _flash(1);
    }
    _retarget();
  }

  @override
  void dispose() {
    _OrbProgram.listeners.remove(_attachShader);
    _ticker?.dispose();
    _frame.dispose();
    super.dispose();
  }

  bool _readReduced() {
    return AppMotion.reduced(context) ||
        (_engine?.settings?.reduceMotion ?? false);
  }

  /// The vsync time every orb sees in the same frame (readable at any time).
  static double get _frameClock {
    return SchedulerBinding
            .instance
            .currentSystemFrameTimeStamp
            .inMicroseconds /
        1e6;
  }

  void _attachShader() {
    final program = _OrbProgram.program;
    if (program == null || _frame.shader != null || !mounted) {
      return;
    }
    _frame.shader = program.fragmentShader();
    _frame.repaint();
  }

  void _resolve() {
    _mood = _resolveMood(widget);
    _moves = widget.live ?? moodIsBusy(_mood);
    _lit = widget.lit;
  }

  /// One-shot gestures on top of the mood: the done flash, the error
  /// head-shake, the wake when an idle orb starts moving.
  void _react({
    required AssistantMood from,
    required bool moved,
    required bool wasLit,
  }) {
    final to = _mood;
    final gestures = widget.live != false;
    if (gestures && to != from) {
      if (to == AssistantMood.error) {
        if (!_reduced) {
          _shakeAt = _age;
        }
      } else if (to == AssistantMood.idle && _isReplying(from)) {
        _flash(1);
      } else if (to == AssistantMood.tool) {
        _flash(0.35);
      } else if (to == AssistantMood.responding &&
          (from == AssistantMood.thinking || from == AssistantMood.tool)) {
        _flash(0.3);
      }
    }
    if (gestures && _lit && !wasLit) {
      _flash(0.45);
    }
    if (_moves && to == AssistantMood.idle && !moved) {
      _wakeAt = _age;
    } else if (!_moves) {
      _wakeAt = null;
    }
  }

  static bool _isReplying(AssistantMood mood) {
    return mood == AssistantMood.thinking ||
        mood == AssistantMood.tool ||
        mood == AssistantMood.responding;
  }

  void _flash(double peak) {
    final capped = _reduced ? math.min(peak, 0.5) : peak;
    _flashPeak = math.max(capped, _flashNow);
    _flashAt = _age;
  }

  void _retarget({bool snap = false}) {
    final look = _OrbLook.of(_mood);
    final features = _featureGain(widget.size);
    final asleep = !_lit;
    final s = _springs;
    s.energy.target = look.energy * (asleep ? 0.35 : 1);
    s.swirl.target = look.swirl * (asleep ? 0.5 : 1) * (_reduced ? 0.5 : 1);
    s.halo.target = look.halo * (asleep ? 0.5 : 1);
    s.ring.target = look.ring * features;
    s.sparks.target = look.sparks * features;
    s.membrane.target = _reduced ? 0 : look.membrane;
    s.key.target = look.key;
    s.density.target = look.density;
    s.desat.target = math.max(look.desat, asleep ? 0.5 : 0);
    s.opacity.target = asleep ? 0.85 : 1;
    s.breath.target = look.breath;
    s.blink.target = look.blink;
    s.voice.target = look.voice;
    s.pump.target = look.pump;
    s.drift.target = _continuous ? 1 : 0;
    if (snap) {
      s.snap();
      _palette.snap(look.palette);
      _publish();
    } else {
      _palette.retarget(
        look.palette,
        _mood == AssistantMood.error ? 0.12 : 0.32,
      );
    }
    _sync();
  }

  bool get _waking =>
      _wakeAt != null && _moves && _age - _wakeAt! < _wakeSeconds;

  /// Motion that lasts as long as the state does (not a settle or gesture).
  bool get _continuous => _moves && (moodIsBusy(_mood) || _waking);

  bool get _gesturing {
    final flash = _flashAt != null && _age - _flashAt! < 0.68;
    final shake = _shakeAt != null && _age - _shakeAt! < 0.36;
    final waves = _age - _waveAAt < 0.7 || _age - _waveBAt < 0.7;
    return flash || shake || waves;
  }

  bool get _wantsFrames =>
      _continuous ||
      _gesturing ||
      _env > 0.002 ||
      !_springs.settled ||
      !_palette.settled;

  void _sync() {
    if (!_wantsFrames) {
      return;
    }
    final ticker = _ticker ??= createTicker(_tick);
    if (!ticker.isActive) {
      _lastTick = Duration.zero;
      _clock = _frameClock;
      ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _lastTick = elapsed;
    _age += dt;
    _clock = _frameClock;

    _springs.drift.target = _continuous ? 1 : 0;
    _springs.step(dt);
    _palette.step(dt);
    _follow(dt);

    // Drift eases the plasma to a stop when Frank goes quiet, and keeps a
    // still orb still while only its colours crossfade.
    final frame = _frame;
    final drift = _springs.drift.value.clamp(0.0, 1.0) * dt;
    final swirl = _springs.swirl.value + _wakeSwirl;
    frame.swirl = (frame.swirl + swirl * math.pi * 2 * drift) % _swirlWrap;
    frame.time = (frame.time + drift * (_reduced ? 0.6 : 1)) % _timeWrap;
    if (_springs.ring.value > 0.001 || _springs.sparks.value > 0.001) {
      // One lap of the thinking ring every 3 s; sparks run 2.4x faster.
      final lap = math.pi * 2 / 3 * (_reduced ? 0.5 : 1);
      frame.orbit = (frame.orbit + lap * drift) % _orbitWrap;
    }

    _publish();
    if (!_wantsFrames) {
      _ticker?.stop();
    }
  }

  /// The voice envelope: mic level while listening, the speech envelope while
  /// speaking, a soft token pump while replying (45 ms attack, 220 ms release).
  void _follow(double dt) {
    final input = _continuous ? _voiceInput() : 0.0;
    final tau = input > _env ? 0.045 : 0.22;
    _env += (input - _env) * (1 - math.exp(-dt / tau));
    if (_env < 0.0005 && input == 0) {
      _env = 0;
    }

    final waves =
        _mood == AssistantMood.speaking &&
        _continuous &&
        !_reduced &&
        _featureGain(widget.size) > 0;
    if (_env > 0.7) {
      final last = math.max(_waveAAt, _waveBAt);
      if (waves && !_envHigh && _age - last > 0.42) {
        if (_nextWaveA) {
          _waveAAt = _age;
        } else {
          _waveBAt = _age;
        }
        _nextWaveA = !_nextWaveA;
      }
      _envHigh = true;
    } else if (_env < 0.6) {
      _envHigh = false;
    }
  }

  double _voiceInput() {
    final level = widget.level;
    switch (_mood) {
      case AssistantMood.listening:
        return (level ?? _engine?.level)?.value.clamp(0.0, 1.0) ?? 0;
      case AssistantMood.speaking:
        if (level != null) {
          return level.value.clamp(0.0, 1.0);
        }
        // No playback level: a calm, speech-like swell (all under 2 Hz).
        final a = 0.5 + 0.5 * math.sin(_clock * math.pi * 2 * 1.7);
        final b = 0.5 + 0.5 * math.sin(_clock * math.pi * 2 * 0.63 + 1.3);
        return 0.2 + 0.65 * a * b;
      case AssistantMood.responding:
        if (level != null) {
          return level.value.clamp(0.0, 1.0);
        }
        final a = 0.5 + 0.5 * math.sin(_clock * math.pi * 2 * 1.3);
        final b = 0.5 + 0.5 * math.sin(_clock * math.pi * 2 * 0.47 + 0.6);
        return 0.15 + 0.4 * a * b;
      default:
        // Any other energy a caller hands in (the lock screen's wake).
        return level?.value.clamp(0.0, 1.0) ?? 0;
    }
  }

  double get _wakeProgress {
    final at = _wakeAt;
    if (at == null || !_moves) {
      return -1;
    }
    return _age - at;
  }

  double get _wakeSwirl {
    final t = _wakeProgress;
    if (t < 0) {
      return 0;
    }
    final speed = _reduced ? 0.02 : 0.04;
    return speed *
        _smoothstep(0, 0.8, t) *
        (1 - _smoothstep(_wakeSeconds - 1.8, _wakeSeconds, t));
  }

  double get _wakeSwell {
    final t = _wakeProgress;
    if (t < 0 || t > 1.6 || !_lit) {
      return 0;
    }
    final s = math.sin(math.pi * t / 1.6);
    return 0.35 * s * s;
  }

  double get _flashNow {
    final at = _flashAt;
    if (at == null) {
      return 0;
    }
    final t = _age - at;
    if (t < 0.08) {
      return _flashPeak * Curves.easeOut.transform(t / 0.08);
    }
    final k = (t - 0.08) / 0.6;
    if (k >= 1) {
      return 0;
    }
    return _flashPeak * (1 - Curves.easeOutCubic.transform(k));
  }

  double get _shakeNow {
    final at = _shakeAt;
    if (at == null) {
      return 0;
    }
    final t = _age - at;
    if (t >= 0.36) {
      return 0;
    }
    // A 'no': three cycles in 360 ms, settling as it goes.
    return math.sin(t / 0.12 * math.pi * 2) * (1 - t / 0.36);
  }

  double _waveNow(double at) {
    final t = (_age - at) / 0.7;
    return t < 0 || t > 1 ? -1 : t;
  }

  /// Writes the springs, envelopes and gestures into the frame the painter
  /// reads, then asks for a repaint (no widget rebuild).
  void _publish() {
    final s = _springs;
    final f = _frame;
    final breath = math.sin(_clock * math.pi); // 2000 ms period
    final blink = 0.5 - 0.5 * math.cos(_clock * math.pi * 2 / 1.6);
    f.energy =
        (s.energy.value +
                s.breath.value * 0.1 * breath +
                s.voice.value * _env +
                s.pump.value * 0.4 * _env +
                _wakeSwell)
            .clamp(0.0, 1.0);
    f.amp = (_env * (s.voice.value * 2 + s.pump.value * 0.6)).clamp(0.0, 1.0);
    f.membrane = s.membrane.value * _env;
    f.halo = s.halo.value * (1 - s.blink.value * 0.5 * blink);
    f.ring = s.ring.value;
    f.sparks = s.sparks.value;
    f.desat = s.desat.value.clamp(0.0, 1.0);
    f.key = s.key.value;
    f.density = s.density.value;
    f.opacity = s.opacity.value.clamp(0.0, 1.0);
    f.flash = _flashNow;
    f.shake = _shakeNow;
    f.waveA = _waveNow(_waveAAt);
    f.waveB = _waveNow(_waveBAt);
    f.palette.setAll(0, _palette.rgb);
    f.repaint();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticLabel(_mood, widget.intense),
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _OrbPainter(
              frame: _frame,
              devicePixelRatio:
                  MediaQuery.maybeDevicePixelRatioOf(context) ?? 3,
            ),
          ),
        ),
      ),
    );
  }
}

AssistantMood _resolveMood(FrankOrb orb) {
  final mood = orb.mood;
  if (mood != null) {
    return mood;
  }
  if (orb.listening) {
    return AssistantMood.listening;
  }
  if (orb.intense) {
    return AssistantMood.responding;
  }
  if (orb.live == true) {
    return AssistantMood.thinking;
  }
  return AssistantMood.idle;
}

String _semanticLabel(AssistantMood mood, bool intense) {
  if (mood == AssistantMood.listening) {
    return 'Hermsy is listening';
  }
  if (intense ||
      mood == AssistantMood.thinking ||
      mood == AssistantMood.tool ||
      mood == AssistantMood.responding) {
    return 'Hermsy is responding';
  }
  return 'Hermsy';
}

/// Rings and sparks need room to read: off at 20dp and below, full at 32dp.
double _featureGain(double size) => ((size - 20) / 12).clamp(0.0, 1.0);

/// 0 for a 16dp inline orb, 1 for 72dp heroes and up.
double _detailFor(double size) => ((size - 16) / 56).clamp(0.0, 1.0);

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Uniform targets per mood (spec_3 "orb"). Springs ease between them.
class _OrbLook {
  const _OrbLook({
    required this.energy,
    required this.palette,
    this.swirl = 0,
    this.halo = 1,
    this.ring = 0,
    this.sparks = 0,
    this.membrane = 0,
    this.key = -1,
    this.density = 1,
    this.desat = 0,
    this.breath = 0,
    this.blink = 0,
    this.voice = 0,
    this.pump = 0,
  });

  final double energy;
  final List<Color> palette;

  /// Plasma rotation, revolutions per second.
  final double swirl;
  final double halo;
  final double ring;
  final double sparks;

  /// Surface wobble at full voice.
  final double membrane;

  /// Plasma key light: -1 from above, +1 from below (listening).
  final double key;
  final double density;
  final double desat;

  /// Thinking breath (±0.1 energy on a 2000 ms sine).
  final double breath;

  /// Reconnecting halo blink (1600 ms).
  final double blink;

  /// How much the [FrankOrb.level] envelope adds to the energy.
  final double voice;

  /// Token pump while replying.
  final double pump;

  static _OrbLook of(AssistantMood mood) {
    return switch (mood) {
      AssistantMood.idle => idle,
      AssistantMood.listening => listening,
      AssistantMood.transcribing => transcribing,
      AssistantMood.thinking => thinking,
      AssistantMood.tool => tool,
      AssistantMood.responding => responding,
      AssistantMood.speaking => speaking,
      AssistantMood.reconnecting => reconnecting,
      AssistantMood.error => error,
    };
  }

  static _OrbLook get idle =>
      _OrbLook(energy: 0.15, halo: 0.6, voice: 0.25, palette: AppSpectrum.idle);
  static _OrbLook get listening => _OrbLook(
    energy: 0.55,
    swirl: 0.12,
    membrane: 0.07,
    key: 1,
    voice: 0.45,
    palette: AppSpectrum.listening,
  );
  static _OrbLook get transcribing => _OrbLook(
    energy: 0.6,
    swirl: 0.35,
    density: 1.4,
    voice: 0.3,
    palette: AppSpectrum.transcribing,
  );
  static _OrbLook get thinking => _OrbLook(
    energy: 0.5,
    swirl: 0.22,
    halo: 0.9,
    ring: 1,
    breath: 1,
    voice: 0.3,
    palette: AppSpectrum.thinking,
  );
  static _OrbLook get tool => _OrbLook(
    energy: 0.7,
    swirl: 0.3,
    sparks: 1,
    voice: 0.3,
    palette: AppSpectrum.tool,
  );
  static _OrbLook get responding => _OrbLook(
    energy: 0.45,
    swirl: 0.15,
    pump: 1,
    palette: AppSpectrum.responding,
  );
  static _OrbLook get speaking => _OrbLook(
    energy: 0.5,
    swirl: 0.15,
    membrane: 0.06,
    voice: 0.5,
    palette: AppSpectrum.speaking,
  );
  static _OrbLook get reconnecting => _OrbLook(
    energy: 0.2,
    swirl: 0.05,
    halo: 0.6,
    desat: 0.7,
    blink: 1,
    palette: AppSpectrum.reconnecting,
  );
  static _OrbLook get error =>
      _OrbLook(energy: 0.3, halo: 0.8, palette: AppSpectrum.error);
}

/// A critically damped spring (ω = 16 rad/s settles in about 250 ms).
class _Spring {
  _Spring([this.omega = 16]);

  final double omega;

  double value = 0;
  double target = 0;
  double velocity = 0;

  bool get settled => (value - target).abs() < 0.0015 && velocity.abs() < 0.01;

  void snap() {
    value = target;
    velocity = 0;
  }

  void step(double dt) {
    if (settled) {
      snap();
      return;
    }
    final x = value - target;
    final decay = math.exp(-omega * dt);
    final drive = velocity + omega * x;
    value = target + (x + drive * dt) * decay;
    velocity = (velocity - omega * drive * dt) * decay;
  }
}

class _OrbSprings {
  final energy = _Spring();
  final swirl = _Spring();
  final halo = _Spring();
  final ring = _Spring();
  final sparks = _Spring();
  final membrane = _Spring();
  final key = _Spring();
  final density = _Spring();
  final desat = _Spring();
  final opacity = _Spring();
  final breath = _Spring();
  final blink = _Spring();
  final voice = _Spring();
  final pump = _Spring();

  /// How much the plasma drifts; slower, so motion dozes off gently.
  final drift = _Spring(9);

  late final List<_Spring> _all = [
    energy,
    swirl,
    halo,
    ring,
    sparks,
    membrane,
    key,
    density,
    desat,
    opacity,
    breath,
    blink,
    voice,
    pump,
    drift,
  ];

  bool get settled => _all.every((spring) => spring.settled);

  void snap() {
    for (final spring in _all) {
      spring.snap();
    }
  }

  void step(double dt) {
    for (final spring in _all) {
      spring.step(dt);
    }
  }
}

/// Four palette stops crossfaded in OKLab, so a mood change never passes
/// through a muddy midpoint.
class _OrbPalette {
  /// Current stops as sRGB 0–1 triples, in shader order.
  final Float64List rgb = Float64List(12);
  final Float64List _from = Float64List(12);
  final Float64List _to = Float64List(12);
  List<Color>? _target;
  double _progress = 1;
  double _duration = 0.32;

  bool get settled => _progress >= 1;

  void snap(List<Color> colors) {
    _target = colors;
    _progress = 1;
    for (var i = 0; i < 4; i++) {
      final color = colors[i];
      rgb[i * 3] = color.r;
      rgb[i * 3 + 1] = color.g;
      rgb[i * 3 + 2] = color.b;
    }
  }

  void retarget(List<Color> colors, double seconds) {
    if (identical(colors, _target)) {
      return;
    }
    _target = colors;
    for (var i = 0; i < 4; i++) {
      _toLab(rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2], _from, i * 3);
      final color = colors[i];
      _toLab(color.r, color.g, color.b, _to, i * 3);
    }
    _duration = seconds;
    _progress = 0;
  }

  void step(double dt) {
    if (settled) {
      return;
    }
    _progress = math.min(1, _progress + dt / _duration);
    final k = Curves.easeInOut.transform(_progress);
    for (var i = 0; i < 12; i += 3) {
      _fromLab(
        _from[i] + (_to[i] - _from[i]) * k,
        _from[i + 1] + (_to[i + 1] - _from[i + 1]) * k,
        _from[i + 2] + (_to[i + 2] - _from[i + 2]) * k,
        rgb,
        i,
      );
    }
  }

  static double _linear(double c) {
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static double _encode(double c) {
    final v = c <= 0.0031308
        ? c * 12.92
        : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
    return v.clamp(0.0, 1.0);
  }

  static double _cbrt(double x) {
    return x < 0
        ? -math.pow(-x, 1 / 3).toDouble()
        : math.pow(x, 1 / 3).toDouble();
  }

  static void _toLab(double r, double g, double b, Float64List out, int at) {
    final lr = _linear(r);
    final lg = _linear(g);
    final lb = _linear(b);
    final l = _cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
    final m = _cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
    final s = _cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
    out[at] = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    out[at + 1] = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    out[at + 2] = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  }

  static void _fromLab(
    double lab,
    double a,
    double b,
    Float64List out,
    int at,
  ) {
    final l = math.pow(lab + 0.3963377774 * a + 0.2158037573 * b, 3).toDouble();
    final m = math.pow(lab - 0.1055613458 * a - 0.0638541728 * b, 3).toDouble();
    final s = math.pow(lab - 0.0894841775 * a - 1.2914855480 * b, 3).toDouble();
    out[at] = _encode(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s);
    out[at + 1] = _encode(
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    );
    out[at + 2] = _encode(
      -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    );
  }
}

/// Loads `shaders/orb.frag` once for every orb in the app.
class _OrbProgram {
  static ui.FragmentProgram? program;
  static Future<void>? _loading;

  /// Orbs waiting to swap their canvas fallback for the shader.
  static final listeners = <VoidCallback>{};

  /// Loads in the root zone, so the shared cache never waits on a zone that
  /// has gone away (a finished test, a disposed error zone).
  static Future<void> load() =>
      _loading ??= Zone.root.run<Future<void>>(_fetch);

  static Future<void> _fetch() async {
    try {
      program = await ui.FragmentProgram.fromAsset('shaders/orb.frag');
    } catch (_) {
      // Unsupported backend or a missing asset: orbs keep the fallback.
      return;
    }
    for (final listener in listeners.toList()) {
      listener();
    }
  }
}

/// The values one painted frame needs. Written by the orb's ticker, read by
/// the painter; notifying it repaints without rebuilding any widget.
class _OrbFrame extends ChangeNotifier {
  ui.FragmentShader? shader;
  final Paint paint = Paint();

  double time = 0;
  double swirl = 0;
  double orbit = 0;
  double energy = 0;
  double amp = 0;
  double membrane = 0;
  double ring = 0;
  double sparks = 0;
  double waveA = -1;
  double waveB = -1;
  double flash = 0;
  double desat = 0;
  double shake = 0;
  double key = -1;
  double halo = 0;
  double density = 1;
  double opacity = 1;
  final Float64List palette = Float64List(12);

  void repaint() => notifyListeners();

  @override
  void dispose() {
    shader?.dispose();
    super.dispose();
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.frame, required this.devicePixelRatio})
    : super(repaint: frame);

  final _OrbFrame frame;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (side <= 0) {
      return;
    }
    final detail = _detailFor(side);
    final radius = side * 0.44;
    // Room around the glass for the halo, rings and sparks.
    final reach = radius * (0.26 + 0.24 * detail + 0.2 * _featureGain(side));
    final center = size.center(Offset.zero);
    final shader = FrankOrb.debugForceFallback ? null : frame.shader;
    if (shader != null) {
      _paintShader(canvas, shader, center, radius, reach, detail);
    } else {
      _paintFallback(canvas, center, radius, reach, detail);
    }
  }

  void _paintShader(
    Canvas canvas,
    ui.FragmentShader shader,
    Offset center,
    double radius,
    double reach,
    double detail,
  ) {
    final f = frame;
    final extent = radius + reach;
    shader
      ..setFloat(0, extent * 2)
      ..setFloat(1, extent * 2)
      ..setFloat(2, radius)
      ..setFloat(3, 1 / (radius * devicePixelRatio))
      ..setFloat(4, f.time)
      ..setFloat(5, f.swirl)
      ..setFloat(6, f.orbit)
      ..setFloat(7, f.energy)
      ..setFloat(8, f.amp)
      ..setFloat(9, f.membrane)
      ..setFloat(10, f.ring)
      ..setFloat(11, f.sparks)
      ..setFloat(12, f.waveA)
      ..setFloat(13, f.waveB)
      ..setFloat(14, f.flash)
      ..setFloat(15, f.desat)
      ..setFloat(16, f.shake)
      ..setFloat(17, f.key)
      ..setFloat(18, f.halo)
      ..setFloat(19, detail)
      ..setFloat(20, f.density)
      ..setFloat(21, f.opacity);
    for (var i = 0; i < 12; i++) {
      shader.setFloat(22 + i, f.palette[i]);
    }
    canvas
      ..save()
      // FlutterFragCoord is in local space, so the square starts at 0,0.
      ..translate(center.dx - extent, center.dy - extent)
      ..drawRect(
        Rect.fromLTWH(0, 0, extent * 2, extent * 2),
        f.paint..shader = shader,
      )
      ..restore();
  }

  /// The canvas version of the orb, for when the shader is not loaded yet
  /// or not supported: the same layers, built from gradients.
  void _paintFallback(
    Canvas canvas,
    Offset center,
    double radius,
    double reach,
    double detail,
  ) {
    final f = frame;
    final c = center.translate(f.shake * radius * 0.12, 0);
    final r = radius * (1 + 0.06 * f.flash);
    final energy = f.energy;
    final paint = Paint()..isAntiAlias = true;
    const clear = Color(0x00000000);

    // Outer halo.
    final halo = (f.halo * (0.16 + 0.5 * energy + 0.35 * f.amp + 0.8 * f.flash))
        .clamp(0.0, 1.2);
    if (halo > 0.01 && reach > 0) {
      final outer = r + reach;
      paint.shader = ui.Gradient.radial(
        c,
        outer,
        [_tone(0, 0.55 * halo), _tone(2, 0.2 * halo), clear],
        [r / outer * 0.96, (r + reach * 0.4) / outer, 1],
      );
      canvas.drawCircle(c, outer, paint);
    }

    // The far half of the ring and the far sparks pass behind the glass.
    _paintRing(canvas, c, r, front: false);
    _paintSparks(canvas, c, r, front: false);

    // Dark glass.
    paint.shader = ui.Gradient.radial(
      c.translate(-r * 0.3, -r * 0.36),
      r * 1.3,
      [
        Color.lerp(const Color(0xFF141B30), _tone(2), 0.18)!,
        const Color(0xFF080C18),
        const Color(0xFF04060C),
      ],
      const [0, 0.55, 1],
    );
    canvas.drawCircle(c, r, paint);

    // Plasma: three lobes in the palette, drifting with the swirl. They stay
    // inside the glass, so no clip is needed.
    paint.blendMode = BlendMode.plus;
    final glow = 0.28 + 0.95 * energy;
    for (var i = 0; i < 3; i++) {
      final a = f.swirl + f.time * 0.12 + i * math.pi * 2 / 3;
      final d = r * (0.34 + 0.08 * math.sin(f.time * 0.7 + i * 1.7));
      final lobe = r * (0.44 + 0.12 * energy);
      final at = c.translate(math.cos(a) * d, math.sin(a) * d * 0.9);
      paint.shader = ui.Gradient.radial(at, lobe, [
        _tone(i, (0.55 * glow).clamp(0.0, 1.0)),
        _tone(i, 0),
      ]);
      canvas.drawCircle(at, lobe, paint);
    }

    // The heart.
    final coreR = r * (0.36 + 0.24 * energy + 0.14 * f.amp);
    final core = (0.12 + 0.55 * energy + 0.45 * f.amp + 0.5 * f.flash).clamp(
      0.0,
      1.0,
    );
    paint.shader = ui.Gradient.radial(c, coreR, [
      Color.lerp(
        _tone(0),
        const Color(0xFFF2F7FF),
        0.6,
      )!.withValues(alpha: core * f.opacity),
      clear,
    ]);
    canvas.drawCircle(c, coreR, paint);

    // Fresnel rim in the palette.
    final rim = (0.45 + 0.75 * energy) * (detail < 0.5 ? 1.35 : 1.0);
    paint.shader = ui.Gradient.radial(
      c,
      r,
      [clear, _tone(1, 0.25 * rim), _tone(3, 0.8 * rim.clamp(0.0, 1.0))],
      const [0.6, 0.86, 1],
    );
    canvas.drawCircle(c, r, paint);
    paint.blendMode = BlendMode.srcOver;

    // A crisp edge that turns through the palette.
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.75, r * 0.035)
      ..shader = ui.Gradient.sweep(
        c,
        [
          _tone(0, 0.5),
          _tone(1, 0.5),
          _tone(2, 0.5),
          _tone(3, 0.5),
          _tone(0, 0.5),
        ],
        const [0, 0.25, 0.5, 0.75, 1],
        TileMode.clamp,
        0,
        math.pi * 2,
        _rotation(c, f.time * 0.25),
      );
    canvas.drawCircle(c, r - paint.strokeWidth / 2, paint);
    paint.style = PaintingStyle.fill;

    _paintRing(canvas, c, r, front: true);
    _paintSparks(canvas, c, r, front: true);

    // Glass: the glint and a lit lip along the top.
    final glintAt = c.translate(-r * 0.4, -r * 0.48);
    final glintR = r * (detail < 0.5 ? 0.34 : 0.26);
    paint.shader = ui.Gradient.radial(
      glintAt,
      glintR,
      [Colors.white.withValues(alpha: 0.75 * f.opacity), clear],
      const [0, 1],
    );
    canvas.drawCircle(glintAt, glintR, paint);

    // Speaking rings.
    for (final wave in [f.waveA, f.waveB]) {
      if (wave < 0) {
        continue;
      }
      final k = 1 - wave;
      paint
        ..shader = null
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, r * (0.04 + 0.04 * wave))
        ..color = _tone(1, 0.85 * k * k);
      canvas.drawCircle(c, r * (1 + wave * 0.3), paint);
      paint.style = PaintingStyle.fill;
    }

    if (f.flash > 0.01) {
      paint
        ..shader = null
        ..color = const Color(0xFFF2F7FF).withValues(alpha: 0.45 * f.flash);
      canvas.drawCircle(c, r, paint);
    }
  }

  void _paintRing(Canvas canvas, Offset c, double r, {required bool front}) {
    final ring = frame.ring;
    if (ring < 0.01) {
      return;
    }
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.8, r * 0.05);
    final oval = Rect.fromCenter(
      center: Offset.zero,
      width: r * 2.34,
      height: r * 2.34 * 0.34,
    );
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(-0.38 + 0.1 * math.sin(frame.time * 0.45));
    paint.color = _tone(1, (front ? 0.5 : 0.22) * ring);
    canvas.drawArc(oval, front ? 0 : math.pi, math.pi, false, paint);
    // The bright head orbiting the ring.
    final head = frame.orbit % (math.pi * 2);
    final onFront = head < math.pi;
    if (onFront == front) {
      paint.color = _tone(0, (front ? 0.95 : 0.4) * ring);
      canvas.drawArc(oval, head - 0.5, 0.5, false, paint);
    }
    canvas.restore();
  }

  void _paintSparks(Canvas canvas, Offset c, double r, {required bool front}) {
    final sparks = frame.sparks;
    if (sparks < 0.01) {
      return;
    }
    final paint = Paint()..isAntiAlias = true;
    const tilt = -0.32;
    for (var i = 0; i < 3; i++) {
      final a = frame.orbit * 2.4 + i * math.pi * 2 / 3;
      if ((math.sin(a) >= 0) != front) {
        continue;
      }
      final x = math.cos(a) * r * 1.16;
      final y = math.sin(a) * r * 1.16 * 0.38;
      final at = c.translate(
        x * math.cos(tilt) - y * math.sin(tilt),
        x * math.sin(tilt) + y * math.cos(tilt),
      );
      final glowR = math.max(2.0, r * 0.22);
      paint.shader = ui.Gradient.radial(at, glowR, [
        _tone(i, 0.7 * sparks),
        _tone(i, 0),
      ]);
      canvas.drawCircle(at, glowR, paint);
      paint.shader = null;
      paint.color = Colors.white.withValues(alpha: sparks * frame.opacity);
      canvas.drawCircle(at, math.max(0.8, r * 0.06), paint);
    }
  }

  /// Palette stop [i], desaturated and faded like the shader does it.
  Color _tone(int i, [double alpha = 1]) {
    final p = frame.palette;
    final r = p[i * 3];
    final g = p[i * 3 + 1];
    final b = p[i * 3 + 2];
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final k = frame.desat;
    return Color.from(
      alpha: (alpha * frame.opacity).clamp(0.0, 1.0),
      red: r + (lum * 0.8 - r) * k,
      green: g + (lum * 0.85 - g) * k,
      blue: b + (lum * 0.95 - b) * k,
    );
  }

  static Float64List _rotation(Offset c, double angle) {
    return (Matrix4.identity()
          ..translateByDouble(c.dx, c.dy, 0, 1)
          ..rotateZ(angle)
          ..translateByDouble(-c.dx, -c.dy, 0, 1))
        .storage;
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) {
    return !identical(oldDelegate.frame, frame) ||
        oldDelegate.devicePixelRatio != devicePixelRatio;
  }
}
