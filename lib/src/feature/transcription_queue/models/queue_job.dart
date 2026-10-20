import 'package:extracter/src/common/database/database.dart';
import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_failure.dart';
import 'package:flutter/foundation.dart';

enum QueueJobStatus {
  pending,
  running,
  cancelling,
  done,

  /// Transcribed, but the history write failed: segments are kept in memory.
  completedUnsaved,
  failed,
  cancelled;

  bool get isTerminal => this == done || this == failed || this == cancelled || this == completedUnsaved;
}

/// One file in the queue with the settings it was enqueued with.
@immutable
class QueueJob {
  const QueueJob({
    required this.id,
    required this.sourceName,
    required this.mediaPath,
    required this.settings,
    this.status = QueueJobStatus.pending,
    this.segments = const <TranscriptSegment>[],
    this.permille,
    this.durationMs,
    this.detectedLanguage,
    this.transcriptId,
    this.failure,
  });

  final String id;

  /// File name shown in the UI and stored in history. Never logged.
  final String sourceName;
  final String mediaPath;
  final TranscriptionSettings settings;
  final QueueJobStatus status;
  final List<TranscriptSegment> segments;

  /// 0..1000 while running; null when unknown (indeterminate).
  final int? permille;
  final int? durationMs;
  final String? detectedLanguage;
  final int? transcriptId;
  final TranscriptionFailure? failure;

  QueueJob copyWith({
    QueueJobStatus? status,
    List<TranscriptSegment>? segments,
    ValueGetter<int?>? permille,
    ValueGetter<int?>? durationMs,
    ValueGetter<String?>? detectedLanguage,
    ValueGetter<int?>? transcriptId,
    ValueGetter<TranscriptionFailure?>? failure,
  }) => QueueJob(
    id: id,
    sourceName: sourceName,
    mediaPath: mediaPath,
    settings: settings,
    status: status ?? this.status,
    segments: segments ?? this.segments,
    permille: permille != null ? permille() : this.permille,
    durationMs: durationMs != null ? durationMs() : this.durationMs,
    detectedLanguage: detectedLanguage != null ? detectedLanguage() : this.detectedLanguage,
    transcriptId: transcriptId != null ? transcriptId() : this.transcriptId,
    failure: failure != null ? failure() : this.failure,
  );

  /// The history row for a finished job.
  NewTranscript toNewTranscript(DateTime createdAt) => NewTranscript(
    sourceName: sourceName,
    durationMs: durationMs,
    language: detectedLanguage ?? (settings.language == TranscriptionSettings.autoLanguage ? null : settings.language),
    modelId: settings.modelId,
    translated: settings.translate,
    createdAt: createdAt,
    segments: segments,
  );
}
