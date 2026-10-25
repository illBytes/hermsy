import 'dart:math' as math;
import 'dart:ui';

/// The glass edge as a loop: 0 at bottom centre, up the right side to 0.5 at
/// top centre, down the left side back to 1 (arc length, rounded corners
/// included). Mirrors `loopParam` in `shaders/edge_glow.frag`, so the CPU
/// can aim blooms and comets at exactly the pixels the shader lights.
class GlowGeometry {
  const GlowGeometry(this.size, this.radius);

  static const zero = GlowGeometry(Size.zero, 0);

  final Size size;
  final double radius;

  bool get isEmpty => size.isEmpty;

  double get _hx => size.width / 2;
  double get _hy => size.height / 2;
  double get _r => math.max(0.0, math.min(radius, math.min(_hx, _hy)));
  double get _halfPerimeter =>
      2 * (_hx - _r) + 2 * (_hy - _r) + math.pi * _r;

  /// Loop position of the rim point nearest [point] (logical, canvas space).
  double loopOf(Offset point) {
    if (isEmpty) {
      return 0;
    }
    final hx = _hx;
    final hy = _hy;
    final r = _r;
    final qx = point.dx - hx;
    final ax = qx.abs();
    final ay = point.dy - hy;
    final sx = hx - r;
    final sy = hy - r;
    final halfP = _halfPerimeter;
    double pos;
    if (ax > sx && ay > sy) {
      pos = sx + (math.pi / 2 - math.atan2(ay - sy, ax - sx)) * r;
    } else if (ax > sx && ay < -sy) {
      pos = sx + math.pi / 2 * r + 2 * sy + math.atan2(-ay - sy, ax - sx) * r;
    } else {
      final db = hy - ay;
      final dr = hx - ax;
      final dt = hy + ay;
      if (db <= dr && db <= dt) {
        pos = ax;
      } else if (dr <= dt) {
        pos = sx + math.pi / 2 * r + (sy - ay);
      } else {
        pos = halfP - ax;
      }
    }
    final t = halfP <= 0 ? 0.0 : (pos / halfP).clamp(0.0, 1.0);
    return qx >= 0 ? 0.5 * t : 1 - 0.5 * t;
  }

  /// The point on the glass at loop position [u]. Inverse of [loopOf].
  Offset pointAt(double u) {
    if (isEmpty) {
      return Offset.zero;
    }
    final hx = _hx;
    final hy = _hy;
    final r = _r;
    final sx = hx - r;
    final sy = hy - r;
    final wrapped = u - u.floorToDouble();
    final right = wrapped <= 0.5;
    var pos = (right ? wrapped * 2 : (1 - wrapped) * 2) * _halfPerimeter;
    double x;
    double y;
    final arc = math.pi / 2 * r;
    if (pos <= sx) {
      x = pos;
      y = hy;
    } else if ((pos -= sx) <= arc) {
      final a = math.pi / 2 - (r == 0 ? 0 : pos / r);
      x = sx + math.cos(a) * r;
      y = sy + math.sin(a) * r;
    } else if ((pos -= arc) <= 2 * sy) {
      x = hx;
      y = sy - pos;
    } else if ((pos -= 2 * sy) <= arc) {
      final a = r == 0 ? 0.0 : pos / r;
      x = sx + math.cos(a) * r;
      y = -sy - math.sin(a) * r;
    } else {
      pos -= arc;
      x = math.max(sx - pos, 0);
      y = -hy;
    }
    return Offset(hx + (right ? x : -x), hy + y);
  }

  @override
  bool operator ==(Object other) =>
      other is GlowGeometry && other.size == size && other.radius == radius;

  @override
  int get hashCode => Object.hash(size, radius);
}

/// Band paths (the screen's rounded rect minus an inset copy) for the glow,
/// cached per inward depth so painting never builds a path per frame.
class GlowBandCache {
  /// Inward depths the band snaps to, smallest first.
  static const depths = <double>[36, 64, 104, 160, 240];

  GlowGeometry _geometry = GlowGeometry.zero;
  final Map<double, Path> _paths = {};

  /// The smallest cached depth that covers [reach] logical px inward.
  static double depthFor(double reach) {
    for (final depth in depths) {
      if (depth >= reach) {
        return depth;
      }
    }
    return depths.last;
  }

  Path band(GlowGeometry geometry, double depth) {
    if (geometry != _geometry) {
      _geometry = geometry;
      _paths.clear();
    }
    return _paths[depth] ??= _build(geometry, depth);
  }

  static Path _build(GlowGeometry geometry, double depth) {
    final rect = Offset.zero & geometry.size;
    final outer = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(geometry.radius)));
    final innerRect = rect.deflate(depth);
    if (innerRect.isEmpty) {
      return outer;
    }
    // The shader's light has rounded inner contours that reach deeper along
    // the corner diagonals, so the hole is rounded generously to match.
    final innerRadius = math.min(
      math.max(geometry.radius - depth, depth * 1.5),
      innerRect.shortestSide / 2,
    );
    final inner = Path()
      ..addRRect(
        RRect.fromRectAndRadius(innerRect, Radius.circular(innerRadius)),
      );
    return Path.combine(PathOperation.difference, outer, inner);
  }
}
