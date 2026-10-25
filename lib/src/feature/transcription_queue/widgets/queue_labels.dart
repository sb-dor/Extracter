import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/common/utils/whisper_languages.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_failure.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_model_labels.dart';
import 'package:intl/intl.dart';

/// "Auto-detect", or the language name in the UI language ("Русский" in the Russian UI).
String languageLabel(Localization l10n, String code) {
  if (code == TranscriptionSettings.autoLanguage) return l10n.languageAuto;
  return WhisperLanguage.byCode(code)?.nameIn(Intl.shortLocale(Intl.getCurrentLocale())) ?? code;
}

/// "48:12 · Base · Auto-detect · Translate" / "2:14 · Base · Detected: Russian".
String jobMeta(Localization l10n, QueueJob job) {
  final detected = job.detectedLanguage;
  return [
    if (job.durationMs case final ms?) FormatUtil.duration(ms),
    modelName(l10n, job.settings.modelId),
    if (detected != null)
      l10n.languageDetected(languageLabel(l10n, detected))
    else
      languageLabel(l10n, job.settings.language),
    if (job.settings.translate) l10n.translateShort,
  ].join(' · ');
}

String failureMessage(Localization l10n, TranscriptionFailure failure) => switch (failure) {
  TranscriptionFailure.cancelled => l10n.failureCancelled,
  TranscriptionFailure.openFailed => l10n.failureOpen,
  TranscriptionFailure.decodeFailed => l10n.failureDecode,
  TranscriptionFailure.noAudio => l10n.failureNoAudio,
  TranscriptionFailure.modelFailed => l10n.failureModel,
  TranscriptionFailure.modelMissing => l10n.failureModelMissing,
  TranscriptionFailure.outOfMemory => l10n.failureOutOfMemory,
  TranscriptionFailure.timeout => l10n.failureTimeout,
  TranscriptionFailure.lowStorage => l10n.failureLowStorage,
  TranscriptionFailure.unreadableFile => l10n.failureUnreadable,
  TranscriptionFailure.saveFailed => l10n.failureSave,
  TranscriptionFailure.internal => l10n.failureInternal,
};

/// "About 13 min left" from progress so far, or null when unknown.
String? remainingLabel(Localization l10n, QueueJob job, Duration elapsed) {
  final permille = job.permille;
  if (permille == null || permille < 20 || elapsed.inSeconds < 5) return null;
  final total = elapsed.inMilliseconds * 1000 ~/ permille;
  final minutes = ((total - elapsed.inMilliseconds) / 60000).ceil();
  return minutes <= 1 ? l10n.lessThanMinuteLeft : l10n.minutesLeft(minutes);
}
