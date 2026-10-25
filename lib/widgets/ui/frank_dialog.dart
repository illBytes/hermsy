import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A Frank-styled dialog: surface black, 20dp radius, light edge, actions
/// as text buttons on the right.
class FrankDialog extends StatelessWidget {
  const FrankDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    required this.actions,
  });

  final String title;
  final String? message;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(color: AppColors.strokeStrong),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      title: Text(title, style: AppText.headline.copyWith(fontSize: 18)),
      content: content ??
          (message == null
              ? null
              : Text(message!, style: AppText.bodySmall.copyWith(fontSize: 15))),
      actions: actions,
    );
  }
}

/// Ask a yes/no question. Returns true only when the user confirms.
Future<bool> showFrankConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (context) {
      return FrankDialog(
        title: title,
        message: message,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: destructive ? AppColors.danger : AppColors.gold,
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return ok == true;
}
