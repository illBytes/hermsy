import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../services/audio_delivery.dart';
import '../services/image_delivery.dart';
import '../state/assistant_mood.dart';
import '../theme/app_theme.dart';
import 'frank_orb.dart';
import 'message_image.dart';
import 'reply_actions.dart';
import 'reply_markdown.dart';
import 'tool_activity_line.dart';
import 'typing_indicator.dart';
import 'voice_note_card.dart';

/// One message in the thread.
///
/// Frank's replies have no bubble: they run the full width between 20dp
/// reading gutters like a typeset document, under a small byline. Your
/// messages are compact graphite bubbles on the right. The list owns the
/// vertical rhythm (16dp between speakers, 4dp within a group); this widget
/// adds no outer vertical spacing.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.playing = false,
    this.onPlay,
    this.onLongPress,
    this.highlighted = false,
    this.showHeader = true,
    this.grouped = false,
    this.isLatest = false,
    this.onCopy,
    this.onSpeak,
    this.onRetry,
    this.onReport,
  });

  final ChatMessage message;
  final bool playing;
  final VoidCallback? onPlay;
  final VoidCallback? onLongPress;

  /// The current find-in-chat hit: an ion wash with a 2dp ion edge.
  final bool highlighted;

  /// Show the assistant byline (orb · Frank · time) above this reply. False
  /// for follow-on replies in the same run.
  final bool showHeader;

  /// Sits close under the previous message from the same speaker (the list
  /// leaves a 4dp gap): a user bubble's top-right corner tucks in to meet
  /// the bubble above.
  final bool grouped;

  /// The newest message in the thread: its inline actions stay visible.
  final bool isLatest;

  /// Inline actions under a finished reply. Null hides that action. Copy
  /// confirms in place, so [onCopy] only needs to copy.
  final VoidCallback? onCopy;
  final VoidCallback? onSpeak;

  /// Also used by a failed user message's "Not sent · Retry".
  final VoidCallback? onRetry;

  /// Reports a reply as offensive or wrong.
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final body = message.isUser
        ? _UserMessage(
            message: message,
            playing: playing,
            onPlay: onPlay,
            onLongPress: onLongPress,
            grouped: grouped,
            onRetry: onRetry,
          )
        : _FrankReply(
            message: message,
            playing: playing,
            onPlay: onPlay,
            onLongPress: onLongPress,
            showHeader: showHeader,
            isLatest: isLatest,
            onCopy: onCopy,
            onSpeak: onSpeak,
            onRetry: onRetry,
            onReport: onReport,
          );
    return _FindHighlight(active: highlighted, child: body);
  }
}

/// Text, voice and pictures shared by both speakers.
///
/// The markup scan is regex work, and the list rebuilds every visible
/// message on each streamed token, so the text-derived parts are kept per
/// message until its text changes.
class _Parts {
  factory _Parts(ChatMessage message) {
    final cached = _cache[message];
    if (cached != null && identical(cached._source, message.text)) {
      return _cache[message] = cached._with(message);
    }
    final text = message.text;
    final display = stripImageMarkup(stripAudioMarkup(text));
    final parts = _Parts._(
      text,
      display: display,
      audioInText:
          extractAudioRefs(text).isNotEmpty || looksLikeAudioPath(text),
      showText: display.isNotEmpty && !looksLikeAudioPath(display),
      message: message,
    );
    _cache[message] = parts;
    return parts;
  }

  _Parts._(
    this._source, {
    required this.display,
    required bool audioInText,
    required this.showText,
    required ChatMessage message,
  }) : _audioInText = audioInText,
       showImages = message.hasImages,
       showPlayer = message.hasAudio || audioInText;

  static final _cache = Expando<_Parts>('messageParts');

  final String _source;
  final bool _audioInText;
  final String display;
  final bool showText;
  final bool showImages;
  final bool showPlayer;

  /// Same text, fresh flags (audio and images can arrive without new text).
  _Parts _with(ChatMessage message) {
    if (showImages == message.hasImages &&
        showPlayer == (message.hasAudio || _audioInText)) {
      return this;
    }
    return _Parts._(
      _source,
      display: display,
      audioInText: _audioInText,
      showText: showText,
      message: message,
    );
  }
}

class _FrankReply extends StatelessWidget {
  const _FrankReply({
    required this.message,
    required this.playing,
    required this.onPlay,
    required this.onLongPress,
    required this.showHeader,
    required this.isLatest,
    required this.onCopy,
    required this.onSpeak,
    required this.onRetry,
    required this.onReport,
  });

  final ChatMessage message;
  final bool playing;
  final VoidCallback? onPlay;
  final VoidCallback? onLongPress;
  final bool showHeader;
  final bool isLatest;
  final VoidCallback? onCopy;
  final VoidCallback? onSpeak;
  final VoidCallback? onRetry;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final waiting =
        message.streaming && message.text.isEmpty && !message.isVoice;
    final finished = !message.streaming;
    final parts = _Parts(message);
    final liveTool = message.streaming ? _liveTool(message.toolStatus) : null;
    final resize = AppMotion.reduced(context) ? Duration.zero : AppMotion.short;
    final trail = finished && message.toolTrail.isNotEmpty;
    final hasActions =
        onCopy != null ||
        onSpeak != null ||
        onRetry != null ||
        onReport != null;
    final showActions = finished && isLatest && hasActions;

    final Widget header;
    if (waiting) {
      header = TypingIndicator(
        key: const ValueKey('presence'),
        detail: message.toolStatus,
        trail: message.toolTrail,
      );
    } else if (showHeader) {
      header = _Byline(
        key: const ValueKey('byline'),
        message: message,
        liveTool: liveTool != null,
      );
    } else {
      header = const SizedBox(key: ValueKey('none'), width: double.infinity);
    }

    final media = <Widget>[
      if (parts.showPlayer)
        VoiceNoteCard(
          playing: playing,
          onPlay: onPlay,
          label: 'Voice reply',
          seed: message.id,
        ),
      if (parts.showImages)
        MessageImageStrip(
          paths: message.imagePaths,
          remotes: message.remoteImages,
        ),
      if (parts.showText)
        message.error
            ? _ErrorText(text: parts.display)
            : ReplyMarkdown(data: parts.display, streaming: message.streaming),
    ];

    final reply = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: resize,
          curve: AppMotion.standard,
          alignment: Alignment.topLeft,
          child: AnimatedSwitcher(
            duration: AppMotion.short,
            switchInCurve: AppMotion.standard,
            switchOutCurve: AppMotion.standard,
            layoutBuilder: _stackTopLeft,
            child: header,
          ),
        ),
        if (trail) _ToolTrail(lines: message.toolTrail),
        if (!waiting && media.isNotEmpty) ...[
          if (showHeader || trail) const SizedBox(height: 6),
          for (var i = 0; i < media.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            media[i],
          ],
        ],
        if (!waiting)
          AnimatedSize(
            duration: resize,
            curve: AppMotion.standard,
            alignment: Alignment.topLeft,
            child: liveTool == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ToolActivityLine(label: liveTool),
                  ),
          ),
        AnimatedSize(
          duration: resize,
          curve: AppMotion.standard,
          alignment: Alignment.topLeft,
          child: showActions
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Transform.translate(
                    offset: const Offset(-ReplyActions.glyphInset, 0),
                    child: ReplyActions(
                      onCopy: onCopy,
                      onSpeak: onSpeak,
                      onRetry: onRetry,
                      onReport: onReport,
                      speaking: playing,
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.reading),
      child: GestureDetector(
        onLongPress: onLongPress != null && !waiting ? onLongPress : null,
        behavior: HitTestBehavior.translucent,
        child: reply,
      ),
    );
  }

  static Widget _stackTopLeft(Widget? current, List<Widget> previous) {
    return Stack(
      alignment: Alignment.topLeft,
      children: [...previous, ?current],
    );
  }

  static String? _liveTool(String? status) {
    final value = status?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final lowered = value.toLowerCase();
    if (lowered == 'thinking…' ||
        lowered == 'thinking...' ||
        lowered == 'working…') {
      return null;
    }
    return value;
  }
}

/// "◉ Frank · 23:28" above the first reply of a run. The orb sits in the
/// same 20dp slot the presence row used, so the swap reads as one object.
class _Byline extends StatelessWidget {
  const _Byline({super.key, required this.message, required this.liveTool});

  final ChatMessage message;
  final bool liveTool;

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(message.createdAt.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final streaming = message.streaming;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 24),
      child: Row(
        children: [
          ExcludeSemantics(
            child: SizedBox.square(
              dimension: 20,
              child: Center(
                // Moves only while this reply streams; when it lands the orb
                // plays its one-shot done flash and goes still.
                child: FrankOrb(
                  size: 16,
                  intense: streaming,
                  mood: !streaming
                      ? AssistantMood.idle
                      : liveTool
                      ? AssistantMood.tool
                      : AssistantMood.responding,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Hermsy',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                  TextSpan(
                    text: '  ·  $time',
                    style: AppText.tabular.copyWith(
                      color: AppColors.hint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A reply that failed: a small error glyph on the first line and the text
/// in the danger color.
class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppColors.danger,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: ReplyMarkdown(data: text, error: true)),
      ],
    );
  }
}

/// "Used 3 tools ▸" under the byline of a finished reply; tap to list them.
class _ToolTrail extends StatefulWidget {
  const _ToolTrail({required this.lines});

  final List<String> lines;

  @override
  State<_ToolTrail> createState() => _ToolTrailState();
}

class _ToolTrailState extends State<_ToolTrail> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.lines.length;
    final label = count == 1 ? 'Used 1 tool' : 'Used $count tools';
    final resize = AppMotion.reduced(context) ? Duration.zero : AppMotion.short;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: label,
          hint: _expanded ? 'Hide tools' : 'Show tools',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSpace.minTouch),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppText.caption.copyWith(color: AppColors.hint),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: AppMotion.short,
                    curve: AppMotion.standard,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: AppColors.hint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: resize,
          curve: AppMotion.standard,
          alignment: Alignment.topLeft,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in widget.lines)
                        ToolTrailLine(label: line),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({
    required this.message,
    required this.playing,
    required this.onPlay,
    required this.onLongPress,
    required this.grouped,
    required this.onRetry,
  });

  final ChatMessage message;
  final bool playing;
  final VoidCallback? onPlay;
  final VoidCallback? onLongPress;
  final bool grouped;
  final VoidCallback? onRetry;

  static const _radius = Radius.circular(AppRadii.lg);
  static const _tail = Radius.circular(AppRadii.xs);

  @override
  Widget build(BuildContext context) {
    final parts = _Parts(message);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;
    final hasBubble = parts.showPlayer || parts.showText;

    final bubble = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.userBubble,
        borderRadius: BorderRadius.only(
          topLeft: _radius,
          topRight: grouped ? _tail : _radius,
          bottomLeft: _radius,
          bottomRight: _tail,
        ),
        border: Border.all(
          color: message.error
              ? AppColors.signal.withValues(alpha: 0.6)
              : AppColors.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (parts.showPlayer)
              VoiceNoteCard(
                playing: playing,
                onPlay: onPlay,
                label: 'Voice note',
                seed: message.id,
                mine: true,
              ),
            if (parts.showPlayer && parts.showText) const SizedBox(height: 6),
            if (parts.showText) Text(parts.display, style: AppText.bodyUser),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 48, right: AppSpace.gutter),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: GestureDetector(
            onLongPress: onLongPress,
            behavior: HitTestBehavior.translucent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (parts.showImages)
                  MessageImageStrip(
                    paths: message.imagePaths,
                    remotes: message.remoteImages,
                  ),
                if (parts.showImages && hasBubble)
                  const SizedBox(height: AppSpace.groupGap),
                if (hasBubble) bubble,
                if (message.error) _NotSent(onRetry: onRetry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Not sent · Retry" under a failed message.
class _NotSent extends StatelessWidget {
  const _NotSent({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final style = AppText.caption.copyWith(color: AppColors.danger);
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline_rounded, size: 14, color: AppColors.danger),
        const SizedBox(width: 6),
        Text(onRetry == null ? 'Not sent' : 'Not sent · Retry', style: style),
      ],
    );
    if (onRetry == null) {
      return Padding(padding: const EdgeInsets.only(top: 6), child: label);
    }
    return Semantics(
      button: true,
      label: 'Not sent. Retry',
      excludeSemantics: true,
      child: InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpace.minTouch),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 4, 0),
            child: label,
          ),
        ),
      ),
    );
  }
}

/// The find-in-chat hit: an ion wash with a 2dp ion edge that bleeds 6dp
/// above and below the message without moving anything.
class _FindHighlight extends StatelessWidget {
  const _FindHighlight({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: -6,
          bottom: -6,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: AppMotion.short,
              curve: AppMotion.standard,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.ion.withValues(alpha: 0.08),
                  border: Border(
                    left: BorderSide(color: AppColors.ion, width: 2),
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
