import 'package:control/control.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
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

/// Full-screen transcript: copy / delete in the app bar, format + Share at the bottom.
class TranscriptDetailMobileWidget extends StatefulWidget {
  const TranscriptDetailMobileWidget({super.key});

  @override
  State<TranscriptDetailMobileWidget> createState() => _TranscriptDetailMobileWidgetState();
}

class _TranscriptDetailMobileWidgetState extends State<TranscriptDetailMobileWidget> {
  late final _scope = TranscriptDetailConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return StateConsumer<TranscriptDetailController, TranscriptDetailState>(
      controller: _scope.transcriptDetailController,
      builder: (context, state, _) {
        final transcript = state is TranscriptDetail$CompletedState ? state.transcript : null;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            shape: const Border(bottom: BorderSide(color: AppColors.border)),
            title: Text(
              transcript?.summary.sourceName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            actions: [
              if (transcript != null) ...[
                TranscriptCopyMenu(transcript: transcript, compact: true),
                IconButton(
                  tooltip: l10n.deleteTranscript,
                  onPressed: _scope.delete,
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                ),
              ],
            ],
          ),
          body: switch (state) {
            TranscriptDetail$CompletedState(:final transcript) => _Body(transcript: transcript),
            TranscriptDetail$ErrorState(notFound: true) => EmptyStateWidget(
              icon: Icons.notes,
              title: l10n.transcriptGone,
            ),
            TranscriptDetail$ErrorState() => ErrorStateWidget(message: l10n.transcriptLoadFailed, onRetry: _scope.load),
            _ => const LoadingStateWidget(),
          },
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.transcript});

  final TranscriptDetail transcript;

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return TranscriptExportConfigWidget(
      sourceName: transcript.summary.sourceName,
      segments: transcript.segments,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              children: [
                TranscriptMetaChips(summary: transcript.summary),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: transcript.segments.isEmpty
                        ? Padding(padding: const EdgeInsets.all(16), child: Text(l10n.noSpeechFound))
                        : SelectionArea(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final s in transcript.segments)
                                  SegmentRow(segment: s, showRange: true, stacked: true),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const _ExportFooter(),
        ],
      ),
    );
  }
}

class _ExportFooter extends StatefulWidget {
  const _ExportFooter();

  @override
  State<_ExportFooter> createState() => _ExportFooterState();
}

class _ExportFooterState extends State<_ExportFooter> {
  late final _export = TranscriptExportConfigInhWidget.of(context);
  TranscriptFormat _format = TranscriptFormat.txt;
  final GlobalKey _shareKey = GlobalKey();

  Rect? _shareOrigin() {
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              SegmentedButton<TranscriptFormat>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: TranscriptFormat.txt, label: Text(l10n.formatShortTxt)),
                  ButtonSegment(value: TranscriptFormat.srt, label: Text(l10n.formatShortSrt)),
                  ButtonSegment(value: TranscriptFormat.vtt, label: Text(l10n.formatShortVtt)),
                ],
                selected: {_format},
                onSelectionChanged: (s) => setState(() => _format = s.first),
              ),
              FilledButton.icon(
                key: _shareKey,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => _export.export(_format, shareOrigin: _shareOrigin()),
                icon: const Icon(Icons.ios_share, size: 18),
                label: Text(l10n.shareFile(_format.extension)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
