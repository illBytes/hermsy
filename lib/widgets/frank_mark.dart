import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../state/assistant_mood.dart';

import 'frank_orb.dart';

/// Frank's mark: the orb, kept as a thin passthrough for older call sites.
/// [active] lights it; inactive is the dimmed, asleep look.
class FrankMark extends StatelessWidget {
  const FrankMark({
    super.key,
    this.size = 44,
    this.active = false,
    this.live,
    this.listening = false,
    this.intense = false,
    this.mood,
    this.level,
    this.pulse = 0,
  });

  final double size;
  final bool active;

  /// See [FrankOrb.live].
  final bool? live;
  final bool listening;
  final bool intense;
  final AssistantMood? mood;
  final ValueListenable<double>? level;

  /// See [FrankOrb.pulse].
  final int pulse;

  @override
  Widget build(BuildContext context) {
    return FrankOrb(
      size: size,
      live: live,
      listening: listening,
      lit: active,
      intense: intense,
      mood: mood,
      level: level,
      pulse: pulse,
    );
  }
}
