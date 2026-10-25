import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../services/message_actions.dart';
import '../theme/app_theme.dart';
import '../widgets/day_separator.dart' show dayLabel;
import '../widgets/frank_backdrop.dart';
import '../widgets/message_image.dart';
import '../widgets/reply_markdown.dart';
import '../widgets/ui/frank_ui.dart';

/// A calm, full-screen reading view of one message, with free text
/// selection. Opened from the message actions sheet ("Select text").
class MessageReaderScreen extends StatefulWidget {
  const MessageReaderScreen({
    super.key,
    required this.message,
    this.title,
    this.onReply,
  });

  final ChatMessage message;

  /// Replaces "You" / "Hermsy" in the bar (an Inbox message's title).
  final String? title;

  /// Shows a Reply button (a message Hermes sent on its own).
  final VoidCallback? onReply;

  /// Brings the dismissed selection tip back (tests).
  @visibleForTesting
  static void debugResetTip() =>
      _MessageReaderScreenState._tipDismissed = false;

  @override
  State<MessageReaderScreen> createState() => _MessageReaderScreenState();
}

class _MessageReaderScreenState extends State<MessageReaderScreen> {
  /// The selection tip stays dismissed for the rest of the session.
  static bool _tipDismissed = false;

  static TextStyle get _readingStyle => TextStyle(
    color: AppColors.text,
    fontSize: 17,
    height: 1.65,
    letterSpacing: 0.1,
  );

  bool _scrolled = false;
  bool _copied = false;
  Timer? _copiedReset;

  @override
  void dispose() {
    _copiedReset?.cancel();
    super.dispose();
  }

  void _copyAll(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _copiedReset?.cancel();
    setState(() => _copied = true);
    _copiedReset = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      final scrolled = notification.metrics.pixels > 0.5;
      if (scrolled != _scrolled) {
        setState(() => _scrolled = scrolled);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final display = copyableText(message);
    final insets = MediaQuery.paddingOf(context);

    return FrankBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.title ?? (message.isUser ? 'You' : 'Hermsy')),
          backgroundColor: _scrolled
              ? AppColors.background.withValues(alpha: 0.94)
              : Colors.transparent,
          shape: Border(
            bottom: BorderSide(
              color: _scrolled ? AppColors.hairline : Colors.transparent,
            ),
          ),
          actions: [
            if (display.isNotEmpty)
              _CopyAllButton(
                copied: _copied,
                onPressed: () => _copyAll(display),
              ),
            const SizedBox(width: AppSpace.x1),
          ],
        ),
        bottomNavigationBar: widget.onReply == null
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(
                  AppSpace.gutter,
                  AppSpace.x2,
                  AppSpace.gutter,
                  AppSpace.x3,
                ),
                child: GoldButton(
                  label: 'Reply',
                  icon: Icons.reply_rounded,
                  onPressed: widget.onReply,
                ),
              ),
        body: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SelectionArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final gutter = math.max(
                  AppSpace.x6,
                  (constraints.maxWidth - 640) / 2,
                );
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    gutter + insets.left,
                    AppSpace.x1,
                    gutter + insets.right,
                    AppSpace.x14 + insets.bottom,
                  ),
                  children: [
                    SelectionContainer.disabled(
                      child: _ReaderTip(
                        visible: !_tipDismissed,
                        onDismiss: () => setState(() => _tipDismissed = true),
                      ),
                    ),
                    SelectionContainer.disabled(
                      child: _ReaderMeta(message: message, text: display),
                    ),
                    if (message.hasImages) ...[
                      MessageImageStrip(
                        paths: message.imagePaths,
                        remotes: message.remoteImages,
                        radius: AppRadii.md,
                      ),
                      const SizedBox(height: AppSpace.x5),
                    ],
                    if (display.isNotEmpty)
                      message.isUser
                          ? Text(
                              display,
                              style: _readingStyle.copyWith(
                                color: message.error
                                    ? AppColors.danger
                                    : AppColors.text,
                              ),
                            )
                          : ReplyMarkdown(
                              data: display,
                              error: message.error,
                              style: _readingStyle,
                            ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Copy all: the icon turns into an ion check for a moment after copying.
class _CopyAllButton extends StatelessWidget {
  const _CopyAllButton({required this.copied, required this.onPressed});

  final bool copied;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    return IconButton(
      tooltip: copied ? 'Copied' : 'Copy all',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(AppSpace.minTouch, AppSpace.minTouch),
        highlightColor: AppColors.veil(0x14),
      ),
      icon: AnimatedSwitcher(
        duration: reduced ? Duration.zero : AppMotion.quick,
        switchInCurve: AppMotion.standard,
        switchOutCurve: AppMotion.standard,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.7, end: 1).animate(animation),
              child: child,
            ),
          );
        },
        child: copied
            ? Icon(
                Icons.check_rounded,
                key: const ValueKey('copied'),
                color: AppColors.ion,
                size: 22,
              )
            : Icon(
                Icons.copy_rounded,
                key: const ValueKey('copy'),
                color: AppColors.secondary,
                size: 20,
              ),
      ),
    );
  }
}

/// A one-line hint about selecting text, dismissible with its X.
class _ReaderTip extends StatelessWidget {
  const _ReaderTip({required this.visible, required this.onDismiss});

  final bool visible;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.short,
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.x5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.veil(0x08),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(
                      Icons.touch_app_rounded,
                      color: AppColors.hint,
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Hold to highlight a passage.',
                        style: AppText.caption.copyWith(fontSize: 13),
                      ),
                    ),
                    FrankIconButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Dismiss tip',
                      size: 16,
                      color: AppColors.hint,
                      onPressed: onDismiss,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// When the message was written, and for long replies a reading time.
class _ReaderMeta extends StatelessWidget {
  const _ReaderMeta({required this.message, required this.text});

  final ChatMessage message;
  final String text;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    final created = message.createdAt;
    if (created.millisecondsSinceEpoch > 0) {
      final local = created.toLocal();
      final clock = MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(local),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
      parts.add('${dayLabel(local)} · $clock');
    }
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final minutes = (words / 230).round();
    if (minutes >= 2) {
      parts.add('$minutes min read');
    }
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }
    return MicroLabel(
      parts.join(' · '),
      padding: const EdgeInsets.only(bottom: AppSpace.x4),
    );
  }
}
