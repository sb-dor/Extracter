import 'package:control/control.dart';
import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:extracter/src/feature/whisper_model_deletion/data/whisper_model_deletion_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'whisper_model_deletion_controller.freezed.dart';

@freezed
sealed class WhisperModelDeletionState with _$WhisperModelDeletionState {
  const factory WhisperModelDeletionState.initial() = WhisperModelDeletion$InitialState;

  const factory WhisperModelDeletionState.inProgress() = WhisperModelDeletion$InProgressState;

  const factory WhisperModelDeletionState.error({required bool inUse}) = WhisperModelDeletion$ErrorState;

  const factory WhisperModelDeletionState.completed() = WhisperModelDeletion$CompletedState;
}

final class WhisperModelDeletionController extends StateController<WhisperModelDeletionState>
    with DroppableControllerHandler {
  WhisperModelDeletionController({
    required IWhisperModelDeletionRepository whisperModelDeletionRepository,
    super.initialState = const WhisperModelDeletionState.initial(),
  }) : _repository = whisperModelDeletionRepository;

  final IWhisperModelDeletionRepository _repository;

  void delete(String modelId) => handle(
    () async {
      setState(const WhisperModelDeletionState.inProgress());
      await _repository.delete(modelId);
      setState(const WhisperModelDeletionState.completed());
    },
    error: (error, stackTrace) async => setState(WhisperModelDeletionState.error(inUse: error is ModelInUseException)),
  );
}
