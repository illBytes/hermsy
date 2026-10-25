import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../presence/presence_engine.dart';
import '../services/biometric_gate.dart';
import '../services/pin_vault.dart';
import '../state/assistant_mood.dart';
import '../theme/app_theme.dart';
import '../widgets/frank_backdrop.dart';
import '../widgets/frank_orb.dart';
import '../widgets/pin_pad.dart';

/// The lock screen. Frank sleeps until you type: each digit wakes the orb a
/// little more. A wrong PIN shakes the dots red; the right one pulls the dots
/// into the orb with a flash, then calls [onUnlocked].
class PinScreen extends StatefulWidget {
  const PinScreen({
    super.key,
    required this.pin,
    required this.onUnlocked,
    this.biometric,
    this.enableHaptics = true,
    this.reduceMotion = false,
    this.lockout = PinLockout.none,
    this.onLockout,
  });

  final StoredPin pin;
  final VoidCallback onUnlocked;

  /// Wrong tries so far and any wait, from before Frank was last closed.
  final PinLockout lockout;

  /// Saves the count and the wait after every try, so closing Frank does
  /// not reset them.
  final ValueChanged<PinLockout>? onLockout;
  final BiometricGate? biometric;
  final bool enableHaptics;

  /// The app's Reduce motion setting (the OS setting is always respected).
  final bool reduceMotion;

  /// Wrong PINs in a row before the pad pauses.
  static const maxAttempts = 5;

  /// The first pause; it doubles with each further miss.
  static const cooldown = Duration(seconds: 30);

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> with TickerProviderStateMixin {
  // The success beat. The dots fly in the first half and the orb flashes as
  // the last ones land (~280ms); the screen hands over at [_unlockAt] while
  // the flash settles under the app's lock-to-chat transition.
  static const _beatDuration = Duration(milliseconds: 560);
  static const _landAt = 0.48;
  static const _unlockAt = 340 / 560;

  // A half-typed PIN stops animating the orb after this long.
  static const _dozeAfter = Duration(seconds: 12);

  String _entered = '';
  String? _error;
  String? _errorDetail;
  BiometricOffer _offer = BiometricOffer.unavailable;
  bool _prompting = false;

  bool _rejecting = false;
  bool _succeeding = false;
  bool _landed = false;

  /// Bumped when the dots land, so the orb plays its own done flash.
  int _orbPulse = 0;
  bool _handedOver = false;
  bool _dozing = false;
  int _misses = 0;
  int _cooldownLeft = 0;
  Timer? _cooldownTimer;
  Timer? _dozeTimer;
  Offset _convergeTo = Offset.zero;

  final _orbKey = GlobalKey();
  final _dotsKey = GlobalKey();

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..addStatusListener(_onShakeStatus);

  // 0 asleep → 1 with every digit in.
  late final AnimationController _wake = AnimationController(vsync: this);

  // A small swell on each digit.
  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: _beatDuration,
  )..addListener(_onBeat);

  late final Animation<double> _flight = CurvedAnimation(
    parent: _beat,
    curve: const Interval(0.06, 0.5),
  );
  late final Animation<double> _chrome = ReverseAnimation(
    CurvedAnimation(
      parent: _beat,
      curve: const Interval(0, 0.32, curve: Curves.easeOut),
    ),
  );
  late final Animation<double> _padFade = ReverseAnimation(
    CurvedAnimation(
      parent: _beat,
      curve: const Interval(0.1, 0.55, curve: Curves.easeOut),
    ),
  );
  late final Animation<double> _padScale = Tween(begin: 1.0, end: 0.96).animate(
    CurvedAnimation(
      parent: _beat,
      curve: const Interval(0.1, 0.55, curve: AppMotion.standard),
    ),
  );

  bool get _coolingDown => _cooldownLeft > 0;

  /// A PIN is being checked (the hash takes a moment).
  bool _checking = false;

  bool get _reduced => widget.reduceMotion || AppMotion.reduced(context);

  @override
  void initState() {
    super.initState();
    _misses = widget.lockout.misses;
    final until = widget.lockout.until;
    if (until != null && until.isAfter(DateTime.now())) {
      // Still waiting from before Frank was closed.
      _error = 'Too many attempts';
      _runCooldown(until.difference(DateTime.now()).inSeconds + 1);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareBiometrics(prompt: true);
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _dozeTimer?.cancel();
    _shake.dispose();
    _wake.dispose();
    _nudge.dispose();
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = _reduced;
    final count = widget.pin.length;
    final awake = _entered.isNotEmpty || _rejecting || _succeeding;

    return FrankBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 680;
              final padHeight = math.min(
                PinPad.size.height,
                constraints.maxHeight * 0.5,
              );
              return Column(
                children: [
                  Expanded(
                    // Sit a little below centre, closer to the pad.
                    child: Align(
                      alignment: const Alignment(0, 0.4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpace.x6,
                              AppSpace.x4,
                              AppSpace.x6,
                              0,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _WakingOrb(
                                  key: _orbKey,
                                  size: compact ? 80 : 96,
                                  wake: _wake,
                                  nudge: _nudge,
                                  beat: _beat,
                                  lit: awake && !_coolingDown,
                                  live: awake && !_dozing,
                                  intense: _entered.length >= count,
                                  error: _rejecting,
                                  reduced: reduced,
                                  pulse: _orbPulse,
                                ),
                                SizedBox(height: compact ? AppSpace.x5 : 28),
                                FadeTransition(
                                  opacity: _chrome,
                                  child: Column(
                                    children: [
                                      Text('Hermsy', style: AppText.display),
                                      const SizedBox(height: 6),
                                      Text(
                                        _subtitle,
                                        textAlign: TextAlign.center,
                                        style: AppText.bodySmall.copyWith(
                                          fontSize: 15,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: compact ? AppSpace.x6 : AppSpace.x8,
                                ),
                                AnimatedOpacity(
                                  opacity: _coolingDown ? 0.4 : 1,
                                  duration: AppMotion.medium,
                                  curve: AppMotion.standard,
                                  child: PinShake(
                                    animation: _shake,
                                    enabled: !reduced,
                                    child: PinDots(
                                      key: _dotsKey,
                                      count: count,
                                      filled: _entered.length,
                                      error: _rejecting,
                                      converge: _succeeding ? _flight : null,
                                      convergeTo: _convergeTo,
                                      reduceMotion: widget.reduceMotion,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpace.x4),
                                FadeTransition(
                                  opacity: _chrome,
                                  child: PinMessage(
                                    text: _coolingDown
                                        ? 'Too many attempts'
                                        : _error,
                                    detail: _coolingDown
                                        ? 'Try again in ${_clock(_cooldownLeft)}'
                                        : _errorDetail,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: padHeight,
                    child: FadeTransition(
                      opacity: _padFade,
                      child: ScaleTransition(
                        scale: _padScale,
                        child: IgnorePointer(
                          ignoring: _succeeding,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.bottomCenter,
                            child: PinPad(
                              onDigit: _onDigit,
                              onDelete: _onDelete,
                              onClear: _onClear,
                              enabled: !_coolingDown,
                              canDelete: _entered.isNotEmpty && !_rejecting,
                              enableHaptics: widget.enableHaptics,
                              biometricIcon: _biometricIcon,
                              biometricLabel: _biometricLabel,
                              onBiometric: _offer == BiometricOffer.unavailable
                                  ? null
                                  : _authenticate,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? AppSpace.x4 : 28),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String get _subtitle {
    switch (_offer) {
      case BiometricOffer.face:
        return 'Use face unlock or enter your PIN';
      case BiometricOffer.fingerprint:
      case BiometricOffer.generic:
        return 'Touch the sensor or enter your PIN';
      case BiometricOffer.unavailable:
        return 'Enter your PIN to unlock';
    }
  }

  IconData? get _biometricIcon {
    switch (_offer) {
      case BiometricOffer.face:
        return Icons.face_unlock_rounded;
      case BiometricOffer.fingerprint:
      case BiometricOffer.generic:
        return Icons.fingerprint_rounded;
      case BiometricOffer.unavailable:
        return null;
    }
  }

  String get _biometricLabel {
    return _offer == BiometricOffer.face
        ? 'Unlock with your face'
        : 'Unlock with fingerprint';
  }

  static String _clock(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  Future<void> _prepareBiometrics({required bool prompt}) async {
    final gate = widget.biometric;
    if (gate == null) {
      return;
    }
    final offer = await gate.probe();
    if (!mounted) {
      return;
    }
    setState(() => _offer = offer);
    if (prompt && offer != BiometricOffer.unavailable) {
      await _authenticate();
    }
  }

  Future<void> _authenticate() async {
    final gate = widget.biometric;
    if (gate == null || _prompting || _succeeding) {
      return;
    }
    setState(() {
      _prompting = true;
      if (!_coolingDown) {
        _error = null;
        _errorDetail = null;
      }
    });
    final ok = await gate.authenticate();
    if (!mounted) {
      return;
    }
    setState(() => _prompting = false);
    if (ok) {
      _succeed();
    }
  }

  void _onDigit(String digit) {
    if (_succeeding || _coolingDown || _checking) {
      return;
    }
    // Typing again cuts a rejection short and starts a fresh entry.
    _finishRejection();
    if (_entered.length >= widget.pin.length) {
      return;
    }
    setState(() {
      _entered += digit;
      _error = null;
      _errorDetail = null;
      _dozing = false;
    });
    _wakeTo(_entered.length / widget.pin.length);
    if (!_reduced) {
      _nudge.forward(from: 0);
    }
    if (_entered.length == widget.pin.length) {
      _submit();
    } else {
      _restartDoze();
    }
  }

  void _onDelete() {
    if (_entered.isEmpty || _succeeding || _rejecting) {
      return;
    }
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = null;
      _errorDetail = null;
      _dozing = false;
    });
    _afterEdit();
  }

  void _onClear() {
    if (_entered.isEmpty || _succeeding || _rejecting) {
      return;
    }
    setState(() {
      _entered = '';
      _error = null;
      _errorDetail = null;
    });
    _afterEdit();
  }

  void _afterEdit() {
    _wakeTo(_entered.length / widget.pin.length);
    if (_entered.isEmpty) {
      _dozeTimer?.cancel();
    } else {
      _restartDoze();
    }
  }

  void _wakeTo(double target) {
    _wake.animateTo(target, duration: AppMotion.long, curve: AppMotion.enter);
  }

  void _restartDoze() {
    _dozeTimer?.cancel();
    _dozeTimer = Timer(_dozeAfter, () {
      if (mounted) {
        setState(() => _dozing = true);
      }
    });
  }

  Future<void> _submit() async {
    _dozeTimer?.cancel();
    _checking = true;
    final ok = await widget.pin.matches(_entered);
    _checking = false;
    if (!mounted) {
      return;
    }
    if (ok) {
      _succeed();
    } else {
      _reject();
    }
  }

  void _reject() {
    _misses++;
    if (widget.enableHaptics) {
      HapticFeedback.heavyImpact();
    }
    PresenceScope.maybeOf(context)?.event(PresenceEvent.error, strength: 0.5);
    final left = PinScreen.maxAttempts - _misses;
    setState(() {
      _rejecting = true;
      _error = 'Wrong PIN';
      _errorDetail = switch (left) {
        2 => 'Two more tries, then a short wait',
        1 => 'One more try, then a short wait',
        _ => null,
      };
    });
    _shake.forward(from: 0);
    if (left <= 0) {
      _startCooldown();
    } else {
      widget.onLockout?.call(PinLockout(misses: _misses));
    }
  }

  void _onShakeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _finishRejection();
    }
  }

  void _finishRejection() {
    if (!_rejecting) {
      return;
    }
    _shake.reset();
    setState(() {
      _rejecting = false;
      _entered = '';
    });
    _wakeTo(0);
  }

  void _startCooldown() {
    final doublings = math.min(_misses - PinScreen.maxAttempts, 7);
    final seconds = PinScreen.cooldown.inSeconds * (1 << doublings);
    widget.onLockout?.call(
      PinLockout(
        misses: _misses,
        until: DateTime.now().add(Duration(seconds: seconds)),
      ),
    );
    _runCooldown(seconds);
  }

  void _runCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownLeft = seconds;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownLeft--;
        if (_cooldownLeft <= 0) {
          timer.cancel();
          _cooldownTimer = null;
          _error = null;
          _errorDetail = null;
        }
      });
    });
  }

  void _succeed() {
    if (_succeeding) {
      return;
    }
    _shake.reset();
    _dozeTimer?.cancel();
    _cooldownTimer?.cancel();
    if (_misses > 0 || widget.lockout.until != null) {
      widget.onLockout?.call(PinLockout.none);
    }
    _misses = 0;
    _measureConvergence();
    setState(() {
      _succeeding = true;
      _rejecting = false;
      // A biometric unlock fills every dot so they can fly in too.
      _entered = '•' * widget.pin.length;
      _error = null;
      _errorDetail = null;
      _cooldownLeft = 0;
      _dozing = false;
    });
    _wakeTo(1);
    _beat.forward(from: 0);
  }

  /// Where the orb's centre sits relative to the centre of the dots row.
  void _measureConvergence() {
    final orb = _orbKey.currentContext?.findRenderObject();
    final dots = _dotsKey.currentContext?.findRenderObject();
    if (orb is! RenderBox ||
        dots is! RenderBox ||
        !orb.hasSize ||
        !dots.hasSize) {
      return;
    }
    final target = orb.localToGlobal(orb.size.center(Offset.zero));
    _convergeTo = dots.globalToLocal(target) - dots.size.center(Offset.zero);
  }

  void _onBeat() {
    final t = _beat.value;
    if (!_landed && t >= _landAt) {
      _landed = true;
      setState(() => _orbPulse++);
      if (widget.enableHaptics) {
        HapticFeedback.mediumImpact();
      }
    }
    if (!_handedOver && t >= _unlockAt) {
      _handedOver = true;
      widget.onUnlocked();
    }
  }
}

/// The 96dp hero orb. Asleep it is dim, slightly small and still; each digit
/// raises an aurora halo and swells it a touch, and on success it flashes
/// gold with a ring that rolls outward.
class _WakingOrb extends StatelessWidget {
  const _WakingOrb({
    super.key,
    required this.size,
    required this.wake,
    required this.nudge,
    required this.beat,
    required this.lit,
    required this.live,
    required this.intense,
    required this.error,
    required this.reduced,
    this.pulse = 0,
  });

  final double size;
  final Animation<double> wake;
  final Animation<double> nudge;
  final Animation<double> beat;
  final bool lit;
  final bool live;
  final bool intense;
  final bool error;
  final bool reduced;

  /// Change to play the orb's one-shot flash (the dots landing).
  final int pulse;

  @override
  Widget build(BuildContext context) {
    final glowInset = -size * 0.75;
    return SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: glowInset,
              top: glowInset,
              right: glowInset,
              bottom: glowInset,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _HaloPainter(
                    wake: wake,
                    nudge: nudge,
                    radius: size / 2,
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: Listenable.merge([wake, nudge, beat]),
              builder: (context, child) {
                return Transform.scale(scale: _scale, child: child);
              },
              child: FrankOrb(
                size: size,
                lit: lit,
                live: live,
                intense: intense,
                mood: error ? AssistantMood.error : null,
                level: wake,
                pulse: pulse,
              ),
            ),
            Positioned(
              left: glowInset,
              top: glowInset,
              right: glowInset,
              bottom: glowInset,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _FlashPainter(
                    beat: beat,
                    radius: size / 2,
                    reduced: reduced,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get _scale {
    if (reduced) {
      return 1;
    }
    final swell = math.sin(math.pi * nudge.value);
    final b = beat.value;
    final flare = AppMotion.flight.transform(_span(b, 0.34, 0.54));
    final settle = Curves.easeOut.transform(_span(b, 0.54, 1));
    return 0.94 +
        0.06 * wake.value +
        0.035 * swell +
        0.1 * flare -
        0.04 * settle;
  }
}

/// Progress of [t] through [begin, end], clamped to 0–1.
double _span(double t, double begin, double end) {
  return ((t - begin) / (end - begin)).clamp(0.0, 1.0);
}

/// A soft two-tone aurora halo around the orb that grows as Frank wakes.
class _HaloPainter extends CustomPainter {
  _HaloPainter({required this.wake, required this.nudge, required this.radius})
    : super(repaint: Listenable.merge([wake, nudge]));

  final Animation<double> wake;
  final Animation<double> nudge;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final swell = math.sin(math.pi * nudge.value);
    final strength = (0.5 * wake.value + 0.18 * swell).clamp(0.0, 0.7);
    if (strength < 0.004) {
      return;
    }
    final center = size.center(Offset.zero);
    final reach = radius * (1.55 + 0.25 * wake.value);
    final shift = Offset(radius * 0.12, radius * 0.12);
    _blob(
      canvas,
      center - shift,
      reach,
      AppColors.ion,
      AppColors.azure,
      strength,
    );
    _blob(
      canvas,
      center + shift,
      reach,
      AppColors.iris,
      AppColors.orchid,
      strength * 0.8,
    );
  }

  void _blob(
    Canvas canvas,
    Offset center,
    double reach,
    Color inner,
    Color outer,
    double s,
  ) {
    final rim = radius / reach;
    final shader = RadialGradient(
      colors: [
        inner.withValues(alpha: 0.42 * s),
        inner.withValues(alpha: 0.3 * s),
        outer.withValues(alpha: 0.12 * s),
        outer.withValues(alpha: 0),
      ],
      stops: [rim * 0.9, rim * 1.12, rim * 1.4, 1],
    ).createShader(Rect.fromCircle(center: center, radius: reach));
    canvas.drawCircle(
      center,
      reach,
      Paint()
        ..blendMode = AppColors.glowBlend
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_HaloPainter oldDelegate) {
    return oldDelegate.wake != wake ||
        oldDelegate.nudge != nudge ||
        oldDelegate.radius != radius;
  }
}

/// The unlock flash: a white-gold bloom over the orb as the dots land, and a
/// thin gold ring rolling outward (no ring when motion is reduced).
class _FlashPainter extends CustomPainter {
  _FlashPainter({
    required this.beat,
    required this.radius,
    required this.reduced,
  }) : super(repaint: beat);

  final Animation<double> beat;
  final double radius;
  final bool reduced;

  @override
  void paint(Canvas canvas, Size size) {
    final b = beat.value;
    if (b <= 0.34 || b >= 1) {
      return;
    }
    final center = size.center(Offset.zero);
    final rise = Curves.easeOut.transform(_span(b, 0.34, 0.5));
    final fall = Curves.easeOut.transform(_span(b, 0.5, 1));
    final flash = rise * (1 - fall);
    if (flash > 0.004) {
      final reach = radius * (reduced ? 1.3 : 1.1 + 0.55 * flash);
      canvas.drawCircle(
        center,
        reach,
        Paint()
          ..blendMode = AppColors.glowBlend
          ..shader = RadialGradient(
            colors: [
              AppColors.whiteHot.withValues(alpha: 0.85 * flash),
              AppColors.goldBright.withValues(alpha: 0.5 * flash),
              AppColors.gold.withValues(alpha: 0.16 * flash),
              AppColors.gold.withValues(alpha: 0),
            ],
            stops: const [0, 0.32, 0.68, 1],
          ).createShader(Rect.fromCircle(center: center, radius: reach)),
      );
    }
    if (reduced) {
      return;
    }
    final roll = _span(b, 0.4, 0.95);
    if (roll <= 0 || roll >= 1) {
      return;
    }
    final ring = radius * (1 + 1.25 * Curves.easeOutCubic.transform(roll));
    final alpha = math.pow(1 - roll, 1.6).toDouble();
    canvas.drawCircle(
      center,
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
        ..color = AppColors.gold.withValues(alpha: 0.28 * alpha),
    );
    canvas.drawCircle(
      center,
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = AppColors.goldBright.withValues(alpha: 0.55 * alpha),
    );
  }

  @override
  bool shouldRepaint(_FlashPainter oldDelegate) {
    return oldDelegate.beat != beat ||
        oldDelegate.radius != radius ||
        oldDelegate.reduced != reduced;
  }
}
