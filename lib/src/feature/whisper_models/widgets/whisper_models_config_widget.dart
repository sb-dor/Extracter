import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/utils/screen_util.dart';
import 'package:extracter/src/feature/transcription_settings/widgets/controllers/transcription_settings_data_controller.dart';
import 'package:extracter/src/feature/transcription_settings/widgets/transcription_settings_config_widget.dart';
import 'package:extracter/src/feature/whisper_model_deletion/widgets/whisper_model_deletion_config_widget.dart';
import 'package:extracter/src/feature/whisper_model_download/controller/whisper_model_download_controller.dart';
import 'package:extracter/src/feature/whisper_model_download/widgets/whisper_model_download_config_widget.dart';
import 'package:extracter/src/feature/whisper_models/controller/whisper_models_controller.dart';
import 'package:extracter/src/feature/whisper_models/data/whisper_models_repository.dart';
import 'package:extracter/src/feature/whisper_models/widgets/desktop/whisper_models_desktop_widget.dart';
import 'package:extracter/src/feature/whisper_models/widgets/mobile/whisper_models_mobile_widget.dart';
import 'package:flutter/widgets.dart';

class WhisperModelsConfigInhWidget extends InheritedWidget {
  const WhisperModelsConfigInhWidget({required this.state, required super.child, super.key});

  final WhisperModelsConfigWidgetState state;

  static WhisperModelsConfigWidgetState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<WhisperModelsConfigInhWidget>()?.widget;
    assert(widget != null, 'WhisperModelsConfigInhWidget was not found in element tree');
    return (widget! as WhisperModelsConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(WhisperModelsConfigInhWidget oldWidget) => false;
}

class WhisperModelsConfigWidget extends StatefulWidget {
  const WhisperModelsConfigWidget({super.key});

  @override
  State<WhisperModelsConfigWidget> createState() => WhisperModelsConfigWidgetState();
}

class WhisperModelsConfigWidgetState extends State<WhisperModelsConfigWidget> {
  late final WhisperModelsController whisperModelsController;
  late final WhisperModelDownloadController downloadController;
  late final TranscriptionSettingsDataController settingsDataController;
  late final WhisperModelDownloadConfigWidgetState _download;

  @override
  void initState() {
    super.initState();
    final dependencies = Dependencies.of(context);
    _download = WhisperModelDownloadConfigInhWidget.of(context);
    downloadController = _download.downloadController;
    settingsDataController = TranscriptionSettingsConfigInhWidget.of(context).settingsDataController;
    whisperModelsController = WhisperModelsController(
      whisperModelsRepository: WhisperModelsRepositoryImpl(
        modelStore: dependencies.modelStore,
        native: dependencies.native,
      ),
    );
    whisperModelsController.changes.addListener(_reload);
    whisperModelsController.load();
  }

  @override
  void dispose() {
    whisperModelsController.changes.removeListener(_reload);
    whisperModelsController.dispose();
    super.dispose();
  }

  void _reload() => whisperModelsController.load(silent: true);

  void load() => whisperModelsController.load();

  void download(WhisperModelSpec spec) => _download.download(spec);

  void cancelDownload() => _download.cancel();

  void delete(WhisperModelSpec spec) => WhisperModelDeletionConfigWidget.show(context, spec: spec);

  void select(String modelId) => settingsDataController.setModel(modelId);

  @override
  Widget build(BuildContext context) => WhisperModelsConfigInhWidget(
    state: this,
    child: context.screenSizeMaybeWhen(
      orElse: () => const WhisperModelsDesktopWidget(),
      phone: () => const WhisperModelsMobileWidget(),
    ),
  );
}
