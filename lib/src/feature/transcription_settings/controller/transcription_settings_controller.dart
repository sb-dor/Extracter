import 'package:control/control.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/feature/transcription_settings/data/transcription_settings_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcription_settings_controller.freezed.dart';

@freezed
sealed class TranscriptionSettingsState with _$TranscriptionSettingsState {
  const factory TranscriptionSettingsState.initial() = TranscriptionSettings$InitialState;

  const factory TranscriptionSettingsState.inProgress() = TranscriptionSettings$InProgressState;

  const factory TranscriptionSettingsState.error() = TranscriptionSettings$ErrorState;

  const factory TranscriptionSettingsState.completed(TranscriptionSettings settings) =
      TranscriptionSettings$CompletedState;
}

/// Loads the persisted transcription settings.
final class TranscriptionSettingsController extends StateController<TranscriptionSettingsState>
    with SequentialControllerHandler {
  TranscriptionSettingsController({
    required ITranscriptionSettingsRepository transcriptionSettingsRepository,
    super.initialState = const TranscriptionSettingsState.initial(),
  }) : _repository = transcriptionSettingsRepository;

  final ITranscriptionSettingsRepository _repository;

  void load() => handle(() async {
    setState(const TranscriptionSettingsState.inProgress());
    setState(TranscriptionSettingsState.completed(await _repository.load()));
  }, error: (error, stackTrace) async => setState(const TranscriptionSettingsState.error()));
}
