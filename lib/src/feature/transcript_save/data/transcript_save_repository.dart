import 'package:extracter/src/common/database/database.dart';

abstract interface class ITranscriptSaveRepository {
  Future<int> save(NewTranscript transcript);
}

final class TranscriptSaveRepositoryImpl implements ITranscriptSaveRepository {
  TranscriptSaveRepositoryImpl({required AppDatabase database}) : _database = database;

  final AppDatabase _database;

  @override
  Future<int> save(NewTranscript transcript) => _database.insertTranscript(transcript);
}
