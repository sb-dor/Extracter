import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/common/widget/segment_row.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/queue_labels.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/transcription_queue_config_widget.dart';
import 'package:flutter/material.dart';

/// The running job with progress, cancel and its latest two segments.
class NowTranscribingCard extends StatefulWidget {
  const NowTranscribingCard({required this.job, this.since, super.key});

  final QueueJob job;
  final DateTime? since;

  @override
  State<NowTranscribingCard> createState() => _NowTranscribingCardState();
}

class _NowTranscribingCardState extends State<NowTranscribingCard> {
  late final _scope = TranscriptionQueueConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final job = widget.job;
    final cancelling = job.status == QueueJobStatus.cancelling;
    final permille = job.permille;
    final since = widget.since;
    final left = since == null ? null : remainingLabel(l10n, job, DateTime.now().difference(since));
    final status = cancelling
        ? l10n.cancelling
        : [if (permille != null) '${permille ~/ 10}%' else l10n.transcribing, ?left].join(' · ');
    final recent = job.segments.length > 2 ? job.segments.sublist(job.segments.length - 2) : job.segments;
    return Semantics(
      container: true,
      label: l10n.nowTranscribing,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accent, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Row(
                spacing: 10,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.audio_file_outlined, size: 18, color: AppColors.accent),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.sourceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        Text(status, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: l10n.cancelTranscription,
                    onPressed: cancelling ? null : () => _scope.cancel(job.id),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              LinearProgressIndicator(
                value: permille == null ? null : permille / 1000,
                borderRadius: BorderRadius.circular(3),
              ),
              for (final segment in recent) SegmentRow(segment: segment),
            ],
          ),
        ),
      ),
    );
  }
}
