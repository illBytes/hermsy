import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../presence/presence_engine.dart';
import '../state/assistant_mood.dart';
import '../theme/app_theme.dart';
import 'frank_orb.dart';
import 'ui/frank_ui.dart';

/// How the mic is being held. The composer publishes it so the stage can say
/// "Release to send" or "Tap send when you're done".
enum VoiceCapture {
  /// Unknown or not recording from the composer.
  none,

  /// A finger is on the mic; letting go sends.
  holding,

  /// Recording hands-free until Send or Cancel.
  handsFree,
}

/// The voice takeover above the composer while Frank listens: a large
/// reactive orb, the live transcript (on-device) or a timer, and a hint.
///
/// The chat screen stacks it over the message list; it ignores touches
/// outside its own controls and animates in and out with [active].
class ListeningStage extends StatefulWidget {
  const ListeningStage({
    super.key,
    required this.active,
    required this.level,
    this.transcript,
    this.onDevice = false,
    this.transcribing = false,
    this.capture,
  });

  final bool active;
  final ValueListenable<double> level;
  final ValueListenable<String>? transcript;
  final bool onDevice;
  final bool transcribing;

  /// Pass the same notifier as [ComposerBar.capture] for a precise hint.
  final ValueListenable<VoiceCapture>? capture;

  @override
  State<ListeningStage> createState() => _ListeningStageState();
}

class _ListeningStageState extends State<ListeningStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
    reverseDuration: AppMotion.short,
    value: widget.active ? 1 : 0,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _show,
    curve: AppMotion.enter,
    reverseCurve: AppMotion.exit.flipped,
  );

  @override
  void didUpdateWidget(covariant ListeningStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _show.forward();
      } else {
        _show.reverse();
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _show.dispose();
    super.dispose();
  }

  bool get _calm {
    return AppMotion.reduced(context) ||
        (PresenceScope.maybeOf(context)?.settings?.reduceMotion ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final calm = _calm;
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        if (_show.isDismissed) {
          return const SizedBox.shrink();
        }
        final t = _curve.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, calm ? 0 : (1 - t) * 24),
            child: child,
          ),
        );
      },
      child: IgnorePointer(child: _content()),
    );
  }

  Widget _content() {
    final transcribing = widget.transcribing;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          // The bottom inset keeps the composer's hold hint lane clear.
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 36),
          child: DecoratedBox(
            // A soft pool of dark under the orb and its words, so they
            // never compete with the dimmed thread behind them.
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.72,
                colors: [
                  AppColors.background.withValues(alpha: 0.92),
                  AppColors.background.withValues(alpha: 0.7),
                  AppColors.background.withValues(alpha: 0),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RepaintBoundary(
                    child: FrankOrb(
                      size: 120,
                      live: true,
                      listening: !transcribing,
                      mood: transcribing
                          ? AssistantMood.transcribing
                          : AssistantMood.listening,
                      level: widget.level,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _status(transcribing),
                  const SizedBox(height: 12),
                  _hint(transcribing),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _status(bool transcribing) {
    final transcript = widget.transcript;
    if (widget.onDevice && transcript != null) {
      return ValueListenableBuilder<String>(
        valueListenable: transcript,
        builder: (context, words, _) {
          return _TranscriptBox(
            words: words.trim(),
            placeholder: const _ListeningLine(),
          );
        },
      );
    }
    return AnimatedSwitcher(
      duration: AppMotion.short,
      child: transcribing
          ? ShimmerText(
              'Transcribing',
              key: const ValueKey('transcribing'),
              style: _statusStyle.copyWith(color: AppColors.secondary),
              highlight: AppColors.whiteHot,
            )
          : const _ListeningLine(key: ValueKey('listening')),
    );
  }

  Widget _hint(bool transcribing) {
    final capture = widget.capture;
    Widget build(VoiceCapture mode) {
      final text = transcribing
          ? 'One moment'
          : switch (mode) {
              VoiceCapture.holding => 'Release to send',
              VoiceCapture.handsFree => 'Tap send when you\'re done',
              VoiceCapture.none => 'Speak naturally — Hermsy is listening',
            };
      return AnimatedSwitcher(
        duration: AppMotion.short,
        child: Text(
          text,
          key: ValueKey(text),
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(color: AppColors.hint),
        ),
      );
    }

    if (capture == null) {
      return build(VoiceCapture.none);
    }
    return ValueListenableBuilder<VoiceCapture>(
      valueListenable: capture,
      builder: (context, mode, _) => build(mode),
    );
  }
}

final _statusStyle = AppText.headline.copyWith(fontWeight: FontWeight.w500);

/// "Listening…" (the composer capsule carries the elapsed time).
class _ListeningLine extends StatelessWidget {
  const _ListeningLine({super.key});

  @override
  Widget build(BuildContext context) {
    return Text('Listening…', style: _statusStyle);
  }
}

/// Live on-device words: four lines reserved so nothing jumps as they arrive,
/// newest at the bottom, older lines fading out at the top.
class _TranscriptBox extends StatelessWidget {
  const _TranscriptBox({required this.words, required this.placeholder});

  final String words;
  final Widget placeholder;

  static TextStyle get _style => TextStyle(
    color: AppColors.text,
    fontSize: 18,
    height: 1.45,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
  );

  @override
  Widget build(BuildContext context) {
    final line =
        MediaQuery.textScalerOf(context).scale(_style.fontSize!) *
        _style.height!;
    final Widget body = words.isEmpty
        ? Align(
            key: const ValueKey('waiting'),
            alignment: Alignment.bottomCenter,
            child: placeholder,
          )
        : ShaderMask(
            key: const ValueKey('words'),
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x40FFFFFF), Color(0xFFFFFFFF)],
                stops: [0, 0.55],
              ).createShader(rect);
            },
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.bottomCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Text(words, textAlign: TextAlign.center, style: _style),
              ),
            ),
          );
    return SizedBox(
      height: line * 4,
      width: double.infinity,
      child: AnimatedSwitcher(duration: AppMotion.short, child: body),
    );
  }
}

/// `0:07`, `1:42`.
String formatVoiceClock(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}
