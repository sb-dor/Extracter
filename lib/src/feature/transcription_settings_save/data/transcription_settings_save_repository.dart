import 'package:extracter/src/common/constant/preference_keys.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ITranscriptionSettingsSaveRepository {
  Future<void> save(TranscriptionSettings settings);
}

final class TranscriptionSettingsSaveRepositoryImpl implements ITranscriptionSettingsSaveRepository {
  TranscriptionSettingsSaveRepositoryImpl({required SharedPreferences sharedPreferences}) : _prefs = sharedPreferences;

  final SharedPreferences _prefs;

  @override
  Future<void> save(TranscriptionSettings settings) async {
    await _prefs.setString(PreferenceKeys.settingsModel, settings.modelId);
    await _prefs.setString(PreferenceKeys.settingsLanguage, settings.language);
    await _prefs.setBool(PreferenceKeys.settingsTranslate, settings.translate);
  }
}
