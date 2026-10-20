import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/queue_labels.dart';
import 'package:extracter/src/feature/transcripts/models/transcript_summary.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_model_labels.dart';
import 'package:intl/intl.dart';

bool isToday(DateTime date, DateTime now) => date.year == now.year && date.month == now.month && date.day == now.day;

/// "Today, 14:32" / "Yesterday, 18:05" / "18 Oct".
String relativeDate(Localization l10n, String locale, DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final time = DateFormat.Hm(locale).format(date);
  if (isToday(date, today)) return l10n.todayAt(time);
  if (isToday(date, today.subtract(const Duration(days: 1)))) return l10n.yesterdayAt(time);
  return DateFormat.MMMd(locale).format(date);
}

/// "Today, 14:32 · 2:14 · Russian · Base" (Translate shown as "Spanish → English").
String transcriptMeta(Localization l10n, String locale, TranscriptSummary t, {bool withModel = true}) {
  final language = t.language;
  return [
    relativeDate(l10n, locale, t.createdAt),
    if (t.durationMs case final ms?) FormatUtil.duration(ms),
    if (language != null)
      t.translated ? l10n.translatedFrom(languageLabel(l10n, language)) : languageLabel(l10n, language),
    if (withModel) modelName(l10n, t.modelId),
  ].join(' · ');
}
