import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Quiet actions under a finished reply: Copy, Speak and Retry as 18dp icons
/// in 40dp targets. Copy confirms in place ("Copied" with a check for
/// 1400ms) instead of a snackbar over the composer.
///
/// A null callback hides that action. The row fades in when it first
/// appears, so it arrives after the reply lands rather than with it.
class ReplyActions extends StatefulWidget {
  const ReplyActions({
    super.key,
    this.onCopy,
    this.onSpeak,
    this.onRetry,
    this.onReport,
    this.speaking = false,
  });

  final VoidCallback? onCopy;
  final VoidCallback? onSpeak;
  final VoidCallback? onRetry;

  /// Reports the reply as offensive or wrong.
  final VoidCallback? onReport;

  /// This reply is being read aloud: Speak shows a stop glyph.
  final bool speaking;

  /// How far the first icon's glyph sits inside its target, so callers can
  /// line the glyph up with the text edge.
  static const glyphInset = (_target - _glyph) / 2;

  static const _target = 40.0;
  static const _glyph = 18.0;

  @override
  State<ReplyActions> createState() => _ReplyActionsState();
}

class _ReplyActionsState extends State<ReplyActions> {
  Timer? _reset;
  var _copied = false;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _copy() {
    widget.onCopy?.call();
    _reset?.cancel();
    setState(() => _copied = true);
    _reset = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.short,
      curve: AppMotion.standard,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onCopy != null) _CopyAction(copied: _copied, onTap: _copy),
          if (widget.onSpeak != null)
            _IconAction(
              icon: widget.speaking
                  ? Icons.stop_rounded
                  : Icons.volume_up_rounded,
              tooltip: widget.speaking ? 'Stop speaking' : 'Speak',
              onTap: widget.onSpeak!,
              color: widget.speaking ? AppColors.text : AppColors.hint,
            ),
          if (widget.onRetry != null)
            _IconAction(
              icon: Icons.refresh_rounded,
              tooltip: 'Retry',
              onTap: widget.onRetry!,
            ),
          if (widget.onReport != null)
            _IconAction(
              icon: Icons.outlined_flag_rounded,
              tooltip: 'Report reply',
              onTap: widget.onReport!,
            ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Defaults to [AppColors.hint].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      iconSize: ReplyActions._glyph,
      color: color ?? AppColors.hint,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: ReplyActions._target,
        height: ReplyActions._target,
      ),
      style: IconButton.styleFrom(
        highlightColor: AppColors.veil(0x14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon),
    );
  }
}

/// Copy, which widens into "✓ Copied" for a moment after a tap.
class _CopyAction extends StatelessWidget {
  const _CopyAction({required this.copied, required this.onTap});

  final bool copied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Copy',
      child: Semantics(
        button: true,
        label: copied ? 'Copied' : 'Copy',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          highlightColor: AppColors.veil(0x14),
          child: AnimatedSize(
            duration: AppMotion.quick,
            curve: AppMotion.standard,
            alignment: Alignment.centerLeft,
            child: Container(
              height: ReplyActions._target,
              constraints: const BoxConstraints(minWidth: ReplyActions._target),
              padding: EdgeInsets.symmetric(
                horizontal: copied ? 10 : ReplyActions.glyphInset,
              ),
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: AppMotion.quick,
                switchInCurve: AppMotion.enter,
                switchOutCurve: AppMotion.exit,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.85, end: 1).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: copied
                    ? Row(
                        key: const ValueKey('copied'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_rounded,
                            size: ReplyActions._glyph,
                            color: AppColors.ion,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Copied',
                            style: AppText.caption.copyWith(color: AppColors.ion),
                          ),
                        ],
                      )
                    : Icon(
                        Icons.copy_rounded,
                        key: const ValueKey('copy'),
                        size: ReplyActions._glyph,
                        color: AppColors.hint,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
