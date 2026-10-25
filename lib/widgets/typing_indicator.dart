import 'package:flutter/material.dart';

import '../state/assistant_mood.dart';
import '../theme/app_theme.dart';
import 'frank_orb.dart';
import 'tool_activity_line.dart';
import 'ui/frank_ui.dart';

/// Frank's inline presence row in the reply slot while he works: a small
/// live orb and a shimmering "Thinking", with the tools he has finished and
/// the one running now underneath.
///
/// It sits exactly where the reply's byline will be, so the first streamed
/// words replace it in place instead of pushing the layout around.
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key, this.detail, this.trail = const []});

  /// The live Hermes tool line, if a tool is running. "Thinking…" and empty
  /// values mean Frank is only thinking.
  final String? detail;

  /// Tool lines this reply already ran, oldest first. The newest few show
  /// as quiet check lines above the live chip.
  final List<String> trail;

  /// How many finished steps stay visible while Frank works.
  static const _visibleSteps = 3;

  /// Left edge of the label, so steps and chips line up under the text.
  static const _labelInset = 30.0;

  @override
  Widget build(BuildContext context) {
    final tool = _liveTool(detail);
    final done = [
      for (final line in trail)
        if (line.trim().isNotEmpty) line,
    ];
    if (tool != null && done.isNotEmpty && done.last.trim() == tool) {
      done.removeLast();
    }
    final steps = done.length > _visibleSteps
        ? done.sublist(done.length - _visibleSteps)
        : done;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FrankOrb(
                size: 20,
                live: true,
                intense: true,
                mood: tool == null ? AssistantMood.thinking : AssistantMood.tool,
              ),
              const SizedBox(width: _labelInset - 20),
              Flexible(
                // Secondary under a white-hot sweep, like the composer's
                // 'Transcribing': white over near-white would barely move.
                child: ShimmerText(
                  'Thinking',
                  period: const Duration(milliseconds: 1200),
                  style: AppText.label.copyWith(color: AppColors.secondary),
                  highlight: AppColors.whiteHot,
                ),
              ),
            ],
          ),
        ),
        if (steps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: _labelInset, top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final step in steps) ToolTrailLine(label: step),
              ],
            ),
          ),
        if (tool != null)
          Padding(
            padding: EdgeInsets.only(
              left: _labelInset,
              top: steps.isEmpty ? 8 : 4,
            ),
            child: _ChipEntrance(
              key: ValueKey(tool),
              child: ToolActivityLine(label: tool),
            ),
          ),
      ],
    );
  }

  static String? _liveTool(String? detail) {
    final value = detail?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final lowered = value.toLowerCase();
    if (lowered == 'thinking…' ||
        lowered == 'thinking...' ||
        lowered == 'working…' ||
        lowered == 'frank is typing') {
      return null;
    }
    return value;
  }
}

/// Slides a new tool chip in (180ms, 6dp rise and fade) each time the tool
/// changes. A crossfade only when the OS asks for less motion.
class _ChipEntrance extends StatelessWidget {
  const _ChipEntrance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: AppMotion.enter,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, reduced ? 0 : (1 - t) * 6),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
