import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Text with a soft highlight sweeping across it, for live states like
/// "Thinking" or "Transcribing". Static when the OS asks for less motion.
class ShimmerText extends StatefulWidget {
  const ShimmerText(
    this.text, {
    super.key,
    this.style,
    this.highlight,
    this.period = const Duration(milliseconds: 1400),
    this.enabled = true,
    this.maxLines = 1,
  });

  final String text;

  /// Defaults to [AppText.label].
  final TextStyle? style;

  /// Defaults to white on dark, the gold on light.
  final Color? highlight;
  final Duration period;
  final bool enabled;
  final int maxLines;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ShimmerText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _sweep.duration = widget.period;
    }
    _sync();
  }

  void _sync() {
    final run = widget.enabled && !AppMotion.reduced(context);
    if (run && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!run && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      style: widget.style ?? AppText.label,
    );
    if (!widget.enabled || AppMotion.reduced(context)) {
      return text;
    }
    final base = (widget.style ?? AppText.label).color ?? AppColors.text;
    // The sweep loops while its busy state shows: keep those repaints off
    // the rest of the screen.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _sweep,
        builder: (context, child) {
          final t = _sweep.value * 2.4 - 0.7;
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  base,
                  widget.highlight ??
                      (AppColors.isDark ? Colors.white : AppColors.goldBright),
                  base,
                ],
                stops: [
                  (t - 0.25).clamp(0.0, 1.0),
                  t.clamp(0.0, 1.0),
                  (t + 0.25).clamp(0.0, 1.0),
                ],
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: text,
      ),
    );
  }
}
