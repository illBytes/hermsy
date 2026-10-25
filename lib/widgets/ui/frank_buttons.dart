import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'pressable.dart';

/// The primary action: a Hermes-gold pill.
class GoldButton extends StatelessWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expanded = true,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Shows a small spinner instead of the icon and blocks taps.
  final bool busy;
  final bool expanded;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.onGold,
            ),
          )
        else if (icon != null)
          Icon(icon, size: 20, color: AppColors.onGold),
        if (busy || icon != null) const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: AppColors.onGold,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          duration: AppMotion.short,
          opacity: enabled || busy ? 1 : 0.4,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              gradient: AppGradients.gold,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              boxShadow: enabled
                  ? [
                      // A centred halo (light, not a drop shadow on black).
                      BoxShadow(
                        color: AppColors.gold.withValues(alpha: 0.28),
                        blurRadius: 22,
                        spreadRadius: -4,
                      ),
                    ]
                  : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// A quiet secondary action: hairline-outlined pill.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = false,
    this.danger = false,
    this.height = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final bool danger;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.text;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onPressed,
        child: AnimatedOpacity(
          duration: AppMotion.short,
          opacity: onPressed == null ? 0.4 : 1,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: AppColors.veil(0x0A),
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(color: AppColors.strokeStrong),
            ),
            child: Row(
              mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 48dp-hit icon button with a tooltip, tuned for Frank's bars.
///
/// [active] tints the icon gold; [filled] puts it on a soft glass circle.
class FrankIconButton extends StatelessWidget {
  const FrankIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.filled = false,
    this.size = 22,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final bool filled;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? (active ? AppColors.gold : AppColors.secondary);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: size,
      color: tint,
      disabledColor: AppColors.disabled,
      style: IconButton.styleFrom(
        minimumSize: const Size(AppSpace.minTouch, AppSpace.minTouch),
        backgroundColor: filled ? AppColors.veil(0x0F) : null,
        highlightColor: AppColors.veil(0x14),
      ),
      icon: Icon(icon),
    );
  }
}
