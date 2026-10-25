import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../theme/app_theme.dart';

/// The quiet canvas every screen sits on: near-black with one soft navy
/// light falling from above the top edge (on light, a white one).
///
/// Static by design: it never animates or repaints on its own. Frank's
/// presence is the global edge glow (`EdgeGlowLayer`), drawn above every
/// route, so [live] and [presence] are kept only for older call sites.
class FrankBackdrop extends StatelessWidget {
  const FrankBackdrop({
    super.key,
    required this.child,
    this.live = false,
    this.presence = PresenceStyle.aura,
  });

  final Widget child;

  /// No longer animates anything; the glow is global.
  final bool live;

  /// No longer used here; the glow reads the style from settings.
  final PresenceStyle presence;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.15),
            radius: 1.1,
            colors: [AppColors.backdropGlow, AppColors.background],
          ),
        ),
        child: child,
      ),
    );
  }
}
