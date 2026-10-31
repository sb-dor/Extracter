import 'dart:io';

import 'package:control/control.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/utils/screen_util.dart';
import 'package:extracter/src/common/utils/transcript_formatters.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/common/widget/segment_row.dart';
import 'package:extracter/src/common/widget/state_widgets.dart';
import 'package:extracter/src/feature/transcript_detail/controller/transcript_detail_controller.dart';
import 'package:extracter/src/feature/transcript_detail/models/transcript_detail.dart';
import 'package:extracter/src/feature/transcript_detail/widgets/transcript_copy_menu.dart';
import 'package:extracter/src/feature/transcript_detail/widgets/transcript_detail_config_widget.dart';
import 'package:extracter/src/feature/transcript_detail/widgets/transcript_meta_chips.dart';
import 'package:extracter/src/feature/transcript_export/widgets/transcript_export_config_widget.dart';
import 'package:flutter/material.dart';

/// Detail pane of History: title, chips, Copy / Save as TXT·SRT·VTT / Delete.
class TranscriptDetailDesktopWidget extends StatefulWidget {
  const TranscriptDetailDesktopWidget({super.key});

  @override
  State<TranscriptDetailDesktopWidget> createState() => _TranscriptDetailDesktopWidgetState();
}

class _TranscriptDetailDesktopWidgetState extends State<TranscriptDetailDesktopWidget> {
  late final _scope = TranscriptDetailConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return StateConsumer<TranscriptDetailController, TranscriptDetailState>(
      controller: _scope.transcriptDetailController,
      builder: (context, state, _) => switch (state) {
        TranscriptDetail$CompletedState(:final transcript) => _Content(transcript: transcript),
        TranscriptDetail$ErrorState(notFound: true) => EmptyStateWidget(icon: Icons.notes, title: l10n.transcriptGone),
        TranscriptDetail$ErrorState() => ErrorStateWidget(message: l10n.transcriptLoadFailed, onRetry: _scope.load),
        _ => const LoadingStateWidget(),
      },
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.transcript});

  final TranscriptDetail transcript;

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final scope = TranscriptDetailConfigInhWidget.of(context);
    final summary = transcript.summary;
    final side = context.screenSize.isTablet ? 24.0 : 40.0;
    return TranscriptExportConfigWidget(
      sourceName: summary.sourceName,
      segments: transcript.segments,
      builder: (context) => CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 28, side, 20),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 16,
                spacing: 16,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10,
                      children: [
                        SelectableText(
                          summary.sourceName,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                        ),
                        TranscriptMetaChips(summary: summary),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TranscriptCopyMenu(transcript: transcript),
                      const _SaveAsGroup(),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.errorBorder),
                        ),
                        onPressed: scope.delete,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: Text(l10n.delete),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 0, side, 48),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: transcript.segments.isEmpty
                      ? Padding(padding: const EdgeInsets.all(24), child: Text(l10n.noSpeechFound))
                      : SelectionArea(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [for (final s in transcript.segments) SegmentRow(segment: s, showRange: true)],
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveAsGroup extends StatelessWidget {
  const _SaveAsGroup();

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final export = TranscriptExportConfigInhWidget.of(context);
    // Android and iOS hand the file to the share sheet instead of a save dialog.
    final share = Platform.isAndroid || Platform.isIOS;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              spacing: 6,
              children: [
                Icon(share ? Icons.ios_share : Icons.download, size: 16, color: AppColors.inkSecondary),
                Text(
                  share ? l10n.shareAs : l10n.saveAs,
                  style: const TextStyle(fontSize: 14, color: AppColors.inkSecondary),
                ),
              ],
            ),
          ),
          for (final format in TranscriptFormat.values)
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: AppColors.border)),
              ),
              // Builder: each button is the share sheet's anchor on iPad.
              child: Builder(
                builder: (context) => TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    shape: const RoundedRectangleBorder(),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => export.export(format, shareOrigin: _originOf(context)),
                  child: Text(format.extension.toUpperCase()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Rect? _originOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }
}
