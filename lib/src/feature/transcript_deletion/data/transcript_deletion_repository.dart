import 'package:extracter/src/common/database/database.dart';

abstract interface class ITranscriptDeletionRepository {
  Future<void> delete(int id);
}

final class TranscriptDeletionRepositoryImpl implements ITranscriptDeletionRepository {
  TranscriptDeletionRepositoryImpl({required AppDatabase database}) : _db = database;

  final AppDatabase _db;

  /// Segments go with it (foreign key cascade); the FTS trigger drops the index row.
  @override
  Future<void> delete(int id) => _db.transaction(() async {
    await (_db.delete(_db.transcriptsTable)..where((t) => t.id.equals(id))).go();
  });
}
