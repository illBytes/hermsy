import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../services/conversation_store.dart';
import '../state/assistant_mood.dart';
import '../theme/app_theme.dart';
import 'frank_orb.dart';
import 'ui/frank_ui.dart';

/// A time-aware hello for the empty chat.
String greetingFor(DateTime time) {
  final hour = time.hour;
  if (hour >= 5 && hour < 12) {
    return 'Good morning';
  }
  if (hour >= 12 && hour < 17) {
    return 'Good afternoon';
  }
  if (hour >= 17 && hour < 22) {
    return 'Good evening';
  }
  return 'Still up?';
}

/// The host part of a server URL, for display (never the key).
String hostOf(String baseUrl) {
  final trimmed = baseUrl.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(trimmed);
  final host = uri?.host ?? '';
  if (host.isEmpty) {
    return trimmed.replaceFirst(RegExp(r'^[a-z]+://'), '');
  }
  return uri!.hasPort ? '$host:${uri.port}' : host;
}

/// The empty chat: a hero orb, a greeting, and a few ways in.
///
/// While Hermes is unreachable it becomes the offline card (a dimmed orb,
/// "Can't reach Hermes", the host, Retry and Server settings) and stays
/// there through retries until the connection comes back.
class ChatEmptyState extends StatefulWidget {
  const ChatEmptyState({
    super.key,
    required this.connected,
    this.connecting = false,
    this.modelLabel,
    this.host,
    this.recent = const [],
    this.onOpenRecent,
    this.onTalk,
    this.onCommands,
    this.onRetry,
    this.onSettings,
    this.now,
  });

  final bool connected;
  final bool connecting;
  final String? modelLabel;
  final String? host;

  /// Up to two recent conversations to offer as 'Continue · …'.
  final List<ConversationSummary> recent;
  final ValueChanged<ConversationSummary>? onOpenRecent;

  /// Starts voice; receives the global point the glow should bloom from.
  final ValueChanged<Offset>? onTalk;

  /// Opens the slash command palette.
  final VoidCallback? onCommands;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;

  /// Overrides the clock (tests).
  final DateTime? now;

  @override
  State<ChatEmptyState> createState() => _ChatEmptyStateState();
}

class _ChatEmptyStateState extends State<ChatEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final _IntroCurves _curves = _IntroCurves(_intro);
  var _offlineSeen = false;

  @override
  void initState() {
    super.initState();
    _offlineSeen = !widget.connected && !widget.connecting;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.isDismissed) {
      if (AppMotion.reduced(context)) {
        _intro.duration = AppMotion.short;
      }
      _intro.forward();
    }
  }

  @override
  void didUpdateWidget(covariant ChatEmptyState oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected) {
      _offlineSeen = false;
    } else if (!widget.connecting) {
      _offlineSeen = true;
    }
  }

  @override
  void dispose() {
    _curves.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final offline = !widget.connected && (!widget.connecting || _offlineSeen);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final fit = ((height - 360) / 260).clamp(0.0, 1.0);
        final orb = lerpDouble(64, 112, fit)!;
        final top = math.max(AppSpace.x4, height * 0.34 - orb / 2 - 12);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpace.x6,
            top,
            AppSpace.x6,
            AppSpace.x6,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AnimatedSwitcher(
                duration: AppMotion.medium,
                switchInCurve: AppMotion.standard,
                switchOutCurve: AppMotion.standard,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, ?current],
                ),
                child: offline
                    ? _Offline(
                        key: const ValueKey('offline'),
                        orbSize: orb,
                        host: widget.host,
                        busy: widget.connecting,
                        onRetry: widget.onRetry,
                        onSettings: widget.onSettings,
                        intro: _curves,
                        reduced: reduced,
                      )
                    : _Welcome(
                        key: const ValueKey('welcome'),
                        orbSize: orb,
                        greeting: greetingFor(widget.now ?? DateTime.now()),
                        ready: widget.connected && !widget.connecting,
                        modelLabel: widget.modelLabel,
                        recent: widget.recent,
                        onOpenRecent: widget.onOpenRecent,
                        onTalk: widget.onTalk,
                        onCommands: widget.onCommands,
                        intro: _curves,
                        reduced: reduced,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({
    super.key,
    required this.orbSize,
    required this.greeting,
    required this.ready,
    required this.modelLabel,
    required this.recent,
    required this.onOpenRecent,
    required this.onTalk,
    required this.onCommands,
    required this.intro,
    required this.reduced,
  });

  final double orbSize;
  final String greeting;
  final bool ready;
  final String? modelLabel;
  final List<ConversationSummary> recent;
  final ValueChanged<ConversationSummary>? onOpenRecent;
  final ValueChanged<Offset>? onTalk;
  final VoidCallback? onCommands;
  final _IntroCurves intro;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final model = modelLabel?.trim() ?? '';
    final chips = <Widget>[
      if (onOpenRecent != null)
        for (final item in recent.take(2))
          _PromptChip(
            leading: Icon(
              Icons.history_rounded,
              size: 18,
              color: AppColors.secondary,
            ),
            label: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Continue · ',
                    style: TextStyle(color: AppColors.secondary),
                  ),
                  TextSpan(text: item.title),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: (_) => onOpenRecent!(item),
          ),
      if (onTalk != null)
        _PromptChip(
          leading: Icon(Icons.mic_rounded, size: 18, color: AppColors.gold),
          // Tapping starts listening hands-free, so the label names the
          // action (holding is the composer mic's gesture).
          label: const Text('Talk to Hermsy'),
          onTap: onTalk!,
        ),
      if (onCommands != null)
        _PromptChip(
          leading: Text(
            '/help',
            style: AppText.code.copyWith(
              color: AppColors.gold,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          label: const Text('Commands'),
          onTap: (_) => onCommands!(),
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Rise(
          animation: intro.orb,
          scaleFrom: reduced ? 1 : 0.9,
          travel: 0,
          child: _HeroOrb(
            size: orbSize,
            live: true,
            lit: true,
            onTap: ready ? onTalk : null,
          ),
        ),
        const SizedBox(height: 28),
        _Rise(
          animation: intro.title,
          travel: reduced ? 0 : 12,
          child: Text(
            greeting,
            textAlign: TextAlign.center,
            style: AppText.display,
          ),
        ),
        const SizedBox(height: AppSpace.x2),
        _Rise(
          animation: intro.subtitle,
          travel: reduced ? 0 : 10,
          child: AnimatedSwitcher(
            duration: AppMotion.medium,
            child: ready
                ? Wrap(
                    key: const ValueKey('ready'),
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpace.x2,
                    runSpacing: AppSpace.x1,
                    children: [
                      Text('Hermsy is ready', style: AppText.bodySmall),
                      if (model.isNotEmpty) _ModelChip(label: model),
                    ],
                  )
                : Text(
                    'Connecting to Hermes…',
                    key: const ValueKey('connecting'),
                    textAlign: TextAlign.center,
                    style: AppText.bodySmall.copyWith(color: AppColors.hint),
                  ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.medium,
          curve: AppMotion.standard,
          alignment: Alignment.topCenter,
          child: ready && chips.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: _Rise(
                    animation: intro.actions,
                    travel: reduced ? 0 : 10,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppSpace.x2,
                      runSpacing: AppSpace.x2,
                      children: chips,
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline({
    super.key,
    required this.orbSize,
    required this.host,
    required this.busy,
    required this.onRetry,
    required this.onSettings,
    required this.intro,
    required this.reduced,
  });

  final double orbSize;
  final String? host;
  final bool busy;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;
  final _IntroCurves intro;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final where = host?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Rise(
          animation: intro.orb,
          scaleFrom: reduced ? 1 : 0.9,
          travel: 0,
          child: Opacity(
            opacity: 0.7,
            child: _HeroOrb(size: orbSize, live: false, lit: false),
          ),
        ),
        const SizedBox(height: 28),
        _Rise(
          animation: intro.title,
          travel: reduced ? 0 : 12,
          child: Text(
            "Can't reach Hermes",
            textAlign: TextAlign.center,
            style: AppText.largeTitle,
          ),
        ),
        const SizedBox(height: AppSpace.x2),
        _Rise(
          animation: intro.subtitle,
          travel: reduced ? 0 : 10,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns_rounded, size: 14, color: AppColors.hint),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  where.isEmpty ? 'No server set' : where,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.code.copyWith(color: AppColors.secondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.x6),
        _Rise(
          animation: intro.actions,
          travel: reduced ? 0 : 10,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpace.x3,
            runSpacing: AppSpace.x3,
            children: [
              if (onRetry != null)
                GoldButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  expanded: false,
                  busy: busy,
                  onPressed: onRetry,
                ),
              if (onSettings != null)
                GhostButton(
                  label: 'Server settings',
                  icon: Icons.tune_rounded,
                  onPressed: onSettings,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The staggered entrance: orb, greeting, subtitle, then the actions.
class _IntroCurves {
  _IntroCurves(Animation<double> parent)
    : orb = _interval(parent, 0, 0.62),
      title = _interval(parent, 0.1, 0.72),
      subtitle = _interval(parent, 0.18, 0.8),
      actions = _interval(parent, 0.26, 0.92);

  final CurvedAnimation orb;
  final CurvedAnimation title;
  final CurvedAnimation subtitle;
  final CurvedAnimation actions;

  static CurvedAnimation _interval(
    Animation<double> parent,
    double begin,
    double end,
  ) {
    return CurvedAnimation(
      parent: parent,
      curve: Interval(begin, end, curve: AppMotion.enter),
    );
  }

  void dispose() {
    orb.dispose();
    title.dispose();
    subtitle.dispose();
    actions.dispose();
  }
}

/// Fades a child in while it rises [travel] dp and grows from [scaleFrom].
class _Rise extends StatelessWidget {
  const _Rise({
    required this.animation,
    required this.child,
    this.travel = 12,
    this.scaleFrom = 1,
  });

  final Animation<double> animation;
  final Widget child;
  final double travel;
  final double scaleFrom;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: travel == 0 && scaleFrom == 1
          ? child
          : AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final t = animation.value;
                return Transform.translate(
                  offset: Offset(0, travel * (1 - t)),
                  child: Transform.scale(
                    scale: scaleFrom + (1 - scaleFrom) * t,
                    child: child,
                  ),
                );
              },
              child: child,
            ),
    );
  }
}

class _HeroOrb extends StatelessWidget {
  const _HeroOrb({
    required this.size,
    required this.live,
    required this.lit,
    this.onTap,
  });

  final double size;
  final bool live;
  final bool lit;
  final ValueChanged<Offset>? onTap;

  @override
  Widget build(BuildContext context) {
    final orb = RepaintBoundary(
      child: FrankOrb(
        size: size,
        mood: AssistantMood.idle,
        live: live,
        lit: lit,
      ),
    );
    if (onTap == null) {
      return orb;
    }
    return Semantics(
      button: true,
      label: 'Talk to Hermsy',
      excludeSemantics: true,
      child: Pressable(
        pressedScale: 0.94,
        onTap: () => onTap!(_globalCentre(context)),
        child: orb,
      ),
    );
  }
}

Offset _globalCentre(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return Offset.zero;
  }
  return box.localToGlobal(box.size.center(Offset.zero));
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.veil(0x0A),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.micro.copyWith(color: AppColors.secondary),
      ),
    );
  }
}

/// A 44dp glass suggestion chip. [onTap] receives the chip's global centre.
class _PromptChip extends StatelessWidget {
  const _PromptChip({
    required this.leading,
    required this.label,
    required this.onTap,
  });

  final Widget leading;
  final Widget label;
  final ValueChanged<Offset> onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Builder(
        builder: (context) {
          return Pressable(
            onTap: () => onTap(_globalCentre(context)),
            child: GlassPanel(
              blur: 0,
              radius: AppRadii.md,
              color: AppColors.surface.withValues(alpha: 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    leading,
                    const SizedBox(width: AppSpace.x2),
                    Flexible(
                      child: DefaultTextStyle.merge(
                        style: AppText.label.copyWith(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: label,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
