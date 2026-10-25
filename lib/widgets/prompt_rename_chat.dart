import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui/frank_ui.dart';

/// Asks for a new chat name. Returns the typed text on Save, or null when
/// the user cancels.
Future<String?> promptRenameChat(
  BuildContext context, {
  required String currentTitle,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (context) => _RenameChatDialog(currentTitle: currentTitle),
  );
}

class _RenameChatDialog extends StatefulWidget {
  const _RenameChatDialog({required this.currentTitle});

  final String currentTitle;

  @override
  State<_RenameChatDialog> createState() => _RenameChatDialogState();
}

class _RenameChatDialogState extends State<_RenameChatDialog> {
  // Owned here (not by the caller) so the field outlives the dialog's exit
  // animation without touching a disposed controller.
  late final TextEditingController _name =
      TextEditingController(text: widget.currentTitle)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.currentTitle.length,
        );
  final _focus = FocusNode();

  bool get _canSave => _name.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _name.addListener(_refresh);
    _focus.addListener(_refresh);
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _save() {
    if (_canSave) {
      Navigator.of(context).pop(_name.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return FrankDialog(
      title: 'Rename chat',
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SizedBox(
          width: double.maxFinite,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.x2),
            child: AnimatedContainer(
              duration: AppMotion.quick,
              curve: AppMotion.standard,
              constraints: const BoxConstraints(minHeight: 52),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: focused
                      ? AppColors.gold.withValues(alpha: 0.6)
                      : AppColors.hairline,
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.1),
                          blurRadius: 14,
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      focusNode: _focus,
                      autofocus: true,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      style: AppText.label.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Chat name',
                        counterText: '',
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(
                          AppSpace.x4,
                          15,
                          AppSpace.x1,
                          15,
                        ),
                      ),
                    ),
                  ),
                  if (_name.text.isNotEmpty)
                    FrankIconButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Clear',
                      size: 18,
                      color: AppColors.hint,
                      onPressed: _name.clear,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _canSave ? _save : null,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.gold,
            disabledForegroundColor: AppColors.disabled,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
