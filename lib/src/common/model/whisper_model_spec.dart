import 'package:flutter/foundation.dart';

/// A downloadable Whisper model, pinned to an immutable Hugging Face revision.
@immutable
class WhisperModelSpec {
  const WhisperModelSpec({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.supportsTranslate,
    required this.minRamGb,
    required this.accuracy,
  });

  static const String revision = '5359861c739e955e79d9a303bcbc70fb988958b1';

  /// Catalogue shown in the app (values from PLAN.md "Pinned inputs").
  static const List<WhisperModelSpec> catalog = [
    WhisperModelSpec(
      id: 'tiny',
      fileName: 'ggml-tiny-q5_1.bin',
      sizeBytes: 32152673,
      sha256: '818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7',
      supportsTranslate: true,
      minRamGb: 0,
      accuracy: 1,
    ),
    WhisperModelSpec(
      id: 'base',
      fileName: 'ggml-base-q5_1.bin',
      sizeBytes: 59707625,
      sha256: '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898',
      supportsTranslate: true,
      minRamGb: 0,
      accuracy: 2,
    ),
    WhisperModelSpec(
      id: 'small',
      fileName: 'ggml-small-q5_1.bin',
      sizeBytes: 190085487,
      sha256: 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
      supportsTranslate: true,
      minRamGb: 4,
      accuracy: 3,
    ),
    WhisperModelSpec(
      id: 'medium',
      fileName: 'ggml-medium-q5_0.bin',
      sizeBytes: 539212467,
      sha256: '19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f',
      supportsTranslate: true,
      minRamGb: 8,
      accuracy: 4,
    ),
    WhisperModelSpec(
      id: 'large-v3-turbo',
      fileName: 'ggml-large-v3-turbo-q5_0.bin',
      sizeBytes: 574041195,
      sha256: '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
      // Turbo returns the original language even when translation is requested.
      supportsTranslate: false,
      minRamGb: 8,
      accuracy: 5,
    ),
  ];

  static WhisperModelSpec? byId(String id) {
    for (final spec in catalog) {
      if (spec.id == id) return spec;
    }
    return null;
  }

  final String id;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final bool supportsTranslate;

  /// Marketed memory size this model needs ("Needs 8 GB memory"); 0 = any.
  final int minRamGb;

  /// 1..5, for the accuracy meter.
  final int accuracy;

  Uri get downloadUri => Uri.parse('https://huggingface.co/ggerganov/whisper.cpp/resolve/$revision/$fileName');

  /// Null [totalRamBytes] (unknown) allows every model.
  /// Devices report less than their marketed size (an "8 GB" phone shows
  /// ~7.4 GB), so the threshold allows 15 % below [minRamGb].
  bool fitsMemory(int? totalRamBytes) => totalRamBytes == null || totalRamBytes >= minRamGb * 850000000;

  @override
  bool operator ==(Object other) => other is WhisperModelSpec && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
