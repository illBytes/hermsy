import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Frosted black glass with a faint top highlight and a light edge.
///
/// Blur is expensive; keep at most two live [GlassPanel]s with [blur] on a
/// screen (the composer and the header). Pass `blur: 0` for a solid panel.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = AppRadii.xl,
    this.blur = 24,
    this.color,
    this.borderColor,
    this.padding = EdgeInsets.zero,
    this.highlight = true,
    this.shape = BoxShape.rectangle,
  });

  final Widget child;
  final double radius;
  final double blur;

  /// Defaults to [AppColors.glass].
  final Color? color;

  /// Defaults to [AppColors.hairline].
  final Color? borderColor;
  final EdgeInsetsGeometry padding;

  /// The 1px inner light along the top edge.
  final bool highlight;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final circle = shape == BoxShape.circle;
    final borderRadius = circle ? null : BorderRadius.circular(radius);
    final color = this.color ?? AppColors.glass;
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: shape,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? AppColors.hairline),
        gradient: highlight
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(AppColors.veil(0x14), color),
                  color,
                  color,
                ],
                stops: const [0, 0.35, 1],
              )
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (blur > 0) {
      body = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: body,
      );
    }
    return circle
        ? ClipOval(child: body)
        : ClipRRect(borderRadius: borderRadius!, child: body);
  }
}
