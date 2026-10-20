import 'package:drift/drift.dart';
import 'package:extracter/src/common/database/tables/transcripts_table.dart';

/// One timestamped segment of a transcript; deleted with its transcript.
@DataClassName('SegmentRow')
class SegmentsTable extends Table {
  @override
  String get tableName => 'segments';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get transcriptId => integer().references(TranscriptsTable, #id, onDelete: KeyAction.cascade)();

  /// Position of the segment within its transcript.
  IntColumn get idx => integer()();

  IntColumn get startMs => integer()();

  IntColumn get endMs => integer()();

  TextColumn get body => text().named('text')();
}
