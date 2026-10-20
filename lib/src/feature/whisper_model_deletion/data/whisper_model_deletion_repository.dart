import 'package:extracter/src/common/model_store/model_store.dart';

abstract interface class IWhisperModelDeletionRepository {
  /// Throws [ModelInUseException] while queued files still need the model.
  Future<void> delete(String modelId);
}

final class WhisperModelDeletionRepositoryImpl implements IWhisperModelDeletionRepository {
  WhisperModelDeletionRepositoryImpl({required ModelStore modelStore}) : _store = modelStore;

  final ModelStore _store;

  @override
  Future<void> delete(String modelId) => _store.delete(modelId);
}
