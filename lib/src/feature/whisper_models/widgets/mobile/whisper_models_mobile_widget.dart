import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/common/widget/licenses.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_models_list.dart';
import 'package:flutter/material.dart';

class WhisperModelsMobileWidget extends StatelessWidget {
  const WhisperModelsMobileWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return SafeArea(
      bottom: false,
      child: WhisperModelsList(
        compact: true,
        builder: (context, snapshot, cards) {
          final device = [
            if (snapshot.totalRamBytes case final ram?) l10n.deviceMemory(FormatUtil.memory(ram)),
            if (snapshot.freeDiskBytes case final free?) l10n.deviceFree(FormatUtil.bytes(free)),
          ].join(' · ');
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              Text(l10n.tabModels, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (device.isNotEmpty) Text(device, style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary)),
              const SizedBox(height: 12),
              for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: 10), child: card),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text(
                  l10n.modelsMobileFootnote,
                  style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.inkMuted),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: () => showAppAbout(context), child: Text(l10n.aboutAndLicenses)),
              ),
            ],
          );
        },
      ),
    );
  }
}
