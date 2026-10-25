import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui/frank_ui.dart';

/// A voice message: a 56dp pill with a play/stop button, the label, and a
/// 32-bar waveform. The bars are drawn from a stable hash of [seed], so a
/// note always has the same shape; while it plays a highlight travels
/// across them.
class VoiceNoteCard extends StatelessWidget {
  const VoiceNoteCard({
    super.key,
    required this.playing,
    required this.onPlay,
    this.label = 'Voice reply',
    this.seed,
    this.mine = false,
  });

  final bool playing;
  final VoidCallback? onPlay;
  final String label;

  /// Shapes the waveform (the message id). Defaults to [label].
  final String? seed;

  /// The user's own note (sits inside their bubble): a neutral button and
  /// gold playback light. Frank's replies get the gold button, a pill of
  /// their own, and the speaking palette.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final status = playing ? 'Playing' : 'Tap to play';
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlayButton(playing: playing, mine: mine),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: AppMotion.short,
                    child: Text(
                      status,
                      key: ValueKey(status),
                      style: AppText.caption.copyWith(
                        color: playing ? AppColors.secondary : AppColors.hint,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              _Waveform(
                seed: seed ?? label,
                playing: playing,
                highlight: mine ? _goldLight : AppSpectrum.speaking,
              ),
            ],
          ),
        ),
      ],
    );

    return Pressable(
      onTap: onPlay,
      pressedScale: 0.98,
      semanticLabel: '$label, $status',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: mine
              ? const EdgeInsets.symmetric(vertical: 2)
              : const EdgeInsets.fromLTRB(10, 9, 18, 9),
          decoration: mine
              ? null
              : BoxDecoration(
                  color: AppColors.veil(0x0A),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: AppColors.hairline),
                ),
          child: content,
        ),
      ),
    );
  }

  static List<Color> get _goldLight => [
    AppColors.goldBright,
    AppColors.gold,
    AppColors.goldDeep,
    AppColors.gold,
  ];
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.mine});

  final bool playing;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final glyph = mine ? AppColors.text : AppColors.onGold;
    return AnimatedContainer(
      duration: AppMotion.short,
      curve: AppMotion.standard,
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: mine ? AppColors.veil(0x14) : null,
        gradient: mine ? null : AppGradients.gold,
        boxShadow: !mine && playing
            ? [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: -2,
                ),
              ]
            : const [],
      ),
      child: AnimatedSwitcher(
        duration: AppMotion.quick,
        transitionBuilder: (child, animation) {
          return ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: Icon(
          playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
          key: ValueKey(playing),
          size: playing ? 20 : 22,
          color: glyph,
        ),
      ),
    );
  }
}

/// 32 bars, 2dp wide with 2dp gaps. Static unless [playing].
class _Waveform extends StatefulWidget {
  const _Waveform({
    required this.seed,
    required this.playing,
    required this.highlight,
  });

  final String seed;
  final bool playing;
  final List<Color> highlight;

  static const bars = 32;
  static const width = bars * 4.0 - 2;
  static const height = 18.0;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late List<double> _levels = _levelsFor(widget.seed);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Waveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed) {
      _levels = _levelsFor(widget.seed);
    }
    _sync();
  }

  void _sync() {
    final run = widget.playing && !AppMotion.reduced(context);
    if (run && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!run && _sweep.isAnimating) {
      _sweep
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(_Waveform.width, _Waveform.height),
        painter: _WaveformPainter(
          levels: _levels,
          sweep: _sweep,
          playing: widget.playing,
          animated: widget.playing && !AppMotion.reduced(context),
          highlight: widget.highlight,
        ),
      ),
    );
  }

  /// FNV-1a over the seed drives a small LCG; neighbours are smoothed and
  /// the ends taper so it reads like speech, not noise.
  static List<double> _levelsFor(String seed) {
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    var state = hash == 0 ? 1 : hash;
    double next() {
      state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
      return state / 0x7FFFFFFF;
    }

    final raw = [for (var i = 0; i < _Waveform.bars; i++) next()];
    return [
      for (var i = 0; i < _Waveform.bars; i++)
        () {
          final left = raw[math.max(0, i - 1)];
          final right = raw[math.min(_Waveform.bars - 1, i + 1)];
          final smooth = raw[i] * 0.5 + (left + right) * 0.25;
          final t = i / (_Waveform.bars - 1);
          final taper = 0.45 + 0.55 * math.sin(math.pi * t);
          return (0.18 + smooth * 0.82 * taper).clamp(0.12, 1.0);
        }(),
    ];
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.levels,
    required this.sweep,
    required this.playing,
    required this.animated,
    required this.highlight,
  }) : super(repaint: sweep);

  final List<double> levels;
  final Animation<double> sweep;
  final bool playing;
  final bool animated;
  final List<Color> highlight;

  static Color get _rest => AppColors.veil(0x47);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final count = levels.length;
    final centre = -0.25 + sweep.value * 1.5;
    for (var i = 0; i < count; i++) {
      final t = i / (count - 1);
      final h = math.max(3.0, levels[i] * size.height);
      double light;
      if (!playing) {
        light = 0;
      } else if (!animated) {
        light = 0.75;
      } else {
        final d = (t - centre) / 0.16;
        light = math.exp(-d * d);
      }
      final tint = _paletteAt(t);
      paint.color = Color.lerp(_rest, tint, playing ? 0.35 + light * 0.65 : 0)!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(i * 4.0 + 1, size.height / 2),
            width: 2,
            height: h * (1 + light * 0.12),
          ),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  Color _paletteAt(double t) {
    final scaled = t * (highlight.length - 1);
    final index = scaled.floor().clamp(0, highlight.length - 2);
    return Color.lerp(highlight[index], highlight[index + 1], scaled - index)!;
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.playing != playing ||
        oldDelegate.animated != animated ||
        oldDelegate.levels != levels ||
        oldDelegate.highlight != highlight;
  }
}
