import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_failure.dart';
import 'package:flutter/foundation.dart';

/// What a running transcription reports. The stream always ends with exactly
/// one [TranscriptionCompleted] or [TranscriptionFailed].
@immutable
sealed class TranscriptionEvent {
  const TranscriptionEvent();
}

/// [permille] 0..999, or null when the duration is unknown.
final class TranscriptionProgress extends TranscriptionEvent {
  const TranscriptionProgress({required this.permille, required this.durationMs});

  final int? permille;
  final int? durationMs;
}

final class TranscriptionSegmentAdded extends TranscriptionEvent {
  const TranscriptionSegmentAdded(this.segment);

  final TranscriptSegment segment;
}

final class TranscriptionCompleted extends TranscriptionEvent {
  const TranscriptionCompleted({required this.detectedLanguage, required this.durationMs});

  final String? detectedLanguage;
  final int? durationMs;
}

final class TranscriptionFailed extends TranscriptionEvent {
  const TranscriptionFailed(this.reason);

  final TranscriptionFailure reason;
}
