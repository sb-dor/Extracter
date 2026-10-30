import 'package:control/control.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/utils/cancel_token.dart';
import 'package:extracter/src/feature/whisper_model_download/data/whisper_model_download_repository.dart';
import 'package:extracter/src/feature/whisper_model_download/models/model_download.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'whisper_model_download_controller.freezed.dart';

@freezed
sealed class WhisperModelDownloadState with _$WhisperModelDownloadState {
  const WhisperModelDownloadState._();

  const factory WhisperModelDownloadState.initial() = WhisperModelDownload$InitialState;

  const factory WhisperModelDownloadState.inProgress({
    required String modelId,
    required int receivedBytes,
    required int totalBytes,
  }) = WhisperModelDownload$InProgressState;

  const factory WhisperModelDownloadState.error({required String modelId, required ModelDownloadFailure reason}) =
      WhisperModelDownload$ErrorState;

  const factory WhisperModelDownloadState.completed(String modelId) = WhisperModelDownload$CompletedState;

  String? get downloadingModelId => switch (this) {
    WhisperModelDownload$InProgressState(:final modelId) => modelId,
    _ => null,
  };
}

/// One download at a time; [cancel] is out-of-band so it is never dropped.
final class WhisperModelDownloadController extends StateController<WhisperModelDownloadState>
    with DroppableControllerHandler {
  WhisperModelDownloadController({
    required IWhisperModelDownloadRepository whisperModelDownloadRepository,
    super.initialState = const WhisperModelDownloadState.initial(),
  }) : _repository = whisperModelDownloadRepository;

  final IWhisperModelDownloadRepository _repository;
  CancelToken? _token;

  void download(WhisperModelSpec spec) => handle(
    () async {
      final token = _token = CancelToken();
      setState(WhisperModelDownloadState.inProgress(modelId: spec.id, receivedBytes: 0, totalBytes: spec.sizeBytes));
      try {
        await for (final p in _repository.download(spec, token)) {
          setState(
            WhisperModelDownloadState.inProgress(
              modelId: spec.id,
              receivedBytes: p.receivedBytes,
              totalBytes: p.totalBytes,
            ),
          );
        }
        setState(WhisperModelDownloadState.completed(spec.id));
      } on ModelDownloadException catch (e) {
        setState(WhisperModelDownloadState.error(modelId: spec.id, reason: e.reason));
      } finally {
        _token = null;
      }
    },
    error: (error, stackTrace) async {
      setState(WhisperModelDownloadState.error(modelId: spec.id, reason: ModelDownloadFailure.network));
    },
  );

  void cancel() => _token?.cancel();

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }
}
