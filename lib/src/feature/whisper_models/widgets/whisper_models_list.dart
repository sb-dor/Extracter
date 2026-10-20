import 'package:control/control.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/state_widgets.dart';
import 'package:extracter/src/feature/whisper_models/controller/whisper_models_controller.dart';
import 'package:extracter/src/feature/whisper_models/models/whisper_model_item.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_model_card.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_models_config_widget.dart';
import 'package:flutter/material.dart';

/// Loads the catalogue state and builds one [WhisperModelCard] per model.
/// Shared by the desktop and mobile screens, which lay out the cards.
class WhisperModelsList extends StatefulWidget {
  const WhisperModelsList({required this.compact, required this.builder, super.key});

  final bool compact;
  final Widget Function(BuildContext context, WhisperModelsSnapshot snapshot, List<Widget> cards) builder;

  @override
  State<WhisperModelsList> createState() => _WhisperModelsListState();
}

class _WhisperModelsListState extends State<WhisperModelsList> {
  late final _scope = WhisperModelsConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) => StateConsumer<WhisperModelsController, WhisperModelsState>(
    controller: _scope.whisperModelsController,
    builder: (context, state, _) => switch (state) {
      WhisperModels$CompletedState(:final snapshot) => ListenableBuilder(
        listenable: Listenable.merge([_scope.downloadController, _scope.settingsDataController]),
        builder: (context, _) {
          final download = _scope.downloadController.state;
          final selected = _scope.settingsDataController.draft.modelId;
          return widget.builder(context, snapshot, [
            for (final item in snapshot.items)
              WhisperModelCard(
                item: item,
                compact: widget.compact,
                selected: item.spec.id == selected,
                download: download,
                onDownload: () => _scope.download(item.spec),
                onCancelDownload: _scope.cancelDownload,
                onDelete: () => _scope.delete(item.spec),
                onSelect: () => _scope.select(item.spec.id),
              ),
          ]);
        },
      ),
      WhisperModels$ErrorState() => ErrorStateWidget(
        message: Localization.of(context).modelsLoadFailed,
        onRetry: _scope.load,
      ),
      _ => const LoadingStateWidget(),
    },
  );
}
