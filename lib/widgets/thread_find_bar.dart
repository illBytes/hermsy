import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui/frank_ui.dart';

/// Find in chat, drawn as a header row: back, a search pill with the match
/// count, then previous and next.
///
/// The chat header cross-fades into this row while finding.
class ThreadFindBar extends StatelessWidget {
  const ThreadFindBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.matchLabel,
    required this.hasQuery,
    required this.hasMatches,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// '2/7', or 'No matches'.
  final String matchLabel;
  final bool hasQuery;
  final bool hasMatches;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  /// Height of the row, matching the chat header.
  static const height = 60.0;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: height),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.x1),
        child: Row(
          children: [
            FrankIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Close find',
              onPressed: onClose,
            ),
            const SizedBox(width: AppSpace.x1),
            Expanded(
              child: _SearchPill(
                controller: controller,
                focusNode: focusNode,
                matchLabel: matchLabel,
                hasQuery: hasQuery,
                hasMatches: hasMatches,
                onSubmitted: hasMatches ? onNext : null,
              ),
            ),
            const SizedBox(width: AppSpace.x1),
            FrankIconButton(
              icon: Icons.keyboard_arrow_up_rounded,
              tooltip: 'Previous match',
              onPressed: hasMatches ? onPrevious : null,
              size: 24,
            ),
            FrankIconButton(
              icon: Icons.keyboard_arrow_down_rounded,
              tooltip: 'Next match',
              onPressed: hasMatches ? onNext : null,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({
    required this.controller,
    required this.focusNode,
    required this.matchLabel,
    required this.hasQuery,
    required this.hasMatches,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String matchLabel;
  final bool hasQuery;
  final bool hasMatches;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final showLabel = hasQuery && matchLabel.isNotEmpty;
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) {
        return AnimatedContainer(
          duration: AppMotion.short,
          curve: AppMotion.standard,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.only(left: 14, right: 14),
          decoration: BoxDecoration(
            color: AppColors.veil(0x0A),
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: focusNode.hasFocus
                  ? AppColors.strokeStrong
                  : AppColors.hairline,
            ),
          ),
          child: child,
        );
      },
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: AppColors.hint),
          const SizedBox(width: AppSpace.x2),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmitted?.call(),
              style: AppText.label.copyWith(
                fontWeight: FontWeight.w400,
                fontSize: 16,
                height: 1.3,
              ),
              decoration: const InputDecoration(
                hintText: 'Find in chat',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 11),
                border: InputBorder.none,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: AppMotion.quick,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: showLabel
                ? Padding(
                    key: ValueKey(matchLabel),
                    padding: const EdgeInsets.only(left: AppSpace.x2),
                    child: Text(
                      matchLabel,
                      style: AppText.tabular.copyWith(
                        color: hasMatches ? AppColors.secondary : AppColors.hint,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
