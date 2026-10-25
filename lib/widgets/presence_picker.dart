import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../presence/presence_engine.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import 'presence_preview.dart';
import 'ui/frank_ui.dart';

/// The edge glow style chooser, shown in a sheet: a live phone preview, the
/// styles with a gold check on the chosen one, and a button that runs the
/// real glow on the screen.
class PresencePicker extends StatefulWidget {
  const PresencePicker({
    super.key,
    required this.current,
    required this.onChanged,
  });

  final PresenceStyle current;
  final ValueChanged<PresenceStyle> onChanged;

  @override
  State<PresencePicker> createState() => _PresencePickerState();
}

class _PresencePickerState extends State<PresencePicker> {
  late PresenceStyle _selected = widget.current;
  bool _previewing = false;

  @override
  void didUpdateWidget(covariant PresencePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current && _selected != widget.current) {
      _selected = widget.current;
    }
  }

  void _select(PresenceStyle style) {
    if (style == _selected) {
      return;
    }
    setState(() => _selected = style);
    widget.onChanged(style);
  }

  Future<void> _previewOnScreen(PresenceEngine engine) async {
    setState(() => _previewing = true);
    await engine.preview();
    if (mounted) {
      setState(() => _previewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = PresenceScope.maybeOf(context);
    final media = MediaQuery.of(context);
    final canPreview =
        engine != null && !_previewing && _selected != PresenceStyle.off;

    final styles = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final style in AppSettings.presenceOrder)
          _StyleRow(
            style: style,
            selected: style == _selected,
            onTap: () => _select(style),
          ),
      ],
    );
    final button = GhostButton(
      label: _previewing ? 'Previewing…' : 'Preview on screen',
      icon: Icons.auto_awesome_rounded,
      expanded: true,
      onPressed: canPreview ? () => _previewOnScreen(engine) : null,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 520;
              final preview = PresencePreview(
                style: _selected,
                active: !_previewing,
                phoneWidth: wide ? 116 : 120,
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetGrabber(),
                  const _Header(),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 236, child: preview),
                        const SizedBox(width: 16),
                        Expanded(child: styles),
                      ],
                    )
                  else ...[
                    preview,
                    const SizedBox(height: 12),
                    styles,
                  ],
                  const SizedBox(height: 12),
                  button,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Presence', style: AppText.headline),
          const SizedBox(height: 4),
          Text('How Hermsy glows while it works', style: AppText.bodySmall),
        ],
      ),
    );
  }
}

class _StyleRow extends StatelessWidget {
  const _StyleRow({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final PresenceStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: AnimatedContainer(
            duration: AppMotion.short,
            curve: AppMotion.standard,
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.veil(0x0A) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                _StyleGlyph(style: style, selected: selected),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppSettings.presenceLabel(style),
                        style: AppText.label.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppSettings.presenceSubtitle(style),
                        style: AppText.bodySmall.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedScale(
                  duration: AppMotion.quick,
                  curve: AppMotion.standard,
                  scale: selected ? 1 : 0.6,
                  child: AnimatedOpacity(
                    duration: AppMotion.quick,
                    opacity: selected ? 1 : 0,
                    child: Icon(
                      Icons.check_rounded,
                      color: AppColors.gold,
                      size: 20,
                    ),
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

/// A tiny still phone sketching each style, so the list reads at a glance.
class _StyleGlyph extends StatelessWidget {
  const _StyleGlyph({required this.style, required this.selected});

  final PresenceStyle style;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: AppMotion.short,
      opacity: selected ? 1 : 0.62,
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(26, 44),
          painter: _GlyphPainter(style),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.style);

  final PresenceStyle style;

  static List<Color> get _colors => [
    AppColors.ion,
    AppColors.azure,
    AppColors.iris,
    AppColors.orchid,
    AppColors.ion,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(7));
    final sweep = SweepGradient(
      colors: _colors,
      transform: const GradientRotation(math.pi / 2),
    ).createShader(rect);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.strokeStrong,
    );
    Paint light(double width, {double blur = 0, double alpha = 1}) {
      return Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = sweep
        ..color = Color.fromRGBO(255, 255, 255, alpha)
        ..maskFilter = blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null;
    }

    Path segment(double start, double length) {
      final metric = (Path()..addRRect(rrect)).computeMetrics().first;
      final from = metric.length * start;
      final to = from + metric.length * length;
      final path = metric.extractPath(from, math.min(to, metric.length));
      if (to > metric.length) {
        path.addPath(metric.extractPath(0, to - metric.length), Offset.zero);
      }
      return path;
    }

    switch (style) {
      case PresenceStyle.off:
        return;
      case PresenceStyle.aura:
        canvas.drawRRect(rrect, light(4, blur: 3, alpha: 0.75));
        canvas.drawRRect(rrect, light(1.4));
      case PresenceStyle.ribbon:
        final path = segment(0.06, 0.22);
        canvas.drawPath(path, light(4, blur: 2.5, alpha: 0.8));
        canvas.drawPath(path, light(1.4));
      case PresenceStyle.twin:
        for (final start in const [0.06, 0.56]) {
          final path = segment(start, 0.16);
          canvas.drawPath(path, light(4, blur: 2.5, alpha: 0.8));
          canvas.drawPath(path, light(1.4));
        }
      case PresenceStyle.veil:
        canvas.drawRRect(rrect, light(2.2));
      case PresenceStyle.pulse:
        canvas.drawRRect(rrect, light(6, blur: 4, alpha: 0.55));
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter oldDelegate) {
    return oldDelegate.style != style;
  }
}
