import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/delivery_inbox.dart';
import '../state/assistant_mood.dart';
import '../theme/app_theme.dart';
import 'frank_orb.dart';
import 'tool_activity_line.dart' show cleanToolLabel;
import 'ui/frank_ui.dart';

export 'tool_activity_line.dart' show cleanToolLabel;

/// What tapping the status line does.
enum ChatStatusAction { none, retry, stopSpeaking }

/// One line of header status: copy, its color, and the 6dp dot.
@immutable
class ChatStatus {
  const ChatStatus(
    this.label, {
    required this.color,
    required this.dot,
    this.busy = false,
    this.action = ChatStatusAction.none,
  });

  final String label;
  final Color color;
  final Color dot;

  /// Frank is doing something; the dot glows.
  final bool busy;
  final ChatStatusAction action;

  @override
  bool operator ==(Object other) {
    return other is ChatStatus &&
        other.label == label &&
        other.color == color &&
        other.dot == dot &&
        other.busy == busy &&
        other.action == action;
  }

  @override
  int get hashCode => Object.hash(label, color, dot, busy, action);
}

Color get _transcribingBlue => AppColors.statusTranscribing;
Color get _thinkingViolet => AppColors.statusThinking;
Color get _speakingWarm => AppColors.statusSpeaking;

/// The header status for [mood]. Never shows raw controller strings.
ChatStatus chatStatusFor({
  required AssistantMood mood,
  required bool loading,
  required bool connected,
  bool onDevice = false,
  String? toolLabel,
  String? modelLabel,
  bool showError = true,
}) {
  final busy = moodIsBusy(mood) && mood != AssistantMood.reconnecting;
  if (!busy) {
    if (loading) {
      return ChatStatus(
        'Connecting…',
        color: AppColors.secondary,
        dot: AppColors.hint,
      );
    }
    if (!connected) {
      return ChatStatus(
        'Offline · tap to retry',
        color: AppColors.amber,
        dot: AppColors.amber,
        action: ChatStatusAction.retry,
      );
    }
  }
  switch (mood) {
    case AssistantMood.listening:
      return ChatStatus(
        onDevice ? 'Listening on device' : 'Listening',
        color: AppColors.ion,
        dot: AppColors.ion,
        busy: true,
      );
    case AssistantMood.transcribing:
      return ChatStatus(
        'Transcribing',
        color: _transcribingBlue,
        dot: _transcribingBlue,
        busy: true,
      );
    case AssistantMood.thinking:
      return ChatStatus(
        'Thinking',
        color: _thinkingViolet,
        dot: _thinkingViolet,
        busy: true,
      );
    case AssistantMood.tool:
      return ChatStatus(
        cleanToolLabel(toolLabel),
        color: _transcribingBlue,
        dot: _transcribingBlue,
        busy: true,
      );
    case AssistantMood.responding:
      return ChatStatus(
        'Replying',
        color: AppColors.text,
        dot: AppColors.ion,
        busy: true,
      );
    case AssistantMood.speaking:
      return ChatStatus(
        'Speaking · tap to stop',
        color: _speakingWarm,
        dot: _speakingWarm,
        busy: true,
        action: ChatStatusAction.stopSpeaking,
      );
    case AssistantMood.reconnecting:
      return ChatStatus(
        'Reconnecting…',
        color: AppColors.amber,
        dot: AppColors.amber,
      );
    case AssistantMood.error when showError:
      return ChatStatus(
        'Something went wrong',
        color: AppColors.danger,
        dot: AppColors.signal,
      );
    case AssistantMood.error:
    case AssistantMood.idle:
      final model = modelLabel?.trim() ?? '';
      return ChatStatus(
        model.isEmpty ? 'Ready' : 'Ready · $model',
        color: AppColors.secondary,
        dot: AppColors.mint,
      );
  }
}

/// The chat screen's top bar: Chats, the orb (Frank's "AI button"), the
/// title with a live status line, Find and New chat.
///
/// Transparent over the canvas; it turns into a glass bar with a bottom
/// hairline once content scrolls under it ([scrolledUnder]) or while
/// finding. While [finding], the row cross-fades into [findBar].
class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.title,
    required this.status,
    required this.mood,
    required this.onOpenDrawer,
    required this.onOrbTap,
    required this.onOpenConversation,
    this.level,
    this.lit = true,
    this.orbEnabled = true,
    this.orbLabel = 'Talk to Hermsy',
    this.onStatusAction,
    this.onFind,
    this.onBrief,
    this.onNewChat,
    this.finding = false,
    this.findBar,
    this.scrolledUnder,
  });

  final String title;
  final ChatStatus status;
  final AssistantMood mood;
  final ValueListenable<double>? level;

  /// False dims the orb (offline).
  final bool lit;

  final VoidCallback onOpenDrawer;

  /// Tap on the orb, with its global centre so the glow can bloom there.
  final ValueChanged<Offset> onOrbTap;
  final bool orbEnabled;

  /// What a tap on the orb does, for screen readers.
  final String orbLabel;

  /// Opens the conversation sheet (title tap, header long-press).
  final VoidCallback onOpenConversation;

  /// Runs the status line's action (retry, stop speaking).
  final VoidCallback? onStatusAction;
  final VoidCallback? onFind;

  /// Opens Frank's Brief, the day at a glance.
  final VoidCallback? onBrief;
  final VoidCallback? onNewChat;
  final bool finding;
  final Widget? findBar;
  final ValueListenable<bool>? scrolledUnder;

  /// Height below the status bar.
  static const height = 60.0;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final top = MediaQuery.paddingOf(context).top;
    final showFind = finding && findBar != null;
    final row = showFind
        ? KeyedSubtree(key: const ValueKey('find'), child: findBar!)
        : KeyedSubtree(
            key: const ValueKey('header'),
            child: _HeaderRow(
              title: title,
              status: status,
              mood: mood,
              level: level,
              lit: lit,
              orbEnabled: orbEnabled,
              orbLabel: orbLabel,
              onOpenDrawer: onOpenDrawer,
              onOrbTap: onOrbTap,
              onOpenConversation: onOpenConversation,
              onStatusAction: onStatusAction,
              onFind: onFind,
              onBrief: onBrief,
              onNewChat: onNewChat,
            ),
          );

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Stack(
        children: [
          Positioned.fill(
            child: _HeaderGlass(forced: finding, scrolledUnder: scrolledUnder),
          ),
          Padding(
            padding: EdgeInsets.only(top: top),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: height),
              child: Material(
                type: MaterialType.transparency,
                child: AnimatedSwitcher(
                  duration: AppMotion.short,
                  switchInCurve: AppMotion.enter,
                  switchOutCurve: AppMotion.exit,
                  transitionBuilder: slideFadeTransition(
                    current: row.key!,
                    travel: const Offset(8, 0),
                    reduced: reduced,
                  ),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.center,
                    children: [...previous, ?current],
                  ),
                  child: row,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An [AnimatedSwitcher] transition: the new child fades in from [travel]
/// away, the old one fades out moving the opposite way. Fade only when
/// [reduced].
AnimatedSwitcherTransitionBuilder slideFadeTransition({
  required Key current,
  required Offset travel,
  bool reduced = false,
}) {
  return (child, animation) {
    final from = child.key == current ? travel : -travel;
    return FadeTransition(
      opacity: animation,
      child: reduced
          ? child
          : AnimatedBuilder(
              animation: animation,
              builder: (context, child) => Transform.translate(
                offset: from * (1 - animation.value),
                child: child,
              ),
              child: child,
            ),
    );
  };
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.title,
    required this.status,
    required this.mood,
    required this.level,
    required this.lit,
    required this.orbEnabled,
    required this.orbLabel,
    required this.onOpenDrawer,
    required this.onOrbTap,
    required this.onOpenConversation,
    required this.onStatusAction,
    required this.onFind,
    required this.onBrief,
    required this.onNewChat,
  });

  final String title;
  final ChatStatus status;
  final AssistantMood mood;
  final ValueListenable<double>? level;
  final bool lit;
  final bool orbEnabled;
  final String orbLabel;
  final VoidCallback onOpenDrawer;
  final ValueChanged<Offset> onOrbTap;
  final VoidCallback onOpenConversation;
  final VoidCallback? onStatusAction;
  final VoidCallback? onFind;
  final VoidCallback? onBrief;
  final VoidCallback? onNewChat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.x1),
      child: Row(
        children: [
          // A gold dot while the Inbox has something unread.
          ValueListenableBuilder<int>(
            valueListenable: DeliveryInbox.unread,
            builder: (context, unread, button) => Stack(
              clipBehavior: Clip.none,
              children: [
                button!,
                if (unread > 0)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IgnorePointer(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.background,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            child: FrankIconButton(
              icon: Icons.menu_rounded,
              tooltip: 'Chats',
              onPressed: onOpenDrawer,
            ),
          ),
          _HeaderOrb(
            mood: mood,
            level: level,
            lit: lit,
            enabled: orbEnabled,
            label: orbLabel,
            onTap: onOrbTap,
            onLongPress: onOpenConversation,
          ),
          Expanded(
            child: _TitleBlock(
              title: title,
              status: status,
              onTap:
                  status.action != ChatStatusAction.none &&
                      onStatusAction != null
                  ? onStatusAction!
                  : onOpenConversation,
              onLongPress: onOpenConversation,
            ),
          ),
          if (onBrief != null)
            FrankIconButton(
              icon: Icons.wb_twilight_rounded,
              tooltip: 'Brief',
              onPressed: onBrief,
            ),
          FrankIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Find in chat',
            onPressed: onFind,
          ),
          FrankIconButton(
            icon: Icons.edit_square,
            tooltip: 'New conversation',
            size: 21,
            onPressed: onNewChat,
          ),
        ],
      ),
    );
  }
}

class _HeaderOrb extends StatelessWidget {
  const _HeaderOrb({
    required this.mood,
    required this.level,
    required this.lit,
    required this.enabled,
    required this.label,
    required this.onTap,
    required this.onLongPress,
  });

  final AssistantMood mood;
  final ValueListenable<double>? level;
  final bool lit;
  final bool enabled;
  final String label;
  final ValueChanged<Offset> onTap;
  final VoidCallback onLongPress;

  static const _size = 30.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        pressedScale: 0.88,
        onTap: enabled ? () => onTap(_globalCentre(context)) : null,
        onLongPress: onLongPress,
        child: SizedBox.square(
          dimension: AppSpace.minTouch,
          child: Center(
            child: RepaintBoundary(
              child: FrankOrb(size: _size, mood: mood, level: level, lit: lit),
            ),
          ),
        ),
      ),
    );
  }

  static Offset _globalCentre(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return Offset.zero;
    }
    return box.localToGlobal(box.size.center(Offset.zero));
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.title,
    required this.status,
    required this.onTap,
    required this.onLongPress,
  });

  final String title;
  final ChatStatus status;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    return Semantics(
      button: true,
      onTapHint: switch (status.action) {
        ChatStatusAction.retry => 'Retry',
        ChatStatusAction.stopSpeaking => 'Stop speaking',
        ChatStatusAction.none => 'Conversation options',
      },
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: AppMotion.short,
                      layoutBuilder: _leftStack,
                      child: Text(
                        title,
                        key: ValueKey(title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.hint,
                  ),
                ],
              ),
              const SizedBox(height: 1),
              _StatusLine(status: status, reduced: reduced),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _leftStack(Widget? current, List<Widget> previous) {
  return Stack(
    alignment: Alignment.centerLeft,
    children: [...previous, ?current],
  );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, required this.reduced});

  final ChatStatus status;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final key = ValueKey(status.label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: AppMotion.short,
          curve: AppMotion.standard,
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: status.dot,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: status.dot.withValues(alpha: status.busy ? 0.7 : 0),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            layoutBuilder: _leftStack,
            transitionBuilder: slideFadeTransition(
              current: key,
              travel: const Offset(0, 6),
              reduced: reduced,
            ),
            child: Text(
              status.label,
              key: key,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: status.color),
            ),
          ),
        ),
      ],
    );
  }
}

/// The header's glass: blur and fill ramp in together (160ms) when content
/// scrolls under, and leave the tree entirely when clear.
class _HeaderGlass extends StatefulWidget {
  const _HeaderGlass({required this.forced, required this.scrolledUnder});

  final bool forced;
  final ValueListenable<bool>? scrolledUnder;

  @override
  State<_HeaderGlass> createState() => _HeaderGlassState();
}

class _HeaderGlassState extends State<_HeaderGlass>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glass = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: _target ? 1 : 0,
  );

  bool get _target => widget.forced || (widget.scrolledUnder?.value ?? false);

  @override
  void initState() {
    super.initState();
    widget.scrolledUnder?.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant _HeaderGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrolledUnder != widget.scrolledUnder) {
      oldWidget.scrolledUnder?.removeListener(_sync);
      widget.scrolledUnder?.addListener(_sync);
    }
    _sync();
  }

  void _sync() {
    if (_target) {
      _glass.forward();
    } else {
      _glass.reverse();
    }
  }

  @override
  void dispose() {
    widget.scrolledUnder?.removeListener(_sync);
    _glass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glass,
      builder: (context, _) {
        final t = AppMotion.standard.transform(_glass.value);
        if (t <= 0.001) {
          return const SizedBox.shrink();
        }
        final sigma = 24 * t;
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.72 * t),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.hairline.withValues(
                      alpha: AppColors.hairline.a * t,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
