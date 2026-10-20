import 'package:control/control.dart';
import 'package:extracter/src/common/database/database.dart';
import 'package:extracter/src/feature/transcript_save/data/transcript_save_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcript_save_controller.freezed.dart';

@freezed
sealed class TranscriptSaveState with _$TranscriptSaveState {
  const factory TranscriptSaveState.initial() = TranscriptSave$InitialState;

  const factory TranscriptSaveState.inProgress(String jobId) = TranscriptSave$InProgressState;

  const factory TranscriptSaveState.error(String jobId) = TranscriptSave$ErrorState;

  const factory TranscriptSaveState.completed({required String jobId, required int transcriptId}) =
      TranscriptSave$CompletedState;
}

/// Retries saving a transcript whose first history write failed.
final class TranscriptSaveController extends StateController<TranscriptSaveState> with DroppableControllerHandler {
  TranscriptSaveController({
    required ITranscriptSaveRepository transcriptSaveRepository,
    super.initialState = const TranscriptSaveState.initial(),
  }) : _repository = transcriptSaveRepository;

  final ITranscriptSaveRepository _repository;

  void save({required String jobId, required NewTranscript transcript}) => handle(() async {
    setState(TranscriptSaveState.inProgress(jobId));
    final id = await _repository.save(transcript);
    setState(TranscriptSaveState.completed(jobId: jobId, transcriptId: id));
  }, error: (error, stackTrace) async => setState(TranscriptSaveState.error(jobId)));
}
