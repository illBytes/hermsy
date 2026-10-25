import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Crossfades the glow's four-stop palette in OKLab, so blends between
/// states stay luminous instead of going muddy through grey.
///
/// [rgb] holds the current stops as 12 floats (r, g, b per stop, 0–1), ready
/// to hand straight to the shader.
class GlowPalette {
  GlowPalette(List<Color> initial) {
    _target = initial;
    _write(initial, _to);
    _from.setAll(0, _to);
    _emit(1);
  }

  final Float64List rgb = Float64List(12);
  final Float64List _from = Float64List(12); // OKLab
  final Float64List _to = Float64List(12); // OKLab
  List<Color> _target = const [];
  double _elapsed = 0;
  double _duration = 0;

  /// The palette the glow is heading to.
  List<Color> get target => _target;

  /// True while a crossfade is still running.
  bool get blending => _elapsed < _duration;

  /// Head to [colors] over [seconds] (0 snaps).
  void fadeTo(List<Color> colors, double seconds) {
    if (identical(colors, _target)) {
      return;
    }
    _target = colors;
    // Start from what is on screen right now, even mid-blend.
    for (var i = 0; i < 4; i++) {
      final lab = _oklab(rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2]);
      _from[i * 3] = lab.$1;
      _from[i * 3 + 1] = lab.$2;
      _from[i * 3 + 2] = lab.$3;
    }
    _write(colors, _to);
    _elapsed = 0;
    _duration = seconds;
    if (seconds <= 0) {
      _emit(1);
    }
  }

  /// Advance the blend by [dt] seconds.
  void step(double dt) {
    if (!blending) {
      return;
    }
    _elapsed = math.min(_elapsed + dt, _duration);
    final t = _elapsed / _duration;
    // Ease in-out so the hue change never pops.
    _emit(t * t * (3 - 2 * t));
  }

  void _emit(double t) {
    for (var i = 0; i < 4; i++) {
      final o = i * 3;
      final l = _from[o] + (_to[o] - _from[o]) * t;
      final a = _from[o + 1] + (_to[o + 1] - _from[o + 1]) * t;
      final b = _from[o + 2] + (_to[o + 2] - _from[o + 2]) * t;
      final c = _srgb(l, a, b);
      rgb[o] = c.$1;
      rgb[o + 1] = c.$2;
      rgb[o + 2] = c.$3;
    }
    if (t >= 1) {
      _duration = 0;
      _elapsed = 0;
    }
  }

  static void _write(List<Color> colors, Float64List out) {
    for (var i = 0; i < 4; i++) {
      final color = colors[i % colors.length];
      final lab = _oklab(color.r, color.g, color.b);
      out[i * 3] = lab.$1;
      out[i * 3 + 1] = lab.$2;
      out[i * 3 + 2] = lab.$3;
    }
  }

  static double _toLinear(double c) {
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static double _toGamma(double c) {
    final v = c.clamp(0.0, 1.0);
    return v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
  }

  static double _cbrt(double x) {
    return x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();
  }

  static (double, double, double) _oklab(double r, double g, double b) {
    final lr = _toLinear(r);
    final lg = _toLinear(g);
    final lb = _toLinear(b);
    final l = _cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
    final m = _cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
    final s = _cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
    return (
      0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    );
  }

  static (double, double, double) _srgb(double l, double a, double b) {
    final l1 = l + 0.3963377774 * a + 0.2158037573 * b;
    final m1 = l - 0.1055613458 * a - 0.0638541728 * b;
    final s1 = l - 0.0894841775 * a - 1.2914855480 * b;
    final l3 = l1 * l1 * l1;
    final m3 = m1 * m1 * m1;
    final s3 = s1 * s1 * s1;
    return (
      _toGamma(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
      _toGamma(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
      _toGamma(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3),
    );
  }
}
