import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:flutter/material.dart';

enum PillTone { accent, solidAccent, neutral, warning, error }

/// Small rounded status label ("Transcribing 37%", "Saved", "Failed").
class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, this.tone = PillTone.neutral, this.icon, super.key});

  final String label;
  final PillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      PillTone.accent => (AppColors.accentSoft, AppColors.accent),
      PillTone.solidAccent => (AppColors.accent, Colors.white),
      PillTone.neutral => (AppColors.chip, AppColors.inkSecondary),
      PillTone.warning => (AppColors.warningSoft, AppColors.warning),
      PillTone.error => (AppColors.errorSoft, AppColors.error),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: foreground), const SizedBox(width: 4)],
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grey metadata chip ("2:14", "Base model").
class MetaChip extends StatelessWidget {
  const MetaChip(this.label, {this.tone = PillTone.neutral, super.key});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final warning = tone == PillTone.warning;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warning ? AppColors.warningSoft : AppColors.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(label, style: TextStyle(fontSize: 12, color: warning ? AppColors.warning : AppColors.inkSecondary)),
      ),
    );
  }
}
