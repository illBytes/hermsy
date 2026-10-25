import 'dart:async';
import 'dart:ui' as ui;

/// Loads Frank's fragment programs once and keeps them compiled.
///
/// `main()` awaits [warmUp] before `runApp`, so the first glow (and the first
/// orb) never hitches on a pipeline compile. A load that fails (widget tests
/// without the asset, very old GPUs) resolves to null and the painters fall
/// back to their CustomPainter versions.
class PresenceShaders {
  PresenceShaders._();

  static const edgeGlowAsset = 'shaders/edge_glow.frag';
  static const orbAsset = 'shaders/orb.frag';

  static ui.FragmentProgram? _edgeGlow;
  static Future<ui.FragmentProgram?>? _edgeGlowLoad;

  /// The edge glow program, once loaded.
  static ui.FragmentProgram? get edgeGlow => _edgeGlow;

  /// Loads the edge glow program once; later calls share the result. A
  /// failed load may be retried by a later caller.
  static Future<ui.FragmentProgram?> loadEdgeGlow() {
    final ready = _edgeGlow;
    if (ready != null) {
      // A fresh future, so callers in any zone (tests) resume normally.
      return Future<ui.FragmentProgram?>.value(ready);
    }
    return _edgeGlowLoad ??= _load(edgeGlowAsset).then((program) {
      _edgeGlowLoad = null;
      return _edgeGlow = program;
    });
  }

  /// Compiles both shaders. dart:ui caches programs by asset key, so the orb
  /// widget's own `FragmentProgram.fromAsset` call then resolves instantly.
  static Future<void> warmUp() async {
    await Future.wait([loadEdgeGlow(), _load(orbAsset)]);
  }

  static Future<ui.FragmentProgram?> _load(String asset) async {
    try {
      return await ui.FragmentProgram.fromAsset(asset);
    } catch (_) {
      return null;
    }
  }
}
