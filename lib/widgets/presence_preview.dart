import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../presence/presence_engine.dart';
import '../services/app_settings.dart';
import '../services/display_corners.dart';
import '../state/assistant_mood.dart';
import '../theme/app_theme.dart';
import 'edge_glow.dart';
import 'frank_orb.dart';
import 'ui/frank_ui.dart';

/// A phone-shaped, live preview of an edge glow [style], drawn by the same
/// painter as the real glow on its own little engine.
///
/// It stages Frank's states in turn (every 2.4s) under a state scrubber;
/// tapping a state pins it, tapping it again resumes the tour. It animates
/// only while it is on screen and [active].
class PresencePreview extends StatefulWidget {
  const PresencePreview({
    super.key,
    required this.style,
    this.active = true,
    this.phoneWidth = 132,
  });

  final PresenceStyle style;

  /// Pauses the tour (for example while the real glow is previewing).
  final bool active;

  /// Width of the phone; its height follows the real screen's shape.
  final double phoneWidth;

  @override
  State<PresencePreview> createState() => _PresencePreviewState();
}

class _Stage {
  const _Stage(this.demo, this.label, this.mood, this.color);

  final PresenceDemo demo;
  final String label;
  final AssistantMood mood;

  /// The status-line color for this state.
  final Color color;
}

List<_Stage> get _stages => [
  _Stage(
    PresenceDemo.listening,
    'Listening',
    AssistantMood.listening,
    AppColors.statusListening,
  ),
  _Stage(
    PresenceDemo.thinking,
    'Thinking',
    AssistantMood.thinking,
    AppColors.statusThinking,
  ),
  _Stage(
    PresenceDemo.tool,
    'Tool',
    AssistantMood.tool,
    AppColors.statusTranscribing,
  ),
  _Stage(
    PresenceDemo.replying,
    'Replying',
    AssistantMood.responding,
    AppColors.text,
  ),
  _Stage(
    PresenceDemo.speaking,
    'Speaking',
    AssistantMood.speaking,
    AppColors.statusSpeaking,
  ),
  _Stage(PresenceDemo.done, 'Done', AssistantMood.idle, AppColors.whiteHot),
  _Stage(PresenceDemo.error, 'Error', AssistantMood.error, AppColors.danger),
];

class _PresencePreviewState extends State<PresencePreview>
    with TickerProviderStateMixin {
  late final PresenceEngine _engine = PresenceEngine(vsync: this);
  late final AnimationController _tour = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..addStatusListener(_onTourStep);
  final _resources = EdgeGlowResources();
  var _index = 0;
  var _pinned = false;

  bool get _off => widget.style == PresenceStyle.off;
  bool get _running => widget.active && !_off;

  @override
  void initState() {
    super.initState();
    _engine.setStyle(widget.style);
    _resources.load(() {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _restage();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = PresenceScope.maybeOf(context)?.settings;
    if (settings != null) {
      _engine.configure(settings);
    }
    _engine.platformReduceMotion = AppMotion.reduced(context);
  }

  @override
  void didUpdateWidget(covariant PresencePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style || oldWidget.active != widget.active) {
      _engine.setStyle(widget.style);
      _restage();
    }
  }

  @override
  void dispose() {
    _tour.dispose();
    _engine.dispose();
    _resources.dispose();
    super.dispose();
  }

  /// Start the current state over (a new style blooms in from dark).
  void _restage() {
    _engine.silence();
    if (!_running) {
      _tour.stop();
      _engine.demo(null);
      setState(() {});
      return;
    }
    _engine.demo(_stages[_index].demo);
    if (_pinned) {
      _tour.stop();
    } else {
      _tour.forward(from: 0);
    }
    setState(() {});
  }

  void _onTourStep(AnimationStatus status) {
    if (status != AnimationStatus.completed || _pinned || !_running) {
      return;
    }
    setState(() => _index = (_index + 1) % _stages.length);
    _engine.demo(_stages[_index].demo);
    _tour.forward(from: 0);
  }

  void _pick(int index) {
    if (!_running) {
      return;
    }
    if (index == _index && _pinned) {
      // Tapping the pinned state again resumes the tour.
      setState(() => _pinned = false);
      _tour.forward(from: 0);
      return;
    }
    setState(() {
      _index = index;
      _pinned = true;
    });
    _tour.stop();
    _engine.demo(_stages[index].demo);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final aspect = screen.width <= 0
        ? 2.1
        : (screen.height / screen.width).clamp(1.9, 2.25).toDouble();
    final width = widget.phoneWidth;
    final height = width * aspect;
    final ratio = screen.width <= 0 ? 0.32 : width / screen.width;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<double>(
          valueListenable: DisplayCorners.radius,
          builder: (context, displayRadius, _) {
            final radius = math.max(displayRadius * ratio, 10.0);
            _engine.updateGeometry(Size(width, height), radius);
            return _Phone(
              width: width,
              height: height,
              radius: radius,
              mood: _running ? _stages[_index].mood : AssistantMood.idle,
              glow: CustomPaint(
                size: Size(width, height),
                painter: EdgeGlowPainter(
                  engine: _engine,
                  resources: _resources,
                  radius: radius,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                  // A touch heavier than true scale, so it reads at this size.
                  scale: math.min(ratio * 1.3, 1),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: AppMotion.short,
          child: Text(
            _off ? 'No edge glow' : 'While Hermsy is working',
            key: ValueKey(_off),
            style: AppText.caption,
          ),
        ),
        const SizedBox(height: 6),
        _Scrubber(
          index: _index,
          pinned: _pinned,
          enabled: _running,
          tour: _tour,
          onPick: _pick,
        ),
      ],
    );
  }
}

/// The phone: a bezel, a quiet sketch of a conversation, and the glow.
class _Phone extends StatelessWidget {
  const _Phone({
    required this.width,
    required this.height,
    required this.radius,
    required this.mood,
    required this.glow,
  });

  final double width;
  final double height;
  final double radius;
  final AssistantMood mood;
  final Widget glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width + 6,
      height: height + 6,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(radius + 3),
        border: Border.all(color: AppColors.strokeStrong),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            const Positioned.fill(child: _Sketch()),
            Positioned(
              top: 12,
              left: 10,
              child: Row(
                children: [
                  FrankOrb(size: 12, mood: mood),
                  const SizedBox(width: 6),
                  _Bar(width: 34, color: AppColors.veil(0x33)),
                ],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(child: RepaintBoundary(child: glow)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton chat: reply lines, a user bubble, and the composer capsule.
class _Sketch extends StatelessWidget {
  const _Sketch();

  @override
  Widget build(BuildContext context) {
    final line = AppColors.veil(0x1A);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -1.15),
          radius: 1.1,
          colors: [AppColors.backdropGlow, AppColors.background],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 40, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 58,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.userBubble,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: AppColors.hairline, width: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Bar(widthFactor: 0.92, color: line),
            const SizedBox(height: 5),
            _Bar(widthFactor: 0.8, color: line),
            const SizedBox(height: 5),
            _Bar(widthFactor: 0.86, color: line),
            const SizedBox(height: 5),
            _Bar(widthFactor: 0.46, color: line),
            const Spacer(),
            Container(
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.glass,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.hairline, width: 0.5),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.all(3),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.veil(0x14),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({this.width, this.widthFactor, required this.color});

  final double? width;
  final double? widthFactor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      width: width,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
    );
    if (widthFactor == null) {
      return bar;
    }
    return FractionallySizedBox(widthFactor: widthFactor, child: bar);
  }
}

/// The state chips under the phone. The active one fills with the tour's
/// progress and is kept in view; a pinned one holds still with a light edge.
class _Scrubber extends StatefulWidget {
  const _Scrubber({
    required this.index,
    required this.pinned,
    required this.enabled,
    required this.tour,
    required this.onPick,
  });

  final int index;
  final bool pinned;
  final bool enabled;
  final Animation<double> tour;
  final ValueChanged<int> onPick;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  final _keys = [for (final _ in _stages) GlobalKey()];

  @override
  void didUpdateWidget(covariant _Scrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      final key = _keys[widget.index];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final chip = key.currentContext;
        if (mounted && chip != null) {
          Scrollable.ensureVisible(
            chip,
            alignment: 0.5,
            duration: AppMotion.medium,
            curve: AppMotion.standard,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: AppMotion.short,
      opacity: widget.enabled ? 1 : 0.4,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            for (var i = 0; i < _stages.length; i++)
              _StateChip(
                key: _keys[i],
                stage: _stages[i],
                active: widget.enabled && i == widget.index,
                pinned: widget.pinned,
                tour: widget.tour,
                onTap: widget.enabled ? () => widget.onPick(i) : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    super.key,
    required this.stage,
    required this.active,
    required this.pinned,
    required this.tour,
    required this.onTap,
  });

  final _Stage stage;
  final bool active;
  final bool pinned;
  final Animation<double> tour;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: AppMotion.short,
      curve: AppMotion.standard,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active ? AppColors.veil(0x14) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: active && pinned ? AppColors.strokeStrong : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: AppMotion.short,
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? stage.color : AppColors.disabled,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            stage.label,
            style: AppText.caption.copyWith(
              fontSize: 13,
              color: active ? AppColors.text : AppColors.secondary,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: active,
      label: stage.label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.94,
        child: SizedBox(
          height: AppSpace.minTouch,
          child: Center(
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                chip,
                if (active && !pinned)
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 4,
                    child: _TourProgress(tour: tour, color: stage.color),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TourProgress extends StatelessWidget {
  const _TourProgress({required this.tour, required this.color});

  final Animation<double> tour;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1.5,
      child: AnimatedBuilder(
        animation: tour,
        builder: (context, _) {
          return FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: tour.value,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
            ),
          );
        },
      ),
    );
  }
}
