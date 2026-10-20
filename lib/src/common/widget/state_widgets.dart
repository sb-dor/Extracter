import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:flutter/material.dart';

class LoadingStateWidget extends StatelessWidget {
  const LoadingStateWidget({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
  );
}

class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({required this.icon, required this.title, this.message, super.key});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(icon, color: AppColors.accent, size: 26),
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          if (message != null)
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.inkMuted),
            ),
        ],
      ),
    ),
  );
}

class TryAgainButton extends StatelessWidget {
  const TryAgainButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.refresh, size: 18),
    label: Text(Localization.of(context).tryAgain),
  );
}

class ErrorStateWidget extends StatelessWidget {
  const ErrorStateWidget({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 14,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 32),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
          TryAgainButton(onPressed: onRetry),
        ],
      ),
    ),
  );
}
