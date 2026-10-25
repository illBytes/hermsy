import 'dart:async';

import 'package:flutter/material.dart';

import '../services/hermes_client.dart';
import '../theme/app_theme.dart';
import 'ui/frank_ui.dart';

/// Which kind of trouble the strip under the header is reporting.
enum ChatNoticeKind {
  /// A reply failed or was cut off: signal red, with Retry.
  reply,

  /// Hermes is unreachable: amber, with Retry and Settings.
  connection,

  /// The mic heard nothing or voice is unavailable: neutral, fades on its own.
  voice,

  /// Anything else (playback, a missing conversation): signal red, dismiss
  /// only.
  notice,
}

/// What the error strip shows. [id] identifies the underlying error so a
/// dismissal sticks until the error changes.
@immutable
class ChatNotice {
  const ChatNotice({
    required this.kind,
    required this.title,
    required this.id,
    this.detail,
  });

  final ChatNoticeKind kind;
  final String title;
  final String? detail;
  final String id;

  @override
  bool operator ==(Object other) {
    return other is ChatNotice &&
        other.kind == kind &&
        other.title == title &&
        other.detail == detail &&
        other.id == id;
  }

  @override
  int get hashCode => Object.hash(kind, title, detail, id);
}

/// True for errors that come from the mic or speech, which read as a gentle
/// heads-up rather than a failure.
bool isVoiceError(String error) {
  final lower = error.toLowerCase();
  return lower.startsWith('no speech detected') ||
      lower.contains('speech api') ||
      lower.contains('dictation') ||
      lower.contains('microphone');
}

/// Maps the controller's raw state to the strip's content, or null when the
/// strip should be hidden.
///
/// The connection variant only shows over an existing thread; the empty
/// state has its own offline layout.
ChatNotice? chatNoticeFor({
  required String? error,
  required bool connected,
  required bool loading,
  required bool hasMessages,
  required bool lastReplyFailed,
  bool fromVoice = false,
  String? host,
}) {
  if (loading) {
    return null;
  }
  final raw = error?.trim() ?? '';
  if (!connected) {
    if (!hasMessages) {
      return null;
    }
    final where = host?.trim() ?? '';
    return ChatNotice(
      kind: ChatNoticeKind.connection,
      title: "Can't reach Hermes",
      detail: where.isNotEmpty ? where : (raw.isEmpty ? null : raw),
      id: 'connection:$raw',
    );
  }
  if (raw.isEmpty) {
    return null;
  }
  if (fromVoice || isVoiceError(raw)) {
    // "Exception: Microphone permission denied." reads as plain words.
    final title = raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
    return ChatNotice(kind: ChatNoticeKind.voice, title: title, id: raw);
  }
  final dropped = raw == describeStreamDrop(hadText: true) ||
      raw == describeStreamDrop(hadText: false);
  if (lastReplyFailed || dropped) {
    return ChatNotice(
      kind: ChatNoticeKind.reply,
      title: "Hermsy couldn't finish that reply.",
      detail: raw,
      id: raw,
    );
  }
  final (title, detail) = _calmNotice(raw);
  return ChatNotice(
    kind: ChatNoticeKind.notice,
    title: title,
    detail: detail,
    id: raw,
  );
}

/// The strip's headline is never a raw technical string: a plain first
/// sentence ("Could not speak that message.") leads, with anything after it
/// as the detail; otherwise a calm fixed title leads and the raw text
/// becomes the (clamped, expandable) detail.
(String, String?) _calmNotice(String raw) {
  final end = raw.indexOf('. ');
  final lead = end < 0 ? raw : raw.substring(0, end + 1);
  final rest = end < 0 ? '' : raw.substring(end + 2).trim();
  final plain = lead.length <= 90 &&
      lead.endsWith('.') &&
      !lead.contains(':') &&
      lead.codeUnitAt(0) >= 0x41 &&
      lead.codeUnitAt(0) <= 0x5A;
  if (plain) {
    return (lead, rest.isEmpty ? null : rest);
  }
  return ('Hermes ran into a problem', raw);
}

/// The strip under the header. It drops in (size + fade, 200ms) when
/// [notice] appears and folds away when it clears; voice notices dismiss
/// themselves after [autoDismissAfter].
class ChatErrorStrip extends StatefulWidget {
  const ChatErrorStrip({
    super.key,
    required this.notice,
    this.onRetry,
    this.onSettings,
    this.onDismiss,
    this.autoDismissAfter = const Duration(seconds: 3),
  });

  final ChatNotice? notice;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;
  final ValueChanged<ChatNotice>? onDismiss;
  final Duration autoDismissAfter;

  @override
  State<ChatErrorStrip> createState() => _ChatErrorStripState();
}

class _ChatErrorStripState extends State<ChatErrorStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: AppMotion.short,
    reverseDuration: const Duration(milliseconds: 160),
  )..addStatusListener(_onStatus);
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _reveal,
    curve: AppMotion.enter,
    reverseCurve: AppMotion.exit,
  );

  ChatNotice? _shown;
  var _expanded = false;
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _show(widget.notice);
  }

  @override
  void didUpdateWidget(covariant ChatErrorStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notice != oldWidget.notice) {
      _show(widget.notice);
    }
  }

  void _show(ChatNotice? notice) {
    _autoDismiss?.cancel();
    if (notice == null) {
      _reveal.reverse();
      return;
    }
    _shown = notice;
    _expanded = false;
    _reveal.forward();
    if (notice.kind == ChatNoticeKind.voice) {
      _autoDismiss = Timer(widget.autoDismissAfter, () {
        if (mounted && widget.notice == notice) {
          widget.onDismiss?.call(notice);
        }
      });
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() => _shown = null);
    }
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _curve.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = _shown;
    if (notice == null) {
      return const SizedBox.shrink();
    }
    final card = _NoticeCard(
      notice: notice,
      expanded: _expanded,
      onToggle: notice.detail == null && notice.title.length < 60
          ? null
          : () => setState(() => _expanded = !_expanded),
      onRetry: switch (notice.kind) {
        ChatNoticeKind.reply || ChatNoticeKind.connection => widget.onRetry,
        _ => null,
      },
      onSettings:
          notice.kind == ChatNoticeKind.connection ? widget.onSettings : null,
      onDismiss: notice.kind == ChatNoticeKind.connection ||
              widget.onDismiss == null
          ? null
          : () => widget.onDismiss!(notice),
    );
    final fade = FadeTransition(opacity: _curve, child: card);
    if (AppMotion.reduced(context)) {
      return fade;
    }
    return SizeTransition(
      sizeFactor: _curve,
      alignment: Alignment.topLeft,
      child: fade,
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.notice,
    required this.expanded,
    this.onToggle,
    this.onRetry,
    this.onSettings,
    this.onDismiss,
  });

  final ChatNotice notice;
  final bool expanded;
  final VoidCallback? onToggle;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final (Color? tint, IconData icon, Color iconColor) = switch (notice.kind) {
      ChatNoticeKind.reply ||
      ChatNoticeKind.notice =>
        (AppColors.signal, Icons.error_outline_rounded, AppColors.danger),
      ChatNoticeKind.connection =>
        (AppColors.amber, Icons.cloud_off_rounded, AppColors.amber),
      ChatNoticeKind.voice =>
        (null, Icons.mic_off_rounded, AppColors.secondary),
    };
    final base = tint == null
        ? AppColors.surfaceHigh.withValues(alpha: 0.96)
        : Color.alphaBlend(
            tint.withValues(alpha: 0.10),
            AppColors.surface.withValues(alpha: 0.97),
          );
    final radius = BorderRadius.circular(AppRadii.md);
    final detail = notice.detail;
    final maxLines = expanded ? null : 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.x1,
        AppSpace.gutter,
        0,
      ),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Material(
          color: base,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: tint?.withValues(alpha: 0.24) ?? AppColors.hairline,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onToggle,
            child: Stack(
              children: [
                if (tint != null)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 3,
                    child: ColoredBox(color: tint),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 2, 6),
                  child: Row(
                    children: [
                      Icon(icon, size: 18, color: iconColor),
                      const SizedBox(width: AppSpace.x3),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: AnimatedSize(
                            duration: AppMotion.short,
                            curve: AppMotion.standard,
                            alignment: Alignment.topLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  notice.title,
                                  maxLines: detail == null ? maxLines : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.label.copyWith(
                                    fontSize: 14,
                                    fontWeight: detail == null
                                        ? FontWeight.w500
                                        : FontWeight.w600,
                                  ),
                                ),
                                if (detail != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    detail,
                                    maxLines: maxLines,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.bodySmall.copyWith(
                                      fontSize: 13,
                                      height: 1.38,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (onRetry != null)
                        _StripAction(
                          label: 'Retry',
                          color: AppColors.gold,
                          onPressed: onRetry!,
                        ),
                      if (onSettings != null)
                        _StripAction(
                          label: 'Settings',
                          color: AppColors.secondary,
                          onPressed: onSettings!,
                        ),
                      if (onDismiss != null)
                        FrankIconButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Dismiss',
                          size: 18,
                          color: AppColors.hint,
                          onPressed: onDismiss,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StripAction extends StatelessWidget {
  const _StripAction({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(48, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
      child: Text(label),
    );
  }
}
