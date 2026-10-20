import 'package:control/control.dart';
import 'package:extracter/src/feature/transcript_deletion/data/transcript_deletion_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcript_deletion_controller.freezed.dart';

@freezed
sealed class TranscriptDeletionState with _$TranscriptDeletionState {
  const factory TranscriptDeletionState.initial() = TranscriptDeletion$InitialState;

  const factory TranscriptDeletionState.inProgress() = TranscriptDeletion$InProgressState;

  const factory TranscriptDeletionState.error() = TranscriptDeletion$ErrorState;

  const factory TranscriptDeletionState.completed() = TranscriptDeletion$CompletedState;
}

final class TranscriptDeletionController extends StateController<TranscriptDeletionState>
    with DroppableControllerHandler {
  TranscriptDeletionController({
    required ITranscriptDeletionRepository transcriptDeletionRepository,
    super.initialState = const TranscriptDeletionState.initial(),
  }) : _repository = transcriptDeletionRepository;

  final ITranscriptDeletionRepository _repository;

  void delete(int id) => handle(() async {
    setState(const TranscriptDeletionState.inProgress());
    await _repository.delete(id);
    setState(const TranscriptDeletionState.completed());
  }, error: (error, stackTrace) async => setState(const TranscriptDeletionState.error()));
}
