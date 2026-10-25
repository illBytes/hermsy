import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui/frank_ui.dart';

/// Actions for the conversation you are in, opened from the header title
/// or a long-press on the header.
///
/// A null callback hides that action (for example Rename and Pin before
/// the chat has been saved). Every action closes the sheet first.
class ConversationSheet extends StatelessWidget {
  const ConversationSheet({
    super.key,
    required this.title,
    this.subtitle,
    this.pinned = false,
    this.onRename,
    this.onTogglePin,
    this.onFind,
    this.onUsage,
    this.onStatus,
    this.onDelete,
  });

  final String title;
  final String? subtitle;
  final bool pinned;
  final VoidCallback? onRename;
  final VoidCallback? onTogglePin;
  final VoidCallback? onFind;
  final VoidCallback? onUsage;
  final VoidCallback? onStatus;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    void run(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    final quick = [
      if (onRename != null)
        QuickTile(
          icon: Icons.drive_file_rename_outline_rounded,
          label: 'Rename',
          onTap: () => run(onRename!),
        ),
      if (onTogglePin != null)
        QuickTile(
          icon: pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          label: pinned ? 'Unpin' : 'Pin',
          onTap: () => run(onTogglePin!),
        ),
      if (onFind != null)
        QuickTile(
          icon: Icons.search_rounded,
          label: 'Find in chat',
          onTap: () => run(onFind!),
        ),
    ];
    final hasRows = onUsage != null || onStatus != null;

    return FrankSheet(
      title: title,
      subtitle: subtitle,
      children: [
        if (quick.isNotEmpty) ...[
          QuickTileRow(children: quick),
          const SizedBox(height: AppSpace.x3),
        ],
        if (onUsage != null)
          SheetRow(
            icon: Icons.insights_rounded,
            label: 'Usage',
            subtitle: 'Tokens and cost for this chat',
            onTap: () => run(onUsage!),
          ),
        if (onStatus != null)
          SheetRow(
            icon: Icons.monitor_heart_rounded,
            label: 'Status',
            subtitle: 'Connection and session info',
            onTap: () => run(onStatus!),
          ),
        if (onDelete != null) ...[
          if (hasRows || quick.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.x1),
              child: Divider(indent: 56, endIndent: 6),
            ),
          SheetRow(
            icon: Icons.delete_outline_rounded,
            label: 'Delete chat',
            danger: true,
            onTap: () => run(onDelete!),
          ),
        ],
      ],
    );
  }
}
