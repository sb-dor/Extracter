import 'package:control/control.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/utils/transcript_formatters.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/feature/transcript_export/controller/transcript_export_controller.dart';
import 'package:extracter/src/feature/transcript_export/widgets/transcript_export_config_widget.dart';
import 'package:flutter/material.dart';

/// Choose TXT / SRT / VTT; closes itself once the export finishes.
class TranscriptExportFormatDialog extends StatefulWidget {
  const TranscriptExportFormatDialog({super.key});

  @override
  State<TranscriptExportFormatDialog> createState() => _TranscriptExportFormatDialogState();
}

class _TranscriptExportFormatDialogState extends State<TranscriptExportFormatDialog> {
  late final _scope = TranscriptExportConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return StateConsumer<TranscriptExportController, TranscriptExportState>(
      controller: _scope.transcriptExportController,
      builder: (context, state, _) {
        final busy = state is TranscriptExport$InProgressState;
        return PopScope(
          canPop: !busy,
          child: SimpleDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text(l10n.exportAs),
            children: [
              for (final format in TranscriptFormat.values)
                SimpleDialogOption(
                  onPressed: busy ? null : () => _scope.export(format),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(switch (format) {
                      TranscriptFormat.txt => l10n.formatTxt,
                      TranscriptFormat.srt => l10n.formatSrt,
                      TranscriptFormat.vtt => l10n.formatVtt,
                    }),
                  ),
                ),
              if (busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
            ],
          ),
        );
      },
    );
  }
}
