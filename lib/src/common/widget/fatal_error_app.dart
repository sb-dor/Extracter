import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Shown when start-up fails (e.g. the native engine is missing or mismatched).
class FatalErrorApp extends StatelessWidget {
  const FatalErrorApp({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    localizationsDelegates: const [
      Localization.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: Localization.delegate.supportedLocales,
    home: Builder(
      builder: (context) {
        final l10n = Localization.of(context);
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 40),
                  Text(l10n.fatalErrorTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  Text(
                    l10n.fatalErrorMessage(_describe(error)),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.inkSecondary),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Type plus, for plugin errors, the channel's code and message — enough to
/// diagnose a release build (whose logs are off) without exposing user data.
String _describe(Object error) => switch (error) {
  PlatformException(:final code, :final message) => 'PlatformException $code: ${message ?? ''}',
  _ => error.runtimeType.toString(),
};
