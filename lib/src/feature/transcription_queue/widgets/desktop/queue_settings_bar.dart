import 'package:control/control.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/common/utils/whisper_languages.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/transcription_queue_config_widget.dart';
import 'package:extracter/src/feature/whisper_models/controller/whisper_models_controller.dart';
import 'package:extracter/src/feature/whisper_models/models/whisper_model_item.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_model_labels.dart';
import 'package:flutter/material.dart';

/// Model, spoken language and translate switch for files added next.
class QueueSettingsBar extends StatefulWidget {
  const QueueSettingsBar({super.key});

  @override
  State<QueueSettingsBar> createState() => _QueueSettingsBarState();
}

class _QueueSettingsBarState extends State<QueueSettingsBar> {
  late final _scope = TranscriptionQueueConfigInhWidget.of(context);
  late final _settings = _scope.settingsDataController;

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: StateConsumer<WhisperModelsController, WhisperModelsState>(
          controller: _scope.whisperModelsController,
          builder: (context, modelsState, _) => ListenableBuilder(
            listenable: _settings,
            builder: (context, _) {
              final draft = _settings.draft;
              final items = modelsState is WhisperModels$CompletedState
                  ? modelsState.snapshot.items
                  : const <WhisperModelItem>[];
              final spec = WhisperModelSpec.byId(draft.modelId);
              final canTranslate = spec?.supportsTranslate ?? false;
              return Wrap(
                spacing: 24,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  _Field(
                    label: l10n.model,
                    width: 260,
                    // Keyed so a change made elsewhere (Models screen) re-seeds the field.
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('model-${draft.modelId}'),
                      initialValue: draft.modelId,
                      isExpanded: true,
                      items: [
                        for (final item in items.where((i) => i.fitsDevice || i.isInstalled))
                          DropdownMenuItem(
                            value: item.spec.id,
                            child: Text(
                              item.isInstalled
                                  ? l10n.modelOptionInstalled(
                                      modelName(l10n, item.spec.id),
                                      FormatUtil.bytes(item.spec.sizeBytes),
                                    )
                                  : l10n.modelOptionMissing(
                                      modelName(l10n, item.spec.id),
                                      FormatUtil.bytes(item.spec.sizeBytes),
                                    ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (items.isEmpty)
                          DropdownMenuItem(value: draft.modelId, child: Text(modelName(l10n, draft.modelId))),
                      ],
                      onChanged: (id) {
                        if (id != null) _settings.setModel(id);
                      },
                    ),
                  ),
                  _Field(
                    label: l10n.spokenLanguage,
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('language-${draft.language}'),
                      initialValue: draft.language,
                      isExpanded: true,
                      menuMaxHeight: 420,
                      items: [
                        DropdownMenuItem(value: TranscriptionSettings.autoLanguage, child: Text(l10n.languageAuto)),
                        for (final language in WhisperLanguage.all)
                          DropdownMenuItem(value: language.code, child: Text(language.name)),
                      ],
                      onChanged: (code) {
                        if (code != null) _settings.setLanguage(code);
                      },
                    ),
                  ),
                  Tooltip(
                    message: canTranslate ? '' : l10n.translateUnsupported,
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: draft.translate,
                            onChanged: canTranslate ? (v) => _settings.setTranslate(v ?? false) : null,
                          ),
                          Text(
                            l10n.translateToEnglish,
                            style: TextStyle(fontSize: 15, color: canTranslate ? AppColors.ink : AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        l10n.settingsApplyHint,
                        style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.width, required this.child});

  final String label;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.inkSecondary),
        ),
        child,
      ],
    ),
  );
}
