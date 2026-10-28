import 'package:extracter/src/common/background/background_work.dart';
import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/feature/whisper_model_download/controller/whisper_model_download_controller.dart';
import 'package:extracter/src/feature/whisper_model_download/data/whisper_model_download_repository.dart';
import 'package:extracter/src/feature/whisper_model_download/models/model_download.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_model_labels.dart';
import 'package:flutter/material.dart';

class WhisperModelDownloadConfigInhWidget extends InheritedWidget {
  const WhisperModelDownloadConfigInhWidget({required this.state, required super.child, super.key});

  final WhisperModelDownloadConfigWidgetState state;

  static WhisperModelDownloadConfigWidgetState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<WhisperModelDownloadConfigInhWidget>()?.widget;
    assert(widget != null, 'WhisperModelDownloadConfigInhWidget was not found in element tree');
    return (widget! as WhisperModelDownloadConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(WhisperModelDownloadConfigInhWidget oldWidget) => false;
}

/// App-level scope (above the shell) so a download keeps running while the
/// user switches screens.
class WhisperModelDownloadConfigWidget extends StatefulWidget {
  const WhisperModelDownloadConfigWidget({required this.child, super.key});

  final Widget child;

  @override
  State<WhisperModelDownloadConfigWidget> createState() => WhisperModelDownloadConfigWidgetState();
}

class WhisperModelDownloadConfigWidgetState extends State<WhisperModelDownloadConfigWidget> {
  late final WhisperModelDownloadController downloadController;

  /// Keeps a download going in the background (Android).
  late final IBackgroundWork backgroundWork;

  @override
  void initState() {
    super.initState();
    final dependencies = Dependencies.of(context);
    backgroundWork = dependencies.backgroundWork;
    downloadController = WhisperModelDownloadController(
      whisperModelDownloadRepository: WhisperModelDownloadRepositoryImpl(
        modelStore: dependencies.modelStore,
        freeDiskBytes: dependencies.native.freeDiskBytes,
      ),
    )..addListener(_onState);
  }

  @override
  void dispose() {
    downloadController
      ..removeListener(_onState)
      ..dispose();
    backgroundWork.report(BackgroundWorkKind.download, null).ignore();
    super.dispose();
  }

  void download(WhisperModelSpec spec) => downloadController.download(spec);

  void cancel() => downloadController.cancel();

  void _onState() {
    final state = downloadController.state;
    _reportBackground(state);
    if (state is! WhisperModelDownload$ErrorState || state.reason == ModelDownloadFailure.cancelled) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final l10n = Localization.of(context);
    final message = switch (state.reason) {
      ModelDownloadFailure.lowStorage => l10n.downloadErrorStorageFull,
      ModelDownloadFailure.hashMismatch || ModelDownloadFailure.sizeMismatch => l10n.downloadErrorCorrupt,
      ModelDownloadFailure.storage => l10n.downloadErrorStorage,
      ModelDownloadFailure.busy => l10n.downloadErrorBusy,
      _ => l10n.downloadErrorNetwork,
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Reports "Downloading the Small model · 45% of 190 MB" while it runs.
  void _reportBackground(WhisperModelDownloadState state) {
    if (state is! WhisperModelDownload$InProgressState) {
      backgroundWork.report(BackgroundWorkKind.download, null).ignore();
      return;
    }
    final l10n = Localization.of(context);
    final percent = state.totalBytes <= 0 ? null : state.receivedBytes * 100 ~/ state.totalBytes;
    final progress = BackgroundProgress(
      channelName: l10n.notificationChannel,
      title: l10n.notificationDownloading(modelName(l10n, state.modelId)),
      text: percent == null
          ? l10n.notificationPreparing
          : l10n.notificationDownloaded(percent, FormatUtil.bytes(state.totalBytes)),
      permille: percent == null ? null : percent * 10,
    );
    backgroundWork.report(BackgroundWorkKind.download, progress).ignore();
  }

  @override
  Widget build(BuildContext context) => WhisperModelDownloadConfigInhWidget(state: this, child: widget.child);
}
