import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Adds whisper.cpp (MIT), the Whisper models (MIT) and FFmpeg (LGPL-2.1) to
/// Flutter's licence page, including the exact FFmpeg configure flags.
void registerThirdPartyLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    final whisper = await rootBundle.loadString('assets/licenses/whisper.cpp.LICENSE');
    yield LicenseEntryWithLineBreaks(const ['whisper.cpp', 'ggml', 'Whisper models'], whisper);
    final ffmpeg = await rootBundle.loadString('assets/licenses/FFmpeg.NOTICE');
    final lgpl = await rootBundle.loadString('assets/licenses/COPYING.LGPLv2.1');
    yield LicenseEntryWithLineBreaks(const ['FFmpeg'], '$ffmpeg\n\n$lgpl');
  });
}

/// About dialog: versions, privacy line, and the licence page.
void showAppAbout(BuildContext context) {
  final l10n = Localization.of(context);
  final buildInfo = Dependencies.of(context).native.buildInfo;
  showAboutDialog(
    context: context,
    applicationName: l10n.appTitle,
    applicationVersion: '1.0.0',
    applicationIcon: const DecoratedBox(
      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.all(Radius.circular(10))),
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.graphic_eq, color: Colors.white),
      ),
    ),
    children: [
      Text(l10n.aboutPrivacy),
      const SizedBox(height: 12),
      SelectableText(buildInfo, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
    ],
  );
}
