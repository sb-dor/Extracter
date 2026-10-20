import 'package:control/control.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/common/utils/whisper_languages.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/queue_labels.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/transcription_queue_config_widget.dart';
import 'package:extracter/src/feature/whisper_models/controller/whisper_models_controller.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_model_labels.dart';
import 'package:flutter/material.dart';

/// Tap-to-change chips: model, language, translate.
class QueueSettingsChips extends StatefulWidget {
  const QueueSettingsChips({super.key});

  @override
  State<QueueSettingsChips> createState() => _QueueSettingsChipsState();
}

class _QueueSettingsChipsState extends State<QueueSettingsChips> {
  late final _scope = TranscriptionQueueConfigInhWidget.of(context);
  late final _settings = _scope.settingsDataController;

  Future<void> _pickModel() async {
    final l10n = Localization.of(context);
    final state = _scope.whisperModelsController.state;
    if (state is! WhisperModels$CompletedState) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in state.snapshot.items.where((i) => i.fitsDevice || i.isInstalled))
              ListTile(
                title: Text(modelName(l10n, item.spec.id)),
                subtitle: Text(
                  '${FormatUtil.bytes(item.spec.sizeBytes)} · ${item.isInstalled ? l10n.modelInstalled : l10n.modelNotDownloaded}',
                ),
                trailing: item.spec.id == _settings.draft.modelId
                    ? const Icon(Icons.check, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.pop(context, item.spec.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _settings.setModel(picked);
  }

  Future<void> _pickLanguage() async {
    final l10n = Localization.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            for (final code in [TranscriptionSettings.autoLanguage, ...WhisperLanguage.all.map((l) => l.code)])
              ListTile(
                title: Text(languageLabel(l10n, code)),
                trailing: code == _settings.draft.language ? const Icon(Icons.check, color: AppColors.accent) : null,
                onTap: () => Navigator.pop(context, code),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _settings.setLanguage(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return StateConsumer<WhisperModelsController, WhisperModelsState>(
      controller: _scope.whisperModelsController,
      builder: (context, _, _) => ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          final draft = _settings.draft;
          final canTranslate = WhisperModelSpec.byId(draft.modelId)?.supportsTranslate ?? false;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                _Chip(label: l10n.modelChip(modelName(l10n, draft.modelId)), onTap: _pickModel),
                _Chip(label: languageLabel(l10n, draft.language), onTap: _pickLanguage),
                FilterChip(
                  label: Text(l10n.translateShort),
                  selected: draft.translate,
                  onSelected: canTranslate ? _settings.setTranslate : null,
                  tooltip: canTranslate ? null : l10n.translateUnsupported,
                  shape: const StadiumBorder(side: BorderSide(color: AppColors.borderStrong)),
                  backgroundColor: AppColors.surface,
                  selectedColor: AppColors.accentSoft,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    onPressed: onTap,
    backgroundColor: AppColors.surface,
    shape: const StadiumBorder(side: BorderSide(color: AppColors.borderStrong)),
    label: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [Text(label), const Icon(Icons.expand_more, size: 16)],
    ),
  );
}
