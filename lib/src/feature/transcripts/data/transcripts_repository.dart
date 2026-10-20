import 'package:drift/drift.dart';
import 'package:extracter/src/common/database/database.dart';
import 'package:extracter/src/common/utils/fts_query.dart';
import 'package:extracter/src/feature/transcripts/models/transcript_summary.dart';

abstract interface class ITranscriptsRepository {
  /// Newest first. [after] is the keyset cursor (null = first page).
  Future<List<TranscriptSummary>> transcripts({
    required String query,
    required TranscriptsCursor? after,
    required int limit,
  });

  /// Fires after any transcript is added or deleted.
  Stream<void> get changes;
}

final class TranscriptsRepositoryImpl implements ITranscriptsRepository {
  TranscriptsRepositoryImpl({required AppDatabase database}) : _db = database;

  final AppDatabase _db;

  static const String _columns =
      't.id, t.source_name, t.duration_ms, t.language, t.model_id, t.translated, t.created_at';

  @override
  Stream<void> get changes => _db.tableUpdates(TableUpdateQuery.onTableName('transcripts')).map<void>((_) {});

  @override
  Future<List<TranscriptSummary>> transcripts({
    required String query,
    required TranscriptsCursor? after,
    required int limit,
  }) async {
    final match = ftsPrefixQuery(query);
    final conditions = <String>[];
    final variables = <Variable<Object>>[];
    if (match != null) {
      conditions.add('transcripts_fts MATCH ?');
      variables.add(Variable<String>(match));
    }
    if (after != null) {
      conditions.add('(t.created_at < ? OR (t.created_at = ? AND t.id < ?))');
      variables
        ..add(Variable<int>(after.createdAtMs))
        ..add(Variable<int>(after.createdAtMs))
        ..add(Variable<int>(after.id));
    }
    variables.add(Variable<int>(limit));
    final from = match != null ? 'transcripts t JOIN transcripts_fts ON transcripts_fts.rowid = t.id' : 'transcripts t';
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final rows = await _db
        .customSelect(
          'SELECT $_columns FROM $from $where ORDER BY t.created_at DESC, t.id DESC LIMIT ?',
          variables: variables,
          readsFrom: {_db.transcriptsTable},
        )
        .get();
    return [
      for (final row in rows)
        TranscriptSummary(
          id: row.read<int>('id'),
          sourceName: row.read<String>('source_name'),
          durationMs: row.readNullable<int>('duration_ms'),
          language: row.readNullable<String>('language'),
          modelId: row.read<String>('model_id'),
          translated: row.read<bool>('translated'),
          createdAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('created_at')),
        ),
    ];
  }
}
