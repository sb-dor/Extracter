import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/feature/transcripts/models/transcript_summary.dart';
import 'package:extracter/src/feature/transcripts/widgets/transcript_row_meta.dart';
import 'package:extracter/src/feature/transcripts/widgets/transcripts_config_widget.dart';
import 'package:extracter/src/feature/transcripts/widgets/transcripts_list.dart';
import 'package:flutter/material.dart';

/// Search + list grouped into Today / Earlier; a tap pushes the transcript.
class TranscriptsMobileWidget extends StatefulWidget {
  const TranscriptsMobileWidget({super.key});

  @override
  State<TranscriptsMobileWidget> createState() => _TranscriptsMobileWidgetState();
}

class _TranscriptsMobileWidgetState extends State<TranscriptsMobileWidget> {
  late final _scope = TranscriptsConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Text(l10n.tabHistory, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
                const TranscriptsSearchField(rounded: true),
              ],
            ),
          ),
          Expanded(
            child: TranscriptsList(
              itemsBuilder: (context, transcripts) {
                final now = DateTime.now();
                final today = transcripts.where((t) => isToday(t.createdAt, now)).toList();
                final earlier = transcripts.where((t) => !isToday(t.createdAt, now)).toList();
                return [
                  if (today.isNotEmpty) ..._group(l10n.today, today, l10n, locale),
                  if (earlier.isNotEmpty) ..._group(l10n.earlier, earlier, l10n, locale),
                ];
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _group(String title, List<TranscriptSummary> rows, Localization l10n, String locale) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
      ),
    ),
    Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, t) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              minTileHeight: 64,
              title: Text(t.sourceName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                transcriptMeta(l10n, locale, t, withModel: false),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right, color: AppColors.inkDisabled),
              onTap: () => _scope.open(t.id),
            ),
          ],
        ],
      ),
    ),
    const SizedBox(height: 8),
  ];
}
