import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui/frank_ui.dart';

/// Asks before a chat is removed. Returns true only when the user confirms.
Future<bool> confirmDeleteChat(BuildContext context) async {
  final shouldDelete = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (context) {
      return FrankDialog(
        title: 'Delete chat?',
        message: 'This removes the conversation from this phone.',
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
              backgroundColor: AppColors.signal.withValues(alpha: 0.12),
              overlayColor: AppColors.signal,
              shape: const StadiumBorder(),
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return shouldDelete == true;
}
