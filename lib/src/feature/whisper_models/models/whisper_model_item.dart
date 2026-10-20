import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:flutter/foundation.dart';

/// A catalogue entry with its state on this device.
@immutable
class WhisperModelItem {
  const WhisperModelItem({
    required this.spec,
    required this.fileState,
    required this.reservations,
    required this.fitsDevice,
  });

  final WhisperModelSpec spec;
  final ModelFileState fileState;

  /// Queued or running jobs holding this model (it cannot be deleted meanwhile).
  final int reservations;

  /// False when this device has less memory than the model needs.
  final bool fitsDevice;

  bool get isInstalled => fileState == ModelFileState.installed;
}

@immutable
class WhisperModelsSnapshot {
  const WhisperModelsSnapshot({required this.items, required this.totalRamBytes, required this.freeDiskBytes});

  final List<WhisperModelItem> items;
  final int? totalRamBytes;
  final int? freeDiskBytes;
}
