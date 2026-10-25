import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'pressable.dart';

/// Opens a Frank bottom sheet: near-opaque black glass, 28dp top corners,
/// a grabber, no boxed rows.
Future<T?> showFrankSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: AppColors.sheet,
    barrierColor: AppColors.scrim,
    elevation: 0,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadii.sheet),
      ),
      side: BorderSide(color: AppColors.hairline),
    ),
    builder: builder,
  );
}

/// The 36x4 handle at the top of every sheet.
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.veil(0x2E),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
      ),
    );
  }
}

/// Standard sheet body: grabber, optional header, then [children].
class FrankSheet extends StatelessWidget {
  const FrankSheet({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.leading,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
    this.scrollable = false,
  });

  final List<Widget> children;
  final String? title;
  final String? subtitle;

  /// Shown above the title, centred (for example an orb).
  final Widget? leading;
  final EdgeInsets padding;

  /// Wrap the body in a scroll view for tall content.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetGrabber(),
        if (leading != null) ...[
          const SizedBox(height: 18),
          Center(child: leading!),
        ],
        if (title != null)
          Padding(
            // The same 6dp inset as SheetRow's content, so the title, the
            // subtitle and the row icons share one left edge.
            padding: EdgeInsets.fromLTRB(
              leading != null ? 0 : 6,
              leading != null ? 12 : 16,
              6,
              subtitle == null ? 12 : 0,
            ),
            child: Text(
              title!,
              textAlign: leading != null ? TextAlign.center : TextAlign.start,
              style: AppText.headline,
            ),
          ),
        if (subtitle != null)
          Padding(
            padding: EdgeInsets.fromLTRB(leading != null ? 0 : 6, 4, 6, 14),
            child: Text(
              subtitle!,
              textAlign: leading != null ? TextAlign.center : TextAlign.start,
              style: AppText.bodySmall,
            ),
          ),
        if (title == null && subtitle == null) const SizedBox(height: 12),
        ...children,
      ],
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: padding,
        child: scrollable ? SingleChildScrollView(child: body) : body,
      ),
    );
  }
}

/// A 36dp rounded icon tile used at the start of sheet and settings rows.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.color,
    this.size = 36,
    this.background,
  });

  final IconData icon;

  /// Defaults to [AppColors.text].
  final Color? color;
  final double size;

  /// Defaults to a faint veil.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? AppColors.veil(0x0F),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Icon(icon, color: color ?? AppColors.text, size: size * 0.55),
    );
  }
}

/// One action row in a sheet: icon tile, label, optional subtitle and
/// trailing. No borders; a soft pressed state.
class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.subtitle,
    this.trailing,
    this.danger = false,
    this.selected = false,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? subtitle;
  final Widget? trailing;
  final bool danger;

  /// Shows a gold check at the end.
  final bool selected;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.text;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: [
                IconTile(
                  icon: icon,
                  color:
                      iconColor ?? (danger ? AppColors.danger : AppColors.text),
                  background: danger
                      ? AppColors.signal.withValues(alpha: 0.12)
                      : AppColors.veil(0x0F),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppText.label.copyWith(
                          fontSize: 16,
                          color: color,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodySmall.copyWith(fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
                if (selected)
                  Icon(Icons.check_rounded, color: AppColors.gold, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A square-ish quick action (icon over label) for 2–4 up rows in a sheet.
class QuickTile extends StatelessWidget {
  const QuickTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.height = 76,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.text;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.veil(0x0A),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: color, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lays [children] (usually [QuickTile]s) out in an evenly split row.
class QuickTileRow extends StatelessWidget {
  const QuickTileRow({super.key, required this.children, this.gap = 8});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}
