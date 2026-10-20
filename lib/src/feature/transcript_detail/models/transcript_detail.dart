import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/feature/transcripts/models/transcript_summary.dart';
import 'package:flutter/foundation.dart';

@immutable
class TranscriptDetail {
  const TranscriptDetail({required this.summary, required this.segments});

  final TranscriptSummary summary;
  final List<TranscriptSegment> segments;
}

/// The transcript was deleted (or never existed).
final class TranscriptNotFoundException implements Exception {
  const TranscriptNotFoundException(this.id);

  final int id;
}
