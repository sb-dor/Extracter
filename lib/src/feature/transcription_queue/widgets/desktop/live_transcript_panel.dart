import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/common/widget/segment_row.dart';
import 'package:extracter/src/common/widget/status_pill.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/queue_labels.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_model_labels.dart';
import 'package:flutter/material.dart';

/// Segments of the running job as they arrive, newest at the bottom.
class LiveTranscriptPanel extends StatefulWidget {
  const LiveTranscriptPanel({required this.job, super.key});

  final QueueJob? job;

  @override
  State<LiveTranscriptPanel> createState() => _LiveTranscriptPanelState();
}

class _LiveTranscriptPanelState extends State<LiveTranscriptPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(LiveTranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow new segments while the user is at the bottom.
    if (widget.job?.segments.length != oldWidget.job?.segments.length && _scroll.hasClients) {
      final atBottom = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 48;
      if (atBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final job = widget.job;
    final running = job?.status == QueueJobStatus.running;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text(
                  l10n.liveTranscript.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.7,
                    color: AppColors.inkMuted,
                  ),
                ),
                if (job != null) ...[
                  Text(job.sourceName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (job.detectedLanguage case final lang?)
                        MetaChip(l10n.languageDetected(languageLabel(l10n, lang))),
                      MetaChip(l10n.modelChip(modelName(l10n, job.settings.modelId))),
                      MetaChip(l10n.segmentsSoFar(job.segments.length)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 460,
            child: job == null || job.segments.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        job == null ? l10n.liveTranscriptEmpty : l10n.listening,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.inkMuted, fontStyle: FontStyle.italic),
                      ),
                    ),
                  )
                : SelectionArea(
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: job.segments.length + (running ? 1 : 0),
                      itemBuilder: (context, i) => i < job.segments.length
                          ? SegmentRow(segment: job.segments[i])
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                l10n.listening,
                                style: const TextStyle(color: AppColors.inkMuted, fontStyle: FontStyle.italic),
                              ),
                            ),
                    ),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              spacing: 8,
              children: [
                const Icon(Icons.light_mode_outlined, size: 16, color: AppColors.inkMuted),
                Expanded(
                  child: Text(l10n.screenStaysAwake, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
