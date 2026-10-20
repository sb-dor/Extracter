import 'package:control/control.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/feature/transcription_settings_save/data/transcription_settings_save_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcription_settings_save_controller.freezed.dart';

@freezed
sealed class TranscriptionSettingsSaveState with _$TranscriptionSettingsSaveState {
  const factory TranscriptionSettingsSaveState.initial() = TranscriptionSettingsSave$InitialState;

  const factory TranscriptionSettingsSaveState.inProgress() = TranscriptionSettingsSave$InProgressState;

  const factory TranscriptionSettingsSaveState.error() = TranscriptionSettingsSave$ErrorState;

  /// [settings] is exactly what was written, so the caller can re-save a newer draft.
  const factory TranscriptionSettingsSaveState.completed(TranscriptionSettings settings) =
      TranscriptionSettingsSave$CompletedState;
}

/// Persists the full settings draft. Saves arriving mid-flight are dropped;
/// the config widget re-saves when the draft differs from [completed].
final class TranscriptionSettingsSaveController extends StateController<TranscriptionSettingsSaveState>
    with DroppableControllerHandler {
  TranscriptionSettingsSaveController({
    required ITranscriptionSettingsSaveRepository transcriptionSettingsSaveRepository,
    super.initialState = const TranscriptionSettingsSaveState.initial(),
  }) : _repository = transcriptionSettingsSaveRepository;

  final ITranscriptionSettingsSaveRepository _repository;

  void save(TranscriptionSettings settings) => handle(() async {
    setState(const TranscriptionSettingsSaveState.inProgress());
    await _repository.save(settings);
    setState(TranscriptionSettingsSaveState.completed(settings));
  }, error: (error, stackTrace) async => setState(const TranscriptionSettingsSaveState.error()));
}
