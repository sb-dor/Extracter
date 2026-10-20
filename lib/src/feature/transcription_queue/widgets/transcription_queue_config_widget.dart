import 'package:desktop_drop/desktop_drop.dart';
import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/common/utils/screen_util.dart';
import 'package:extracter/src/common/widget/adaptive_dialog_widget.dart';
import 'package:extracter/src/common/widget/app_shell.dart';
import 'package:extracter/src/feature/transcript_detail/widgets/transcript_detail_config_widget.dart';
import 'package:extracter/src/feature/transcript_export/widgets/transcript_export_config_widget.dart';
import 'package:extracter/src/feature/transcript_save/controller/transcript_save_controller.dart';
import 'package:extracter/src/feature/transcript_save/data/transcript_save_repository.dart';
import 'package:extracter/src/feature/transcription_queue/controller/transcription_queue_controller.dart';
import 'package:extracter/src/feature/transcription_queue/data/transcription_queue_repository.dart';
import 'package:extracter/src/feature/transcription_queue/models/picked_media.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_failure.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/desktop/transcription_queue_desktop_widget.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/mobile/transcription_queue_mobile_widget.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/queue_labels.dart';
import 'package:extracter/src/feature/transcription_settings/widgets/controllers/transcription_settings_data_controller.dart';
import 'package:extracter/src/feature/transcription_settings/widgets/transcription_settings_config_widget.dart';
import 'package:extracter/src/feature/whisper_model_download/widgets/whisper_model_download_config_widget.dart';
import 'package:extracter/src/feature/whisper_models/controller/whisper_models_controller.dart';
import 'package:extracter/src/feature/whisper_models/data/whisper_models_repository.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_model_labels.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:l/l.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class TranscriptionQueueConfigInhWidget extends InheritedWidget {
  const TranscriptionQueueConfigInhWidget({required this.state, required super.child, super.key});

  final TranscriptionQueueConfigWidgetState state;

  static TranscriptionQueueConfigWidgetState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<TranscriptionQueueConfigInhWidget>()?.widget;
    assert(widget != null, 'TranscriptionQueueConfigInhWidget was not found in element tree');
    return (widget! as TranscriptionQueueConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(TranscriptionQueueConfigInhWidget oldWidget) => false;
}

class TranscriptionQueueConfigWidget extends StatefulWidget {
  const TranscriptionQueueConfigWidget({super.key});

  @override
  State<TranscriptionQueueConfigWidget> createState() => TranscriptionQueueConfigWidgetState();
}

class TranscriptionQueueConfigWidgetState extends State<TranscriptionQueueConfigWidget> {
  late final TranscriptionQueueController queueController;
  late final TranscriptSaveController transcriptSaveController;

  /// Installed / allowed models for the model picker.
  late final WhisperModelsController whisperModelsController;
  late final TranscriptionSettingsDataController settingsDataController;

  /// True while picked files are being validated / copied in.
  final ValueNotifier<bool> adding = ValueNotifier<bool>(false);

  /// True while a drag hovers over the window (desktop).
  final ValueNotifier<bool> dragging = ValueNotifier<bool>(false);

  /// When the active job started, for the time-left estimate.
  DateTime? activeSince;
  bool _wakelock = false;

  @override
  void initState() {
    super.initState();
    final dependencies = Dependencies.of(context);
    settingsDataController = TranscriptionSettingsConfigInhWidget.of(context).settingsDataController;
    queueController = TranscriptionQueueController(
      transcriptionQueueRepository: TranscriptionQueueRepositoryImpl(
        native: dependencies.native,
        modelStore: dependencies.modelStore,
        database: dependencies.database,
        inboxDirectory: dependencies.inboxDirectory,
      ),
    )..addListener(_onQueueChanged);
    transcriptSaveController = TranscriptSaveController(
      transcriptSaveRepository: TranscriptSaveRepositoryImpl(database: dependencies.database),
    )..addListener(_onSaveChanged);
    whisperModelsController = WhisperModelsController(
      whisperModelsRepository: WhisperModelsRepositoryImpl(
        modelStore: dependencies.modelStore,
        native: dependencies.native,
      ),
    );
    whisperModelsController.changes.addListener(_reloadModels);
    whisperModelsController.load();
  }

  @override
  void dispose() {
    queueController
      ..removeListener(_onQueueChanged)
      ..dispose();
    transcriptSaveController
      ..removeListener(_onSaveChanged)
      ..dispose();
    whisperModelsController.changes.removeListener(_reloadModels);
    whisperModelsController.dispose();
    adding.dispose();
    dragging.dispose();
    if (_wakelock) WakelockPlus.disable().ignore();
    super.dispose();
  }

  void _reloadModels() => whisperModelsController.load(silent: true);

  void _onQueueChanged() {
    final state = queueController.state;
    final working = state.isWorking;
    if (working && activeSince == null) activeSince = DateTime.now();
    if (state.active == null) activeSince = null;
    if (working != _wakelock) {
      _wakelock = working;
      // The screen stays on while transcribing; the OS would otherwise suspend us.
      WakelockPlus.toggle(enable: working).catchError((Object e) => l.w('wakelock: ${e.runtimeType}'));
    }
  }

  void _onSaveChanged() {
    final state = transcriptSaveController.state;
    if (state is TranscriptSave$CompletedState) queueController.markSaved(state.jobId, state.transcriptId);
    if (state is TranscriptSave$ErrorState && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Localization.of(context).failureSave)));
    }
  }

  Future<void> pickFiles() async {
    if (adding.value) return;
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(dialogTitle: Localization.of(context).addFiles);
    } on Object catch (e) {
      l.w('file picker failed: ${e.runtimeType}');
      return;
    }
    await addFiles([for (final f in files) PickedMedia(name: f.name, path: f.path, file: f.xFile)]);
  }

  Future<void> addDropped(List<DropItem> items) => addFiles([
    for (final item in items)
      if (item is! DropItemDirectory) PickedMedia(name: item.name, path: item.path, file: item),
  ]);

  Future<void> addFiles(List<PickedMedia> media) async {
    if (media.isEmpty || adding.value) return;
    adding.value = true;
    try {
      final rejected = await queueController.enqueue(media, settingsDataController.draft);
      if (!mounted || rejected.isEmpty) return;
      if (rejected.any((r) => r.reason == TranscriptionFailure.modelMissing)) {
        await _showModelMissing();
        return;
      }
      final l10n = Localization.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rejected.length == 1
                ? l10n.addRejectedOne(rejected.first.fileName, failureMessage(l10n, rejected.first.reason))
                : l10n.addRejectedMany(rejected.length, failureMessage(l10n, rejected.first.reason)),
          ),
        ),
      );
    } finally {
      if (mounted) adding.value = false;
    }
  }

  Future<void> _showModelMissing() async {
    final spec = WhisperModelSpec.byId(settingsDataController.draft.modelId);
    if (spec == null) return;
    final l10n = Localization.of(context);
    final shell = AppShellScope.of(context);
    final download = WhisperModelDownloadConfigInhWidget.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AdaptiveDialogWidget(
        icon: Icons.download,
        title: l10n.modelMissingTitle(modelName(l10n, spec.id)),
        content: l10n.modelMissingMessage(modelName(l10n, spec.id), FormatUtil.bytes(spec.sizeBytes)),
        cancelLabel: l10n.notNow,
        confirmLabel: l10n.downloadSize(FormatUtil.bytes(spec.sizeBytes)),
        onConfirm: () {
          Navigator.pop(dialogContext);
          download.download(spec);
          shell.selectTab(AppTab.models);
        },
      ),
    );
  }

  void cancel(String jobId) => queueController.cancel(jobId);

  void remove(String jobId) => queueController.remove(jobId);

  void clearFinished() => queueController.clearFinished();

  void retrySave(QueueJob job) =>
      transcriptSaveController.save(jobId: job.id, transcript: job.toNewTranscript(DateTime.now()));

  void export(QueueJob job) =>
      TranscriptExportConfigWidget.showFormatPicker(context, sourceName: job.sourceName, segments: job.segments);

  void openTranscript(int transcriptId) => TranscriptDetailConfigWidget.open(context, transcriptId: transcriptId);

  @override
  Widget build(BuildContext context) => TranscriptionQueueConfigInhWidget(
    state: this,
    child: context.screenSizeMaybeWhen(
      orElse: () => const TranscriptionQueueMobileWidget(),
      desktop: () => DropTarget(
        onDragEntered: (_) => dragging.value = true,
        onDragExited: (_) => dragging.value = false,
        onDragDone: (details) {
          dragging.value = false;
          addDropped(details.files);
        },
        child: const TranscriptionQueueDesktopWidget(),
      ),
    ),
  );
}
