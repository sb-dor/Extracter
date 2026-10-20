import 'package:drift/drift.dart';

/// One saved transcription. The source is stored by file name only, never by path.
@DataClassName('TranscriptRow')
class TranscriptsTable extends Table {
  @override
  String get tableName => 'transcripts';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get sourceName => text()();

  IntColumn get durationMs => integer().nullable()();

  /// ISO-639-1 code detected or chosen for the transcription.
  TextColumn get language => text().nullable()();

  TextColumn get modelId => text()();

  BoolColumn get translated => boolean()();

  /// Unix epoch milliseconds; with [id] it forms the keyset pagination cursor.
  IntColumn get createdAt => integer()();

  /// All segment texts joined, indexed by the `transcripts_fts` FTS5 table.
  TextColumn get fullText => text()();
}
