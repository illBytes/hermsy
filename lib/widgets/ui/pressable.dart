import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Gives any child a soft, springy press: it dips to [pressedScale] while
/// held and settles back with a hint of overshoot.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.haptic = false,
    this.behavior = HitTestBehavior.opaque,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;

  /// Fire a selection click on tap.
  final bool haptic;
  final HitTestBehavior behavior;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down() {
    if (!_enabled) {
      return;
    }
    _press.animateTo(
      widget.pressedScale,
      duration: AppMotion.instant,
      curve: Curves.easeOut,
    );
  }

  void _up() {
    _press.animateWith(
      SpringSimulation(AppMotion.pressSpring, _press.value, 1, _press.velocity),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: (_) => _down(),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        onLongPressEnd: (_) => _up(),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) {
                  HapticFeedback.selectionClick();
                }
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) {
            return Transform.scale(scale: _press.value, child: child);
          },
          child: widget.child,
        ),
      ),
    );
  }
}
