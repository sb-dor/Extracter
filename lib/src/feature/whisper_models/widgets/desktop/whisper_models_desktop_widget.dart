import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_models_list.dart';
import 'package:flutter/material.dart';

class WhisperModelsDesktopWidget extends StatelessWidget {
  const WhisperModelsDesktopWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return WhisperModelsList(
      compact: false,
      builder: (context, snapshot, cards) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 32, 40, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 24,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  runSpacing: 16,
                  spacing: 16,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          Text(l10n.tabModels, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
                          Text(
                            l10n.modelsSubtitle,
                            style: const TextStyle(fontSize: 15, color: AppColors.inkSecondary),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (snapshot.totalRamBytes case final ram?)
                          _DeviceChip(l10n.deviceMemory(FormatUtil.memory(ram))),
                        if (snapshot.freeDiskBytes case final free?)
                          _DeviceChip(l10n.deviceFree(FormatUtil.bytes(free))),
                      ],
                    ),
                  ],
                ),
                Column(spacing: 12, crossAxisAlignment: CrossAxisAlignment.stretch, children: cards),
                Text(l10n.modelsFootnote, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceChip extends StatelessWidget {
  const _DeviceChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary)),
    ),
  );
}
