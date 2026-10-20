import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:flutter/foundation.dart';

/// The in-memory settings draft the UI edits. Persistence happens in the
/// config widget through the save controller.
class TranscriptionSettingsDataController with ChangeNotifier {
  TranscriptionSettings _draft = const TranscriptionSettings();
  bool _loaded = false;

  TranscriptionSettings get draft => _draft;

  /// False until the persisted settings arrived; edits before that are not saved.
  bool get isLoaded => _loaded;

  void applyLoaded(TranscriptionSettings settings) {
    _loaded = true;
    _set(settings);
  }

  void setModel(String modelId) {
    final spec = WhisperModelSpec.byId(modelId);
    if (spec == null) return;
    // Translation is only offered by models that can do it.
    _set(_draft.copyWith(modelId: modelId, translate: _draft.translate && spec.supportsTranslate));
  }

  void setLanguage(String language) => _set(_draft.copyWith(language: language));

  void setTranslate(bool translate) {
    final spec = WhisperModelSpec.byId(_draft.modelId);
    _set(_draft.copyWith(translate: translate && (spec?.supportsTranslate ?? false)));
  }

  void _set(TranscriptionSettings value) {
    if (value == _draft) return;
    _draft = value;
    notifyListeners();
  }
}
