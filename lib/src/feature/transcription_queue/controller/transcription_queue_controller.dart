import 'package:collection/collection.dart';
import 'package:control/control.dart';
import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/feature/transcription_queue/data/transcription_queue_repository.dart';
import 'package:extracter/src/feature/transcription_queue/models/picked_media.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_event.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_failure.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:l/l.dart';

part 'transcription_queue_controller.freezed.dart';

@freezed
sealed class TranscriptionQueueState with _$TranscriptionQueueState {
  const TranscriptionQueueState._();

  const factory TranscriptionQueueState.idle({@Default(<QueueJob>[]) List<QueueJob> jobs}) =
      TranscriptionQueue$IdleState;

  const factory TranscriptionQueueState.processing({required List<QueueJob> jobs}) = TranscriptionQueue$ProcessingState;

  /// The job a native worker is busy with (running or unwinding a cancel).
  QueueJob? get active =>
      jobs.firstWhereOrNull((j) => j.status == QueueJobStatus.running || j.status == QueueJobStatus.cancelling);

  bool get isWorking => active != null;
}

/// Runs queued files one at a time. Cancel/remove are out-of-band (not in
/// handle()), so they are never queued behind the running transcription.
final class TranscriptionQueueController extends StateController<TranscriptionQueueState>
    with SequentialControllerHandler {
  TranscriptionQueueController({
    required ITranscriptionQueueRepository transcriptionQueueRepository,
    super.initialState = const TranscriptionQueueState.idle(),
  }) : _repository = transcriptionQueueRepository;

  final ITranscriptionQueueRepository _repository;

  /// Adds files with a snapshot of [settings]; returns the files refused.
  Future<List<QueueRejectedException>> enqueue(List<PickedMedia> media, TranscriptionSettings settings) async {
    final rejected = <QueueRejectedException>[];
    for (final item in media) {
      try {
        final job = await _repository.prepare(item, settings);
        if (isDisposed) {
          await _repository.discard(job);
          return rejected;
        }
        _setJobs([...state.jobs, job]);
      } on QueueRejectedException catch (e) {
        rejected.add(e);
      }
    }
    _pump();
    return rejected;
  }

  /// Pending: removed at once. Running: moves to cancelling until native confirms.
  void cancel(String jobId) {
    final job = state.jobs.firstWhereOrNull((j) => j.id == jobId);
    if (job == null) return;
    switch (job.status) {
      case QueueJobStatus.pending:
        _setJobs(state.jobs.where((j) => j.id != jobId).toList());
        _repository.discard(job).ignore();
      case QueueJobStatus.running:
        _update(jobId, (j) => j.copyWith(status: QueueJobStatus.cancelling));
        _repository.cancel(job);
      case _:
        break;
    }
  }

  /// Removes a finished row (unsaved transcripts excepted: they would be lost).
  void remove(String jobId) {
    final job = state.jobs.firstWhereOrNull((j) => j.id == jobId);
    if (job == null) return;
    if (job.status == QueueJobStatus.pending) return cancel(jobId);
    if (job.status.isTerminal && job.status != QueueJobStatus.completedUnsaved) {
      _setJobs(state.jobs.where((j) => j.id != jobId).toList());
    }
  }

  void clearFinished() =>
      _setJobs(state.jobs.where((j) => !j.status.isTerminal || j.status == QueueJobStatus.completedUnsaved).toList());

  /// A retried save (transcript_save feature) succeeded.
  void markSaved(String jobId, int transcriptId) => _update(
    jobId,
    (j) => j.copyWith(status: QueueJobStatus.done, transcriptId: () => transcriptId, failure: () => null),
  );

  void _pump() => handle(
    () async {
      while (!isDisposed) {
        final next = state.jobs.firstWhereOrNull((j) => j.status == QueueJobStatus.pending);
        if (next == null) break;
        await _run(next);
      }
      if (isDisposed) return;
      setState(TranscriptionQueueState.idle(jobs: state.jobs));
      await _repository.clearTemporaryFiles();
    },
    error: (error, stackTrace) async {
      l.e('queue runner failed: ${error.runtimeType}', stackTrace);
      if (!isDisposed) setState(TranscriptionQueueState.idle(jobs: state.jobs));
    },
  );

  Future<void> _run(QueueJob job) async {
    _update(job.id, (j) => j.copyWith(status: QueueJobStatus.running, permille: () => 0));
    final segments = <TranscriptSegment>[];
    TranscriptionEvent? last;
    await for (final event in _repository.transcribe(job)) {
      last = event;
      switch (event) {
        case TranscriptionProgress(:final permille, :final durationMs):
          _update(job.id, (j) => j.copyWith(permille: () => permille, durationMs: () => durationMs ?? j.durationMs));
        case TranscriptionSegmentAdded(:final segment):
          segments.add(segment);
          _update(job.id, (j) => j.copyWith(segments: List.unmodifiable(segments)));
        case TranscriptionCompleted() || TranscriptionFailed():
          break;
      }
    }

    switch (last) {
      case TranscriptionCompleted(:final detectedLanguage, :final durationMs):
        final finished = _find(job.id)?.copyWith(
          segments: List.unmodifiable(segments),
          permille: () => 1000,
          detectedLanguage: () => detectedLanguage,
          durationMs: () => durationMs ?? job.durationMs,
        );
        if (finished == null) return;
        try {
          final id = await _repository.save(finished);
          _put(finished.copyWith(status: QueueJobStatus.done, transcriptId: () => id));
        } on Object catch (error) {
          l.w('history save failed: ${error.runtimeType}');
          _put(
            finished.copyWith(status: QueueJobStatus.completedUnsaved, failure: () => TranscriptionFailure.saveFailed),
          );
        }
      case TranscriptionFailed(reason: TranscriptionFailure.cancelled):
        _update(job.id, (j) => j.copyWith(status: QueueJobStatus.cancelled, permille: () => null));
      case TranscriptionFailed(:final reason):
        _update(job.id, (j) => j.copyWith(status: QueueJobStatus.failed, failure: () => reason, permille: () => null));
      case _:
        _update(job.id, (j) => j.copyWith(status: QueueJobStatus.failed, failure: () => TranscriptionFailure.internal));
    }
  }

  QueueJob? _find(String jobId) => state.jobs.firstWhereOrNull((j) => j.id == jobId);

  void _put(QueueJob job) => _update(job.id, (_) => job);

  void _update(String jobId, QueueJob Function(QueueJob job) change) {
    if (isDisposed) return;
    _setJobs([for (final j in state.jobs) j.id == jobId ? change(j) : j]);
  }

  void _setJobs(List<QueueJob> jobs) {
    if (isDisposed) return;
    final working = jobs.any((j) => j.status == QueueJobStatus.running || j.status == QueueJobStatus.cancelling);
    setState(
      working || isProcessing
          ? TranscriptionQueueState.processing(jobs: List.unmodifiable(jobs))
          : TranscriptionQueueState.idle(jobs: List.unmodifiable(jobs)),
    );
  }

  @override
  void dispose() {
    final active = state.active;
    if (active != null) _repository.cancel(active);
    super.dispose();
  }
}
