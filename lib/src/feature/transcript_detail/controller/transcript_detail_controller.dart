import 'package:control/control.dart';
import 'package:extracter/src/feature/transcript_detail/data/transcript_detail_repository.dart';
import 'package:extracter/src/feature/transcript_detail/models/transcript_detail.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcript_detail_controller.freezed.dart';

@freezed
sealed class TranscriptDetailState with _$TranscriptDetailState {
  const factory TranscriptDetailState.initial() = TranscriptDetail$InitialState;

  const factory TranscriptDetailState.inProgress() = TranscriptDetail$InProgressState;

  const factory TranscriptDetailState.error({required bool notFound}) = TranscriptDetail$ErrorState;

  const factory TranscriptDetailState.completed(TranscriptDetail transcript) = TranscriptDetail$CompletedState;
}

/// Loads one transcript by id.
final class TranscriptDetailController extends StateController<TranscriptDetailState> with SequentialControllerHandler {
  TranscriptDetailController({
    required ITranscriptDetailRepository transcriptDetailRepository,
    super.initialState = const TranscriptDetailState.initial(),
  }) : _repository = transcriptDetailRepository;

  final ITranscriptDetailRepository _repository;

  void load(int id) => handle(
    () async {
      setState(const TranscriptDetailState.inProgress());
      setState(TranscriptDetailState.completed(await _repository.transcript(id)));
    },
    error: (error, stackTrace) async =>
        setState(TranscriptDetailState.error(notFound: error is TranscriptNotFoundException)),
  );
}
