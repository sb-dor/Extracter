import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/utils/screen_util.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/common/widget/state_widgets.dart';
import 'package:extracter/src/feature/transcript_detail/widgets/transcript_detail_config_widget.dart';
import 'package:extracter/src/feature/transcripts/widgets/transcript_row_meta.dart';
import 'package:extracter/src/feature/transcripts/widgets/transcripts_config_widget.dart';
import 'package:extracter/src/feature/transcripts/widgets/transcripts_list.dart';
import 'package:flutter/material.dart';

/// Master (list) + detail side by side.
class TranscriptsDesktopWidget extends StatefulWidget {
  const TranscriptsDesktopWidget({super.key});

  @override
  State<TranscriptsDesktopWidget> createState() => _TranscriptsDesktopWidgetState();
}

class _TranscriptsDesktopWidgetState extends State<TranscriptsDesktopWidget> {
  late final _scope = TranscriptsConfigInhWidget.of(context);
  late final _data = _scope.transcriptsDataController;

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: context.screenSize.isTablet ? 340 : 400,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(right: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 14,
                  children: [
                    Text(l10n.tabHistory, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                    const TranscriptsSearchField(),
                  ],
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _data,
                  builder: (context, _) => TranscriptsList(
                    itemsBuilder: (context, transcripts) => [
                      for (final t in transcripts)
                        _Row(
                          title: t.sourceName,
                          meta: transcriptMeta(l10n, locale, t),
                          selected: t.id == _data.selectedId,
                          onTap: () => _scope.open(t.id),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _data,
            builder: (context, _) {
              final id = _data.selectedId;
              if (id == null) {
                return EmptyStateWidget(icon: Icons.notes, title: l10n.selectTranscript);
              }
              return TranscriptDetailConfigWidget(
                key: ValueKey(id),
                transcriptId: id,
                onDeleted: () => _data.select(null),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.meta, required this.selected, required this.onTap});

  final String title;
  final String meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Material(
      color: selected ? AppColors.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
              ),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: selected ? AppColors.inkSecondary : AppColors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
