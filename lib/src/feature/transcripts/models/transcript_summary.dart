import 'package:flutter/foundation.dart';

/// One History row (without the segments).
@immutable
class TranscriptSummary {
  const TranscriptSummary({
    required this.id,
    required this.sourceName,
    required this.durationMs,
    required this.language,
    required this.modelId,
    required this.translated,
    required this.createdAt,
  });

  final int id;
  final String sourceName;
  final int? durationMs;
  final String? language;
  final String modelId;
  final bool translated;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) => other is TranscriptSummary && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Keyset cursor: the last row of the page already shown.
@immutable
class TranscriptsCursor {
  const TranscriptsCursor({required this.createdAtMs, required this.id});

  factory TranscriptsCursor.after(TranscriptSummary row) =>
      TranscriptsCursor(createdAtMs: row.createdAt.millisecondsSinceEpoch, id: row.id);

  final int createdAtMs;
  final int id;
}
