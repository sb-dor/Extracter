import 'package:extracter/src/common/constant/preference_keys.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/utils/whisper_languages.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ITranscriptionSettingsRepository {
  Future<TranscriptionSettings> load();
}

final class TranscriptionSettingsRepositoryImpl implements ITranscriptionSettingsRepository {
  TranscriptionSettingsRepositoryImpl({required SharedPreferences sharedPreferences}) : _prefs = sharedPreferences;

  final SharedPreferences _prefs;

  @override
  Future<TranscriptionSettings> load() async {
    const defaults = TranscriptionSettings();
    final modelId = _prefs.getString(PreferenceKeys.settingsModel);
    final language = _prefs.getString(PreferenceKeys.settingsLanguage);
    final model = modelId == null ? null : WhisperModelSpec.byId(modelId);
    final known = language == TranscriptionSettings.autoLanguage || WhisperLanguage.byCode(language ?? '') != null;
    return TranscriptionSettings(
      modelId: model?.id ?? defaults.modelId,
      language: known ? language! : defaults.language,
      translate: (_prefs.getBool(PreferenceKeys.settingsTranslate) ?? false) && (model?.supportsTranslate ?? true),
    );
  }
}
