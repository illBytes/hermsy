import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui/frank_ui.dart';

/// A 44dp glass disc that jumps the thread back to the newest message.
///
/// It scales in when [visible] and carries a gold dot when [unseen] content
/// arrived while you were reading further up.
class ScrollToLatestButton extends StatelessWidget {
  const ScrollToLatestButton({
    super.key,
    required this.visible,
    required this.onPressed,
    this.unseen = false,
  });

  final bool visible;
  final bool unseen;
  final VoidCallback onPressed;

  static const size = 44.0;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final duration = reduced ? AppMotion.instant : AppMotion.quick;
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          curve: AppMotion.standard,
          child: AnimatedScale(
            scale: visible || reduced ? 1 : 0.8,
            duration: duration,
            curve: visible ? AppMotion.enter : AppMotion.exit,
            child: Tooltip(
              message: unseen ? 'Jump to new messages' : 'Jump to latest',
              child: Pressable(
                onTap: onPressed,
                pressedScale: 0.9,
                child: SizedBox.square(
                  dimension: size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: GlassPanel(
                          shape: BoxShape.circle,
                          blur: 0,
                          color: AppColors.surfaceHigh.withValues(alpha: 0.92),
                          borderColor: AppColors.strokeStrong,
                          child: Center(
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 24,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 1,
                        right: 1,
                        child: AnimatedScale(
                          scale: unseen ? 1 : 0,
                          duration: reduced ? Duration.zero : AppMotion.short,
                          curve: unseen ? Curves.easeOutBack : AppMotion.exit,
                          child: const _UnseenDot(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnseenDot extends StatelessWidget {
  const _UnseenDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppGradients.gold,
        border: Border.all(color: AppColors.background, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.45),
            blurRadius: 8,
          ),
        ],
      ),
    );
  }
}
