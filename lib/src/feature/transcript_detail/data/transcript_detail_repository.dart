import 'package:drift/drift.dart';
import 'package:extracter/src/common/database/database.dart';
import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/feature/transcript_detail/models/transcript_detail.dart';
import 'package:extracter/src/feature/transcripts/models/transcript_summary.dart';

abstract interface class ITranscriptDetailRepository {
  /// Throws [TranscriptNotFoundException].
  Future<TranscriptDetail> transcript(int id);
}

final class TranscriptDetailRepositoryImpl implements ITranscriptDetailRepository {
  TranscriptDetailRepositoryImpl({required AppDatabase database}) : _db = database;

  final AppDatabase _db;

  @override
  Future<TranscriptDetail> transcript(int id) => _db.transaction(() async {
    final row = await (_db.select(_db.transcriptsTable)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) throw TranscriptNotFoundException(id);
    final segments =
        await (_db.select(_db.segmentsTable)
              ..where((s) => s.transcriptId.equals(id))
              ..orderBy([(s) => OrderingTerm.asc(s.idx)]))
            .get();
    return TranscriptDetail(
      summary: TranscriptSummary(
        id: row.id,
        sourceName: row.sourceName,
        durationMs: row.durationMs,
        language: row.language,
        modelId: row.modelId,
        translated: row.translated,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      ),
      segments: [for (final s in segments) TranscriptSegment(startMs: s.startMs, endMs: s.endMs, text: s.body)],
    );
  });
}
