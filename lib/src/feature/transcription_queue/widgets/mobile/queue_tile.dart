import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/common/widget/status_pill.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_failure.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/queue_labels.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/transcription_queue_config_widget.dart';
import 'package:flutter/material.dart';

/// A pending or finished job in the phone list.
class QueueTile extends StatefulWidget {
  const QueueTile({required this.job, super.key});

  final QueueJob job;

  @override
  State<QueueTile> createState() => _QueueTileState();
}

class _QueueTileState extends State<QueueTile> {
  late final _scope = TranscriptionQueueConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final job = widget.job;
    final failed = job.status == QueueJobStatus.failed;
    final subtitle = failed ? failureMessage(l10n, job.failure ?? TranscriptionFailure.internal) : jobMeta(l10n, job);
    final trailing = switch (job.status) {
      QueueJobStatus.pending => IconButton(
        tooltip: l10n.removeNamedFromQueue(job.sourceName),
        onPressed: () => _scope.cancel(job.id),
        icon: const Icon(Icons.close, size: 18, color: AppColors.inkSecondary),
      ),
      QueueJobStatus.done => StatusPill(label: l10n.saved, tone: PillTone.accent),
      QueueJobStatus.completedUnsaved => StatusPill(label: l10n.notSaved, tone: PillTone.warning),
      QueueJobStatus.failed => StatusPill(label: l10n.failed, tone: PillTone.error),
      QueueJobStatus.cancelled => StatusPill(label: l10n.cancelled),
      _ => const SizedBox.shrink(),
    };
    final transcriptId = job.transcriptId;
    final tile = Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.sourceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: failed ? AppColors.error : AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              Padding(padding: const EdgeInsets.only(right: 8), child: trailing),
            ],
          ),
          if (job.status == QueueJobStatus.completedUnsaved)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(onPressed: () => _scope.retrySave(job), child: Text(l10n.retrySave)),
                OutlinedButton(onPressed: () => _scope.export(job), child: Text(l10n.exportEllipsis)),
              ],
            ),
        ],
      ),
    );
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: job.status == QueueJobStatus.done && transcriptId != null
          ? InkWell(onTap: () => _scope.openTranscript(transcriptId), child: tile)
          : job.status.isTerminal && job.status != QueueJobStatus.completedUnsaved
          ? Dismissible(key: ValueKey(job.id), onDismissed: (_) => _scope.remove(job.id), child: tile)
          : tile,
    );
  }
}
