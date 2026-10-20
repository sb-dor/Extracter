import 'dart:ui';

import 'package:control/control.dart';
import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/utils/transcript_formatters.dart';
import 'package:extracter/src/feature/transcript_export/data/transcript_export_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcript_export_controller.freezed.dart';

@freezed
sealed class TranscriptExportState with _$TranscriptExportState {
  const factory TranscriptExportState.initial() = TranscriptExport$InitialState;

  const factory TranscriptExportState.inProgress() = TranscriptExport$InProgressState;

  const factory TranscriptExportState.error() = TranscriptExport$ErrorState;

  const factory TranscriptExportState.completed(ExportResult result) = TranscriptExport$CompletedState;
}

final class TranscriptExportController extends StateController<TranscriptExportState> with DroppableControllerHandler {
  TranscriptExportController({
    required ITranscriptExportRepository transcriptExportRepository,
    super.initialState = const TranscriptExportState.initial(),
  }) : _repository = transcriptExportRepository;

  final ITranscriptExportRepository _repository;

  void export({
    required String sourceName,
    required List<TranscriptSegment> segments,
    required TranscriptFormat format,
    Rect? shareOrigin,
  }) => handle(() async {
    setState(const TranscriptExportState.inProgress());
    final result = await _repository.export(
      sourceName: sourceName,
      segments: segments,
      format: format,
      shareOrigin: shareOrigin,
    );
    setState(TranscriptExportState.completed(result));
  }, error: (error, stackTrace) async => setState(const TranscriptExportState.error()));
}
