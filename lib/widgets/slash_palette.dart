import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui/frank_ui.dart';

/// A command Frank runs locally, with the one line the palette shows for it.
class SlashCommandInfo {
  const SlashCommandInfo(this.command, this.description);

  final String command;
  final String description;
}

/// Frank's local slash commands, in palette order.
const slashCommandCatalog = <SlashCommandInfo>[
  SlashCommandInfo('/new', 'Start a fresh chat'),
  SlashCommandInfo('/reset', 'Start a fresh chat'),
  SlashCommandInfo('/clear', 'Start a fresh chat'),
  SlashCommandInfo('/usage', 'Tokens and cost for this chat'),
  SlashCommandInfo('/status', 'Connection and session info'),
  SlashCommandInfo('/stop', 'Stop the current reply'),
  SlashCommandInfo('/undo', 'Remove the last exchange'),
  SlashCommandInfo('/help', 'All commands'),
];

/// The commands to offer while [text] is being typed: all of them for a bare
/// "/", prefix matches while the first word grows, and none once the text
/// has a space or does not start with "/".
List<SlashCommandInfo> matchSlashCommands(String text) {
  if (!text.startsWith('/') || text.contains(RegExp(r'\s'))) {
    return const [];
  }
  final query = text.toLowerCase();
  return [
    for (final info in slashCommandCatalog)
      if (info.command.startsWith(query)) info,
  ];
}

/// The floating card of matching commands above the composer. Tapping a row
/// hands the command to [onSelect], which runs it.
class SlashPalette extends StatelessWidget {
  const SlashPalette({
    super.key,
    required this.commands,
    required this.onSelect,
    this.maxHeight = 300,
  });

  final List<SlashCommandInfo> commands;
  final ValueChanged<SlashCommandInfo> onSelect;

  /// Taller lists scroll inside the card.
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      blur: 0,
      radius: AppRadii.lg,
      color: AppColors.surfaceHigh.withValues(alpha: 0.97),
      borderColor: AppColors.strokeStrong,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MicroLabel(
              'Commands',
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 6),
                physics: const ClampingScrollPhysics(),
                children: [
                  for (final info in commands)
                    _PaletteRow(info: info, onTap: () => onSelect(info)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaletteRow extends StatefulWidget {
  const _PaletteRow({required this.info, required this.onTap});

  final SlashCommandInfo info;
  final VoidCallback onTap;

  @override
  State<_PaletteRow> createState() => _PaletteRowState();
}

class _PaletteRowState extends State<_PaletteRow> {
  bool _pressed = false;

  void _press(bool value) {
    if (value != _pressed) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${widget.info.command}, ${widget.info.description}',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.instant,
          constraints: const BoxConstraints(minHeight: 44),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: _pressed ? AppColors.veil(0x0F) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 76),
                child: Text(
                  widget.info.command,
                  style: AppText.code.copyWith(
                    color: AppColors.gold,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.info.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
