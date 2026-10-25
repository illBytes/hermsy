import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'frank_sheet.dart';

/// UPPERCASE micro label above a group or list section.
class MicroLabel extends StatelessWidget {
  const MicroLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(4, 0, 4, 8),
    this.color,
  });

  final String text;
  final EdgeInsets padding;

  /// Defaults to [AppColors.hint].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: AppText.micro.copyWith(color: color ?? AppColors.hint),
      ),
    );
  }
}

/// A card of rows on surface black, radius 20, hairline dividers inset past
/// the icon tile.
class FrankGroup extends StatelessWidget {
  const FrankGroup({
    super.key,
    required this.children,
    this.dividerIndent = 60,
  });

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.veil(0x0D)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.hairline,
                  indent: dividerIndent,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A 56dp settings-style row: icon tile, title, optional subtitle, trailing.
class FrankTile extends StatelessWidget {
  const FrankTile({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.chevron = false,
    this.leading,
  });

  final String title;
  final IconData? icon;
  final Color? iconColor;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  /// Shows a trailing chevron when no [trailing] is given.
  final bool chevron;

  /// Replaces the icon tile (for example a mini glow preview).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.text;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(
            children: [
              if (leading != null)
                leading!
              else if (icon != null)
                IconTile(
                  icon: icon!,
                  size: 32,
                  color:
                      iconColor ?? (danger ? AppColors.danger : AppColors.text),
                ),
              if (leading != null || icon != null) const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.label.copyWith(fontSize: 16, color: color),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppText.bodySmall.copyWith(fontSize: 13.5),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (chevron)
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.hint,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A [FrankTile] with a switch that toggles when the row is tapped.
class FrankSwitchTile extends StatelessWidget {
  const FrankSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.iconColor,
    this.subtitle,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final Color? iconColor;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: FrankTile(
        title: title,
        subtitle: subtitle,
        icon: icon,
        iconColor: iconColor,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}
