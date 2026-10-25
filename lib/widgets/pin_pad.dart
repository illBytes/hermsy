import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Frank's PIN keypad: 72dp glass keys in a phone-keypad grid, sized for the
/// thumb. A key lights the moment it is touched and lingers a thin gold ring
/// after release, so even a quick tap reads.
///
/// The pad has a fixed natural [size]; wrap it in a [FittedBox] to let it
/// shrink on short screens.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onDelete,
    this.onClear,
    this.biometricIcon,
    this.onBiometric,
    this.biometricLabel = 'Use biometrics',
    this.enableHaptics = true,
    this.enabled = true,
    this.canDelete = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;

  /// Long-pressing delete clears every digit.
  final VoidCallback? onClear;
  final IconData? biometricIcon;
  final VoidCallback? onBiometric;
  final String biometricLabel;
  final bool enableHaptics;

  /// False dims the digits and delete and ignores them (a cooldown). The
  /// biometric key stays usable.
  final bool enabled;

  /// False fades the delete key away (there is nothing to delete).
  final bool canDelete;

  static const keySize = 72.0;
  static const columnGap = 28.0;
  static const rowGap = 16.0;

  /// The pad's natural size.
  static const size = Size(
    keySize * 3 + columnGap * 2,
    keySize * 4 + rowGap * 3,
  );

  static TextStyle get _digitStyle => TextStyle(
    color: AppColors.text,
    fontSize: 28,
    height: 1,
    fontWeight: FontWeight.w400,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    Widget digit(String value) {
      return _Dimmed(
        opacity: enabled ? 1 : 0.3,
        child: _PadKey(
          semanticLabel: value,
          enabled: enabled,
          enableHaptics: enableHaptics,
          onTap: () => onDigit(value),
          child: Text(value, style: _digitStyle),
        ),
      );
    }

    final biometric = biometricIcon == null || onBiometric == null
        ? const SizedBox.square(dimension: keySize)
        : Tooltip(
            message: biometricLabel,
            excludeFromSemantics: true,
            child: _PadKey(
              semanticLabel: biometricLabel,
              filled: false,
              enableHaptics: enableHaptics,
              onTap: onBiometric!,
              child: Icon(biometricIcon, color: AppColors.ion, size: 30),
            ),
          );

    final showDelete = canDelete;
    final delete = _Dimmed(
      opacity: !showDelete ? 0 : (enabled ? 1 : 0.3),
      child: IgnorePointer(
        ignoring: !showDelete,
        child: ExcludeSemantics(
          excluding: !showDelete,
          child: Tooltip(
            message: 'Delete',
            excludeFromSemantics: true,
            // A long press clears the PIN, so it must not also open the tip.
            triggerMode: onClear == null ? null : TooltipTriggerMode.manual,
            child: _PadKey(
              semanticLabel: 'Delete',
              filled: false,
              enabled: enabled,
              enableHaptics: enableHaptics,
              onTap: onDelete,
              onLongPress: onClear == null
                  ? null
                  : () {
                      if (enableHaptics) {
                        HapticFeedback.mediumImpact();
                      }
                      onClear!();
                    },
              child: Icon(
                Icons.backspace_rounded,
                color: AppColors.secondary,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );

    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    Widget row(List<Widget> keys) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: keys,
      );
    }

    // Keys are fixed circles; past this the digits would outgrow them.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SizedBox.fromSize(
        size: size,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final keys in rows) row([for (final key in keys) digit(key)]),
            row([biometric, digit('0'), delete]),
          ],
        ),
      ),
    );
  }
}

class _Dimmed extends StatelessWidget {
  const _Dimmed({required this.opacity, required this.child});

  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: opacity,
      duration: AppMotion.short,
      curve: AppMotion.standard,
      child: child,
    );
  }
}

class _PadKey extends StatefulWidget {
  const _PadKey({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.filled = true,
    this.enabled = true,
    this.enableHaptics = true,
  });

  final String semanticLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  /// Digit keys sit on a faint glass disc; function keys are bare.
  final bool filled;
  final bool enabled;
  final bool enableHaptics;

  @override
  State<_PadKey> createState() => _PadKeyState();
}

class _PadKeyState extends State<_PadKey> with SingleTickerProviderStateMixin {
  // 1 while touched. On release it holds for ~140ms, then fades.
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  static const _linger = Interval(0.35, 1, curve: Curves.easeOut);

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    if (widget.enabled) {
      _press.value = 1;
    }
  }

  void _up(PointerEvent event) {
    if (_press.value > 0) {
      _press.animateTo(0, curve: _linger);
    }
  }

  void _tap() {
    if (widget.enableHaptics) {
      HapticFeedback.selectionClick();
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? _tap : null,
          onLongPress: widget.enabled ? widget.onLongPress : null,
          child: CustomPaint(
            painter: _KeyPainter(press: _press, filled: widget.filled),
            child: SizedBox.square(
              dimension: PinPad.keySize,
              child: Center(child: ExcludeSemantics(child: widget.child)),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyPainter extends CustomPainter {
  _KeyPainter({required this.press, required this.filled})
      : super(repaint: press);

  final Animation<double> press;
  final bool filled;

  static Color get _rest => AppColors.veil(0x08);
  static const _bare = Color(0x00FFFFFF);
  static Color get _pressed => AppColors.veil(0x1A);

  @override
  void paint(Canvas canvas, Size size) {
    final p = press.value;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final fill = Color.lerp(filled ? _rest : _bare, _pressed, p)!;
    if (fill.a > 0) {
      canvas.drawCircle(center, radius, Paint()..color = fill);
    }
    if (p > 0.01) {
      canvas.drawCircle(
        center,
        radius - 0.6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.gold.withValues(alpha: 0.6 * p),
      );
    }
  }

  @override
  bool shouldRepaint(_KeyPainter oldDelegate) {
    return oldDelegate.filled != filled || oldDelegate.press != press;
  }
}

/// PIN progress: rings that fill with Hermes gold and pop as digits land,
/// flash red on a rejected PIN, and arc into [convergeTo] on success.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.count,
    required this.filled,
    this.strongCount,
    this.error = false,
    this.converge,
    this.convergeTo = Offset.zero,
    this.reduceMotion = false,
  });

  final int count;
  final int filled;

  /// How many leading rings are required digits, drawn with a firmer stroke;
  /// the rest are optional and fainter. Defaults to all of them.
  final int? strongCount;

  /// Filled dots turn signal red.
  final bool error;

  /// The success flight, 0 → 1. The inner dots lead; each one gathers toward
  /// the centre, then lifts into [convergeTo], shrinking as it is absorbed.
  final Animation<double>? converge;

  /// Where the dots converge, relative to the centre of the row.
  final Offset convergeTo;

  /// The app's Reduce motion setting (the OS setting is always respected).
  final bool reduceMotion;

  static const dotSize = 12.0;
  static const gap = 18.0;

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotion || AppMotion.reduced(context);
    final strong = strongCount ?? count;
    final flight = converge;
    return Semantics(
      label: strong >= count
          ? '$filled of $count digits entered'
          : '$filled digits entered',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            _flying(
              index: i,
              flight: flight,
              reduced: reduced,
              child: _PinDot(
                filled: i < filled,
                error: error,
                strong: i < strong,
                reduced: reduced,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _flying({
    required int index,
    required Animation<double>? flight,
    required bool reduced,
    required Widget child,
  }) {
    if (flight == null) {
      return child;
    }
    final mid = (count - 1) / 2;
    final spread = mid == 0 ? 0.0 : (index - mid).abs() / mid;
    final delay = 0.22 * spread;
    final window = Interval(delay, delay + 0.78);
    final home = Offset((index - mid) * (dotSize + gap), 0);
    return AnimatedBuilder(
      animation: flight,
      builder: (context, child) {
        final p = window.transform(flight.value);
        if (p == 0) {
          return child!;
        }
        if (reduced) {
          return Opacity(opacity: 1 - p, child: child);
        }
        final travel = convergeTo - home;
        final offset = Offset(
          travel.dx * Curves.easeInOutCubic.transform(p),
          travel.dy * Curves.easeInCubic.transform(p),
        );
        final scale = 1 - 0.55 * Curves.easeIn.transform(p);
        final opacity = 1 - const Interval(0.7, 1).transform(p);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: offset,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

class _PinDot extends StatefulWidget {
  const _PinDot({
    required this.filled,
    required this.error,
    required this.strong,
    required this.reduced,
  });

  final bool filled;
  final bool error;
  final bool strong;
  final bool reduced;

  @override
  State<_PinDot> createState() => _PinDotState();
}

class _PinDotState extends State<_PinDot> with TickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: AppMotion.quick,
    value: widget.filled ? 1 : 0,
  );

  // 0 gold, 1 signal red.
  late final AnimationController _tint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    value: widget.filled && widget.error ? 1 : 0,
  );

  static final _pop = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.6, end: 1.15).chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 55,
    ),
  ]);

  static final _gold = BoxDecoration(
    shape: BoxShape.circle,
    gradient: AppGradients.gold,
    boxShadow: [
      BoxShadow(color: AppColors.gold.withValues(alpha: 0.55), blurRadius: 8),
    ],
  );

  static final _red = BoxDecoration(
    shape: BoxShape.circle,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.danger, AppColors.signal, AppColors.signal],
      stops: const [0, 0.55, 1],
    ),
    boxShadow: [
      BoxShadow(color: AppColors.signal.withValues(alpha: 0.6), blurRadius: 8),
    ],
  );

  @override
  void didUpdateWidget(covariant _PinDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filled != oldWidget.filled) {
      if (widget.filled) {
        // A fresh digit lands in the right color; no red-to-gold blend.
        _tint.value = widget.error ? 1 : 0;
        if (widget.reduced) {
          _fill.forward();
        } else {
          _fill.forward(from: 0);
        }
      } else {
        // Empty in whatever color it had, so a red dot leaves red.
        _fill.reverse();
      }
    } else if (widget.filled && widget.error != oldWidget.error) {
      if (widget.error) {
        _tint.forward();
      } else {
        _tint.reverse();
      }
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    _tint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: PinDots.dotSize,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.strong ? AppColors.strokeStrong : AppColors.hairline,
                width: 1.5,
              ),
            ),
          ),
          AnimatedBuilder(
            animation: Listenable.merge([_fill, _tint]),
            builder: (context, child) {
              final v = _fill.value;
              if (v == 0) {
                return const SizedBox.shrink();
              }
              final leaving = _fill.status == AnimationStatus.reverse;
              final double scale;
              final double opacity;
              if (widget.reduced) {
                scale = 1;
                opacity = v;
              } else if (leaving) {
                scale = 0.5 + 0.5 * v;
                opacity = v;
              } else {
                scale = _pop.transform(v);
                opacity = math.min(1, v / 0.3);
              }
              return Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: DecoratedBox(
                    decoration: BoxDecoration.lerp(_gold, _red, _tint.value)!,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Shakes its child sideways with a damped wobble, for a rejected PIN.
class PinShake extends StatelessWidget {
  const PinShake({
    super.key,
    required this.animation,
    required this.child,
    this.enabled = true,
  });

  /// Runs 0 → 1 once per rejection.
  final Animation<double> animation;
  final Widget child;

  /// False keeps the child still (reduce motion).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        final dx = math.sin(t * math.pi * 7) * 14 * math.pow(1 - t, 2);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: child,
    );
  }
}

/// The line under the PIN dots: a message and an optional quieter detail.
/// It reserves its height up front so nothing above it moves when it shows.
class PinMessage extends StatelessWidget {
  const PinMessage({
    super.key,
    this.text,
    this.detail,
    this.lines = 2,
  });

  final String? text;
  final String? detail;

  /// Lines to reserve (1 or 2).
  final int lines;

  static TextStyle get _textStyle => TextStyle(
    color: AppColors.danger,
    fontSize: 15,
    height: 1.33,
    fontWeight: FontWeight.w500,
  );

  static final _detailStyle = AppText.bodySmall.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final message = text;
    return Semantics(
      liveRegion: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: lines * 22.0),
        child: AnimatedSwitcher(
          duration: AppMotion.short,
          switchInCurve: AppMotion.enter,
          switchOutCurve: AppMotion.exit,
          layoutBuilder: (current, previous) {
            return Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            );
          },
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, -0.12),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: message == null
              ? const SizedBox.shrink(key: ValueKey('none'))
              : Column(
                  key: ValueKey(message),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, style: _textStyle, textAlign: TextAlign.center),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(detail!, style: _detailStyle, textAlign: TextAlign.center),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
