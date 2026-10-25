import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../presence/glow_geometry.dart';
import '../presence/presence_engine.dart';
import '../presence/presence_shaders.dart';
import '../services/display_corners.dart';
import '../theme/app_theme.dart';

/// Frank's edge glow over the whole app: light on the phone's real rounded
/// glass while Frank listens or works.
///
/// Mount it above the Navigator (in `MaterialApp.builder`) so it survives
/// routes, sheets and the drawer. It never rebuilds per frame: the painter
/// repaints straight from the engine, and paints nothing while Frank is idle.
class EdgeGlowLayer extends StatefulWidget {
  const EdgeGlowLayer({super.key, this.engine});

  /// Defaults to the nearest [PresenceScope].
  final PresenceEngine? engine;

  @override
  State<EdgeGlowLayer> createState() => _EdgeGlowLayerState();
}

class _EdgeGlowLayerState extends State<EdgeGlowLayer> {
  final _resources = EdgeGlowResources();

  @override
  void initState() {
    super.initState();
    _resources.load(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _resources.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine ?? PresenceScope.maybeOf(context);
    if (engine == null) {
      return const SizedBox.shrink();
    }
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    engine.platformReduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _KeyboardProbe(engine: engine),
          RepaintBoundary(
            child: ValueListenableBuilder<double>(
              valueListenable: DisplayCorners.radius,
              builder: (context, radius, _) {
                engine.updateGeometry(size, radius);
                return CustomPaint(
                  size: Size.infinite,
                  painter: EdgeGlowPainter(
                    engine: engine,
                    resources: _resources,
                    radius: radius,
                    devicePixelRatio: dpr,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Tells the engine when the keyboard covers the bottom edge, without
/// rebuilding the glow while the keyboard animates.
class _KeyboardProbe extends StatelessWidget {
  const _KeyboardProbe({required this.engine});

  final PresenceEngine engine;

  @override
  Widget build(BuildContext context) {
    engine.keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return const SizedBox.shrink();
  }
}

/// The shader, cached band paths and paints a glow surface reuses across
/// frames and rebuilds. One per surface (the screen, a preview).
class EdgeGlowResources {
  ui.FragmentShader? _shader;
  bool _disposed = false;

  /// Null until the program loads, or forever if it cannot (fallback).
  ui.FragmentShader? get shader => _shader;

  final bands = GlowBandCache();
  final Paint _shaderPaint = Paint()..blendMode = BlendMode.plus;
  final Paint _halo = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;
  final Paint _core = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;
  final Paint _fill = Paint()..blendMode = BlendMode.plus;

  /// Loads the shader. [onReady] runs if it arrives after this call returns.
  void load(VoidCallback onReady) {
    final program = PresenceShaders.edgeGlow;
    if (program != null) {
      _shader = program.fragmentShader();
      return;
    }
    PresenceShaders.loadEdgeGlow().then((program) {
      if (_disposed || program == null) {
        return;
      }
      _shader = program.fragmentShader();
      onReady();
    });
  }

  void dispose() {
    _disposed = true;
    _shader?.dispose();
    _shader = null;
  }
}

/// Paints a [PresenceEngine]'s current [GlowFrame]: the edge glow shader on
/// a cached band path with additive blending, or a CustomPainter fallback
/// when the shader is unavailable.
class EdgeGlowPainter extends CustomPainter {
  EdgeGlowPainter({
    required this.engine,
    required this.resources,
    required this.radius,
    required this.devicePixelRatio,
    this.scale = 1,
  })  : _shader = resources.shader,
        super(repaint: engine);

  final PresenceEngine engine;
  final EdgeGlowResources resources;

  /// Corner radius of the surface, logical px.
  final double radius;
  final double devicePixelRatio;

  /// Shrinks the light's depth for miniature previews (1 = the real screen).
  final double scale;

  /// Where reply text starts, in from the glass (the reading gutter): the
  /// glow's added light is held under [GlowFrame.readCap] from here inward.
  static const readingInset = 20.0;

  final ui.FragmentShader? _shader;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = engine.frame;
    if (!frame.visible || size.isEmpty) {
      return;
    }
    final geometry = GlowGeometry(size, radius);
    final shader = _shader;
    if (shader != null) {
      _paintShader(canvas, geometry, frame, shader);
    } else {
      _paintFallback(canvas, geometry, frame);
    }
  }

  void _paintShader(
    Canvas canvas,
    GlowGeometry geometry,
    GlowFrame f,
    ui.FragmentShader shader,
  ) {
    // The path snaps to a cached depth; the shader's fade and thickness
    // clamp follow the (smoothed) reach itself, so the faint tail never
    // steps when the path flips between depths.
    final reach = f.reach * scale;
    final band = GlowBandCache.depthFor(reach);
    // Indices follow the uniform declaration order in edge_glow.frag.
    shader
      ..setFloat(0, geometry.size.width)
      ..setFloat(1, geometry.size.height)
      ..setFloat(2, radius)
      ..setFloat(3, devicePixelRatio)
      ..setFloat(4, math.min(reach, band))
      ..setFloat(5, f.intensity)
      ..setFloat(6, math.max(f.depth * scale, 1))
      ..setFloat(7, f.amp)
      ..setFloat(8, f.flow)
      ..setFloat(9, f.hue)
      ..setFloat(10, f.bias)
      ..setFloat(11, f.origin)
      ..setFloat(12, f.reveal)
      ..setFloat(13, f.front)
      ..setFloat(14, f.flare)
      ..setFloat(15, f.comet)
      ..setFloat(16, f.cometWidth)
      ..setFloat(17, f.cometGain)
      ..setFloat(18, f.twin)
      ..setFloat(19, f.cometOnly)
      ..setFloat(20, f.ringMix)
      ..setFloat(21, f.flash);
    for (var i = 0; i < 4; i++) {
      shader.setFloat(22 + i, f.ripples[i]);
    }
    for (var i = 0; i < 12; i++) {
      shader.setFloat(26 + i, f.palette[i]);
    }
    shader
      ..setFloat(38, f.readCap)
      ..setFloat(39, readingInset * scale);
    final paint = resources._shaderPaint
      ..blendMode = AppColors.glowBlend
      ..shader = shader;
    canvas.drawPath(resources.bands.band(geometry, band), paint);
  }

  /// Blurred strokes with a sweep of the palette: not the shader's liquid
  /// light, but the same colors, depth, lean, comets and sweep.
  void _paintFallback(Canvas canvas, GlowGeometry geometry, GlowFrame f) {
    final size = geometry.size;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final strength = f.intensity * (0.2 + 0.8 * f.reveal);
    if (strength < 0.002) {
      return;
    }
    final depth = math.max(f.depth * scale, 2.0);
    final reach = depth * (1 + 1.1 * f.amp);
    final p = f.palette;
    final colors = [
      for (var i = 0; i < 4; i++)
        Color.from(alpha: 1, red: p[i * 3], green: p[i * 3 + 1], blue: p[i * 3 + 2]),
    ];
    final sweep = SweepGradient(
      colors: [...colors, colors.first],
      transform: GradientRotation(math.pi / 2 - f.hue * 2 * math.pi),
    ).createShader(rect);
    final body = 1 - 0.75 * f.cometOnly;

    canvas.save();
    canvas.clipRRect(rrect);

    final halo = resources._halo
      ..blendMode = AppColors.glowBlend
      ..shader = sweep
      ..strokeWidth = reach * 1.3
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, reach * 0.55)
      ..color = Color.fromRGBO(255, 255, 255, (0.6 * strength * body).clamp(0.0, 1.0));
    canvas.drawRRect(rrect.deflate(reach * 0.2), halo);

    final core = resources._core
      ..blendMode = AppColors.glowBlend
      ..shader = sweep
      ..strokeWidth = 1.6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8)
      ..color = Color.fromRGBO(255, 255, 255, (0.95 * strength).clamp(0.0, 1.0));
    canvas.drawRRect(rrect.deflate(0.8), core);

    final fill = resources._fill..blendMode = AppColors.glowBlend;
    if (f.bias.abs() > 0.05) {
      final bottom = f.bias > 0;
      final h = depth * 3.4 * f.bias.abs();
      final lean = bottom
          ? Rect.fromLTWH(0, size.height - h, size.width, h)
          : Rect.fromLTWH(0, 0, size.width, h);
      final color = colors[bottom ? 1 : 2];
      fill
        ..maskFilter = null
        ..shader = LinearGradient(
          begin: bottom ? Alignment.bottomCenter : Alignment.topCenter,
          end: bottom ? Alignment.topCenter : Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: (0.4 * strength * f.bias.abs()).clamp(0.0, 1.0)),
            color.withValues(alpha: 0),
          ],
        ).createShader(lean);
      canvas.drawRect(lean, fill);
    }

    void blob(double u, double size, double alpha, Color color) {
      final center = geometry.pointAt(u);
      fill
        ..maskFilter = null
        ..shader = RadialGradient(
          colors: [
            (AppColors.isDark ? Color.lerp(color, Colors.white, 0.55)! : color)
                .withValues(alpha: alpha.clamp(0.0, 1.0)),
            color.withValues(alpha: (alpha * 0.35).clamp(0.0, 1.0)),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.35, 1],
        ).createShader(Rect.fromCircle(center: center, radius: size));
      canvas.drawCircle(center, size, fill);
    }

    if (f.comet >= 0) {
      final heads = f.twin > 1.5
          ? [f.origin + f.comet, f.origin - f.comet]
          : f.twin > 0.5
              ? [f.comet, f.comet + 0.5]
              : [f.comet];
      for (final head in heads) {
        blob(head, depth * 2.6, 0.75 * strength * f.cometGain, colors[1]);
      }
    }
    if (f.flare > 0) {
      blob(f.origin, depth * 2.2, 0.8 * f.flare * strength, colors[0]);
    }
    if (f.flash >= 0) {
      final alpha = 0.85 * strength * (1 - f.flash * 0.6);
      final flash = AppColors.isDark ? Colors.white : AppColors.goldBright;
      blob(0.5 - f.flash * 0.5, depth * 2.4, alpha, flash);
      blob(0.5 + f.flash * 0.5, depth * 2.4, alpha, flash);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant EdgeGlowPainter oldDelegate) {
    return !identical(oldDelegate.engine, engine) ||
        !identical(oldDelegate.resources, resources) ||
        !identical(oldDelegate._shader, _shader) ||
        oldDelegate.radius != radius ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.scale != scale;
  }
}
