import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui/frank_ui.dart';

/// The long-press sheet for a message: the allowed actions (Copy, Select
/// text, Speak, Retry) as a row of quick tiles. Open it with
/// `showFrankSheet`. A null callback leaves that action out.
class MessageActionsSheet extends StatelessWidget {
  const MessageActionsSheet({
    super.key,
    this.onCopy,
    this.onSelectText,
    this.onSpeak,
    this.onRetry,
    this.onReport,
    this.preview,
  });

  final VoidCallback? onCopy;
  final VoidCallback? onSelectText;
  final VoidCallback? onSpeak;
  final VoidCallback? onRetry;

  /// Reports an AI reply as offensive or wrong (Google Play asks for it).
  final VoidCallback? onReport;

  /// Optional excerpt of the message, shown above the actions so it is
  /// clear which message they apply to.
  final String? preview;

  @override
  Widget build(BuildContext context) {
    final excerpt = previewExcerpt(preview ?? '');
    final tiles = [
      if (onCopy != null)
        QuickTile(icon: Icons.copy_rounded, label: 'Copy', onTap: onCopy!),
      if (onSelectText != null)
        QuickTile(
          icon: Icons.text_fields_rounded,
          label: 'Select text',
          onTap: onSelectText!,
        ),
      if (onSpeak != null)
        QuickTile(
          icon: Icons.volume_up_rounded,
          label: 'Speak',
          onTap: onSpeak!,
        ),
      if (onRetry != null)
        QuickTile(
          icon: Icons.refresh_rounded,
          label: 'Retry',
          onTap: onRetry!,
        ),
      if (onReport != null)
        QuickTile(
          icon: Icons.outlined_flag_rounded,
          label: 'Report',
          onTap: onReport!,
        ),
    ];

    return FrankSheet(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      children: [
        if (excerpt.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: Text(
              excerpt,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodySmall.copyWith(height: 1.5),
            ),
          ),
        ],
        if (tiles.isNotEmpty) QuickTileRow(children: tiles),
      ],
    );
  }
}

/// A plain-text excerpt of a reply for the sheet's preview: markdown marks,
/// code fences and link targets removed, whitespace collapsed.
String previewExcerpt(String raw, {int max = 400}) {
  // Three lines never need more than a few hundred characters.
  var text = raw.length > max * 2 ? raw.substring(0, max * 2) : raw;
  text = text
      .replaceAll(RegExp(r'^[ \t]*(```|~~~).*$', multiLine: true), ' ')
      .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'^[ \t]*#{1,6}[ \t]+', multiLine: true), '')
      .replaceAll(RegExp(r'^[ \t]*>[ \t]?', multiLine: true), '')
      .replaceAll(RegExp(r'^[ \t]*(?:[-*+]|\d+[.)])[ \t]+', multiLine: true), '')
      .replaceAll(RegExp(r'(\*\*|__|~~|`)'), '')
      .replaceAllMapped(RegExp(r'(^|[\s(])[*_]([^*_\s][^*_]*)[*_]'), (m) => '${m.group(1)}${m.group(2)}')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.length > max ? '${text.substring(0, max).trimRight()}…' : text;
}
