import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:flutter/material.dart';

enum DialogTone { accent, warning, destructive }

/// Confirmation dialog in the design's style: tinted icon, title, body, actions.
/// Blocks dismissal while [inProgress] (PopScope).
class AdaptiveDialogWidget extends StatelessWidget {
  const AdaptiveDialogWidget({
    required this.title,
    required this.content,
    required this.confirmLabel,
    required this.onConfirm,
    this.icon,
    this.tone = DialogTone.accent,
    this.cancelLabel,
    this.inProgress = false,
    this.showCancel = true,
    super.key,
  });

  final String title;
  final String content;
  final String confirmLabel;
  final String? cancelLabel;
  final IconData? icon;
  final DialogTone tone;
  final bool inProgress;
  final bool showCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final (soft, strong) = switch (tone) {
      DialogTone.accent => (AppColors.accentSoft, AppColors.accent),
      DialogTone.warning => (AppColors.warningSoft, AppColors.warning),
      DialogTone.destructive => (AppColors.errorSoft, AppColors.error),
    };
    return PopScope(
      canPop: !inProgress,
      child: Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 14,
              children: [
                if (icon != null)
                  DecoratedBox(
                    decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Icon(icon, color: strong, size: 22),
                    ),
                  ),
                Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                Text(content, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.inkSecondary)),
                const SizedBox(height: 2),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (showCancel)
                      OutlinedButton(
                        onPressed: inProgress ? null : () => Navigator.pop(context),
                        child: Text(cancelLabel ?? Localization.of(context).cancel),
                      ),
                    FilledButton(
                      style: tone == DialogTone.destructive
                          ? FilledButton.styleFrom(backgroundColor: AppColors.error)
                          : null,
                      onPressed: inProgress ? null : onConfirm,
                      child: inProgress
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
