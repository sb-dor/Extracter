import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/common/utils/whisper_language_names.dart';
import 'package:extracter/src/common/utils/whisper_languages.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/queue_labels.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WhisperLanguage names', () {
    test('every Whisper language has a Russian name, and no extras', () {
      final russian = whisperLanguageNames['ru']!;
      final codes = WhisperLanguage.all.map((l) => l.code).toSet();
      expect(russian.keys.toSet(), codes);
      expect(russian.values.every((n) => n.trim().isNotEmpty), isTrue);
      expect(russian.values.toSet(), hasLength(russian.length), reason: 'names are distinct');
    });

    test('nameIn picks the UI language and falls back to English', () {
      final russianLanguage = WhisperLanguage.byCode('ru')!;
      expect(russianLanguage.nameIn('ru'), 'Русский');
      expect(russianLanguage.nameIn('en'), 'Russian');
      expect(WhisperLanguage.byCode('de')!.nameIn('fr'), 'German', reason: 'no French names yet');
    });
  });

  group('languageLabel', () {
    test('follows the loaded UI language', () async {
      final ru = await Localization.load(const Locale('ru'));
      expect(languageLabel(ru, 'en'), 'Английский');
      expect(languageLabel(ru, 'tg'), 'Таджикский');
      expect(languageLabel(ru, TranscriptionSettings.autoLanguage), ru.languageAuto);

      final en = await Localization.load(const Locale('en'));
      expect(languageLabel(en, 'en'), 'English');
      expect(languageLabel(en, 'yue'), 'Cantonese');
    });

    test('unknown codes are shown as they are', () async {
      final en = await Localization.load(const Locale('en'));
      expect(languageLabel(en, 'xx'), 'xx');
    });
  });
}
