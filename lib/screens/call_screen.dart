import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/relay_client.dart';
import '../state/assistant_mood.dart';
import '../state/chat_controller.dart';
import '../theme/app_theme.dart';
import '../voice/audio_route.dart';
import '../voice/call_controller.dart';
import '../voice/on_device_voice.dart';
import '../widgets/frank_backdrop.dart';
import '../widgets/frank_orb.dart';
import '../widgets/ui/frank_ui.dart';

/// Opens a live call with Frank over [chat]. The call's turns are saved in
/// that chat's thread.
Future<void> showCallScreen(
  BuildContext context, {
  required ChatController chat,
  required OnDeviceVoice voice,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: AppMotion.reduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 280),
      pageBuilder: (context, animation, _) => FadeTransition(
        opacity: animation,
        child: CallScreen(chat: chat, voice: voice),
      ),
    ),
  );
}

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.chat,
    required this.voice,
    this.controller,
  });

  final ChatController chat;
  final OnDeviceVoice voice;

  /// A prepared call (tests); otherwise the screen starts its own.
  final CallController? controller;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallController _call =
      widget.controller ??
      CallController(
        chat: widget.chat,
        voice: widget.voice,
        voiceId: widget.chat.settings?.callVoice ?? defaultKokoroVoice,
        speed: widget.chat.settings?.callSpeed ?? 1.0,
        cloud: _cloudVoice(),
        fallback: widget.chat.settings?.callFallback ?? true,
        pause: Duration(
          milliseconds: ((widget.chat.settings?.callPause ?? 1.0) * 1000)
              .round(),
        ),
      );

  /// The cloud voice chosen in Settings, if one is.
  ({RelayClient relay, String provider, String voice})? _cloudVoice() {
    final settings = widget.chat.settings;
    final engine = settings?.callEngine ?? 'kokoro';
    final voice = settings?.cloudVoice(engine);
    if (engine == 'kokoro' || voice == null) {
      return null;
    }
    return (
      relay: RelayClient(widget.chat.config),
      provider: engine,
      voice: voice,
    );
  }

  final _started = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _call.addListener(_changed);
    if (widget.controller == null) {
      unawaited(_call.start());
    }
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  var _closing = false;

  void _changed() {
    if (_call.phase == CallPhase.ended && _call.endedOffScreen && !_closing) {
      // Ended after a goodbye or from the notification: close, as if you
      // had tapped End.
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
      return;
    }
    if (_call.phase == CallPhase.ended && _call.error != null && mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(_call.error!)));
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _call.removeListener(_changed);
    if (widget.controller == null) {
      _call.dispose();
    }
    super.dispose();
  }

  Future<void> _hangUp() async {
    HapticFeedback.mediumImpact();
    await _call.end();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String get _elapsed {
    final seconds = DateTime.now().difference(_started).inSeconds;
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_hangUp());
        }
      },
      child: FrankBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: ListenableBuilder(
              listenable: _call,
              builder: (context, _) {
                final size = MediaQuery.sizeOf(context);
                final orb = math.min(size.width * 0.62, 280.0);
                return Column(
                  children: [
                    const SizedBox(height: AppSpace.x4),
                    Text(
                      widget.chat.conversationTitle ?? 'Hermsy',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: AppSpace.x1),
                    // Where you hear Frank: a headset by name, or the speaker.
                    ValueListenableBuilder<AudioRouteInfo?>(
                      valueListenable: AudioRoute.current,
                      builder: (context, route, _) => Text(
                        [
                          'Voice call',
                          _elapsed,
                          ?route?.label,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.tabular.copyWith(color: AppColors.hint),
                      ),
                    ),
                    const Spacer(),
                    FrankOrb(
                      size: orb,
                      live: true,
                      listening: _call.phase == CallPhase.listening,
                      mood: _mood(_call.phase),
                      level: _call.level,
                    ),
                    const SizedBox(height: AppSpace.x6),
                    Text(
                      _label(),
                      textAlign: TextAlign.center,
                      style: AppText.label.copyWith(
                        fontSize: 17,
                        color: AppColors.secondary,
                      ),
                    ),
                    if (_call.fallbackReason != null) ...[
                      const SizedBox(height: AppSpace.x2),
                      Text(
                        "Cloud voice unavailable · using the phone's voice",
                        style: TextStyle(color: AppColors.hint, fontSize: 13),
                      ),
                    ] else if (_call.speechError != null) ...[
                      const SizedBox(height: AppSpace.x2),
                      Text(
                        'Cloud voice unavailable · replies show as captions',
                        style: TextStyle(color: AppColors.danger, fontSize: 13),
                      ),
                    ],
                    const Spacer(),
                    if (_call.captions) _Captions(call: _call),
                    const SizedBox(height: AppSpace.x6),
                    _Controls(call: _call, onHangUp: _hangUp),
                    const SizedBox(height: AppSpace.x6),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _label() {
    if (_call.muted && _call.phase == CallPhase.listening) {
      return 'Muted';
    }
    return switch (_call.phase) {
      CallPhase.starting => 'Waking up…',
      CallPhase.listening => 'Listening',
      CallPhase.thinking => _call.activity ?? 'Thinking…',
      CallPhase.speaking => _call.activity ?? 'Speaking',
      CallPhase.ended => 'Call ended',
    };
  }

  static AssistantMood _mood(CallPhase phase) => switch (phase) {
    CallPhase.starting => AssistantMood.thinking,
    CallPhase.listening => AssistantMood.listening,
    CallPhase.thinking => AssistantMood.thinking,
    CallPhase.speaking => AssistantMood.speaking,
    CallPhase.ended => AssistantMood.idle,
  };
}

/// What you said and what Frank is saying, as text.
class _Captions extends StatelessWidget {
  const _Captions({required this.call});

  final CallController call;

  @override
  Widget build(BuildContext context) {
    final reply = call.reply.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.x8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 180),
        child: _FadedEdges(
          child: SingleChildScrollView(
            reverse: true,
            child: Column(
              children: [
                if (call.heard.isNotEmpty)
                  Text(
                    call.heard,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.hint,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                if (reply.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.x3),
                  Text(
                    reply,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades a scrolling caption into the background where text runs on past
/// an edge, instead of cutting it at a hard line. An edge with nothing
/// beyond it stays crisp, so a short caption is never faded.
class _FadedEdges extends StatefulWidget {
  const _FadedEdges({required this.child});

  final Widget child;

  @override
  State<_FadedEdges> createState() => _FadedEdgesState();
}

class _FadedEdgesState extends State<_FadedEdges> {
  static const _fade = 44.0;
  var _top = false;
  var _bottom = false;

  bool _onMetrics(ScrollMetrics metrics) {
    // The caption scrolls reversed: what lies after is above, before below.
    final top = metrics.extentAfter > 0.5;
    final bottom = metrics.extentBefore > 0.5;
    if (top != _top || bottom != _bottom) {
      setState(() {
        _top = top;
        _bottom = bottom;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (note) => _onMetrics(note.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (note) => _onMetrics(note.metrics),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final stop = bounds.height <= 0
                ? 0.0
                : (_fade / bounds.height).clamp(0.0, 0.5);
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _top ? Colors.transparent : Colors.white,
                Colors.white,
                Colors.white,
                _bottom ? Colors.transparent : Colors.white,
              ],
              stops: [0, stop, 1 - stop, 1],
            ).createShader(bounds);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.call, required this.onHangUp});

  final CallController call;
  final VoidCallback onHangUp;

  /// Calm call controls, as in other voice-first apps: small dark circles,
  /// with a light × at the bottom right to end the call.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.x5),
      child: Row(
        children: [
          _RoundButton(
            tooltip: call.captions ? 'Hide captions' : 'Show captions',
            icon: call.captions
                ? Icons.closed_caption_rounded
                : Icons.closed_caption_off_outlined,
            active: !call.captions,
            onPressed: call.toggleCaptions,
          ),
          const Spacer(),
          _RoundButton(
            tooltip: call.muted ? 'Unmute' : 'Mute',
            icon: call.muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
            active: call.muted,
            onPressed: call.toggleMute,
          ),
          const SizedBox(width: AppSpace.x3),
          _RoundButton(
            tooltip: 'End call',
            icon: Icons.close_rounded,
            light: true,
            onPressed: onHangUp,
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.light = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  /// On: muted, or captions hidden. The glyph turns gold.
  final bool active;

  /// The end-call ×: a light circle with a dark glyph.
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Pressable(
          onTap: onPressed,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: light ? AppColors.text : AppColors.surfaceHigh,
              shape: BoxShape.circle,
              border: light ? null : Border.all(color: AppColors.hairline),
            ),
            child: Icon(
              icon,
              size: 26,
              color: light
                  ? AppColors.background
                  : active
                  ? AppColors.gold
                  : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
