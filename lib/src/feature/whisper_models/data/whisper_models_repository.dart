import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:extracter/src/feature/whisper_models/models/whisper_model_item.dart';
import 'package:extracter_native/extracter_native.dart';
import 'package:flutter/foundation.dart';

abstract interface class IWhisperModelsRepository {
  Future<WhisperModelsSnapshot> load();

  /// Fires whenever a model is installed, deleted, reserved or released.
  Listenable get changes;
}

final class WhisperModelsRepositoryImpl implements IWhisperModelsRepository {
  WhisperModelsRepositoryImpl({required ModelStore modelStore, required IExtracterNative native})
    : _store = modelStore,
      _native = native;

  final ModelStore _store;
  final IExtracterNative _native;

  @override
  Listenable get changes => _store;

  @override
  Future<WhisperModelsSnapshot> load() async {
    final ram = _native.totalRamBytes;
    return WhisperModelsSnapshot(
      items: [
        for (final spec in WhisperModelSpec.catalog)
          WhisperModelItem(
            spec: spec,
            fileState: _store.stateOf(spec.id),
            reservations: _store.reservationsOf(spec.id),
            fitsDevice: spec.fitsMemory(ram),
          ),
      ],
      totalRamBytes: ram,
      freeDiskBytes: _native.freeDiskBytes(_store.directory.path),
    );
  }
}
