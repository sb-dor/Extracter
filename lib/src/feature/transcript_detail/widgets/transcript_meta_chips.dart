import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/common/widget/status_pill.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/queue_labels.dart';
import 'package:extracter/src/feature/transcripts/models/transcript_summary.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_model_labels.dart';
import 'package:flutter/material.dart';

/// Duration · language · model · date chips for a transcript.
class TranscriptMetaChips extends StatelessWidget {
  const TranscriptMetaChips({required this.summary, super.key});

  final TranscriptSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final language = summary.language;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (summary.durationMs case final ms?) MetaChip(FormatUtil.duration(ms)),
        if (language != null)
          MetaChip(
            summary.translated ? l10n.translatedFrom(languageLabel(l10n, language)) : languageLabel(l10n, language),
          ),
        MetaChip(l10n.modelChip(modelName(l10n, summary.modelId))),
        MetaChip(FormatUtil.dateTime(summary.createdAt, locale)),
      ],
    );
  }
}
