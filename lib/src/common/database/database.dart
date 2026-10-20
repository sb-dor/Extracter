import 'package:drift/drift.dart';
import 'package:extracter/src/common/database/tables/segments_table.dart';
import 'package:extracter/src/common/database/tables/transcripts_table.dart';
import 'package:extracter/src/common/model/transcript_segment.dart';

part 'database.g.dart';

/// A finished transcription ready to be stored.
final class NewTranscript {
  const NewTranscript({
    required this.sourceName,
    required this.durationMs,
    required this.language,
    required this.modelId,
    required this.translated,
    required this.createdAt,
    required this.segments,
  });

  final String sourceName;
  final int? durationMs;
  final String? language;
  final String modelId;
  final bool translated;
  final DateTime createdAt;
  final List<TranscriptSegment> segments;
}

@DriftDatabase(tables: [TranscriptsTable, SegmentsTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await m.createIndex(
        Index(
          'transcripts_created_at',
          'CREATE INDEX transcripts_created_at ON transcripts (created_at DESC, id DESC)',
        ),
      );
      await m.createIndex(
        Index('segments_transcript', 'CREATE INDEX segments_transcript ON segments (transcript_id, idx)'),
      );
      // External-content FTS5 index over file name + text, kept in sync by triggers.
      await customStatement(
        "CREATE VIRTUAL TABLE transcripts_fts USING fts5(source_name, full_text, content='transcripts', "
        "content_rowid='id', tokenize='unicode61 remove_diacritics 2')",
      );
      await customStatement(
        'CREATE TRIGGER transcripts_ai AFTER INSERT ON transcripts BEGIN '
        'INSERT INTO transcripts_fts(rowid, source_name, full_text) VALUES (new.id, new.source_name, new.full_text); END',
      );
      await customStatement(
        'CREATE TRIGGER transcripts_ad AFTER DELETE ON transcripts BEGIN '
        "INSERT INTO transcripts_fts(transcripts_fts, rowid, source_name, full_text) VALUES ('delete', old.id, old.source_name, old.full_text); END",
      );
      await customStatement(
        'CREATE TRIGGER transcripts_au AFTER UPDATE ON transcripts BEGIN '
        "INSERT INTO transcripts_fts(transcripts_fts, rowid, source_name, full_text) VALUES ('delete', old.id, old.source_name, old.full_text); "
        'INSERT INTO transcripts_fts(rowid, source_name, full_text) VALUES (new.id, new.source_name, new.full_text); END',
      );
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Stores a transcript and all its segments in one transaction; returns its id.
  Future<int> insertTranscript(NewTranscript transcript) => transaction(() async {
    final id = await into(transcriptsTable).insert(
      TranscriptsTableCompanion.insert(
        sourceName: transcript.sourceName,
        durationMs: Value(transcript.durationMs),
        language: Value(transcript.language),
        modelId: transcript.modelId,
        translated: transcript.translated,
        createdAt: transcript.createdAt.millisecondsSinceEpoch,
        fullText: transcript.segments.map((s) => s.text).join('\n'),
      ),
    );
    await batch((b) {
      b.insertAll(segmentsTable, [
        for (final (i, s) in transcript.segments.indexed)
          SegmentsTableCompanion.insert(transcriptId: id, idx: i, startMs: s.startMs, endMs: s.endMs, body: s.text),
      ]);
    });
    return id;
  });
}
