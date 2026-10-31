import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:flutter/material.dart';

/// Android keeps working in the background (foreground service); iOS stops
/// unfinished files when the user switches apps, so it asks to stay open.
class KeepOpenBanner extends StatelessWidget {
  const KeepOpenBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final background = Dependencies.of(context).backgroundWork.keepsRunningInBackground;
    final l10n = Localization.of(context);
    final ink = background ? AppColors.accent : const Color(0xFF6E4100);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ? AppColors.accentSoft : AppColors.warningSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Icon(background ? Icons.notifications_active_outlined : Icons.info_outline, size: 18, color: ink),
            Expanded(
              child: Text(
                background ? l10n.workInBackground : l10n.keepAppOpen,
                style: TextStyle(fontSize: 13, height: 1.45, color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
