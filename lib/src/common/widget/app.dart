import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_shell.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/common/widget/licenses.dart';
import 'package:extracter/src/feature/transcription_settings/widgets/transcription_settings_config_widget.dart';
import 'package:extracter/src/feature/whisper_model_download/widgets/whisper_model_download_config_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    registerThirdPartyLicenses();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => Localization.of(context).appTitle,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    themeMode: ThemeMode.light,
    localizationsDelegates: const [
      Localization.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: Localization.delegate.supportedLocales,
    // Settings and downloads are shared by several screens and outlive them,
    // so their scopes sit above the shell.
    home: const TranscriptionSettingsConfigWidget(child: WhisperModelDownloadConfigWidget(child: AppShell())),
  );
}
