import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// A fenced code block in a reply: a quiet plate with the language and a
/// copy button in a 36dp header, a horizontally scrolling body, and long
/// listings folded behind "Show all N lines".
class ReplyCodeBlock extends StatefulWidget {
  const ReplyCodeBlock({super.key, required this.code, this.language = ''});

  final String code;
  final String language;

  /// Listings longer than this fold to their first [foldLines] lines.
  static const foldLines = 18;

  @override
  State<ReplyCodeBlock> createState() => _ReplyCodeBlockState();
}

class _ReplyCodeBlockState extends State<ReplyCodeBlock> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final lines = '\n'.allMatches(widget.code).length + 1;
    final foldable = lines > ReplyCodeBlock.foldLines;
    final folded = foldable && !_expanded;
    final visible = folded
        ? _firstLines(widget.code, ReplyCodeBlock.foldLines)
        : widget.code;
    final label = widget.language.trim();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.codeBg,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.md - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label.isEmpty ? 'code' : label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.code.copyWith(
                          color: AppColors.hint,
                          fontSize: 12,
                          height: 1.2,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    _CopyCodeButton(code: widget.code),
                  ],
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: AppColors.hairline),
            Stack(
              children: [
                _CodeBody(code: visible),
                if (folded)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 36,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.codeBg.withValues(alpha: 0),
                              AppColors.codeBg,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (foldable)
              _FoldToggle(
                expanded: _expanded,
                lines: lines,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
          ],
        ),
      ),
    );
  }

  static String _firstLines(String code, int count) {
    var index = -1;
    for (var i = 0; i < count; i++) {
      index = code.indexOf('\n', index + 1);
      if (index < 0) {
        return code;
      }
    }
    return code.substring(0, index);
  }
}

/// The monospace listing. Scrolls sideways; the right edge fades so long
/// lines read as continuing rather than cut off.
class _CodeBody extends StatelessWidget {
  const _CodeBody({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final fade = bounds.width <= 0
            ? 0.0
            : (16 / bounds.width).clamp(0.0, 0.5);
        return LinearGradient(
          colors: const [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 1 - fade, 1],
        ).createShader(bounds);
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 12, 24, 14),
        child: Text(code, style: AppText.code),
      ),
    );
  }
}

/// "Copy" that turns into an ion "Copied" with a check for 1400ms.
class _CopyCodeButton extends StatefulWidget {
  const _CopyCodeButton({required this.code});

  final String code;

  @override
  State<_CopyCodeButton> createState() => _CopyCodeButtonState();
}

class _CopyCodeButtonState extends State<_CopyCodeButton> {
  Timer? _reset;
  var _copied = false;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    _reset?.cancel();
    setState(() => _copied = true);
    _reset = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _copied ? AppColors.ion : AppColors.secondary;
    return Tooltip(
      message: 'Copy code',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _copy,
          customBorder: const StadiumBorder(),
          highlightColor: AppColors.veil(0x14),
          child: Container(
            constraints: const BoxConstraints(minWidth: 64, minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: AppMotion.quick,
              switchInCurve: AppMotion.enter,
              switchOutCurve: AppMotion.exit,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.92,
                      end: 1,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Row(
                key: ValueKey(_copied),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _copied ? 'Copied' : 'Copy',
                    style: AppText.caption.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FoldToggle extends StatelessWidget {
  const _FoldToggle({
    required this.expanded,
    required this.lines,
    required this.onTap,
  });

  final bool expanded;
  final int lines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                expanded ? 'Show less' : 'Show all $lines lines',
                style: AppText.caption,
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: AppMotion.short,
                curve: AppMotion.standard,
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
