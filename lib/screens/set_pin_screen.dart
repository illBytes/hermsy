import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/frank_backdrop.dart';
import '../widgets/frank_orb.dart';
import '../widgets/pin_pad.dart';
import '../widgets/ui/frank_ui.dart';

/// Creates (or changes) the PIN in two steps: choose it, then confirm it.
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({
    super.key,
    required this.onSaved,
    this.onCancel,
    this.title = 'Create a PIN',
    this.enableHaptics = true,
    this.reduceMotion = false,
  });

  final ValueChanged<String> onSaved;

  /// Shows a close button (changing an existing PIN).
  final VoidCallback? onCancel;

  /// The first step's title.
  final String title;
  final bool enableHaptics;

  /// The app's Reduce motion setting (the OS setting is always respected).
  final bool reduceMotion;

  static const minLength = 4;
  static const maxLength = 8;

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen>
    with SingleTickerProviderStateMixin {
  String _first = '';
  String _entered = '';
  bool _confirming = false;
  bool _rejecting = false;

  // Which way the step header slides: forward into step 2, back to step 1.
  bool _forward = true;
  String? _error;

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _startOver();
      }
    });

  int get _step => _confirming ? 2 : 1;

  // Confirming shows exactly as many dots as the PIN being confirmed.
  int get _slots => _confirming ? _first.length : SetPinScreen.maxLength;

  bool get _canContinue => _confirming
      ? _entered.length == _first.length
      : _entered.length >= SetPinScreen.minLength;

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = widget.reduceMotion || AppMotion.reduced(context);
    final cta = _confirming ? 'Save PIN' : 'Continue';

    return FrankBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              final padHeight = math.min(
                PinPad.size.height,
                constraints.maxHeight * 0.46,
              );
              return Column(
                children: [
                  SizedBox(
                    height: widget.onCancel == null ? AppSpace.x4 : AppSpace.x14,
                    child: widget.onCancel == null
                        ? null
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: AppSpace.x1),
                              child: FrankIconButton(
                                icon: Icons.close_rounded,
                                tooltip: 'Cancel',
                                onPressed: widget.onCancel,
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    // Sit a little below centre, closer to the pad.
                    child: Align(
                      alignment: const Alignment(0, 0.3),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.x6,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FrankOrb(size: compact ? 52 : 64),
                                SizedBox(height: compact ? AppSpace.x4 : AppSpace.x6),
                                _StepHeader(
                                  step: _step,
                                  forward: _forward,
                                  reduced: reduced,
                                  title: _confirming ? 'Confirm your PIN' : widget.title,
                                  subtitle: _confirming
                                      ? 'Enter the same PIN again'
                                      : 'Choose a ${SetPinScreen.minLength}–'
                                          '${SetPinScreen.maxLength} digit PIN',
                                ),
                                SizedBox(height: compact ? AppSpace.x6 : AppSpace.x8),
                                PinShake(
                                  animation: _shake,
                                  enabled: !reduced,
                                  child: AnimatedSwitcher(
                                    duration: AppMotion.short,
                                    switchInCurve: AppMotion.standard,
                                    switchOutCurve: AppMotion.standard,
                                    child: PinDots(
                                      key: ValueKey(_slots),
                                      count: _slots,
                                      filled: _entered.length,
                                      strongCount: _confirming
                                          ? _slots
                                          : SetPinScreen.minLength,
                                      error: _rejecting,
                                      reduceMotion: widget.reduceMotion,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpace.x4),
                                PinMessage(text: _error, lines: 1),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 52,
                    child: _Reveal(
                      reduced: reduced,
                      child: _canContinue && !_rejecting
                          ? SizedBox(
                              key: ValueKey(cta),
                              width: PinPad.size.width,
                              child: GoldButton(label: cta, onPressed: _continue),
                            )
                          : const SizedBox.shrink(key: ValueKey('none')),
                    ),
                  ),
                  SizedBox(height: compact ? AppSpace.x4 : AppSpace.x6),
                  SizedBox(
                    height: padHeight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomCenter,
                      child: PinPad(
                        onDigit: _onDigit,
                        onDelete: _onDelete,
                        onClear: _onClear,
                        canDelete: _entered.isNotEmpty && !_rejecting,
                        enableHaptics: widget.enableHaptics,
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

  void _onDigit(String digit) {
    // Typing again cuts a mismatch short and starts over from step 1.
    if (_rejecting) {
      _shake.reset();
      _startOver();
    }
    if (_entered.length >= _slots) {
      return;
    }
    setState(() {
      _entered += digit;
      _error = null;
    });
  }

  void _onDelete() {
    if (_entered.isEmpty || _rejecting) {
      return;
    }
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = null;
    });
  }

  void _onClear() {
    if (_entered.isEmpty || _rejecting) {
      return;
    }
    setState(() {
      _entered = '';
      _error = null;
    });
  }

  void _continue() {
    if (!_canContinue || _rejecting) {
      return;
    }
    if (!_confirming) {
      _tap(HapticFeedback.lightImpact);
      setState(() {
        _first = _entered;
        _entered = '';
        _confirming = true;
        _forward = true;
        _error = null;
      });
      return;
    }
    if (_entered != _first) {
      _tap(HapticFeedback.heavyImpact);
      setState(() {
        _rejecting = true;
        _error = "PINs didn't match. Start again.";
      });
      _shake.forward(from: 0);
      return;
    }
    _tap(HapticFeedback.lightImpact);
    widget.onSaved(_entered);
  }

  /// Back to step 1 after a mismatch.
  void _startOver() {
    if (!_rejecting) {
      return;
    }
    setState(() {
      _rejecting = false;
      _entered = '';
      _first = '';
      _confirming = false;
      _forward = false;
    });
  }

  void _tap(Future<void> Function() feedback) {
    if (widget.enableHaptics) {
      feedback();
    }
  }
}

/// 'STEP 1 OF 2', the title and the subtitle, sliding sideways between steps.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.forward,
    required this.reduced,
    required this.title,
    required this.subtitle,
  });

  final int step;
  final bool forward;
  final bool reduced;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final current = ValueKey(step);
    return AnimatedSwitcher(
      duration: AppMotion.medium,
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) {
        if (reduced) {
          return FadeTransition(opacity: animation, child: child);
        }
        // The new step arrives from the direction of travel; the old one
        // leaves the other way.
        final incoming = child.key == current;
        final side = (incoming ? 1.0 : -1.0) * (forward ? 1.0 : -1.0);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: Offset(0.08 * side, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Column(
        key: current,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('STEP $step OF 2', style: AppText.micro),
          const SizedBox(height: 10),
          Text(title, style: AppText.largeTitle, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppText.bodySmall.copyWith(fontSize: 15, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Fades its child in while it rises 8dp, and reverses that on the way out.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.child, required this.reduced});

  final Widget child;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.short,
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) {
        if (reduced) {
          return FadeTransition(opacity: animation, child: child);
        }
        return FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, 8 * (1 - animation.value)),
                child: child,
              );
            },
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
