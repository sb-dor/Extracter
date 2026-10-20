import 'package:flutter/foundation.dart';

/// What a new queue job is transcribed with. Each job keeps the snapshot it
/// was enqueued with.
@immutable
class TranscriptionSettings {
  const TranscriptionSettings({this.modelId = 'base', this.language = autoLanguage, this.translate = false});

  static const String autoLanguage = 'auto';

  final String modelId;

  /// `auto` or an ISO-639-1 code.
  final String language;

  /// Translate to English (only for models that support it).
  final bool translate;

  TranscriptionSettings copyWith({String? modelId, String? language, bool? translate}) => TranscriptionSettings(
    modelId: modelId ?? this.modelId,
    language: language ?? this.language,
    translate: translate ?? this.translate,
  );

  @override
  bool operator ==(Object other) =>
      other is TranscriptionSettings &&
      other.modelId == modelId &&
      other.language == language &&
      other.translate == translate;

  @override
  int get hashCode => Object.hash(modelId, language, translate);
}
