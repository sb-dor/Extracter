import 'dart:io';

import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum ModelFileState { absent, downloading, installed, deleting }

/// The model is reserved by queued or running jobs.
final class ModelInUseException implements Exception {
  const ModelInUseException(this.modelId);

  final String modelId;
}

/// Another download or delete of the same model is in progress.
final class ModelBusyException implements Exception {
  const ModelBusyException(this.modelId);

  final String modelId;
}

final class ModelNotInstalledException implements Exception {
  const ModelNotInstalledException(this.modelId);

  final String modelId;
}

/// Keeps one model file from being deleted while a job needs it.
/// [release] is idempotent; the owner calls it exactly once on every path.
final class ModelReservation {
  ModelReservation._(this._store, this.modelId, this.path);

  final ModelStore _store;
  final String modelId;
  final String path;
  bool _released = false;

  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    _store._release(modelId);
  }
}

/// The single coordinator for model files: installed state, downloads,
/// deletes and reservations all go through it, so they cannot race.
final class ModelStore extends ChangeNotifier {
  ModelStore({required this.directory});

  final Directory directory;
  final Set<String> _installed = <String>{};
  final Set<String> _downloading = <String>{};
  final Set<String> _deleting = <String>{};
  final Map<String, int> _reservations = <String, int>{};

  Future<void> initialize() async {
    await directory.create(recursive: true);
    for (final spec in WhisperModelSpec.catalog) {
      final file = File(filePath(spec));
      // Files only reach their final name after SHA-256 verification.
      if (file.existsSync() && file.lengthSync() == spec.sizeBytes) _installed.add(spec.id);
    }
  }

  String filePath(WhisperModelSpec spec) => p.join(directory.path, spec.fileName);

  /// Partial download; same directory as the final file so the rename is atomic.
  String partPath(WhisperModelSpec spec) => '${filePath(spec)}.part';

  ModelFileState stateOf(String modelId) {
    if (_deleting.contains(modelId)) return ModelFileState.deleting;
    if (_downloading.contains(modelId)) return ModelFileState.downloading;
    if (_installed.contains(modelId)) return ModelFileState.installed;
    return ModelFileState.absent;
  }

  bool isInstalled(String modelId) => stateOf(modelId) == ModelFileState.installed;

  /// Number of queued or running jobs holding [modelId].
  int reservationsOf(String modelId) => _reservations[modelId] ?? 0;

  ModelReservation reserve(String modelId) {
    final spec = WhisperModelSpec.byId(modelId);
    if (spec == null || !isInstalled(modelId)) throw ModelNotInstalledException(modelId);
    _reservations[modelId] = reservationsOf(modelId) + 1;
    notifyListeners();
    return ModelReservation._(this, modelId, filePath(spec));
  }

  void _release(String modelId) {
    final count = reservationsOf(modelId) - 1;
    if (count <= 0) {
      _reservations.remove(modelId);
    } else {
      _reservations[modelId] = count;
    }
    notifyListeners();
  }

  void beginDownload(String modelId) {
    if (stateOf(modelId) != ModelFileState.absent) throw ModelBusyException(modelId);
    _downloading.add(modelId);
    notifyListeners();
  }

  void completeDownload(String modelId) {
    _downloading.remove(modelId);
    _installed.add(modelId);
    notifyListeners();
  }

  void abortDownload(String modelId) {
    _downloading.remove(modelId);
    notifyListeners();
  }

  Future<void> delete(String modelId) async {
    final spec = WhisperModelSpec.byId(modelId);
    if (spec == null) throw ModelNotInstalledException(modelId);
    if (reservationsOf(modelId) > 0) throw ModelInUseException(modelId);
    if (stateOf(modelId) != ModelFileState.installed) throw ModelBusyException(modelId);
    _deleting.add(modelId);
    notifyListeners();
    try {
      for (final path in [filePath(spec), partPath(spec)]) {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      }
      _installed.remove(modelId);
    } finally {
      _deleting.remove(modelId);
      notifyListeners();
    }
  }
}
