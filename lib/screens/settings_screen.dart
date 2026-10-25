import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/app_config.dart';
import '../config/app_version.dart';
import '../presence/presence_engine.dart';
import '../services/app_settings.dart';
import '../services/connection_store.dart';
import '../services/push_service.dart';
import '../services/relay_client.dart';
import '../services/voice_models.dart';
import '../voice/on_device_voice.dart';
import '../state/chat_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/frank_backdrop.dart';
import '../widgets/presence_picker.dart';
import '../widgets/ui/frank_ui.dart';
import 'server_settings_screen.dart';
import 'brief_settings_screen.dart';
import 'voice_models_screen.dart';
import 'voice_picker_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.connection,
    required this.onChangePin,
    required this.onLock,
    this.verifyConnection,
    this.onConnectionSaved,
    this.chat,
    this.push,
    this.voiceModels,
    this.onDeviceVoice,
  });

  final AppSettings settings;
  final ConnectionStore connection;
  final VoidCallback onChangePin;
  final VoidCallback onLock;
  final Future<void> Function(AppConfig config)? verifyConnection;
  final Future<void> Function(AppConfig config)? onConnectionSaved;

  /// The live conversation, when there is one. It lights the server status
  /// dot and names the agent; without it those simply stay hidden.
  final ChatController? chat;

  /// Push notifications; the Notifications group shows only with it.
  final PushService? push;

  /// The on-device voice models; the Voice group shows only with them.
  final VoiceModelStore? voiceModels;

  /// Plays voice previews in Frank's voice picker.
  final OnDeviceVoice? onDeviceVoice;

  /// Settings home: the server at the top, then each area as one row that
  /// says how it is set, opening a page of its own. No tabs: on a phone they
  /// hide settings behind swipes; a short list with live summaries shows the
  /// state at a glance and is one tap from any setting.
  @override
  Widget build(BuildContext context) {
    final listenable = Listenable.merge([settings, connection, ?push]);
    return FrankBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListenableBuilder(
          listenable: listenable,
          builder: (context, _) {
            return CustomScrollView(
              slivers: [
                const LargeTitleSliverBar(title: 'Settings'),
                SliverPadding(
                  padding: _contentPadding(context),
                  sliver: SliverList.list(
                    children: [
                      _withChat(_serverGroup),
                      const _GroupGap(),
                      FrankGroup(
                        children: [
                          _CategoryTile(
                            icon: Icons.auto_awesome_rounded,
                            color: AppColors.iris,
                            title: 'Appearance',
                            subtitle: _appearanceSummary(),
                            onTap: () => _open(
                              context,
                              'Appearance',
                              (context) => [
                                _frankGroup(context, _reduced(context)),
                              ],
                            ),
                          ),
                          ListenableBuilder(
                            listenable: voiceModels ?? settings,
                            builder: (context, _) => _CategoryTile(
                              icon: Icons.graphic_eq_rounded,
                              color: AppColors.ion,
                              title: 'Voice',
                              subtitle: _voiceSummary(),
                              onTap: () => _open(
                                context,
                                'Voice',
                                (context) => [_voiceGroup(context)],
                                also: voiceModels,
                              ),
                            ),
                          ),
                          _CategoryTile(
                            icon: Icons.wb_twilight_rounded,
                            color: AppColors.solar,
                            title: 'Brief',
                            subtitle:
                                '${settings.briefShown.length} of '
                                '${settings.briefOrder.length} sections shown',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    BriefSettingsScreen(settings: settings),
                              ),
                            ),
                          ),
                          if (push case final push?)
                            _CategoryTile(
                              icon: Icons.notifications_none_rounded,
                              color: AppColors.rose,
                              title: 'Notifications',
                              subtitle: _notificationsSummary(push),
                              onTap: () => _open(
                                context,
                                'Notifications',
                                (context) => [
                                  _notificationsGroup(context, push),
                                ],
                                also: push,
                              ),
                            ),
                        ],
                      ),
                      const _GroupGap(),
                      FrankGroup(
                        children: [
                          _CategoryTile(
                            icon: Icons.lock_rounded,
                            color: AppColors.mint,
                            title: 'Privacy & security',
                            subtitle: _privacySummary(),
                            onTap: () => _open(
                              context,
                              'Privacy & security',
                              (context) => [
                                _privacyGroup(context, _reduced(context)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const _GroupGap(),
                      const MicroLabel('About'),
                      _withChat((context) => _aboutGroup()),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _reduced(BuildContext context) =>
      AppMotion.reduced(context) || settings.reduceMotion;

  /// Opens one area's page. It rebuilds with the settings (and [also]).
  void _open(
    BuildContext context,
    String title,
    List<Widget> Function(BuildContext context) children, {
    Listenable? also,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _SettingsPage(
          title: title,
          listenable: Listenable.merge([settings, connection, ?also]),
          children: children,
        ),
      ),
    );
  }

  String _appearanceSummary() {
    final glow = switch (settings.glowIntensity) {
      GlowIntensity.subtle => 'subtle glow',
      GlowIntensity.balanced => 'balanced glow',
      GlowIntensity.vivid => 'vivid glow',
    };
    return [
      AppSettings.presenceLabel(settings.presence),
      if (settings.presence != PresenceStyle.off) glow,
      if (settings.reduceMotion) 'reduced motion',
    ].join(' · ');
  }

  String _voiceSummary() {
    final models = voiceModels;
    if (models == null) {
      return settings.speakReplies
          ? 'Reads replies aloud'
          : 'Replies stay as text';
    }
    return models.allReady
        ? callVoiceSummary(settings)
        : 'Voice models not downloaded';
  }

  String _privacySummary() {
    return [
      settings.autoLock
          ? 'Locks after ${AppSettings.labelFor(settings.autoLockAfter).toLowerCase()}'
          : 'Locks only when you ask',
      if (settings.hideInSwitcher) 'hidden in recents',
    ].join(' · ');
  }

  String _notificationsSummary(PushService push) => switch (push.status) {
    PushStatus.off => 'Not set up in this build',
    PushStatus.starting => 'Connecting…',
    PushStatus.denied => 'Off in Android settings',
    PushStatus.ready =>
      push.relayError != null ? 'On · plugin unreachable' : 'On',
    PushStatus.failed => 'Could not reach Firebase',
  };

  Widget _voiceGroup(BuildContext context) {
    final models = voiceModels;
    return FrankGroup(
      children: [
        if (models != null) ...[
          FrankTile(
            icon: Icons.record_voice_over_rounded,
            title: "Hermsy's voice",
            subtitle: callVoiceSummary(settings),
            chevron: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => VoicePickerScreen(
                  settings: settings,
                  voice: onDeviceVoice,
                  relay: connection.current.looksConfigured
                      ? RelayClient(connection.current)
                      : null,
                ),
              ),
            ),
          ),
          FrankTile(
            icon: Icons.download_for_offline_outlined,
            title: 'Voice models',
            subtitle: voiceModelsSummary(models),
            chevron: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) =>
                    VoiceModelsScreen(store: models, settings: settings),
              ),
            ),
          ),
        ],
        FrankSwitchTile(
          icon: Icons.volume_up_outlined,
          title: 'Speak replies',
          subtitle: 'Read Hermsy\'s replies aloud when Hermes can speak',
          value: settings.speakReplies,
          onChanged: settings.setSpeakReplies,
        ),
      ],
    );
  }

  Widget _frankGroup(BuildContext context, bool reduced) {
    return FrankGroup(
      children: [
        FrankTile(
          leading: _PresenceGlyph(style: settings.presence),
          title: 'Presence',
          subtitle: AppSettings.presenceLabel(settings.presence),
          chevron: true,
          onTap: () => _pickPresence(context),
        ),
        _GlowIntensityTile(
          value: settings.glowIntensity,
          onChanged: settings.setGlowIntensity,
          presenceOn: settings.presence != PresenceStyle.off,
          haptics: settings.haptics,
          reduced: reduced,
        ),
        FrankSwitchTile(
          icon: Icons.vibration_rounded,
          title: 'Haptics',
          subtitle: 'Taps for send, tools, replies, and unlock',
          value: settings.haptics,
          onChanged: settings.setHaptics,
        ),
        FrankSwitchTile(
          icon: Icons.motion_photos_paused_rounded,
          title: 'Reduce motion',
          subtitle: 'Calmer glow, no flashes or shimmer',
          value: settings.reduceMotion,
          onChanged: settings.setReduceMotion,
        ),
      ],
    );
  }

  Widget _privacyGroup(BuildContext context, bool reduced) {
    return FrankGroup(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FrankSwitchTile(
              icon: Icons.lock_clock_rounded,
              title: 'Lock when you leave',
              subtitle: 'Face ID, fingerprint, or PIN when you come back',
              value: settings.autoLock,
              onChanged: settings.setAutoLock,
            ),
            _Reveal(
              visible: settings.autoLock,
              reduced: reduced,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.hairline,
                    indent: 60,
                  ),
                  FrankTile(
                    icon: Icons.timer_rounded,
                    title: 'Lock after',
                    subtitle: AppSettings.labelFor(settings.autoLockAfter),
                    chevron: true,
                    onTap: () => _pickDelay(context),
                  ),
                ],
              ),
            ),
          ],
        ),
        FrankSwitchTile(
          icon: Icons.visibility_off_rounded,
          title: 'Hide in app switcher',
          subtitle: 'Blank the preview in recent apps',
          value: settings.hideInSwitcher,
          onChanged: settings.setHideInSwitcher,
        ),
        FrankTile(
          icon: Icons.pin_rounded,
          title: 'Change PIN',
          chevron: true,
          onTap: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
            onChangePin();
          },
        ),
        FrankTile(
          icon: Icons.lock_rounded,
          title: 'Lock now',
          onTap: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
            onLock();
          },
        ),
      ],
    );
  }

  Widget _notificationsGroup(BuildContext context, PushService push) {
    final (subtitle, onTap) = switch (push.status) {
      PushStatus.off => ('Not set up in this build', null),
      PushStatus.starting => ('Connecting…', null),
      PushStatus.denied => (
        'Notifications are off for Hermsy. Tap to open settings.',
        openAppSettings,
      ),
      PushStatus.ready => (
        push.relayError != null
            ? 'On, but Hermes could not be reached: ${push.relayError}'
            : push.registered
            ? 'On. Hermes can reach this phone. Tap to copy its token.'
            : 'On. Tap to copy this device\'s token for a test push.',
        () => _copyToken(context, push.token),
      ),
      PushStatus.failed => (push.error ?? 'Could not reach Firebase', null),
    };
    return FrankGroup(
      children: [
        FrankTile(
          icon: Icons.notifications_none_rounded,
          title: 'Push',
          subtitle: subtitle,
          onTap: onTap,
        ),
      ],
    );
  }

  void _copyToken(BuildContext context, String? token) {
    if (token == null) {
      return;
    }
    Clipboard.setData(ClipboardData(text: token));
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Token copied')));
  }

  Widget _serverGroup(BuildContext context) {
    return FrankGroup(
      children: [
        _ServerTile(
          config: connection.current,
          status: _serverStatus(),
          onTap: () => _editServer(context),
        ),
      ],
    );
  }

  Widget _aboutGroup() {
    final agent = _liveChat?.agentLabel;
    return FrankGroup(
      children: [
        const FrankTile(
          icon: Icons.info_outline_rounded,
          title: 'Version',
          trailing: _Value(appVersion),
        ),
        if (agent != null && agent != 'Hermes')
          FrankTile(
            icon: Icons.memory_rounded,
            title: 'Agent',
            trailing: _Value(agent),
          ),
      ],
    );
  }

  /// Rebuilds [builder] when the live chat changes (connects, learns its
  /// model). Kept apart from the settings listener so a disposed controller
  /// is never subscribed to again.
  Widget _withChat(WidgetBuilder builder) {
    // Only a chat that still matches the saved server: after a server change
    // the app disposes the old one, which must not be subscribed to again.
    final chat = _liveChat;
    if (chat == null) {
      return Builder(builder: builder);
    }
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => builder(context),
    );
  }

  /// The chat, but only while it still talks to the saved server. After the
  /// server changes the app replaces it, so its state would be stale.
  ChatController? get _liveChat {
    final chat = this.chat;
    final current = connection.current;
    if (chat == null ||
        chat.config.baseUrl != current.baseUrl ||
        chat.config.apiKey != current.apiKey) {
      return null;
    }
    return chat;
  }

  _ServerStatus? _serverStatus() {
    if (!connection.current.looksConfigured) {
      return _ServerStatus(AppColors.amber, 'Needs setup');
    }
    final chat = _liveChat;
    if (chat == null) {
      return null;
    }
    if (chat.connected) {
      return _ServerStatus(AppColors.mint, 'Connected');
    }
    if (chat.loading) {
      return _ServerStatus(AppColors.amber, 'Connecting');
    }
    return _ServerStatus(AppColors.amber, 'Offline');
  }

  Future<void> _editServer(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ServerSettingsScreen(
          initial: connection.current,
          verify: verifyConnection,
          onSave: (next) async {
            await connection.save(next);
            await onConnectionSaved?.call(next);
          },
        ),
      ),
    );
  }

  Future<void> _pickDelay(BuildContext context) async {
    final chosen = await showFrankSheet<Duration>(
      context,
      builder: (context) {
        return FrankSheet(
          title: 'Lock after',
          subtitle: 'How long you can be away before Hermsy asks again.',
          children: [
            for (final delay in AppSettings.lockDelays)
              _ChoiceRow(
                label: AppSettings.labelFor(delay),
                selected: delay == settings.autoLockAfter,
                onTap: () => Navigator.of(context).pop(delay),
              ),
          ],
        );
      },
    );
    if (chosen != null) {
      await settings.setAutoLockAfter(chosen);
    }
  }

  Future<void> _pickPresence(BuildContext context) {
    return showFrankSheet<void>(
      context,
      isScrollControlled: true,
      builder: (context) {
        return PresencePicker(
          current: settings.presence,
          onChanged: settings.setPresence,
        );
      },
    );
  }
}

/// Screen gutters for a settings-style page: 16dp, centred at 640dp wide on
/// tablets, clear of the side insets and the navigation bar.
EdgeInsets _contentPadding(BuildContext context) {
  final media = MediaQuery.of(context);
  final side = math.max(AppSpace.gutter, (media.size.width - 640) / 2);
  return EdgeInsets.fromLTRB(
    side + media.padding.left,
    AppSpace.x2,
    side + media.padding.right,
    AppSpace.x10 + media.padding.bottom,
  );
}

/// One area's page under Settings: a large title and its groups.
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.title,
    required this.listenable,
    required this.children,
  });

  final String title;
  final Listenable listenable;
  final List<Widget> Function(BuildContext context) children;

  @override
  Widget build(BuildContext context) {
    return FrankBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListenableBuilder(
          listenable: listenable,
          builder: (context, _) => CustomScrollView(
            slivers: [
              LargeTitleSliverBar(title: title),
              SliverPadding(
                padding: _contentPadding(context),
                sliver: SliverList.list(children: children(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A Settings area: a tinted icon, its name, and how it is set now.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FrankTile(
      leading: IconTile(
        icon: icon,
        color: color,
        background: color.withValues(alpha: AppColors.isDark ? 0.16 : 0.12),
      ),
      title: title,
      subtitle: subtitle,
      chevron: true,
      onTap: onTap,
    );
  }
}

class _GroupGap extends StatelessWidget {
  const _GroupGap();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 28);
}

/// A read-only value on the right of a row (version, agent).
class _Value extends StatelessWidget {
  const _Value(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: AppText.tabular.copyWith(fontSize: 14, color: AppColors.hint),
      ),
    );
  }
}

/// The Presence row's icon: a tiny phone frame lit the way the chosen style
/// lights the real screen edge. Painted once; it crossfades on change.
class _PresenceGlyph extends StatelessWidget {
  const _PresenceGlyph({required this.style});

  final PresenceStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.veil(0x0F),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: AnimatedSwitcher(
        duration: AppMotion.short,
        switchInCurve: AppMotion.standard,
        switchOutCurve: AppMotion.standard,
        child: CustomPaint(
          key: ValueKey(style),
          size: const Size.square(32),
          painter: _PresenceGlyphPainter(style),
        ),
      ),
    );
  }
}

class _PresenceGlyphPainter extends CustomPainter {
  const _PresenceGlyphPainter(this.style);

  final PresenceStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: 14,
      height: 22,
    );
    final rrect = RRect.fromRectAndRadius(frame, const Radius.circular(4.5));
    final dim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = AppColors.veil(0x2E);
    if (style == PresenceStyle.off) {
      canvas.drawRRect(rrect, dim..color = AppColors.hint);
      return;
    }

    final shader = SweepGradient(
      colors: [
        AppColors.ion,
        AppColors.azure,
        AppColors.iris,
        AppColors.orchid,
        AppColors.ion,
      ],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(frame);
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = shader
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..shader = shader;

    void lit(Path path, {bool glow = true}) {
      if (glow) {
        canvas.drawPath(path, halo);
      }
      canvas.drawPath(path, line);
    }

    final ring = Path()..addRRect(rrect);
    switch (style) {
      case PresenceStyle.aura:
        canvas.drawRRect(
          rrect.deflate(1.5),
          Paint()
            ..shader = RadialGradient(
              colors: [
                AppColors.iris.withValues(alpha: 0.22),
                AppColors.iris.withValues(alpha: 0),
              ],
            ).createShader(frame),
        );
        lit(ring);
      case PresenceStyle.veil:
        lit(ring, glow: false);
      case PresenceStyle.ribbon:
      case PresenceStyle.twin:
        canvas.drawRRect(rrect, dim);
        final metric = ring.computeMetrics().first;
        final spans = style == PresenceStyle.ribbon
            ? const [(0.06, 0.36)]
            : const [(0.04, 0.22), (0.54, 0.72)];
        for (final (start, end) in spans) {
          lit(metric.extractPath(metric.length * start, metric.length * end));
        }
      case PresenceStyle.pulse:
        canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = AppColors.iris.withValues(alpha: 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawRRect(rrect, dim..color = const Color(0x8CB59CFF));
      case PresenceStyle.off:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PresenceGlyphPainter oldDelegate) {
    return oldDelegate.style != style;
  }
}

/// Subtle / Balanced / Vivid, with a shortcut to watch the real edge glow.
class _GlowIntensityTile extends StatelessWidget {
  const _GlowIntensityTile({
    required this.value,
    required this.onChanged,
    required this.presenceOn,
    required this.haptics,
    required this.reduced,
  });

  final GlowIntensity value;
  final ValueChanged<GlowIntensity> onChanged;
  final bool presenceOn;
  final bool haptics;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final engine = presenceOn ? PresenceScope.maybeOf(context) : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Row(
              children: [
                const IconTile(icon: Icons.flare_rounded, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Glow intensity',
                        style: AppText.label.copyWith(fontSize: 16),
                      ),
                      if (!presenceOn) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Used when Presence is on',
                          style: AppText.bodySmall.copyWith(fontSize: 13.5),
                        ),
                      ],
                    ],
                  ),
                ),
                if (engine != null)
                  TextButton(
                    onPressed: engine.preview,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Preview'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.x2),
          Padding(
            padding: const EdgeInsets.only(left: 46),
            child: _Segmented<GlowIntensity>(
              values: GlowIntensity.values,
              selected: value,
              label: AppSettings.glowIntensityLabel,
              onChanged: (next) {
                if (haptics) {
                  HapticFeedback.selectionClick();
                }
                onChanged(next);
              },
              reduced: reduced,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact segmented control: a quiet track with a gold-tinted thumb that
/// glides to the chosen segment. 48dp tall for the touch target, 44 drawn.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    required this.reduced,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final index = math.max(0, values.indexOf(selected));
    final x = values.length < 2 ? 0.0 : -1 + 2 * index / (values.length - 1);
    final duration = reduced ? Duration.zero : AppMotion.medium;
    return SizedBox(
      height: AppSpace.minTouch,
      child: Stack(
        children: [
          Positioned.fill(
            top: 2,
            bottom: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.veil(0x08),
                borderRadius: BorderRadius.circular(AppRadii.md - 2),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: AnimatedAlign(
                  alignment: Alignment(x, 0),
                  duration: duration,
                  curve: AppMotion.standard,
                  child: FractionallySizedBox(
                    widthFactor: 1 / values.length,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.goldSoft,
                        borderRadius: BorderRadius.circular(AppRadii.sm - 1),
                        border: Border.all(
                          color: AppColors.gold.withValues(alpha: 0.32),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final value in values)
                Expanded(
                  child: _Segment(
                    label: label(value),
                    selected: value == selected,
                    duration: duration,
                    onTap: value == selected ? null : () => onChanged(value),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Duration duration;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: duration,
            curve: AppMotion.standard,
            style: DefaultTextStyle.of(context).style.merge(
              TextStyle(
                color: selected ? AppColors.goldText : AppColors.secondary,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grows a row in or out of a group (size and fade) instead of popping it.
/// Static once settled; hidden content leaves the tree.
class _Reveal extends StatefulWidget {
  const _Reveal({
    required this.visible,
    required this.reduced,
    required this.child,
  });

  final bool visible;
  final bool reduced;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
    value: widget.visible ? 1 : 0,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _shown,
    curve: AppMotion.standard,
  );

  @override
  void didUpdateWidget(covariant _Reveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) {
      return;
    }
    if (widget.reduced) {
      _shown.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _shown.forward();
    } else {
      _shown.reverse();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shown,
      builder: (context, child) {
        return _shown.isDismissed
            ? const SizedBox(width: double.infinity)
            : child!;
      },
      child: SizeTransition(
        sizeFactor: _curve,
        alignment: Alignment.topLeft,
        child: FadeTransition(opacity: _curve, child: widget.child),
      ),
    );
  }
}

class _ServerStatus {
  const _ServerStatus(this.color, this.label);

  final Color color;
  final String label;
}

/// The Hermes row: server icon with a status dot, the URL, and the masked
/// key. The full key is never shown here.
class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.config,
    required this.status,
    required this.onTap,
  });

  final AppConfig config;
  final _ServerStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final url = config.baseUrl;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const IconTile(icon: Icons.dns_rounded, size: 32),
                  if (status != null)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: status.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.surface,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: status.color.withValues(alpha: 0.45),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Hermes',
                        style: AppText.label.copyWith(fontSize: 16),
                      ),
                      if (status != null) ...[
                        const SizedBox(width: AppSpace.x2),
                        Flexible(
                          child: Text(
                            status.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: status.color,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    url.isEmpty ? 'Add your server URL and key' : url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySmall.copyWith(fontSize: 13.5),
                  ),
                  if (url.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'API key · ${AppConfig.maskApiKey(config.apiKey)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.tabular.copyWith(color: AppColors.hint),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpace.x2),
            Icon(Icons.chevron_right_rounded, color: AppColors.hint, size: 22),
          ],
        ),
      ),
    );
  }
}

/// A radio row in a picker sheet: the label, and a gold check when chosen.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? AppColors.veil(0x08) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppText.label.copyWith(
                        fontSize: 16,
                        color: selected ? AppColors.text : AppColors.secondary,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_rounded, color: AppColors.gold, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
